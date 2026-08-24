-- P02. A DESTRUCTIVE SUPERSEDED RUNNER, AND A DENOMINATOR THAT WAS TYPED.
--
-- Two audit-safety findings from the final independent acceptance audit of 24 Aug 2026. Neither
-- failed a mandatory gate; both can corrupt another audit.
--
-- NO TRANSACTION CONTROL. This file carries no BEGIN and no COMMIT of its own: every transport in
-- this repository sends a file as ONE simple-query batch, which Postgres runs as one implicit
-- transaction, so the file is atomic AND it can be rehearsed inside `begin; … rollback;` without
-- committing. 67 of the 97 Phase D down scripts did not have that property until this session.
--
-- ================================================================================================
-- §8.C  fn_phase_d_run_step_cases() IS SUPERSEDED, STILL DEPLOYED, AND DESTRUCTIVE
-- ================================================================================================
-- Its first statement is `delete from public.phase_d_step_case_result;` and it then repopulates
-- from the pre-23-Aug contract-only matrix. Re-run at HEAD it returns passed 1542, failed 257 —
-- every one of the 257 `positive` cases fails at step_contract, because the input schemas now type
-- their object-valued keys and that matrix sends one string per key
-- ("schema_input_w01_s01: wrong types [current_approved_founder_policies expected object got
-- string; …]"). Anything that calls it wipes the authoritative 1,799-row table and replaces it with
-- 257 failures that are then indistinguishable from a genuine regression.
--
-- MEASURED 24 AUG 2026 — ACTIVE CALLERS: ZERO. No pg_proc but itself (prosrc ilike), none of the
-- 206 cron jobs, no policy (the table has none at all), no view, no rule, no column default, no
-- check constraint, nothing under supabase/functions/, no npm script, no .github/workflows, nothing
-- under scripts/checks/. The one thing that DID call it is audit/phase-d-final/g10_rerun.sql — the
-- audit that wiped the table.
--
-- WHY DISABLE IN PLACE RATHER THAN DROP. Three committed artifacts assert the routine is present
-- (docs/phase-c-final-kernel/CANONICAL_ROUTINE_MANIFEST.csv, the d10 down script, the deployment
-- ledger) and two repository files still tell a reader to run it — including
-- scripts/phase_d/build_step_case_result.mjs, whose ERROR MESSAGE prints "run
-- fn_phase_d_run_step_cases() first" at exactly the moment the table is short. A drop turns all of
-- that into 42883, which says nothing about why and names no replacement, and the next reader
-- re-derives the wipe from the builder's own instruction. A raising body carries the reason and the
-- replacement to whoever calls it. That instruction is corrected in the same change.
--
-- WHY NOT A COMPATIBILITY WRAPPER. Measured, not assumed: the authoritative runner
-- (scripts/phase_d/run_step_cases_live.mjs) drives one workflow per step through
-- fn_phase_d_drive_workflow with app.phase_d_hold_step set, releases the hold mid-transaction, and
-- ABORTS each of the 257 transactions. A SQL function runs inside its caller's transaction and
-- cannot abort-and-continue, so no wrapper can reach the replacement.
--
-- THE REVOKE ALONE WOULD NOT STOP IT, AND PUBLIC IS NOT THE HOLE. pg_proc.proacl is already
-- {postgres=X/postgres,service_role=X/postgres} — no bare `=X/` entry, so PUBLIC holds nothing and
-- has_function_privilege('public',…) is false. The management door this repository uses runs as
-- `postgres`, the function's OWNER, and an owner cannot be revoked out of EXECUTE on its own
-- function. The raise is the mechanism; the revoke keeps
-- fn_kernel_retired_grant_state.retired_paths_executable_by_an_ordinary_role at 0, which counts
-- service_role as an ordinary role.
--
-- NOT RETIRED, DELIBERATELY: public.fn_phase_d_step_cases(p_step_id text). It is a pure per-step
-- reader and public.fn_phase_d_run_injected_defects calls it for PD-STATE-005. Retiring it would
-- delete a live injected-defect case.

