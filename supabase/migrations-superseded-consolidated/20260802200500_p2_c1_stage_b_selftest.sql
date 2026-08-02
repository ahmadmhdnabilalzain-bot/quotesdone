-- P2-C1 STAGE B (6/6) - the fourteen required proofs, plus two regressions for bugs found while
-- re-running Stage A against Stage B. Applied as p2_c1_stage_b_selftest and
-- p2_c1_stage_b_regression_tests.
-- Re-runnable: select * from public.fn_p2c1_stage_b_selftest();

create or replace function public.fn_p2c1_stage_b_selftest()
returns table(test_no integer, name text, passed boolean, detail text, ms numeric)
language plpgsql security definer set search_path to 'public' as $fn$
declare
  g1 bigint; g2 bigint; g3 bigint; g4 bigint; g5 bigint; g6 bigint;
  r jsonb; rep jsonb; n integer; n2 integer; b boolean; t text; t2 text;
  we bigint; wf bigint; f_em text; t0 timestamptz; groups bigint[];
  intake_before bigint; intake_after bigint;
begin
  select count(*) into intake_before from public.inquiry_intake;

  insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g1;
  t0 := clock_timestamp();
  r := public.fn_trade_identify(g1, 'Full MEP package required for a new building.', null, null, 'selftest');
  ms := round(extract(milliseconds from clock_timestamp()-t0)::numeric,1);
  select string_agg(trade_key,',' order by trade_key) into t
    from public.inquiry_workstream where group_id = g1 and active;
  test_no := 1; name := '"Full MEP package" activates HVAC, Electrical and Plumbing';
  passed := (t = 'electrical,hvac,plumbing'
             and not exists (select 1 from public.inquiry_trade_candidate
                              where group_id = g1 and trade_key in ('fire','elv')));
  detail := format('active workstreams = [%s]; fire and ELV were not created, because "full MEP" does not order them', t);
  return next;

  insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g2;
  t0 := clock_timestamp();
  r := public.fn_trade_identify(g2, 'HVAC only for the office floor.', null, null, 'selftest');
  ms := round(extract(milliseconds from clock_timestamp()-t0)::numeric,1);
  select string_agg(trade_key,',' order by trade_key), count(*) into t, n
    from public.inquiry_workstream where group_id = g2 and active;
  test_no := 2; name := '"HVAC only" activates only HVAC';
  passed := (t = 'hvac' and n = 1);
  detail := format('active workstreams = [%s], count = %s', t, n);
  return next;

  insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g3;
  t0 := clock_timestamp();
  r := public.fn_trade_identify(g3, 'We need electrical and plumbing works.', null, null, 'selftest');
  ms := round(extract(milliseconds from clock_timestamp()-t0)::numeric,1);
  select string_agg(trade_key,',' order by trade_key), count(*) into t, n
    from public.inquiry_workstream where group_id = g3 and active;
  test_no := 3; name := 'electrical plus plumbing activates exactly two workstreams';
  passed := (t = 'electrical,plumbing' and n = 2);
  detail := format('active workstreams = [%s], count = %s', t, n);
  return next;

  insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g4;
  t0 := clock_timestamp();
  r := public.fn_trade_identify(g4, 'MEP works.', null, null, 'selftest');
  ms := round(extract(milliseconds from clock_timestamp()-t0)::numeric,1);
  select count(*) into n from public.inquiry_trade_clarification where group_id = g4 and answered_at is null;
  select count(*) into n2 from public.inquiry_workstream where group_id = g4 and active;
  select reason into t from public.inquiry_trade_clarification where group_id = g4 and answered_at is null;
  test_no := 4; name := 'a vague "MEP works" request asks exactly one clarification';
  passed := ((r->>'clarification_required')::boolean and n = 1 and n2 = 0 and r->>'confirmed' = '[]');
  detail := format('open clarifications = %s, active workstreams = %s, reason: %s', n, n2, t);
  return next;

  t0 := clock_timestamp();
  r := public.fn_trade_identify(g1, 'Fire fighting system also required.', null, null, 'selftest');
  ms := round(extract(milliseconds from clock_timestamp()-t0)::numeric,1);
  select string_agg(trade_key,',' order by trade_key) into t
    from public.inquiry_workstream where group_id = g1 and active;
  select status into t2 from public.inquiry_trade_candidate where group_id = g1 and trade_key = 'fire';
  test_no := 5; name := 'fire mentioned explicitly adds Fire';
  passed := (t2 = 'confirmed' and t like '%fire%'
             and not exists (select 1 from public.inquiry_trade_candidate where group_id=g1 and trade_key='elv'));
  detail := format('fire candidate status = %s; active workstreams now [%s]; ELV still absent', t2, t);
  return next;

  insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g5;
  perform public.fn_trade_identify(g5, 'Electrical works for a retail unit.', null, null, 'selftest');
  t0 := clock_timestamp();
  r := public.fn_trade_identify(g5, null, null,
        jsonb_build_array(jsonb_build_object('document_id','DRW-ELV-01','approved',true,
          'text','CCTV and access control layout with structured cabling risers.')), 'extractor');
  ms := round(extract(milliseconds from clock_timestamp()-t0)::numeric,1);
  select status, requires_confirmation, workstream_id into t, b, n
    from public.inquiry_trade_candidate where group_id = g5 and trade_key = 'elv';
  select count(*) into n2 from public.inquiry_workstream where group_id = g5 and trade_key = 'elv';
  test_no := 6; name := 'a trade detected only in a drawing stays proposed until confirmed';
  passed := (t = 'proposed' and b and n is null and n2 = 0);
  detail := format('elv status = %s, requires_confirmation = %s, workstream rows = %s. A document proposes; it never activates.', t, b, n2);
  return next;

  select active_workstreams into n2 from public.v_group_dispatch where group_id = g5;
  r := public.fn_trade_reject(g5, 'elv', 'ops:zaino', 'Customer confirmed the CCTV scope is by others.');
  select count(*) into n from public.inquiry_workstream_requirement req
    join public.inquiry_workstream w on w.id = req.workstream_id
   where w.group_id = g5 and req.field_id like 'elv.%';
  test_no := 7; name := 'a rejected document-detected trade does not affect completeness';
  passed := ((r->>'ok')::boolean and n = 0
             and (select active_workstreams from public.v_group_dispatch where group_id = g5) = n2
             and exists (select 1 from public.inquiry_trade_candidate
                          where group_id=g5 and trade_key='elv' and status='rejected'
                            and rejection_reason is not null));
  detail := format('elv requirements after rejection = %s; active workstreams unchanged at %s; rejection carries a person and a reason', n, n2);
  ms := null; return next;

  select count(*) into n from public.inquiry_workstream_requirement req
    join public.inquiry_workstream w on w.id = req.workstream_id where w.group_id = g5;
  t0 := clock_timestamp();
  r := public.fn_trade_confirm(g5, 'elv', 'ops:zaino', 'Customer reinstated the CCTV package.');
  ms := round(extract(milliseconds from clock_timestamp()-t0)::numeric,1);
  select count(*) into n2 from public.inquiry_workstream_requirement req
    join public.inquiry_workstream w on w.id = req.workstream_id where w.group_id = g5;
  test_no := 8; name := 'adding a trade recalculates requirements immediately';
  passed := ((r->>'ok')::boolean and n2 > n and (r->>'requirements')::integer > 0
             and exists (select 1 from public.v_workstream_dispatch
                          where group_id = g5 and trade_key = 'elv' and active));
  detail := format('group requirements %s -> %s in the same call; elv materialised %s of its own', n, n2, r->>'requirements');
  return next;

  select id into we from public.inquiry_workstream where group_id = g5 and trade_key = 'elv';
  perform public.fn_p2c1_fixture_satisfy(g5, we);
  select count(*) into n from public.inquiry_answer a
   where a.group_id = g5 and exists (select 1 from public.inquiry_answer_scope s
                                      where s.answer_id = a.id and s.workstream_id = we);
  r := public.fn_trade_remove(g5, 'elv', 'ops:zaino', 'Descoped by the customer.');
  select count(*) into n2 from public.inquiry_answer a
   where a.group_id = g5 and exists (select 1 from public.inquiry_answer_scope s
                                      where s.answer_id = a.id and s.workstream_id = we);
  test_no := 9; name := 'removing a trade drops the dispatch dependency without deleting history';
  passed := (n2 = n and n > 0
             and not exists (select 1 from public.v_workstream_dispatch
                              where group_id=g5 and trade_key='elv' and active)
             and (select status from public.inquiry_trade_candidate where group_id=g5 and trade_key='elv') = 'inactive'
             and exists (select 1 from public.inquiry_trade_candidate_evidence e
                          join public.inquiry_trade_candidate c on c.id=e.candidate_id
                         where c.group_id=g5 and c.trade_key='elv'));
  detail := format('elv answers %s -> %s across removal; candidate now inactive; evidence rows still present', n, n2);
  ms := null; return next;

  select id into we from public.inquiry_workstream where group_id = g1 and trade_key = 'electrical';
  select id into wf from public.inquiry_workstream where group_id = g1 and trade_key = 'fire';
  select field_id into f_em from public.inquiry_workstream_requirement
   where workstream_id = we and field_id like 'electrical.%emergency%' order by field_id limit 1;
  perform public.fn_inquiry_answer_set(g1, f_em, '3 hours maintained', 'customer_confirmed',
            'customer', 'selftest', null, array[we]);
  select count(*) into n from public.inquiry_workstream_requirement
   where workstream_id = wf and field_id like 'electrical.%';
  select via, satisfies_mandatory into t, b
    from public.v_workstream_answer where workstream_id = wf and field_id = f_em;
  select count(*) into n2 from public.inquiry_answer
   where group_id = g1 and field_id = f_em and superseded_by is null;
  test_no := 10; name := 'emergency lighting is stored once under Electrical and referenced by Life Safety';
  passed := (n = 0 and t = 'referenced' and b is false and n2 = 1
             and not exists (select 1 from public.inquiry_workstream_requirement req
                              where req.workstream_id = wf
                                and req.field_id in (select field_id from public.field_definition_reference
                                                      where referencing_trade_key='fire')));
  detail := format('%s = 1 stored row; fire owns %s electrical requirements; fire sees it via=%s, satisfies_mandatory=%s', f_em, n, t, b);
  ms := null; return next;

  perform public.fn_inquiry_answer_set(g1, 'shared.brand_acceptance_policy',
            'named_brand_or_approved_equal', 'customer_confirmed', 'customer', 'selftest');
  select count(*) into n from public.v_workstream_brand_policy
   where group_id = g1 and active and effective_policy = 'named_brand_or_approved_equal'
     and effective_source = 'shared_default';
  perform public.fn_inquiry_answer_set(g1, 'electrical.brand_acceptance_policy_override',
            'named_brand_only', 'customer_confirmed', 'customer', 'selftest', null, array[we]);
  select effective_policy, effective_source into t, t2 from public.v_workstream_brand_policy
   where workstream_id = we;
  select count(*) into n2 from public.v_workstream_brand_policy
   where group_id = g1 and active and workstream_id <> we
     and effective_policy = 'named_brand_or_approved_equal' and effective_source = 'shared_default';
  test_no := 11; name := 'shared brand policy is inherited unless a trade override exists';
  passed := (n >= 3 and t = 'named_brand_only' and t2 = 'trade_override' and n2 = n - 1
             and (select count(*) from public.field_question_variant
                   where field_id='shared.brand_acceptance_policy') >= 2);
  detail := format('%s workstreams inherited the shared default; electrical overrode to %s (%s); the other %s still inherit; original corpus wordings preserved as variants', n, t, t2, n2);
  ms := null; return next;

  insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g6;
  perform public.fn_trade_identify(g6, null, null,
        jsonb_build_array(jsonb_build_object('document_id','DRW-X','approved',true,
          'text','Chilled water pipework and CCTV cameras.')), 'extractor');
  rep := public.fn_group_dispatch_report(g6);
  select count(*) into n from public.inquiry_trade_candidate where group_id = g6 and status = 'proposed';
  test_no := 12; name := 'unconfirmed trade evidence cannot make an inquiry dispatchable';
  passed := (not (rep->>'overall_dispatch_eligible')::boolean
             and (rep->>'active_workstreams')::integer = 0
             and rep::text like '%no_active_workstream%' and n > 0);
  detail := format('%s proposed candidate(s), 0 active workstreams, overall_dispatch_eligible=%s, blockers=%s',
                   n, rep->>'overall_dispatch_eligible', rep->>'blocker_count');
  ms := null; return next;

  select count(*) into n from public.v_inquiry_workstream_identity where shape = 'multi_workstream';
  select count(*) into n2 from public.v_inquiry_workstream_identity
   where shape = 'implicit_single_workstream' and effective_workstreams = 1;
  test_no := 13; name := 'existing single-route inquiries remain unaffected';
  passed := (n = 0 and n2 = (select count(*) from public.inquiry_intake));
  detail := format('%s of %s existing inquiries report an implicit single workstream; %s were given a group by Stage B',
                   n2, (select count(*) from public.inquiry_intake), n);
  ms := null; return next;

  select count(*) into n from public.kb_operational_route
   where coalesce(regulatory_coverage_status,'requires_review') <> 'requires_review';
  select count(*) into intake_after from public.inquiry_intake;
  select count(*) into n2 from public.v_scenario_expectation_drift;
  test_no := 14; name := 'no route is activated and no customer-visible behaviour changes';
  passed := (n = 0 and intake_after = intake_before and n2 = 0);
  detail := format('routes off requires_review = %s (of 86); inquiry_intake rows %s -> %s; unledgered expectation drift = %s',
                   n, intake_before, intake_after, n2);
  ms := null; return next;

  groups := array[g1,g2,g3,g4,g5,g6];
  perform set_config('quotesdone.p2c1_teardown','approved',true);
  delete from public.inquiry_state_audit where group_id = any(groups);
  delete from public.inquiry_workstream_group where id = any(groups);
  perform set_config('quotesdone.p2c1_teardown','',true);
