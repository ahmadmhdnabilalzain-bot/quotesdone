-- RECONCILING scripts/sql WITH PRODUCTION. THE FILES WERE STALE, NOT THE DATABASE.
--
-- scripts/checks/sql_files_match_live.test.mjs has reported drift for weeks and its own output says
-- what that means: "present but DRIFTED from the newest file". 8 routines had a live definition
-- that differed from the newest file claiming to define them, and the check pinned the count so it
-- could not grow. It was never reconciled, so the hazard stayed live: applying one of those files
-- would have silently REVERTED the production version.
--
-- CHECKED THE DIRECTION BEFORE ASSUMING IT. fn_term_matches, live:
--
--     then p_text_norm ~ ('...(وال|بال|فال|كال|ال|لل|و|ف|ب|ك|ل)?'
--                         || replace(p_pattern_norm, ' ', '[[:space:]]+(ال)?')   <-- multi-word Arabic
--                         || '(ات|ين|ون|ها|هم|ه)?($|[^[:alnum:]])')
--     else p_text_norm ~ ('(^|[^[:alnum:]])' || p_pattern_norm || '(es|s)?($|...)')  <-- plurals
--
-- and the same function in scripts/sql/stage_b6_rollback_completion.sql has NEITHER the multi-word
-- Arabic handling nor the English plural. Applying that file would have broken Arabic term matching
-- on a UAE marketplace. LIVE IS NEWER AND BETTER; the files are stale.
--
-- So this file captures the live definition of all eight verbatim and becomes the newest file for
-- each. APPLYING IT IS A NO-OP by construction - it is what production already runs - and its only
-- effect is that scripts/sql now describes the database that exists. Drift 8 -> 0.
--
-- The eight, and the stale file each was drifting from:
--   fn_agent_action_resolve_addressee  agent_action_addressee_resolution.sql
--   fn_kb_route_decide                 pack_artefacts_get_readers.sql
--   fn_ai_quality_watch                event_emitters_five_missing_classes.sql
--   fn_evolution_scan                  fn_evolution_scan_prompting_domain.sql
--   fn_decide                          escalation_names_a_party.sql
--   fn_event_consolidate               bus_contract_close.sql
--   fn_term_matches                    stage_b6_rollback_completion.sql
--   fn_group_dispatch_report           stage_b6_rollback_completion.sql
--
-- Generated from pg_get_functiondef against production, not retyped.

-- fn_agent_action_resolve_addressee
CREATE OR REPLACE FUNCTION public.fn_agent_action_resolve_addressee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_key text;
begin
  if new.agent is null or new.agent = '' then
    new.agent := 'brief';
    new.escalated := true;
    new.escalation_reason := coalesce(new.escalation_reason, 'written with no addressee at all');
    return new;
  end if;

  if exists (select 1 from public.org_agents o where o.agent_key = new.agent and o.active) then
    return new;
  end if;

  v_key := public.fn_org_agent_resolve(new.agent);

  if v_key is null then
    new.detail := coalesce(new.detail, '{}'::jsonb)
                  || jsonb_build_object('addressed_as', new.agent, 'addressee_unresolved', true);
    new.escalated := true;
    new.escalation_reason := coalesce(new.escalation_reason,
      'addressee "' || new.agent || '" is not an employee and no org_agent_alias maps it');
    new.agent := 'brief';
    return new;
  end if;

  new.detail := coalesce(new.detail, '{}'::jsonb) || jsonb_build_object('addressed_as', new.agent);
  new.agent := v_key;
  return new;
end $function$;

