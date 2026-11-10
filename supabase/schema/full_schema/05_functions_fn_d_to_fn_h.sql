CREATE OR REPLACE FUNCTION public.fn_dbx_category(p_lead_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select public.fn_dbx_safe(coalesce(
    (select c.slug from public.lead_category lc
       join public.catalog_supplier_categories c on c.slug = lc.slug
      where lc.lead_id = p_lead_id and lc.is_primary
      order by lc.score desc nulls last limit 1),
    (select c.slug from public.lead_category lc
       join public.catalog_supplier_categories c on c.slug = lc.slug
      where lc.lead_id = p_lead_id
      order by lc.score desc nulls last limit 1),
    (select c.slug from public.leads l
       join public.catalog_supplier_categories c
         on c.slug = btrim(split_part(coalesce(l.categories,''),',',1))
         or lower(c.name) = lower(btrim(split_part(coalesce(l.categories,''),',',1)))
         or c.slug = btrim(coalesce(l.sector,''))
      where l.id = p_lead_id limit 1),
    'uncategorized'));
$function$


CREATE OR REPLACE FUNCTION public.fn_dbx_component(p text, p_max integer DEFAULT 200)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare s text := public.fn_dbx_safe(p); tail text;
begin
  if char_length(s) <= p_max then return s; end if;
  -- the id suffix and the extension survive; the middle is cut
  tail := coalesce(substring(s from '((?: \([0-9A-Za-z_-]{1,40}\)| #[0-9A-Za-z_-]{1,40})?(?:\.[A-Za-z0-9]{1,8})?)$'), '');
  return public.fn_dbx_safe(left(s, greatest(p_max - char_length(tail) - 1, 1)) || '…' || tail);
end $function$


CREATE OR REPLACE FUNCTION public.fn_dbx_path(p text, p_strict boolean DEFAULT false)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select '/' || string_agg(public.fn_dbx_component(u.c, case when p_strict then 80 else 200 end), '/' order by u.n)
    from unnest(string_to_array(p, '/')) with ordinality u(c, n)
   where btrim(u.c) <> ''
$function$


CREATE OR REPLACE FUNCTION public.fn_dbx_safe(x text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select coalesce(nullif(
           regexp_replace(
             btrim(regexp_replace(regexp_replace(coalesce(x, ''), '[\\/:*?"<>|[:cntrl:]]+', ' ', 'g'), '\s+', ' ', 'g')),
             '[. ]+$', ''),
           ''), '_')
$function$


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
  v_actor_tier text;   -- reputation tier of the acting agent (gap 8)
  v_dr_id bigint; v_dr_status text; v_verdict text; v_gate_reason text;
  v_corr uuid; v_trace uuid; v_prior jsonb;
  v_held bigint;   -- the CEO seat's held question when the text is not yet reasoned (23 Sep 2026)
begin
  begin v_amount := nullif(coalesce(v_ctx->>'amount_aed', v_ctx->>'amount'), '')::numeric;
  exception when others then v_amount := null; end;
  v_dept := nullif(v_ctx->>'dept_key', '');

  -- A MEANING NOT YET REASONED IS NOT DECIDED (23 Sep 2026, founder_instruction 886-903). When the
  -- context carries text, whether it is a legal matter or repeats a failure is the CEO seat's reasoning,
  -- not a word list (fn_should_escalate). Until it is reasoned the question waits, visible, in the CEO
  -- seat's queue (reasoning_held_question) and NOTHING is recorded, routed or escalated — to the founder
  -- least of all. fn_reason_apply_ceo__escalation_meaning re-runs this decision once it is answered.
  if p_kind in ('escalate', 'approve') then
    res := public.fn_should_escalate(v_ctx || jsonb_build_object('actor', p_actor, 'decide_kind', p_kind));
    if jsonb_typeof(res->'needs_reasoning') = 'object' then
      v_held := public.fn_reason_route_ask('ceo', 'ceo.escalation_meaning',
                  'The ' || p_kind || ' decision requested by ' || p_actor || ' concerns: ' || (res->'needs_reasoning'->>'question'),
                  res->'needs_reasoning'->'options',
                  jsonb_build_object('kind', p_kind, 'ctx', v_ctx, 'actor', p_actor),
                  res->'needs_reasoning'->>'dedupe_key');
      return jsonb_build_object('kind', p_kind, 'decision', 'awaiting_reasoning', 'status', 'held', 'held_id', v_held,
                                'route_to', 'ceo', 'reasons', jsonb_build_array('the meaning of the text is being reasoned by the CEO seat; nothing is decided on a word'),
                                'detail', res);
    end if;
  end if;

  if p_kind='escalate' then
    -- p_actor goes IN. Without it the router has no line to send the escalation up and answers
    -- every caller with the same company-wide owner; see fn_should_escalate's reporting-line rung.
    res := public.fn_should_escalate(v_ctx || jsonb_build_object('actor', p_actor, 'decide_kind', p_kind));
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
        -- The supplier's trade as REASONED from its own record (lead_trade_class), exactly (23 Sep 2026). A
        -- substring of the free-text categories column decided it before ('tile' matched 'textile'), and that
        -- column holds company names as often as trades (measured 23 Sep 2026), so it decides nothing now.
        and (coalesce(v_ctx->>'category','')=''
             or exists (select 1 from lead_trade_class c where c.lead_id = leads.id and c.trade_code = lower(btrim(v_ctx->>'category'))))
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
    res := public.fn_should_escalate(v_ctx || jsonb_build_object('actor', p_actor, 'decide_kind', p_kind));
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
  -- Read inline (23 Sep 2026): retire_the_routines_no_seat_can_reach.sql dropped fn_decision_outcomes on
  -- 8 Sep 2026 while this call to it survived, so every fn_decide raised 42883 here (measured 23 Sep 2026
  -- in the batch probe). The same count, 'cancelled' reported and not a failure, as that routine made it.
  select jsonb_build_object('decision_type', p_kind, 'window_days', 90, 'traced', count(*),
           'graded', count(*) filter (where t.outcome_status is not null),
           'succeeded', count(*) filter (where t.outcome_status = 'succeeded'),
           'failed', count(*) filter (where t.outcome_status in ('failed','stalled')),
           'cancelled', count(*) filter (where t.outcome_status = 'cancelled'),
           'last_evaluated_at', max(t.evaluated_at))
    into v_prior
    from public.decision_trace t
   where t.decision_type = p_kind and t.created_at > now() - interval '90 days';
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

  -- Reputation is load-bearing beyond spend: an agent on probation does not take a decision
  -- autonomously, whatever its kind. This is the demotion signal the spend check already reads.
  select r.tier into v_actor_tier from public.agent_reputation r where r.agent_key = p_actor;
  if v_actor_tier = 'probation' then
    reasons := coalesce(reasons,'[]'::jsonb) || jsonb_build_array(
      format('%s is on probation in the reputation system, so this decision is escalated to a person rather than taken autonomously', p_actor));
  end if;

  v_escalates := decision in ('escalate','human_review','unsupported_kind')
                 or conf < 0.7
                 or jsonb_array_length(v_evidence) = 0
                 or not v_authorised
                 or v_actor_tier = 'probation';
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
      case when v_escalates then 'Rollback: nothing executed; the decision sits at proposed and is routed to the accountable department''s lead through the org_task lane (fn_decision_record_route). Only a Stripe refund reaches the founder.'
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
  -- The row is written 'queued'; the hourly execution-run routine (retired 8 Sep 2026, so nothing performs
  -- it today) was to perform it: it delivers the decision to the actor the decision named and settles the row against the
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


  -- A PROPOSED DECISION HAS AN OWNER WHO IS NOT THE FOUNDER (5 Sep 2026). An escalating decision used
  -- to sit at 'proposed' with nobody routed to it and the OS showed it to the founder as his. It is now
  -- handed to the accountable department through the org_task lane in the same transaction. The routing
  -- must never lose the decision it routes, so a failure is a warning on the record, not an abort.
  if v_escalates and v_dr_id is not null then
    begin
      perform public.fn_decision_record_route(v_dr_id);
    exception when others then
      -- recorded where it can be read (a warning prints nowhere through the management API)
      insert into public.error_events(source, kind, severity, detail) values ('fn_decide', 'decision_record_route', 'medium', jsonb_build_object('decision_record_id', v_dr_id, 'error', sqlerrm));
    end;
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
      insert into public.error_events(source, kind, severity, detail) values ('fn_decide', 'board_review', 'medium', jsonb_build_object('decision_record_id', v_dr_id, 'error', sqlerrm));
    end;
  end if;

  return jsonb_build_object('kind',p_kind,'decision',decision,'confidence',conf,'reasons',reasons,
                            'route_to',route,'sources',sources,'detail',res,
                            'decision_record_id',v_dr_id,'status',v_dr_status,
                            'gate_verdict',v_verdict,'gate_reason',v_gate_reason,
                            'options',v_options,'knowledge_hits',jsonb_array_length(v_hits),
                            'prior_outcomes',v_prior);
end $function$


CREATE OR REPLACE FUNCTION public.fn_decision_record_route(p_decision_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  d record; t record;
  v_dept text; v_lead text; v_task bigint; v_title text; v_detail text; v_hops int;
  v_routed int := 0; v_shared int := 0; v_closed int := 0; v_status text;
begin
  for d in
    select r.id, r.decided_by, r.dept_key, r.problem, r.recommendation, r.options, r.created_at
      from public.decision_record r
     where r.status = 'proposed' and r.approved_by is null
       and (p_decision_id is null or r.id = p_decision_id)
       and not exists (select 1 from public.org_tasks o
                        where o.detail like '%[decision_record:' || r.id || ']%')
     order by r.id
  loop
    -- the owning department: the record's, followed through merges; else the actor's; else exec
    v_dept := d.dept_key; v_hops := 0;
    while v_dept is not null and v_hops < 6
          and not exists (select 1 from public.org_departments x where x.dept_key = v_dept and x.active) loop
      select x.merged_into into v_dept from public.org_departments x where x.dept_key = v_dept;
      v_hops := v_hops + 1;
    end loop;
    if v_dept is null then
      select a.department into v_dept from public.org_agents a where a.agent_key = d.decided_by and a.active;
    end if;
    if v_dept is null or not exists (select 1 from public.org_departments x where x.dept_key = v_dept and x.active) then
      v_dept := 'exec';
    end if;
    select x.lead_agent into v_lead from public.org_departments x where x.dept_key = v_dept;
    if not exists (select 1 from public.org_agents a where a.agent_key = v_lead and a.active and coalesce(a.available, true)) then
      v_lead := null;   -- a05_org_task_fill_ownership picks the least-loaded colleague
    end if;

    v_title := left('Decision requested: ' || regexp_replace(coalesce(d.problem, 'decision_record ' || d.id), '^Decision requested \([^)]*\) by [^:]+: ', ''), 200);

    -- the same open question in the same department is one task, not one per retry
    select o.id into v_task from public.org_tasks o
     where o.dept_key = v_dept and o.title = v_title
       and o.status not in ('done', 'cancelled')
       and o.detail like '[decision_record:%'
     order by o.id limit 1;

    if v_task is not null then
      update public.org_tasks
         set detail = detail || ' [decision_record:' || d.id || ']', updated_at = now()
       where id = v_task;
      v_shared := v_shared + 1;
    else
      v_detail := '[decision_record:' || d.id || '] ' || coalesce(d.problem, '')
        || E'\n\nEngine recommendation: ' || coalesce(d.recommendation, '(none)')
        || E'\nOptions scored: ' || left(coalesce(d.options::text, '[]'), 1500)
        || E'\nRaised by ' || coalesce(d.decided_by, '?') || ' at ' || d.created_at
        || '. fn_decide escalated it instead of taking it; the department determines it in the org_task lane '
        || 'and the decision_record closes on that determination. Only a Stripe refund reaches the founder.';
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, decided_by,
                                    action_class, assigned_agent, priority, result)
      values (v_dept, v_title, v_detail, 'assigned', 'advisory', false, 'fn_decision_record_route',
              'analysis', v_lead, 1,
              jsonb_build_object('source', jsonb_build_object('decision_record_id', d.id,
                                 'routed_at', now(), 'routed_by', 'fn_decision_record_route')))
      returning id into v_task;
      v_routed := v_routed + 1;
    end if;
  end loop;

  -- close-back: a decision whose task the department has determined is approved by that employee, and
  -- the gate rules on it
  for d in
    select r.id, o.id as task_id, coalesce(o.result->>'employee', o.assigned_agent, o.dept_key) as employee,
           left(coalesce(o.result->>'deliverable', o.result->>'summary', ''), 2000) as determination
      from public.decision_record r
      join public.org_tasks o on o.detail like '%[decision_record:' || r.id || ']%' and o.status = 'done'
     where r.status = 'proposed' and r.approved_by is null
       and (p_decision_id is null or r.id = p_decision_id)
     order by r.id
  loop
    update public.decision_record
       set status = 'approved', approved_by = d.employee, decided_at = now(),
           actual_outcome = 'Determined in the org_task lane by ' || d.employee || ' (org_task ' || d.task_id || '): '
                            || coalesce(nullif(d.determination, ''), '(no deliverable text on the task)')
     where id = d.id
     returning status into v_status;
    v_closed := v_closed + 1;
  end loop;

  return jsonb_build_object('routed', v_routed, 'shared_existing_task', v_shared,
                            'closed_on_determination', v_closed, 'ran_at', now());
end
$function$


CREATE OR REPLACE FUNCTION public.fn_decision_trace_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if old.sealed_at is not null then
    -- Only the outcome may be graded after sealing. Everything the decision was BASED on is frozen.
    if (new.decision        is distinct from old.decision)
    or (new.evidence_refs   is distinct from old.evidence_refs)
    or (new.knowledge_refs  is distinct from old.knowledge_refs)
    or (new.tool_result_refs is distinct from old.tool_result_refs)
    or (new.confidence      is distinct from old.confidence)
    or (new.authority_result is distinct from old.authority_result)
    or (new.agent_key       is distinct from old.agent_key)
    or (new.role_id         is distinct from old.role_id)
    or (new.proposed_action is distinct from old.proposed_action) then
      raise exception 'decision_trace % is sealed. Evidence, confidence, authority and identity cannot be edited after the fact; grade the outcome instead.', old.id;
    end if;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_deliberation_subject_is_fixture(p_subject_table text, p_subject_id text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id text := split_part(coalesce(p_subject_id, ''), ':', 1); v_s jsonb;
begin
  if p_subject_table = 'inquiries' then
    v_s := jsonb_build_object('inquiry_id', v_id);
  elsif p_subject_table = 'refunds' and v_id ~ '^[0-9]+$' then
    select jsonb_strip_nulls(jsonb_build_object('inquiry_id', r.inquiry_id, 'customer_id', r.customer_id, 'supplier_id', r.supplier_lead_id))
      into v_s from public.refunds r where r.id = v_id::bigint;
  elsif p_subject_table = 'quotes' then
    v_s := jsonb_build_object('quote_id', v_id);
  end if;
  return v_s is not null and public.fn_reason_subject_is_fixture(v_s);
end $function$


CREATE OR REPLACE FUNCTION public.fn_delivery_feedback_canary_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c public.notifications;
  v_new bigint;
  v_arrived timestamptz;
  v_sends int;
  v_out jsonb := '{}'::jsonb;
  v_key constant text := 'delivery_feedback:bounce_reports_silent';
begin
  select * into c from public.notifications
   where type = 'delivery_feedback_canary' order by id desc limit 1;

  -- ── judge the last canary, once ──
  if c.id is not null and c.last_error is null then
    if c.status = 'sent' then
      select s.created_at into v_arrived from public.email_suppressions s
       where s.email = lower(c.to_email) and s.source = 'resend_webhook';
      if v_arrived is not null then
        update public.notifications
           set last_error = 'canary verdict: bounce report arrived ' || round(extract(epoch from v_arrived - c.sent_at)) || ' s after sending'
         where id = c.id;
        delete from public.email_suppressions where email = lower(c.to_email) and source = 'resend_webhook';
        delete from public.error_events where source = 'resend_webhook' and detail -> 'emails' ? lower(c.to_email);
        perform public.fn_it_engineer_finding_close(v_key, 'the daily canary bounce came back through resend_webhook (notification ' || c.id || ')');
        v_out := jsonb_build_object('judged', c.id, 'arrived', true, 'seconds', round(extract(epoch from v_arrived - c.sent_at)));
      elsif c.sent_at < now() - interval '30 minutes' then
        update public.notifications set last_error = 'canary verdict: NO bounce report within 30 minutes' where id = c.id;
        perform public.fn_it_engineer_finding_upsert(v_key,
          'Bounce and complaint reports have stopped arriving: the daily test bounce sent at '
            || to_char(c.sent_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z never reached resend_webhook',
          'Resend webhook -> resend_webhook -> email_suppressions', 'customer_facing', 1,
          jsonb_build_object('notification_id', c.id, 'to_email', c.to_email, 'provider_message_id', c.provider_message_id,
                             'sent_at', c.sent_at,
                             'last_verified_webhook_run', (select max(started_at) from public.agent_runs
                                                            where agent = 'resend_webhook' and status = 'ok')),
          array['the canary was accepted by Resend (status sent, provider id recorded)'],
          array['whether Resend emitted the event (read GET /emails/<provider_message_id> last_event)',
                'whether the webhook is still registered and enabled, with the key and signing secret app_secrets holds'],
          'customer_support');
        v_out := jsonb_build_object('judged', c.id, 'arrived', false);
      else
        v_out := jsonb_build_object('waiting', c.id);
      end if;
    elsif c.status not in ('queued', 'pending') then
      update public.notifications set last_error = 'canary not judged: the outbox left it ' || coalesce(c.status, 'null') where id = c.id;
      v_out := jsonb_build_object('not_sent', c.id, 'status', c.status);
    end if;
  end if;

  -- ── one canary a day, only while real mail is going out ──
  if c.id is null or c.created_at < now() - interval '23 hours 50 minutes' then
    select count(*) into v_sends from public.notifications
     where status = 'sent' and sent_at > now() - interval '24 hours' and type <> 'delivery_feedback_canary';
    if v_sends > 0 then
      -- to_role 'system': not a customer, supplier or founder, so no WhatsApp twin, no language rewrite,
      -- no founder-mail policy and no digest applies; requested_by 'platform' keeps it out of the seats' loop.
      insert into public.notifications (type, to_email, to_role, channel, subject, body, lang, status, requested_by)
      values ('delivery_feedback_canary',
              'bounced+canary-' || to_char(now() at time zone 'UTC', 'YYYYMMDDHH24MI') || '@resend.dev',
              'system', 'email', 'Delivery feedback canary',
              'Daily check that bounce reports still reach resend_webhook. Sent to Resend''s bounce test sink; reaches no person.',
              'en', 'queued', 'platform')
      returning id into v_new;
      v_out := v_out || jsonb_build_object('queued', v_new, 'real_sends_24h', v_sends);
    end if;
  end if;
  return jsonb_build_object('ok', true) || v_out;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_delivery_request_outcome(p_request_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare q public.agent_actions; v_loop text;
begin
  select * into q from public.agent_actions where id = p_request_id and kind = 'handoff';
  if not found then return jsonb_build_object('state', 'missing', 'request_id', p_request_id); end if;
  v_loop := q.detail->>'loop';
  return jsonb_build_object('request_id', q.id, 'loop', v_loop,
    'state', case
      when v_loop in ('confirmed', 'retry_confirmed', 'handled_by_the_ladder', 'retry_handled_by_the_ladder') then 'reached'
      -- escalation_refused filed no report, so it reads as waiting and the 24-hour escalation takes over.
      when v_loop in ('escalated', 'retry_escalated') then 'failed'
      when v_loop in ('routed', 'stubbed', 'digested', 'cancelled', 'retry_routed', 'retry_stubbed', 'retry_digested', 'retry_cancelled') then 'ended'
      else 'waiting' end,
    'report_key', 'delivery_undelivered:' || coalesce(q.detail->>'retry_request_id', q.id::text),
    'fixture', q.detail::text ilike '%ZZ DEMO%'
               or coalesce(q.detail->'prepared'->>'to_email', q.detail->>'to_email', '') ilike '%@example.invalid');
end $function$


CREATE OR REPLACE FUNCTION public.fn_delivery_result_acts(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff' and detail->>'type' = 'delivery.result';
  if not found then raise exception 'fn_delivery_result_acts: % is not a delivery.result handoff', p_id; end if;
  return case when a.agent = 'sales_engineer' and a.detail->>'result' in ('proof_of_response', 'no_response_confirmation')
              then public.fn_sales_engineer_acts_on_handoff(p_id) else '{}'::jsonb end
         || public.fn_originator_checks_delivery(p_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_demand_forecast_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_method constant text := 'blended daily rate 0.6*r30 + 0.4*r90, times 30 / 90 days; searches projected separately, never added';
  v_rows int; v_acted int;
begin
  delete from public.demand_forecast where run_on = v_today;   -- a re-run the same day replaces its own rows
  delete from public.demand_search where searched_at < now() - interval '90 days';   -- nothing reads older rows

  with inq as (
    -- distinct: an inquiry's trades usually already contain its category's code, and must count once
    select i.created_at, array(select distinct t from unnest(coalesce(i.trades, '{}') || public.fn_taxonomy_trades_for(array[i.category])) t) as trades, i.emirate
      from public.inquiries i
      left join public.customers c on c.id = i.customer_id
     where i.created_at > now() - interval '90 days' and i.parent_inquiry_id is null
       -- DEMO IS NEVER DEMAND (a_demo_request_is_never_supply_gap_demand.sql): a request with no customer, or a
       -- fixture customer's (is_demo, ZZ DEMO name, @example.invalid email), never starts real recruitment
       and i.customer_id is not null and not coalesce(public.fn_seat_clock_customer_is_fixture(c), false)
  ), srch as (
    select s.searched_at as created_at, s.trades, s.emirate
      from public.demand_search s where s.searched_at > now() - interval '90 days' and s.source <> 'fixture'
  ), ev as (
    select 'i' as k, created_at, t as trade, emirate from inq, unnest(trades) t
    union all
    select 's', created_at, t, emirate from srch, unnest(trades) t
  ), ev2 as (                                  -- each event counts for its emirate and for the UAE roll-up
    select k, created_at, trade, emirate from ev where emirate is not null
    union all
    select k, created_at, trade, 'UAE' from ev
  ), agg as (
    select trade, emirate,
           count(*) filter (where k = 'i' and created_at > now() - interval '30 days')::int as i30,
           count(*) filter (where k = 'i')::int as i90,
           count(*) filter (where k = 's' and created_at > now() - interval '30 days')::int as s30,
           count(*) filter (where k = 's')::int as s90
      from ev2 group by trade, emirate
  )
  insert into public.demand_forecast (run_on, trade, emirate, inquiries_30d, inquiries_90d, searches_30d, searches_90d,
         forecast_30d, forecast_90d, searches_forecast_30d, searches_forecast_90d, method, sufficient_data, matchable, target)
  select v_today, a.trade, a.emirate, a.i30, a.i90, a.s30, a.s90,
         round((0.6 * a.i30 / 30.0 + 0.4 * a.i90 / 90.0) * 30, 1), round((0.6 * a.i30 / 30.0 + 0.4 * a.i90 / 90.0) * 90, 1),
         round((0.6 * a.s30 / 30.0 + 0.4 * a.s90 / 90.0) * 30, 1), round((0.6 * a.s30 / 30.0 + 0.4 * a.s90 / 90.0) * 90, 1),
         v_method || case when a.i90 < 10 then '; insufficient_data (' || a.i90 || ' inquiries in 90 days)' else '' end,
         a.i90 >= 10, g.matchable, g.target
    from agg a left join public.supply_gap g on g.trade = a.trade and g.emirate = a.emirate;
  get diagnostics v_rows = row_count;

  -- ACT: recruit ahead of forecast demand, on the supply-gap path the sales engineer already owns.
  with hit as (
    update public.supply_gap g set status = 'recruit', decided_by = 'rule:forecast_demand', decided_at = now()
      from public.demand_forecast f
     where f.run_on = v_today and f.trade = g.trade and f.emirate = g.emirate
       and g.matchable < g.target and g.status in ('open', 'deciding', 'deferred')
       and g.uninvited_pool > 0 and g.decided_by is distinct from 'rule:no_uninvited_leads'   -- nobody to invite: stays deferred
       and f.forecast_90d >= 1   -- real inquiries only: searches are anonymous and never start recruitment
    returning g.trade, g.emirate
  )
  update public.demand_forecast f set acted = 'supply_gap -> recruit (rule:forecast_demand)'
    from hit where f.run_on = v_today and f.trade = hit.trade and f.emirate = hit.emirate;
  get diagnostics v_acted = row_count;

  return jsonb_build_object('run_on', v_today, 'basis', 'estimate', 'method', v_method, 'rows', v_rows,
    'recruit_started', v_acted,
    'top', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
              select trade, emirate, forecast_30d, forecast_90d, searches_30d, sufficient_data from public.demand_forecast
               where run_on = v_today order by forecast_90d desc, searches_30d desc limit 10) x));
end $function$


CREATE OR REPLACE FUNCTION public.fn_demand_search_record(p_category text, p_emirate text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  insert into public.demand_search (category, trades, emirate)
  select p_category, public.fn_taxonomy_trades_for(array[p_category]),
         case when p_emirate in ('Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah') then p_emirate end
   where p_category ~ '^[a-z][a-z0-9_-]{1,59}$';
$function$


CREATE OR REPLACE FUNCTION public.fn_demo_and_real_never_pair()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_inq boolean; v_sup boolean;
begin
  v_inq := public.fn_inquiry_is_demo(NEW.inquiry_id);
  select coalesce(l.is_demo, false) into v_sup from public.leads l where l.id = NEW.supplier_id;
  if v_inq = coalesce(v_sup, false) then return NEW; end if;
  -- A match that must not exist is simply not recorded. customer_api and sales_engineer both read
  -- the landed rows back and report a missing one as refused, so the fanout stays honest.
  if TG_TABLE_NAME = 'inquiry_matches' then return null; end if;
  raise exception 'a % supplier cannot quote a % request (demo and real accounts never meet)',
    case when coalesce(v_sup, false) then 'demo' else 'real' end,
    case when v_inq then 'demo' else 'real' end
    using errcode = '23514';
end $function$


CREATE OR REPLACE FUNCTION public.fn_demo_purge(p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb;
begin
  if p_apply then return jsonb_build_object('mode', 'apply') || public.fn_demo_purge_run(); end if;
  begin
    v := public.fn_demo_purge_run();
    raise exception using errcode = 'QD199', message = v::text;
  exception when sqlstate 'QD199' then
    return jsonb_build_object('mode', 'plan') || sqlerrm::jsonb;
  end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_demo_purge_address(p_email text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_is_demo_email(p_email) or lower(btrim(coalesce(p_email, ''))) = any(public.fn_demo_purge_confirmed_logins()) $function$


CREATE OR REPLACE FUNCTION public.fn_demo_purge_confirmed_logins()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$ select array['ahmadmhdnabilalzain+qdprobe1@gmail.com', 'ahmadmhdnabilalzain+qdcust1@gmail.com']::text[] $function$


CREATE OR REPLACE FUNCTION public.fn_demo_purge_dropbox_paths()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$ select array[
  '/QuotesDone Backup/Customers/Ahmad Nabil Al Zain',
  '/QuotesDone Backup/Customers/QA Journey Tester',
  '/QuotesDone Backup/Customers/QA Portal Tester',
  '/QuotesDone Backup/Customers/QA Test Customer',
  '/QuotesDone Backup/Customers/QA Villa Owner',
  '/QuotesDone Backup/Customers/ahmad test',
  '/QuotesDone Backup/Customers/ahmad test 2',
  '/QuotesDone Backup/Customers/qa.portal.testquotesdone.com',
  '/QuotesDone Backup/_archive/demo-leftovers-2026-10-12/Suppliers/QD Demo Claimed Aluminium 0686',
  '/QuotesDone Backup/_archive/demo-leftovers-2026-10-12/Suppliers/QD Demo Claimed Aluminium 1755',
  '/QuotesDone Backup/_archive/demo-leftovers-2026-10-12/Suppliers/QD Demo Claimed Aluminium 1c4d',
  '/QuotesDone Backup/_archive/demo-leftovers-2026-10-12/Suppliers/QD Demo Claimed Aluminium e236',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/Ahmad Nabil Al Zain (dbb4e36f)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/Ahmed Al Mansoori (301a941f)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/Bara Al Zain (d38c4fac)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/DEMO — Sara Ahmed (657e47eb)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/Fatima Rahman (d52e1f20)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/John Peterson (16b28330)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/Layla Haddad (74a0d6f7)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/Layla Test (5e97a48c)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/Mohammed Iqbal (70683bb5)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/Noura Al Ali (65f309ea)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/QA Journey Tester (68abd9e3)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/QA Portal Tester (296c6bbd)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/QA Regression Owner (75bbef26)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/QA Test Customer (58371fbd)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/QA Test Customer (c5e47f2d)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/QA Villa Owner (424d48c3)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/QD DEMO Customer (cbfd972e)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/QuotesDone Test (191e9197)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/Rajesh Kumar (83e4b5fb)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/Sara Khalifa (8025bf05)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/ZZ DEMO - shared handset A (ccef2d0d)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/ZZ DEMO - shared handset B (91eeccf8)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/ZZ DEMO — section 8 probe customer A (6636916e)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/ZZ DEMO — section 8 probe customer B (1bfe4f47)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/__selftest__ctrl A (ae8d1a34)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/__selftest__ctrl B (05540815)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/ahmad (27cbbc0a)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/ahmad alzain (95e4345e)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/ahmad test (70f15bc3)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/ahmad test 2 (a6d900ab)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/ahmadsw (84a808ec)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/Interior fit-out/DEMO — BlueBay Contracting (30298)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/Interior fit-out/DEMO — Falcon Interiors LLC (30297)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/Other/ZZ TEST Expiry Harness (delete me) (30371)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/Uncategorized/MERIDIAN MEP CONTRACTING LLC (30466)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/Uncategorized/ZZ DEMO — section 8 probe supplier A (40466)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/Uncategorized/ZZ DEMO — section 8 probe supplier B (40467)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/Uncategorized/شركة اختبار المورّد (30346)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/ac-duct-cleaning/QA PureDuct Cleaning (30328)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/ac-maintenance/QA CoolCare HVAC (30327)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/aluminium-glass/QA ClearView Aluminium & Glass (30329)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/cctv-security/HARNESS_FIX Security (30349)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/cctv-security/QA SecureEye Systems (30330)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/cleaning/QA SparkleClean Services (30331)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/combined-mep/QD DEMO — Al Noor Technical Services LLC (30372)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/custom-furniture/QA Artisan Custom Furniture (30332)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/electrical/HARNESS_FIX Electrical (30348)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/electrical/HARNESS_FIX Electrical (30395)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/electrical/QA Volt Electrical Contracting (30325)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/electrical/VoltEdge Electrical Contracting LLC (30365)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/electrical/[QA] Gamma Electrical Works (30358)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/flooring/Emirates Prestige Flooring LLC (30361)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/flooring/Prestige Floors Contracting LLC (30362)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/flooring/QA Flooring Test Co (30355)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/flooring/QA TerraFloor Solutions (30333)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/flooring/Skyline Surfaces Interiors LLC (30363)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/flooring/[QA] Alpha Flooring LLC (30356)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/flooring/[QA] Beta Floors & More (30357)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/flooring/[QA] Regress Alpha Flooring (30359)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/flooring/[QA] Regress Beta Floors (30360)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/interior-design/HARNESS_FIX Fitout (30350)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/interior-design/[TEST] Falcon Fit-Out LLC (30296)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/joinery-kitchens/QA MasterWood Kitchens (30335)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/landscaping/HARNESS_FIX Landscaping (30351)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/painting/QA ProCoat Painting (30334)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/plumbing/AquaFix Plumbing Services LLC (30364)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/plumbing/QA AquaFlow Plumbing Works (30326)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/swimming-pools/HARNESS_FIX Pools (30347)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/swimming-pools/HARNESS_FIX Pools (30394)',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12/Suppliers/tiling-marble/QA StonePro Tiling & Marble (30336)'
]::text[] $function$


CREATE OR REPLACE FUNCTION public.fn_demo_purge_kept_leads()
 RETURNS bigint[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$ select array[143027]::bigint[] $function$


CREATE OR REPLACE FUNCTION public.fn_demo_purge_key_has_confirmed(p_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$ select exists (select 1 from unnest(public.fn_demo_purge_confirmed_logins()) a
  where lower(coalesce(p_key, '')) ~ ('(^|[^a-z0-9._%+-])' || regexp_replace(a, '([.+*?^$(){}|\[\]\\])', '\\\1', 'g') || '($|[^a-z0-9.-])')) $function$


CREATE OR REPLACE FUNCTION public.fn_demo_purge_real_counts()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'customers', (select count(*) from public.customers where not coalesce(is_demo, false)),
    'leads', (select count(*) from public.leads where not coalesce(is_demo, false)),
    'inquiries', (select count(*) from public.inquiries i where not public.fn_inquiry_is_demo(i.id)),
    'quotes', (select count(*) from public.quotes q where not public.fn_quote_is_demo(q.id)),
    'transactions', (select count(*) from public.transactions t where not public.fn_transaction_is_demo(t.id)),
    'auth_users', (select count(*) from auth.users u where not public.fn_is_demo_email(u.email) and not public.fn_is_demo_phone(u.phone)
                     and not lower(coalesce(u.email, '')) = any(public.fn_demo_purge_confirmed_logins())
                     and not exists (select 1 from public.customers c where c.id = u.id and c.is_demo)))
$function$


CREATE OR REPLACE FUNCTION public.fn_demo_purge_run()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_before jsonb := public.fn_demo_purge_real_counts(); v_after jsonb;
  c jsonb := '{}'::jsonb; v_pid bigint; v_obj int; v_dbx int; v_rec int; r record;
  EM constant text := '@([a-z0-9_-]+[.])*(example[.](com|net|org)|test|example|invalid|localhost)([^a-z0-9._-]|$)';
begin
  -- the demo id sets: markers only
  create temp table _dc on commit drop as select id from public.customers where is_demo;
  -- 143027 (Assurance Corps Co., a real sourced company) is never a demo id, whatever its flag reads
  create temp table _dl on commit drop as select id from public.leads where is_demo and id <> all(public.fn_demo_purge_kept_leads());
  create temp table _di on commit drop as select id from public.inquiries i where public.fn_inquiry_is_demo(i.id);
  create temp table _dq on commit drop as select id from public.quotes where inquiry_id in (select id from _di) or supplier_id in (select id from _dl);
  create temp table _dt on commit drop as select id from public.transactions
    where customer_id in (select id from _dc) or supplier_id in (select id from _dl) or inquiry_id in (select id from _di) or quote_id in (select id from _dq);
  create temp table _du on commit drop as select id from auth.users u
    where public.fn_is_demo_email(u.email) or public.fn_is_demo_phone(u.phone) or u.id in (select id from _dc)
       or lower(coalesce(u.email, '')) = any(public.fn_demo_purge_confirmed_logins());
  create temp table _dk on commit drop as
    select id::text k from _dc union select id::text from _dl union select id::text from _di
    union select id::text from _dq union select id::text from _dt;
  c := jsonb_build_object('demo_ids', jsonb_build_object('customers', (select count(*) from _dc), 'leads', (select count(*) from _dl),
         'inquiries', (select count(*) from _di), 'quotes', (select count(*) from _dq), 'transactions', (select count(*) from _dt),
         'auth_users', (select count(*) from _du)));

  insert into public.signup_purge (kind, subject_ref, missing) values ('demo_purge', 'founder ruling 1199', '{}') returning id into v_pid;

  -- storage: every object a demo row names, or whose path carries a marker, that storage actually holds
  insert into public.signup_purge_object (purge_id, bucket, path)
  select v_pid, o.bucket_id, o.name from storage.objects o
    join (
      select 'signed-terms' b, signed_terms_path p from public.customers where id in (select id from _dc)
      union select 'signed-terms', signed_terms_path from public.leads where id in (select id from _dl)
      union select 'supplier-docs', regexp_replace(unnest(array[license_doc_path, company_profile_doc_path, egr_doc_path, insurance_doc_path,
                     vat_doc_path, iso_doc_path, manufacturer_auth_doc_path] || coalesce(catalog_doc_paths, '{}'::text[])), '^supplier-docs/', '')
          from public.leads where id in (select id from _dl)
      union select 'drawing-files', drawing_file_path from public.inquiries where id in (select id from _di)
      union select 'drawing-files', unnest(drawing_redacted_paths) from public.inquiries where id in (select id from _di)
      union select 'quote-files', original_file_path from public.quotes where id in (select id from _dq)
      union select 'quote-files', original_file_path from public.quote_reviews where inquiry_id in (select id from _di) or supplier_id in (select id from _dl)
      union select bucket, path from public.documents where ref_table in ('inquiries', 'quotes', 'leads', 'customers', 'transactions') and ref_id in (select k from _dk)
      union select bucket, path from public.doc_backups where entity in ('customer', 'supplier', 'inquiry', 'quote', 'transaction') and entity_id in (select k from _dk)
      union select bucket, path from public.supplier_document_cache where supplier_id in (select id from _dl)
      union select pdf_bucket, pdf_path from public.quote_spec_hold where quote_id in (select id from _dq)
    ) x on x.b = o.bucket_id and x.p = o.name
  union
  select v_pid, o.bucket_id, o.name from storage.objects o
   where (o.bucket_id = 'drawing-files' and split_part(o.name, '/', 2) in (select k from _dk))
      or (o.bucket_id = 'supplier-docs' and split_part(o.name, '/', 2) in (select id::text from _dl))
      or (o.bucket_id = 'agent-docs' and exists (select 1 from _di where o.name like '%QD-' || upper(left(_di.id::text, 8)) || '-CMP%'))
      or (o.bucket_id not in ('brand', 'site', 'demo-assets', 'social-media', 'kb-import-assets', 'backups')
          and o.name ~* '(^|/)(zz[ _-]?demo([^a-z]|$)|__selftest__|_selftest/)')
  on conflict (bucket, path) do nothing;
  get diagnostics v_obj = row_count;

  -- Dropbox (review of #1348, coordinator 13 Oct 2026): ONLY the frozen, reviewed list (fn_demo_purge_dropbox_paths,
  -- the same paths as supabase/functions/dropbox_backup/demo_purge_paths.json) and the _sandbox/_selftest probe roots.
  -- No name pattern decides. Each backup record whose copy lies inside a listed path goes with it; a demo entity's
  -- copy anywhere else is NOT deleted from Dropbox and is named in the plan for a person to add to the list.
  create temp table _fp on commit drop as select unnest(public.fn_demo_purge_dropbox_paths()) p;
  insert into public.signup_purge_dropbox (purge_id, doc_backup_id, dropbox_file)
  select v_pid, d.id, d.dropbox_path from public.doc_backups d
   where d.dropbox_path is not null
     and (exists (select 1 from _fp where d.dropbox_path = _fp.p or starts_with(d.dropbox_path, _fp.p || '/'))
          or d.dropbox_path ~ '^/QuotesDone Backup/_(sandbox|selftest)/[^/]+/')
  on conflict (doc_backup_id) do nothing;
  get diagnostics v_dbx = row_count;
  insert into public.signup_purge_dropbox (purge_id, doc_backup_id, dropbox_file)
  select v_pid, null, f.p from (
      select p from _fp
      union select substring(dropbox_path from '^(/QuotesDone Backup/_(?:sandbox|selftest)/[^/]+)/') from public.doc_backups
       where dropbox_path ~ '^/QuotesDone Backup/_(sandbox|selftest)/[^/]+/'
      union select path from public.dropbox_files where path ~ '^/QuotesDone Backup/_(sandbox|selftest)/[^/]+$') f
   where f.p is not null
     and not exists (select 1 from public.signup_purge_dropbox s where s.dropbox_file = f.p and s.done_at is null);
  get diagnostics v_rec = row_count;
  v_dbx := v_dbx + v_rec;
  c := c || jsonb_build_object('dropbox_frozen_paths', (select jsonb_agg(p order by p) from _fp));
  -- a listed copy keeps its record until dropbox_backup has deleted the copy; a record with no copy goes now
  update public.doc_backups d set status = 'signup_purge_pending', claimed_at = null, claimed_by = null,
         error = 'demo data purged (founder ruling 1199): Dropbox copy and record to be deleted'
   where d.id in (select doc_backup_id from public.signup_purge_dropbox where purge_id = v_pid and doc_backup_id is not null);
  -- a demo record with no copy, or whose copy the live Dropbox listing (refreshed within 36 hours) no longer holds, has
  -- nothing in Dropbox to delete: the record goes now. Without a fresh listing such a record is kept and named.
  create temp table _dgone on commit drop as
  select d.id from public.doc_backups d
   where ((d.entity in ('customer', 'supplier', 'inquiry', 'quote', 'transaction') and d.entity_id in (select k from _dk))
          or d.entity = 'zz_demo' or d.dedupe_key like 'SBX:%')
     and d.id not in (select doc_backup_id from public.signup_purge_dropbox where purge_id = v_pid and doc_backup_id is not null)
     and (d.dropbox_path is null
          or ((select max(synced_at) from public.dropbox_files) > now() - interval '36 hours'
              and not exists (select 1 from public.dropbox_files f where lower(f.path) = lower(d.dropbox_path)
                                and f.synced_at > now() - interval '36 hours')));
  c := c || jsonb_build_object('dropbox_demo_copies_still_in_dropbox_outside_the_list', coalesce((select jsonb_agg(d.dropbox_path order by d.dropbox_path)
         from public.doc_backups d
        where ((d.entity in ('customer', 'supplier', 'inquiry', 'quote', 'transaction') and d.entity_id in (select k from _dk))
               or d.entity = 'zz_demo' or d.dedupe_key like 'SBX:%')
          and d.id not in (select doc_backup_id from public.signup_purge_dropbox where purge_id = v_pid and doc_backup_id is not null)
          and d.id not in (select id from _dgone)), '[]'::jsonb));
  c := public.fn_demo_purge_walk('public.doc_backups', 'id in (select id from _dgone)', 0, c);
  c := c || jsonb_build_object('storage_objects_listed', v_obj, 'dropbox_listed', v_dbx, 'purge_id', v_pid);

  -- the id-keyed and identity-keyed rows, while the ids are still known
  for r in select * from (values
    ('public.company_event', 'entity_type in (''customer'',''supplier'',''lead'',''inquiry'',''quote'',''transaction'',''refund'') and entity_id in (select k from _dk)'),
    ('public.agent_actions', 'target_table in (''customers'',''leads'',''suppliers'',''inquiries'',''quotes'',''transactions'') and target_id in (select k from _dk)'),
    ('public.doc_versions', 'entity_type in (''quote'',''rfq'',''inquiry'',''customer'',''lead'',''supplier'',''transaction'') and entity_id in (select k from _dk)'),
    ('public.documents', 'ref_table in (''inquiries'',''quotes'',''leads'',''customers'',''transactions'') and ref_id in (select k from _dk)'),
    ('public.quote_items', 'quote_id in (select id::text from _dq)'),
    ('public.notifications', 'public.fn_demo_purge_address(to_email) or public.fn_is_demo_phone(to_phone) or lead_id in (select id from _dl) or inquiry_id in (select id from _di) or quote_id in (select id from _dq)'),
    ('public.email_verifications', 'public.fn_demo_purge_address(email)'),
    ('public.phone_verifications', 'public.fn_demo_purge_address(email) or public.fn_is_demo_phone(phone)'),
    ('public.inquiry_intake', 'customer_id in (select id from _dc) or public.fn_demo_purge_address(email)'),
    ('public.drawing_redaction_runs', 'customer_id in (select id from _dc) or public.fn_demo_purge_address(owner_email)'),
    ('public.cad_read_jobs', 'customer_id in (select id from _dc) or public.fn_demo_purge_address(owner_email)'),
    ('public.support_case', 'public.fn_party_is_demo(party_kind, party_id)'),
    ('public.support_customer_profile', 'customer_id in (select id from _dc) or lead_id in (select id from _dl) or public.fn_demo_purge_address(email)'),
    ('public.customer_support_duty_message', 'customer_id in (select id from _dc) or lead_id in (select id from _dl) or public.fn_demo_purge_address(to_email)'),
    ('public.quote_reviews', 'inquiry_id in (select id from _di) or supplier_id in (select id from _dl) or public.fn_demo_purge_address(owner_email)'),
    ('public.quote_spec_hold', 'quote_id in (select id from _dq) or inquiry_id in (select id from _di) or supplier_id in (select id from _dl)'),
    ('public.supplier_score', 'lead_id in (select id from _dl)'),
    ('public.supplier_document_cache', 'supplier_id in (select id from _dl)'),
    ('public.wa_conversation', 'public.fn_is_demo_phone(phone_e164) or public.fn_party_is_demo(party_kind, party_id)'),
    ('public.wa_messages', 'public.fn_is_demo_phone(wa_from) or public.fn_is_demo_phone(wa_to)'),
    ('public.wa_inbound_seen', 'public.fn_is_demo_phone(wa_from)'),
    ('public.wa_answer_log', 'public.fn_is_demo_phone(from_phone)'),
    ('public.sms_messages', 'public.fn_is_demo_phone(sms_from) or public.fn_is_demo_phone(sms_to)'),
    ('public.email_suppressions', 'public.fn_demo_purge_address(email)'),
    -- pdpl_requests and pdpl_operator_log are NEVER purged: they are the evidence a data request was handled
    ('public.rl_hits', 'k ~* ''' || EM || ''' or public.fn_demo_purge_key_has_confirmed(k)'),
    ('public.ai_rate_limit', 'bucket ~* ''' || EM || ''' or public.fn_demo_purge_key_has_confirmed(bucket)'),
    ('public.assistant_logs', 'user_agent ~* ''(qd-[a-z-]*probe|latency-probe)'''),
    ('public.ai_cost_log', 'e2e_run_tag is not null'),
    ('public.rehearsal_window', 'run_tag like ''qd\_run:%'''),
    ('public.marketing_outreach_message', 'is_demo'),
    ('public.marketing_prospect', 'is_demo'),
    ('public.marketing_post', 'is_demo'),
    ('public.marketing_campaign', 'is_demo'),
    ('public.marketing_article', 'is_demo'),
    ('public.marketing_ad_spend_day', 'is_demo'),
    ('public.ad_campaign_state', 'is_demo'),
    ('public.social_conversation', 'is_demo'),
    -- the entities, children first through the walk
    ('public.transactions', 'id in (select id from _dt)'),
    ('public.quotes', 'id in (select id from _dq)'),
    ('public.inquiries', 'id in (select id from _di)'),
    ('public.customers', 'id in (select id from _dc)'),
    ('public.leads', 'id in (select id from _dl)'),
    ('auth.users', 'id in (select id from _du)')
  ) t(rel, w) loop
    continue when to_regclass(r.rel) is null;
    c := public.fn_demo_purge_walk(r.rel::regclass, r.w, 0, c);
  end loop;

  -- THE GUARD: nothing that is not demo may have moved
  v_after := public.fn_demo_purge_real_counts();
  if v_after is distinct from v_before then
    raise exception 'DEMO PURGE REFUSED: a real row would change. before % after %', v_before, v_after
      using errcode = 'QD198';
  end if;
  return c || jsonb_build_object('real_counts_unchanged', v_after);
end $function$


CREATE OR REPLACE FUNCTION public.fn_demo_purge_verify()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'customers', (select count(*) from public.customers where is_demo),
    'leads', (select count(*) from public.leads where is_demo),
    'inquiries', (select count(*) from public.inquiries i where public.fn_inquiry_is_demo(i.id)),
    'auth_users', (select count(*) from auth.users u where public.fn_is_demo_email(u.email) or public.fn_is_demo_phone(u.phone)
                     or lower(coalesce(u.email, '')) = any(public.fn_demo_purge_confirmed_logins())),
    'notifications', (select count(*) from public.notifications where public.fn_demo_purge_address(to_email) or public.fn_is_demo_phone(to_phone)),
    'confirmed_alias_leftovers', (select count(*) from public.email_verifications where public.fn_demo_purge_address(email))
                               + (select count(*) from public.phone_verifications where public.fn_demo_purge_address(email)),
    'ai_cost_log_tagged', (select count(*) from public.ai_cost_log where e2e_run_tag is not null),
    'rehearsal_windows', (select count(*) from public.rehearsal_window where run_tag like 'qd\_run:%'),
    'doc_backups', (select count(*) from public.doc_backups where entity = 'zz_demo' or dedupe_key like 'SBX:%'),
    'marketing_demo', (select count(*) from public.marketing_prospect where is_demo) + (select count(*) from public.marketing_post where is_demo)
                    + (select count(*) from public.marketing_campaign where is_demo) + (select count(*) from public.marketing_outreach_message where is_demo),
    'social_demo', (select count(*) from public.social_conversation where is_demo),
    'storage_queue_open', (select count(*) from public.signup_purge_object o join public.signup_purge p on p.id = o.purge_id
                            where p.kind = 'demo_purge' and o.done_at is null),
    'dropbox_queue_open', (select count(*) from public.signup_purge_dropbox o join public.signup_purge p on p.id = o.purge_id
                            where p.kind = 'demo_purge' and o.done_at is null))
$function$


CREATE OR REPLACE FUNCTION public.fn_demo_purge_walk(p_rel regclass, p_where text, p_depth integer, p_counts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare f record; v_n bigint; v_key text := p_rel::text; v_k text;
begin
  if p_depth > 8 then raise exception 'demo purge: foreign-key chain deeper than 8 at %', p_rel; end if;
  -- the data-request evidence is never walked into, by any route (release review of 2953dbf)
  if regexp_replace(v_key, '^.*[.]', '') ~* '^pdpl_' then raise exception 'DEMO PURGE REFUSED: % is data-request evidence', v_key using errcode = 'QD196'; end if;
  -- every child, cascading ones included, is walked here, so the plan names each table the purge touches
  for f in
    select c.conrelid::regclass child, a.attname col, pa.attname pcol, c.confdeltype del
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
      join pg_attribute pa on pa.attrelid = c.confrelid and pa.attnum = c.confkey[1]
     where c.contype = 'f' and c.confrelid = p_rel and c.conrelid <> p_rel and cardinality(c.conkey) = 1
  loop
    if f.del = 'n' then
      -- a SET NULL reference is unlinked, never deleted: that row is not the demo entity's own
      execute format('update %s set %I = null where %I in (select %I from %s where %s)', f.child, f.col, f.col, f.pcol, p_rel, p_where);
      get diagnostics v_n = row_count;
      v_k := f.child::text || ' (unlinked ' || f.col || ')';
      p_counts := jsonb_set(p_counts, '{touched}', coalesce(p_counts->'touched', '{}'::jsonb)
                    || jsonb_build_object(v_k, coalesce((p_counts->'touched'->>v_k)::bigint, 0) + v_n));
    else
      p_counts := public.fn_demo_purge_walk(f.child,
        format('%I in (select %I from %s where %s)', f.col, f.pcol, p_rel, p_where), p_depth + 1, p_counts);
    end if;
  end loop;
  execute format('delete from %s where %s', p_rel, p_where);
  get diagnostics v_n = row_count;
  -- the books are never purged: a demo row that reached a ledger table is reversed by the accountant first
  if v_n > 0 and regexp_replace(v_key, '^.*[.]', '') ~ '^(gl_|ledger|journal|supplier_dues|accountant_issued|reveal_invoices|refund|stripe_|payout|bank_|cash_|finance_)' then
    raise exception 'DEMO PURGE REFUSED: % demo row(s) reached the ledger table %; the accountant reverses them first', v_n, v_key
      using errcode = 'QD197';
  end if;
  p_counts := jsonb_set(p_counts, '{touched}', coalesce(p_counts->'touched', '{}'::jsonb)
                || jsonb_build_object(v_key, coalesce((p_counts->'touched'->>v_key)::bigint, 0) + v_n));
  return p_counts;
end $function$


CREATE OR REPLACE FUNCTION public.fn_dept_authority(p_dept text, p_action_class text, p_amount_aed numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v jsonb;
  v_tier text;
  v_reason text;
  v_avg numeric; v_measured int; v_probation int;
  v_capped boolean := false;
begin
  v := public.fn_ops_authority_check(p_dept, p_action_class, p_amount_aed, null);
  v_tier := v->>'effective_tier';
  v_reason := v->>'reason';

  -- The department's earned reputation: only employees with a measured tier count.
  select round(avg(r.score), 1), count(*), count(*) filter (where r.tier = 'probation')
    into v_avg, v_measured, v_probation
    from public.agent_reputation r
    join public.org_agents a on a.agent_key = r.agent_key
   where a.active and a.department = p_dept and r.tier <> 'unmeasured' and r.score is not null;

  if v_tier = 'autonomous' and coalesce(v_measured, 0) > 0 and v_avg < 50 then
    v_tier := 'supervised';
    v_capped := true;
    v_reason := format('capped by reputation: %s measured employee(s) in %s average %s, below the '
                       || 'probation line of 50, so autonomous work runs supervised until the '
                       || 'department earns it back (%s)', v_measured, p_dept, v_avg, v_reason);
  end if;

  return jsonb_build_object(
    'dept', p_dept,
    'action_class', p_action_class,
    'tier', v_tier,
    'threshold_aed', (v->>'threshold_aed')::numeric,
    'capped', coalesce(v->>'production_tier', 'gated') is distinct from v_tier,
    'capped_by_reputation', v_capped,
    'reputation', jsonb_build_object('avg_score', v_avg, 'measured', coalesce(v_measured, 0),
                                     'on_probation', coalesce(v_probation, 0)),
    'reviewed', (v->>'reviewed')::boolean,
    'reason', v_reason);
end $function$


CREATE OR REPLACE FUNCTION public.fn_dept_canonical(p_dept text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select d.merged_into from public.org_departments d
      where d.dept_key = p_dept and d.merged_into is not null),
    p_dept);
$function$


CREATE OR REPLACE FUNCTION public.fn_dept_decision_thresholds(p_dept text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with keys as (
    select k, ord from unnest(case p_dept
      when 'marketplace' then array['match_relevance_floor','match_max_fanout','match_max_fanout_per_trade','score_w_product','score_w_brand','score_w_project_type','score_w_size_fit','score_w_track_record','matching_strike_limit','sensitive_categories','confidence_min','fraud_score_max','use_capability_matching']
      when 'supply' then array['matching_strike_limit','match_relevance_floor','match_max_fanout','match_max_fanout_per_trade','score_w_track_record','sensitive_categories','confidence_min','fraud_score_max']
      when 'finance' then array['financial_review_aed','auto_action_max_aed','refund_reveal_fee_pct','refund_admin_fee_aed','refund_late_fee_annual_pct','refund_notify_after_working_days','refund_call_after_working_days','refund_claim_after_call_working_days','founder_review_gates','confidence_min']
      when 'customer_experience' then array['refund_notify_after_working_days','refund_call_after_working_days','refund_claim_after_call_working_days','refund_reveal_fee_pct','refund_admin_fee_aed','founder_review_gates','legal_triggers','confidence_min']
      when 'legal' then array['fraud_score_max','legal_triggers','founder_review_gates','financial_review_aed','sensitive_categories','confidence_min']
      when 'exec' then array['financial_review_aed','auto_action_max_aed','founder_review_gates','confidence_min','fraud_score_max']
      when 'growth' then array['confidence_min','legal_triggers','sensitive_categories','founder_review_gates']
      else array['confidence_min','fraud_score_max','founder_review_gates'] end) with ordinality as u(k, ord))
  select '# YOUR THRESHOLDS (decision_policy, live - these are the numbers the deterministic gates enforce; reason with THESE, never with a remembered figure)'||E'\n'
      || left(string_agg('- '||p.key||' = '||left(p.value::text, 120)
                         ||coalesce(' ('||left(regexp_replace(p.description, '\s+', ' ', 'g'), 80)||')', ''), E'\n' order by keys.ord), 1500)
    from keys join public.decision_policy p on p.key = keys.k;
$function$


CREATE OR REPLACE FUNCTION public.fn_dept_library_search(p_dept text, p_query text, p_limit integer DEFAULT 5)
 RETURNS TABLE(id bigint, department text, title text, content text, rank real)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare q_or tsquery; words text[];
begin
  words := array(select w from unnest(regexp_split_to_array(lower(regexp_replace(coalesce(p_query,''),'[^a-z0-9 ]',' ','g')),'\s+')) w where length(w)>2);
  if array_length(words,1) is null then return; end if;
  begin q_or := to_tsquery('english', array_to_string(words,' | ')); exception when others then return; end;
  return query
    select l.id, l.department, l.title, l.content, ts_rank(l.tsv, q_or) as rank
    from dept_library l
    where (p_dept is null or l.department = p_dept) and l.tsv @@ q_or
    order by ts_rank(l.tsv, q_or) desc, l.id
    limit greatest(1, least(coalesce(p_limit,5),20));
end $function$


CREATE OR REPLACE FUNCTION public.fn_dept_module_scope(p_dept text)
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(array(select a.alias_key from public.dept_knowledge_alias a
                         where a.dept_key = p_dept and a.alias_kind = 'module'), '{}'::text[]);
$function$


CREATE OR REPLACE FUNCTION public.fn_dept_scope(p_dept text)
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select array(select p_dept
               union
               select d.dept_key from public.org_departments d where d.merged_into = p_dept
               union
               select a.alias_key from public.dept_knowledge_alias a where a.dept_key = p_dept and a.alias_kind = 'dept');
$function$


CREATE OR REPLACE FUNCTION public.fn_derive_supplier_registration_state()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_fee numeric; v_start date; v_free int;
begin
  -- Only registered suppliers carry a registration state. The other ~20k scraped listings are
  -- left completely untouched so bulk maintenance on leads stays cheap.
  if coalesce(new.claimed,false) is not true and new.founding_rank is null then
    return new;
  end if;

  select coalesce(p.supplier_reg_fee,1000), p.supplier_charging_starts, coalesce(p.supplier_free_count,1000)
    into v_fee, v_start, v_free from public.pricing_config p where p.id = 1;
  v_fee := coalesce(v_fee,1000); v_free := coalesce(v_free,1000);

  if coalesce(new.subscription_exempt,false) then
    new.registration_status := 'exempt'; new.registration_fee_due := 0;
  elsif new.subscription_paid_until is not null and new.subscription_paid_until >= current_date then
    new.registration_status := 'paid'; new.registration_fee_due := 0;
  elsif v_start is not null and current_date < v_start then
    new.registration_status := 'not_due'; new.registration_fee_due := 0;
  elsif v_start is null and (new.founding_rank is null or new.founding_rank <= v_free) then
    -- 6 Sep 2026 (founder): no calendar start. Charging begins with the registration after the free
    -- count; a rank not yet stamped, or inside the free count, owes nothing.
    new.registration_status := 'not_due'; new.registration_fee_due := 0;
  else
    new.registration_status := 'due'; new.registration_fee_due := v_fee;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_dispatch_agent_knowledge_gaps(p_stale_days integer DEFAULT 14, p_thin_min integer DEFAULT 4)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare a jsonb; g jsonb; opened int := 0; resolved_before int; resolved_after int; total_gap int := 0;
begin
  g := fn_knowledge_gaps(p_stale_days, p_thin_min);
  select count(*) into resolved_before from agent_actions where kind='knowledge_task' and detail->>'signal' like 'agent_knowledge:%' and status in ('pending','needs_review');
  for a in select * from jsonb_array_elements(g->'agents') loop
    declare v_gap boolean := (a->>'status') in ('stale','thin'); v_slug text := a->>'slug';
    begin
      if v_gap then total_gap := total_gap + 1; end if;
      perform kn_task('agent_knowledge:'||v_slug, v_gap, case when (a->>'status')='thin' then 'low' else 'medium' end,
        'Refresh knowledge: '||coalesce(a->>'name',v_slug),
        coalesce(a->>'name',v_slug)||' has '||coalesce(a->>'items','0')||' knowledge item(s), last refreshed '||
        coalesce((a->>'days_stale')||' days ago','never')||' (status: '||(a->>'status')||'). Regenerate its field brief so it advises with current expertise. Auto-closes once refreshed.',
        jsonb_build_array(
          'Item count and refresh date measure the SHELF, not the reading. '||coalesce(a->>'name',v_slug)||' could hold a large, fresh brief it never retrieves and look identical here to one that reads it on every call.',
          'The thresholds are chosen, not derived: under '||p_thin_min||' item(s) is "thin" and '||p_stale_days||' day(s) is "stale". An agent whose field genuinely changes twice a year is stale here every fortnight.',
          '"Regenerate" assumes the source material has moved on. Regenerating against an unchanged world produces a new date and the same knowledge, which closes this task without improving anything.',
          coalesce(a->>'name',v_slug)||' is doing work worth briefing. An agent that has never run is stale in exactly the same way as one that runs hourly.'),
        coalesce(a->>'name',v_slug)||' currently advises from '||coalesce(a->>'items','0')||' item(s) last refreshed '||coalesce((a->>'days_stale')||' days ago','never')||'. Refreshing changes what it tells suppliers and customers; leaving it means confident advice from a stale field brief, which does not fail visibly.',
        'Model spend, one generation per agent. The cheap failure is regenerating everything on a schedule; the expensive one is an agent quoting last quarter''s rules to a customer.');
    end;
  end loop;
  select count(*) into resolved_after from agent_actions where kind='knowledge_task' and detail->>'signal' like 'agent_knowledge:%' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at', now(), 'gaps_found', total_gap, 'open_tasks', resolved_after,
    'summary', g->'summary');
end $function$


CREATE OR REPLACE FUNCTION public.fn_doc_backups_next(p_limit integer DEFAULT 8, p_run text DEFAULT NULL::text, p_demo boolean DEFAULT false)
 RETURNS SETOF doc_backups
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(btrim(p_run), '') = '' then raise exception 'fn_doc_backups_next: p_run (the claiming run id) is required'; end if;
  update public.doc_backups d set status = 'pending', claimed_at = null, claimed_by = null,
         error = left('claim by ' || coalesce(d.claimed_by, '?') || ' expired after 10 minutes; requeued', 300)
   where d.status = 'processing' and d.claimed_at < now() - interval '10 minutes';
  update public.doc_backups d set status = 'pending', error = null
   where d.status = 'waiting_source'
     and exists (select 1 from storage.objects o where o.bucket_id = d.bucket and o.name = d.path);
  return query
    with c as (
      select d.id from public.doc_backups d
       where d.status in ('pending', 'error') and d.attempts < 5
         and (d.entity = 'zz_demo') = coalesce(p_demo, false)
         and (d.status = 'pending' or d.last_attempt_at is null
              or d.last_attempt_at < now() - interval '1 minute' * power(2, least(d.attempts, 8)))
       order by (d.upload_state is not null) desc, d.id
       limit greatest(1, least(coalesce(p_limit, 8), 25))
       for update skip locked)
    update public.doc_backups d set status = 'processing', claimed_at = now(), claimed_by = p_run
      from c where d.id = c.id
    returning d.*;
end $function$


CREATE OR REPLACE FUNCTION public.fn_doc_backups_prune_done(p_results jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r jsonb; n_ok int := 0; n_fail int := 0;
begin
  for r in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    if (r->>'ok')::boolean then
      update public.doc_backups d set status = 'pruned', status_before_prune = null, claimed_at = null, claimed_by = null,
             error = null, last_attempt_at = now()
       where d.id = (r->>'id')::bigint and d.status = 'pruning';
      if not found then
        -- the day was cancelled while this delete was in flight: the Dropbox copy is gone but the rules keep
        -- it, so the row goes back to the upload queue and says why (the uploader re-files it from storage)
        update public.doc_backups d set status = 'pending', status_before_prune = null, backed_up_at = null, verified_at = null,
               dropbox_content_hash = null, dropbox_size = null,
               error = 'deleted from Dropbox after its retention deletion was cancelled; re-filed'
         where d.id = (r->>'id')::bigint and d.status not in ('pruned', 'prune_pending', 'pruning');
      end if;
      n_ok := n_ok + 1;
    else
      update public.doc_backups d set status = 'prune_pending', claimed_at = null, claimed_by = null,
             prune_attempts = d.prune_attempts + case when r->>'error' = 'deadline' then 0 else 1 end,
             error = left('prune: ' || coalesce(r->>'error', 'unknown'), 300), last_attempt_at = now()
       where d.id = (r->>'id')::bigint and d.status = 'pruning';
      n_fail := n_fail + 1;
    end if;
  end loop;
  update public.backup_prune_log l set dropbox_done_at = now()
   where l.mode = 'delete' and l.cancelled_at is null and l.dropbox_done_at is null
     and not exists (select 1 from public.doc_backups b
                      where b.dedupe_key like 'EXPORT:' || to_char(l.day, 'YYYY-MM-DD') || '/%' and b.status <> 'pruned');
  return jsonb_build_object('deleted', n_ok, 'failed', n_fail);
end $function$


CREATE OR REPLACE FUNCTION public.fn_doc_backups_prune_next(p_limit integer DEFAULT 25, p_run text DEFAULT NULL::text)
 RETURNS SETOF doc_backups
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(btrim(p_run), '') = '' then raise exception 'fn_doc_backups_prune_next: p_run (the claiming run id) is required'; end if;
  if public.fn_backup_prune_mode() <> 'delete' then return; end if;
  -- the rules again, before a single Dropbox path is handed over; a cancelled day's rows revert here
  perform public.fn_backup_prune_recheck();
  update public.doc_backups d set status = 'prune_pending', claimed_at = null, claimed_by = null
   where d.status = 'pruning' and d.claimed_at < now() - interval '10 minutes';
  return query
    with c as (
      select d.id from public.doc_backups d
       where d.status = 'prune_pending' and d.prune_attempts < 5
         and public.fn_backup_prune_dropbox_allowed(d.bucket, d.path, d.dedupe_key, d.doc_type, d.dropbox_path)
         -- 15 Sep 2026 (the guard): a Dropbox copy is claimed for deletion only once its day's storage
         -- deletion finished, and only a copy that was verified when it was uploaded
         and d.verified_at is not null
         and exists (select 1 from public.backup_prune_log bl
                      where bl.mode = 'delete' and bl.cancelled_at is null and bl.storage_deleted_at is not null
                        and d.dedupe_key like 'EXPORT:' || to_char(bl.day, 'YYYY-MM-DD') || '/%')
         and (d.last_attempt_at is null or d.prune_attempts = 0
              or d.last_attempt_at < now() - interval '1 minute' * power(2, least(d.prune_attempts, 8)))
       order by d.id limit greatest(1, least(coalesce(p_limit, 25), 25))
       for update skip locked)
    update public.doc_backups d set status = 'pruning', claimed_at = now(), claimed_by = p_run
      from c where d.id = c.id
    returning d.*;
end $function$


CREATE OR REPLACE FUNCTION public.fn_doc_backups_sandbox_next(p_tag text, p_limit integer, p_run text)
 RETURNS SETOF doc_backups
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(p_tag, '') !~ '^[A-Za-z0-9-]{6,40}$' then raise exception 'fn_doc_backups_sandbox_next: bad tag %', p_tag; end if;
  if coalesce(btrim(p_run), '') = '' then raise exception 'fn_doc_backups_sandbox_next: p_run is required'; end if;
  update public.doc_backups d set status = 'pending', claimed_at = null, claimed_by = null,
         error = left('claim by ' || coalesce(d.claimed_by, '?') || ' expired after 10 minutes; requeued', 300)
   where d.entity = 'zz_demo' and d.dedupe_key like 'SBX:' || p_tag || ':%'
     and d.status = 'processing' and d.claimed_at < now() - interval '10 minutes';
  update public.doc_backups d set status = 'pending', error = null
   where d.entity = 'zz_demo' and d.dedupe_key like 'SBX:' || p_tag || ':%' and d.status = 'waiting_source'
     and exists (select 1 from storage.objects o where o.bucket_id = d.bucket and o.name = d.path);
  return query
    with c as (
      select d.id from public.doc_backups d
       where d.entity = 'zz_demo' and d.dedupe_key like 'SBX:' || p_tag || ':%'
         and d.status in ('pending', 'error') and d.attempts < 5
         and (d.status = 'pending' or d.last_attempt_at is null
              or d.last_attempt_at < now() - interval '1 minute' * power(2, least(d.attempts, 8)))
       order by (d.upload_state is not null) desc, d.id
       limit greatest(1, least(coalesce(p_limit, 8), 25))
       for update skip locked)
    update public.doc_backups d set status = 'processing', claimed_at = now(), claimed_by = p_run
      from c where d.id = c.id
    returning d.*;
end $function$


CREATE OR REPLACE FUNCTION public.fn_doc_final_notice(p_days integer DEFAULT 7)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  rec record; v_email int := 0; v_wa int := 0; v_skipped int := 0;
  v_horizon date := current_date + make_interval(days => p_days);
  v_to text; v_label text; v_exp date;
begin
  for rec in
    select id, company_name, claimed_by, email, license_expiry, insurance_expiry
      from leads
     where approval_status = 'approved'
       and coalesce(banned,false) = false
       and coalesce(matching_blocked,false) = false
       and ((license_expiry   is not null and license_expiry   between current_date and v_horizon)
         or (insurance_expiry is not null and insurance_expiry between current_date and v_horizon))
  loop
    -- Whichever gating document expires first is the one we lead with.
    if rec.license_expiry is not null and rec.license_expiry between current_date and v_horizon
       and (rec.insurance_expiry is null or rec.license_expiry <= rec.insurance_expiry) then
      v_label := 'trade licence'; v_exp := rec.license_expiry;
    else
      v_label := 'insurance certificate'; v_exp := rec.insurance_expiry;
    end if;

    -- One final notice per document per expiry cycle. Without this the daily cron would send
    -- the same warning seven days running.
    if exists (select 1 from notifications
                where type = 'doc_final_notice' and lead_id = rec.id
                  and subject like '%' || v_label || '%'
                  and created_at > now() - interval '20 days') then
      v_skipped := v_skipped + 1; continue;
    end if;

    v_to := nullif(trim(coalesce(rec.claimed_by, rec.email)), '');
    if v_to is null or position('@' in v_to) = 0 then v_skipped := v_skipped + 1; continue; end if;

    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_final_notice', v_to, 'supplier', rec.id, 'email',
      'Final reminder: your ' || v_label || ' expires on ' || v_exp,
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Your ' || v_label || ' on file with QuotesDone expires on ' || v_exp || '.' || chr(10) || chr(10) ||
      'If we do not have a valid copy by then, your account will be paused automatically and you will stop receiving customer requests until it is renewed. This is temporary and there is no fee to restore it.' || chr(10) || chr(10) ||
      'Two ways to fix it, either is fine:' || chr(10) ||
      '  1. Reply to this email with the renewed document attached. Our system reads it and updates your profile automatically.' || chr(10) ||
      '  2. Upload it in the Documents tab of your supplier portal: https://quotesdone.com/portal' || chr(10) || chr(10) ||
      'If you have already renewed, please send us the latest copy so our records match.',
      'queued');
    v_email := v_email + 1;

    -- WhatsApp is the fan-out twin of that email (confirmed number only, approved
    -- supplier_doc_expiry template). A second row of our own would be a duplicate message.
    if exists (select 1 from notifications n
                where n.lead_id = rec.id and n.type = 'doc_final_notice' and n.channel = 'whatsapp'
                  and n.created_at >= now()) then
      v_wa := v_wa + 1;
    end if;
  end loop;

  return json_build_object('emails_queued', v_email, 'whatsapp_queued', v_wa,
                           'skipped', v_skipped, 'days_ahead', p_days,
                           'whatsapp_note', 'WhatsApp goes only as the fan-out twin to a confirmed number, on the approved supplier_doc_expiry template.',
                           'ran_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_document_classify(p_caption text, p_path text, p_declared text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_cap text := lower(coalesce(p_caption, '') || ' ' || coalesce(p_path, ''));
begin
  -- A DECLARED TYPE BEATS A GUESS. The portal has a dropdown; when the uploader has told us what the
  -- file is, reading the filename instead would be replacing knowledge with inference.
  if p_declared in ('licence','profile','signed_terms') then
    return jsonb_build_object('kind', p_declared, 'by', 'declared', 'confidence', 'high');
  end if;
  if v_cap ~ '(trade|licence|license|رخصة|رخصه)' then
    return jsonb_build_object('kind', 'licence', 'by', 'caption', 'confidence', 'high');
  elsif v_cap ~ '(profile|company profile|brochure|ملف|بروفايل)' then
    return jsonb_build_object('kind', 'profile', 'by', 'caption', 'confidence', 'high');
  elsif v_cap ~ '(terms|t&c|agreement|signed|شروط|اتفاقية)' then
    return jsonb_build_object('kind', 'signed_terms', 'by', 'caption', 'confidence', 'high');
  end if;
  return jsonb_build_object('kind', 'unknown', 'by', 'caption', 'confidence', 'low');
end $function$


CREATE OR REPLACE FUNCTION public.fn_dropbox_backup_daily_report()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_local timestamp := now() at time zone 'Asia/Dubai'; s jsonb;
begin
  if v_local::time < time '19:00' then
    return jsonb_build_object('filed', false, 'reason', 'before 19:00 Asia/Dubai');
  end if;
  if exists (select 1 from public.support_ceo_report
              where idempotency_key = 'dropbox_backup_daily:' || to_char(v_local, 'YYYY-MM-DD')) then
    return jsonb_build_object('filed', false, 'reason', 'already filed today');
  end if;
  s := public.fn_dropbox_backup_summary();
  return public.fn_support_report_to_ceo(
    'dropbox_backup_daily:' || to_char(v_local, 'YYYY-MM-DD'),
    case when (s->>'failed')::int > 0 or (s->>'never_queued')::int > 0 or (s->>'open_handoffs')::int > 0 then 'elevated' else 'routine' end,
    'Dropbox backup ' || to_char(v_local, 'DD Mon') || ': ' || (s->>'line'),
    s, '[]'::jsonb,
    'Note the day''s backup position. NOTHING IS REQUESTED: this is the IT engineer''s daily confirmation. A case still failing after two refiles or 48 hours reaches you separately, as a serious report.',
    p_review_in => interval '1 day', p_source_agent => 'it_engineer') || jsonb_build_object('filed', true);
end $function$


CREATE OR REPLACE FUNCTION public.fn_dropbox_backup_due()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'due', (not exists (
              select 1 from public.agent_runs r
               where r.agent = 'dropbox_backup' and r.status = 'ok'
                 and (r.started_at at time zone 'Asia/Dubai')::date
                     = (now() at time zone 'Asia/Dubai')::date))
           or exists (
              select 1 from public.doc_backups d
               where d.status in ('pending','error') and coalesce(d.attempts,0) < 5),
    'local_date', (now() at time zone 'Asia/Dubai')::date,
    'ran_today', exists (
              select 1 from public.agent_runs r
               where r.agent = 'dropbox_backup' and r.status = 'ok'
                 and (r.started_at at time zone 'Asia/Dubai')::date
                     = (now() at time zone 'Asia/Dubai')::date),
    'queued', (select count(*) from public.doc_backups d
                where d.status in ('pending','error') and coalesce(d.attempts,0) < 5));
$function$


CREATE OR REPLACE FUNCTION public.fn_dropbox_backup_summary()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with e as (select * from public.fn_it_backup_expected_status()),
  ex as (
    select count(*) as expected,
           count(*) filter (where status = 'done') as backed_up,
           count(*) filter (where status = 'done' and verified_at is not null) as verified,
           count(*) filter (where doc_backup_id is null) as never_queued
      from e),
  f as (
    select
      count(*) filter (where created_at > now() - interval '24 hours')                  as queued_24h,
      count(*) filter (where backed_up_at > now() - interval '24 hours')                as uploaded_24h,
      count(*) filter (where verified_at > now() - interval '24 hours')                 as verified_24h,
      count(*) filter (where status in ('pending','error') and coalesce(attempts,0) < 5) as pending,
      count(*) filter (where status = 'done')                                           as uploaded_total,
      count(*) filter (where status = 'done' and verified_at is not null)               as verified_total,
      count(*) filter (where (status = 'error' and attempts >= 5) or status = 'skipped_large') as failed,
      count(*) filter (where status = 'abandoned')                                      as abandoned,
      count(*)                                                                          as total
    from public.doc_backups where entity <> 'zz_demo'),
  h as (select count(*) as open_handoffs from public.agent_actions
         where kind = 'handoff' and status = 'pending' and detail->>'type' in ('backup.refile','backup.remediate'))
  select to_jsonb(ex) || to_jsonb(f) || to_jsonb(h) || jsonb_build_object('line',
    'Dropbox backup: ' || ex.expected || ' expected, ' || ex.backed_up || ' backed up, ' || ex.verified || ' verified in Dropbox, '
    || ex.never_queued || ' never queued; queue ' || f.pending || ' pending, ' || f.failed || ' failed, '
    || h.open_handoffs || ' open refile handoff(s). Last 24h: ' || f.queued_24h || ' queued, ' || f.uploaded_24h || ' uploaded, '
    || f.verified_24h || ' verified. All rows: ' || f.uploaded_total || ' uploaded (' || f.verified_total || ' verified), '
    || f.abandoned || ' abandoned with a recorded reason, of ' || f.total || '.',
    'measured_at', now())
  from ex, f, h;
$function$


CREATE OR REPLACE FUNCTION public.fn_dropbox_files_refresh(p_root text, p_rows jsonb, p_stamp timestamp with time zone, p_final boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_up integer := 0; v_rm integer := 0;
begin
  if coalesce(p_root, '') !~ '^/QuotesDone Backup/[^/]' or p_stamp is null then
    raise exception 'fn_dropbox_files_refresh: a root under /QuotesDone Backup/ and the walk stamp are required';
  end if;
  insert into public.dropbox_files (dropbox_id, path, name, is_folder, size, content_hash, server_modified, synced_at)
  select r->>'id', r->>'path', r->>'name', false, (r->>'size')::bigint, r->>'hash', (r->>'modified')::timestamptz, p_stamp
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
   where coalesce(r->>'id', '') <> '' and starts_with(lower(r->>'path'), lower(p_root) || '/')
  on conflict (dropbox_id) do update set path = excluded.path, name = excluded.name, size = excluded.size,
        content_hash = excluded.content_hash, server_modified = excluded.server_modified, synced_at = excluded.synced_at;
  get diagnostics v_up = row_count;
  if p_final then
    delete from public.dropbox_files f where starts_with(lower(f.path), lower(p_root) || '/') and f.synced_at < p_stamp;
    get diagnostics v_rm = row_count;
  end if;
  return jsonb_build_object('upserted', v_up, 'removed', v_rm);
end $function$


CREATE OR REPLACE FUNCTION public.fn_dropbox_list(p_prefix text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'prefix', p_prefix,
    'items', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.is_folder desc, lower(t.name))
      from (
        select id, path, name, is_folder, size, server_modified
        from dropbox_files
        where substring(path, 1, length(path) - length(split_part(path,'/', -1)) - 1) = p_prefix
      ) t
    ), '[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_dropbox_queue_stale(p_hours integer DEFAULT 3, p_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_hours integer := greatest(coalesce(p_hours, 3), 1);
  v_duty text := case when coalesce(p_demo, false) then 'dropbox_queue_zz_demo' else 'dropbox_queue' end;
  v_n integer; v_oldest timestamptz; v_ids jsonb; v_items jsonb := '[]'::jsonb;
begin
  select count(*), min(coalesce(d.requeued_at, d.created_at)),
         coalesce(jsonb_agg(d.id order by d.id) filter (where d.rn <= 20), '[]'::jsonb)
    into v_n, v_oldest, v_ids
    from (select b.*, row_number() over (order by b.id) rn from public.doc_backups b
           where b.status in ('pending', 'error') and coalesce(b.attempts, 0) < 5
             and (b.entity = 'zz_demo') = coalesce(p_demo, false)
             and coalesce(b.requeued_at, b.created_at) < now() - make_interval(hours => v_hours)) d;
  if v_n > 0 then
    v_items := jsonb_build_array(jsonb_build_object(
      'item', 'stale_pending',
      'title', left(format('%s Dropbox backup row(s) still queued after %s hours (oldest queued %s)',
                           v_n, v_hours, to_char(v_oldest at time zone 'UTC', 'YYYY-MM-DD HH24:MI "UTC"')), 300),
      'owner_seat', 'it_engineer', 'subject', 'dropbox_backup', 'demo', coalesce(p_demo, false),
      'affected', v_n,
      'evidence', jsonb_build_object('hours', v_hours, 'count', v_n, 'oldest_queued_at', v_oldest, 'first_ids', v_ids,
        'why', 'nothing is draining the doc_backups queue: check resilience_ping backupTick, fn_backup_kick and the dropbox_backup edge log')));
  end if;
  return public.fn_it_duty_settle(v_duty, v_items)
         || jsonb_build_object('stale', v_n, 'hours', v_hours, 'oldest_queued_at', v_oldest);
end $function$


CREATE OR REPLACE FUNCTION public.fn_dropbox_reconcile_apply(p_results jsonb, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_it_backup_check(p_results, 'dropbox_daily_check', p_error);
$function$


CREATE OR REPLACE FUNCTION public.fn_dropbox_reconcile_due()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'due', not exists (select 1 from public.agent_runs r
                        where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_daily_check' and r.status in ('ok', 'warn')
                          and (r.started_at at time zone 'Asia/Dubai')::date = (now() at time zone 'Asia/Dubai')::date)
       and not exists (select 1 from public.agent_runs r
                        where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_daily_check'
                          and r.status = 'error' and r.started_at > now() - interval '6 hours'),
    'day', (now() at time zone 'Asia/Dubai')::date,
    'weekly_due', public.fn_dropbox_weekly_due());
$function$


CREATE OR REPLACE FUNCTION public.fn_dropbox_reconcile_sample(p_n integer DEFAULT 20)
 RETURNS TABLE(id bigint, dropbox_path text, bucket text, path text, bytes bigint, dropbox_content_hash text, why text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  (select d.id, d.dropbox_path, d.bucket, d.path, d.bytes, d.dropbox_content_hash, 'new'
     from public.doc_backups d
    where d.status = 'done' and d.verified_at is null and d.dropbox_path is not null and d.entity <> 'zz_demo'
    order by d.backed_up_at desc nulls last limit 40)
  union all
  (select d.id, d.dropbox_path, d.bucket, d.path, d.bytes, d.dropbox_content_hash, 'weekly'
     from public.doc_backups d
    where public.fn_dropbox_weekly_due()
      and d.status = 'done' and d.verified_at is not null and d.dropbox_path is not null and d.entity <> 'zz_demo'
    order by random() limit greatest(1, least(coalesce(p_n, 20), 200)));
$function$


CREATE OR REPLACE FUNCTION public.fn_dropbox_weekly_due()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select not exists (select 1 from public.agent_runs r
                      where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_daily_check' and r.counts->>'weekly' = 'true'
                        and to_char(r.started_at at time zone 'Asia/Dubai', 'IYYY-IW') = to_char(now() at time zone 'Asia/Dubai', 'IYYY-IW'));
$function$


CREATE OR REPLACE FUNCTION public.fn_duty_pause_stakes(p_duty text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when coalesce((select sd.owner_seat from public.seat_duty sd where sd.duty = p_duty), split_part(p_duty, '.', 1)) = 'accountant'
      or p_duty = 'sales_engineer.disputes'
      then 'money'
    when p_duty = any (array[
      'resilience_ping.rotate_by_api',          -- rotates a provider API key
      'resilience_ping.renewal',                -- credential renewal reminders
      'resilience_ping.restore_overdue',        -- the restore drill is overdue
      'resilience_ping.restore_table',          -- the restore drill itself
      'it_engineer.credential_rotation_age',
      'it_engineer.backup_objectives',
      'it_engineer.dr_review'])
      then 'security'
    else 'routine' end
$function$


CREATE OR REPLACE FUNCTION public.fn_e2e_run_tag_current()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  return coalesce(nullif(current_setting('app.e2e_run_tag', true), ''),
                  case when nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role' = 'service_role'
                       then nullif(nullif(current_setting('request.headers', true), '')::json ->> 'x-qd-e2e-run', '') end);
exception when others then
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_e2e_run_tag_open(p_tag text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select p_tag ~ '^[a-z0-9]{4,16}$' and exists (
    select 1 from public.rehearsal_window w
     where w.run_tag = 'qd_run:' || p_tag and w.ended_at is null and w.models_allowed and w.expires_at > now())
$function$


CREATE OR REPLACE FUNCTION public.fn_ea_agenda(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'as_of', now(),
    'today', jsonb_build_object(
      'events', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'starts_at',starts_at,'location',location,'attendees',attendees) order by starts_at)
          from ea_events where status='scheduled' and coalesce(starts_at, now())::date = current_date),'[]'::jsonb),
      'reminders_due', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'remind_at',remind_at) order by remind_at)
          from ea_reminders where not done and remind_at <= now()+interval '1 day'),'[]'::jsonb)
    ),
    'upcoming_events', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'starts_at',starts_at,'location',location) order by starts_at)
        from ea_events where status='scheduled' and starts_at > current_date and starts_at <= (current_date + (p_days||' days')::interval)),'[]'::jsonb),
    'open_tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'priority',priority,'due',due_date,'source',source) order by (due_date is null), due_date)
        from (select * from crm_tasks where coalesce(status,'open') not in ('done','cancelled') order by (due_date is null), due_date limit 15) t),'[]'::jsonb),
    'overdue_tasks', (select count(*) from crm_tasks where coalesce(status,'open') not in ('done','cancelled') and due_date < now()),
    -- HIS, AND ONLY HIS. fn_founder_queue is the one reader of what waits on the founder (a refund decision);
    -- an agent_action held with a department is that department's and is never counted here again.
    'approvals_to_clear', (
      select jsonb_build_object(
        'total', coalesce((q->>'waiting_on_you_total')::int, 0),
        'high_risk', coalesce((q->>'waiting_on_you_total')::int, 0),
        'top', coalesce((select jsonb_agg(jsonb_build_object(
                 'agent', y->>'from', 'title', y->>'title', 'risk', 'money', 'kind', y->>'kind',
                 'reason', coalesce(y->>'kind_label', 'Refund decision') || ' — the only decision that is yours',
                 'os', 'finance', 'source', y->>'source', 'subject_ref', y->>'subject_ref',
                 'raised', y->'raised', 'age_days', y->'age_days',
                 'outcome', 'waiting on you since ' || left(coalesce(y->>'raised', ''), 10)))
               from jsonb_array_elements(coalesce(q->'waiting_on_you', '[]'::jsonb)) y), '[]'::jsonb))
      from (select public.fn_founder_queue(8) q) fq
    ),
    'recent_meetings', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'meeting_at',meeting_at,'summary',left(summary,240)) order by meeting_at desc)
        from (select * from ea_meetings order by meeting_at desc limit 5) m),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_edit_inquiry(p_inquiry uuid, p_customer uuid, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v inquiries%rowtype; v_paid boolean; v_deadline timestamptz;
  v_material boolean := false; v_reason text; v_stale int := 0; v_notified int := 0;
  v_cust_email text; v_admin text;
begin
  select * into v from inquiries where id=p_inquiry;
  if not found then return jsonb_build_object('error','inquiry_not_found'); end if;
  if p_customer is not null and v.customer_id is distinct from p_customer then
    return jsonb_build_object('error','not_your_inquiry'); end if;
  select exists(select 1 from transactions where inquiry_id=p_inquiry) into v_paid;
  -- 10 Nov 2026: expired and lost are ends too (one list with _shared/request_closed.ts)
  if v_paid or v.status in ('revealed','completed','cancelled','closed','expired','lost') or v.pipeline_stage in ('revealed','won','cancelled') then
    return jsonb_build_object('error','not_editable','status',v.status,
      'message','This request can no longer be edited.'); end if;
  v_deadline := v.created_at + interval '1 hour';
  if now() > v_deadline then
    return jsonb_build_object('error','edit_window_closed','editable_until',v_deadline,
      'message','Inquiries can be edited within 1 hour of submitting. Please create a new request for changes after that.'); end if;

  -- Decide materiality BEFORE the update, while the old row is still in hand.
  v_material :=
       (p_patch ? 'spec'       and (p_patch->'spec')       is distinct from v.spec)
    or (p_patch ? 'boq'        and (p_patch->'boq')        is distinct from v.boq)
    or (p_patch ? 'budget'     and (p_patch->>'budget')    is distinct from v.budget)
    or (p_patch ? 'scope_type' and (p_patch->>'scope_type') is distinct from v.scope_type)
    or (p_patch ? 'emirate'    and (p_patch->>'emirate')   is distinct from v.emirate)
    or (p_patch ? 'trades'     and array(select jsonb_array_elements_text(p_patch->'trades')) is distinct from v.trades);

  update inquiries set
    summary   = coalesce(p_patch->>'summary', summary),
    raw_input = coalesce(p_patch->>'raw_input', raw_input),
    budget    = coalesce(p_patch->>'budget', budget),
    emirate   = coalesce(p_patch->>'emirate', emirate),
    scope_type= coalesce(p_patch->>'scope_type', scope_type),
    spec      = case when p_patch ? 'spec' then p_patch->'spec' else spec end,
    boq       = case when p_patch ? 'boq' then p_patch->'boq' else boq end,
    trades    = case when p_patch ? 'trades' then array(select jsonb_array_elements_text(p_patch->'trades')) else trades end,
    keywords  = case when p_patch ? 'keywords' then array(select jsonb_array_elements_text(p_patch->'keywords')) else keywords end
    where id=p_inquiry;

  if v_material then
    v_reason := 'The customer changed the requirements of this request on '
             || to_char(now() at time zone 'Asia/Dubai','DD Mon YYYY HH24:MI')
             || ' (Dubai), after this quote was submitted.';

    -- Stale the live quotes and tell each supplier, in one statement so a quote can never be
    -- reverted without its supplier being told.
    with staled as (
      update quotes q
         set stale_at = now(), stale_reason = v_reason, status = 'draft'
       where q.inquiry_id = p_inquiry
         and q.stale_at is null
         and coalesce(q.status,'') in ('submitted','draft')
      returning q.id, q.supplier_id
    ),
    told as (
      insert into notifications(type, to_email, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status)
      select 'quote_requirements_changed',
             coalesce(l.claimed_by, l.email), 'supplier', s.supplier_id, p_inquiry, s.id, 'email',
             'The customer changed this request — please re-quote',
             'Hello ' || coalesce(l.company_name,'') || ',' || chr(10) || chr(10) ||
             'A customer has changed the requirements of a request you had already quoted, so your quote has been set back to draft and is no longer being shown to them.' || chr(10) || chr(10) ||
             v_reason || chr(10) || chr(10) ||
             'Please open the request in your supplier portal, review what changed, and submit an updated quote. Your original figures are still there — nothing has been deleted.' || chr(10) || chr(10) ||
             'QuotesDone',
             'queued'
        from staled s join leads l on l.id = s.supplier_id
       where coalesce(l.claimed_by, l.email) is not null
      returning 1
    )
    select (select count(*) from staled), (select count(*) from told) into v_stale, v_notified;

    if v_stale > 0 then
      select email into v_cust_email from customers where id = v.customer_id;
      v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),
                          'management@quotesdone.com');

      -- The customer must know their edit cost them their quotes, or they will wait for prices
      -- that are never coming back on their own. The type now has a notification_copy row in both
      -- languages (above), so a04 states THIS in Arabic rather than the generic fallback (CP-04).
      if v_cust_email is not null then
        insert into notifications(type, to_email, to_role, inquiry_id, channel, subject, body, status)
        values ('inquiry_edit_staled_quotes', v_cust_email, 'customer', p_inquiry, 'email',
                'Your change means we have asked for fresh prices',
                'Hello,' || chr(10) || chr(10) ||
                'You changed the requirements on your request, so the ' || v_stale ||
                ' quote(s) already submitted no longer match what you are asking for. We have asked those suppliers to re-quote against your updated requirements.' || chr(10) || chr(10) ||
                'You do not need to do anything — the new prices will appear as they arrive.' || chr(10) || chr(10) ||
                'QuotesDone', 'queued');
      end if;

      -- THE SALES ENGINEER OWNS AN RFQ WHOSE QUOTES WENT BACK (CP-04). This said 'procurement',
      -- which is not one of the estate's seats, so the follow-up reached nobody.
      insert into agent_actions(agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('sales_engineer','requote_required','needs_review','medium',
              'Requirements changed after ' || v_stale || ' quote(s) were submitted',
              'Watch that the invited suppliers actually re-quote. If they do not, the customer is left with a request that had prices and now has none.',
              jsonb_build_object('inquiry_id', p_inquiry, 'quotes_staled', v_stale,
                                 'suppliers_notified', v_notified, 'changed_at', now()),
              'inquiries', p_inquiry::text);
    end if;
  end if;

  return jsonb_build_object('ok',true,'edited',true,'editable_until',v_deadline,
                            'material_change', v_material,
                            'quotes_staled', v_stale,
                            'suppliers_notified', v_notified);
end $function$


CREATE OR REPLACE FUNCTION public.fn_email_domain_class(p_email text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with d as (select lower(btrim(split_part(coalesce(p_email, ''), '@', 2))) as dom)
  select case
    when position('@' in coalesce(p_email, '')) = 0 or (select dom from d) = '' then null
    when exists (select 1 from public.app_blocked_domains b, d where b.domain = d.dom)
      or exists (select 1 from public.email_platform_domain e, d where e.kind = 'disposable' and e.domain = d.dom) then 'disposable'
    when exists (select 1 from public.free_email_domain f, d where f.domain = d.dom) then 'free'
    else 'company' end
$function$


CREATE OR REPLACE FUNCTION public.fn_email_open_classify(p_user_agent text, p_ip inet, p_seconds numeric, OUT classification text, OUT rule text)
 RETURNS record
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare ua text := btrim(coalesce(p_user_agent, '')); ipc text := public.fn_email_open_ip_class(p_ip); c_fast constant numeric := 60;
begin
  if p_seconds is null then classification := 'unknown'; rule := 'no send time on the notification'; return; end if;
  if ua ~* '(bot\M|crawl|spider|scanner|barracuda|mimecast|proofpoint|ppops|forcepoint|symantec|messagelabs|trend ?micro|sophos|fortinet|fortimail|ironport|cisco|zscaler|libwww|python|curl/|wget|go-http|java/|okhttp|axios|node-fetch|undici|headless|phantomjs|link ?check|urlscan|safelinks|existence discovery)' then
    classification := 'machine_prefetch'; rule := 'scanner or bot user agent'; return; end if;
  if ua ~* '(googleimageproxy|ggpht\.com|yahoomailproxy)' then
    if p_seconds < c_fast then classification := 'machine_prefetch'; rule := 'mail image proxy within 60 s of the send';
    else classification := 'likely_human'; rule := 'mail image proxy fetch after 60 s (fetched when the message is opened)'; end if;
    return; end if;
  if ua = 'Mozilla/5.0' or ipc = 'apple' then classification := 'machine_prefetch'; rule := 'Apple Mail Privacy Protection'; return; end if;
  if ipc = 'microsoft_eop' then classification := 'machine_prefetch'; rule := 'Microsoft Exchange Online Protection address'; return; end if;
  if p_seconds < c_fast then classification := 'machine_prefetch'; rule := 'loaded within 60 s of the send'; return; end if;
  if ua ~* '(outlook|microsoft office|thunderbird|windows nt|macintosh|iphone|ipad|android|applewebkit|gecko|chrome|safari)' then
    classification := 'likely_human'; rule := 'mail client or browser user agent after 60 s'; return; end if;
  classification := 'unknown'; rule := case when ua = '' then 'no user agent' else 'unrecognised user agent' end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_email_open_ip_class(p_ip inet)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when p_ip is null then null
    when family(p_ip) = 4 and p_ip << inet '17.0.0.0/8' then 'apple'
    when (family(p_ip) = 4 and (p_ip << inet '40.92.0.0/15' or p_ip << inet '40.107.0.0/16' or p_ip << inet '52.100.0.0/14' or p_ip << inet '104.47.0.0/17'))
      or (family(p_ip) = 6 and (p_ip << inet '2a01:111:f400::/48' or p_ip << inet '2a01:111:f403::/48')) then 'microsoft_eop'
  end
$function$


CREATE OR REPLACE FUNCTION public.fn_email_open_record(p_token text, p_user_agent text DEFAULT NULL::text, p_ip text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t public.email_open_token%rowtype; v_sent timestamptz; v_ip inet; v_secs numeric; v_salt text; c record;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then return 'bad_token'; end if;
  select * into t from public.email_open_token where token = p_token;
  if not found then return 'unknown_token'; end if;
  if (select count(*) from public.email_open_event where token = p_token) >= 50 then return 'capped'; end if;
  select sent_at into v_sent from public.notifications where id = t.notification_id;
  begin v_ip := nullif(btrim(split_part(coalesce(p_ip, ''), ',', 1)), '')::inet; exception when others then v_ip := null; end;
  v_secs := case when v_sent is null then null else round(extract(epoch from (now() - v_sent))::numeric, 1) end;
  select * into c from public.fn_email_open_classify(p_user_agent, v_ip, v_secs);
  v_salt := (select value from public.app_secrets where key = 'email_open_ip_salt');
  insert into public.email_open_event (token, notification_id, seconds_after_send, user_agent, ip_hash, ip_class, classification, rule)
  values (p_token, t.notification_id, v_secs, left(p_user_agent, 300),
          case when v_ip is not null and coalesce(v_salt, '') <> '' then encode(sha256(convert_to(v_salt || '|' || host(v_ip), 'UTF8')), 'hex') end,
          public.fn_email_open_ip_class(v_ip), c.classification, c.rule);
  return c.classification;
end $function$


CREATE OR REPLACE FUNCTION public.fn_email_proven(p_email text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(btrim(p_email), '') <> ''
     and exists (select 1 from public.email_verifications v
                  where v.email = lower(btrim(p_email))
                    and v.purpose in ('login', 'kyc')
                    and v.verified_at is not null)
$function$


CREATE OR REPLACE FUNCTION public.fn_email_sendable(p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_e text; v_pat record; v_dom text;
begin
  v_e := lower(btrim(coalesce(p_email,'')));
  if v_e = '' then
    return jsonb_build_object('ok', false, 'reason', 'no address');
  end if;
  if v_e !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$' then
    return jsonb_build_object('ok', false, 'reason', 'not a valid address shape');
  end if;
  if exists (select 1 from email_suppressions s where lower(s.email) = v_e) then
    return jsonb_build_object('ok', false, 'reason', 'suppressed');
  end if;
  v_dom := split_part(v_e, '@', 2);
  if exists (select 1 from email_domain_mx m
              where m.domain = v_dom and m.has_mx = false
                and m.kind in ('nxdomain','no_records')) then
    return jsonb_build_object('ok', false, 'reason', 'domain does not accept mail');
  end if;
  for v_pat in select pattern, reason from email_block_pattern where active loop
    if v_e ~ v_pat.pattern then
      return jsonb_build_object('ok', false, 'reason', v_pat.reason);
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'reason', 'sendable');
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_email_sendable(p_email text, p_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_e text; v_pat record; v_dom text;
begin
  v_e := lower(btrim(coalesce(p_email, '')));
  if v_e = '' then return jsonb_build_object('ok', false, 'reason', 'no address'); end if;
  if v_e !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$' then
    return jsonb_build_object('ok', false, 'reason', 'not a valid address shape');
  end if;
  if exists (select 1 from public.email_suppressions s where lower(s.email) = v_e
               and (lower(btrim(coalesce(s.reason, ''))) <> 'unsubscribe' or public.fn_email_type_is_marketing(p_type))) then
    return jsonb_build_object('ok', false, 'reason', 'suppressed');
  end if;
  v_dom := split_part(v_e, '@', 2);
  if exists (select 1 from public.email_domain_mx m
              where m.domain = v_dom and m.has_mx = false and m.kind in ('nxdomain', 'no_records')) then
    return jsonb_build_object('ok', false, 'reason', 'domain does not accept mail');
  end if;
  for v_pat in select pattern, reason from public.email_block_pattern where active loop
    if v_e ~ v_pat.pattern then return jsonb_build_object('ok', false, 'reason', v_pat.reason); end if;
  end loop;
  return jsonb_build_object('ok', true, 'reason', 'sendable');
end $function$


CREATE OR REPLACE FUNCTION public.fn_email_type_is_marketing(p_type text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select p_type is null or p_type = any (public.fn_opt_out_types())
      or p_type ~* '(invite|nudge|newsletter|marketing|promo|winback|activation)';
$function$


CREATE OR REPLACE FUNCTION public.fn_emit(p_event_type text, p_entity_type text, p_entity_id text, p_actor text DEFAULT 'system'::text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint;
begin
  -- correlation_id and causation_id are deliberately NOT named here. They carry the column
  -- defaults, which read app.correlation_id / app.causation_event_id — so an event emitted inside
  -- fn_event_dispatch's loop joins the chain it came from, and one emitted from a cron starts its
  -- own. Naming them here would override that and silently break the chain.
  insert into company_event (event_type, entity_type, entity_id, actor, payload)
  values (p_event_type, p_entity_type, p_entity_id, coalesce(p_actor,'system'), coalesce(p_payload,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_campaign_launched()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.campaign_id is not null and not exists (
       select 1 from company_event
        where event_type = 'campaign.launched' and entity_id = new.campaign_id) then
    perform fn_emit('campaign.launched', 'campaign', new.campaign_id, 'marketing',
      jsonb_build_object('name', new.campaign_name, 'objective', new.objective,
                         'status', new.effective_status));
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_campaign_published()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' or coalesce(old.state,'') is distinct from 'published' then
    perform public.fn_emit('campaign.published', 'content_campaign', new.business_key, coalesce(new.created_by,'system'),
      jsonb_build_object('business_key', new.business_key, 'version', new.version,
                         'object_id', new.object_id, 'payload', new.payload));
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_campaign_published_from_content()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if exists (select 1 from public.company_event e
              where e.event_type = 'campaign.published' and e.entity_type = 'content_draft'
                and e.entity_id = new.id::text) then
    return new;
  end if;
  perform public.fn_emit('campaign.published', 'content_draft', new.id::text,
    coalesce(nullif(new.source, ''), 'marketing'),
    jsonb_build_object('content_draft_id', new.id, 'channel', new.channel, 'category', new.category,
      'title', left(coalesce(new.title, ''), 200), 'posted_at', coalesce(new.reviewed_at, now())));
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_churn_signal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.churn_risk is not null and new.churn_risk >= 0.7
     and (tg_op = 'INSERT' or coalesce(old.churn_risk, 0) < 0.7) then
    perform public.fn_emit('customer.churn_signal', 'customer', new.customer_id::text, 'system',
      jsonb_build_object('customer_id', new.customer_id, 'churn_risk', new.churn_risk,
                         'lifetime_value_aed', new.lifetime_value_aed, 'last_active', new.last_active));
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_competitor_pricing_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform fn_emit('competitor.pricing_changed', 'competitor', new.id::text, 'competitive',
    jsonb_build_object('name', new.name,
                       'was', left(coalesce(old.business_model,''), 400),
                       'now', left(coalesce(new.business_model,''), 400),
                       'what_they_do_changed',
                         coalesce(old.what_they_do,'') is distinct from coalesce(new.what_they_do,'')));
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_content_drafted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.fn_emit('content.drafted', 'content_draft', new.id::text, coalesce(new.source,'system'),
    jsonb_build_object('channel', new.channel, 'category', new.category, 'title', new.title,
                       'status', new.status));
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_customer_complaint()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.fn_emit('customer.complaint', 'feedback', new.id::text, coalesce(new.source,'customer'),
    jsonb_build_object('subject_type', new.subject_type, 'subject_id', new.subject_id,
                       'rating', new.rating, 'source', new.source, 'comment', left(coalesce(new.comment,''),500)));
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_customer_complaint_from_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if exists (select 1 from public.company_event e
              where e.event_type = 'customer.complaint' and e.entity_type = 'review'
                and e.entity_id = new.id::text) then
    return new;
  end if;
  perform public.fn_emit('customer.complaint', 'review', new.id::text, 'customer',
    jsonb_build_object('subject_type', 'supplier', 'subject_id', new.supplier_id::text,
      'rating', new.rating, 'source', 'review', 'comment', left(coalesce(new.comment, ''), 500),
      'inquiry_id', new.inquiry_id, 'transaction_id', new.transaction_id, 'customer_id', new.customer_id));
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_customer_registered()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform fn_emit('customer.registered', 'customer', new.id::text, 'system',
    jsonb_build_object('locale', new.locale, 'industry', new.industry,
                       'email_verified', new.email_verified, 'phone_verified', new.phone_verified));
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_type text; v_entity text; v_id text; v_actor text;
begin
  v_entity := tg_argv[0];
  v_type   := tg_argv[1];
  begin v_id := (to_jsonb(new)->>'id'); exception when others then v_id := null; end;
  begin v_actor := coalesce(to_jsonb(new)->>'created_by', to_jsonb(new)->>'author_agent', to_jsonb(new)->>'actor', 'system'); exception when others then v_actor := 'system'; end;
  insert into company_event (event_type, entity_type, entity_id, actor, payload)
  values (v_type, v_entity, v_id, v_actor, to_jsonb(new));
  return new;
end; $function$


CREATE OR REPLACE FUNCTION public.fn_emit_health_degraded()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform fn_emit('health.degraded', 'operating_system', coalesce(new.payload->>'os_key','unknown'),
    'os_review',
    jsonb_build_object('os_key', new.payload->>'os_key',
                       'score', (new.payload->>'score')::numeric,
                       'previous_score', (new.payload->>'previous_score')::numeric,
                       'drop', (new.payload->>'previous_score')::numeric - (new.payload->>'score')::numeric,
                       'health', new.payload->>'health',
                       'period', new.payload->>'period',
                       'source_event', new.id));
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_invoice_received()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into company_event (event_type, entity_type, entity_id, actor, payload)
  values ('invoice.received','ap_bill', new.bill_no, coalesce(new.created_by,'system'),
          jsonb_build_object('vendor_id', new.vendor_id, 'total', new.total,
                             'bill_date', new.bill_date, 'due_date', new.due_date));
  return new;
end; $function$


CREATE OR REPLACE FUNCTION public.fn_emit_invoice_received_from_expense()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_emit('invoice.received', 'expense_entry', new.id::text,
    coalesce(nullif(new.source, ''), 'expenses_inbox'),
    jsonb_build_object('vendor', new.vendor, 'amount', new.amount, 'currency', new.currency,
      'charged_on', new.charged_on, 'category', new.category, 'note', left(coalesce(new.note, ''), 300),
      'doc_path', new.doc_path, 'source', new.source));
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_refund_requested()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- Only a genuine NEW customer request: status 'requested' and no Stripe refund id (an externally
  -- issued refund is a recorded fact, not a request, and must not enter the approval workflow).
  if new.status = 'requested' and new.stripe_refund_id is null then
    -- 4 Sep 2026: the customer's own request (transactions.refund_status → 'requested') already
    -- put this case on the bus; the claim continues that case rather than opening a second run.
    if new.transaction_id is not null and exists (select 1 from public.company_event e
         where e.event_type = 'refund.requested' and e.entity_type = 'transaction'
           and e.entity_id = new.transaction_id::text) then
      return new;
    end if;
    perform public.fn_emit('refund.requested', 'refund', new.id::text,
      coalesce(new.requested_by, 'system'),
      jsonb_build_object('refund_id', new.id, 'inquiry_id', new.inquiry_id,
        'customer_id', new.customer_id, 'supplier_lead_id', new.supplier_lead_id,
        'amount_fils', new.amount_fils, 'reason_code', new.reason_code));
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_refund_requested_from_transaction()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if exists (select 1 from public.refunds r where r.transaction_id = new.id) then
    return new;   -- the refunds row already carried this request onto the bus
  end if;
  if exists (select 1 from public.company_event e
              where e.event_type = 'refund.requested' and e.entity_type = 'transaction'
                and e.entity_id = new.id::text) then
    return new;
  end if;
  perform public.fn_emit('refund.requested', 'transaction', new.id::text, 'customer',
    jsonb_build_object('transaction_id', new.id, 'inquiry_id', new.inquiry_id,
      'customer_id', new.customer_id, 'supplier_lead_id', new.supplier_id, 'quote_id', new.quote_id,
      'amount_fils', round(coalesce(new.reveal_fee, 0) * 100)::bigint,
      'reason_code', coalesce(new.refund_reason, 'supplier_unresponsive'),
      'refund_deadline', new.refund_deadline, 'source', 'customer_api request_refund'));
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_regulation_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform fn_emit('regulation.changed', 'compliance_source', new.id::text, 'compliance',
    jsonb_build_object('authority', new.authority, 'topic', new.topic, 'url', new.url,
                       'summary', left(coalesce(new.last_summary,''), 600),
                       'previous_change', old.last_changed_at));
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_rfq_classified()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(btrim(new.category),'') = '' then return null; end if;
  if tg_op = 'UPDATE' and coalesce(old.category,'') = coalesce(new.category,'') then return null; end if;
  perform fn_emit('rfq.classified', 'inquiry', new.id::text, 'route_inquiry',
    jsonb_build_object('category', new.category, 'trades', new.trades,
                       'rfq_ready', new.rfq_ready, 'status', new.status));
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_supplier_applied()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.registration_submitted_at is not null
     and coalesce(old.registration_submitted_at, '-infinity'::timestamptz) is distinct from new.registration_submitted_at then
    insert into company_event (event_type, entity_type, entity_id, actor, payload)
    values ('supplier.applied','lead', new.id::text, coalesce(new.claimed_by,'supplier'),
            jsonb_build_object('company', new.company_name, 'emirate', new.emirate,
                               'trade_licence', new.trade_license_no, 'trades', new.invite_trades));
  end if;
  return new;
end; $function$


CREATE OR REPLACE FUNCTION public.fn_emit_supplier_approved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(new.approval_status,'') <> 'approved' then return null; end if;
  if tg_op = 'UPDATE' and coalesce(old.approval_status,'') = 'approved' then return null; end if;
  perform fn_emit('supplier.approved', 'lead', new.id::text, 'system',
    jsonb_build_object('company', new.company_name, 'city', new.city,
                       'verified', new.verified, 'lifecycle_stage', new.lifecycle_stage));
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_emit_test_failed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'error' and coalesce(old.status,'') <> 'error' then
    if not exists (
      select 1 from company_event e
      where e.event_type = 'test.failed' and e.entity_id = new.agent
        and e.occurred_at > date_trunc('day', now())
    ) then
      insert into company_event (event_type, entity_type, entity_id, actor, payload)
      values ('test.failed','scheduled_run', new.agent, 'system',
              jsonb_build_object('run_id', new.id, 'note', left(coalesce(new.note,''), 500),
                                 'started_at', new.started_at));
    end if;
  end if;
  return new;
end; $function$


CREATE OR REPLACE FUNCTION public.fn_emit_test_failed_ins()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'error' then
    if not exists (
      select 1 from company_event e
      where e.event_type = 'test.failed' and e.entity_id = new.agent
        and e.occurred_at > date_trunc('day', now())
    ) then
      insert into company_event (event_type, entity_type, entity_id, actor, payload)
      values ('test.failed','scheduled_run', new.agent, 'system',
              jsonb_build_object('run_id', new.id, 'note', left(coalesce(new.note,''), 500),
                                 'started_at', new.started_at));
    end if;
  end if;
  return new;
end; $function$


CREATE OR REPLACE FUNCTION public.fn_employee_knowledge_freshness(p_stale_days integer DEFAULT 30, p_thin_min integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with base as (
    select a.agent_key as slug, coalesce(a.title, a.role, a.agent_key) as name, a.department,
           (select count(*) from public.agent_knowledge k
             where k.agent_key = a.agent_key and coalesce(k.layer,'profession') in ('profession','state')
               and coalesce(k.validation_status,'') <> 'quarantined') as items,
           (select max(k.updated_at) from public.agent_knowledge k
             where k.agent_key = a.agent_key and coalesce(k.layer,'profession') in ('profession','state')
               and coalesce(k.validation_status,'') <> 'quarantined') as last_updated,
           (select count(*) from public.agent_knowledge k
             where k.agent_key = a.agent_key and k.layer = 'experience'
               and coalesce(k.validation_status,'') <> 'quarantined') as lessons
      from public.org_agents a
     where a.active and a.kind in ('brain','agent')
  ),
  scored as (
    select slug, name, department, items, lessons, last_updated,
           case when last_updated is null then null else floor(extract(epoch from (now() - last_updated))/86400)::int end as days_stale,
           case when items = 0 then 'missing'
                when last_updated < now() - (p_stale_days || ' days')::interval then 'stale'
                when items < p_thin_min then 'thin'
                else 'ok' end as status
      from base
  )
  select jsonb_build_object(
    'population', 'employees (org_agents active, kind brain/agent)',
    'thresholds', jsonb_build_object('stale_days', p_stale_days, 'thin_min', p_thin_min),
    'summary', jsonb_build_object(
      'total', (select count(*) from scored),
      'ok', (select count(*) from scored where status = 'ok'),
      'stale', (select count(*) from scored where status = 'stale'),
      'thin', (select count(*) from scored where status = 'thin'),
      'missing', (select count(*) from scored where status = 'missing'),
      'coverage_pct', round(100.0 * (select count(*) from scored where status = 'ok') / nullif((select count(*) from scored), 0), 1)),
    'agents', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', slug, 'name', name, 'emoji', null, 'department', department, 'items', items, 'lessons', lessons,
        'last_updated', last_updated, 'days_stale', days_stale, 'status', status)
        order by case status when 'missing' then 0 when 'stale' then 1 when 'thin' then 2 else 3 end, days_stale desc nulls last, slug)
      from scored), '[]'::jsonb));
$function$


CREATE OR REPLACE FUNCTION public.fn_enforce_rls_on_new_tables()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare r record;
begin
  for r in
    select object_identity, schema_name, object_type
    from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE','CREATE TABLE AS','SELECT INTO')
      and object_type = 'table'
      and schema_name = 'public'
  loop
    execute format('alter table %s enable row level security', r.object_identity);
  end loop;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_enqueue_doc_backups()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n integer := 0; m integer;
begin
  -- ============ SUPPLIERS ============
  with s as (
    select l.*,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false)
  ),
  sd as (
    select s.id, s.base, v.doc_type, v.bucket, v.path
    from s cross join lateral (values
      ('Trade licence','supplier-docs', s.license_doc_path),
      ('Establishment card','supplier-docs', s.egr_doc_path),
      ('Insurance','supplier-docs', s.insurance_doc_path),
      ('VAT certificate','supplier-docs', s.vat_doc_path),
      ('ISO certificate','supplier-docs', s.iso_doc_path),
      ('Manufacturer authorization','supplier-docs', s.manufacturer_auth_doc_path),
      ('Company profile','supplier-docs', s.company_profile_doc_path),
      ('Signed Terms & Conditions','signed-terms', s.signed_terms_path)
    ) v(doc_type,bucket,path)
    where v.path is not null and length(v.path)>0
  )
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'supplier', sd.id::text, sd.doc_type, sd.bucket, sd.path,
         regexp_replace(sd.path,'^.*/',''),
         sd.base || sd.doc_type || ' - ' || regexp_replace(sd.path,'^.*/',''),
         'storage', 'S:'||sd.id||':'||sd.doc_type||':'||sd.path
  from sd on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'supplier', s.id::text, 'Catalogue', 'supplier-docs', cat,
         regexp_replace(cat,'^.*/',''), s.base || 'Catalogue - ' || regexp_replace(cat,'^.*/',''),
         'storage', 'S:'||s.id||':cat:'||cat
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base,
      l.catalog_doc_paths
    from public.leads l
    where (l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false)) and l.catalog_doc_paths is not null ) s,
    unnest(s.catalog_doc_paths) cat
  where cat is not null and length(cat)>0 on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'supplier', s.id::text, 'Company Details','generated','supplier_details', s.id::text,
         s.base || 'Company Details.pdf', 'S:'||s.id||':details'
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false) ) s
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ CUSTOMERS ============
  -- This is the row that carries a signed T&C certificate into Dropbox. compliance_archive writes
  -- customers.signed_terms_path and stops; the file is placed here, in one folder, once.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'customer', c.id::text, 'Signed Terms & Conditions','signed-terms', c.signed_terms_path,
         regexp_replace(c.signed_terms_path,'^.*/',''),
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Signed Terms & Conditions - '||regexp_replace(c.signed_terms_path,'^.*/',''),
         'storage', 'C:'||c.id||':terms:'||c.signed_terms_path
  from public.customers c where c.signed_terms_path is not null and length(c.signed_terms_path)>0
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'customer', c.id::text, 'Customer Details','generated','customer_details', c.id::text,
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Customer Details.pdf',
         'C:'||c.id||':details'
  from public.customers c on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ INQUIRIES (under their customer) ============
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'inquiry', i.id::text, 'RFQ drawing','drawing-files', i.drawing_file_path,
         coalesce(i.drawing_file_name, regexp_replace(i.drawing_file_path,'^.*/','')),
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Drawing - '||coalesce(i.drawing_file_name, regexp_replace(i.drawing_file_path,'^.*/','')),
         'storage', 'I:'||i.id||':drawing:'||i.drawing_file_path
  from public.inquiries i join public.customers c on c.id=i.customer_id
  where i.drawing_file_path is not null and length(i.drawing_file_path)>0
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'inquiry', i.id::text, 'Inquiry Summary','generated','inquiry_summary', i.id::text,
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Inquiry Summary.pdf', 'I:'||i.id||':summary'
  from public.inquiries i join public.customers c on c.id=i.customer_id
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- The gen_kind='comparison' block that stood here is deliberately absent. See the header.

  -- ============ REVENUE INVOICES (9 SEP 2026) ============
  -- The founder: "our accountant need to retrieve that and be connected, then add it to his
  -- records, sync it with back up on dropbox." This is the sync half. The trigger is doc_path
  -- being non-null, NOT who wrote it, so a backfill or a hand-repair mirrors on the same rule as
  -- the webhook. They are filed under Finance rather than under the customer, because the person
  -- who opens this folder is the accountant reconciling a month, not someone reading one customer.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'transaction', t.id::text, 'Stripe invoice', 'finance-docs', t.doc_path,
         coalesce(t.doc_name, regexp_replace(t.doc_path,'^.*/','')),
         '/QuotesDone Backup/Finance/Revenue Invoices/'
           || to_char(coalesce(t.revealed_at, now()), 'YYYY') || '/'
           || to_char(coalesce(t.revealed_at, now()), 'YYYY-MM') || '/'
           || public.fn_dbx_safe(coalesce(t.stripe_invoice_number, t.stripe_invoice_id, left(t.id::text,8)))
           || ' - ' || coalesce(t.doc_name, regexp_replace(t.doc_path,'^.*/','')),
         'storage', 'T:'||t.id||':invoice:'||t.doc_path
  from public.transactions t
  where t.doc_path is not null and length(t.doc_path) > 0
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ CORRESPONDENCE (14 SEP 2026) ============
  -- The founder: "by back up i mean 2 points. supabase and dropbox." Every conversation message whose
  -- PDF is in backups/conversations/ (public.conversation_archive) is mirrored to Dropbox on his
  -- entity -> type -> date tree. A customer's message on an inquiry goes under that inquiry; a
  -- supplier's goes under the supplier ONLY when the supplier is a registrant (the same predicate the
  -- supplier documents use above); everything else is Company correspondence by month. Demo rows are
  -- never queued. Times are Dubai time.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select x.entity, x.entity_id, 'Correspondence', a.pdf_bucket, a.pdf_path, x.fname, x.base || x.fname, 'storage',
         'CONV:' || a.source_table || ':' || a.source_id
  -- 21 SEP 2026 (it_engineer): ONLY ARCHIVE ROWS THAT HAVE NO CORRESPONDENCE ROW YET. This block used to
  -- join every conversation_archive row (257) to v_conversation_message on every call and let ON CONFLICT
  -- discard all of them; the view resolves each message's party through fn_conversation_party, 20-45 ms
  -- a row, so the call cost 7,006 ms (EXPLAIN ANALYZE, 21 Sep) and PostgREST cancels at 8 s. The OFFSET 0
  -- fences keep the anti-join FIRST and the view LATERAL, so a call with nothing new costs 1.7 ms and a
  -- new message costs one party lookup. The dedupe key is unchanged, so what is queued is unchanged.
  from (select ca.* from public.conversation_archive ca
         where not exists (select 1 from public.doc_backups d
                            where d.dedupe_key = 'CONV:' || ca.source_table || ':' || ca.source_id)
         offset 0) a
  cross join lateral (select * from public.v_conversation_message v0
                       where v0.source_table = a.source_table and v0.source_id = a.source_id offset 0) v
  left join public.customers c on v.party_kind = 'customer' and c.id::text = v.party_id
  left join public.inquiries i on c.id is not null and i.id::text = v.inquiry_id
  left join public.leads l on v.party_kind = 'supplier' and l.id::text = v.party_id
       and (l.approved_at is not null or l.registration_submitted_at is not null
         or l.signed_terms_path is not null or l.company_profile_doc_path is not null
         or l.license_doc_path is not null or coalesce(l.claimed,false))
  cross join lateral (select
      case when c.id is not null then 'customer' when l.id is not null then 'supplier' else 'company' end as entity,
      coalesce(c.id::text, l.id::text, v.source_table || ':' || v.source_id) as entity_id,
      case when c.id is not null then
             '/QuotesDone Backup/Customers/' || public.fn_dbx_safe(coalesce(c.full_name,'Customer')) || ' (' || left(c.id::text,8) || ')/'
             || case when i.id is not null then 'Inquiries/' || to_char(i.created_at,'YYYY-MM-DD') || ' ' || left(i.id::text,8)
                       || ' - ' || public.fn_dbx_safe(coalesce(i.status,'inquiry')) || '/' else '' end
             || 'Correspondence/'
           when l.id is not null then
             '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id) || '/'
             || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/Correspondence/'
           else '/QuotesDone Backup/Company/Correspondence/' || to_char(v.occurred_at at time zone 'Asia/Dubai','YYYY-MM') || '/'
      end as base,
      to_char(v.occurred_at at time zone 'Asia/Dubai','YYYY-MM-DD HH24MI') || ' ' || v.direction || ' ' || v.channel || ' - '
        || public.fn_dbx_safe(left(coalesce(nullif(btrim(v.subject),''),'(no subject)'),80)) || ' #' || v.source_id || '.pdf' as fname) x
  -- a tagged sandbox run (fn_backup_sandbox_enqueue) lets its own demo messages through; trg_doc_backups_admit
  -- files them under _sandbox/<tag>/ and drops every other demo row exactly as before
  where (not v.is_demo or coalesce(current_setting('qd.backup_sandbox', true), '') <> '')
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ ACCOUNTING (14 SEP 2026, accountant duty 4 of the five further duties) ============
  -- The founder, 14 Sep 2026: "add all for accountant and IT". The accountant's own documents are filed on
  -- the entity -> type -> date tree under Finance: the month close the CEO signed for (PDF and CSV), the
  -- Mashreq statements, every document the accountant issued in the founder's name, and the year-end pack.
  -- A path stored as '<bucket>/<path>' (bank_statement_intake.doc_path, accountant_issued_document.file_path)
  -- is split at its first slash; any other shape is not queued. Demo rows are filtered exactly as
  -- fn_it_backup_expected filters them (a zz_demo account, an @example.invalid recipient, a ZZ DEMO path):
  -- no demo document reaches Dropbox or the backups bucket.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'close:' || to_char(c.month,'YYYY-MM'), v.doc_type, c.pdf_bucket, v.path,
         regexp_replace(v.path,'^.*/',''),
         '/QuotesDone Backup/Finance/Month Close/' || to_char(c.month,'YYYY') || '/' || to_char(c.month,'YYYY-MM')
           || ' - ' || regexp_replace(v.path,'^.*/',''),
         'storage', 'ACCT:close:' || to_char(c.month,'YYYY-MM') || ':' || v.path
  from public.accountant_month_close c
  cross join lateral (values ('Month close (PDF)', c.pdf_path), ('Month close (CSV)', c.csv_path)) v(doc_type, path)
  where c.rendered_at is not null and c.pdf_bucket is not null and length(coalesce(v.path,'')) > 0
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'bank_statement:' || b.source_ref, 'Bank statement', split_part(b.doc_path,'/',1),
         substr(b.doc_path, strpos(b.doc_path,'/') + 1), regexp_replace(b.doc_path,'^.*/',''),
         '/QuotesDone Backup/Finance/Bank Statements/' || initcap(b.account) || '/'
           || to_char(coalesce(b.statement_month, (b.received_at at time zone 'Asia/Dubai')::date),'YYYY') || '/'
           || to_char(coalesce(b.statement_month, (b.received_at at time zone 'Asia/Dubai')::date),'YYYY-MM')
           || ' - ' || regexp_replace(b.doc_path,'^.*/',''),
         'storage', 'ACCT:bank:' || b.source_ref
  from public.bank_statement_intake b
  where b.doc_path ~ '^[a-z0-9-]+/.+' and b.account <> 'zz_demo'
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'issued:' || d.id, 'Issued document', split_part(d.file_path,'/',1),
         substr(d.file_path, strpos(d.file_path,'/') + 1), regexp_replace(d.file_path,'^.*/',''),
         '/QuotesDone Backup/Finance/Issued Documents/' || to_char(d.issued_at at time zone 'Asia/Dubai','YYYY') || '/'
           || to_char(d.issued_at at time zone 'Asia/Dubai','YYYY-MM') || '/'
           || to_char(d.issued_at at time zone 'Asia/Dubai','YYYY-MM-DD') || ' ' || d.document_kind || ' #' || d.id
           || ' - ' || regexp_replace(d.file_path,'^.*/',''),
         'storage', 'ACCT:issued:' || d.id
  from public.accountant_issued_document d
  where d.file_path ~ '^[a-z0-9-]+/.+' and d.recipient !~* 'example\.invalid'
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'year_end:' || p.year, 'Year-end pack', f->>'bucket', f->>'path', f->>'name',
         '/QuotesDone Backup/Finance/Year End/' || p.year || '/' || (f->>'name'),
         'storage', 'ACCT:year_end:' || p.year || ':' || (f->>'name')
  from public.accountant_year_end_pack p cross join lateral jsonb_array_elements(p.files) f
  where p.rendered_at is not null and (f->>'path') !~* 'zz[_ -]?demo'
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ CUSTOMER DOCUMENTS (7 OCT 2026, sales_engineer) ============
  -- Founder gate, ledger 1162: "no issue in the Dropbox backup of supplier/customer documents and the
  -- folder workflow and organisation". Measured 7 Oct 2026: 386 files that belong to a customer, an
  -- inquiry, a quote or a supplier were filed by the STORAGE SWEEP under Storage/<bucket>/<path>, outside
  -- the entity -> type -> date tree (quote-files 274, agent-docs 92, drawing-files 33 ...). The documents
  -- of a request are filed under that request, in the customer's folder:
  --   Quotes/   the supplier's quotation as uploaded, and the quotation PDF the customer downloaded
  --   Payment/  every reveal invoice and receipt (agent-docs/reveal_invoice/<sale id8>/)
  --   Reports/  the comparison report and the request brief (agent-docs/compare|brief/<inquiry id>/,
  --             the folders customer_api writes since this change)
  -- A file already queued by any rule (the sweep included) is skipped on (bucket, path), so nothing is
  -- filed twice and nothing already in Dropbox is moved. The folder of the request is the one its
  -- Inquiry Summary was filed in (trg_doc_backups_admit), so a status change never splits it.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'inquiry', i.id::text, x.doc_type, x.bucket, x.path, regexp_replace(x.path,'^.*/',''),
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/' || x.folder || '/' || public.fn_dbx_safe(x.fname),
         'storage', x.dkey
  from (
    select q.inquiry_id, 'Supplier quotation' as doc_type, 'quote-files' as bucket, q.original_file_path as path, 'Quotes' as folder,
           to_char(q.created_at at time zone 'Asia/Dubai','YYYY-MM-DD') || ' Quote ' || left(q.id::text,8) || ' - '
             || coalesce(nullif(btrim(q.original_file_name),''), regexp_replace(q.original_file_path,'^.*/','')) as fname,
           'Q:' || q.id || ':original:' || q.original_file_path as dkey
      from public.quotes q
     where length(coalesce(q.original_file_path,'')) > 0
    union all
    select q.inquiry_id, 'Quotation PDF', p.bucket, p.path, 'Quotes',
           'Quote ' || left(q.id::text,8) || ' (' || upper(coalesce(p.lang,'')) || ') - ' || regexp_replace(p.path,'^.*/',''),
           'QPDF:' || p.bucket || ':' || p.path
      from public.quote_pdf_cache p join public.quotes q on q.id = p.quote_id
     where length(coalesce(p.path,'')) > 0 and p.bucket is not null
    union all
    select t.inquiry_id, 'Reveal invoice or receipt', o.bucket_id, o.name, 'Payment', regexp_replace(o.name,'^.*/',''),
           'RCPT:' || o.bucket_id || ':' || o.name
      from storage.objects o join public.transactions t on left(t.id::text,8) = split_part(o.name,'/',2)
     where o.bucket_id = 'agent-docs' and o.name like 'reveal\_invoice/%' and t.inquiry_id is not null
    union all
    select i2.id, case split_part(o.name,'/',1) when 'compare' then 'Comparison report' else 'Request brief' end,
           o.bucket_id, o.name, 'Reports', regexp_replace(o.name,'^.*/',''), 'IDOC:' || o.bucket_id || ':' || o.name
      from storage.objects o join public.inquiries i2 on i2.id::text = split_part(o.name,'/',2)
     where o.bucket_id = 'agent-docs' and (o.name like 'compare/%' or o.name like 'brief/%')
  ) x
  join public.inquiries i on i.id = x.inquiry_id
  join public.customers c on c.id = i.customer_id
  where not exists (select 1 from public.doc_backups d where d.bucket = x.bucket and d.path = x.path)
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ TABLE EXPORTS (14 SEP 2026, it_engineer) ============
  -- Every file of a FINISHED day's export (public.table_export_run.status = 'done'), filed as
  -- Company -> Database Exports -> month -> day. Only finished days: a day that is re-run rewrites its
  -- pages, and a page mirrored mid-run would be a copy of an export that never completed. Demo rows
  -- never reach these files (fn_table_export_page). A (bucket, path) already queued by another rule
  -- (a refile) is skipped rather than allowed to fail this whole routine on the unique key.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'table_export:' || to_char(r.stamp,'YYYY-MM-DD'), 'Database export', 'backups', o.name,
         regexp_replace(o.name,'^.*/',''),
         '/QuotesDone Backup/Company/Database Exports/' || to_char(r.stamp,'YYYY-MM') || '/' || o.name,
         'storage', 'EXPORT:' || o.name
  from public.table_export_run r
  join storage.objects o on o.bucket_id = 'backups' and o.name like to_char(r.stamp,'YYYY-MM-DD') || '/%'
  where r.status = 'done'
    and not exists (select 1 from public.doc_backups d where d.bucket = 'backups' and d.path = o.name)
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- LEGACY EXPORTS and the STORAGE SWEEP are fn_enqueue_doc_backups_backfill (15 Sep 2026): together they
  -- took this call from milliseconds to 50 s, past PostgREST's 8 s, and every new document stopped.
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_enqueue_doc_backups_backfill(p_limit integer DEFAULT 200)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare n integer := 0; m integer;
begin
  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'fn_enqueue_doc_backups_backfill: p_limit is 1..1000 (got %)', p_limit;
  end if;

  -- ============ LEGACY EXPORTS (15 SEP 2026, it_engineer) ============
  -- The founder: "that data should never get lost no matter what". backup v1's dated folders (on or
  -- before 2026-09-07, no table_export_run row: the legacy-day definition fn_backup_prune_days uses) are
  -- filed exactly like a TABLE EXPORTS day, so retention recognises the copies. At most p_limit (200)
  -- legacy rows wait at a time, oldest day first: the uploader claims lowest id first, so a new customer
  -- or supplier document waits behind at most 200 export pages (measured median 2.6 MB). Refilled on
  -- every non-chained dropbox_backup run. One call at a time tops the queue up (review: a second scheduler
  -- and a kick can overlap, and each would read the same waiting count); a run that loses the lock skips
  -- only this section.
  if pg_try_advisory_xact_lock(hashtext('fn_enqueue_doc_backups:legacy_exports')) then
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'table_export:' || split_part(o.name,'/',1), 'Database export', 'backups', o.name,
         regexp_replace(o.name,'^.*/',''),
         '/QuotesDone Backup/Company/Database Exports/' || left(o.name, 7) || '/' || o.name,
         'storage', 'EXPORT:' || o.name
  from storage.objects o
  where o.bucket_id = 'backups' and o.name ~ '^\d{4}-\d{2}-\d{2}/' and split_part(o.name,'/',1) <= '2026-09-07'
    and not exists (select 1 from public.table_export_run r where r.stamp::text = split_part(o.name,'/',1))
    and not exists (select 1 from public.doc_backups d where d.bucket = 'backups' and d.path = o.name)
  order by o.name
  limit greatest(0, p_limit - (select count(*) from public.doc_backups w
                                 where w.dedupe_key like 'EXPORT:%' and w.status in ('pending', 'processing', 'error', 'waiting_source')
                                   and w.bucket = 'backups' and split_part(w.path,'/',1) <= '2026-09-07'
                                   and not exists (select 1 from public.table_export_run r2 where r2.stamp::text = split_part(w.path,'/',1))))
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;
  end if;

  -- ============ STORAGE SWEEP (15 SEP 2026, it_engineer) ============
  -- The founder: "of course that data should never get lost no matter what". Every stored file no owner
  -- rule filed: fn_backup_sweep_objects() is the one list of what may be swept (the registry's swept
  -- buckets, without ZZ DEMO, demo owners, the export and conversation folders of backups, or any file
  -- of a customer PDPL is erasing; each row carries its real owner). Filed under Storage/<bucket>/<path> so the
  -- original path, which carries the supplier, inquiry or quote id, is kept. Only files over an hour
  -- old, so an owner rule that runs on the same upload files it first under its owner. At most p_limit
  -- (200) per call, oldest first: the backfill of existing files drains over successive runs.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select s.entity, s.entity_id, 'Stored file', s.bucket, s.path, regexp_replace(s.path,'^.*/',''),
         '/QuotesDone Backup/Storage/' || s.bucket || '/' || s.path,
         'storage', 'SWEEP:' || s.bucket || ':' || s.path
  from public.fn_backup_sweep_objects() s
  where s.created_at < now() - interval '1 hour'
    and not exists (select 1 from public.doc_backups d where d.bucket = s.bucket and d.path = s.path)
  order by s.created_at, s.bucket, s.path
  limit p_limit
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_entity_activity(p_entity text, p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare out jsonb := '[]'::jsonb; l public.leads%rowtype;
begin
  -- comments (all entities)
  out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','comment','title','Comment','actor',c.author,'body',c.body,'at',c.created_at)) from public.entity_comments c where c.entity=p_entity and c.entity_id=p_id),'[]'::jsonb);
  -- audit trail (all entities)
  out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','audit','title',a.action,'actor',a.actor,'at',a.at,'ok',a.ok)) from public.os_audit_log a where a.entity_id=p_id and (a.entity=p_entity or (p_entity='supplier' and a.entity in ('leads','supplier','suppliers')))),'[]'::jsonb);
  if p_entity = 'supplier' then
    select * into l from public.leads where id = p_id::bigint;
    if l.id is not null then
      out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','agent','title',coalesce(nullif(btrim(aa.title),''), aa.kind),'actor',aa.agent,'body',aa.recommendation,'at',aa.created_at,'status',aa.status)) from public.agent_actions aa where aa.target_table='leads' and aa.target_id::text = p_id),'[]'::jsonb);
      out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','milestone','title',v.label,'actor','system','at',v.ts)) from (values
        ('Sourced', l.created_at),('Scraped', l.scraped_at),('Invited', l.invited_at),('AI reviewed', l.ai_reviewed_at),
        ('Documents extracted', l.doc_extracted_at),('Capability enriched', l.capability_enriched_at),
        ('Registration submitted', l.registration_submitted_at),('Terms accepted', l.accepted_terms_at),
        ('Terms signed', l.signed_terms_at),('Approved', l.approved_at)
      ) v(label, ts) where v.ts is not null),'[]'::jsonb);
    end if;
  end if;
  -- QD_RFQ_TRACE: the inquiry lifecycle, assembled from the rows that already record it.
  if p_entity in ('rfq','inquiry') and p_id ~ '^[0-9a-fA-F-]{36}$' then
    out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','milestone','title',v.label,'actor','system','at',v.ts))
      from public.inquiries i cross join lateral (values
             ('Inquiry created', i.created_at),
             ('Moved to stage: '||coalesce(i.pipeline_stage,'(none)'), i.stage_changed_at),
             ('Completed'||coalesce(' — '||i.outcome,''), i.completed_at)
           ) v(label, ts)
     where i.id = p_id::uuid and v.ts is not null),'[]'::jsonb);

    out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','decision',
        'title','Routed to category '||coalesce(i.category,'(none)')||
                case when coalesce(i.rfq_ready,false) then ' — brief complete' else ' — brief NOT complete' end,
        'actor','route_inquiry','body',left(coalesce(i.routing::text,''),400),'at',i.created_at))
      from public.inquiries i where i.id = p_id::uuid and i.routing is not null),'[]'::jsonb);

    out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','document',
        'title',coalesce(d.kind,'document')||' '||coalesce(d.file_name,''),'actor','doc_extract',
        'body','status '||coalesce(d.status,'?')||case when coalesce(d.indexed,false) then ', indexed' else '' end,
        'at',coalesce(d.processed_at,d.created_at)))
      from public.documents d where d.ref_table='inquiries' and d.ref_id::text = p_id),'[]'::jsonb);

    out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','match',
        'title','Dispatched to supplier #'||m.supplier_id||coalesce(' ('||ld.company_name||')',''),
        'actor','dispatch_inquiry',
        'body',coalesce(m.match_reason,'')||coalesce(' score '||m.similarity,''),'at',m.sent_at))
      from public.inquiry_matches m left join public.leads ld on ld.id = m.supplier_id
     where m.inquiry_id = p_id::uuid),'[]'::jsonb);

    out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','quote',
        'title','Quotation AED '||q.quote_amount||' from supplier #'||q.supplier_id,
        'actor',coalesce(q.source,'form'),
        'body','status '||coalesce(q.status,'?')||coalesce(', quality '||q.quality::text,''),
        'at',q.created_at,'status',q.status))
      from public.quotes q where q.inquiry_id = p_id::uuid),'[]'::jsonb);

    out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','comparison',
        'title','Quotation comparison produced','actor','quote_compare',
        'body',left(coalesce(c.explanation_en::text,''),400),'at',c.created_at))
      from public.comparison_run_v2 c where c.inquiry_id = p_id::uuid),'[]'::jsonb);

    out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','reveal',
        'title','Supplier revealed to the customer for AED '||t.reveal_fee,'actor','customer','at',t.revealed_at))
      from public.transactions t where t.inquiry_id = p_id::uuid and t.revealed_at is not null),'[]'::jsonb);

    out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','event','title',e.event_type,
        'actor',coalesce(e.actor,'system'),'at',e.occurred_at))
      from public.company_event e where e.entity_type in ('inquiry','inquiries') and e.entity_id = p_id),'[]'::jsonb);

    out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','agent',
        'title',coalesce(nullif(btrim(aa.title),''), aa.kind),'actor',aa.agent,
        'body',aa.recommendation,'at',aa.created_at,'status',aa.status))
      from public.agent_actions aa where aa.target_table='inquiries' and aa.target_id::text = p_id),'[]'::jsonb);
  end if;


  -- CONFIGURATION ENTITIES. pricing_config, model_policy and prompts are changed by the company
  -- itself, and their history is the row-level change log rather than the action log. Without this
  -- branch "when did AI change pricing" had no reader at all.
  if p_entity in ('pricing_config','model_policy','prompts','config') then
    out := out || coalesce((select jsonb_agg(jsonb_build_object(
        'kind','change','title', u.op || ' on ' || u.table_name,
        'actor', coalesce(u.actor,'system'), 'at', u.created_at,
        'reverted', u.reverted, 'row_id', u.row_id) order by u.created_at desc)
      from (select * from public.undo_log u
             where u.table_name = p_entity
               and (coalesce(p_id,'') = '' or u.row_id::text = p_id)
             order by u.created_at desc limit 50) u), '[]'::jsonb);
  end if;

  return coalesce((select jsonb_agg(e) from (select e from jsonb_array_elements(out) e where (e->>'at') is not null order by (e->>'at') desc limit 80) z),'[]'::jsonb);
