-- DEPARTMENT OPS HEARTBEAT — the producer that makes departments ACT on their own.
--
-- The execution engine is on and every department has executors, but an executor only runs when an
-- action is queued for it. This is the producer: twice a day it queues each department's SAFE routine
-- work — executors that are autonomous, unattended-safe, low-risk, reversible and non-human-notifying —
-- so departments run their own health scans, boards, scorecards and forecasts without anyone asking.
-- Deterministic (no inference). Idempotent: an executor is re-queued only when 12h have passed, so a
-- department's routine runs about twice a day, never floods. Money/destructive/founder-reserved and
-- anything not explicitly unattended-safe is never auto-run here.
--
--   node scripts/apply_sql.mjs scripts/sql/department_ops_heartbeat.sql --apply --ddl

begin;

-- Heavy synchronous rpc executors run on-demand, not in the twice-daily heartbeat: the rpc invoker
-- executes them inside its own transaction, so a long one (e.g. fn_kb_reconcile's full kb_chunks scan)
-- would block the invoker. Keep them out of the unattended set.
update public.org_action_executor
   set unattended_ok = false,
       note = coalesce(note,'') || ' | not unattended: heavy synchronous rpc, runs on-demand not in the ops heartbeat'
 where kind = 'rpc' and unattended_ok and target in ('fn_kb_reconcile');

create or replace function public.fn_dept_ops_heartbeat()
 returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare v_queued int := 0; r record;
begin
  for r in
    select e.action_class, e.department, e.target, e.risk_tier, e.reversible
      from public.org_action_executor e
      join public.org_authority au
        on au.dept_key = e.department and au.action_class = e.action_class and au.max_tier = 'autonomous'
     where e.active
       and coalesce(e.unattended_ok, false) = true
       and e.risk_tier = 'low'
       and e.reversible
       and coalesce(e.notifies_human, false) = false
       and not exists (
         select 1 from public.action_execution a
          where a.action_class = e.action_class and a.created_at > now() - interval '12 hours')
  loop
    begin
      insert into public.action_execution(action_class, executor, idempotency_key, risk_tier, reversible,
                                           request, status, author, correlation_id)
      values (r.action_class, r.target,
              r.action_class || '_hb_' || to_char(now() at time zone 'utc','YYYYMMDDHH24'),
              r.risk_tier, r.reversible, '{}'::jsonb, 'queued', 'dept_ops_heartbeat', gen_random_uuid());
      v_queued := v_queued + 1;
    exception when unique_violation then null;  -- already queued this window
    end;
  end loop;
  return jsonb_build_object('queued', v_queued, 'at', now());
end $fn$;
revoke execute on function public.fn_dept_ops_heartbeat() from public;
grant execute on function public.fn_dept_ops_heartbeat() to service_role;

-- Runs hourly; self-gates on the 12h window, so each department's routine fires about twice a day.
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

commit;
