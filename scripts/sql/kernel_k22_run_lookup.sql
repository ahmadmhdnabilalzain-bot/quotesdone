-- K22 — a class-B source has to find the run it belongs to, and it must not guess.
--
-- fn_kernel_signal_submit demands a workflow_run_id and refuses to look one up by business object,
-- deliberately: guessing which run a signal belongs to is how one arrival lands on two runs. But a
-- database trigger only knows its own row — a quote_id, a transaction_id — so something has to do
-- the resolution, once, in a place that can be checked.
--
--   select public.fn_kernel_run_for('quotation:' || NEW.quote_id);
--
-- It returns the ONE live run for that business object, or NULL. It never returns a terminal run
-- (a closed run does not accept signals, and the signal door would refuse it anyway), and if more
-- than one live run somehow exists for one object it returns NULL rather than picking the lowest
-- id. Picking the first match is how the pack auditor once invented a 16,608-record hole; a
-- resolver that cannot be certain must say so, not choose.
--
-- NULL is a real answer and the callers treat it as one: no live run means there is nothing to
-- attach a signal to, and the source stays quiet rather than opening a workflow to have somewhere
-- to put its signal.
--
-- Rollback: scripts/sql/rollback/kernel_k22_run_lookup.rollback.sql

begin;

create or replace function public.fn_kernel_run_for(p_business_object_id text)
returns bigint
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $k22_run_for$
  select case when count(*) = 1 then min(r.run_id) end
    from public.phase_c_workflow_run r
   where r.business_object_id = p_business_object_id
     and r.state in (select state from public.phase_b_workflow_state where not terminal);
$k22_run_for$;

revoke all on function public.fn_kernel_run_for(text) from public, anon, authenticated;
grant execute on function public.fn_kernel_run_for(text) to service_role;

comment on function public.fn_kernel_run_for(text) is
  'K22. The one live workflow run for a business object, or NULL. Returns NULL when there is none '
  'AND when there is more than one: a resolver that cannot be certain must say so rather than '
  'take the first match. Terminal runs are excluded — a closed run does not accept signals.';

commit;
