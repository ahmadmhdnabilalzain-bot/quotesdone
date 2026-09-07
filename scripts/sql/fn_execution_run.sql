-- STEP 9 (Execution), given the thing it never had: something that actually executes.
--
-- MEASURED DEFECT, production, 6 Aug 2026: action_execution held 4 rows, all 'stalled', and the
-- table has never contained a single success in its history. That is not bad luck, it is
-- structural. fn_decide writes the row 'queued'; fn_execution_sweep is the only other routine that
-- touches it, and the sweep does not perform anything — its 'succeeded' branch fires only
-- `when d.status = 'executed'`, and NOTHING in the database has ever set decision_record.status to
-- 'executed'. So the queue's only possible fate was to be relabelled 'stalled' sixty minutes after
-- it was written. Step 9 was being scored complete by the routine that gives up on it.
--
-- WHAT "EXECUTE" MEANS HERE, STATED PLAINLY. fn_decide's decisions are routing and approval
-- rulings; the work they commit the company to is that the party the decision names is actually
-- given the item. Nothing was doing that: the engine decided, queued an action_execution row, and
-- no one was ever told. So execution is delivery — an agent_actions row addressed to the actor the
-- decision named, carrying the decision it came from — and the execution row records the id of the
-- artefact it created, so the claim "this ran" is checkable against a row rather than a status.
--
-- A row this routine cannot honestly execute is settled honestly instead: a decision the gate
-- refused is 'cancelled', and a decision naming a party that resolves to no actor is 'failed' with
-- the unresolved name in the response. Nothing is left queued to be relabelled by the sweep.
create or replace function public.fn_execution_run(p_limit integer default 25)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_agent text; v_aa bigint; v_queue jsonb;
        v_done integer := 0; v_failed integer := 0; v_cancelled integer := 0;
begin
  for r in
    select a.id, a.correlation_id, a.action_class, a.risk_tier, a.request,
           d.id as dr_id, d.status as dr_status, d.gate_verdict as dr_verdict,
           d.recommendation, d.problem, d.decided_by
      from public.action_execution a
      left join public.decision_record d on d.id::text = a.request ->> 'decision_record_id'
     where a.status in ('queued','stalled')
     order by a.created_at
     limit greatest(coalesce(p_limit, 25), 1)
  loop
    -- NOT EXECUTABLE. The gate refused it, or it never reached the gate, or the decision is gone.
    if r.dr_id is null or coalesce(r.dr_verdict,'') <> 'passed'
       or coalesce(r.dr_status,'') not in ('approved','executed') then
      update public.action_execution
         set status      = 'cancelled',
             attempts    = coalesce(attempts,0) + 1,
             started_at  = coalesce(started_at, now()),
             finished_at = now(),
             response    = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                             'ran_at', now(), 'outcome', 'cancelled',
                             'reason', case when r.dr_id is null
                                            then 'the decision this action came from no longer exists'
                                            else format('decision_record %s is %s and the gate said %s — not executable',
                                                        r.dr_id, coalesce(r.dr_status,'?'),
                                                        coalesce(r.dr_verdict,'nothing')) end)
       where id = r.id;
      v_cancelled := v_cancelled + 1;
      continue;
    end if;

    -- WHO THE DECISION NAMED. route_to is the party the engine chose, and it is a real identity in
    -- two different registers: an employee (org_agents) or a category desk (agent_knowledge, where
    -- 'cat:signage' carries 8 rows of its own knowledge). Failing that, the decider carries it.
    v_agent := coalesce(
      (select o.agent_key from public.org_agents o
        where o.agent_key = nullif(btrim(r.request ->> 'route_to'),'') and o.active limit 1),
      (select k.agent_key from public.agent_knowledge k
        where k.agent_key = nullif(btrim(r.request ->> 'route_to'),'') limit 1),
      (select o2.agent_key from public.org_agents o2
        where o2.agent_key = nullif(btrim(r.decided_by),'') and o2.active limit 1));

    if v_agent is null then
      update public.action_execution
         set status      = 'failed',
             attempts    = coalesce(attempts,0) + 1,
             started_at  = coalesce(started_at, now()),
             finished_at = now(),
             response    = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                             'ran_at', now(), 'outcome', 'failed',
                             'reason', format('route_to %L resolves to no active employee and no category desk, and decider %L is not an active employee either',
                                              r.request ->> 'route_to', r.decided_by))
       where id = r.id;
      v_failed := v_failed + 1;
      continue;
    end if;

    -- PERFORM IT: the decision is handed to the actor it named.
    insert into public.agent_actions(agent, kind, title, recommendation, detail, risk, status, decided_by)
    values (v_agent, r.action_class,
            left(coalesce(nullif(btrim(r.problem),''), 'decision_record ' || r.dr_id::text), 180),
            coalesce(nullif(btrim(r.recommendation),''), 'carry out the decision on record'),
            jsonb_build_object('decision_record_id', r.dr_id, 'correlation_id', r.correlation_id,
                               'execution_id', r.id, 'route_to', r.request ->> 'route_to',
                               'source', 'fn_execution_run'),
            coalesce(r.risk_tier, 'low'), 'pending', r.decided_by)
    returning id into v_aa;

    -- A BEFORE trigger on agent_actions may swallow the row (dedupe_it_incident returns NULL for a
    -- duplicate open incident). No artefact means nothing was delivered, so it is not a success.
    if v_aa is null then
      update public.action_execution
         set status      = 'failed',
             attempts    = coalesce(attempts,0) + 1,
             started_at  = coalesce(started_at, now()),
             finished_at = now(),
             response    = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                             'ran_at', now(), 'outcome', 'failed',
                             'reason', format('delivery to %L was refused by a trigger on agent_actions', v_agent))
       where id = r.id;
      v_failed := v_failed + 1;
      continue;
    end if;

    update public.action_execution
       set status      = 'succeeded',
           attempts    = coalesce(attempts,0) + 1,
           started_at  = coalesce(started_at, now()),
           finished_at = now(),
           response    = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                           'ran_at', now(), 'outcome', 'succeeded',
                           'agent_action_id', v_aa, 'delivered_to', v_agent,
                           'decision_record_id', r.dr_id)
     where id = r.id;

    update public.decision_record
       set status = 'executed'
     where id = r.dr_id and status = 'approved';

    v_done := v_done + 1;
  end loop;

  select jsonb_object_agg(status, n) into v_queue
    from (select status, count(*) n from public.action_execution group by 1) z;

  return jsonb_build_object('executed', v_done, 'failed', v_failed, 'cancelled', v_cancelled,
                            'queue', coalesce(v_queue,'{}'::jsonb), 'ran_at', now());
