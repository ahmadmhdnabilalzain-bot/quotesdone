-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802173318   name: p2_c1_stage_b_regression_tests
-- SHA-256 of the applied SQL: 826637edb0a90a0e81b68115e82ed54362892a186b2da9c0c65c8757139fc9b9
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- Two regressions, one per bug found while re-running Stage A against Stage B. Both bugs were
-- silent - the first made an explicit "passed" gate read as never-evaluated, the second quietly
-- dropped the "full MEP package" half of a sentence. Silent bugs earn permanent tests.

create or replace function public.fn_p2c1_stage_b_regression()
returns table(test_no integer, name text, passed boolean, detail text)
language plpgsql security definer set search_path to 'public' as $fn$
declare g bigint; r jsonb; t text; st text; pa boolean; ws bigint;
begin
  insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g;

  -- 15: naming an extra trade must ADD to the core set, not replace it
  r := public.fn_trade_identify(g,
        'Full MEP package for a warehouse; fire fighting also required.', null, null, 'regression');
  select string_agg(trade_key, ',' order by trade_key) into t
    from public.inquiry_workstream where group_id = g and active;
  test_no := 15;
  name := 'an explicitly named trade adds to "full MEP", it does not replace it';
  passed := (t = 'electrical,fire,hvac,plumbing');
  detail := format('active workstreams = [%s]; the umbrella scope rule and the named trade both applied, and ELV is still absent', t);
  return next;

  -- 16: a gate written the older way (passed only) must not land as not_evaluated
  select id into ws from public.inquiry_workstream where group_id = g and trade_key = 'hvac';
  insert into public.inquiry_gate (group_id, workstream_id, gate_key, passed, asserted_by)
  values (g, ws, 'validations', true, 'regression');
  select state::text, passed into st, pa from public.inquiry_gate
   where workstream_id = ws and gate_key = 'validations';
  test_no := 16;
  name := 'a gate asserted as passed lands as passed, not as not_evaluated';
  passed := (st = 'passed' and pa);
  detail := format('inserted passed=true -> state=%s, passed=%s', st, pa);
  return next;

  perform set_config('quotesdone.p2c1_teardown','approved',true);
  delete from public.inquiry_state_audit where group_id = g;
  delete from public.inquiry_workstream_group where id = g;
  perform set_config('quotesdone.p2c1_teardown','',true);
end $fn$;

revoke all on function public.fn_p2c1_stage_b_regression() from public, anon, authenticated;
;