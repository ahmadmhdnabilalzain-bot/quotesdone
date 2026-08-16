-- ROLLBACK for kernel_k4_cancellation.sql
--
-- Drops the cancellation service and its invariant. It does NOT re-open the rows the service
-- closed: reversing a cancellation would resurrect work the founder stopped, and a rollback that
-- creates business work is not a rollback. The closures carry their reason, their actor and their
-- sealed trace, so if any of them was wrong it is visible and can be re-opened deliberately, by
-- name, as its own migration.
--
-- founder_command_plan.state / .closed_at are kept. Dropping a column destroys the record of which
-- plans were closed and why; the columns are additive and harmless if unused.

begin;

drop function if exists public.fn_kernel_orphaned_work();
drop function if exists public.fn_kernel_cancel(jsonb);

-- Deliberately NOT dropped:
--   alter table public.founder_command_plan drop column state;      -- destroys evidence
--   alter table public.founder_command_plan drop column closed_at;  -- destroys evidence
--   constraint founder_command_plan_state_ck                        -- guards the above

commit;