-- fn_kb_route_decide
CREATE OR REPLACE FUNCTION public.fn_kb_route_decide(p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v jsonb; top numeric; second numeric; n int; v_action text; v_conf numeric; v_reason text;
  v_cat int; v_rules jsonb; v_dropped int := 0;
begin
  -- deactivated routes are removed BEFORE scoring, so a blocked route cannot win, tie, or make
  -- the decision look ambiguous
  select coalesce(jsonb_agg(to_jsonb(r) order by r.score desc), '[]'::jsonb) into v
  from (select * from public.fn_kb_route(p_text, 5)) r
  where not coalesce((public.fn_kb_route_activation_blocked(r.catalog_num)->>'blocked')::boolean, true);

  select count(*) into v_dropped
  from (select * from public.fn_kb_route(p_text, 5)) r
  where coalesce((public.fn_kb_route_activation_blocked(r.catalog_num)->>'blocked')::boolean, true);

  n := jsonb_array_length(v);
  if n = 0 then
    return jsonb_build_object(
      'action', 'ask_clarifying_question', 'confidence', 0, 'top_score', 0,
      'candidates', '[]'::jsonb, 'catalog_num', null, 'multi_category', false,
      'reason', case when v_dropped > 0
                     then format('%s matching route(s) are not activated for live use', v_dropped)
                     else 'no deterministic alias matched the customer wording' end,
      'clarification', 'Could you tell me in your own words what you need supplied or done? For example "waterproof a warehouse roof" or "supply 200 office chairs".',
      'rules', '[]'::jsonb, 'deactivated_candidates', v_dropped,
      'normalised', public.kb_norm(p_text));
  end if;

  top    := (v->0->>'score')::numeric;
  second := case when n > 1 then (v->1->>'score')::numeric else 0 end;
  v_conf := round(top / nullif(top + second, 0), 3);

  if top < 3 then
    v_action := 'ask_clarifying_question';
    v_reason := 'only a weak fragment matched; not enough to act on';
  elsif n = 1 or top >= second * 1.5 then
    v_action := 'route_or_ask_scope_details';
    v_reason := case when n = 1 then 'single deterministic alias match'
                     else 'leading route is decisively ahead of the runner-up' end;
  else
    v_action := 'ask_clarifying_question';
    v_reason := 'leading routes are too close to call';
  end if;

  v_cat := case when v_action = 'route_or_ask_scope_details' then (v->0->>'catalog_num')::int end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'rule_id', d.rule_id, 'type', d.rule_type, 'priority', d.priority,
           'when', d.when_json, 'then', d.then_json,
           'requires_human_review', d.requires_human_review,
           'confidence', d.confidence) order by d.priority desc nulls last, d.rule_id), '[]'::jsonb)
    into v_rules
    from (select * from kb_stage.decision_rules dr
           where v_cat is not null
             and dr.category_slug in (select m.package_slug from public.kb_operational_route_map m
                                       where m.catalog_num = v_cat)
           order by dr.priority desc nulls last, dr.rule_id
           limit 5) d;

  return jsonb_build_object(
    'action', v_action,
    'confidence', v_conf,
    'top_score', top,
    'candidates', v,
    'catalog_num', v_cat,
    'multi_category', (n > 1 and second >= top * 0.75),
    'reason', v_reason,
    'clarification', case when v_action = 'ask_clarifying_question' then
        'Just so this reaches the right suppliers - is this closer to "' || (v->0->>'live_name') ||
        '" or "' || coalesce(v->1->>'live_name', 'something else') || '"?' end,
    'rules', coalesce(v_rules, '[]'::jsonb),
    'deactivated_candidates', v_dropped,
    'normalised', public.kb_norm(p_text));
end $function$;

-- fn_ai_quality_watch
CREATE OR REPLACE FUNCTION public.fn_ai_quality_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_regs int:=0; v_spikes int:=0; v_detail jsonb; v_open int; v_owner text; v_t0 timestamptz := now();
begin
  insert into public.ai_quality_snapshots(agent,override_pct,actions_30d)
    select agent, override_pct, actions_30d from public.v_ai_agent_health where override_pct is not null;

  with ranked as (
    select prompt_key, score, created_at,
           row_number() over(partition by prompt_key order by created_at desc) rn
    from public.prompt_eval_runs
  ),
  reg as (
    select c.prompt_key, c.score cur, p.score prev
    from ranked c join ranked p on p.prompt_key=c.prompt_key and p.rn=2
    where c.rn=1 and (c.score < p.score - 5 or c.score < 70)
  ),
  ins as (
    insert into public.security_events(kind,severity,source,subject,detail)
    select 'eval_regression', case when cur<70 then 'high' else 'medium' end, 'ai_quality_watch', prompt_key,
           jsonb_build_object('current',cur,'previous',prev)
    from reg returning 1
  )
  select count(*) into v_regs from ins;

  with cur as (
    select agent, override_pct, actions_30d from public.v_ai_agent_health
    where override_pct is not null and actions_30d>=5 and agent not in ('security','onboarding','email')
  ),
  hist as (
    select agent, avg(override_pct) avg_prev, count(*) n
    from public.ai_quality_snapshots where at < now()-interval '12 hours' group by agent
  ),
  spike as (
    select c.agent, c.override_pct, round(h.avg_prev,1) avg_prev
    from cur c join hist h on h.agent=c.agent
    where h.n>=1 and c.override_pct > coalesce(h.avg_prev,0)+20
  ),
  ins2 as (
    insert into public.security_events(kind,severity,source,subject,detail)
    select 'override_spike','medium','ai_quality_watch', agent,
           jsonb_build_object('override_pct',override_pct,'trailing_avg',avg_prev)
    from spike returning 1
  )
  select count(*) into v_spikes from ins2;

  v_detail := jsonb_build_object('eval_regressions',v_regs,'override_spikes',v_spikes);

  -- Added 10 Aug 2026: this routine has detected quality falling since it was written and never
  -- emitted an event, so nothing downstream could react to it.
  if v_regs + v_spikes > 0 then
    perform fn_emit('ai.confidence_dropped',
                    case when se.kind='eval_regression' then 'prompt' else 'agent' end,
                    se.subject, 'ai_quality_watch',
                    se.detail || jsonb_build_object('finding', se.kind, 'severity', se.severity))
       from public.security_events se
      where se.source='ai_quality_watch' and se.kind in ('eval_regression','override_spike')
        and se.created_at >= v_t0;
  end if;

  if v_regs+v_spikes > 0 then
    select count(*) into v_open from public.agent_actions
      where kind='ai_quality_alert' and coalesce(status,'') in ('pending','needs_review')
        and created_at > now()-interval '24 hours';
    if v_open = 0 then
      insert into public.agent_actions(agent,kind,status,risk,title,recommendation,target_table,detail)
      values('ai_trainer','ai_quality_alert','pending','medium',
        'AI quality alert: '||v_regs||' eval regression(s), '||v_spikes||' override spike(s)',
        'Open the AI Observability dashboard and review security_events of kind eval_regression / override_spike. Consider rolling back the regressed prompt version, or investigating why a human-facing agent''s suggestions are being rejected.',
        'security_events', v_detail);
      select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner
        from public.app_secrets where key='admin_emails';
      insert into public.notifications(type,to_email,to_role,channel,subject,body,status)
      values('ai_quality_alert', v_owner,'admin','email','QuotesDone: AI quality alert',
        'The AI quality watch flagged '||v_regs||' eval regression(s) and '||v_spikes||' override spike(s). Open the AI Observability dashboard and check security_events (kind eval_regression / override_spike).','queued');
    end if;
  end if;
  return v_detail;
