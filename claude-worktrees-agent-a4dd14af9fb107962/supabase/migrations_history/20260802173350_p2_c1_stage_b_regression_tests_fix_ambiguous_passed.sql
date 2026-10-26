-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802173350   name: p2_c1_stage_b_regression_tests_fix_ambiguous_passed
-- SHA-256 of the applied SQL: b781c507ab9edbed3a477cf7c6cde3f501f0cdc60a06743fcad00f4a92dbf3ab
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

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

revoke all on function public.fn_p2c1_stage_b_regression() from public, anon, authenticated;
;