end $function$;

-- THE CONSUMER decision_trace NEVER HAD.
--
-- Round 3's finding, verbatim: the only non-producer routine naming decision_trace was
-- fn_execution_sweep, and its single read of the table is `coalesce(t.outcome_status,'') is
-- distinct from a.status` — reading back the column it writes, purely to skip a no-op UPDATE.
-- Nothing anywhere consumed outcome_status, outcome or evaluated_at, so step 9's second artefact
-- was written-and-unread, which is the one thing this whole spec file exists to catch.
--
-- This function reads them and writes nothing, and fn_decide calls it BEFORE it decides: the track
-- record of past decisions of the same kind is retrieved, attached to the new decision's sources
-- and evidence, and — when it is bad — pulls the confidence below the autonomy threshold so the
-- decision escalates instead of being taken. An outcome that changes the next decision is a
-- consumed outcome.
create or replace function public.fn_decision_outcomes(p_kind text, p_days integer default 90)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
  -- 'cancelled' is counted and reported but is NOT a failure: it means the decision was withdrawn
  -- or refused before it ran, which the authority gate has already ruled on and which says nothing
  -- about whether decisions OF THIS KIND work when they are carried out. Folding it in would make
  -- three gate refusals suppress a whole decision kind for ninety days, which is a punishment, not
  -- a measurement.
  select jsonb_build_object(
           'decision_type', p_kind,
           'window_days',   greatest(coalesce(p_days, 90), 1),
           'traced',        count(*),
           'graded',        count(*) filter (where t.outcome_status is not null),
           'succeeded',     count(*) filter (where t.outcome_status = 'succeeded'),
           'failed',        count(*) filter (where t.outcome_status in ('failed','stalled')),
           'cancelled',     count(*) filter (where t.outcome_status = 'cancelled'),
           'last_evaluated_at', max(t.evaluated_at))
    from public.decision_trace t
   where t.decision_type = p_kind
     and t.created_at > now() - make_interval(days => greatest(coalesce(p_days, 90), 1));
$function$;

-- fn_decide, with the outcome feedback wired in. THE SIGNATURE IS UNCHANGED: CREATE OR REPLACE with
-- a different argument list makes an OVERLOAD, not a replacement, and every existing caller would
-- keep running the old body.
--
-- THIS FILE SUPERSEDES scripts/sql/fn_decide_producer.sql, which was deleted rather than left
-- beside it. Two files defining one routine is how a deployed repair gets silently reverted by
-- someone re-applying the older of the pair; the producer file's history is in git.
create or replace function public.fn_decide(p_kind text, p_ctx jsonb, p_actor text default 'agent'::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
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
    res := public.fn_should_escalate(v_ctx);
    decision := case when (res->>'escalate')::boolean then 'escalate' else 'proceed' end;
    reasons := res->'reasons'; route := res->>'route_to';
    conf := case when (res->>'escalate')::boolean then 0.9 else 0.8 end;
    sources := to_jsonb(array['decision_policy']);
    v_alt := case when decision='escalate' then 'proceed' else 'escalate' end;
    v_alt_why := 'the opposite verdict from fn_should_escalate on the same context';

  elsif p_kind='price' then
    res := public.fn_price_confidence(coalesce(v_ctx->>'category','default'), nullif(v_ctx->>'amount_aed','')::numeric);
    decision := 'priced'; conf := coalesce((res->>'confidence')::numeric, 0.5);
    reasons := jsonb_build_array(coalesce(res->>'band', 'price band computed')); sources := to_jsonb(array['price_confidence']);
    route := 'none';
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
    res := public.fn_should_escalate(v_ctx);
    if (res->>'escalate')::boolean then decision:='human_review'; conf:=0.9; reasons:=res->'reasons';
    else decision:='auto_approve'; conf:=0.85; reasons:=jsonb_build_array('within autonomous thresholds'); end if;
    route := res->>'route_to'; sources := to_jsonb(array['decision_policy']);
    v_alt := case when decision='human_review' then 'auto_approve' else 'human_review' end;
    v_alt_why := 'the opposite side of the autonomous threshold in decision_policy';

  else
    decision := 'unsupported_kind'; conf := 0; reasons := jsonb_build_array('no handler for kind '||p_kind); route:='Secretary';
    v_alt := 'add_a_handler'; v_alt_why := 'teach fn_decide this kind rather than routing it to a person every time';
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

-- Ten minutes before execution_sweep_hourly (:20), so the sweep finds a settled queue and mirrors
-- the outcome onto the trace rather than relabelling an undrained one 'stalled'.
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