end $fn$;

-- Two regressions. Both bugs were silent: the first made an explicit "passed" gate read as
-- never-evaluated, the second quietly dropped the "full MEP package" half of a sentence.
create or replace function public.fn_p2c1_stage_b_regression()
returns table(test_no integer, name text, passed boolean, detail text)
language plpgsql security definer set search_path to 'public' as $fn$
declare g bigint; t text; v_state text; v_passed boolean; ws bigint;
begin
  insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g;

  perform public.fn_trade_identify(g,
        'Full MEP package for a warehouse; fire fighting also required.', null, null, 'regression');
  select string_agg(w.trade_key, ',' order by w.trade_key) into t
    from public.inquiry_workstream w where w.group_id = g and w.active;
  test_no := 15;
  name := 'an explicitly named trade adds to "full MEP", it does not replace it';
  passed := (t = 'electrical,fire,hvac,plumbing');
  detail := format('active workstreams = [%s]; the umbrella scope rule and the named trade both applied, and ELV is still absent', t);
  return next;

  select w.id into ws from public.inquiry_workstream w where w.group_id = g and w.trade_key = 'hvac';
  insert into public.inquiry_gate (group_id, workstream_id, gate_key, passed, asserted_by)
  values (g, ws, 'validations', true, 'regression');
  select ig.state::text, ig.passed into v_state, v_passed
    from public.inquiry_gate ig where ig.workstream_id = ws and ig.gate_key = 'validations';
  test_no := 16;
  name := 'a gate asserted as passed lands as passed, not as not_evaluated';
  passed := (v_state = 'passed' and v_passed);
  detail := format('inserted passed=true -> state=%s, passed=%s', v_state, v_passed);
  return next;

  perform set_config('quotesdone.p2c1_teardown','approved',true);
  delete from public.inquiry_state_audit where group_id = g;
  delete from public.inquiry_workstream_group where id = g;
  perform set_config('quotesdone.p2c1_teardown','',true);
end $fn$;

revoke all on function public.fn_p2c1_stage_b_selftest() from public, anon, authenticated;
revoke all on function public.fn_p2c1_stage_b_regression() from public, anon, authenticated;