end $function$


CREATE OR REPLACE FUNCTION public.fn_entity_comment_add(p_entity text, p_id text, p_author text, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare r public.entity_comments%rowtype;
begin
  if coalesce(btrim(p_body),'') = '' then return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  insert into public.entity_comments(entity, entity_id, author, body)
    values (p_entity, p_id, coalesce(nullif(btrim(p_author),''),'operator'), left(p_body, 4000))
    returning * into r;
  return jsonb_build_object('ok', true, 'id', r.id, 'at', r.created_at);
end $function$


CREATE OR REPLACE FUNCTION public.fn_entity_files(p_entity text, p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare out jsonb := '[]'::jsonb; l public.leads%rowtype;
begin
  if p_entity = 'supplier' then
    select * into l from public.leads where id = p_id::bigint;
    if l.id is not null then
      if l.license_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Trade licence','name',coalesce(l.license_doc_name,'trade licence'),'bucket','supplier-docs','path',l.license_doc_path); end if;
      if l.egr_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Establishment card','name',coalesce(l.egr_doc_name,'establishment card'),'bucket','supplier-docs','path',l.egr_doc_path); end if;
      if l.insurance_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Insurance','name','insurance','bucket','supplier-docs','path',l.insurance_doc_path); end if;
      if l.vat_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','VAT certificate','name','vat certificate','bucket','supplier-docs','path',l.vat_doc_path); end if;
      if l.company_profile_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Company profile','name','company profile','bucket','supplier-docs','path',l.company_profile_doc_path); end if;
      if l.signed_terms_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Signed terms','name','signed terms','bucket','signed-terms','path',l.signed_terms_path); end if;
      if l.catalog_doc_paths is not null then
        out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Catalogues','type','Catalogue','name','catalogue','bucket','supplier-docs','path',x)) from unnest(l.catalog_doc_paths) x),'[]'::jsonb);
      end if;
      -- Storage scan: surface any stored documents whose column pointers are null (files live under <folder>/<supplier_id>/<file>).
      out := out || coalesce((
        select jsonb_agg(jsonb_build_object(
          'group', case when split_part(o.name,'/',1) in ('catalogs','catalogues') then 'Catalogues'
                        when o.bucket_id = 'signed-terms' then 'Signed terms'
                        else 'Compliance documents' end,
          'type', case split_part(o.name,'/',1)
                    when 'licence' then 'Trade licence' when 'license' then 'Trade licence' when 'licenses' then 'Trade licence'
                    when 'certs' then 'Certificate' when 'cert' then 'Certificate' when 'insurance' then 'Insurance'
                    when 'profile' then 'Company profile' when 'company_profile' then 'Company profile'
                    when 'catalogs' then 'Catalogue' when 'catalogues' then 'Catalogue'
                    when 'vat' then 'VAT certificate' when 'egr' then 'Establishment card'
                    when 'terms' then 'Signed terms'
                    else initcap(replace(split_part(o.name,'/',1),'_',' ')) end,
          'name', regexp_replace(split_part(o.name,'/', greatest(array_length(string_to_array(o.name,'/'),1),1)), '^[0-9]+_', ''),
          'bucket', o.bucket_id,
          'path', o.name))
        from storage.objects o
        where o.bucket_id in ('supplier-docs','signed-terms')
          and split_part(o.name,'/',2) = p_id
          and not exists (select 1 from jsonb_array_elements(out) xx where xx->>'path' = o.name)
      ), '[]'::jsonb);
    end if;
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Quotations submitted','type','Quote #'||q.id,'name',coalesce(q.original_file_name,'quote file'),'bucket','quote-files','path',q.original_file_path) order by q.created_at desc)
                            from public.quotes q where q.supplier_id = p_id::bigint and q.original_file_path is not null),'[]'::jsonb);

  elsif p_entity = 'customer' then
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Drawings & RFQ files','type','RFQ drawing','name',coalesce(i.drawing_file_name,'drawing'),'bucket','drawing-files','path',i.drawing_file_path) order by i.created_at desc)
                            from public.inquiries i where i.customer_id = p_id::uuid and i.drawing_file_path is not null),'[]'::jsonb);
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Quotations received','type','Quote #'||q.id,'name',coalesce(q.original_file_name,'quote file'),'bucket','quote-files','path',q.original_file_path) order by q.created_at desc)
                            from public.quotes q join public.inquiries i on i.id = q.inquiry_id where i.customer_id = p_id::uuid and q.original_file_path is not null),'[]'::jsonb);

  elsif p_entity in ('rfq','inquiry') then
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Drawing','type','RFQ drawing','name',coalesce(i.drawing_file_name,'drawing'),'bucket','drawing-files','path',i.drawing_file_path))
                            from public.inquiries i where i.id = p_id::uuid and i.drawing_file_path is not null),'[]'::jsonb);
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Quotations','type','Quote #'||q.id,'name',coalesce(q.original_file_name,'quote file'),'bucket','quote-files','path',q.original_file_path) order by q.created_at desc)
                            from public.quotes q where q.inquiry_id = p_id::uuid and q.original_file_path is not null),'[]'::jsonb);
  end if;
  return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_eval_snapshot(p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  intake_total int; intake_complete int; q_total int; q_scored int; q_pass numeric; q_avg numeric;
  inq_matched int; inq_all int; inq_done int; inq_open int; esc_pending int; esc_total int; lat_avg numeric;
  dec_total int; dec_grounded int; k jsonb;
begin
  select count(*) filter (where created_at > now()-(p_days||' days')::interval),
         count(*) filter (where created_at > now()-(p_days||' days')::interval and coalesce(rfq_ready,false))
    into intake_total, intake_complete from inquiries;
  select count(*) filter (where created_at > now()-(p_days||' days')::interval),
         count(*) filter (where created_at > now()-(p_days||' days')::interval and quality is not null),
         avg(nullif(quality->>'score','')::numeric) filter (where created_at > now()-(p_days||' days')::interval),
         count(*) filter (where created_at > now()-(p_days||' days')::interval and nullif(quality->>'score','')::numeric >= 60)
    into q_total, q_scored, q_avg, q_pass from quotes;
  select count(*) filter (where i.created_at > now()-(p_days||' days')::interval),
         count(*) filter (where i.created_at > now()-(p_days||' days')::interval and exists(select 1 from inquiry_matches m where m.inquiry_id=i.id))
    into inq_all, inq_matched from inquiries i;
  select count(*) filter (where created_at > now()-(p_days||' days')::interval and (status in ('completed','accepted','closed') or completed_at is not null)),
         count(*) filter (where created_at > now()-(p_days||' days')::interval) into inq_done, inq_open from inquiries;
  begin select count(*) filter (where created_at > now()-(p_days||' days')::interval and status='pending'), count(*) filter (where created_at > now()-(p_days||' days')::interval) into esc_pending, esc_total from agent_actions; exception when others then esc_pending:=0; esc_total:=0; end;
  begin select round(avg(extract(epoch from (finished_at-started_at)))::numeric,1) into lat_avg from agent_runs where started_at > now()-(p_days||' days')::interval and finished_at is not null; exception when others then lat_avg:=null; end;
  begin select count(*), count(*) filter (where jsonb_array_length(coalesce(sources,'[]'))>0) into dec_total, dec_grounded from decision_log where created_at > now()-(p_days||' days')::interval; exception when others then dec_total:=0; dec_grounded:=0; end;

  k := jsonb_build_object(
    'window_days', p_days,
    'rfq_completeness_pct', case when intake_total=0 then null else round(intake_complete::numeric/intake_total*100,1) end,
    'quote_gate_pass_pct',  case when q_scored=0 then null else round(q_pass::numeric/q_scored*100,1) end,
    'quote_quality_avg',    round(coalesce(q_avg,0),1),
    'match_coverage_pct',   case when inq_all=0 then null else round(inq_matched::numeric/inq_all*100,1) end,
    'resolution_pct',       case when inq_open=0 then null else round(inq_done::numeric/inq_open*100,1) end,
    'escalation_rate_pct',  case when esc_total=0 then null else round(esc_pending::numeric/esc_total*100,1) end,
    'agent_latency_sec_avg',lat_avg,
    'decision_grounding_pct', case when dec_total=0 then null else round(dec_grounded::numeric/dec_total*100,1) end,
    'clarification_efficiency', null, 'hallucination_rate_pct', null, 'customer_satisfaction', null,
    'samples', jsonb_build_object('inquiries',intake_total,'quotes',q_total,'agent_actions',esc_total,'decisions',dec_total));
  return k;
end $function$


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
              'ceo', jsonb_build_object('lessons_added', n_lessons));
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
end $function$


