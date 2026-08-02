-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802170233   name: p2_c1_stage_a_selftest_fix_corroboration_case
-- SHA-256 of the applied SQL: 5c76d211889bda2f3f7647ffeecc84e025adb84c656a8a599c0ec24fd5235031
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- Test 9 compared against the value test 1 had written, but the fixture pass had since superseded
-- the shared field with its own value. So the "agreeing" document actually disagreed, a SHARED
-- conflict opened, and - correctly - that blocked every workstream in the group, which is what
-- then failed tests 11 and 12. The model behaved exactly as designed; the test was wrong.
-- Test 9 now reads the live canonical value and corroborates a case/whitespace variant of THAT.

create or replace function public.fn_p2c1_stage_a_selftest()
returns table(test_no integer, name text, passed boolean, detail text)
language plpgsql security definer set search_path to 'public' as $fn$
declare
  g bigint; wh bigint; we bigint; wp bigint; wf bigint; wv bigint;
  r jsonb; n integer; n2 integer; b boolean; b2 boolean; t text;
  f_hvac text; f_elec text; f_shared text := 'shared.project_emirate';
  live_id bigint; inq uuid := gen_random_uuid(); err text;
begin
  insert into public.inquiry_workstream_group (inquiry_id) values (inq) returning id into g;
  wh := (public.fn_inquiry_workstream_activate(g,'hvac','selftest')->>'workstream_id')::bigint;
  we := (public.fn_inquiry_workstream_activate(g,'electrical','selftest')->>'workstream_id')::bigint;
  wp := (public.fn_inquiry_workstream_activate(g,'plumbing','selftest')->>'workstream_id')::bigint;
  wf := (public.fn_inquiry_workstream_activate(g,'fire','selftest')->>'workstream_id')::bigint;
  wv := (public.fn_inquiry_workstream_activate(g,'elv','selftest')->>'workstream_id')::bigint;

  select r2.field_id into f_hvac from public.inquiry_workstream_requirement r2
   where r2.workstream_id = wh and r2.mandatory and r2.field_id like 'hvac.%' order by 1 limit 1;
  select r2.field_id into f_elec from public.inquiry_workstream_requirement r2
   where r2.workstream_id = we and r2.mandatory and r2.field_id like 'electrical.%' order by 1 limit 1;

  perform public.fn_inquiry_answer_set(g, f_shared, 'Dubai', 'customer_confirmed','customer','selftest');
  select count(*) into n from public.v_workstream_answer
   where group_id = g and field_id = f_shared and value = 'Dubai';
  select count(distinct answer_id) into n2 from public.v_workstream_answer
   where group_id = g and field_id = f_shared;
  perform public.fn_inquiry_answer_set(g, f_shared, 'Sharjah','customer_confirmed','customer','selftest');
  select count(*) into live_id from public.v_workstream_answer
   where group_id = g and field_id = f_shared and value = 'Sharjah';
  test_no := 1; name := 'one shared answer updates five workstream views';
  passed := (n = 5 and n2 = 1 and live_id = 5);
  detail := format('5 workstreams saw the first value from %s answer row(s); after one update %s of 5 see the new value, with no propagation step', n2, live_id);
  return next;

  r := public.fn_inquiry_answer_set(g, f_hvac, 'x','customer_confirmed','customer','selftest', null, array[we]);
  test_no := 2; name := 'a trade-specific answer cannot satisfy another trade';
  passed := (not (r->>'ok')::boolean and r->>'error' = 'trade_mismatch');
  detail := format('setting %s on the electrical workstream returned %s', f_hvac, coalesce(r->>'error','ACCEPTED - WRONG'));
  return next;

  perform public.fn_p2c1_fixture_satisfy(g, wh);
  perform public.fn_p2c1_fixture_satisfy(g, we);
  perform public.fn_p2c1_fixture_satisfy(g, wp);
  perform public.fn_p2c1_fixture_satisfy(g, wf);
  perform public.fn_p2c1_fixture_satisfy(g, wv);
  insert into public.inquiry_gate (group_id, workstream_id, gate_key, passed, asserted_by)
  select g, null, gr.gate_key, true, 'selftest'
    from public.inquiry_gate_required gr where gr.level = 'group' on conflict do nothing;

  select dispatch_eligible into b from public.v_workstream_dispatch where workstream_id = wh;
  perform set_config('quotesdone.p2c1_teardown','approved',true);
  delete from public.inquiry_answer a
   where a.group_id = g and a.field_id = f_hvac and a.superseded_by is null;
  perform set_config('quotesdone.p2c1_teardown','',true);
  select dispatch_eligible, cardinality(missing_mandatory) into b2, n
    from public.v_workstream_dispatch where workstream_id = wh;
  test_no := 5; name := 'a missing mandatory field blocks trade dispatch';
  passed := (b and not b2 and n = 1);
  detail := format('hvac was eligible=%s with everything answered; removing one mandatory field left %s missing and eligible=%s', b, n, b2);
  return next;

  select overall_dispatch_eligible, array_to_string(blocking_trades,',') into b, t
    from public.v_group_dispatch where group_id = g;
  test_no := 6; name := 'one blocked trade keeps overall dispatch false';
  passed := (not b and t = 'hvac');
  detail := format('four trades complete, hvac blocked -> overall_dispatch_eligible=%s, blocking_trades=[%s]', b, t);
  return next;

  perform public.fn_inquiry_answer_set(g, f_hvac, 'fixture-value','customer_confirmed','customer','selftest', null, array[wh]);
  select overall_dispatch_eligible into b from public.v_group_dispatch where group_id = g;
  test_no := 8; name := 'restoring the missing answer makes the whole group dispatch-eligible again';
  passed := b;
  detail := format('overall_dispatch_eligible=%s once hvac is complete again', b);
  return next;

  r := public.fn_inquiry_answer_set(g, f_elec, '12 units','document_extracted','document','extractor',
        null, array[we], jsonb_build_object('document_id','DRW-001','page_or_sheet','E-201'));
  select dispatch_eligible, cardinality(blocked_by) into b, n
    from public.v_workstream_dispatch where workstream_id = we;
  select overall_dispatch_eligible into b2 from public.v_group_dispatch where group_id = g;
  test_no := 3; name := 'document conflicts block dispatch';
  passed := (r->>'action' = 'conflict_opened' and not b and n = 1 and not b2);
  detail := format('drawing disagreed with the customer -> action=%s, electrical blocked_by=%s, electrical eligible=%s, overall=%s',
                   r->>'action', n, b, b2);
  return next;

  select value into t from public.inquiry_answer
   where group_id = g and field_id = f_elec and superseded_by is null;
  test_no := 10; name := 'a lower-precedence value never overwrites the canonical answer';
  passed := (t = 'fixture-value');
  detail := format('canonical value is still %L after a document proposed %L', t, '12 units');
  return next;

  select count(*) into n from public.inquiry_answer_conflict_value cv
    join public.inquiry_answer_conflict c on c.id = cv.conflict_id
   where c.group_id = g and c.field_id = f_elec;
  r := public.fn_inquiry_answer_confirm(g, f_elec, '12 units', 'customer:zaino',
        'Customer checked the drawing and agrees with 12 units.', array[we]);
  select count(*) into n2 from public.inquiry_answer_conflict_value cv
    join public.inquiry_answer_conflict c on c.id = cv.conflict_id
   where c.group_id = g and c.field_id = f_elec;
  select dispatch_eligible into b from public.v_workstream_dispatch where workstream_id = we;
  select value into t from public.inquiry_answer
   where group_id = g and field_id = f_elec and superseded_by is null;
  test_no := 4; name := 'customer confirmation resolves conflict without deleting evidence';
  passed := ((r->>'ok')::boolean and n2 >= n and n2 >= 3 and b and t = '12 units'
             and exists (select 1 from public.inquiry_answer_conflict c
                          where c.group_id = g and c.field_id = f_elec
                            and c.resolved_at is not null and c.resolution_reason is not null));
  detail := format('evidence values before=%s after=%s (never fewer); canonical now %L; electrical eligible=%s; resolution carries a person and a reason', n, n2, t, b);
  return next;

  select count(*) into n from public.inquiry_answer
   where group_id = g and field_id = f_shared and superseded_by is null;
  select count(*) into n2 from public.inquiry_answer_scope s
    join public.inquiry_answer a on a.id = s.answer_id
   where a.group_id = g and a.field_id = f_shared;
  test_no := 7; name := 'a shared answer is stored once and never copied per workstream';
  passed := (n = 1 and n2 = 0);
  detail := format('%s live row for the shared field, %s per-workstream scope rows (a copy design would show 5)', n, n2);
  return next;

  -- corroborate a case/whitespace variant of whatever the LIVE canonical value currently is
  select value into t from public.inquiry_answer
   where group_id = g and field_id = f_shared and superseded_by is null;
  select count(*) into n from public.inquiry_answer_conflict where group_id = g and resolved_at is null;
  r := public.fn_inquiry_answer_set(g, f_shared, '  ' || upper(t) || '  ','document_extracted','document',
        'extractor', null, null, jsonb_build_object('document_id','DRW-002'));
  select count(*) into n2 from public.inquiry_answer_conflict where group_id = g and resolved_at is null;
  test_no := 9; name := 'an agreeing lower-precedence source corroborates rather than conflicts';
  passed := (r->>'action' = 'corroborated' and n2 = n
             and exists (select 1 from public.inquiry_answer_corroboration co
                          join public.inquiry_answer a on a.id = co.answer_id
                         where a.group_id = g and a.field_id = f_shared));
  detail := format('%L vs %L normalised equal -> action=%s, open conflicts %s -> %s',
                   '  ' || upper(t) || '  ', t, r->>'action', n, n2);
  return next;

  perform set_config('quotesdone.p2c1_teardown','approved',true);
  delete from public.inquiry_answer a where a.group_id = g and a.field_id = f_hvac;
  perform set_config('quotesdone.p2c1_teardown','',true);
  perform public.fn_inquiry_answer_set(g, f_hvac, 'guessed','model_inference','model','router', null, array[wh]);
  select dispatch_eligible into b from public.v_workstream_dispatch where workstream_id = wh;
  r := public.fn_inquiry_answer_confirm(g, f_hvac, 'guessed','customer:zaino','Customer confirmed the inference.', array[wh]);
  select dispatch_eligible into b2 from public.v_workstream_dispatch where workstream_id = wh;
  test_no := 11; name := 'model inference proposes but cannot satisfy a mandatory field alone';
  passed := (not b and b2);
  detail := format('with only a model inference eligible=%s; after customer confirmation eligible=%s', b, b2);
  return next;

  select count(*) into n from public.inquiry_answer a
   where a.group_id = g and exists (select 1 from public.inquiry_answer_scope s
                                     where s.answer_id = a.id and s.workstream_id = wv);
  perform set_config('quotesdone.p2c1_teardown','approved',true);
  delete from public.inquiry_answer a
   where a.group_id = g and a.superseded_by is null
     and a.field_id in (select r2.field_id from public.inquiry_workstream_requirement r2
                         where r2.workstream_id = wv and r2.mandatory and r2.field_id like 'elv.%' limit 1);
  perform set_config('quotesdone.p2c1_teardown','',true);
  select overall_dispatch_eligible into b from public.v_group_dispatch where group_id = g;
  perform public.fn_inquiry_workstream_deactivate(g,'elv','selftest');
  select overall_dispatch_eligible into b2 from public.v_group_dispatch where group_id = g;
  select count(*) into n2 from public.inquiry_answer a
   where a.group_id = g and exists (select 1 from public.inquiry_answer_scope s
                                     where s.answer_id = a.id and s.workstream_id = wv);
  test_no := 12; name := 'deactivating a trade leaves the roll-up, not the data';
  passed := (not b and b2 and n2 >= n and n2 > 0);
  detail := format('incomplete elv held the group at %s; deactivating it gave %s, and its %s answers are still there', b, b2, n2);
  return next;

  select count(*) into n from public.inquiry_workstream_requirement where workstream_id = wv;
  r := public.fn_inquiry_workstream_activate(g,'elv','selftest');
  select count(*) into n2 from public.inquiry_workstream_requirement where workstream_id = wv;
  select count(*) into live_id from public.inquiry_workstream where group_id = g and trade_key = 'elv';
  test_no := 13; name := 'reactivation flips the flag and duplicates nothing';
  passed := ((r->>'reactivated')::boolean and n2 = n and live_id = 1);
  detail := format('reactivated=%s, requirements %s -> %s, workstream rows for elv = %s', r->>'reactivated', n, n2, live_id);
  return next;

  err := '';
  begin
    update public.inquiry_state_audit set event = 'tampered' where group_id = g;
    err := err || 'audit-update-ALLOWED ';
  exception when others then err := err || 'audit-update-refused '; end;
  begin
    delete from public.inquiry_answer_conflict_value cv using public.inquiry_answer_conflict c
     where c.id = cv.conflict_id and c.group_id = g;
    err := err || 'evidence-delete-ALLOWED';
  exception when others then err := err || 'evidence-delete-refused'; end;
  select count(*) into n from public.inquiry_state_audit where group_id = g;
  test_no := 14; name := 'audit and evidence are append-only';
  passed := (err = 'audit-update-refused evidence-delete-refused' and n > 0);
  detail := format('%s; %s audit rows recorded for this group', err, n);
  return next;

  perform set_config('quotesdone.p2c1_teardown','approved',true);
  delete from public.inquiry_state_audit where group_id = g;
  delete from public.inquiry_workstream_group where id = g;
  perform set_config('quotesdone.p2c1_teardown','',true);
end $fn$;

revoke all on function public.fn_p2c1_stage_a_selftest() from public, anon, authenticated;
;