-- fn_decide, given the producer it never had.
--
-- Before this change the ten-step chain was a table with three hand-typed rows: fn_decide appended
-- to decision_log (1,099 rows) and NOTHING ever wrote decision_record, so steps 1/4/6/9 had a
-- column each and no engine, trg_decision_gate had never fired once, and fn_memory_search — the
-- knowledge-retrieval step — had zero callers in the entire database.
--
-- The signature is UNCHANGED on purpose: (p_kind text, p_ctx jsonb, p_actor text DEFAULT 'agent').
-- CREATE OR REPLACE with a different argument list makes an OVERLOAD, not a replacement, and the
-- old body would keep running under every existing caller.
--
-- What is added, in blueprint step order:
--   step 3  a real fn_memory_search retrieval whose hits are attached to decision_log.sources and
--           to decision_record.evidence — the retrieval marker is written even on zero hits, because
--           "we looked and found nothing" is a different claim from "we never looked"
--   step 4  the four impact fields, each derived from what the branch actually computed
--   step 6  two SCORED options, the selected one and the alternative it beat, never one
--   step 7  trg_decision_gate is now actually reached: a decision within autonomous thresholds is
--           inserted as 'approved' so the gate inspects it, and a decision that escalates is not
--   step 9  a passing decision writes decision_trace + action_execution on ONE correlation_id, so
--           the execution points back at the decision_record that caused it
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
  v_escalates boolean; v_status text; v_approver text;
  v_dr_id bigint; v_dr_status text; v_verdict text; v_gate_reason text;
  v_corr uuid; v_trace uuid;
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
  v_escalates := decision in ('escalate','human_review','unsupported_kind')
                 or conf < 0.7
                 or jsonb_array_length(v_evidence) = 0;
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
      format('%s (confidence %s, route %s)', decision, conf, coalesce(route,'none')),
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
  -- ponytail: the action is written 'queued' because nothing drains action_execution yet —
  -- marking it 'succeeded' here would be a claim the system cannot back.
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
                            'options',v_options,'knowledge_hits',jsonb_array_length(v_hits));
end $function$;