CREATE OR REPLACE FUNCTION public.fn_phase_d_run_step_cases()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  raise exception
    'fn_phase_d_run_step_cases is retired: it is the pre-23-Aug contract-only matrix and its first '
    'statement was `delete from public.phase_d_step_case_result`. Re-run at HEAD it replaces the '
    'authoritative 1,799 rows (1,542 decided_at live_step_run, 257 kernel_boundary, 0 failing) with '
    '257 positive failures, because every input schema now types its object-valued keys and this '
    'matrix sends one string per key. Run: node scripts/phase_d/run_step_cases_live.mjs'
    using errcode = '23514',
          hint = 'public.kernel_retired_path names the replacement for every retired path.';
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_run_step_cases()
  FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO public.kernel_retired_path (path_name, disposition, replacement, evidence)
VALUES ('fn_phase_d_run_step_cases', 'DISABLED',
        'scripts/phase_d/run_step_cases_live.mjs',
        'Measured 24 Aug 2026: ZERO active callers. No pg_proc but itself, none of the 206 cron '
        'jobs, no policy, view, rule, column default or check constraint, nothing under '
        'supabase/functions, no npm script, no .github/workflows, nothing under scripts/checks. Its '
        'first act was `delete from public.phase_d_step_case_result`; audit/phase-d-final/'
        'g10_rerun.sql called it and wiped the authoritative table, and '
        'scripts/phase_d/build_step_case_result.mjs printed an instruction to run it at exactly the '
        'moment the table was short. No compatibility wrapper is possible: the replacement is a '
        'Node driver that opens 257 ABORTED transactions and sets app.phase_d_hold_step per step, '
        'which no SQL function can do. fn_phase_d_step_cases(text) is deliberately NOT retired — '
        'fn_phase_d_run_injected_defects calls it for PD-STATE-005.')
ON CONFLICT (path_name) DO UPDATE
  SET disposition = excluded.disposition,
      replacement = excluded.replacement,
      evidence    = excluded.evidence,
      measured_at = now();

-- ================================================================================================
-- §8.D  THE DENOMINATOR WAS TYPED, AND TWO ROWS COULD NEVER REDDEN
-- ================================================================================================
-- THE BRIEF'S HEADLINE IS WRONG AND THE CORRECTION IS RECORDED HERE RATHER THAN ACTED ON SILENTLY.
-- "fn_phase_d_case_state() reads green on an empty table" was re-measured by emptying the table
-- inside an aborted transaction and reading the board. It returned:
--
--   per_step_cases_recorded             expected 1799   actual 0   ok = FALSE
--   steps_with_fewer_than_seven_cases   expected 0      actual 0   ok = true
--   cases_failing                       expected 0      actual 0   ok = true
--   negative_cases_with_no_refusal_code expected 0      actual 0   ok = true
--   cases_decided_at_the_step_contract  informational   actual 0   ok = true
--   cases_decided_at_a_shared_boundary  informational   actual 0   ok = true
--
-- One red, five green. The board ALREADY fails closed on an empty table, and fn_kernel_all_boards()
-- reads it as a GATE. Deleting one row reddens two more. A missing kind and a short population are
-- likewise already caught. A duplicate test row is IMPOSSIBLE — forced, not assumed: the insert
-- returned 23505 on phase_d_step_case_result_pkey (step_id, case_kind), and the table records no
-- run_id, attempt or generation column, so there is no other dimension to duplicate across. Given
-- the primary key plus the 7-value CHECK, a step with exactly 7 rows necessarily has all 7 kinds.
--
-- WHAT IS GENUINELY BROKEN, AND IS FIXED BELOW.
--
--   1. THE 7 IS A LITERAL, TYPED TWICE. The comment above it says "the denominator is derived,
--      never typed", and the step count is — but the required case-kind count is the literal 7,
--      while the authority is CHECK phase_d_step_case_result_kind_ck. An expectation typed into the
--      check it guards is the shape that put 15 count literals inside fn_phase_b_invariants.
--
--   2. THREE CHECKS ARE `not exists` OVER THE RESULT TABLE ITSELF, so an empty relation satisfies
--      each of them by having nothing to judge. Only per_step_cases_recorded reaches outside the
--      table, and it is the only reason the board is red on empty at all. The gap is now computed
--      against the frozen step registry CROSS JOIN the constraint's own kind list, so an empty
--      table reports 257 of 257 steps missing every kind rather than "no findings".
--
--   3. TWO ROWS CARRY `ok := true` AS A SQL LITERAL and cannot redden on any input. Worse, they
--      count step_contract / executor_boundary / structural_constraint — the vocabulary of the
--      SUPERSEDED contract-only runner. The live 1,799 are 1,542 live_step_run + 257
--      kernel_boundary, so those two rows read 0 and 257 today and assert nothing. The one
--      discriminator between the authoritative population and the superseded runner's output was
--      present in the table and unused. They are replaced by a row that reddens the INSTANT the
--      superseded runner writes, instead of waiting for its 257 failures to surface as a regression.
--
--   4. `and (select n from want) > 0` fails closed if the CHECK constraint is ever dropped. 0 = 0
--      must not read green: zero cannot tell a dead guard from an idle system.
--
-- SHAPE IS LOAD-BEARING. fn_kernel_all_boards() discovers boards by
-- `pronargs = 0 and proargnames @> array['check_name','expected','actual','ok']`. The signature,
-- the OUT parameter names and the argument count are unchanged; only the body moves.

