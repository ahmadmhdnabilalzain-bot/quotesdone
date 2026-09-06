CREATE OR REPLACE FUNCTION public.fn_phase_d_run_step_cases()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  st record; c record;
  v_steps int := 0; v_cases int := 0; v_passed int := 0;
  v_eff_before bigint; v_eff_after bigint; v_run_before bigint; v_run_after bigint;
begin
  -- NO CASE MAY WRITE. Counted around the whole matrix rather than promised in a comment.
  select count(*) into v_eff_before from public.phase_d_effect_ledger;
  select count(*) into v_run_before from public.phase_c_workflow_step_run;

  delete from public.phase_d_step_case_result;

  for st in select step_id from public.phase_b_workflow_step order by step_id loop
    v_steps := v_steps + 1;
    for c in select * from public.fn_phase_d_step_cases(st.step_id) loop
      insert into public.phase_d_step_case_result
        (step_id, case_kind, decided_at, expectation, passed, refused_with, detail)
      values (st.step_id, c.case_kind, c.decided_at, c.expectation, c.passed,
              c.refused_with, left(c.detail, 400))
      on conflict (step_id, case_kind) do update
        set decided_at = excluded.decided_at, expectation = excluded.expectation,
            passed = excluded.passed, refused_with = excluded.refused_with,
            detail = excluded.detail, run_at = now();
      v_cases := v_cases + 1;
      if c.passed then v_passed := v_passed + 1; end if;
    end loop;
  end loop;

  select count(*) into v_eff_after from public.phase_d_effect_ledger;
  select count(*) into v_run_after from public.phase_c_workflow_step_run;
  if v_eff_after <> v_eff_before or v_run_after <> v_run_before then
    raise exception 'fn_phase_d_run_step_cases: the matrix produced % effect(s) and % step run(s). A contract test may not write. (pd_case_matrix_had_a_side_effect)',
      v_eff_after - v_eff_before, v_run_after - v_run_before using errcode = '23514';
  end if;

  return jsonb_build_object(
    'ok', v_cases = v_steps * 7,
    'steps', v_steps, 'cases', v_cases, 'expected_cases', v_steps * 7,
    'passed', v_passed, 'failed', v_cases - v_passed,
    'effects_written', v_eff_after - v_eff_before,
    'step_runs_written', v_run_after - v_run_before);
end $function$
