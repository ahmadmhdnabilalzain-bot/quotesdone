-- P02 — A DESTRUCTIVE RUNNER AND A DENOMINATOR THAT WAS TYPED — ROLLBACK.
--
-- TRANSACTION_NEUTRAL. No BEGIN, no COMMIT, no ROLLBACK.
--
-- The two routine bodies below were read out of production with pg_get_functiondef immediately
-- before P02 was written; their sha256 digests and their live ACLs are recorded beside them.
--
--   fn_phase_d_run_step_cases()         993c1628f51e640d32bff2b4850a91ffb24b0fac7d1bc62f42987cf0dda337dd   acl {postgres=X/postgres,service_role=X/postgres}
--   fn_phase_d_case_state()             f08efceab13d67969db83da158300784816384ed304525e2c94e1af859edb05a   acl {postgres=X/postgres,service_role=X/postgres}
--
-- WHAT THIS ROLLBACK COSTS, STATED PLAINLY. It puts back a routine whose FIRST STATEMENT is
--  and which repopulates the authoritative 1,799-row
-- table from the superseded contract-only matrix as 1,542 passes and 257 failures. It also puts
-- back a board whose denominator types the 7 and whose last two rows carry ok := true and cannot
-- redden. Do not run it to tidy a red board.

-- ---- 1. THE TWO ROUTINE BODIES, RESTORED VERBATIM --------------------------------------------

-- fn_phase_d_run_step_cases()  sha256 993c1628f51e640d32bff2b4850a91ffb24b0fac7d1bc62f42987cf0dda337dd
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
end $function$;

-- fn_phase_d_case_state()  sha256 f08efceab13d67969db83da158300784816384ed304525e2c94e1af859edb05a
CREATE OR REPLACE FUNCTION public.fn_phase_d_case_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with steps as (select count(*) n from public.phase_b_workflow_step),
       res   as (select count(*) n from public.phase_d_step_case_result)
  -- The denominator is derived, never typed: if the frozen step count moves, this reports it.
  select 'per_step_cases_recorded', ((select n from steps) * 7)::text,
         (select n::text from res), (select n from res) = (select n from steps) * 7
  union all
  select 'steps_with_fewer_than_seven_cases', '0',
         (select count(*)::text from (
            select step_id from public.phase_d_step_case_result
             group by step_id having count(*) <> 7) x),
         not exists (select 1 from (
            select step_id from public.phase_d_step_case_result
             group by step_id having count(*) <> 7) x)
  union all
  select 'cases_failing', '0',
         (select count(*)::text from public.phase_d_step_case_result where not passed),
         not exists (select 1 from public.phase_d_step_case_result where not passed)
  union all
  -- A negative case that reports no machine code is a prose assertion.
  select 'negative_cases_with_no_refusal_code', '0',
         (select count(*)::text from public.phase_d_step_case_result
           where case_kind <> 'positive' and passed and coalesce(refused_with,'') in ('','(none)')),
         not exists (select 1 from public.phase_d_step_case_result
                      where case_kind <> 'positive' and passed
                        and coalesce(refused_with,'') in ('','(none)'))
  union all
  select 'cases_decided_at_the_step_contract', 'informational',
         (select count(*)::text from public.phase_d_step_case_result
           where decided_at = 'step_contract'), true
  union all
  select 'cases_decided_at_a_shared_boundary', 'informational',
         (select count(*)::text from public.phase_d_step_case_result
           where decided_at in ('executor_boundary','kernel_boundary','structural_constraint')), true;
$function$;

-- ---- 2. THE GRANTS THE RESTORED BODIES CARRIED ------------------------------------------------
-- CREATE OR REPLACE preserves the ACL, so the revoke P02 issued must be undone explicitly.
GRANT EXECUTE ON FUNCTION public.fn_phase_d_run_step_cases() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_case_state() TO service_role;

-- ---- 3. THE RETIREMENT REGISTER ---------------------------------------------------------------
DELETE FROM public.kernel_retired_path WHERE path_name = 'fn_phase_d_run_step_cases';