CREATE OR REPLACE FUNCTION public.fn_phase_d_case_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with
    -- NEITHER FACTOR OF THE DENOMINATOR IS TYPED. The step count comes from the frozen registry
    -- and the required case kinds come from THE CHECK CONSTRAINT THAT ENFORCES THEM, so a 7 that
    -- moves moves here too.
    kinds as (
      select count(*)::bigint n, array_agg(m[1] order by m[1]) list
        from pg_constraint c,
             lateral regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''::text', 'g') m
       where c.conrelid = 'public.phase_d_step_case_result'::regclass
         and c.conname  = 'phase_d_step_case_result_kind_ck'),
    steps as (select count(*)::bigint n from public.phase_b_workflow_step),
    want  as (select (select n from steps) * coalesce((select n from kinds), 0) n),
    res   as (select count(*)::bigint n from public.phase_d_step_case_result),
    -- REACHES OUTSIDE THE RESULT TABLE. An empty table leaves 257 x 7 gaps, not zero findings.
    gap   as (select s.step_id, k.kind
                from public.phase_b_workflow_step s
                cross join lateral unnest(coalesce((select list from kinds), '{}'::text[])) k(kind)
               where not exists (select 1 from public.phase_d_step_case_result r
                                  where r.step_id = s.step_id and r.case_kind = k.kind)),
    wrong as (select r.step_id from public.phase_d_step_case_result r
               group by r.step_id having count(*) <> coalesce((select n from kinds), 0))
  select 'per_step_cases_recorded', (select n::text from want), (select n::text from res),
         (select n from res) = (select n from want) and (select n from want) > 0
  union all
  select 'steps_missing_a_required_case_kind', '0',
         (select count(distinct step_id)::text from gap) || ' of ' || (select n::text from steps),
         not exists (select 1 from gap)
  union all
  select 'steps_with_the_wrong_number_of_cases', '0',
         (select count(*)::text from wrong), not exists (select 1 from wrong)
  union all
  select 'cases_failing', '0',
         (select count(*)::text from public.phase_d_step_case_result where not passed)
           || ' of ' || (select n::text from res),
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
  -- REPLACES THE TWO `ok := true` INFORMATIONAL ROWS. The authoritative runner decides six kinds
  -- against a live step run and malformed_output at the kernel boundary. Any other level in this
  -- table is the superseded contract-only matrix's vocabulary, so this row goes red the instant
  -- that runner writes — before its 257 positive failures can be mistaken for a regression.
  select 'cases_not_decided_against_a_live_step_run', '0',
         (select count(*)::text from public.phase_d_step_case_result
           where decided_at not in ('live_step_run','kernel_boundary'))
           || ' of ' || (select n::text from res)
           || ' (live_step_run '
           || (select count(*)::text from public.phase_d_step_case_result where decided_at = 'live_step_run')
           || ', kernel_boundary '
           || (select count(*)::text from public.phase_d_step_case_result where decided_at = 'kernel_boundary')
           || ')',
         not exists (select 1 from public.phase_d_step_case_result
                      where decided_at not in ('live_step_run','kernel_boundary'));
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_case_state() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_case_state() TO service_role;
