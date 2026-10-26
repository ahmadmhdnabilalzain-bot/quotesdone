-- ESCALATION NAMES A PARTY, AND THE PARTY DEPENDS ON WHO IS ESCALATING.
--
-- Measured on production 6 Aug 2026 before this file: fn_should_escalate consulted exactly one
-- source for "who takes it", decision_policy.review_owner = 'Secretary', which matches no
-- agent_key, no dept_key and no title. Every one of the 1,094 routed escalations of the last 30
-- days was therefore addressed to nobody, and after the exec fallback landed, every one of them
-- was addressed to the SAME somebody — 'brief' — whoever raised it and whatever it was about.
-- A constant is not an answer to "Who must approve? Who must review?".
--
-- Three routines knew who was escalating and told the router nothing: trg_action_gate wrote
-- NEW.agent to decision_log.actor, fn_ai_gate passed p_actor to fn_authorize, fn_decide carried
-- p_actor through to decision_record — and all three called fn_should_escalate without it. They
-- pass it now, and fn_should_escalate routes up org_agents.manager_key (65 of 66 active employees
-- carry one; all 65 resolve to an active employee), falling back to the standing deputy through
-- fn_pick_reviewer — which already owns delegation_rule, availability and the seniority tie-break
-- — when that manager is unavailable. The configured review_owner still wins when it resolves,
-- and the exec fallback still catches a context with no actor at all.
--
-- Also here: fn_agent_context's workflow_run subquery took the 8 newest runs COMPANY-WIDE and only
-- then filtered on os_key, so with all 8 newest runs in operations, employees in intelligence (19
-- running), leadership (12), evolution (6) and knowledge (2) saw none of their own. The filter
-- moves inside the subquery so the limit is per-OS.