CREATE OR REPLACE FUNCTION public.fn_event_dispatch(p_lookback_minutes integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_delivered integer := 0; v_tasks integer := 0; v_gated integer := 0;
        v_unroutable integer := 0; v_assessed integer := 0; v_attached integer := 0;
        r record; v_task bigint; v_dept text; v_tier text; v_os text;
        v_impact text; v_subject_task bigint;
        v_title text; v_detail text; v_open_task bigint;
        -- RECURRENCE COOL-DOWN (14 Aug 2026). See the migration header: the open-task guard
        -- below cannot see a condition that is STILL TRUE after its task was closed, so a
        -- standing miss re-minted itself every tick and was answered again at the large tier.
        v_recur_task bigint; v_suppressed integer := 0; v_cooldown_days integer;
        v_open_bus integer; v_capped boolean; v_backpressured integer := 0;
        -- 5 SEP 2026: per-pair failures are counted and carried, never allowed to abort the batch.
        v_failed integer := 0; v_first_err text;
        -- BACK-PRESSURE. 25 OPEN BUS TASKS PER DEPARTMENT, MEASURED 6 Aug 2026 ON PRODUCTION.
        --
        -- The queue grows ~100x faster than it drains. The dispatcher mints up to 50 (event,
        -- subscriber) pairs per */15 tick — 329 events arrived in the last 24 hours — while the
        -- whole organisation closed 132 org_tasks in 30 days, 4.4 a day. Of those 132, ZERO were
        -- bus-minted: all 395 tasks this routine has ever authored are still open, none has ever
        -- reached 'done'. 395 pieces of work nobody will ever reach is the same built-and-never-
        -- read defect the blueprint exists to catch, one level up.
        --
        -- 25 is the cap because it is generous against the MEASURED drain of every department.
        -- Closures in 30d, by department: knowledge 41, exec 32, it 14, procurement 8,
        -- knowledge_eng 7, finance 7, marketing 6, legal 5, evolution 4, intelligence 4,
        -- supplier_success 2, hr 1, sales 1. At the FASTEST of those, 25 open bus tasks is
        -- eighteen days of queue; at the median (5/30d) it is five months. A department holding
        -- more than 25 is not busy, it is unreachable, and minting a 26th is writing into a
        -- surface with no reader.
        --
        -- Open bus queue when this cap was chosen: knowledge 102, exec 97, knowledge_eng 46,
        -- sales 36, marketing 32 (over) — finance 19, evolution 19, intelligence 19, legal 12,
        -- it 12, procurement 1 (under). So the bus keeps minting per-event work for six of the
        -- eleven departments and stops piling it onto the five that are already buried.
        c_max_open_per_dept integer := coalesce((select (value #>> '{}')::int from public.decision_policy where key = 'dispatch_max_open_per_dept'), 250);
        -- 50, MEASURED, NOT GUESSED. The backlog this uncovers is 147 undelivered (event,
        -- subscriber) pairs — 145 routable, 2 unroutable, across 99 events — against 182 open
        -- tasks today. Draining it in one tick would nearly double the open queue in fifteen
        -- minutes; at 50 it lands over three ticks and the first one can be inspected before the
        -- rest arrives. The cap bounds the RATE, not the total: the backlog is finite and the
        -- loop still delivers every pair.
        c_max_batch integer := coalesce((select (value #>> '{}')::int from public.decision_policy where key = 'dispatch_max_batch'), 500);
begin
  -- Policy, not deploy. 0 disables the cool-down and restores the pre-14-Aug behaviour exactly.
  select coalesce((value #>> '{}')::int, 7) into v_cooldown_days
    from decision_policy where key = 'event_recur_cooldown_days';
  v_cooldown_days := coalesce(v_cooldown_days, 7);
  -- ── PASS 1 · ASSESS EVERYTHING PENDING, BEFORE ACTING ON ANY OF IT ──────────────────────────
  -- xos-04. The severity is the OS's own declared reading of this input from os_interface; the
  -- impact names which of the OS's declared responsibilities the event touches. Both come from
  -- tables the founder populated, so this is a JOIN, not a judgement. A NULL severity is itself
  -- the finding: the OS received an event it never declared it consumes, which is exactly the
  -- os_interface/event_subscription drift comp-07 measures.
  --
  -- HOISTED OUT OF THE LOOP 6 Aug 2026, AND IT IS A CORRECTNESS FIX, NOT A TIDY-UP. It used to sit
  -- inside the loop, one insert per iteration, which made "assessed before acting" true PER EVENT
  -- and false ACROSS THE BATCH. Any branch that ATTACHES event j to a task minted for event i
  -- earlier in the same run stamps assessed_at(j) AFTER created_at(i's task) — and when that task
  -- was raised after event j occurred, that reads exactly like acting before assessing. MEASURED
  -- on staging with the back-pressure branch in the loop: 56 deliveries assessed after the task
  -- they attached to, 50 of them on a back-pressure task, from a production baseline of 0. The
  -- latent form of the same hazard was already there in the duplicate-subject attach.
  --
  -- One statement, before any org_tasks row in this run exists, so every assessment strictly
  -- precedes every task and every delivery this run creates. The order is real, not asserted.
  --
  -- DELIBERATELY UNBOUNDED, where the delivery loop below takes 50. The two queries are separate
  -- and the invariant between them is "pass 1 is a SUPERSET of pass 2", not "identical" — a much
  -- weaker thing to keep true. Assessing an event this tick that gets delivered three ticks later
  -- is free (the insert is idempotent on (event_id, os_key)) and still correct: it was assessed
  -- before it was acted on. Sharing a LIMIT, by contrast, could cut the two batches differently on
  -- an e.id tie and leave a delivered pair unassessed, which is the one outcome xos-04 forbids.
  --
  -- The inner joins to org_agents/os_department are the v_os test from the old inline form: a
  -- subscription pointing at an employee who does not exist, or a department belonging to no OS,
  -- produces no assessment here and is handled as unroutable in the loop, exactly as before.
  with pending as (
    select distinct on (e.id, od.os_key)
           e.id as event_id, e.event_type, od.os_key, s.agent_key, s.reason
      from company_event e
      join event_subscription s on s.active and s.event_type = e.event_type
                               and s.agent_key <> coalesce(e.actor, '')
      join org_agents a         on a.agent_key = s.agent_key
      join os_department od     on od.dept_key = a.department
      left join event_delivery d on d.event_id = e.id and d.agent_key = s.agent_key
     where d.id is null
       and (p_lookback_minutes <= 0
            or e.occurred_at > now() - make_interval(mins => p_lookback_minutes))
     order by e.id, od.os_key, s.agent_key
  )
  insert into event_assessment (event_id, os_key, agent_key, severity, impact, proposed_action,
                                assessed_at)
  select p.event_id, p.os_key, p.agent_key, coalesce(i.severity, 'medium'),
         format('%s affects %s: %s', p.event_type, p.os_key,
                coalesce(rs.resp, 'no declared responsibilities')),
         case when i.severity is null
              then 'UNDECLARED INPUT: os_interface does not list this event type for this OS'
              else coalesce(p.reason, 'act on the subscription') end,
         -- clock_timestamp(), NOT the column default. "BEFORE acting" was UNMEASURABLE while every
         -- timestamp here came from now(): now() is TRANSACTION start, so the assessment, the task
         -- and the delivery all carried the identical value and `assessed_at > created_at` read 0
         -- whatever order the statements ran in. clock_timestamp() is statement time, so the
         -- ordering below is stored rather than assumed. Move this block after the loop and
         -- xos-04 fails, which is the property that makes it a measurement.
         clock_timestamp()
    from pending p
    left join lateral (select i2.severity from os_interface i2
                        where i2.os_key = p.os_key and i2.event_type = p.event_type
                          and i2.direction = 'input' limit 1) i on true
    left join lateral (select string_agg(x.responsibility, ', ') as resp
                         from (select responsibility from os_responsibility
                                where os_key = p.os_key order by responsibility limit 3) x) rs on true
  on conflict (event_id, os_key) do nothing;
  get diagnostics v_assessed = row_count;

  -- ── PASS 2 · ROUTE, RAISE WORK, DELIVER ─────────────────────────────────────────────────────
  -- p_lookback_minutes is KEPT and now means what its name says: an optional narrowing for a
  -- manual catch-up run, not a wall that silently drops events. <= 0 means "every undelivered
  -- event, however old", which is the setting the cron uses.
  for r in
    select e.id as event_id, e.event_type, e.entity_type, e.entity_id, e.actor, e.occurred_at,
           e.correlation_id, e.payload, s.agent_key, s.reason,
           -- 6 SEP 2026: the subscription may name the executor class its task carries (see the
           -- header of scripts/sql/the_onboarding_specialist_checks_every_registration.sql).
           s.action_class as sub_action_class
    from company_event e
    join event_subscription s on s.active and s.event_type = e.event_type
    left join event_delivery d on d.event_id = e.id and d.agent_key = s.agent_key
    where d.id is null
      and (p_lookback_minutes <= 0
           or e.occurred_at > now() - make_interval(mins => p_lookback_minutes))
      and s.agent_key <> coalesce(e.actor, '')
    order by e.id
    -- BOUNDED ON PURPOSE. Dropping the time filter exposes a real backlog, and this bus has
    -- already produced 169 tasks in one hour once. A batch cap drains it over consecutive ticks
    -- instead of in a single burst, and the cron runs every 15 minutes.
    limit c_max_batch
  loop
    -- 5 SEP 2026: one sub-transaction per pair. See the header: a single raising pair used to roll
    -- back the whole batch, and at the head of the cron sweep it blocked every delivery behind it.
    begin
    select department into v_dept from org_agents where agent_key = r.agent_key;
    -- xos-03. The OS, not just the agent. Resolved through the same os_department link the rest
    -- of the blueprint uses, so a department that belongs to no OS is visibly null rather than
    -- silently defaulted to one.
    select od.os_key into v_os from os_department od where od.dept_key = v_dept;
    v_task := null;

    -- xos-14. Everything raised from here on belongs to THIS event's chain and was CAUSED by it.
    -- Set before any insert so a trigger firing downstream inherits both through the column
    -- defaults on company_event — that is why the defaults read a setting rather than a literal.
    perform set_config('app.correlation_id', coalesce(r.correlation_id::text, ''), true);
    perform set_config('app.causation_event_id', r.event_id::text, true);

    if v_dept is null then
      -- xos-05. Say why. An unroutable subscription is a real defect in the subscription table
      -- and it was previously indistinguishable from a task that had not been created yet.
      --
      -- AND IT IS CLOSED HERE, 6 Aug 2026. An unroutable delivery is TERMINAL: no task exists, no
      -- task will ever exist, and no result can ever come back — so leaving result/closed_at NULL
      -- filed it forever as "loop still open". It is not open; it finished, badly, at this instant,
      -- and the reason it finished is already on the row. contract-consolidation asks whether the
      -- deliveries the bus made came back with a result; a broken subscription that can never come
      -- back dragged that ratio down permanently and no amount of correct work could ever clear it.
      -- The result is the reason, not a placeholder, and closed_at is now, not the delivery's past.
      insert into event_delivery (event_id, agent_key, event_type, os_key, task_id, delivered_at,
                                  unroutable_reason, result, closed_at)
      values (r.event_id, r.agent_key, r.event_type, v_os, null, clock_timestamp(),
              format('no org_agents row for subscriber %s — this subscription points at an '
                  || 'employee who does not exist, so the event reaches nobody', r.agent_key),
              left(format('unroutable: no org_agents row for subscriber %s; the event reached '
                  || 'nobody and nothing further will happen to this delivery', r.agent_key), 1000),
              clock_timestamp())
      on conflict do nothing;
      v_unroutable := v_unroutable + 1;
      v_delivered  := v_delivered + 1;
      continue;
    end if;

    -- 7.3 PRECONDITION. This used to hard-code tier 'autonomous', so a subscriber was granted
    -- autonomy by the dispatcher rather than by the authority model. It reads the tier now.
    v_tier := coalesce(public.fn_dept_authority(v_dept, 'analysis')->>'tier', 'gated');
    if v_tier <> 'autonomous' then v_gated := v_gated + 1; end if;

    -- xos-04. The assessment for this (event, OS) was written in PASS 1, before this loop began
    -- and therefore before any task in this run exists. Read the impact back for the task detail
    -- below rather than recomputing it, so the sentence the employee reads is the same sentence
    -- the OS recorded. NULL when the department resolves to no OS, which coalesce() handles.
    select a.impact into v_impact
      from event_assessment a where a.event_id = r.event_id and a.os_key = v_os;

    -- xos-05 / contract-consolidation. THE EVENT THAT REPORTS ON WORK IS NOT NEW WORK.
    --
    -- MEASURED 6 Aug 2026, and it is a divergent feedback loop, not an inefficiency. Closing one
    -- task runs fn_task_review, which writes 3-4 review_chain rows; trg_event_review emits one
    -- review.step per row; knowledge_director subscribes to review.step; and this loop minted a
    -- fresh org_task for every one of them. review.step was 183 of the ~300 events of the last
    -- seven days and 217 of 576 deliveries all time. The Chief of Staff's executor closes 2 tasks
    -- an hour, so every closure created 3-4 new tasks and the queue grew by working it — 336 open
    -- event-derived tasks against 58 ever closed, and no coverage ratio for "the loop closes"
    -- could ever be satisfied while that held.
    --
    -- The row already says what the event is about: fn_emit_event copies the whole source row into
    -- payload, so a review_chain event carries subject_type='org_task' and subject_id. When the
    -- event REPORTS ON a task that exists, the work is that task. The delivery is attached to it,
    -- so the result that comes back is that task's own result and the loop closes on the work
    -- itself rather than on a duplicate of it. Nothing is dropped: the delivery, its os_key and
    -- its assessment (pass 1) are all still written.
    --
    -- Scoped by the payload, not by an event-type list: any future emitter whose row names an
    -- org_task subject gets the same treatment, and one that does not still raises a task.
    v_subject_task := null;
    if r.payload->>'subject_type' = 'org_task' and coalesce(r.payload->>'subject_id','') ~ '^[0-9]+$' then
      select t.id into v_subject_task
        from org_tasks t where t.id = (r.payload->>'subject_id')::bigint;
    end if;
    if v_subject_task is not null then
      insert into event_delivery (event_id, agent_key, event_type, os_key, task_id, delivered_at)
      values (r.event_id, r.agent_key, r.event_type, v_os, v_subject_task, clock_timestamp())
      on conflict do nothing;
      v_attached  := v_attached + 1;
      v_delivered := v_delivered + 1;
      continue;
    end if;

    -- THE SAME SUBJECT, RAISED AGAIN, IS NOT A SECOND PIECE OF WORK.
    --
    -- The attach above handles an event that REPORTS ON a task. This is its sibling: an event that
    -- re-reports the SAME SUBJECT to the SAME department while that department's task for it is
    -- still open and untouched. MEASURED 6 Aug 2026 on production: of 372 open bus-minted tasks,
    -- 107 (29%) are duplicate copies — 'test.failed on scheduled_run uptime' had SIX open copies
    -- raised the same day, 'kpi.missed on metric open_p1' three. The Chief of Staff's executor
    -- closes 2 tasks an hour, so a condition that re-fires hourly minted copies faster than the
    -- company could ever work them, and every copy diluted the coverage the closing loop is scored
    -- on. The title is the subject identity the mint below already builds from event_type +
    -- entity_type + entity_id, so it is computed once here and reused rather than re-derived.
    --
    -- The delivery is STILL WRITTEN — the denominator does not shrink, and that is the point. When
    -- the department finally does the work, fn_event_consolidate closes EVERY delivery attached to
    -- that task, so all six events that reported the failure get the same result back. That is the
    -- contract ("the result comes back to the event that caused the work"), not an exemption from it.
    --
    -- Scoped to decided_by='fn_event_dispatch' so the bus can only ever attach to its OWN open
    -- task: a human's or another routine's task with a colliding title is never hijacked.
    -- ── BACK-PRESSURE ─────────────────────────────────────────────────────────────────────────
    -- THE BUS MUST NOT MINT NEW WORK INTO A DEPARTMENT WHOSE BUS QUEUE IS NOT DRAINING.
    --
    -- The two attach branches above stop the bus DUPLICATING work. Neither of them stops it
    -- OUTPACING the company: 395 bus tasks minted, 0 ever closed, against an organisation that
    -- closes 4.4 tasks a day across every department and every author. Deduplication cannot fix
    -- a rate mismatch — every one of those 395 is a distinct subject.
    --
    -- So the department's own open bus queue is the signal. Over the cap, this event does not get
    -- its own task; it is collapsed onto the department's single standing back-pressure task by
    -- rewriting v_title to a per-department constant. That makes the attach lookup immediately
    -- below do the work — the first over-cap event mints the standing task, every later one
    -- attaches to it — instead of adding a third near-identical branch beside the two above.
    --
    -- WHAT IS NOT SKIPPED, AND BOTH ARE THE POINT:
    --  * THE DELIVERY IS STILL WRITTEN, below, exactly as in every other branch. Skipping it would
    --    make the event permanently undeliverable again — the xos-02 defect at the top of this
    --    file — and would SHRINK the denominator of contract-consolidation, flattering that ratio
    --    while fixing nothing. Back-pressure regulates work, never the ledger.
    --  * THE ASSESSMENT IS ALREADY WRITTEN, in PASS 1, before this loop began — so it cannot be
    --    reached by any decision taken here. xos-04 says nothing is acted on unassessed, and no
    --    reordering of the branches in this loop can lose one or stamp one late.
    -- And when the department finally drains the standing task, fn_event_consolidate closes EVERY
    -- delivery attached to it, so all the queued events get their result back. Same contract as
    -- the duplicate-subject attach, one level up.
    select count(*) into v_open_bus
      from org_tasks t
     where t.decided_by = 'fn_event_dispatch'
       and t.dept_key = v_dept
       and t.status not in ('done','closed','cancelled');
    v_capped := v_open_bus >= c_max_open_per_dept;

    if v_capped then
      v_title  := left('bus.backpressure on department ' || v_dept, 200);
      v_detail := format('BUS BACK-PRESSURE — %s holds %s open task(s) raised by the event bus and '
                      || 'the bus has stopped minting more into it (cap %s). Events still arrive: '
                      || 'each one is delivered and assessed as normal and attached to THIS task '
                      || 'instead of raising its own, so nothing is lost and the queue stops '
                      || 'growing. Drain %s below %s open bus tasks and per-event tasks resume by '
                      || 'themselves. Close this one when the backlog is worked; every event '
                      || 'queued behind it gets that result back. Latest arrival: %s (%s %s) at %s.',
                         v_dept, v_open_bus, c_max_open_per_dept, v_dept, c_max_open_per_dept,
                         r.event_type, r.entity_type, coalesce(r.entity_id,'-'), r.occurred_at);
    else
      v_title  := left(r.event_type || ' on ' || r.entity_type || ' ' || coalesce(r.entity_id,''), 200);
      v_detail := format('Event %s (%s %s) raised by %s at %s. You subscribe to this because: %s. '
                      || 'Assessed impact: %s. Act on it or close it with a reason.',
                         r.event_type, r.entity_type, coalesce(r.entity_id,'-'),
                         coalesce(r.actor,'system'), r.occurred_at,
                         coalesce(r.reason,'subscription'), coalesce(v_impact,'not assessed'));
    end if;

    -- `status not in ('done','closed','cancelled')` rather than the old
    -- `in ('proposed','assigned','in_progress')`: the two lists disagreed about 'escalated', so an
    -- escalated task was open for the count above and closed for this lookup — which would mint a
    -- SECOND standing back-pressure task the moment the first one escalated, and had already been
    -- duplicating escalated subject tasks. One definition of open, used by both.
    select t.id into v_open_task
      from org_tasks t
     where t.decided_by = 'fn_event_dispatch'
       and t.dept_key = v_dept
       and t.title = v_title
       and t.status not in ('done','closed','cancelled')
     order by t.id
     limit 1;
    if v_open_task is not null then
      insert into event_delivery (event_id, agent_key, event_type, os_key, task_id, delivered_at)
      values (r.event_id, r.agent_key, r.event_type, v_os, v_open_task, clock_timestamp())
      on conflict do nothing;
      v_attached  := v_attached + 1;
      if v_capped then v_backpressured := v_backpressured + 1; end if;
      v_delivered := v_delivered + 1;
      continue;
    end if;

    -- ALREADY ANSWERED, INSIDE THE COOL-DOWN. The lookup above found nothing OPEN, which for a
    -- recurring condition means the last one was closed, not that the question is new. Attach
    -- to the task that already carries the answer rather than buying another one.
    if v_cooldown_days > 0 then
      select t.id into v_recur_task
        from org_tasks t
       -- Provenance is the delivery, not decided_by: the executor overwrites decided_by when
       -- it settles the row, so no closed task has ever carried 'fn_event_dispatch'.
       where exists (select 1 from event_delivery ed where ed.task_id = t.id)
         and t.dept_key = v_dept
         and t.title = v_title
         and t.status in ('done','closed','cancelled')
         and coalesce(t.updated_at, t.created_at) > clock_timestamp() - make_interval(days => v_cooldown_days)
       order by coalesce(t.updated_at, t.created_at) desc
       limit 1;
      if v_recur_task is not null then
        insert into event_delivery (event_id, agent_key, event_type, os_key, task_id, delivered_at)
        values (r.event_id, r.agent_key, r.event_type, v_os, v_recur_task, clock_timestamp())
        on conflict do nothing;
        v_suppressed := v_suppressed + 1;
        v_delivered  := v_delivered + 1;
        continue;
      end if;
    end if;

    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class,
                           decided_by, created_at)
    values (v_dept,
            v_title,
            v_detail,
            case when v_tier = 'autonomous' then 'assigned' else 'proposed' end,
            v_tier,
            -- 9 SEP 2026 -- THE PROGRAMME AND ITS KERNEL ARE REMOVED, founder ruling of 8 Sep
            -- 2026: "remove them totally. i dont want to see their names popping anymore."
            --
            -- This argument used to be an exists() against the programme's action-class table,
            -- asking whether the 'analysis' class required founder approval. It read that table
            -- because the kernel's refund-only routing guard enforced the SAME table one level up,
            -- so the writer and the guard could not disagree and mint a task the guard then
            -- refused with 23514. Both the table and that guard are dropped in this same sweep.
            --
            -- MEASURED 9 Sep 2026, BEFORE REMOVAL: 'analysis' was not a row in that table at all
            -- (26 rows; only 'refund_decision' required founder approval). The exists() was
            -- therefore a constant FALSE, and every bus task this routine has ever minted was
            -- already written needs_founder = false. The literal below is that same answer with
            -- the dependency gone -- it is not a policy change. A gated task still goes up the
            -- INTERNAL chain: it is written 'proposed' above and fn_task_approve resolves the
            -- entitled head. Nothing on this path pages the founder.
            false,
            -- 6 SEP 2026: 'analysis' unless the subscription names a class. The tier above and the
            -- needs_founder test stay on 'analysis' -- the department's authority to work bus tasks
            -- is unchanged; only the executor the org_task lane looks up by this class differs.
            coalesce(r.sub_action_class, 'analysis'), 'fn_event_dispatch', clock_timestamp())
    returning id into v_task;
    v_tasks := v_tasks + 1;
    -- The standing task counts as back-pressured too: it is the one task the cap allows, not a
    -- per-event task that slipped through. Counted so `backpressured` in the return value is the
    -- full number of events the cap handled, and never silently one short.
    if v_capped then v_backpressured := v_backpressured + 1; end if;

    insert into event_delivery (event_id, agent_key, event_type, os_key, task_id, delivered_at)
    values (r.event_id, r.agent_key, r.event_type, v_os, v_task, clock_timestamp())
    on conflict do nothing;
    v_delivered := v_delivered + 1;
    exception when others then
      v_failed := v_failed + 1;
      if v_first_err is null then
        v_first_err := format('%s %s (event %s -> %s)', sqlstate, left(sqlerrm, 300), r.event_id, r.agent_key);
      end if;
    end;
  end loop;

  -- Leave no correlation bound to the session after the loop: a later statement on this
  -- connection is NOT part of the last event's chain, and inheriting it would be a false link.
  perform set_config('app.correlation_id', '', true);
  perform set_config('app.causation_event_id', '', true);

  -- 5 SEP 2026: a failed pair is a real failure and is said once per call, on the ledger the
  -- failed-runs watcher reads. It is not re-raised: re-raising is exactly the head-of-line block.
  if v_failed > 0 then
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('event_dispatch', clock_timestamp(), clock_timestamp(), 'error',
            jsonb_build_object('pairs_failed', v_failed, 'delivered', v_delivered, 'lookback_minutes', p_lookback_minutes),
            left(format('%s (event, subscriber) pair(s) failed and were left undelivered for the next pass; '
                     || 'the other %s pair(s) in the batch were delivered. First failure: %s', v_failed, v_delivered, v_first_err), 1000));
  end if;

  return jsonb_build_object('delivered', v_delivered, 'tasks_created', v_tasks,
                            'attached_to_existing_task', v_attached,
                            'backpressured', v_backpressured,
                            'suppressed_recurring', v_suppressed,
                            'recur_cooldown_days', v_cooldown_days,
                            'tasks_awaiting_a_human', v_gated,
                            'unroutable', v_unroutable, 'assessed', v_assessed,
                            'lookback_minutes', p_lookback_minutes,
                            'max_batch', c_max_batch,
                            'pairs_failed', v_failed,
                            'max_open_per_dept', c_max_open_per_dept);
end; $function$


CREATE OR REPLACE FUNCTION public.fn_every_category_has_ten_suppliers(p_demo boolean DEFAULT false, p_trades text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with c as (
    select * from public.fn_supplier_target_by_trade_emirate(p_demo)
     where emirate = 'UAE' and (p_trades is null or trade = any(p_trades))
  )
  select jsonb_build_object(
    'gate', count(*) > 0 and count(*) filter (where verified < 10) = 0,
    'categories', count(*),
    'below_ten', count(*) filter (where verified < 10),
    'short', coalesce(jsonb_agg(jsonb_build_object('trade', trade, 'label', label, 'verified', verified)
                                order by verified, trade) filter (where verified < 10), '[]'::jsonb))
  from c
$function$


CREATE OR REPLACE FUNCTION public.fn_execution_sweep(p_stall_minutes integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_exec integer := 0; v_trace integer := 0; v_queue jsonb;
begin
  with seen as (
    select a.id,
           case
             when a.response->>'invoker' = 'refused'                       then 'cancelled'
             when (a.request ? 'decision_record_id') and d.id is null      then 'cancelled'
             when d.id is not null and d.status = 'executed'               then 'succeeded'
             when d.id is not null and (d.gate_verdict = 'refused'
               or d.status not in ('approved','executed'))                 then 'cancelled'
             when a.created_at < now() - make_interval(mins => greatest(coalesce(p_stall_minutes,60), 1))
                                                                            then 'stalled'
             else a.status
           end as new_status,
           d.id as dr_id, d.status as dr_status, d.gate_verdict as dr_verdict
      from public.action_execution a
      left join public.decision_record d on d.id::text = a.request ->> 'decision_record_id'
     where a.status = 'queued')
  update public.action_execution a
     set status      = s.new_status,
         attempts    = coalesce(a.attempts, 0) + 1,
         started_at  = coalesce(a.started_at, now()),
         finished_at = case when s.new_status in ('succeeded','cancelled') then now() else a.finished_at end,
         response    = coalesce(a.response, '{}'::jsonb) || jsonb_build_object(
                         'swept_at', now(), 'observed', s.new_status,
                         'decision_record_id', s.dr_id,
                         'decision_status', s.dr_status, 'gate_verdict', s.dr_verdict)
    from seen s
   where s.id = a.id and s.new_status <> 'queued';
  get diagnostics v_exec = row_count;

  update public.decision_trace t
     set outcome_status = a.status,
         outcome        = jsonb_build_object('execution_id', a.id, 'status', a.status,
                            'action_class', a.action_class, 'attempts', a.attempts,
                            'finished_at', a.finished_at),
         evaluated_at   = now()
    from public.action_execution a
   where a.correlation_id = t.correlation_id
     and t.entity_type = 'decision_record'
     and coalesce(t.outcome_status,'') is distinct from a.status;
  get diagnostics v_trace = row_count;

  select jsonb_object_agg(status, n) into v_queue
    from (select status, count(*) n from public.action_execution group by 1) z;

  return jsonb_build_object('executions_settled', v_exec, 'traces_updated', v_trace,
                            'queue', coalesce(v_queue, '{}'::jsonb), 'swept_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_executor_needs_model(p_target text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (
    select 1 from public.fn_task_class c
     where c.fn = p_target and c.active
       and c.task_class not in ('health_ping', 'json_extraction'));
$function$


CREATE OR REPLACE FUNCTION public.fn_expense_document(p_entry_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select coalesce(
    (select jsonb_build_object(
       'ok',            v.doc_path is not null,
       'entry_id',      v.id,
       'vendor',        v.vendor,
       'charged_on',    v.charged_on,
       'amount',        v.amount,
       'currency',      v.currency,
       'bucket',        v.doc_bucket,
       'path',          v.doc_path,
       'name',          v.doc_name,
       'content_type',  v.doc_content_type,
       'kind',          v.doc_kind,
       'note',          v.doc_note,
       'state',         v.document_state,
       'reason',        case
                          when v.doc_path is not null then null
                          else 'This expense has no stored document. Its source message carried no '
                               || 'vendor file that could be retrieved and no email print has been '
                               || 'rendered for it yet.'
                        end)
     from public.v_expense_documents v where v.id = p_entry_id),
    jsonb_build_object('ok', false, 'entry_id', p_entry_id, 'state', 'no_such_entry',
                       'reason', 'There is no expense_entries row with that id.'));
$function$


CREATE OR REPLACE FUNCTION public.fn_expense_document_coverage()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'entries',          count(*),
    'vendor_document',  count(*) filter (where document_state = 'vendor_document'),
    'email_print',      count(*) filter (where document_state = 'email_print'),
    'unclassified',     count(*) filter (where document_state = 'unclassified'),
    'missing',          count(*) filter (where document_state = 'missing'),
    'openable',         count(*) filter (where is_openable),
    'missing_ids',      coalesce(jsonb_agg(id order by id) filter (where document_state = 'missing'), '[]'::jsonb),
    'by_channel',       (select coalesce(jsonb_object_agg(source_channel, n), '{}'::jsonb)
                         from (select source_channel, count(*) n
                               from public.v_expense_documents group by 1) s))
  from public.v_expense_documents;
$function$


CREATE OR REPLACE FUNCTION public.fn_expense_post_to_gl(p_entry_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e record; fx numeric; acct text; amt_aed numeric(18,2); vat_aed numeric(18,2);
        net_aed numeric(18,2); jid bigint; lines jsonb;
begin
  select id, vendor, category, amount, upper(coalesce(currency,'AED')) as cur, vat_amount,
         coalesce(charged_on, created_at::date) as d, note
    into e
    from public.expense_entries where id = p_entry_id;
  if not found or coalesce(e.amount,0) <= 0 then return null; end if;
  -- a ZZ DEMO expense is a rehearsal's, never the company's (same marker as fn_gl_sync_business)
  if (coalesce(e.vendor, '') || ' ' || coalesce(e.note, '')) ~* 'zz[ _-]?demo' then return null; end if;

  -- already posted (by this routine or by fn_gl_sync_business): return it, never post twice
  select g.id into jid from public.gl_journal g
   where g.source='expense' and g.source_ref = e.id::text limit 1;
  if jid is not null then return jid; end if;

  select num_value into fx from public.gl_settings where key='usd_to_aed';
  fx := coalesce(fx, 3.6725);

  -- Same refusal as fn_gl_sync_business: a currency with no rate is NOT booked at 1:1. An
  -- understated ledger that says so beats a wrong one that does not.
  if e.cur not in ('AED','USD') then
    begin
      insert into public.founder_alerts(level, event, detail, channel)
      values ('warn','gl_unconvertible_currency',
              'Expense #'||e.id||' from '||coalesce(e.vendor,'?')||' is in '||e.cur||
              ', which has no rate in gl_settings, so it was NOT posted to the ledger.','system');
    exception when others then null; end;
    return null;
  end if;

  amt_aed := round(e.amount * case when e.cur='USD' then fx else 1 end, 2);
  vat_aed := round(coalesce(e.vat_amount,0) * case when e.cur='USD' then fx else 1 end, 2);
  if vat_aed <= 0 or vat_aed >= amt_aed then vat_aed := 0; end if;
  net_aed := amt_aed - vat_aed;

  acct := coalesce((select m.account_code from public.gl_expense_map m where m.category = e.category), '6300');

  lines := jsonb_build_array(jsonb_build_object('account', acct, 'debit', net_aed,
             'memo', coalesce(e.vendor,'')||' '||coalesce(e.category,'G&A')));
  if vat_aed > 0 then
    lines := lines || jsonb_build_array(jsonb_build_object('account','1150','debit',vat_aed,
               'memo','Input VAT stated on the receipt'));
  end if;
  lines := lines || jsonb_build_array(jsonb_build_object('account','1000','credit',amt_aed));

  return public.fn_gl_entry(e.d,
    'Expense: '||coalesce(e.vendor,'?')||' - '||coalesce(e.category,'G&A')
      ||case when e.cur='USD' then ' ('||e.amount||' USD @ '||fx||')' else '' end
      ||case when vat_aed > 0 then ' incl VAT '||vat_aed||' AED' else '' end,
    'expense', e.id::text, lines, 'expenses_inbox');
end
$function$


CREATE OR REPLACE FUNCTION public.fn_expense_sender_learn(p_sender text, p_kind text, p_vendor text, p_email_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_sender text := lower(btrim(p_sender)); r public.expense_sender_reading;
begin
  if v_sender is null or v_sender !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then
    return jsonb_build_object('learned', false, 'why', 'not an address');
  end if;
  insert into public.expense_sender_reading as e (sender, kind, kind_times, vendor, vendor_times, last_email_id)
  values (v_sender, p_kind, case when p_kind is null then 0 else 1 end, p_vendor, case when p_vendor is null then 0 else 1 end, p_email_id)
  on conflict (sender) do update set
    kind = coalesce(excluded.kind, e.kind),
    kind_times = case when excluded.kind is null then e.kind_times when excluded.kind = e.kind then e.kind_times + 1 else 1 end,
    vendor = coalesce(excluded.vendor, e.vendor),
    vendor_times = case when excluded.vendor is null then e.vendor_times when excluded.vendor = e.vendor then e.vendor_times + 1 else 1 end,
    last_email_id = coalesce(excluded.last_email_id, e.last_email_id),
    updated_at = now()
  returning * into r;
  return jsonb_build_object('learned', true, 'kind', r.kind, 'kind_times', r.kind_times, 'vendor', r.vendor, 'vendor_times', r.vendor_times);
end $function$


CREATE OR REPLACE FUNCTION public.fn_expense_sender_reading(p_sender text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select to_jsonb(r) - 'sender' from public.expense_sender_reading r where r.sender = lower(btrim(p_sender));
$function$


CREATE OR REPLACE FUNCTION public.fn_expiring_docs(p_days integer DEFAULT 60)
 RETURNS TABLE(id bigint, company_name text, sector text, doc text, expiry date, days_left integer, status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.id, l.company_name, l.sector, d.label, d.exp, (d.exp-current_date),
    case when d.exp<current_date then 'expired' when d.exp<=current_date+30 then 'expiring' else 'soon' end
  from leads l, lateral (values ('Trade license',l.license_expiry),('ISO certification',l.iso_expiry),
     ('Insurance',l.insurance_expiry),('Manufacturer authorization',l.manufacturer_auth_expiry)) d(label,exp)
  where d.exp is not null and d.exp <= current_date + p_days
    and coalesce(l.approval_status,'')='approved'
  order by d.exp asc;
$function$


CREATE OR REPLACE FUNCTION public.fn_external_refund_is_verified()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_tx uuid;
begin
  if NEW.status <> 'succeeded' or (TG_OP = 'UPDATE' and OLD.status = 'succeeded') then return NEW; end if;
  if lower(coalesce(NEW.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') then return NEW; end if;
  v_tx := coalesce(NEW.transaction_id,
                   (select t.id from public.transactions t
                     where coalesce(NEW.stripe_payment_intent, '') <> '' and t.payment_ref = NEW.stripe_payment_intent limit 1));
  if v_tx is not null then
    begin
      perform public.fn_ceo_refund_verify(v_tx);
    exception when others then
      insert into public.ceo_task (title, detail)
      values (left('A refund Stripe reported on reveal ' || left(v_tx::text, 8) || ' could not be verified', 200),
              'fn_ceo_refund_verify raised: ' || sqlerrm || '. Stripe refund ' || coalesce(NEW.stripe_refund_id, '?') || ' is recorded.');
    end;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_faq_answer(p_text text, p_min_rank numeric DEFAULT 0.15, p_embedding vector DEFAULT NULL::vector, p_min_similarity numeric DEFAULT 0.86)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_q tsquery; k_q text; k_a text; k_src text; k_rank numeric; v_tpl record; v_ar boolean; v_qc text[]; v_best numeric; v_kq int;
begin
  if p_text is null or length(btrim(p_text)) < 2 then
    return jsonb_build_object('answered', false, 'reason', 'input too short');
  end if;

  v_ar := p_text ~ '[؀-ۿ]';

  -- 1. Fixed intents. No retrieval, no model.
  select * into v_tpl from response_template
   where active and (
     (intent='greeting' and (p_text ~* '^\s*(hi|hey|hello|salam|marhaba|good (morning|afternoon|evening))\W*$'
                             or public.fn_ar_norm(p_text) ~ '^\s*(مرحبا|اهلا|السلام عليكم|صباح الخير|مساء الخير)\s*[؟!.]*\s*$')) or
     (intent='thanks'   and (p_text ~* '^\s*(thanks|thank you|thx|shukran|much appreciated)\W*$'
                             or public.fn_ar_norm(p_text) ~ '^\s*(شكرا|شكرا لك|شكرا جزيلا|مشكور)\s*[؟!.]*\s*$'))
   ) limit 1;
  if found then
    update response_template set used_count = used_count + 1 where key = v_tpl.key;
    -- 22 SEP 2026 (DL-01): the Arabic body for an Arabic greeting. coalesce, not a second branch: an
    -- intent whose Arabic copy has not been written yet answers in English rather than in nothing.
    return jsonb_build_object('answered', true, 'source', 'template', 'key', v_tpl.key,
                              'answer', case when v_ar then coalesce(v_tpl.body_ar, v_tpl.body) else v_tpl.body end,
                              'lang', case when v_ar and v_tpl.body_ar is not null then 'ar' else 'en' end,
                              'confidence', 1.0);
  end if;

  -- 2. Keyword match, in the asker's language (Arabic records for an Arabic question, English
  --    records otherwise), exactly as before. Held in k, not returned yet.
  if v_ar then
    v_q := websearch_to_tsquery('arabic', public.fn_ar_norm(p_text));
    if v_q is not null then
      select f.question, f.answer, 'faq_keyword_ar',
             ts_rank(to_tsvector('arabic', public.fn_ar_norm(coalesce(f.question,'')||' '||coalesce(f.answer,''))), v_q) as rank
        into k_q, k_a, k_src, k_rank
        from company_faq f
       where f.public and f.status='approved' and f.language = 'ar'
         and to_tsvector('arabic', public.fn_ar_norm(coalesce(f.question,'')||' '||coalesce(f.answer,''))) @@ v_q
       order by rank desc limit 1;
      if k_rank < p_min_rank then k_q := null; end if;
    end if;
  end if;
  if k_q is null then
    v_q := websearch_to_tsquery('english', p_text);
    if v_q is not null then
      select f.question, f.answer, 'faq_keyword',
             ts_rank(to_tsvector('english', coalesce(f.question,'')||' '||coalesce(f.answer,'')), v_q) as rank
        into k_q, k_a, k_src, k_rank
        from company_faq f
       where f.public and f.status='approved' and f.language = 'en'
         and to_tsvector('english', coalesce(f.question,'')||' '||coalesce(f.answer,'')) @@ v_q
       order by rank desc limit 1;
      if k_rank < p_min_rank then k_q := null; end if;
    end if;
  end if;

  -- 3. Semantic, CORROBORATED (22 Sep 2026, instruction 763). Of the five nearest records in the
  --    asker's language, one is accepted only if cosine >= p_min_similarity, its own QUESTION carries at
  --    least one of the asker's concepts, and the record carries at least half of them (two when the
  --    asker used three or more; ALL of them for an Arabic question). Measured with the live gte-small:
  --      - "can i trust the suppliers on your site" -> "Can I invite my own supplier?" at 0.8885 with one
  --        concept of three: refused (the previous rule answered it);
  --      - "كم رسومكم" -> "متى يتم الكشف عن هويتي؟" 0.8873 (only its answer mentions the fee) lost to
  --        "ما هي رسوم المنصة؟" 0.8816 once the question's own concepts rank first;
  --      - gte-small is an English model: "ما هو سعر الذهب اليوم" (today's gold price) met "هل يمكنني
  --        استرداد المبلغ؟" at 0.9091 with two of three concepts. Arabic therefore needs every concept.
  if p_embedding is not null then
    v_qc := public.fn_faq_concepts(p_text, v_ar);
    select c.question, c.answer, c.sim,
           cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(c.question || ' ' || c.answer, v_ar)))) hits,
           cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(c.question, v_ar)))) qhits,
           cardinality(v_qc) nq
      into r
      from (select f.question, coalesce(f.answer, '') answer, round((1 - (f.embedding_gte <=> p_embedding))::numeric, 4) sim
              from company_faq f
             where f.public and f.status = 'approved' and f.embedding_gte is not null
               and f.language = case when v_ar then 'ar' else 'en' end
               -- 23 Sep 2026: the five nearest are taken among records whose QUESTION shares a concept with
               -- the asker's. gte-small is an English model: for "كم رسومكم" the fee FAQ 609 (0.8816) ranked
               -- sixth behind five unrelated Arabic records, and the window of five dropped it.
               and public.fn_faq_concepts(f.question, v_ar) && v_qc
             order by f.embedding_gte <=> p_embedding limit 5) c
     where c.sim >= p_min_similarity
       -- A SUPPLIER-SIDE record answers only a question that names the supplier side (22 Sep 2026):
       -- "كم رسومكم" (what are your fees) met the Arabic supplier-fee twin #843 added at 0.883, above
       -- the customer platform-fee record, and a stranger was told what suppliers pay.
       and (c.question !~* '(for|as an?) suppliers?|suppliers? pay|do suppliers|كمورد|للموردين|الموردون|يدفع المورد'
            or p_text ~* 'supplier|vendor|مورد')
       and cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(c.question, v_ar)))) >= 1
       and cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(c.question || ' ' || c.answer, v_ar))))
           >= case when v_ar then cardinality(v_qc) when cardinality(v_qc) >= 3 then greatest(2, ceil(cardinality(v_qc) / 2.0)::int)
                   else ceil(cardinality(v_qc) / 2.0)::int end
     order by 5 desc, 3 desc limit 1;
    -- The keyword match keeps the answer when ITS question carries more of the asker's concepts:
    -- "what documents does a supplier need for verification" is that FAQ's own question, and the
    -- semantic neighbour "Supplier onboarding policy" shares one concept with it (measured on the site
    -- assistant's real questions, 22 Sep 2026).
    if r.question is not null then
      v_kq := case when k_q is null then -1
                   else cardinality(array(select unnest(v_qc) intersect select unnest(public.fn_faq_concepts(k_q, v_ar)))) end;
      if v_kq <= r.qhits then
        return jsonb_build_object('answered', true, 'source', 'faq_semantic', 'question', r.question,
                                  'answer', r.answer, 'confidence', r.sim, 'corroborated', r.hits || '/' || r.nq);
      end if;
    else
      select round(max(1 - (f.embedding_gte <=> p_embedding))::numeric, 4) into v_best from company_faq f
       where f.public and f.status = 'approved' and f.embedding_gte is not null and f.language = case when v_ar then 'ar' else 'en' end;
    end if;
  end if;

  if k_q is not null then
    return jsonb_build_object('answered', true, 'source', k_src, 'question', k_q,
                              'answer', k_a, 'confidence', round(k_rank::numeric, 4));
  end if;
  return jsonb_build_object('answered', false, 'reason', 'no confident FAQ match', 'best_similarity', v_best);
end $function$


CREATE OR REPLACE FUNCTION public.fn_faq_concepts(p_text text, p_ar boolean)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with fold(lexeme, concept) as (values
      ('fee','fee'),('charg','fee'),('cost','fee'),('price','fee'),('pay','fee'),('paid','fee'),('payment','fee'),
      ('much','fee'),('commiss','fee'),('free','fee'),('subscript','fee'),('expens','fee'),('cheap','fee'),
      ('رسوم','fee'),('رسم','fee'),('تكلف','fee'),('تكلفه','fee'),('سعر','fee'),('اسعار','fee'),('عمول','fee'),
      ('مجا','fee'),('دفع','fee'),('اشتر','fee'),
      ('supplier','supplier'),('vendor','supplier'),('contractor','supplier'),('مورد','supplier'),('موردين','supplier'))
  select coalesce(array_agg(distinct coalesce(f.concept, l)), '{}')
    from unnest(tsvector_to_array(case when p_ar then to_tsvector('arabic',
                    -- عرض سعر / عروض الأسعار is a quotation: its price word is not a fee.
                    regexp_replace(public.fn_ar_norm(coalesce(p_text, '')), '(عرض|عروض)\s+(ال)?(سعر|اسعار)', '\1', 'g'))
                                       else to_tsvector('english', coalesce(p_text, '')) end)) l
    left join fold f on f.lexeme = l
   where not (p_ar and l = any (array['كم','هل','ما','هي','هو','كيف','مع','في','من','على','عن','الي','او','لا','متي','ماذا','لماذا','اين','انا','نحن','انتم','لكم','لي']))
$function$


CREATE OR REPLACE FUNCTION public.fn_file_is_cleared(p_sha256 text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select coalesce(
    (select bool_or(verdict = 'clean') from public.file_scan where sha256 = p_sha256),
    false);
$function$


CREATE OR REPLACE FUNCTION public.fn_finance_forecast()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cp jsonb := public.fn_accountant_cash_position(current_date, null);
  v_cash numeric := (v_cp #>> '{cash_in_bank,aed}')::numeric;
  v_gl numeric; v_rev numeric; v_rvs numeric; v_exp numeric; v_out jsonb := '[]'::jsonb; h int; v_ar numeric; v_ap numeric;
begin
  select coalesce(sum(balance), 0) into v_gl from public.gl_account_balances where code in ('1000', '1050');
  select coalesce(sum(revenue_aed) filter (where not is_reversal), 0), coalesce(sum(revenue_aed) filter (where is_reversal), 0)
    into v_rev, v_rvs from public.gl_revenue_lines_measured where entry_date >= current_date - 30;
  select coalesce(sum(l.debit - l.credit), 0) into v_exp
    from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
    join public.gl_accounts a on a.code = l.account_code and a.type = 'expense'
   where j.entry_date >= current_date - 30;
  foreach h in array array[30, 60, 90] loop
    select coalesce(sum(amount_due), 0) into v_ar from public.supplier_dues
     where public.fn_supplier_due_is_owed(status, paid_at) and coalesce(due_date_30, reveal_date + 30) <= current_date + h;
    select coalesce(sum(balance_due), 0) into v_ap from public.ap_open_bills where coalesce(due_date, bill_date) <= current_date + h;
    v_out := v_out || jsonb_build_object('days', h,
      'expected_inflows', round(v_ar + v_rev * h / 30.0, 2),
      'expected_outflows', round(v_ap + v_exp * h / 30.0, 2),
      'projected_cash', case when v_cash is not null then round(v_cash + v_ar + v_rev * h / 30.0 - v_ap - v_exp * h / 30.0, 2) end,
      'revenue_forecast', round(v_rev * h / 30.0, 2));
  end loop;
  return jsonb_build_object(
    'as_of', now(),
    'cash_now', v_cash,
    'cash_source', jsonb_build_object('basis', 'fn_accountant_cash_position: the latest Mashreq statement closing balance',
                                      'as_of', v_cp #> '{cash_in_bank,as_of}', 'stale', v_cp #> '{cash_in_bank,stale}',
                                      'missing', v_cp #> '{cash_in_bank,missing}'),
    'gl_cash_aed', v_gl,
    'gl_minus_bank_aed', case when v_cash is not null then round(v_gl - v_cash, 2) end,
    'assumptions', jsonb_build_object('revenue_run_rate_30d', v_rev, 'reversals_30d_not_carried_forward', v_rvs,
                                      'expense_run_rate_30d', v_exp),
    'horizons', v_out);
end $function$


CREATE OR REPLACE FUNCTION public.fn_founder_apply_setting(p_key text, p_value text, p_inbound text, p_actor text DEFAULT 'founder'::text, p_channel text DEFAULT 'whatsapp'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_old text; v_new text; v_num numeric; v_bool boolean; v_refusal text;
begin
  select * into r from public.fn_founder_settings() s where s.setting_key = p_key;

  if not found then
    v_refusal := 'I cannot change "' || coalesce(p_key,'(nothing)') || '" from a message. '
              || 'The settings I can change this way are: '
              || (select string_agg(s.setting_key, ', ' order by s.setting_key) from public.fn_founder_settings() s)
              || '. Money, refunds and the three go-live switches are deliberately not on that list.';
    insert into public.founder_directive(actor, channel, inbound, setting_key, applied, refusal)
    values (p_actor, p_channel, left(coalesce(p_inbound,''), 2000), p_key, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal);
  end if;

  v_old := r.current_value;

  -- TYPE AND BOUNDS. A mistyped number must not become an incident before anyone reads the reply.
  if r.kind in ('int','number') then
    begin v_num := p_value::numeric; exception when others then
      v_refusal := '"' || p_value || '" is not a number, and ' || p_key || ' takes one.'; end;
    if v_refusal is null and r.kind = 'int' and v_num <> trunc(v_num) then
      v_refusal := p_key || ' takes a whole number; "' || p_value || '" is not one.';
    end if;
    if v_refusal is null and r.min_val is not null and v_num < r.min_val then
      v_refusal := p_key || ' has a floor of ' || r.min_val || ' on this channel, and you asked for ' || v_num || '.';
    end if;
    if v_refusal is null and r.max_val is not null and v_num > r.max_val then
      v_refusal := p_key || ' has a ceiling of ' || r.max_val || ' on this channel, and you asked for ' || v_num
                || '. Change it in the OS if you really mean that.';
    end if;
    v_new := case when r.kind = 'int' then trunc(v_num)::bigint::text else v_num::text end;
  elsif r.kind = 'bool' then
    v_bool := case lower(btrim(p_value))
                when 'true' then true when 'on' then true when 'yes' then true when 'enable' then true when 'enabled' then true when '1' then true
                when 'false' then false when 'off' then false when 'no' then false when 'disable' then false when 'disabled' then false when '0' then false
                else null end;
    if v_bool is null then v_refusal := '"' || p_value || '" is not on or off, and ' || p_key || ' is a switch.';
    else v_new := case when v_bool then 'true' else 'false' end; end if;
  else
    v_new := p_value;
  end if;

  if v_refusal is not null then
    insert into public.founder_directive(actor, channel, inbound, setting_key, old_value, applied, refusal)
    values (p_actor, p_channel, left(coalesce(p_inbound,''), 2000), p_key, v_old, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal, 'key', p_key, 'old', v_old);
  end if;

  if v_old is not distinct from v_new then
    insert into public.founder_directive(actor, channel, inbound, setting_key, old_value, new_value, applied, refusal)
    values (p_actor, p_channel, left(coalesce(p_inbound,''), 2000), p_key, v_old, v_new, false, 'already at that value');
    return jsonb_build_object('ok', true, 'unchanged', true, 'key', p_key, 'old', v_old, 'new', v_new,
      'message', p_key || ' is already ' || v_new || '. Nothing to change.');
  end if;

  if r.store = 'app_secrets' then
    update public.app_secrets set value = v_new, updated_at = now() where key = p_key;
  else
    update public.decision_policy set value = to_jsonb(v_new), updated_at = now() where key = p_key;
    -- decision_policy holds real jsonb types, not strings: keep numbers as numbers.
    if r.kind in ('int','number') then
      update public.decision_policy set value = to_jsonb(v_new::numeric) where key = p_key;
    elsif r.kind = 'bool' then
      update public.decision_policy set value = to_jsonb(v_new::boolean) where key = p_key;
    end if;
  end if;

  insert into public.founder_directive(actor, channel, inbound, setting_key, old_value, new_value, applied)
  values (p_actor, p_channel, left(coalesce(p_inbound,''), 2000), p_key, v_old, v_new, true);

  insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('founder_directive', 'ok',
          jsonb_build_object('key', p_key, 'old', v_old, 'new', v_new, 'channel', p_channel),
          'The founder changed ' || p_key || ' from ' || coalesce(v_old,'(unset)') || ' to ' || v_new
          || ' by ' || p_channel || '. Instruction: ' || left(coalesce(p_inbound,''), 200), now(), now());

  return jsonb_build_object('ok', true, 'key', p_key, 'old', v_old, 'new', v_new,
    'message', 'Done — ' || p_key || ' changed from ' || coalesce(v_old,'(unset)') || ' to ' || v_new || '. ' || r.description);
end $function$


CREATE OR REPLACE FUNCTION public.fn_founder_brief(p_local_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz text := 'Asia/Dubai';
  v_day date := coalesce(p_local_date, (now() at time zone 'Asia/Dubai')::date);
  v_midnight timestamptz := (v_day::timestamp) at time zone 'Asia/Dubai';
  v_from timestamptz; v_to timestamptz; v_prev timestamptz;
  v_fig jsonb; v_body text; v_subj text; v_run bigint; v_alert uuid;
begin
  insert into public.agent_runs(agent, started_at) values ('brief', now()) returning id into v_run;

  -- The window starts where the previous brief ended, so 20:00-24:00 is never lost between days.
  select (figures->>'window_to')::timestamptz into v_prev
    from public.ceo_daily_digest
   where local_date < v_day and figures ? 'window_to'
   order by local_date desc limit 1;
  v_from := case when v_prev is null or v_prev < v_midnight - interval '1 day' then v_midnight else v_prev end;
  v_to   := least(now(), v_midnight + interval '1 day');

  v_fig  := public.fn_founder_brief_figures(v_from, v_to);
  v_body := public.fn_founder_brief_text(v_fig);
  v_subj := 'QuotesDone daily brief - '||to_char(v_day,'Dy DD Mon');

  -- The Command Center row is written whether or not a recipient exists.
  insert into public.founder_alerts(level, event, detail, channel)
    values ('info', 'CEO end-of-day company digest', v_body, 'os') returning id into v_alert;

  -- Unchanged from the previous brief: fold the week's 'digest' notifications.
  update public.notifications set status = 'digested'
   where status = 'digest' and created_at >= now() - interval '7 days' and created_at <= now();

  update public.agent_runs set finished_at = now(), status = 'ok',
         counts = jsonb_build_object(
           'invitations', v_fig->'invitations'->'count', 'suppliers_registered', v_fig->'suppliers_registered'->'count',
           'inquiries', v_fig->'inquiries'->'count', 'customers', v_fig->'customers'->'count',
           'comparisons', v_fig->'comparisons'->'count', 'reveal_fees', v_fig->'reveal_fees'->'count')
   where id = v_run;

  return jsonb_build_object('subject', v_subj, 'body', v_body, 'figures', v_fig, 'command_center_id', v_alert);
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_founder_brief_figures(p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_inv jsonb; v_sup jsonb; v_inq jsonb; v_cus jsonb; v_cmp jsonb; v_rev jsonb; v_plan jsonb;
  v_on boolean; v_cap int;
begin
  -- COUNTS BEGIN
  -- 1. Invitations: an outbox row the provider accepted (provider_message_id) in the window.
  with d as (
    select l.company_name,
           (coalesce(l.is_demo,false) or l.company_name ilike 'ZZ DEMO%' or n.to_email ilike '%@example.invalid'
            or coalesce(l.email,'') ilike '%@example.invalid') as demo
      from public.notifications n left join public.leads l on l.id = n.lead_id
     where n.type = 'supplier_invite' and n.provider_message_id is not null
       and n.sent_at >= p_from and n.sent_at < p_to)
  select jsonb_build_object('count', count(*) filter (where not demo),
           'names', coalesce(jsonb_agg(coalesce(company_name,'(no company name)') order by company_name) filter (where not demo), '[]'),
           'demo_excluded', count(*) filter (where demo)) into v_inv from d;

  -- 2. Suppliers registered: the registration form was submitted in the window.
  with d as (
    select company_name,
           (coalesce(is_demo,false) or company_name ilike 'ZZ DEMO%' or coalesce(email,'') ilike '%@example.invalid') as demo
      from public.leads where registration_submitted_at >= p_from and registration_submitted_at < p_to)
  select jsonb_build_object('count', count(*) filter (where not demo),
           'names', coalesce(jsonb_agg(coalesce(company_name,'(no company name)') order by company_name) filter (where not demo), '[]'),
           'demo_excluded', count(*) filter (where demo)) into v_sup from d;

  -- 3. Inquiries received: a customer request created in the window. Split children
  --    (parent_inquiry_id) are one request, not several.
  with d as (
    select (c.id is null or coalesce(c.is_demo,false) or c.full_name ilike 'ZZ DEMO%' or coalesce(c.email,'') ilike '%@example.invalid'
            or coalesce(i.provenance->>'source','') in ('demo_factory','e2e')) as demo
      from public.inquiries i left join public.customers c on c.id = i.customer_id
     where i.parent_inquiry_id is null and i.created_at >= p_from and i.created_at < p_to)
  select jsonb_build_object('count', count(*) filter (where not demo), 'demo_excluded', count(*) filter (where demo))
    into v_inq from d;

  -- 4. Customers registered: the account was created in the window. Names and mobiles go to the PDF.
  with d as (
    select c.full_name, coalesce(nullif(c.phone,''), nullif(c.whatsapp_phone,'')) as mobile, c.created_at,
           (coalesce(c.is_demo,false) or c.full_name ilike 'ZZ DEMO%' or coalesce(c.email,'') ilike '%@example.invalid'
            or coalesce(c.phone,'') like '+9715000000%') as demo
      from public.customers c where c.created_at >= p_from and c.created_at < p_to)
  select jsonb_build_object('count', count(*) filter (where not demo),
           'list', coalesce(jsonb_agg(jsonb_build_object('name', coalesce(nullif(btrim(full_name),''),'(no name given)'),
                                                         'mobile', coalesce(mobile,'(no mobile given)'),
                                                         'at', to_char(created_at at time zone 'Asia/Dubai','FMHH12:MI am'))
                                      order by created_at) filter (where not demo), '[]'),
           'demo_excluded', count(*) filter (where demo)) into v_cus from d;

  -- 5. Comparison reports generated: a quote_comparisons row created in the window.
  with d as (
    select (c.id is null or coalesce(c.is_demo,false) or c.full_name ilike 'ZZ DEMO%' or coalesce(c.email,'') ilike '%@example.invalid') as demo
      from public.quote_comparisons q
      left join public.inquiries i on i.id = q.inquiry_id
      left join public.customers c on c.id = coalesce(q.customer_id, i.customer_id)
     where q.created_at >= p_from and q.created_at < p_to)
  select jsonb_build_object('count', count(*) filter (where not demo), 'demo_excluded', count(*) filter (where demo))
    into v_cmp from d;

  -- 6. Reveal fees paid: a transaction carrying Stripe's own payment id, revealed in the window.
  --    The payment id is written only after Stripe confirms the charge.
  with d as (
    select coalesce(t.reveal_fee, t.app_fee, 0) as fee,
           (c.id is null or coalesce(c.is_demo,false) or c.full_name ilike 'ZZ DEMO%' or coalesce(c.email,'') ilike '%@example.invalid') as demo
      from public.transactions t left join public.customers c on c.id = t.customer_id
     where t.payment_ref ~ '^(pi|ch|py)_' and t.revealed_at >= p_from and t.revealed_at < p_to)
  select jsonb_build_object('count', count(*) filter (where not demo),
           'aed', coalesce(sum(fee) filter (where not demo), 0),
           'demo_excluded', count(*) filter (where demo)) into v_rev from d;
  -- COUNTS END

  -- 7. THE PLAN FOR TOMORROW. Read from the seats' configuration and open work; 3-5 lines.
  select coalesce(max(value) filter (where key='invite_enabled'),'') = 'true'
     and coalesce(max(value) filter (where key='supplier_outreach_golive'),'') = 'true',
         coalesce(nullif(max(value) filter (where key='invite_daily_cap'),'')::int, 0)
    into v_on, v_cap from public.app_secrets where key in ('invite_enabled','supplier_outreach_golive','invite_daily_cap');

  -- 22 Sep 2026 (ceo, instructions 636/639): the campaign gate is the founder's reserved decision and he
  -- is never reminded of it. While it is closed the brief says nothing about invitations at all.
  v_plan := case when v_on then jsonb_build_array('The sales engineer sends up to '||v_cap||' supplier invitations.')
                 else '[]'::jsonb end;

  v_plan := v_plan || (
    select jsonb_build_array(case when count(*) = 0 then 'No customer request is waiting for a quote.'
                else 'Customer support follows up '||count(*)||' customer request(s) that have no quote yet.' end)
      from public.inquiries i join public.customers c on c.id = i.customer_id
     where i.parent_inquiry_id is null and i.completed_at is null
       and not (coalesce(c.is_demo,false) or c.full_name ilike 'ZZ DEMO%' or coalesce(c.email,'') ilike '%@example.invalid')
       and not exists (select 1 from public.quotes q where q.inquiry_id = i.id));

  v_plan := v_plan || (
    select jsonb_build_array(case when count(*) = 0 then 'No supplier registration is waiting for verification.'
                else 'The CEO reviews '||count(*)||' supplier registration(s) waiting for verification.' end)
      from public.leads
     where registration_submitted_at is not null and approved_at is null and rejection_reason is null
       and not (coalesce(is_demo,false) or company_name ilike 'ZZ DEMO%' or coalesce(email,'') ilike '%@example.invalid'));

  v_plan := v_plan || (
    select case when count(*) = 0 then '[]'::jsonb
                else jsonb_build_array('The CEO decides '||count(*)||' refund request(s).') end
      from public.transactions t join public.customers c on c.id = t.customer_id
     where t.refund_requested_at is not null and t.refund_resolved_at is null
       and not (coalesce(c.is_demo,false) or c.full_name ilike 'ZZ DEMO%'));

  v_plan := v_plan || (
    -- PROBLEMS, NOT ALERTS (10 Nov 2026, it_engineer). This line counted one per open alert row, and the founder read
    -- "works on 833 open technical problem(s)" (2 Nov) as 833 bugs. One fault opens many rows: duty:delivery opened
    -- 2,773 for one burst on 2-4 Nov, duty:credential_rotation_age 43 for one batch of credentials. MEASURED today:
    -- 266 open rows = 51 problems, 0 of which need him. fn_it_open_problems groups fn_it_open_findings() (still the ONE
    -- definition of open) by the first two parts of the issue key, and marks a problem as his by the IT digest's rule.
    with p as (select * from public.fn_it_open_problems()),
         s as (select count(*)::int as n, coalesce(sum(p.alerts), 0)::int as a,
                      count(*) filter (where p.needs_founder)::int as k,
                      array_agg(p.founder_title order by p.started_at, p.problem) filter (where p.needs_founder) as t
                 from p)
    select jsonb_build_array(case
      when s.n = 0 then 'The IT engineer has no open technical problems.'
      else 'The IT engineer is working on ' || s.n
           || case when s.n = 1 then ' technical problem' else ' technical problems' end
           || ', raised as ' || s.a || case when s.a = 1 then ' alert. ' else ' separate alerts. ' end
           || case when s.k = 0 then case when s.n = 1 then 'It does not need you.' else 'None of them needs you.' end
                   else case when s.n = 1 then 'It needs you: '
                             when s.k = 1 then '1 of them needs you: '
                             else s.k || ' of them need you: ' end
                        || array_to_string(s.t[1:3], '; ')
                        || case when s.k > 3 then '; and ' || (s.k - 3) || ' more' else '' end || '.'
              end
      end)
      from s);

  -- 22 Sep 2026 (ceo, instruction 638): the CEO's own plan leads item 7 -- the binding constraint, the
  -- directive each seat is working to, and the one decision only the founder can take, if any. This is
  -- the ONLY way the daily plan reaches him: no separate email. Defined in
  -- the_ceo_plans_every_day_and_directs_the_seats.sql, which must be applied before this file.
  v_plan := public.fn_ceo_plan_brief_lines() || v_plan;

  return jsonb_build_object(
    'window_from', p_from, 'window_to', p_to,
    'local_date', (p_to at time zone 'Asia/Dubai')::date,
    'invitations', v_inv, 'suppliers_registered', v_sup, 'inquiries', v_inq,
    'customers', v_cus, 'comparisons', v_cmp, 'reveal_fees', v_rev, 'plan', v_plan);
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_founder_brief_pdf_blocks(p_fig jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_array(
    jsonb_build_object('t','p','text',
      (p_fig->'customers'->>'count')||' customer(s) registered on QuotesDone on '||
      to_char(((p_fig->>'window_to')::timestamptz) at time zone 'Asia/Dubai','FMDay FMDD FMMonth YYYY')||
      ' (Dubai time). Test accounts are not included.'),
    jsonb_build_object('t','table','head', jsonb_build_array('#','Name','Mobile number','Registered at'),
      'widths', jsonb_build_array(0.08, 0.44, 0.28, 0.20),
      'rows', coalesce((select jsonb_agg(jsonb_build_array(o::text, e->>'name', e->>'mobile', e->>'at') order by o)
                          from jsonb_array_elements(p_fig->'customers'->'list') with ordinality as t(e, o)), '[]'::jsonb)),
    jsonb_build_object('t','note','text','Confidential: personal data of QuotesDone customers, for the founder only.'));
$function$


CREATE OR REPLACE FUNCTION public.fn_founder_brief_text(p_fig jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  n_inv int := coalesce((p_fig->'invitations'->>'count')::int, 0);
  n_sup int := coalesce((p_fig->'suppliers_registered'->>'count')::int, 0);
  n_inq int := coalesce((p_fig->'inquiries'->>'count')::int, 0);
  n_cus int := coalesce((p_fig->'customers'->>'count')::int, 0);
  n_cmp int := coalesce((p_fig->'comparisons'->>'count')::int, 0);
  n_rev int := coalesce((p_fig->'reveal_fees'->>'count')::int, 0);
  v_aed numeric := coalesce((p_fig->'reveal_fees'->>'aed')::numeric, 0);
  v_from timestamptz := (p_fig->>'window_from')::timestamptz;
  v_to   timestamptz := (p_fig->>'window_to')::timestamptz;
  v_demo int;
  v_names text; v_plan text;
  v_period text;
begin
  v_period := case when (v_from at time zone 'Asia/Dubai')::time = time '00:00'
                    and (v_from at time zone 'Asia/Dubai')::date = (v_to at time zone 'Asia/Dubai')::date
                   then 'from midnight to '||to_char(v_to at time zone 'Asia/Dubai','FMHH12:MI am')
                   else 'from '||to_char(v_from at time zone 'Asia/Dubai','FMHH12:MI am Dy FMDD Mon')||
                        ' to '||to_char(v_to at time zone 'Asia/Dubai','FMHH12:MI am')
              end;
  v_demo := coalesce((p_fig->'invitations'->>'demo_excluded')::int,0) + coalesce((p_fig->'suppliers_registered'->>'demo_excluded')::int,0)
          + coalesce((p_fig->'inquiries'->>'demo_excluded')::int,0) + coalesce((p_fig->'customers'->>'demo_excluded')::int,0)
          + coalesce((p_fig->'comparisons'->>'demo_excluded')::int,0) + coalesce((p_fig->'reveal_fees'->>'demo_excluded')::int,0);
  select string_agg('   - '||x, E'\n') into v_plan from jsonb_array_elements_text(coalesce(p_fig->'plan','[]')) x;

  return
    'Your QuotesDone brief for '||to_char(v_to at time zone 'Asia/Dubai','FMDay FMDD FMMonth')||
    ' ('||v_period||', Dubai time).'||E'\n\n'||
    '1. Supplier invitations sent: '||
      case when n_inv = 0 then 'none today.'
           else n_inv||' today, to: '||
                (select string_agg(x, ', ') from jsonb_array_elements_text(p_fig->'invitations'->'names') x)||'.' end||E'\n'||
    '2. Suppliers registered: '||
      case when n_sup = 0 then 'none today.'
           else n_sup||' today: '||
                (select string_agg(x, ', ') from jsonb_array_elements_text(p_fig->'suppliers_registered'->'names') x)||'.' end||E'\n'||
    '3. Customer inquiries received: '||case when n_inq = 0 then 'none today.' else n_inq||' today.' end||E'\n'||
    '4. Customers registered: '||
      case when n_cus = 0 then 'none today.'
           else n_cus||' today. Their names and mobile numbers are in the attached PDF.' end||E'\n'||
    '5. Comparison reports generated: '||case when n_cmp = 0 then 'none today.' else n_cmp||' today.' end||E'\n'||
    '6. Customers who paid a reveal fee: '||
      case when n_rev = 0 then 'none today.'
           else n_rev||' today, AED '||to_char(v_aed,'FM999,999,990.00')||' in total (confirmed by Stripe).' end||E'\n'||
    '7. The plan for tomorrow:'||E'\n'||coalesce(v_plan, '   - Nothing is scheduled.')||E'\n\n'||
    case when v_demo > 0 then 'Test data is left out of every number above ('||v_demo||' test record(s) today).'
         else 'Test data is left out of every number above.' end||E'\n'||
    'Nothing here needs a reply.';
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_founder_hold_change_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$ select coalesce(current_setting('app.change_reason', true), '') ~ '^(founder:[0-9]+|probe:[a-z0-9_]+)' $function$


CREATE OR REPLACE FUNCTION public.fn_founder_hold_is_lifted_only_by_its_flag()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'founder_hold %: a hold is lifted only by its flag (%), never by deleting it', old.hold_key, old.flag_key;
  end if;
  if new.flag_key is distinct from old.flag_key or new.flag_released_value is distinct from old.flag_released_value then
    raise exception 'founder_hold %: its flag (% = %) cannot be changed; the hold lifts only when that flag flips', old.hold_key, old.flag_key, old.flag_released_value;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_founder_hold_line()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select string_agg(x.what_is_held || ' ' || x.until_when || ', so ' || x.words
                    || ' are paused. They are not counted as misses and nobody is chased for them.', E'\n')
    from (select h.hold_key, h.what_is_held, h.until_when,
                 regexp_replace(string_agg(distinct public.fn_target_words(h.target_key), ', '), ', ([^,]*)$', ' and \1') words
            from public.fn_held_targets() h group by h.hold_key, h.what_is_held, h.until_when) x
$function$


CREATE OR REPLACE FUNCTION public.fn_founder_instruction_needs_evidence()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.status = 'done' and coalesce(btrim(new.evidence), '') = '' then
    raise exception 'instruction % cannot be marked done with no evidence. Name the file, routine or measurement that proves it.', new.id;
  end if;
  if new.status <> 'open' and new.closed_at is null then new.closed_at := now(); end if;
  new.updated_at := now();
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_founder_mail_policy_at(p_kind text, p_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
           when not exists (select 1 from public.founder_mail_policy_history h where h.kind = p_kind) then false
           else (select h.allowed_to_email from public.founder_mail_policy_history h
                  where h.kind = p_kind and h.valid_from <= p_at
                  order by h.valid_from desc, h.id desc limit 1)
         end
$function$


CREATE OR REPLACE FUNCTION public.fn_founder_mail_policy_history_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- valid_from is clock_timestamp(), not now(): several changes inside one transaction keep their order.
  -- ponytail: a flip is visible to other sessions at COMMIT, a few ms after valid_from; a founder email
  -- queued in that gap is judged by the new value. Upgrade path: track_commit_timestamp.
  if TG_OP = 'DELETE' then
    insert into public.founder_mail_policy_history (kind, allowed_to_email, valid_from, source, reason)
    values (OLD.kind, false, clock_timestamp(), 'delete (an unregistered kind is never emailed)', OLD.reason);
    return OLD;
  end if;
  if TG_OP = 'INSERT' or OLD.allowed_to_email is distinct from NEW.allowed_to_email
     or OLD.kind is distinct from NEW.kind then
    insert into public.founder_mail_policy_history (kind, allowed_to_email, valid_from, source, reason)
    values (NEW.kind, NEW.allowed_to_email, clock_timestamp(), lower(TG_OP), NEW.reason);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_founder_mail_route(p_kind text, p_subject text, p_body text, p_level text DEFAULT 'high'::text, p_owner_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pol record; v_owner_role text; v_reason text; v_agent text;
  v_sig text; v_task bigint; v_new boolean := false; v_prio int; v_title text;
begin
  select * into v_pol from public.founder_mail_policy where kind = p_kind;
  v_owner_role := coalesce(v_pol.owner_role, 'cto');
  v_reason := coalesce(v_pol.reason,
    'kind ''' || coalesce(p_kind, '(null)') || ''' is not registered in founder_mail_policy, and an unregistered kind is never emailed');

  -- WHO OWNS IT. 7 Sep 2026: the org is exactly two agents and NO departments, so a task is owned by
  -- an AGENT and never by a department. The named agent wins; else the policy role's runtime agent;
  -- else the seat whose work this is — customer_support for anything customer-, comms- or
  -- marketplace-facing, the ceo for the rest. If neither seat is active the owner is left null and
  -- a05_org_task_fill_ownership picks, exactly as before.
  if p_owner_agent is not null and exists (
       select 1 from public.org_agents o
        where o.agent_key = p_owner_agent and o.active and coalesce(o.available, true)) then
    v_agent := p_owner_agent;
  else
    select r.runtime_agent_key into v_agent
      from public.org_role r
      join public.org_agents o on o.agent_key = r.runtime_agent_key and o.active and coalesce(o.available, true)
     where r.role_id = v_owner_role and r.status = 'active';
  end if;
  if v_agent is null then
    v_agent := case when v_owner_role ~* 'support|success|customer|communicat|deliver|marketplace|sales'
                    then 'customer_support' else 'ceo' end;
  end if;
  if not exists (select 1 from public.org_agents o
                  where o.agent_key = v_agent and o.active and coalesce(o.available, true)) then
    v_agent := null;
  end if;

  -- THE CONDITION: kind + subject with a leading [TAG] removed and every number replaced by '#', so
  -- "[HIGH] Backup may have failed" from the trigger and "Backup may have failed" from the sweep, or run #80
  -- and run #82 of one stalled handoff, are one condition.
  v_title := regexp_replace(coalesce(nullif(p_subject, ''), p_kind, 'engine signal'), '^\[[^\]]*\]\s*', '');
  v_sig := coalesce(p_kind, 'unregistered') || ':' || left(regexp_replace(v_title, '[0-9]+', '#', 'g'), 150);
  insert into public.alert_signature (watcher, signature) values ('founder_mail', v_sig)
    on conflict (watcher, signature) do update
      set last_seen_at = now(), seen_count = alert_signature.seen_count + 1, resolved_at = null;

  -- ONE OPEN TASK PER CONDITION. An open task is bumped; a closed one lets the condition open a new one,
  -- because the condition coming back after the owner closed it IS new information.
  select t.id into v_task
    from public.org_tasks t
   where t.status in ('proposed', 'assigned', 'in_progress', 'blocked', 'escalated')
     and t.result -> 'founder_mail' ->> 'signature' = v_sig
   order by t.id desc limit 1;

  if v_task is not null then
    update public.org_tasks
       set result = jsonb_set(coalesce(result, '{}'::jsonb), '{founder_mail}',
                     coalesce(result -> 'founder_mail', '{}'::jsonb)
                     || jsonb_build_object('last_seen_at', now(),
                                           'seen_count', coalesce((result -> 'founder_mail' ->> 'seen_count')::int, 1) + 1,
                                           'latest', left(coalesce(p_body, ''), 600))),
           updated_at = now()
     where id = v_task;
  else
    v_prio := case when lower(coalesce(p_level, '')) in ('critical', 'urgent', 'danger', 'high', 'error', 'action', 'alert', 'escalation', 'fail', 'failed')
                   then 2 else 1 end;
    insert into public.org_tasks (title, detail, status, tier, needs_founder, decided_by,
                                  action_class, assigned_agent, priority, result)
    values (left(v_title, 200),
            '[founder_mail:' || coalesce(p_kind, 'unregistered') || '] ' || coalesce(p_body, '')
              || E'\n\nThis signal was routed to you instead of the founder''s inbox: ' || v_reason
              || '. Resolve the condition and close this task; it re-opens only if the condition returns.',
            'assigned', 'advisory', false, 'fn_founder_mail_route',
            'routine_operational_decision', v_agent, v_prio,
            jsonb_build_object('founder_mail', jsonb_build_object(
              'kind', p_kind, 'signature', v_sig, 'owner_role', v_owner_role, 'level', p_level,
              'registered', v_pol.kind is not null, 'routed_at', now(), 'seen_count', 1)))
    returning id into v_task;
    v_new := true;
  end if;

  -- the ledger resolves on merit: a signature whose task the owner closed is no longer open
  update public.alert_signature s
     set resolved_at = now()
   where s.watcher = 'founder_mail' and s.resolved_at is null and s.signature <> v_sig
     and not exists (select 1 from public.org_tasks t
                      where t.result -> 'founder_mail' ->> 'signature' = s.signature
                        and t.status in ('proposed', 'assigned', 'in_progress', 'blocked', 'escalated'));

  return jsonb_build_object('mode', 'routed', 'task_id', v_task, 'new', v_new, 'signature', v_sig,
                            'kind', p_kind, 'registered', v_pol.kind is not null,
                            'owner', v_agent, 'owner_role', v_owner_role);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_founder_open_instructions()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'open', count(*) filter (where status = 'open'),
    'done', count(*) filter (where status = 'done'),
    'deferred_by_him', count(*) filter (where status = 'deferred_by_founder'),
    'items', coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'said_at', said_at, 'subject', subject,
        'instruction', instruction, 'note', note)
      order by said_at) filter (where status = 'open'), '[]'::jsonb))
  from public.founder_instruction;
$function$


CREATE OR REPLACE FUNCTION public.fn_founder_settings()
 RETURNS TABLE(setting_key text, store text, kind text, min_val numeric, max_val numeric, current_value text, description text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with reg(setting_key, store, kind, min_val, max_val, description) as (values
    ('invite_daily_cap',                 'app_secrets',     'int',    1,   200, 'How many supplier invitations may be sent in one day. fn_invite_ramp raises it on its own while the list behaves; setting it here overrides today.'),
    ('invite_max_bounce_rate',           'app_secrets',     'number', 0.01, 0.20,'The hard-bounce rate at which invites auto-pause.'),
    ('invite_enabled',                   'app_secrets',     'bool',   null, null,'Whether supplier invitations send at all.'),
    ('invite_target_per_category',       'app_secrets',     'int',    1,   100, 'How many confirmed suppliers a trade category is aiming for before it stops being prioritised.'),
    ('supplier_emails_enabled',          'app_secrets',     'bool',   null, null,'Whether any email may be sent to suppliers.'),
    ('email_enabled',                    'app_secrets',     'bool',   null, null,'The master switch for outbound email.'),
    ('wa_daily_cap',                     'app_secrets',     'int',    1,   500, 'How many WhatsApp messages the company may send in a day.'),
    ('wa_per_recipient_24h',             'app_secrets',     'int',    1,    10, 'How many WhatsApp messages one recipient may get in 24 hours.'),
    ('wa_autoreply_enabled',             'app_secrets',     'bool',   null, null,'Whether inbound WhatsApp gets an automatic reply.'),
    ('workflow_reflection_steps_per_day','decision_policy', 'int',    1,   200, 'How many non-demand workflow steps - health reports, forecasts, recommendations - may run in a day.'),
    ('cos_reflection_tasks_per_day',     'decision_policy', 'int',    1,   100, 'How many non-revenue tasks the chief of staff may hand to a large model in a day.'),
    ('match_max_fanout',                 'decision_policy', 'int',    1,    20, 'How many suppliers one RFQ may be sent to.'),
    ('match_max_fanout_per_trade',       'decision_policy', 'int',    1,    10, 'How many suppliers within a single trade one RFQ may reach.'),
    ('match_relevance_floor',            'decision_policy', 'int',    0,   100, 'The relevance score below which a supplier is not matched to an RFQ at all.'),
    ('confidence_min',                   'decision_policy', 'number', 0,     1, 'The confidence below which an agent escalates instead of acting.'),
    ('matching_strike_limit',            'decision_policy', 'int',    1,    10, 'How many times a supplier may ignore an RFQ before the matcher stops offering them work.')
  )
  select r.setting_key, r.store, r.kind, r.min_val, r.max_val,
         case r.store
           when 'app_secrets'     then (select s.value from public.app_secrets s where s.key = r.setting_key)
           when 'decision_policy' then (select d.value #>> '{}' from public.decision_policy d where d.key = r.setting_key)
         end,
         r.description
  from reg r;
$function$


CREATE OR REPLACE FUNCTION public.fn_founder_whatsapp_figures(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_now   timestamptz := now();
  v_day   timestamptz := date_trunc('day', v_now at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
  v_month timestamptz := date_trunc('month', v_now at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
  v_ever  timestamptz := timestamptz '2000-01-01 00:00+00';
  v_ctx jsonb; v_mkt jsonb; v_at text; v_sent boolean;
begin
  if (public.fn_identify_contact(p_phone)->>'audience') is distinct from 'founder' then
    return jsonb_build_object('ok', false, 'reason', 'not_the_founder');
  end if;

  v_ctx := public.fn_wa_context('founder', p_phone);
  v_mkt := public.fn_marketing_report_figures(v_now - interval '7 days', v_now)->'measured';
  select coalesce(nullif(btrim(value), ''), '20:00') into v_at from public.app_secrets where key = 'ceo_digest_local_time';
  v_sent := exists (select 1 from public.ceo_daily_digest
                     where report_key = 'quotesdone:' || to_char((v_now at time zone 'Asia/Dubai')::date, 'YYYY-MM-DD')
                       and submitted_at is not null);

  return jsonb_build_object(
    'ok', true,
    'read_at', v_now,
    'read_at_local', to_char(v_now at time zone 'Asia/Dubai', 'HH24:MI "on" Dy DD Mon'),
    'suppliers', jsonb_build_object(
      'registered',      public.fn_ceo_plan_measure('registrations_submitted', v_ever, v_now),
      'registered_7d',   public.fn_ceo_plan_measure('registrations_submitted', v_now - interval '7 days', v_now),
      'verified',        public.fn_ceo_plan_measure('registrations_verified', v_ever, v_now)),
    'requests', jsonb_build_object(
      'today',           public.fn_ceo_plan_measure('inquiries_posted', v_day, v_now),
      'last_7d',         public.fn_ceo_plan_measure('inquiries_posted', v_now - interval '7 days', v_now)),
    'quotes', jsonb_build_object(
      'total',           (v_ctx->'demand'->>'quotes_total')::numeric,
      'last_7d',         (v_ctx->'demand'->>'quotes_7d')::numeric),
    'reveals_month', jsonb_build_object(
      'paid',            public.fn_ceo_plan_measure('reveals_paid', v_month, v_now),
      'fee_aed',         public.fn_ceo_plan_measure('fee_aed', v_month, v_now)),
    'support', jsonb_build_object(
      'open_cases',      (select count(*) from public.support_case where closed_at is null),
      'waiting_for_person', (select count(*) from public.agent_actions
                              where kind = 'handoff' and status = 'pending'
                                and detail ->> 'type' = 'support.human_requested')),
    'it', jsonb_build_object(
      'open_findings',   (select count(*) from public.it_engineer_finding where closed_at is null)),
    'marketing_7d', jsonb_build_object(
      'posts_published', (v_mkt->>'posts_published')::numeric,
      'posts_scheduled', (v_mkt->>'posts_scheduled_next_7_days')::numeric,
      'ad_spend_aed',    (v_mkt->>'ad_spend_reported_aed')::numeric),
    'brief', jsonb_build_object('local_time', v_at, 'sent_today', v_sent));
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_fraud_resolve(p_subject_type text, p_subject_id text, p_action text, p_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_ok boolean := true; v_msg text := '';
begin
  if p_action = 'ban' then
    begin
      if p_subject_type in ('customer','customers') then
        update customers set banned=true, banned_reason=coalesce(banned_reason,'fraud: manual ban by '||coalesce(p_by,'admin')) where id = p_subject_id::uuid;
      elsif p_subject_type in ('supplier','lead','leads') then
        update leads set banned=true, matching_blocked=true, matching_block_reason=coalesce(matching_block_reason,'fraud ban'), banned_reason=coalesce(banned_reason,'fraud: manual ban by '||coalesce(p_by,'admin')) where id = p_subject_id::bigint;
      else v_ok:=false; v_msg:='unknown subject_type';
      end if;
    exception when others then v_ok:=false; v_msg:=SQLERRM;
    end;
    update fraud_flags set status='resolved', updated_at=now() where subject_type=p_subject_type and subject_id=p_subject_id;
  elsif p_action = 'unban' then
    begin
      if p_subject_type in ('customer','customers') then update customers set banned=false, banned_reason=null where id=p_subject_id::uuid;
      elsif p_subject_type in ('supplier','lead','leads') then update leads set banned=false, matching_blocked=false where id=p_subject_id::bigint;
      end if;
    exception when others then v_ok:=false; v_msg:=SQLERRM; end;
    update fraud_flags set status='resolved', updated_at=now() where subject_type=p_subject_type and subject_id=p_subject_id;
  elsif p_action = 'dismiss' then
    update fraud_flags set status='dismissed', updated_at=now() where subject_type=p_subject_type and subject_id=p_subject_id;
  else v_ok:=false; v_msg:='unknown action';
  end if;
  return jsonb_build_object('ok', v_ok, 'action', p_action, 'subject', p_subject_type||':'||p_subject_id, 'error', nullif(v_msg,''), 'by', p_by, 'at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_gate_state_satisfies(s gate_state)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select s in ('passed','not_applicable');
$function$


CREATE OR REPLACE FUNCTION public.fn_gateway_client_key()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- the new key first; the legacy anon JWT only while the publishable_key row is absent (TEMPORARY, 27 Oct 2026)
  select coalesce(
    (select nullif(btrim(value), '') from public.app_secrets where key = 'publishable_key'),
    (select nullif(btrim(value), '') from public.app_secrets where key = 'anon_key'));
$function$


CREATE OR REPLACE FUNCTION public.fn_gl_entry(p_date date, p_memo text, p_source text, p_ref text, p_lines jsonb, p_created_by text DEFAULT 'system'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare jid bigint; ln jsonb; i int := 0;
begin
  insert into public.gl_journal(entry_date, memo, source, source_ref, created_by)
    values (coalesce(p_date, (now() at time zone 'utc')::date), p_memo, coalesce(p_source,'manual'), p_ref, p_created_by)
    returning id into jid;
  for ln in select * from jsonb_array_elements(p_lines) loop
    i := i + 1;
    insert into public.gl_journal_lines(journal_id, line_no, account_code, debit, credit, memo)
      values (jid, i, (ln->>'account'),
              round(coalesce((ln->>'debit')::numeric,0),2),
              round(coalesce((ln->>'credit')::numeric,0),2),
              ln->>'memo');
  end loop;
  perform public.fn_gl_post(jid);
  return jid;
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_fixture_or_orphan(p_transaction uuid, p_supplier bigint, p_customer uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_found boolean; v_sup bigint := p_supplier; v_cust uuid := p_customer; v_demo boolean;
begin
  if p_transaction is not null then
    select true, coalesce(v_sup, t.supplier_id), coalesce(v_cust, t.customer_id)
      into v_found, v_sup, v_cust
      from public.transactions t where t.id = p_transaction;
    if v_found is null then return 'orphan: transaction ' || p_transaction || ' no longer exists'; end if;
  end if;
  if v_sup is not null then
    select coalesce(l.is_demo, false) into v_demo from public.leads l where l.id = v_sup;
    if not found then return 'orphan: supplier ' || v_sup || ' no longer exists'; end if;
    if v_demo then return 'fixture: supplier ' || v_sup || ' is a demo identity'; end if;
  end if;
  if v_cust is not null then
    select coalesce(c.is_demo, false) into v_demo from public.customers c where c.id = v_cust;
    if not found then return 'orphan: customer ' || v_cust || ' no longer exists'; end if;
    if v_demo then return 'fixture: customer ' || v_cust || ' is a demo identity'; end if;
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_journal_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  if old.status = 'posted' then
    if tg_op = 'UPDATE' and (
         (new.status = 'posted' and (to_jsonb(new) - 'memo') = (to_jsonb(old) - 'memo')
          and (new.memo is not distinct from old.memo or new.memo = public.fn_mask_bank_text(old.memo)))
      or (new.status = 'void' and new.reverses is not null
          and (to_jsonb(new) - 'status' - 'reverses') = (to_jsonb(old) - 'status' - 'reverses'))) then
      return new;
    end if;
    raise exception 'Posted journal % is immutable (reverse it instead)', old.id;
  end if;
  -- A void journal is terminal: fn_gl_reverse already set it void with its reversal link. Measured
  -- 15 Sep 2026: no routine or code path updates or deletes a void journal (the only writers are
  -- fn_gl_reverse's posted-to-void statement and fn_gl_post, which is only ever called on drafts).
  if old.status = 'void' then
    raise exception 'Void journal % is terminal: it was reversed and can never change again', old.id;
  end if;
  return case when tg_op='DELETE' then old else new end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_journal_memo_masked()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.memo := public.fn_mask_bank_text(new.memo);
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_lines_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare st text;
begin
  select status into st from public.gl_journal where id = coalesce(new.journal_id, old.journal_id);
  if st = 'posted' then
    raise exception 'Cannot modify lines of a posted journal (reverse it instead)';
  end if;
  return case when tg_op='DELETE' then old else new end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_open_period_date(p_date date)
 RETURNS date
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m date := date_trunc('month', p_date)::date; v_today date := (now() at time zone 'Asia/Dubai')::date; v_open date;
begin
  if p_date is null or not exists (select 1 from public.accountant_month_close where month = v_m) then
    return p_date;
  end if;
  select min(g)::date into v_open
    from generate_series(v_m + interval '1 month', date_trunc('month', greatest(v_today, p_date)), interval '1 month') g
   where not exists (select 1 from public.accountant_month_close c where c.month = g::date);
  if v_open is null then
    -- fn_accountant_month_close refuses a month that has not ended, so the current month is always open
    raise exception 'no open period after %: every month up to today is closed', to_char(v_m, 'YYYY-MM');
  end if;
  return least(v_today, (v_open + interval '1 month' - interval '1 day')::date);
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_period_lock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.status = 'posted'
     and (tg_op = 'INSERT' or old.status is distinct from 'posted' or old.entry_date is distinct from new.entry_date)
     and exists (select 1 from public.accountant_month_close where month = date_trunc('month', new.entry_date)::date)
     and coalesce(current_setting('app.period_reopen_reason', true), '') = '' then
    raise exception 'period % is closed: post this entry in the open period, or set app.period_reopen_reason in the same transaction',
      to_char(new.entry_date, 'YYYY-MM');
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_post(p_journal bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d numeric(18,2); c numeric(18,2); n int; j public.gl_journal; v_open date; v_line bigint;
begin
  select * into j from public.gl_journal where id = p_journal for update;
  if j.id is null then raise exception 'journal % not found', p_journal; end if;
  if j.status is distinct from 'draft' then
    raise exception 'journal % is %; only a draft can be posted (a posted journal is corrected with fn_gl_reverse, and a void one is terminal)', p_journal, j.status;
  end if;
  select coalesce(sum(debit),0), coalesce(sum(credit),0), count(*) into d,c,n from public.gl_journal_lines where journal_id=p_journal;
  if n < 2 then raise exception 'journal % needs at least 2 lines', p_journal; end if;
  if d <> c then raise exception 'journal % out of balance: debits % <> credits %', p_journal, to_char(d,'FM999999990.00'), to_char(c,'FM999999990.00'); end if;
  if d = 0 then raise exception 'journal % has zero amount', p_journal; end if;

  -- A deliberate reopen (app.period_reopen_reason, the lock's own audit trail) keeps the original date.
  v_open := case when coalesce(current_setting('app.period_reopen_reason', true), '') = ''
                 then public.fn_gl_open_period_date(j.entry_date) else j.entry_date end;
  if v_open is distinct from j.entry_date then
    if j.source in ('bank_charge', 'bank_interest', 'owner_capital') and j.source_ref ~ '^[0-9]+$' then
      select b.id into v_line from public.bank_statement_line b where b.id = j.source_ref::bigint;
    end if;
    update public.gl_journal
       set entry_date = v_open,
           memo = 'Prior-period adjustment: originally dated ' || j.entry_date || ' in the closed period '
                  || to_char(j.entry_date, 'YYYY-MM') || coalesce(', statement line ' || v_line, '') || '. ' || coalesce(j.memo, '')
     where id = p_journal;
  end if;

  update public.gl_journal
     set status='posted', posted_at=now(),
         entry_no = coalesce(entry_no, 'JE-'||lpad(p_journal::text,6,'0'))
   where id=p_journal;

  if v_open is distinct from j.entry_date then
    insert into public.gl_prior_period_adjustment (journal_id, original_date, closed_month, posted_on, source, source_ref, statement_line_id, amount_aed)
    values (p_journal, j.entry_date, date_trunc('month', j.entry_date)::date, v_open, j.source, j.source_ref, v_line, d);
  end if;
  return p_journal;
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_reverse(p_journal_id bigint, p_reason text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_orig  public.gl_journal%rowtype;
  v_lines jsonb;
  v_new   bigint;
  v_dr    numeric;
  v_cr    numeric;
begin
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'a reversal needs a reason: reversing a posted entry is a decision and the ledger must carry why';
  end if;

  select * into v_orig from public.gl_journal where id = p_journal_id;
  if not found then
    raise exception 'no journal %', p_journal_id;
  end if;
  if v_orig.status <> 'posted' then
    raise exception 'journal % has status %, not posted; only a posted entry can be reversed', p_journal_id, v_orig.status;
  end if;
  if exists (select 1 from public.gl_journal where reverses = p_journal_id) then
    raise exception 'journal % has already been reversed; reversing it twice would double the correction', p_journal_id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
             'account', l.account_code,
             'debit',   l.credit,
             'credit',  l.debit,
             'memo',    'Reversal of journal ' || p_journal_id || coalesce(': ' || l.memo, '')
           ) order by l.line_no), '[]'::jsonb)
    into v_lines
    from public.gl_journal_lines l
   where l.journal_id = p_journal_id;

  if jsonb_array_length(v_lines) = 0 then
    raise exception 'journal % has no lines, so there is nothing to reverse', p_journal_id;
  end if;

  v_new := public.fn_gl_entry(
    (now() at time zone 'Asia/Dubai')::date,
    'REVERSAL of journal ' || p_journal_id || ' (' || coalesce(v_orig.memo, '') || ') — ' || p_reason,
    'reversal', p_journal_id::text, v_lines, 'fn_gl_reverse');

  -- BOTH SIDES GO VOID, each pointing at the other, through the one exit the immutability trigger
  -- allows. Reports count posted journals only; voiding just the original left the reversal
  -- counted on its own and overstated the ledger.
  update public.gl_journal set status = 'void', reverses = v_new        where id = p_journal_id;
  update public.gl_journal set status = 'void', reverses = p_journal_id where id = v_new;

  if exists (select 1 from public.gl_journal where id in (p_journal_id, v_new) and status <> 'void') then
    raise exception 'journal % or its reversal % is still posted; the pair would not net to zero in the reports', p_journal_id, v_new;
  end if;

  select sum(l.debit), sum(l.credit) into v_dr, v_cr
    from public.gl_journal_lines l
   where l.journal_id in (p_journal_id, v_new);
  if round(coalesce(v_dr, 0), 2) <> round(coalesce(v_cr, 0), 2) then
    raise exception 'the reversal did not net to zero: DR % CR % across journals % and %',
      v_dr, v_cr, p_journal_id, v_new;
  end if;

  return v_new;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_gl_sync_business()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0; acct text;
        fee_pct numeric; fee_fixed numeric; fee numeric(18,2); gross numeric(18,2); net numeric(18,2);
        fx numeric; amt_aed numeric(18,2); diff numeric(18,2); extra numeric(18,2); lines jsonb; v_orphans jsonb;
begin
  select num_value into fee_pct   from public.gl_settings where key='stripe_fee_pct';
  select num_value into fee_fixed from public.gl_settings where key='stripe_fee_fixed';
  select num_value into fx        from public.gl_settings where key='usd_to_aed';
  fee_pct   := coalesce(fee_pct,0);
  fee_fixed := coalesce(fee_fixed,0);
  fx        := coalesce(fx, 3.6725);

  -- TEST MONEY NEVER REACHES THE BOOKS (15 Sep 2026). Every business branch below books only a row that
  -- fn_gl_fixture_or_orphan passes. Journal #690 was an E2E fixture due whose supplier and transaction the
  -- teardown had deleted; it posted the first tick after the bank-booking hold was lifted.

  -- 1) Reveal-fee revenue with Stripe fee split (refunded transactions excluded)
  for r in
    select id, reveal_fee, total_charged, processing_fee, stripe_fee_fils, coalesce(revealed_at::date, current_date) as d
    from public.transactions
    where fee_status='paid' and coalesce(reveal_fee,0) > 0
      and coalesce(refund_status,'') not in ('refunded','refund_approved','succeeded')
      and not exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=transactions.id::text)
      and public.fn_gl_fixture_or_orphan(transactions.id, null, null) is null
  loop
    gross := round(coalesce(r.total_charged, r.reveal_fee),2);
    fee   := coalesce(round(r.stripe_fee_fils / 100.0, 2), nullif(r.processing_fee, 0), round(gross*fee_pct/100 + fee_fixed, 2));
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;
    perform public.fn_gl_entry(r.d, 'Reveal fee (net of Stripe fee)', 'reveal_fee', r.id::text,
      case when fee > 0 then
        jsonb_build_array(
          jsonb_build_object('account','1050','debit',net),
          jsonb_build_object('account','6100','debit',fee),
          jsonb_build_object('account','4000','credit',gross))
      else
        jsonb_build_array(
          jsonb_build_object('account','1050','debit',gross),
          jsonb_build_object('account','4000','credit',gross))
      end, 'gl_sync');
    n := n + 1;
  end loop;

  -- 1b) REFUND PAID OUT: everything the customer paid (total_charged) goes back. Stripe keeps its
  --     processing fee and QuotesDone absorbs it (founder, 14 Sep 2026). 'succeeded' is the status the
  --     refunds-table path writes, and it was missing here, so a Stripe-settled refund never posted.
  --     If the sale was booked, the refund reverses it through 6900 and the fee booked at sale stays in
  --     6100 as the absorbed cost. If it was not, the only real movement is the fee: 6100 / 1050.
  for r in
    select t.id, coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0) as amt,
           coalesce(round(t.stripe_fee_fils / 100.0, 2), nullif(t.processing_fee, 0), round(coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0)*fee_pct/100 + fee_fixed, 2)) as fee_absorbed,
           exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=t.id::text) as sale_booked,
           coalesce(t.refund_resolved_at::date, t.revealed_at::date, current_date) as d
    from public.transactions t
    where coalesce(t.refund_status,'') in ('refunded','refund_approved','succeeded')
      and coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='refund_paid' and g.source_ref=t.id::text)
      and public.fn_gl_fixture_or_orphan(t.id, null, null) is null
  loop
    gross := round(r.amt,2);
    if r.sale_booked then
      perform public.fn_gl_entry(r.d, 'Reveal charge refunded in full to the customer; the Stripe fee booked at sale stays in 6100, absorbed',
        'refund_paid', r.id::text,
        jsonb_build_array(jsonb_build_object('account','6900','debit',gross),
                          jsonb_build_object('account','1050','credit',gross)), 'gl_sync');
      n := n + 1;
    else
      fee := least(round(coalesce(r.fee_absorbed,0),2), gross);
      if fee > 0 then
        perform public.fn_gl_entry(r.d, 'Stripe processing fee absorbed on a reveal refunded in full before its sale was booked',
          'refund_paid', r.id::text,
          jsonb_build_array(jsonb_build_object('account','6100','debit',fee),
                            jsonb_build_object('account','1050','credit',fee)), 'gl_sync');
        n := n + 1;
      end if;
    end if;
  end loop;

  -- 2) Clawback RAISED on the supplier. Credits 6900 (recovering the refund), NOT 4100.
  --    Any admin fee / interest assessed at the same time is genuine income -> 4400.
  --    A due with no supplier is judged as one whose supplier is gone (-1 is never a lead id).
  for r in
    select id, amount_due,
           coalesce(admin_fee,0) + coalesce(interest_amount,0) as extra_owed,
           coalesce(reveal_date, created_at::date, current_date) as d
    from public.supplier_dues
    where coalesce(amount_due,0) > 0
      and coalesce(status,'') not in ('waived','cancelled','reversed','void')
      and not exists (select 1 from public.gl_journal g where g.source='commission_accrue' and g.source_ref=supplier_dues.id::text)
      and public.fn_gl_fixture_or_orphan(supplier_dues.transaction_id, coalesce(supplier_dues.supplier_id, -1), null) is null
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    lines := jsonb_build_array(
      jsonb_build_object('account','1110','debit', round(r.amount_due,2) + extra),
      jsonb_build_object('account','6900','credit', round(r.amount_due,2)));
    if extra > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','4400','credit', extra)); end if;
    perform public.fn_gl_entry(r.d,
      'Refund clawback raised on supplier' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_accrue', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2b) Supplier SETTLES via Stripe.
  for r in
    select id, amount_due,
           coalesce(fine_amount,0) + coalesce(interest_amount,0) + coalesce(admin_fee,0) as extra_owed,
           paid_at::date as d
    from public.supplier_dues
    where status in ('paid','settled') and paid_at is not null and coalesce(amount_due,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='commission_collect' and g.source_ref=supplier_dues.id::text)
      and public.fn_gl_fixture_or_orphan(supplier_dues.transaction_id, coalesce(supplier_dues.supplier_id, -1), null) is null
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    gross := round(r.amount_due,2) + extra;
    fee   := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;

    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','1110','credit', gross));

    perform public.fn_gl_entry(r.d,
      'Refund clawback settled by supplier via Stripe' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_collect', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2c) SUBSCRIPTION revenue (RULE 1). Previously never posted - 4200 sat unused.
  for r in
    select l.id, l.registration_fee_due, l.registration_paid_at::date as d
    from public.leads l
    where l.registration_status = 'paid'
      and l.registration_paid_at is not null
      and coalesce(l.registration_fee_due,0) >= 0
      and coalesce(l.subscription_exempt,false) = false
      and not exists (select 1 from public.gl_journal g
                      where g.source='subscription' and g.source_ref = l.id::text || ':' || l.registration_paid_at::date)
      and public.fn_gl_fixture_or_orphan(null, l.id, null) is null
  loop
    gross := round(coalesce(r.registration_fee_due,0),2);
    if gross <= 0 then continue; end if;
    fee := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net := gross - fee;
    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','4200','credit',gross));
    perform public.fn_gl_entry(r.d, 'Annual supplier subscription', 'subscription',
      r.id::text || ':' || r.d::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 3) Expense charges, converted to AED (the ledger currency). A ZZ DEMO expense is a rehearsal's, never
  --    the company's (the same marker the receipt duty uses).
  for r in
    select e.id, e.amount, upper(coalesce(e.currency,'AED')) as cur, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d
    from public.expense_entries e
    where coalesce(e.amount,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
      and not ((coalesce(e.vendor, '') || ' ' || coalesce(e.note, '')) ~* 'zz[ _-]?demo')
  loop
    if r.cur not in ('AED','USD') then
      begin
        insert into public.founder_alerts(level, event, detail, channel)
        values ('warn', 'gl_unconvertible_currency',
                'Expense #'||r.id||' from '||coalesce(r.vendor,'?')||' is in '||r.cur||
                ', which has no rate in gl_settings, so it was NOT posted. Expenses are understated by '||
                r.amount||' '||r.cur||' until a rate is added. Skipped rather than booked at 1:1.', 'system');
      exception when others then null; end;
      continue;
    end if;
    amt_aed := round(r.amount * case when r.cur='USD' then fx else 1 end, 2);
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'Expense: '||coalesce(r.category,'G&A')||case when r.cur='USD' then ' ('||r.amount||' USD @ '||fx||')' else '' end,
      'expense', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',amt_aed),
                        jsonb_build_object('account','1000','credit',amt_aed)), 'gl_sync');
    n := n + 1;
  end loop;

  -- 3b) One-off FX correction for USD expenses posted at 1:1 before the 19 Jul 2026 fix.
  for r in
    select e.id, e.amount, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d,
           (select sum(jl.debit) from public.gl_journal g
              join public.gl_journal_lines jl on jl.journal_id = g.id
             where g.source='expense' and g.source_ref = e.id::text and jl.debit > 0) as posted_aed
    from public.expense_entries e
    where upper(coalesce(e.currency,'AED')) = 'USD'
      and coalesce(e.amount,0) > 0
      and exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
      and not exists (select 1 from public.gl_journal g where g.source='expense_fx_adj' and g.source_ref=e.id::text)
      and not ((coalesce(e.vendor, '') || ' ' || coalesce(e.note, '')) ~* 'zz[ _-]?demo')
  loop
    diff := round(r.amount * fx, 2) - coalesce(r.posted_aed, 0);
    if diff is null or diff = 0 then continue; end if;
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'FX correction: expense #'||r.id||' ('||coalesce(r.vendor,'?')||') was booked at 1:1; restated at USD/AED '||fx,
      'expense_fx_adj', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',diff),
                        jsonb_build_object('account','1000','credit',diff)), 'gl_fx_fix');
    n := n + 1;
  end loop;

  -- 4) AN ORPHAN IS NEVER BOOKED SILENTLY. Every open money row whose transaction, supplier or customer is
  --    gone is an accountant finding; the same call closes it once the row is reversed, cancelled or
  --    waived. Fixtures are expected and raise nothing.
  select coalesce(jsonb_agg(jsonb_build_object('item', x.item, 'owner_seat', 'accountant', 'subject', x.subject,
           'title', x.subject || ' #' || x.id || ' (' || x.amount || ' AED) was not booked: ' || x.why,
           'blast', 'internal', 'affected', 0, 'demo', false,
           'evidence', jsonb_build_object('row', x.id, 'amount_aed', x.amount, 'why', x.why, 'no_founder_email', true,
             'remedy', 'find what created it; reverse any journal already posted from it (fn_gl_reverse), then set the row reversed or cancelled with status_reason'))
           order by x.item), '[]'::jsonb)
    into v_orphans
    from (select 'supplier_dues:' || d.id as item, 'supplier_dues' as subject, d.id::text as id,
                 round(coalesce(d.total_claim, d.amount_due), 2) as amount,
                 public.fn_gl_fixture_or_orphan(d.transaction_id, coalesce(d.supplier_id, -1), null) as why
            from public.supplier_dues d
           where coalesce(d.amount_due, 0) > 0 and coalesce(d.status, '') not in ('waived', 'cancelled', 'reversed', 'void')
          union all
          select 'transactions:' || t.id, 'transactions', t.id::text,
                 round(coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0), 2),
                 public.fn_gl_fixture_or_orphan(t.id, null, null)
            from public.transactions t
           where t.fee_status = 'paid' or coalesce(t.refund_status, '') in ('refunded', 'refund_approved', 'succeeded')) x
   where x.why like 'orphan:%';
  perform public.fn_it_duty_settle('ledger_orphan', v_orphans);

  return n;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_glockapps_provider_class(p_name text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when lower(btrim(coalesce(p_name, ''))) ~ '^(outlook|hotmail|live|msn|exchange|office ?365|microsoft)' then 'microsoft'
    when lower(btrim(coalesce(p_name, ''))) ~ '^(gmail|google|g ?suite)' then 'google'
    when lower(btrim(coalesce(p_name, ''))) ~ '^(yahoo|aol)' then 'yahoo_aol'
    else 'other' end;
$function$


CREATE OR REPLACE FUNCTION public.fn_goal_attainment(p_horizon text DEFAULT 'monthly'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with p as (
    select case p_horizon
             when 'monthly'   then to_char(now(),'YYYY-MM')
             when 'quarterly' then to_char(now(),'YYYY')||'-Q'||extract(quarter from now())::int
             else to_char(now(),'YYYY') end as label),
  s as (
    select g.actual_value, g.target_value, coalesce(cg.direction,'at_least') dir
      from goal_period g
      left join company_goals cg on cg.key = g.goal_key
      cross join p
     where g.horizon = p_horizon and g.period_label = p.label and g.target_value is not null)
  select jsonb_build_object(
    'horizon', p_horizon,
    'period', (select label from p),
    'goals_total', count(*),
    'goals_measured', count(*) filter (where actual_value is not null),
    'pct', round(avg(case
        -- NOT least(100, ...): least() ignores nulls, so an unmeasured goal scored 100%.
        when actual_value is null then null
        when dir in ('at_most','down')
          then least(100.0, case when actual_value = 0 then 100.0
                                 else 100.0 * target_value / nullif(actual_value,0) end)
        else least(100.0, 100.0 * actual_value / nullif(target_value,0)) end), 1))
  from s;
$function$


CREATE OR REPLACE FUNCTION public.fn_governance_stamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_sensitive boolean;
begin
  v_sensitive := exists (select 1 from public.governance_sensitive g
                          where (g.subject = 'agent' and g.key = NEW.agent) or (g.subject = 'kind' and g.key = NEW.kind));
  if NEW.confidence is null then
    NEW.confidence := 0.9;
  end if;
  if NEW.evidence is null then
    NEW.evidence := jsonb_build_object('basis','deterministic rule from live platform data',
                                       'agent',NEW.agent,'kind',NEW.kind);
  end if;
  if NEW.escalated is not true and (coalesce(NEW.confidence,0) < 0.6 or v_sensitive) then
    NEW.escalated := true;
    NEW.escalation_reason := coalesce(NEW.escalation_reason,
      case when coalesce(NEW.confidence,0) < 0.6
           then 'Confidence below 0.60 threshold — human review required.'
           else 'Sensitive domain (registered in governance_sensitive) — human review required.' end);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_handoff_citation_gaps(p_since timestamp with time zone DEFAULT (now() - '1 day'::interval))
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with c as (
    select a.id,
           (a.evidence->'cites_note'->>'handoff_id') = a.id::text as cited,
           nullif(btrim(coalesce(a.evidence->'not_cited'->>'reason', '')), '') is not null as reasoned,
           coalesce(a.evidence->'not_cited'->>'by', 'unnamed') as reason_by
      from public.agent_actions a
     where a.kind = 'handoff' and a.status = 'done' and a.decided_at >= p_since
       and a.detail->'summary' ?& array['context','decision','open_asks','deadline'])
  select jsonb_build_object(
    'since', p_since,
    'closed_with_note', count(*),
    'cited', count(*) filter (where cited),
    'reason_recorded', count(*) filter (where not coalesce(cited, false) and reasoned),
    'reason_by', coalesce((select jsonb_object_agg(reason_by, n) from (select reason_by, count(*) n from c
                             where not coalesce(cited, false) and reasoned group by 1) r), '{}'::jsonb),
    'neither', count(*) filter (where not coalesce(cited, false) and not reasoned),
    'uncited_ids', coalesce(jsonb_agg(id order by id) filter (where not coalesce(cited, false) and not reasoned), '[]'::jsonb))
    from c;
$function$


CREATE OR REPLACE FUNCTION public.fn_handoff_contract_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_check_owner boolean := false;
  v_owner       record;
  v_missing     text;
begin
  new.updated_at := now();

  -- (a) THE OWNER CANNOT BE LOST. NOT NULL stops the null; this stops the blank, the stranger,
  --     the deactivated replacement, and the owner who does not belong to the sending department.
  if coalesce(btrim(new.accountable_owner), '') = '' then
    raise exception 'handoff %: accountable_owner cannot be blank', coalesce(new.id, 0);
  end if;
  if tg_op = 'INSERT' then
    v_check_owner := true;
  elsif new.accountable_owner is distinct from old.accountable_owner then
    v_check_owner := true;
  end if;
  if v_check_owner then
    select agent_key, department, active into v_owner
      from org_agents where agent_key = new.accountable_owner;
    if not found then
      raise exception 'handoff %: accountable_owner % is not on the roster',
        coalesce(new.id, 0), new.accountable_owner;
    end if;
    if not v_owner.active then
      raise exception 'handoff %: accountable_owner % is not an active employee',
        coalesce(new.id, 0), new.accountable_owner;
    end if;
    if v_owner.department is distinct from new.from_dept then
      raise exception 'handoff %: accountable_owner % belongs to %, not the originating department %',
        coalesce(new.id, 0), new.accountable_owner, coalesce(v_owner.department, '(none)'), new.from_dept;
    end if;
  end if;

  -- (b) THE LIFECYCLE. open -> accepted|rejected; accepted -> returned|closed;
  --     rejected|returned -> open (the sender corrected it). closed is terminal.
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if old.status = 'closed' then
      raise exception 'handoff %: closed is terminal, cannot move to %', new.id, new.status;
    end if;
    if not ((old.status = 'open'     and new.status in ('accepted','rejected'))
         or (old.status = 'accepted' and new.status in ('returned','closed'))
         or (old.status in ('rejected','returned') and new.status = 'open')) then
      raise exception 'handoff %: illegal transition % -> %', new.id, old.status, new.status;
    end if;
  end if;

  -- (c) CLOSURE NEEDS PROOF, PER CRITERION. This is CMP-HO-05 made unavoidable: a closure with a
  --     criterion nobody evidenced is refused, and the message names which criterion.
  if new.status = 'closed' then
    if new.closed_by is null or new.closed_at is null then
      raise exception 'handoff %: a closure must record who closed it and when', new.id;
    end if;
    select string_agg(c, '; ') into v_missing
      from unnest(new.closure_criteria) c
     where not exists (
       select 1 from jsonb_array_elements(coalesce(new.closure_evidence, '[]'::jsonb)) e
        where btrim(coalesce(e->>'criterion', '')) = btrim(c)
          and coalesce(btrim(e->>'evidence'), '') <> '');
    if v_missing is not null then
      raise exception 'handoff %: cannot close, no recorded proof for closure criteria: %',
        new.id, v_missing;
    end if;
  end if;

  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_handoff_is_late(p_detail jsonb, p_created_at timestamp with time zone, p_window interval, p_at timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when p_detail ? 'replied_at'
              then coalesce((p_detail->>'due_at')::timestamptz, p_created_at + p_window) < p_at
              else p_created_at + p_window < p_at end
$function$


CREATE OR REPLACE FUNCTION public.fn_handoff_note_citation(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('handoff_id', a.id, 'read_by', a.agent, 'read_at', now(),
                            'deadline', a.detail->'summary'->'deadline',
                            'open_asks', a.detail->'summary'->'open_asks',
                            'on_time', now() <= (a.detail->'summary'->>'deadline')::timestamptz)
    from public.agent_actions a
   where a.id = p_id and a.kind = 'handoff';
$function$


CREATE OR REPLACE FUNCTION public.fn_handoff_redact(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select regexp_replace(regexp_replace(
           regexp_replace(p::text, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}', '[email]', 'g'),
           '([+]|\m00)[0-9][0-9 -]{5,}[0-9]', '[phone]', 'g'),
           '\m0[1-9]([ -]?[0-9]){7,8}\M', '[phone]', 'g')::jsonb;
$function$


CREATE OR REPLACE FUNCTION public.fn_handoff_summary(p_detail jsonb, p_agent text, p_target_table text, p_target_id text, p_title text DEFAULT NULL::text, p_recommendation text DEFAULT NULL::text, p_self_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  d        jsonb := coalesce(p_detail, '{}'::jsonb);
  v_table  text  := nullif(btrim(coalesce(d->>'subject_table', p_target_table, '')), '');
  v_id     text  := nullif(btrim(coalesce(d->>'subject_id', p_target_id, '')), '');
  v_type   text  := coalesce(d->>'type', d->>'subject', 'handoff');
  v_from   text  := d->>'from';
  k        public.seat_handoff_kind;
  v_facts  jsonb;
  v_tried  jsonb;
  v_cases  jsonb;
  v_needed jsonb;
  v_links  jsonb;
  v_context  text;
  v_decision text;
  v_asks     jsonb;
  v_deadline timestamptz;
  v_dsource  text;
  v_row      jsonb;
  v_col      text;
begin
  if v_id is null then
    raise exception 'a handoff must name its case (subject_id or target_id) - refused, no note can be built';
  end if;
  v_table := coalesce(v_table, 'unknown');

  select * into k from public.seat_handoff_kind
   where type = v_type and from_seat = v_from and to_seat = p_agent;

  -- The sender's scalar facts, minus the keys that are the envelope itself.
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) into v_facts
    from jsonb_each(d) e
   where e.key not in ('type','from','from_name','to','subject_table','subject_id','summary','error',
                       'awaiting','replied_at','subject')
     -- 1013 review: no contact detail is a fact; a key naming one is dropped (its value is redacted below too)
     and e.key !~* '(mail|phone|mobile|whatsapp|msisdn|tel|contact|address|wa_?id|number$)'
     and jsonb_typeof(e.value) in ('string','number','boolean');

  -- What was already done on this case: earlier actions (any seat, any kind), newest first.
  select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) into v_tried
    from (select jsonb_build_object('action_id', a.id, 'seat', a.agent, 'kind', a.kind, 'status', a.status,
                                    'what', left(coalesce(a.title, a.kind), 200), 'at', a.created_at) x
            from public.agent_actions a
           where a.id is distinct from p_self_id
             and ((a.target_table = v_table and a.target_id = v_id)
               or (a.kind = 'handoff' and a.detail->>'subject_id' = v_id
                   and coalesce(a.detail->>'subject_table', a.target_table) = v_table))
           order by a.created_at desc limit 10) t;

  -- What the seats remember deciding on this case.
  select coalesce(jsonb_agg(jsonb_build_object('case_id', m.id, 'seat', m.seat, 'decision', left(m.decision, 300),
                                               'outcome', left(m.outcome, 300), 'finalised', m.finalised,
                                               'lessons', to_jsonb(m.lessons)) order by m.id desc), '[]'::jsonb)
    into v_cases
    from public.seat_case_memory m
   where m.source_table = v_table and m.source_id = v_id;

  v_needed := case
    when k.type is not null then jsonb_build_object(
      'ask', k.meaning, 'handler', k.handler,
      'reply_within', coalesce(k.reply_within::text, 'no deadline set'),
      'closes', case when k.originator_closes then v_from || ' re-verifies and closes' else p_agent || ' closes' end)
    else jsonb_build_object('ask', nullif(btrim(coalesce(p_recommendation, p_title, '')), ''),
                            'handler', null, 'reply_within', 'no registered conversation',
                            'closes', p_agent || ' closes')
  end;
  if nullif(btrim(coalesce(v_needed->>'ask', '')), '') is null then
    raise exception 'handoff % on %#% states nothing needed - refused', v_type, v_table, v_id;
  end if;

  select jsonb_agg(l) into v_links from (
    select 'public.' || v_table || '?id=eq.' || v_id as l
    union all select 'public.agent_actions?id=eq.' || (t->>'action_id') from jsonb_array_elements(v_tried) t
    union all select 'public.seat_case_memory?id=eq.' || (c->>'case_id') from jsonb_array_elements(v_cases) c
  ) z;

  -- 1013: CONTEXT. One sentence a colleague reads first.
  v_context := format('%s handed %s on %s#%s to %s.%s Earlier on this case: %s action(s), %s remembered decision(s).',
    coalesce(v_from, 'a seat'), v_type, v_table, v_id, p_agent,
    case when v_facts = '{}'::jsonb then '' else ' Facts: ' || left(v_facts::text, 400) || '.' end,
    jsonb_array_length(v_tried), jsonb_array_length(v_cases));

  -- 1013: DECISION. What the sender decided.
  v_decision := coalesce(
    nullif(btrim(d->>'decision'), ''),
    (select left(m.decision, 300) from public.seat_case_memory m
      where m.source_table = v_table and m.source_id = v_id and m.seat = v_from
        and nullif(btrim(m.decision), '') is not null order by m.id desc limit 1),
    case when v_from is not null
         then v_from || ' decided this needs ' || p_agent || ': ' || (v_needed->>'ask') end);

  -- 1013: OPEN ASKS. What the receiver must do, as a list.
  select coalesce(jsonb_agg(distinct q), '[]'::jsonb) into v_asks
    from (select v_needed->>'ask' as q
          union all select jsonb_array_elements_text(case when jsonb_typeof(d->'asks') = 'array' then d->'asks' else '[]'::jsonb end)
          union all select d->>'question') s
   where nullif(btrim(q), '') is not null;

  -- 1013: DEADLINE. The sender's own date, the conversation's window, the case's due date, else 24 h.
  begin
    v_deadline := nullif(coalesce(d->>'deadline', d->>'due_at'), '')::timestamptz;
    if v_deadline is not null then v_dsource := 'set by ' || coalesce(v_from, 'the sender'); end if;
  exception when others then v_deadline := null;
  end;
  if v_deadline is null and k.reply_within is not null then
    v_deadline := now() + k.reply_within; v_dsource := 'reply window of ' || v_type || ' (' || k.reply_within::text || ')';
  end if;
  if v_deadline is null and v_table ~ '^[a-z_][a-z0-9_]*$'
     and exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = v_table and c.column_name = 'id') then
    begin
      execute format('select to_jsonb(t) from public.%I t where t.id::text = $1 limit 1', v_table) into v_row using v_id;
      foreach v_col in array array['due_at','deadline','due_date','response_due_at','expires_at'] loop
        if v_row ? v_col and nullif(v_row->>v_col, '') is not null then
          v_deadline := (v_row->>v_col)::timestamptz; v_dsource := 'case due date ' || v_table || '.' || v_col; exit;
        end if;
      end loop;
    exception when others then v_deadline := null;
    end;
  end if;
  if v_deadline is null then
    v_deadline := now() + interval '24 hours'; v_dsource := 'default handoff window (24 hours)';
  end if;

  if nullif(btrim(v_context), '') is null or nullif(btrim(v_decision), '') is null
     or jsonb_array_length(v_asks) = 0 or v_deadline is null then
    raise exception 'handoff % on %#% cannot state its context, decision, open asks and deadline - refused', v_type, v_table, v_id;
  end if;

  -- 1013 review: the note is read by other seats and by a model; no e-mail address or phone number lands
  -- in it, whichever field carried it (a fact, the question, the decision, the title).
  return public.fn_handoff_redact(jsonb_build_object(
    'context', v_context,
    'decision', v_decision,
    'open_asks', v_asks,
    'deadline', v_deadline,
    'deadline_source', v_dsource,
    'known', jsonb_build_object('case', v_table || '#' || v_id, 'conversation', v_type,
                                'from', v_from, 'to', p_agent, 'means', k.meaning, 'facts', v_facts),
    'tried', jsonb_build_object('actions', v_tried, 'case_memory', v_cases),
    'needed', v_needed,
    'evidence', coalesce(v_links, '[]'::jsonb),
    'built_by', 'fn_handoff_summary'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_health_index()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  s_acq numeric; s_supp numeric; s_rfq numeric; s_qual numeric;
  s_resp numeric; s_disp numeric; s_up numeric;
  signups_7d int; quotes_7d int; approved_suppliers int;
  inq_total int; inq_done int; avg_qual numeric; avg_resp numeric;
  blocked_30d int; msgs_30d int; up_ok int; up_tot int;
  parts numeric[]; overall numeric; band text; present int;
begin
  select count(*) into signups_7d from customers where created_at > now()-interval '7 days' and not is_demo;
  select count(*) into quotes_7d  from quotes    where created_at > now()-interval '7 days' and not exists (select 1 from public.leads dl where dl.id = quotes.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = quotes.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo)));
  -- DEMO FIXTURES EXCLUDED. The marker is in the data, not the schema: the convention seeded on
  -- 7-8 Aug 2026 is 'ZZ DEMO ' in company_name and an @example.invalid address. Both are checked
  -- because either alone would let a half-formed fixture through.
  select count(*) into approved_suppliers from leads
     where (coalesce(approval_status,'')='approved' or claimed=true)
       and coalesce(company_name,'') not like 'ZZ DEMO%'
       and coalesce(email,'') not like '%@example.invalid'
       and not is_demo;
  -- RFQ completion: real RFQs only (exclude split-parent containers and customer-cancelled),
  -- success = completed/won or closed-with-a-hire (a "closed, not hired" is NOT a completion).
  select count(*) filter (where created_at > now()-interval '90 days'
                            and coalesce(status,'')<>'split' and coalesce(category,'')<>'combined'
                            and coalesce(status,'')<>'cancelled'),
         count(*) filter (where created_at > now()-interval '90 days'
                            and coalesce(status,'')<>'split' and coalesce(category,'')<>'combined'
                            and (status in ('completed','won')
                                 or (status='closed' and coalesce(outcome,'') in ('hired','hired_elsewhere'))))
    into inq_total, inq_done from inquiries where not (inquiries.provenance->>'qd_run' is not null or inquiries.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = inquiries.customer_id and dc.is_demo));
  select avg(nullif(quality->>'score','')::numeric) into avg_qual
    from quotes where quality is not null and created_at > now()-interval '90 days' and not exists (select 1 from public.leads dl where dl.id = quotes.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = quotes.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo)));
  select avg(nullif(rv_response_rate,0)) into avg_resp
    from leads where coalesce(rv_reveals,0) > 0 and not is_demo;
  select count(*) filter (where coalesce(blocked,false)),
         count(*) into blocked_30d, msgs_30d
    from messages where created_at > now()-interval '30 days';
  select count(*) filter (where ok), count(*) into up_ok, up_tot
    from health_checks where created_at > now()-interval '24 hours';

  s_acq  := least(100, signups_7d * 10.0);
  s_supp := case when approved_suppliers=0 and quotes_7d=0 then null
                 else least(100, quotes_7d * 5.0) end;
  s_rfq  := case when inq_total=0 then null else round(inq_done::numeric/inq_total*100,1) end;
  s_qual := avg_qual;
  s_resp := case when avg_resp is null then null
                 when avg_resp <= 1 then round(avg_resp*100,1) else round(avg_resp,1) end;
  s_disp := case when msgs_30d=0 then null
                 else greatest(0, 100 - least(100, blocked_30d*5.0)) end;
  s_up   := case when up_tot=0 then null else round(up_ok::numeric/up_tot*100,1) end;

  parts := array_remove(array[s_acq,s_supp,s_rfq,s_qual,s_resp,s_disp,s_up], null);
  present := coalesce(array_length(parts,1),0);
  overall := case when present=0 then null else round((select avg(x) from unnest(parts) x),1) end;
  band := case when overall is null then 'no data'
               when overall >= 75 then 'healthy'
               when overall >= 50 then 'watch'
               else 'attention' end;

  return jsonb_build_object(
    'index', overall, 'band', band, 'components_present', present,
    -- A PROSE INSIGHT WITH A CAUSE AND A MAGNITUDE, not a blank.
    -- `overall` is the mean of the present components, so the ones furthest below it are
    -- arithmetically what hold the index there. "driven by" is division, not narrative.
    'note', case
      when present < 3 then 'insufficient data - pre-traction; index will firm up with volume'
      else (select 'Company health is '||overall||' of 100 ('||band||'), driven by '
              ||string_agg(w.label||' at '||w.score, ' and ' order by w.score, w.label)
              ||' - the two furthest below the '||overall||'-point average of '||present
              ||' measured components.'
              from (select v.label, v.score from (values
                      ('customer acquisition', s_acq), ('supplier activity', s_supp),
                      ('RFQ completion', s_rfq), ('quote quality', s_qual),
                      ('response time', s_resp), ('dispute health', s_disp), ('uptime', s_up)
                    ) v(label, score)
                     where v.score is not null order by v.score, v.label limit 2) w)
      end,
    'components', jsonb_build_object(
       'customer_acquisition', s_acq, 'supplier_activity', s_supp, 'rfq_completion', s_rfq,
       'quote_quality', s_qual, 'response_time', s_resp, 'dispute_health', s_disp,
       'uptime', s_up, 'revenue', null),
    'raw', jsonb_build_object(
       'signups_7d', signups_7d, 'quotes_7d', quotes_7d, 'approved_suppliers', approved_suppliers,
       'inquiries_eligible_90d', inq_total, 'completed_90d', inq_done,
       'blocked_msgs_30d', blocked_30d, 'uptime_ok', up_ok, 'uptime_checks', up_tot),
    'computed_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_held_question_is_person_facing(p_surface text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(p_surface, '') in ('wa_inbound.unwritten_reply', 'supplier_api.quote_review_unwritten', 'sales_engineer.portal_unwritten',
                                     'inquiry_intake.unwritten_reply')
      or coalesce(p_surface, '') like '%needs_a_person%'
$function$


CREATE OR REPLACE FUNCTION public.fn_held_questions_settle(p_limit integer DEFAULT 1000)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a record; v_status text; v_verdict text; v_later bigint; n_done int := 0; n_dismissed int := 0; n_overdue int := 0; n_open int := 0;
  v_by jsonb := '{}'::jsonb;
begin
  -- EVERY PARKED QUESTION HAS AN OWNER AND A DEADLINE: its seat, and created + the seat clock policy held_question_days
  -- (default 7). Stamped here rather than by a trigger on agent_actions, so no DDL ever takes a lock on that table.
  update public.agent_actions x
     set detail = coalesce(x.detail, '{}'::jsonb) || jsonb_build_object('owner_seat', x.agent,
                    'due_at', (x.created_at + make_interval(days => greatest(1, public.fn_seat_clock_policy('held_question_days', 7)::int)))::text)
   where x.id in (select y.id from public.agent_actions y
                   where y.kind = 'held_question' and y.status = 'pending' and not (coalesce(y.detail, '{}'::jsonb) ? 'due_at')
                   for update skip locked);
  for a in select x.*, r.id rid, r.status rstatus, r.surface rsurface, r.subject rsubject, r.applied_at, r.expires_at, r.created_at rcreated
             from public.agent_actions x left join public.reasoning_held_question r on r.id = (x.detail->>'held_id')::bigint
            where x.kind = 'held_question' and x.status = 'pending'
            order by x.id limit greatest(1, least(coalesce(p_limit, 1000), 5000))
            for update of x skip locked loop
    v_status := null; v_verdict := null; v_later := null;
    if a.rid is null then
      v_status := 'dismissed'; v_verdict := 'the held question no longer exists (reasoning_held_question ' || coalesce(a.detail->>'held_id', '?') || ')';
    elsif a.rstatus = 'applied' then
      v_status := 'done'; v_verdict := 'answered and applied' || coalesce(' on ' || to_char(a.applied_at, 'YYYY-MM-DD'), '');
    else
      select r2.id into v_later from public.reasoning_held_question r2
       where r2.seat = a.agent and r2.surface = a.rsurface and r2.subject is not distinct from a.rsubject
         and r2.created_at > a.rcreated and r2.id <> a.rid
       order by r2.created_at desc limit 1;
      if v_later is not null and not public.fn_held_question_is_person_facing(a.rsurface) then
        v_status := 'dismissed'; v_verdict := 'superseded: the same question was asked again as held question ' || v_later;
      elsif a.rstatus = 'expired' and not public.fn_held_question_is_person_facing(a.rsurface) then
        v_status := 'dismissed'; v_verdict := 'the question expired unanswered' || coalesce(' on ' || to_char(a.expires_at, 'YYYY-MM-DD'), '') || '; nothing will apply it';
      end if;
    end if;
    if v_status is not null then
      update public.agent_actions
         set status = v_status, decided_at = now(), decided_by = 'it_engineer:fn_held_questions_settle',
             evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('verdict', v_verdict, 'held_status', a.rstatus, 'settled_at', now())
       where id = a.id;
      if v_status = 'done' then n_done := n_done + 1; else n_dismissed := n_dismissed + 1; end if;
      v_by := jsonb_set(v_by, array[coalesce(a.rstatus, 'gone')], to_jsonb(coalesce((v_by->>coalesce(a.rstatus, 'gone'))::int, 0) + 1));
    elsif coalesce(a.detail->>'due_at', '') <> '' and (a.detail->>'due_at')::timestamptz < now() then
      if not (a.detail ? 'overdue_at') then
        update public.agent_actions set detail = detail || jsonb_build_object('overdue_at', now()) where id = a.id;
      end if;
      n_overdue := n_overdue + 1;
    else
      n_open := n_open + 1;
    end if;
  end loop;
  return jsonb_build_object('done', n_done, 'dismissed', n_dismissed, 'settled_by_held_status', v_by, 'overdue', n_overdue, 'open_in_time', n_open);
end $function$


CREATE OR REPLACE FUNCTION public.fn_held_targets()
 RETURNS TABLE(target_key text, hold_key text, what_is_held text, until_when text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select k, h.hold_key, h.what_is_held, h.until_when
    from public.founder_hold h cross join lateral unnest(h.target_keys) k
   where (select s.value from public.app_secrets s where s.key = h.flag_key) is distinct from h.flag_released_value
$function$


CREATE OR REPLACE FUNCTION public.fn_high_stakes_campaign_review(p_campaign_id bigint, p_owed boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.marketing_campaign; v_q text; v_ev jsonb; v_prop jsonb; v_id bigint;
begin
  select * into c from public.marketing_campaign where id = p_campaign_id;
  if c.id is null or c.is_demo or c.approved_at is null then
    return jsonb_build_object('opened', false, 'reason', 'not an approved real campaign');
  end if;
  v_q := 'Should this month''s organic campaign be launched as approved?';
  v_ev := jsonb_build_object('campaign', jsonb_build_object('month', c.month, 'spend_policy', c.spend_policy),
            'posts', (select count(*) from public.marketing_post p where p.campaign_id = c.id));
  v_prop := jsonb_build_object('campaign_key', c.campaign_key, 'theme', c.theme, 'title', c.title,
              'posts', (select jsonb_agg(jsonb_build_object('channels', p.channels, 'scheduled_at', p.scheduled_at, 'text', left(p.text_en, 300)) order by p.scheduled_at)
                          from (select * from public.marketing_post p where p.campaign_id = c.id order by p.scheduled_at limit 40) p));
  if not p_owed then
    return public.fn_high_stakes_gate('campaign_launch', 'marketing', 'marketing_campaign', c.id::text, v_q, v_ev, v_prop);
  end if;
  v_id := public.fn_high_stakes_challenge('campaign_launch', 'marketing', 'marketing_campaign', c.id::text, v_q, v_ev, v_prop, 'deterministic');
  update public.seat_deliberation set proceeded_at = coalesce(proceeded_at, c.approved_at) where id = v_id;
  return jsonb_build_object('opened', true, 'deliberation_id', v_id, 'owed', true);
end $function$


CREATE OR REPLACE FUNCTION public.fn_high_stakes_challenge(p_kind text, p_author_seat text, p_subject_table text, p_subject_id text, p_question text, p_evidence jsonb, p_proposal jsonb, p_author_model text, p_author_task_class text DEFAULT NULL::text, p_demo boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_reviewer text := public.fn_high_stakes_reviewer(p_kind, p_author_seat); v_id bigint;
begin
  if v_reviewer is null then
    raise exception 'not a high-stakes kind: % (pricing_change, campaign_launch, supplier_choice, refund)', p_kind using errcode = '22023';
  end if;
  if coalesce(btrim(p_subject_table), '') = '' or coalesce(btrim(p_subject_id), '') = '' then
    raise exception 'a high-stakes challenge names the decision it is about (subject table and id)' using errcode = '22023';
  end if;
  select d.id into v_id from public.seat_deliberation d
   where d.kind = 'high_stakes.' || p_kind and d.subject_table = p_subject_table and d.subject_id = p_subject_id and d.status <> 'closed'
   order by d.id desc limit 1;
  if v_id is not null then return v_id; end if;
  return public.fn_seat_deliberation_open('high_stakes.' || p_kind, p_author_seat, v_reviewer, p_question, p_evidence, p_proposal,
    p_author_model, p_author_task_class, p_subject_table, p_subject_id, p_demo);
end $function$


CREATE OR REPLACE FUNCTION public.fn_high_stakes_clearance(p_kind text, p_subject_table text, p_subject_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.seat_deliberation; c public.seat_deliberation_turn; h public.seat_deliberation_turn; v_state text;
begin
  select * into d from public.seat_deliberation x
   where x.kind = 'high_stakes.' || p_kind and x.subject_table = p_subject_table and x.subject_id = p_subject_id
   order by x.id desc limit 1;
  if d.id is null then
    return jsonb_build_object('cleared', false, 'state', 'not_challenged', 'reason', 'no second seat has reviewed this decision');
  end if;
  select * into c from public.seat_deliberation_turn t
   where t.deliberation_id = d.id and t.phase = 'compare' and t.status = 'recorded' order by t.round desc, t.id desc limit 1;
  select * into h from public.seat_deliberation_turn t
   where t.deliberation_id = d.id and t.status = 'held_not_run' and t.round = d.round
     and not exists (select 1 from public.seat_deliberation_turn r where r.deliberation_id = d.id and r.round = t.round
                        and r.phase = t.phase and r.status = 'recorded')
   order by t.id desc limit 1;
  v_state := case when c.id is not null and c.round = d.round then case when c.verdict = 'approve' then 'agreed' else 'disagreed' end
                  when d.status = 'no_independent_reviewer' then 'no_independent_reviewer'
                  when h.id is not null then 'held'
                  else 'pending' end;
  return jsonb_build_object('cleared', v_state = 'agreed', 'state', v_state, 'deliberation_id', d.id,
    'author_seat', d.author_seat, 'reviewer_seat', d.reviewer_seat, 'author_model', d.author_model,
    'reviewer_model', c.model, 'verdict', c.verdict,
    'reason', case v_state when 'agreed' then c.agreements when 'disagreed' then c.disagreements when 'held' then h.why
                           when 'pending' then 'waiting for the ' || d.reviewer_seat || ' seat''s review'
                           else 'no model of another family was available; escalated' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_high_stakes_gate(p_kind text, p_author_seat text, p_subject_table text, p_subject_id text, p_question text, p_evidence jsonb, p_proposal jsonb, p_author_model text DEFAULT NULL::text, p_author_task_class text DEFAULT NULL::text, p_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_model text := p_author_model; v_class text := p_author_task_class; v_id bigint; v_err text; v_held boolean; c jsonb; v_go boolean;
begin
  if public.fn_deliberation_subject_is_fixture(p_subject_table, p_subject_id) then
    return jsonb_build_object('proceed', true, 'state', 'not_challenged', 'fixture', true, 'deliberation_id', null,
      'reason', 'the subject is an identity of our own E2E harness: no second-seat review is opened, none is ever paid for');
  end if;
  -- THE AUTHOR'S MODEL: the one given, else the seat's latest reasoning call in 24 hours (what open() proves), else code.
  if v_model is null then
    select l.model_used, l.task_class into v_model, v_class from public.ai_cost_log l
     -- 1056: think() bills a seat's decision to internal_judgement
     where l.ok and l.task_class = 'internal_judgement' and l.occurred_at > now() - interval '24 hours'
       and (l.agent_key = p_author_seat or l.seat = p_author_seat)
     order by l.occurred_at desc, l.id desc limit 1;
    v_model := coalesce(v_model, 'deterministic');
    if v_model = 'deterministic' then v_class := null; end if;
  end if;
  begin
    v_id := public.fn_high_stakes_challenge(p_kind, p_author_seat, p_subject_table, p_subject_id, p_question, p_evidence, p_proposal,
                                           v_model, v_class, p_demo);
  exception when others then
    v_err := sqlerrm;
    -- Recorded for the deciding seat, never raised: the decision path decides what a failed gate means.
    perform public.fn_it_engineer_finding_upsert('high_stakes_open:' || p_kind || ':' || p_subject_table || ':' || p_subject_id,
      'The second-seat review of a ' || p_kind || ' decision could not be opened', p_author_seat || ' ' || p_kind || ' on ' || p_subject_table,
      'agent_facing', 1, jsonb_build_object('owner_seat', p_author_seat, 'error', left(v_err, 500), 'subject_id', p_subject_id), '{}', '{}', 'it_engineer');
  end;
  v_held := public.fn_high_stakes_model_held();
  c := public.fn_high_stakes_clearance(p_kind, p_subject_table, p_subject_id);
  v_go := coalesce((c->>'cleared')::boolean, false) or (v_held and coalesce(c->>'state', '') <> 'disagreed');
  if v_go and not coalesce((c->>'cleared')::boolean, false) and v_id is not null then
    update public.seat_deliberation set proceeded_at = coalesce(proceeded_at, now()) where id = v_id;
  end if;
  return c || jsonb_build_object('proceed', v_go, 'owed', v_go and not coalesce((c->>'cleared')::boolean, false),
                                 'model_held', v_held, 'author_model', v_model, 'open_error', v_err);
end $function$


CREATE OR REPLACE FUNCTION public.fn_high_stakes_may_proceed(p_kind text, p_subject_table text, p_subject_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((public.fn_high_stakes_clearance(p_kind, p_subject_table, p_subject_id)->>'cleared')::boolean, false)
      or exists (select 1 from public.seat_deliberation d where d.kind = 'high_stakes.' || p_kind and d.subject_table = p_subject_table
                    and d.subject_id = p_subject_id and d.proceeded_at is not null)
$function$


CREATE OR REPLACE FUNCTION public.fn_high_stakes_model_held()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- The same probe llm_hold.ts asks: the hold is a gate rule, not a row count.
  select coalesce((g->>'allowed')::boolean, false) is not true and g->>'rule' in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state')
    from (select public.fn_kernel_paid_provider_gate('hold-probe/not-a-model') g) x
$function$


CREATE OR REPLACE FUNCTION public.fn_high_stakes_reviewer(p_kind text, p_author_seat text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when p_kind in ('pricing_change', 'campaign_launch', 'supplier_choice', 'refund')
              then case when p_author_seat = 'ceo' then 'accountant' else 'ceo' end end
$function$