end $function$;

-- fn_evolution_scan
-- ROUTINE REMOVED 7 September 2026. public.fn_evolution_scan was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- fn_decide
CREATE OR REPLACE FUNCTION public.fn_decide(p_kind text, p_ctx jsonb, p_actor text DEFAULT 'agent'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  res jsonb; conf numeric; reasons jsonb := '[]'::jsonb; route text; decision text;
  sources jsonb := '[]'::jsonb;
  v_alt text; v_alt_why text; v_alt_score numeric;
  v_ctx jsonb := coalesce(p_ctx, '{}'::jsonb);
  v_q text; v_cands text[]; v_hits jsonb := '[]'::jsonb; v_evidence jsonb;
  v_options jsonb; v_amount numeric; v_dept text;
  v_problem text; v_imp_bus text; v_imp_fin text; v_imp_leg text; v_imp_cus text;
  v_escalates boolean; v_status text; v_approver text; v_authorised boolean;
  v_dr_id bigint; v_dr_status text; v_verdict text; v_gate_reason text;
  v_corr uuid; v_trace uuid; v_prior jsonb;
begin
  begin v_amount := nullif(coalesce(v_ctx->>'amount_aed', v_ctx->>'amount'), '')::numeric;
  exception when others then v_amount := null; end;
  v_dept := nullif(v_ctx->>'dept_key', '');

  if p_kind='escalate' then
    -- p_actor goes IN. Without it the router has no line to send the escalation up and answers
    -- every caller with the same company-wide owner; see fn_should_escalate's reporting-line rung.
    res := public.fn_should_escalate(v_ctx || jsonb_build_object('actor', p_actor));
    decision := case when (res->>'escalate')::boolean then 'escalate' else 'proceed' end;
    reasons := res->'reasons'; route := res->>'route_to';
    conf := case when (res->>'escalate')::boolean then 0.9 else 0.8 end;
    -- WHY THIS PARTY, NOT JUST WHICH. 'decision_policy' was a label naming a table; the router's
    -- own verdict — route_basis, route_note and the reasons it fired on — is the retrieval this
    -- decision was actually taken on, and it is what makes the routing auditable after the fact.
    sources := to_jsonb(array['decision_policy'])
      || jsonb_build_array(jsonb_build_object('kind','policy_check','ref','fn_should_escalate','result',res));
    v_alt := case when decision='escalate' then 'proceed' else 'escalate' end;
    v_alt_why := 'the opposite verdict from fn_should_escalate on the same context';

  elsif p_kind='price' then
    res := public.fn_price_confidence(coalesce(v_ctx->>'category','default'), nullif(v_ctx->>'amount_aed','')::numeric);
    decision := 'priced'; conf := coalesce((res->>'confidence')::numeric, 0.5);
    reasons := jsonb_build_array(coalesce(res->>'band', 'price band computed')); sources := to_jsonb(array['price_confidence']);
    route := null;   -- a price band hands off to nobody; 'none' was a name that named nobody
    v_alt := 'quote_manually'; v_alt_why := 'refer the price to a human estimator instead of the band';

  elsif p_kind='route_category' then
    route := public.fn_resolve_cat_agent(coalesce(v_ctx->>'category',''));
    decision := coalesce(route,'unmatched'); conf := case when route is null then 0.3 else 0.85 end;
    reasons := jsonb_build_array('mapped category "'||coalesce(v_ctx->>'category','')||'" to agent '||coalesce(route,'(none)'));
    sources := to_jsonb(array['category_agents']);
    v_alt := 'Secretary'; v_alt_why := 'the unrouted-work fallback, which is slower but never drops the item';

  elsif p_kind='invite' then
    -- rank approved suppliers for a category (+ optional emirate)
    with pool as (
      select id, company_name, coalesce(capability_score,0) cap, coalesce(app_rating,rating,0) rat, coalesce(rv_response_rate,0) resp
      from leads
      where coalesce(approval_status,'')='approved'
        and (coalesce(v_ctx->>'category','')='' or lower(coalesce(categories,''))||' '||lower(coalesce(sub_type,'')) like '%'||lower(v_ctx->>'category')||'%')
        and (coalesce(v_ctx->>'emirate','')='' or coalesce(v_ctx->>'emirate')= any(coalesce(service_emirates,array[emirate])))
      order by (coalesce(capability_score,0)*0.5 + coalesce(app_rating,rating,0)*8 + coalesce(rv_response_rate,0)*0.3) desc
      limit coalesce((v_ctx->>'n')::int, 5))
    select jsonb_agg(jsonb_build_object('id',id,'name',company_name,'cap',cap,'rating',rat,'response',resp)) into res from pool;
    decision := 'invite_ranked'; conf := case when res is null then 0.2 when jsonb_array_length(res)>=3 then 0.8 else 0.5 end;
    reasons := jsonb_build_array('ranked by capability_score, rating and response rate');
    sources := to_jsonb(array['leads','supplier_capability','response_rate']);
    res := jsonb_build_object('suppliers', coalesce(res,'[]'));
    v_alt := 'broadcast_to_all_approved';
    v_alt_why := 'invite every approved supplier instead of the ranked shortlist — more coverage, worse response rate';

  elsif p_kind='approve' then
    res := public.fn_should_escalate(v_ctx || jsonb_build_object('actor', p_actor));
    if (res->>'escalate')::boolean then decision:='human_review'; conf:=0.9; reasons:=res->'reasons';
    else decision:='auto_approve'; conf:=0.85; reasons:=jsonb_build_array('within autonomous thresholds'); end if;
    route := res->>'route_to';
    sources := to_jsonb(array['decision_policy'])
      || jsonb_build_array(jsonb_build_object('kind','policy_check','ref','fn_should_escalate','result',res));
    v_alt := case when decision='human_review' then 'auto_approve' else 'human_review' end;
    v_alt_why := 'the opposite side of the autonomous threshold in decision_policy';

  else
    decision := 'unsupported_kind'; conf := 0; reasons := jsonb_build_array('no handler for kind '||p_kind); route:='Secretary';
    v_alt := 'add_a_handler'; v_alt_why := 'teach fn_decide this kind rather than routing it to a person every time';
  end if;

  -- ROUTE_TO NAMES A PARTY, OR IT NAMES NOBODY AND IS NULL.
  --
  -- MEASURED DEFECT, production, 6 Aug 2026: every routed decision this engine has ever written
  -- names something the org model does not contain. route_category wrote 'cat:signage' (9 rows) —
  -- a knowledge persona in category_agents, not an employee; price wrote the literal string
  -- 'none'; the unsupported-kind branch wrote 'Secretary', which matches no agent_key, no title
  -- and no dept_key across all 67 employees. The requirement is "Should I escalate? routes to a
  -- NAMED PARTY", and a column that is merely non-null answers it with a string.
  --
  -- The ladder resolves whatever the branch above chose, and it invents nobody: each rung returns
  -- a party the org model already contains, and if none does, the value is whatever
  -- fn_should_escalate itself answers — so a configuration gap stays visible as an unresolvable
  -- route rather than being papered over here.
  --   1. the name is already an active employee or a staffed department -> keep it
  --   2. 'cat:x' is a knowledge persona; the party is 'x' if 'x' is one  -> cat:it -> it
  --   3. the deciding actor's own department, if staffed — the work stays where it arose
  --   4. the escalation resolver's answer, which is the same one every other kind gets
  -- A decision that hands off to nobody carries NULL, which is what `invite` already did. The
  -- category agent itself is not lost: it is already the value of `decision` and is quoted in
  -- `reasons`, which is where "which persona holds this knowledge" belongs.
  route := nullif(btrim(coalesce(route, '')), '');
  if route in ('none', 'unmatched') then route := null; end if;
  if route is not null then
    route := coalesce(
      public.fn_route_party(route),
      public.fn_route_party(regexp_replace(route, '^cat:', '')),
      public.fn_route_party((select a.department from public.org_agents a
                              where a.agent_key = p_actor and a.active limit 1)),
      public.fn_should_escalate(jsonb_build_object('actor', p_actor)) ->> 'route_to');
  end if;

  -- STEP 3, KNOWLEDGE RETRIEVAL. fn_memory_search had zero callers, which is the whole defect:
  -- the engine decided without consulting anything the company already knew.
  --
  -- NARROW FIRST, THEN WIDER. fn_memory_search builds its query with plainto_tsquery, which ANDs
  -- every lexeme, so handing it a whole sentence retrieves NOTHING: 'Which agent owns Printing /
  -- Packaging / Signage work when an RFQ arrives' returned 0 hits on production while 'signage'
  -- returned 5. The candidates are therefore tried shortest-first and the first one that retrieves
  -- wins. A failed search must not lose the decision, so it degrades to "searched, no hits".
  v_cands := array_remove(array[
      nullif(btrim(coalesce(v_ctx->>'category','')), ''),
      nullif(array_to_string((regexp_split_to_array(
        btrim(coalesce(v_ctx->>'question', v_ctx->>'problem','')), '\s+'))[1:4], ' '), ''),
      nullif(btrim(coalesce(v_ctx->>'question', v_ctx->>'problem','')), ''),
      p_kind], null);

  foreach v_q in array v_cands loop
    begin
      select coalesce(jsonb_agg(jsonb_build_object(
               'kind', m.kind, 'ref', m.ref, 'snippet', left(m.snippet, 180),
               'score', round(m.score::numeric, 4))), '[]'::jsonb)
        into v_hits
        from public.fn_memory_search(v_q, null::text[], 5) m;
    exception when others then v_hits := '[]'::jsonb; end;
    exit when jsonb_array_length(v_hits) > 0;
  end loop;

  sources := sources || jsonb_build_array(jsonb_build_object(
               'kind', 'memory_search', 'q', v_q, 'hits', jsonb_array_length(v_hits))) || v_hits;

  -- HOW THE LAST DECISIONS OF THIS KIND TURNED OUT. decision_trace.outcome_status was written by
  -- fn_execution_sweep and read by nobody; it is retrieved here, recorded as a source, and it
  -- BITES: a kind whose executions have failed more often than they succeeded loses the confidence
  -- it needs to be taken autonomously and escalates instead. That is the difference between a
  -- measured outcome and a stored one.
  v_prior := public.fn_decision_outcomes(p_kind, 90);
  sources := sources || jsonb_build_array(jsonb_build_object(
               'kind', 'prior_outcomes', 'ref', 'decision_trace', 'result', v_prior));
  if coalesce((v_prior->>'graded')::int, 0) >= 3
     and coalesce((v_prior->>'failed')::int, 0) > coalesce((v_prior->>'succeeded')::int, 0) then
    conf := least(conf, 0.65);
    reasons := coalesce(reasons,'[]'::jsonb) || jsonb_build_array(format(
      'the last %s graded %s decisions went %s failed against %s succeeded, so this one is not taken autonomously',
      v_prior->>'graded', p_kind, v_prior->>'failed', v_prior->>'succeeded'));
  end if;

  v_evidence := sources;

  -- STEP 6. Two scored alternatives, always. One "option" is a conclusion, not a choice.
  v_options := jsonb_build_array(
    jsonb_build_object('option', decision, 'score', conf, 'selected', true, 'rationale', reasons),
    jsonb_build_object('option', coalesce(v_alt,'no_action'),
                       'score', coalesce(v_alt_score, round(1 - conf, 2)), 'selected', false,
                       'rationale', jsonb_build_array(coalesce(v_alt_why, 'the alternative the engine scored lower'))));

  -- STEP 1 and STEP 4. The problem in words, and the four impacts derived from what was computed.
  v_problem := format('Decision requested (%s) by %s: %s', p_kind, p_actor,
                 left(coalesce(nullif(btrim(concat_ws(' ', nullif(v_ctx->>'question',''), nullif(v_ctx->>'problem',''))), ''),
                               v_ctx::text), 400));
  v_imp_bus := format('Business: the engine selected "%s" over "%s" for %s. %s',
                 decision, coalesce(v_alt,'no_action'), p_actor, coalesce(v_alt_why,''));
  v_imp_fin := case when coalesce(v_amount,0) > 0
                 then format('Financial: AED %s is committed by this decision and is checked against %s spend authority before the gate lets it through.',
                             v_amount, coalesce(v_dept,'company'))
                 else format('Financial: no money moves. A %s decision consumes no spend authority and financial_aed stays null.', p_kind) end;
  v_imp_leg := case when p_kind in ('price','approve','invite')
                 then format('Legal: %s decisions are visible to a counterparty, so the record is retained for audit and PDPL subject access.', p_kind)
                 else format('Legal: internal routing only; a %s decision creates no counterparty obligation.', p_kind) end;
  v_imp_cus := case when coalesce(route,'none') in ('none','')
                 then format('Customer: no customer-facing step changes; the %s decision stays inside the operating system.', p_kind)
                 else format('Customer: the work moves to %s, which sets who answers the customer next and how quickly.', route) end;

  -- STEP 7. Whether this is the engine's to take. Escalating decisions stay 'proposed' and never
  -- reach the gate; autonomous ones are written as 'approved' so trg_decision_gate must inspect
  -- them, and it is free to refuse — 'blocked_by_gate' coming back out is a working gate, not a bug.
  --
  -- THE ACTOR MUST HAVE AUTHORITY ON FILE. This is now belt AND braces: fn_decision_gate consults
  -- the register itself for every writer (scripts/sql/fn_decision_gate_authority_register.sql), and
  -- the engine declines to even propose an autonomous decision for an actor it cannot find there —
  -- an escalation is a better answer than a refusal for something the engine could see coming.
  -- 'founder' is the one identity the gate treats as top authority without an employee_authority
  -- row, so it resolves here too; every other actor must be on the list.
  v_authorised := p_actor = 'founder'
                  or exists (select 1 from public.employee_authority ea where ea.agent_key = p_actor);
  if not v_authorised then
    reasons := coalesce(reasons,'[]'::jsonb) || jsonb_build_array(
      format('%s has no employee_authority record, so this decision is escalated rather than taken autonomously', p_actor));
  end if;

  v_escalates := decision in ('escalate','human_review','unsupported_kind')
                 or conf < 0.7
                 or jsonb_array_length(v_evidence) = 0
                 or not v_authorised;
  v_status   := case when v_escalates then 'proposed' else 'approved' end;
  v_approver := case when v_escalates then null else p_actor end;

  insert into public.decision_record(
      decided_by, dept_key, problem, context, options, risks, benefits, recommendation,
      confidence, expected_outcome, rollback_plan, approved_by, status,
      impact_business, impact_financial, financial_aed, impact_legal, impact_customer,
      evidence, reversible)
  values (
      p_actor, v_dept, v_problem, left(v_ctx::text, 2000), v_options,
      format('Risk: if "%s" is the wrong call, %s. Scored %s against %s for the alternative.',
             decision, coalesce(v_alt_why,'the rejected alternative was the better one'),
             conf, coalesce(v_alt_score, round(1 - conf, 2))),
      format('Benefit: the %s step is taken now instead of waiting for a person, on %s retrieved reference(s).',
             p_kind, jsonb_array_length(v_hits)),
      -- recommendation is the ONE decision_record field fn_agent_context actually emits to an
      -- employee ('# DECISIONS ALREADY ON RECORD FOR YOUR DEPARTMENT', left(...,150)). The step-3
      -- retrieval was landing on evidence, which travels nowhere, so the count of references the
      -- engine consulted is carried here instead of being computed and thrown away.
      format('%s (confidence %s, route %s, %s reference(s) retrieved)',
             decision, conf, coalesce(route,'none'), jsonb_array_length(v_hits)),
      conf,
      format('Expected: %s is carried out and the outcome recorded against decision_record.', decision),
      case when v_escalates then 'Rollback: nothing executed; the decision sits at proposed until a human takes it.'
           else format('Rollback: set status back to proposed and re-run fn_decide(%L, ...) with corrected context.', p_kind) end,
      v_approver, v_status,
      v_imp_bus, v_imp_fin, v_amount, v_imp_leg, v_imp_cus,
      v_evidence, coalesce(v_amount,0) = 0)
  returning id, status, gate_verdict, gate_reason
       into v_dr_id, v_dr_status, v_verdict, v_gate_reason;

  insert into public.decision_log(actor,kind,ctx,decision,confidence,reasons,sources,route_to)
  values (p_actor,p_kind,v_ctx,decision,conf,reasons,sources,route);

  -- STEP 9. Execution linked BACK to the decision. One correlation_id ties the trace to the
  -- action, and the action carries the decision_record id it came from, so
  -- v_executions_without_decision_trace stays empty for anything this engine produced.
  -- The row is written 'queued' and public.fn_execution_run (cron execution_run_hourly) performs
  -- it: it delivers the decision to the actor the decision named and settles the row against the
  -- artefact it created. Claiming 'succeeded' here would be claiming an outcome before the act.
  if v_verdict = 'passed' then
    begin v_corr := nullif(current_setting('app.correlation_id', true), '')::uuid;
    exception when others then v_corr := null; end;
    v_corr := coalesce(v_corr, gen_random_uuid());

    insert into public.decision_trace(
        correlation_id, entity_type, entity_id, decision_type, proposed_by, decided_by,
        policy_keys, knowledge_refs, evidence_refs, alternatives, assumptions, risk,
        confidence, authority_result, decision)
    values (v_corr, 'decision_record', v_dr_id::text, p_kind, p_actor, coalesce(v_approver, p_actor),
        array['decision_policy'], v_hits, v_evidence, v_options,
        jsonb_build_array(format('context supplied by %s is current', p_actor)),
        jsonb_build_object('escalated', v_escalates, 'route_to', route, 'financial_aed', v_amount),
        conf,
        jsonb_build_object('gate_verdict', v_verdict, 'approved_by', v_approver, 'status', v_dr_status),
        jsonb_build_object('kind', p_kind, 'decision', decision, 'decision_record_id', v_dr_id,
                           'confidence', conf))
    returning id into v_trace;

    insert into public.action_execution(
        correlation_id, action_class, executor, idempotency_key, risk_tier, reversible, request, status)
    values (v_corr, 'decision.'||p_kind, p_actor, 'decision_record:'||v_dr_id::text,
        case when coalesce(v_amount,0) >= 1000 then 'high'
             when coalesce(v_amount,0) > 0 then 'medium' else 'low' end,
        coalesce(v_amount,0) = 0,
        jsonb_build_object('decision_record_id', v_dr_id, 'decision_trace_id', v_trace,
                           'kind', p_kind, 'decision', decision, 'route_to', route, 'ctx', v_ctx),
        'queued');
  end if;


  -- BOARD BEFORE A MAJOR DECISION (spec #3 s24). Every active advisor gives an independent opinion
  -- on the problem this decision answers, keyed to the decision_record by id -- so the link is a
  -- foreign key and not the text match the scorer had to fall back on when subject_ref was null on
  -- all 28 rows. fn_challenge underneath is pure SQL, so this costs no model call.
  -- Guarded twice: only when a record was actually written, and an advisor that throws must not
  -- lose the decision it was advising on. The failure is raised as a warning rather than swallowed.
  if v_dr_id is not null then
    begin
      perform public.fn_board_review(
        coalesce((select d.problem from public.decision_record d where d.id = v_dr_id), p_kind),
        v_dr_id::text);
    exception when others then
      raise warning 'fn_board_review failed for decision_record % : %', v_dr_id, sqlerrm;
    end;
  end if;

  return jsonb_build_object('kind',p_kind,'decision',decision,'confidence',conf,'reasons',reasons,
                            'route_to',route,'sources',sources,'detail',res,
                            'decision_record_id',v_dr_id,'status',v_dr_status,
                            'gate_verdict',v_verdict,'gate_reason',v_gate_reason,
                            'options',v_options,'knowledge_hits',jsonb_array_length(v_hits),
                            'prior_outcomes',v_prior);
end $function$;

-- fn_event_consolidate
CREATE OR REPLACE FUNCTION public.fn_event_consolidate()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record; v_outcome text; v_note text; v_backbone text; v_lesson bigint; v_sev text;
  n_closed int := 0; n_lessons int := 0; n_rollups int := 0; n_priorities int := 0;
  v_open_chains bigint := 0;
  -- Bounded like the dispatcher's batch, for the same reason: an unbounded first run on a backlog
  -- is how a burst happens.  The work is finite and the cron is hourly.
  c_max_close    constant int := 200;
  c_max_priority constant int := 25;
begin
  -- ── LINK 7 · the result comes back to the event that caused the work ────────────────────────
  -- A delivery whose task has closed but whose result column is still NULL is precisely the gap:
  -- the OS did the work and the event never heard.  org_tasks.result is the OS's own words; the
  -- status is the fallback when it closed without writing one.
  for r in
    select d.id as delivery_id, d.event_id, d.task_id, d.os_key,
           t.status, t.result, t.title, t.updated_at, e.correlation_id, e.event_type
      from event_delivery d
      join org_tasks t     on t.id = d.task_id
      join company_event e on e.id = d.event_id
     where d.closed_at is null and t.status in ('done','closed')
     order by d.id
     limit c_max_close
  loop
    update event_delivery
       -- ->> not nullif(...,''): org_tasks.result is jsonb and event_delivery.result is text.
       set result    = left(coalesce(nullif(r.result->>'summary',''),
                                     r.status || ': ' || coalesce(r.title,'')), 1000),
           closed_at = coalesce(r.updated_at, now())
     where id = r.delivery_id;
    n_closed := n_closed + 1;

    -- ── LINK 10 · Knowledge captures the lesson from an EVENT outcome ─────────────────────────
    -- Joined through event_delivery.task_id, which is what makes the lesson traceable to a
    -- dispatched event rather than to a task that arrived some other way.
    if not exists (select 1 from institutional_memory m
                    where m.subject_type = 'org_task' and m.subject_id = r.task_id::text) then
      v_lesson := public.fn_task_lesson(r.task_id, 'event_closed',
                    jsonb_build_object('event_type', r.event_type,
                                       'correlation_id', r.correlation_id::text,
                                       'os_key', r.os_key));
      if v_lesson is not null then n_lessons := n_lessons + 1; end if;
    end if;
  end loop;

  -- ── LINK 8 · the Chief of Staff consolidates ACROSS OSes ───────────────────────────────────
  -- One row per business episode, not per event: correlation_id is the episode.  os_count is the
  -- number of distinct Operating Systems the episode touched, which is the difference between a
  -- consolidation and a receipt.
  --
  -- LINK 4 IS READ HERE.  Each OS records an event_assessment — severity, impact, proposed action
  -- — before it raises a task, and until now nothing ever looked at one.  The episode's assessed
  -- severity travels with the consolidation into priority_note and into the priority.updated
  -- payload, so what the OSes said about impact reaches the person re-prioritising on it.
  for r in
    select e.correlation_id,
           min(e.id)                                        as root_event_id,
           (array_agg(e.event_type order by e.id))[1]       as root_type,
           count(distinct d.os_key)                         as os_count,
           count(d.task_id)                                 as tasks_total,
           count(*) filter (where d.closed_at is not null)   as tasks_closed,
           (select count(*) from event_assessment a
              join company_event ae on ae.id = a.event_id
             where ae.correlation_id = e.correlation_id)     as assessed,
           (select max(case a.severity when 'high' then 3 when 'medium' then 2 else 1 end)
              from event_assessment a
              join company_event ae on ae.id = a.event_id
             where ae.correlation_id = e.correlation_id)     as sev_rank
      from company_event e
      join event_delivery d on d.event_id = e.id
     where e.correlation_id is not null
     group by e.correlation_id
  loop
    -- Defence 2: never consolidate a chain a re-prioritisation started.
    if r.root_type = 'priority.updated' then continue; end if;

    v_outcome := case when r.tasks_total = 0                  then 'no_work'
                      when r.tasks_closed = 0                 then 'open'
                      when r.tasks_closed < r.tasks_total     then 'partial'
                      else 'closed' end;
    v_sev := case r.sev_rank when 3 then 'high' when 2 then 'medium' when 1 then 'low'
                             else 'unassessed' end;
    v_note := format('%s across %s OS: %s of %s task(s) closed. Impact: %s assessment(s), highest severity %s.',
                     r.root_type, r.os_count, r.tasks_closed, r.tasks_total,
                     coalesce(r.assessed,0), v_sev);

    insert into event_rollup (correlation_id, root_event_id, event_type, os_count,
                              tasks_total, tasks_closed, outcome, priority_note, consolidated_at)
    values (r.correlation_id, r.root_event_id, r.root_type, r.os_count,
            r.tasks_total, r.tasks_closed, v_outcome, v_note, now())
    on conflict (correlation_id) do update
      set os_count = excluded.os_count, tasks_total = excluded.tasks_total,
          tasks_closed = excluded.tasks_closed, outcome = excluded.outcome,
          priority_note = excluded.priority_note, consolidated_at = excluded.consolidated_at;
    n_rollups := n_rollups + 1;

    -- ── LINK 9 · the CEO re-prioritises off the consolidated outcome ──────────────────────────
    -- The episode must have crossed an OS boundary — a single-OS chain is that OS's own business
    -- and does not move company priorities — and at least one OS must have RETURNED something,
    -- because a priority cannot be revised against an outcome that does not exist yet.
    --   Deliberately not 'closed' only. Measured on production: all 22 cross-OS episodes sit at
    --   0/4 or 1/4 tasks closed, and one task that never closes would hold the whole episode — and
    --   the company's priorities — hostage forever. Link 9 says "off event OUTCOMES", not "off all
    --   of them". One re-prioritisation per episode either way: the dedupe is on correlation_id.
    if v_outcome in ('closed','partial') and r.os_count > 1 and n_priorities < c_max_priority
       and not exists (select 1 from company_event ce
                        where ce.event_type = 'priority.updated'
                          and ce.correlation_id = r.correlation_id) then
      -- xos-14. This event is CAUSED by the root of the chain and belongs to the same chain. The
      -- settings are read by company_event's column defaults, which is why fn_emit does not name
      -- either column.  Defence 1 lives here: same correlation_id => the `not exists` above is
      -- permanently true for this episode from the next run onward.
      perform set_config('app.correlation_id',      r.correlation_id::text, true);
      perform set_config('app.causation_event_id',  r.root_event_id::text,  true);
      perform public.fn_emit('priority.updated', 'event_chain', r.correlation_id::text, 'ceo',
                jsonb_build_object('root_event_id', r.root_event_id, 'root_type', r.root_type,
                                   'os_count', r.os_count, 'tasks_closed', r.tasks_closed,
                                   'assessments', coalesce(r.assessed,0), 'max_severity', v_sev,
                                   'note', v_note));
      perform set_config('app.correlation_id',     '', true);
      perform set_config('app.causation_event_id', '', true);
      n_priorities := n_priorities + 1;
    end if;
  end loop;

  -- The Knowledge OS's declared output. One per run rather than one per lesson: the bus carries
  -- the fact that institutional memory moved, not 58 copies of it.
  if n_lessons > 0 then
    perform public.fn_emit('knowledge.updated', 'institutional_memory', 'event_lessons',
              'knowledge_director', jsonb_build_object('lessons_added', n_lessons));
  end if;

  -- ── xos-15 · somebody looks at the bus ─────────────────────────────────────────────────────
  -- v_event_backbone is the one surface that says which subscribed event types are live, which
  -- have never fired and which are undelivered.  It had zero readers, which made it a diagram.
  -- chains_open is the consolidation backlog the view now carries: episodes that reached an OS
  -- and have not finished.  Reported here so the number lands in agent_runs rather than only in
  -- the view definition.
  select coalesce(string_agg(event_type || ' ' || state, ', ' order by event_type),
                  'every subscribed event type is LIVE')
    into v_backbone
    from v_event_backbone where state <> 'LIVE';

  select coalesce(sum(chains_open), 0) into v_open_chains from v_event_backbone;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('event_consolidate', now(), now(), 'ok',
          jsonb_build_object('deliveries_closed', n_closed, 'lessons', n_lessons,
                             'rollups', n_rollups, 'priorities_emitted', n_priorities,
                             'chains_open', v_open_chains),
          'Cross-OS contract closed: ' || n_closed || ' delivery result(s) returned, ' || n_lessons
          || ' lesson(s) captured, ' || n_rollups || ' chain(s) consolidated, ' || n_priorities
          || ' re-prioritisation(s) emitted, ' || v_open_chains || ' episode(s) still open. '
          || 'Bus backbone: ' || v_backbone);

  return jsonb_build_object('deliveries_closed', n_closed, 'lessons', n_lessons,
                            'rollups', n_rollups, 'priorities_emitted', n_priorities,
                            'chains_open', v_open_chains, 'bus_backbone', v_backbone);
end $function$;

-- fn_term_matches
-- ROUTINE REMOVED 7 September 2026. public.fn_term_matches was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- fn_group_dispatch_report
-- ROUTINE REMOVED 7 September 2026. public.fn_group_dispatch_report was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