CREATE OR REPLACE FUNCTION public.fn_should_escalate(ctx jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  reasons text[] := '{}';
  conf_min numeric; fin_review numeric; auto_max numeric; fraud_max numeric;
  legal jsonb; sens jsonb; owner text;
  c_conf numeric := nullif(ctx->>'confidence','')::numeric;
  c_amt  numeric := nullif(ctx->>'amount_aed','')::numeric;
  c_fraud numeric := nullif(ctx->>'fraud_score','')::numeric;
  c_cat  text := lower(coalesce(ctx->>'category',''));
  c_txt  text := lower(coalesce(ctx->>'text',''));
  c_money boolean := coalesce((ctx->>'moves_money')::boolean,false);
  trg text;
  -- WHO IS ESCALATING. Every caller knows it and none of them used to say it, so the router had
  -- exactly one input for "who takes this" — decision_policy.review_owner — and therefore exactly
  -- one answer for all 67 employees and every situation.
  c_actor text := nullif(btrim(coalesce(ctx->>'actor', ctx->>'agent_key', '')), '');
  v_route text; v_basis text; v_note text;
  v_mgr text; v_mgr_dept text; v_pick jsonb;
begin
  select value::numeric into conf_min   from decision_policy where key='confidence_min';
  select value::numeric into fin_review  from decision_policy where key='financial_review_aed';
  select value::numeric into auto_max    from decision_policy where key='auto_action_max_aed';
  select value::numeric into fraud_max   from decision_policy where key='fraud_score_max';
  select value into legal                from decision_policy where key='legal_triggers';
  select value into sens                 from decision_policy where key='sensitive_categories';
  select value #>> '{}' into owner       from decision_policy where key='review_owner';

  if c_conf is not null and c_conf < conf_min then
     reasons := array_append(reasons, 'confidence '||round(c_conf,2)::text||' < min '||round(conf_min,2)::text); end if;
  if c_amt is not null and c_amt >= fin_review then
     reasons := array_append(reasons, 'amount AED '||c_amt::text||' >= review threshold '||fin_review::text); end if;
  if c_money and (c_amt is null or c_amt > auto_max) then
     reasons := array_append(reasons, 'action moves money beyond autonomous limit'); end if;
  if c_fraud is not null and c_fraud >= fraud_max then
     reasons := array_append(reasons, 'fraud score '||round(c_fraud,2)::text||' >= max '||round(fraud_max,2)::text); end if;
  if c_cat <> '' and sens ? c_cat and (c_conf is null or c_conf < conf_min) then
     reasons := array_append(reasons, 'sensitive category "'||c_cat||'" with low/absent confidence'); end if;
  for trg in select jsonb_array_elements_text(legal) loop
     if c_txt <> '' and position(trg in c_txt) > 0 then
        reasons := array_append(reasons, 'legal trigger: "'||trg||'"'); end if;
  end loop;

  -- RESOLVE THE PARTY. Four attempts, strongest first; each one is a party the org model contains.
  if owner is not null and btrim(owner) <> '' then
    select a.agent_key into v_route from org_agents a
     where a.active and a.agent_key = owner limit 1;
    if v_route is not null then v_basis := 'employee'; end if;

    if v_route is null then
      select d.dept_key into v_route from org_departments d
       where d.dept_key = owner
         and exists (select 1 from org_agents a where a.department = d.dept_key and a.active)
       limit 1;
      if v_route is not null then v_basis := 'staffed_department'; end if;
    end if;

    if v_route is null then
      select a.agent_key into v_route from org_agents a
       where a.active and a.title ilike '%'||owner||'%'
       order by a.agent_key limit 1;
      if v_route is not null then v_basis := 'employee_by_title'; end if;
    end if;
  end if;

  -- THE REPORTING LINE. The configured owner named nobody, and before this rung existed the next
  -- thing to run was the exec fallback — so every escalation in the company, whoever raised it and
  -- whatever it was about, was addressed to one person. "Who must approve? Who must review?" was
  -- being answered with a constant. org_agents.manager_key is the only column in the company that
  -- records what "up" is (65 of 66 active employees carry one and all 65 resolve to an active
  -- employee), and escalation means up. It sits AFTER the configured owner deliberately: an explicit
  -- review_owner that resolves is founder configuration and still wins.
  --
  -- AVAILABILITY IS PART OF NAMING A PARTY. A manager on leave is the same nobody an unstaffed
  -- department is, so the manager must be active AND available; if they are not, the standing deputy
  -- is resolved by fn_pick_reviewer — which already owns delegation_rule, the reputation tier and
  -- the seniority tie-break for exactly this question, and is not reimplemented here.
  if v_route is null and c_actor is not null then
    select a.manager_key into v_mgr from org_agents a where a.agent_key = c_actor and a.active;
    if v_mgr is not null and v_mgr <> c_actor then
      select a.agent_key into v_route from org_agents a
       where a.agent_key = v_mgr and a.active and a.available
         and (a.unavailable_until is null or a.unavailable_until < current_date);
      if v_route is not null then v_basis := 'reporting_line'; end if;

      if v_route is null then
        select a.department into v_mgr_dept from org_agents a where a.agent_key = v_mgr;
        begin v_pick := public.fn_pick_reviewer(v_mgr_dept);
        exception when others then v_pick := null; end;
        v_route := public.fn_route_party(v_pick->>'reviewer');
        -- ESCALATING TO YOURSELF IS ESCALATING TO NOBODY. Measured on staging while proving this
        -- branch: with cfo marked unavailable, delegation_rule #4 names ap_specialist as finance's
        -- standing deputy — and ap_specialist was the employee raising the escalation, so the
        -- router handed the item straight back to them. When the deputy is the escalator the rung
        -- yields and the exec fallback below takes it up instead.
        if v_route = c_actor then v_route := null; end if;
        if v_route is not null then
          v_basis := 'reporting_line_delegated';
          v_note  := 'manager '||v_mgr||' is unavailable; '
                  || coalesce(v_pick->>'basis','delegation_rule standing deputy');
        end if;
      end if;
    end if;
  end if;

  -- The configured owner names nobody. Escalate to the executive department's own head rather than
  -- to a string: brain_agent first (the department's reasoning seat), then lead_agent, then any
  -- active member. Recorded as a fallback so the configuration gap stays visible.
  if v_route is null then
    select coalesce(
             (select d.brain_agent from org_departments d where d.dept_key='exec'
               and exists (select 1 from org_agents a where a.agent_key=d.brain_agent and a.active)),
             (select d.lead_agent  from org_departments d where d.dept_key='exec'
               and exists (select 1 from org_agents a where a.agent_key=d.lead_agent and a.active)),
             (select a.agent_key from org_agents a where a.active and a.department='exec'
               order by a.agent_key limit 1))
      into v_route;
    if v_route is not null then
      v_basis := 'fallback_exec';
      v_note := 'configured review_owner "'||coalesce(owner,'(unset)')||'" names no active employee '
             || 'and no staffed department; escalation addressed to '||v_route||' instead';
    end if;
  end if;

  -- Nothing in the org model resolves. Return the configured label unchanged and say so, so the
  -- gap is measurable rather than papered over.
  if v_route is null then
    v_route := owner; v_basis := 'unresolved';
    v_note := 'configured review_owner "'||coalesce(owner,'(unset)')||'" resolves to no party in the '
           || 'org model, and no active executive employee was available to take it';
  end if;

  -- ROUTING IS NOT A REASON TO ESCALATE. `reasons` is what makes `escalate` true and what
  -- trg_action_gate copies into decision_log.reasons, so appending a routing note here would have
  -- made EVERY gated action escalate — the note lives in its own key for exactly that reason.
  return jsonb_build_object(
    'escalate', array_length(reasons,1) is not null,
    'reasons', to_jsonb(reasons),
    'route_to', v_route,
    'route_basis', v_basis,
    'route_note', v_note,
    'route_owner_configured', owner);
end $function$;

-- ROUTINE REMOVED 7 September 2026. public.fn_ai_gate was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ROUTINE REMOVED 7 September 2026. public.trg_action_gate was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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

  return jsonb_build_object('kind',p_kind,'decision',decision,'confidence',conf,'reasons',reasons,
                            'route_to',route,'sources',sources,'detail',res,
                            'decision_record_id',v_dr_id,'status',v_dr_status,
                            'gate_verdict',v_verdict,'gate_reason',v_gate_reason,
                            'options',v_options,'knowledge_hits',jsonb_array_length(v_hits),
                            'prior_outcomes',v_prior);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text DEFAULT NULL::text, p_max_chars integer DEFAULT 9000)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text := ''; r record; piece text; cap int; own_cap int;
        v_dept text; v_role text; v_charter text; v_north text; v_health_fn text;
        v_status text; v_state jsonb; v_l4 text := '';
        v_emp text := ''; v_title text; v_resp text; v_mgr text; v_sen text; v_plan text;
        v_cap_tasks int; v_line text; v_n int; v_os text; v_pad int := 0;
begin
  cap := greatest(coalesce(p_max_chars,9000), 22000);
  own_cap := least(cap/2, 6000);
  if p_agent_key is not null then
    select a.department, a.role into v_dept, v_role from org_agents a where a.agent_key=p_agent_key;
    select d.charter, d.north_star, d.health_fn into v_charter, v_north, v_health_fn
      from org_departments d where d.dept_key=v_dept;
    select status into v_status from org_onboarding where agent_key=p_agent_key;
    out := out || '# YOUR IDENTITY AT QUOTESDONE'||E'\n'
      ||'You are '||coalesce(v_role, p_agent_key||' (senior specialist)')
      ||case when v_charter is not null then '. Department charter: '||v_charter else '' end
      ||case when v_north is not null then ' North star: '||v_north||'.' else '' end
      ||' Employment status: '||coalesce(v_status,'onboarding')||'.'||E'\n'
      ||'POSTURE: You are a senior executive employee, not an assistant. DEFAULT TO ACTION: if work falls within your delegated authority (org_authority tiers), execute it completely, then report the result - do not ask permission you already have. Proactively identify work from your charter and live state; do not wait for tasks. Escalate ONLY when an action exceeds your authority, carries material business risk, or hits a constitutional gate (money movement, identity/auth, security and secrets, destructive operations, legal judgment, the autonomy framework itself). Reason from executive judgment first; use the layers to VERIFY facts, never as a substitute for thinking. Quote operational numbers ONLY from LIVE STATE. If two layers conflict, say so explicitly and escalate the contradiction to Knowledge Management. Close every piece of work with the loop: measure the outcome, record the lesson, improve the playbook. If your employment status is not certified, mark your outputs as provisional.'||E'\n\n';

    -- ---- THE EMPLOYEE OBJECT (spec line 372) --------------------------------------------------
    select a.title, a.responsibilities, a.manager_key, a.seniority, a.improvement_plan, a.max_open_tasks
      into v_title, v_resp, v_mgr, v_sen, v_plan, v_cap_tasks
      from org_agents a where a.agent_key = p_agent_key;

    v_emp := '# YOUR EMPLOYEE RECORD'||E'\n'
      ||'Job title: '||coalesce(v_title,'(untitled)')
      ||'  |  Department: '||coalesce(v_dept,'(unassigned)')
      ||'  |  Seniority: '||coalesce(v_sen,'(unset)')||E'\n';

    -- The reporting line, finally walked. CEO -> Chief of Staff -> Department Heads -> Specialists.
    if v_mgr is not null then
      select 'Reports to: '||m.agent_key||' — '||coalesce(m.title, m.role, 'manager') into v_line
        from org_agents m where m.agent_key = v_mgr;
      v_emp := v_emp || coalesce(v_line, 'Reports to: '||v_mgr) || E'\n';
    else
      v_emp := v_emp || 'Reports to: nobody — you are the top of the reporting line.'||E'\n';
    end if;

    select count(*), string_agg(x.agent_key||' ('||coalesce(x.title, x.role, 'specialist')||')', '; ' order by x.agent_key)
      into v_n, v_line
      from (select b.agent_key, b.title, b.role from org_agents b
             where b.manager_key = p_agent_key and b.active order by b.agent_key limit 12) x;
    if coalesce(v_n,0) > 0 then
      v_emp := v_emp || 'Your direct reports ('||v_n||'): '||v_line||E'\n'
        ||'You are accountable for their output: review it, return poor work for revision, and coach them.'||E'\n';
    end if;

    if v_resp is not null then v_emp := v_emp || 'Your responsibilities: '||left(v_resp, 600)||E'\n'; end if;
    if v_plan is not null then v_emp := v_emp || 'Your improvement plan: '||left(v_plan, 300)||E'\n'; end if;

    -- ---- AUTHORITY LIMITS ----------------------------------------------------------------------
    -- Per-employee first (employee_authority), falling back to the department grant that
    -- cos_execute:170 actually enforces. Stating the ceiling is what makes "escalate only when an
    -- action exceeds your authority" in the POSTURE above an instruction rather than a slogan.
    select string_agg(z.action_class||' -> '||z.max_tier
             ||case when z.threshold_aed is not null then ' (up to '||z.threshold_aed||' AED)' else '' end, '; '
             order by z.action_class)
      into v_line
      from (select e.action_class, e.max_tier, e.threshold_aed from employee_authority e
             where e.agent_key = p_agent_key order by e.action_class limit 14) z;
    if v_line is null then
      select string_agg(z.action_class||' -> '||z.max_tier
               ||case when z.threshold_aed is not null then ' (up to '||z.threshold_aed||' AED)' else '' end, '; '
               order by z.action_class)
        into v_line
        from (select o.action_class, o.max_tier, o.threshold_aed from org_authority o
               where o.dept_key = v_dept order by o.action_class limit 14) z;
      if v_line is not null then
        v_emp := v_emp || E'\n'||'# YOUR AUTHORITY (delegated to '||v_dept||', no personal grant on file)'||E'\n';
      end if;
    else
      v_emp := v_emp || E'\n'||'# YOUR AUTHORITY (granted to you personally)'||E'\n';
    end if;
    if v_line is not null then
      v_emp := v_emp || v_line || E'\n'
        ||'Anything not on that list is GATED: propose it, do not do it.'||E'\n';
    end if;

    -- ---- ESCALATION RULES (blueprint component 5) ----------------------------------------------
    -- The spec requires every employee to have Escalation Rules alongside Role, Authority, KPIs,
    -- Knowledge and Decision Rights. There is no escalation table — only escalations_archive — but
    -- ops_knowledge.escalation_rule carries a real one on 1,206 of its 3,959 records, shaped
    -- {"when": ..., "action": ...}. Its only reader was fn_kb_retrieve, which has ZERO callers
    -- anywhere, so the rules reached nobody.
    --
    -- Read here rather than by widening fn_ops_knowledge_search: that function's return type would
    -- have to change, which needs a DROP, and fn_agent_context itself depends on it. An additive
    -- read is the smaller and safer diff.
    select string_agg(distinct '- when ' || replace(e.escalation_rule->>'when','_',' ')
                             || ' -> ' || replace(e.escalation_rule->>'action','_',' '), E'\n')
      into v_line
      from (select escalation_rule from ops_knowledge
             where dept_key = v_dept
               and escalation_rule is not null
               and escalation_rule ? 'when' and escalation_rule ? 'action'
             limit 40) e;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# WHEN TO ESCALATE (your department''s recorded rules)'||E'\n'||left(v_line, 700)||E'\n';
    end if;

    -- ---- KPIs: how this employee's work is judged ----------------------------------------------
    select string_agg(z.kpi||' — target '||coalesce(z.target_value::text,'?')||' '||coalesce(z.unit,'')
             ||' ('||coalesce(z.cadence,'ongoing')
             ||case when z.serves_goal is not null then '; serves company goal '||z.serves_goal else '' end||')', E'\n- '
             order by z.kpi)
      into v_line
      from (select k.kpi, k.target_value, k.unit, k.cadence, k.serves_goal from employee_kpi k
             where k.agent_key = p_agent_key and k.active order by k.kpi limit 8) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR KPIs — this is how your work is measured'||E'\n- '||v_line||E'\n';
    end if;

    -- ---- CURRENT WORKLOAD, measured rather than assumed -----------------------------------------
    -- max_open_tasks is a CAP. This is the LOAD against it, read live at prompt time.
    select 'Your department has '||count(*)||' task(s) in flight ('
           ||count(*) filter (where t.status='assigned')||' assigned, '
           ||count(*) filter (where t.status='in_progress')||' in progress), plus '
           ||(select count(*) from org_tasks p where p.dept_key = v_dept and p.status='proposed')
           ||' awaiting a founder decision. Your personal cap is '||coalesce(v_cap_tasks,0)||' open task(s).'
      into v_line
      from org_tasks t where t.dept_key = v_dept and t.status in ('assigned','in_progress');
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR CURRENT WORKLOAD (live)'||E'\n'||v_line||E'\n';
      select string_agg('- ['||z.status||'] '||left(z.title,90), E'\n' order by z.id)
        into v_line
        from (select t.id, t.status, t.title from org_tasks t
               where t.dept_key = v_dept and t.status in ('assigned','in_progress')
               order by t.id limit 6) z;
      if v_line is not null then v_emp := v_emp || v_line || E'\n'; end if;
    end if;

    -- ---- WHICH OPERATING SYSTEM YOU BELONG TO (spec file #2) ------------------------------------
    -- The Universal OS Blueprint's first four components — Purpose, Mission, Objectives,
    -- Responsibilities — were all POPULATED and read by NOTHING: operating_system.charter/mandate
    -- and .mission 10/10, os_objective 50 rows (all five horizons for all ten OSes),
    -- os_responsibility 71 rows whose only reader was fn_graph_rebuild. The single view that
    -- exposed them, v_operating_manual, has zero readers itself.
    --
    -- An employee belongs to an OS through org_agents.department -> os_department -> operating_system.
    -- Emitting it here is the same fix that closed row #1: the company knew all of this and never
    -- told the people doing the work.
    --
    -- 4. THE OWNER. 'owner' is one of the seven attributes the blueprint names per OS
    --    (operating_system.owner_agent, 10/10 populated, all ten resolving to a live employee) and
    --    it was the one attribute of the seven that never left the table: fn_os_improve read the
    --    column on a cron, but the block below emitted name/Purpose/Mission/Mandate/OWNS/objectives
    --    and no owner line, so measured across all 66 active employees not one could name who owns
    --    their OS. A responsibility an employee cannot escalate is a responsibility with no route
    --    out, which is what makes this the same defect as the other three: known by the company,
    --    never told to the person doing the work.
    for r in
      select o.os_key, o.name, o.charter, o.mandate, o.mission, o.owner_agent,
             (select coalesce(w.title, w.role) from org_agents w
               where w.agent_key = o.owner_agent and w.active) owner_title,
             (select string_agg(x.responsibility, ', ' order by x.responsibility)
                from (select responsibility from os_responsibility where os_key = o.os_key
                       order by responsibility limit 12) x) resp,
             (select string_agg(y.horizon || ': ' || y.objective, E'\n- '
                       order by case y.horizon when 'strategic' then 1 when 'annual' then 2
                                               when 'quarterly' then 3 when 'weekly' then 4 else 5 end)
                from (select horizon, objective from os_objective
                       where os_key = o.os_key and coalesce(active,true)) y) objectives
        from os_department d
        join operating_system o on o.os_key = d.os_key and coalesce(o.active,true)
       where d.dept_key = v_dept
       limit 1
    loop
      v_os := r.os_key;
      -- Emitted and measured from ONE expression. The line's length is what compensates the layer
      -- budgets below, so a second copy of the text is a copy that can be edited alone and leave
      -- the compensation quietly wrong.
      v_line := case when r.owner_agent is not null
                     then 'Your OS is owned by: '||r.owner_agent
                       ||coalesce(' — '||left(r.owner_title,60), '')
                       ||'. Escalate OS-level decisions there.'||E'\n'
                     else '' end;
      v_pad := length(v_line);
      v_emp := v_emp || E'\n'||'# YOUR OPERATING SYSTEM — '||coalesce(r.name, r.os_key)||E'\n'
        ||case when r.charter is not null then 'Purpose: '||left(r.charter,300)||E'\n' else '' end
        ||case when r.mission is not null then 'Mission: '||left(r.mission,240)||E'\n' else '' end
        ||case when r.mandate is not null then 'Mandate: '||left(r.mandate,240)||E'\n' else '' end
        ||v_line
        ||case when r.resp is not null
               then 'Your OS OWNS, and no other OS may own: '||r.resp||E'\n'
                 ||'If work belongs to another OS, hand it over — do not duplicate it.'||E'\n'
               else '' end
        ||case when r.objectives is not null
               then 'Your OS objectives by horizon:'||E'\n- '||r.objectives||E'\n' else '' end;
    end loop;

    -- THE OWNER LINE IS NOT PAID FOR OUT OF THE KNOWLEDGE BUDGET. LAYER 2 admits a piece while
    -- length(out) + length(piece) <= own_cap + 2200 and LAYER 1 while <= cap, and `out` already
    -- carries the employee record — so 70-97 characters added here come straight off the end of
    -- LAYER 1. Measured on production the first time this line was deployed WITHOUT this
    -- compensation: 19 employees lost a global knowledge topic each, including 'Penalty &
    -- collections model' (priority 94), 'Escalation policy' (93) and 'canon:supplier_status' (93).
    -- That is the file header's own rule — anything inserted before the layers deletes something
    -- already proven to reach an employee — and the owner line is the one insertion that cannot be
    -- moved to the end, because it has to land inside the OS block. So it buys its own space
    -- instead: both budgets grow by exactly the characters it used, which leaves every other
    -- inclusion decision bit-for-bit where it was. v_pad is 0 when no OS block was emitted.
    cap := cap + v_pad;
    own_cap := own_cap + v_pad;

    -- ---- WHAT THE COMPANY IS TRYING TO ACHIEVE ---------------------------------------------------
    -- company_goals was read by dept_plan:79 and by nothing an ordinary employee ever saw. The spec
    -- opens with "Every employee works toward the same business objectives" and "Every decision made
    -- by every AI employee should support these objectives".
    -- goal_period held 183 rows, refreshed daily by fn_goal_period_refresh, and was read by NOTHING
    -- but its own refresher. It carries the only actual-versus-target the company computes, so a
    -- goal without it is an aspiration and a goal with it is a number someone can act on.
    select string_agg(z.goal||' ('||coalesce(z.metric,'no metric')
             ||case when z.target_value is not null then '; target '||z.target_value||' '||coalesce(z.unit,'') else '' end
             ||case when z.actual_value is not null
                    then '; CURRENTLY '||z.actual_value||coalesce(' ('||z.status||')','') else '; not yet measured' end||')', E'\n- '
             order by z.sort nulls last)
      into v_line
      from (select g.goal, g.metric, g.target_value, g.unit, g.sort, gp.actual_value, gp.status
              from company_goals g
              left join lateral (select p.actual_value, p.status from goal_period p
                                  where p.goal_key = g.key
                                  order by p.updated_at desc nulls last limit 1) gp on true
             where g.active and (g.owner_dept is null or g.owner_dept = v_dept or g.owner_dept = 'exec')
             order by g.sort nulls last limit 8) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# COMPANY GOALS YOUR WORK MUST MOVE'||E'\n- '||v_line||E'\n';
    end if;

    select string_agg('- '||z.objective, E'\n' order by z.sort nulls last)
      into v_line
      from (select o.objective, o.sort from department_objective o
             where o.dept_key = v_dept and coalesce(o.active,true) order by o.sort nulls last limit 6) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR DEPARTMENT''S OBJECTIVES'||E'\n'||v_line||E'\n';
    end if;

    -- ---- THE IMPROVEMENT LOOP, WHICH WROTE WHERE NOTHING READ -------------------------------
    -- Of the seven self-optimisation loops, four wrote into tables nobody consulted:
    -- self_review 31 rows, evolution_proposal 32 (31 proposed, 1 ever implemented), decision_record
    -- 3, company_reflection 9 — each read by nothing but its own writer. The spec's "Continuous
    -- Improvement" section is what they implement, so the department they concern is the reader.
    -- Bounded hard: this is context, not a report.
    select string_agg(z.line, E'\n' order by z.ord, z.line)
      into v_line
      from (
        select 1 ord, '- OPEN FINDING ('||s.review_type||'): '||left(s.finding, 160)
               ||coalesce(' — proposed: '||left(s.proposal,120), '') line
          from self_review s
         where coalesce(s.status,'open') not in ('done','implemented','rejected')
         order by s.created_at desc limit 3
      ) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# WHAT THIS ORGANISATION IS TRYING TO FIX'||E'\n'||v_line||E'\n';
    end if;

    select string_agg('- PROPOSED CHANGE ('||e.change_class||'): '||left(e.proposal, 170), E'\n' order by e.id desc)
      into v_line
      from (select id, change_class, proposal from evolution_proposal
             where status = 'proposed' order by id desc limit 3) e;
    if v_line is not null then
      v_emp := v_emp || v_line || E'\n';
    end if;

    -- decision_record carries serves_goal and the reasoning behind past calls. 3 rows, 0 readers.
    -- "Learn from results" cannot happen if the record of what was decided reaches nobody.
    select string_agg('- '||coalesce(d.decided_by,'someone')||' decided: '||left(d.recommendation, 150)
             ||coalesce(' (serves '||d.serves_goal||')','')
             ||coalesce(' — outcome: '||left(d.actual_outcome,80), ' — outcome not yet recorded'), E'\n' order by d.id desc)
      into v_line
      from (select id, decided_by, recommendation, serves_goal, actual_outcome from decision_record
             where dept_key = v_dept or dept_key is null order by id desc limit 2) d;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# DECISIONS ALREADY ON RECORD FOR YOUR DEPARTMENT'||E'\n'||v_line||E'\n';
    end if;

    -- company_reflection: 9 rows, written nightly by fn_company_reflect, read by nothing but its
    -- own writer. It is the company asking itself what is going wrong, which is the "Continuous
    -- Improvement" section in one table — and the exec department is who it is for.
    if v_dept = 'exec' then
      select '- '||to_char(c.reflected_on,'DD Mon')||': '||c.concerns||' concern(s), '||c.actions
             ||' action(s) — '||left(coalesce(c.answers->>'biggest_risk', c.answers::text), 200)
        into v_line
        from company_reflection c order by c.reflected_on desc limit 1;
      if v_line is not null then
        v_emp := v_emp || E'\n'||'# THE COMPANY''S OWN LATEST REFLECTION'||E'\n'||v_line||E'\n';
      end if;
    end if;

    out := out || left(v_emp, 6200) || E'\n\n';
  end if;
  if p_agent_key is not null then
    out := out || '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE'||E'\n\n';
    for r in select topic,content from agent_knowledge
             where coalesce(layer,'profession') in ('profession','state')
               and (agent_key = p_agent_key
                    or (v_dept is not null
                        and not exists (select 1 from agent_knowledge k2
                                         where k2.agent_key = p_agent_key
                                           and coalesce(k2.layer,'profession') in ('profession','state'))
                        and agent_key in (select b.agent_key from org_agents b
                                           where b.active and b.department = v_dept
                                             and b.agent_key <> p_agent_key)))
             order by priority desc nulls last, updated_at desc loop
      piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
      if length(out)+length(piece) <= own_cap + 2200 then out := out||piece; end if;
    end loop;
  end if;
  out := out || '# LAYER 1 - COMPANY KNOWLEDGE (authoritative; pricing marked LIVE overrides any other figure)'||E'\n\n';
  for r in select topic,content from agent_knowledge
           where agent_key='_global' and coalesce(priority,0)>=90 order by priority desc nulls last, updated_at desc loop
    piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;
  for r in select topic,content from agent_knowledge
           where agent_key='_global' and coalesce(priority,0)<90 order by priority desc nulls last, updated_at desc loop
    piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;
  if v_health_fn is not null then
    begin
      execute format('select %I()', v_health_fn) into v_state;
      piece := '# LAYER 3 - LIVE OPERATIONAL STATE (from '||v_health_fn||' at '||now()::timestamptz(0)||'; the ONLY valid source for operational numbers)'||E'\n'
               ||left(coalesce(v_state::text,'{}'), 2600)||E'\n\n';
      if length(out)+length(piece) <= cap + 3000 then out := out||piece; end if;
    exception when others then
      out := out || '# LAYER 3 - LIVE OPERATIONAL STATE unavailable ('||sqlerrm||'); do not quote operational numbers this turn.'||E'\n\n';
    end;
  end if;
  if p_agent_key is not null then
    for r in select topic, content from agent_knowledge
             where layer='experience' and agent_key in (p_agent_key,'_global')
             order by updated_at desc limit 12 loop
      v_l4 := v_l4 || '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    end loop;
    for r in select kind, content from agent_memory m
             where m.agent_key=p_agent_key and m.importance >= 5
               and not exists (select 1 from policy_rules p where p.active and m.content ~* p.forbid_regex)
             order by m.importance desc, m.created_at desc limit 8 loop
      v_l4 := v_l4 || '## memory ('||r.kind||')'||E'\n'||r.content||E'\n\n';
    end loop;
    v_l4 := v_l4 || coalesce(public.fn_agent_institutional_memory(p_agent_key, 6), '');
    if v_l4 <> '' then
      out := out || '# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED'||E'\n\n'|| left(v_l4, 3500);
    end if;
  end if;
  -- ---- THE OS LAYER'S THREE UNREAD OUTPUTS ------------------------------------------------------
  -- Appended at the END on purpose. v_emp is truncated at 6,200 characters and LAYER 2 is budgeted
  -- against length(out); adding any of this earlier would silently delete something already proven
  -- to reach the employee. An output landing exactly on a ceiling is truncation, not coincidence.
  if v_os is not null then
    -- os_objective.measure was a LABEL on all 50 rows — 'gl_journal', 'qualified pipeline',
    -- 'KPI instrumentation'. A label cannot be met or missed. measure_sql now resolves to a number
    -- on a daily cron and this is the only place that number reaches a person.
    select string_agg(z.horizon||': '||z.objective||' — reads '
             ||coalesce(z.actual_value::text,'no value')
             ||coalesce(' (measured '||to_char(z.measured_at,'DD Mon')||')', ' (measure failed)'),
             E'\n- '
             order by case z.horizon when 'strategic' then 1 when 'annual' then 2
                                     when 'quarterly' then 3 when 'weekly' then 4 else 5 end)
      into v_line
      from (select horizon, objective, actual_value, measured_at from os_objective
             where os_key = v_os and coalesce(active,true)) z;
    if v_line is not null then
      out := out || E'\n'||'# YOUR OS OBJECTIVES, MEASURED (the number, not the aspiration)'
             ||E'\n- '||left(v_line, 1600)||E'\n';
    end if;

    -- OS.txt line 109: "Leadership OS should not duplicate this knowledge; it queries Finance OS
    -- when needed." os_knowledge_domain wrote that routing down 315 times and nothing resolved it;
    -- its only reader, fn_knowledge_gaps, takes no os_key and cannot answer "who owns this".
    v_line := public.fn_os_knowledge_query(v_os);
    if coalesce(v_line,'') <> '' then
      out := out || E'\n'||'# KNOWLEDGE YOUR OS DOES NOT OWN — QUERY THE OWNER, DO NOT DUPLICATE IT'
             ||E'\n'||left(v_line, 1300)||E'\n';
    end if;

    -- workflow_run and workflow_step_run were 0 rows with 0 readers while workflow held 14 active
    -- definitions and workflow_step 117 steps. A run nobody can see is the diagram again.
    select string_agg('- '||coalesce(w.name, x.workflow_key)||': step '||coalesce(x.current_step,0)
             ||' of '||(select count(*) from workflow_step s where s.workflow_key = x.workflow_key)
             ||' ('||x.status||')'
             ||coalesce(' — now: '||(select sr.input->>'step' from workflow_step_run sr
                                      where sr.workflow_run_id = x.id
                                        and sr.step_no = x.current_step), ''),
             E'\n' order by x.started_at desc nulls last)
      into v_line
      -- THE LIMIT MUST SIT AFTER THE FILTER, NOT BEFORE IT. This subquery used to take the 8
      -- newest runs COMPANY-WIDE and only then join workflow and filter on os_key, so the moment
      -- one OS owned all 8 newest runs every other OS's employees saw nothing. Measured on
      -- production 6 Aug 2026: all 8 newest in-flight runs were operations, while intelligence had
      -- 19 running, leadership 12, evolution 6 and knowledge 2 — and not one of those employees'
      -- prompts carried this section. The os_key filter now sits INSIDE the subquery so the 8 is
      -- per-OS; the outer join and where are left in place so the emitted text is byte-identical
      -- for an OS that was already inside the company-wide window.
      from (select r2.id, r2.workflow_key, r2.current_step, r2.status, r2.started_at
              from workflow_run r2 join workflow w2 on w2.workflow_key = r2.workflow_key
             where r2.status in ('queued','running') and w2.os_key = v_os
             order by r2.started_at desc nulls last limit 8) x
      join workflow w on w.workflow_key = x.workflow_key
     where w.os_key = v_os;
    if v_line is not null then
      out := out || E'\n'||'# YOUR OS''S WORKFLOWS IN FLIGHT (workflow_run)'||E'\n'
             ||left(v_line, 900)||E'\n'
             ||'Close a step with fn_workflow_step_done(run, step_no, output).'||E'\n';
    end if;
  end if;

  return out;
end $function$;
