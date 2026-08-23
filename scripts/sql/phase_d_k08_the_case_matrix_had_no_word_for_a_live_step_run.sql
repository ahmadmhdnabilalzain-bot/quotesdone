-- K08 — the case matrix had no word for the level the founder asked it to reach
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. public.phase_d_step_case_result holds the 1,799
-- step-contract cases, and its `decided_at` column is the honesty column: it records WHERE the
-- guard that settled each case actually lives, so a contract-level refusal can never be read as a
-- driven one. Its closed vocabulary was
--
--   step_contract | executor_boundary | kernel_boundary | structural_constraint
--
-- and all 1,799 committed rows sat in the first, second and fourth. NONE was decided against a live
-- step run, and the file that builds the deliverable says so in its own header.
--
-- The founder's brief of 23 Aug 2026 requires the handler-specific negatives to be decided by
-- invoking the real handler on a real step run with actual invalid input. That is a STRONGER level
-- than any of the four, and the vocabulary had no word for it -- so the driver that produces it
-- could not record what it had done without misfiling it as one of the weaker four.
--
--   ADDED: live_step_run -- the case was decided by calling the real handler, or the kernel's own
--   dispatch door, against a step run opened by a real drive of the real workflow, inside a
--   transaction that ends in raise exception.
--
-- NOTHING IS REMOVED AND NOTHING IS RELABELLED. The four existing levels keep their meaning and
-- their rows; this widens the set by one so that a case decided at the strongest level can say so.
-- A row is still refused if it names a level outside the set, which is what the constraint is for.
--
-- ROLLBACK: scripts/sql/down/phase_d_k08_the_case_matrix_had_no_word_for_a_live_step_run_down.sql
-- restores the four-value constraint. It will refuse to run while any row still carries
-- live_step_run, deliberately: dropping the value while rows use it would leave the table holding
-- a level its own constraint forbids.

alter table public.phase_d_step_case_result
  drop constraint if exists phase_d_step_case_result_level_ck;

alter table public.phase_d_step_case_result
  add constraint phase_d_step_case_result_level_ck
  check (decided_at = any (array[
    'step_contract'::text,        -- the step's own declared input/output contract refused it
    'executor_boundary'::text,    -- a rule or gate service refused it, asked directly
    'kernel_boundary'::text,      -- a frozen kernel door refused it
    'structural_constraint'::text,-- a UNIQUE constraint or foreign key makes it impossible
    'live_step_run'::text         -- K08: the real handler or the kernel dispatch, on a real step run
  ]));
