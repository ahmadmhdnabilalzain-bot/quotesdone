-- ---------------------------------------------------------------------------------------------
-- STAND DOWN. EVERY QUEUE TO ZERO, AND THE INTAKE STOPPED SO IT STAYS THERE.
--
-- Founder, 16 Aug 2026, after reviewing the chain-of-command audit:
--   "no one should have a single task now until we fix the workflow and chain of command"
--   "escalations log is still there while i asked you to clear it totally"
--   "i will share exact workflow once you clear everything i asked for"
--
-- The earlier watermark (os_fresh_start) was the wrong answer to the question he asked. It hid
-- five surfaces and left the others reading live rows, and hiding was never what he asked for: the
-- company is being stood down so its chain of command can be rebuilt, and work sitting in a queue
-- that nobody can see is worse than work sitting in a queue he can.
--
-- Measured immediately before this file ran:
--   org_tasks open            527
--   agent_actions open         71
--   evolution_proposal         53
--   founder_alerts            372
--   dead_letter               122
--   opportunity open           19
--   phase_c_task queued         8
--   crm_tasks open              6
--
-- WHY CANCELLING ALONE WOULD NOT HAVE HELD. Every raiser in this codebase dedupes on "is an open
-- row already present", so closing a row RELEASES its suppression — proved earlier today by
-- clearing the 27-item founder queue and re-running five of the 186 active cron jobs in one
-- aborted transaction: 7 returned immediately, 36 over a full cycle. Cancelling without stopping
-- the intake would have refilled the queues inside an hour and looked like nothing had happened.
--
-- So two halves, and both are necessary:
--   1. every open row is CANCELLED with a stated reason,
--   2. the 69 active cron jobs that mint work or escalations are PAUSED.
--
-- WHAT IS NOT PAUSED, deliberately: backups, uptime and health probes, the security scanner's
-- own logging, and everything that only observes. Standing the workforce down is not the same as
-- blinding the infrastructure, and he did not ask for the second.
--
-- REVERSIBLE IN ONE STATEMENT. Every paused job is recorded in public.company_stand_down with its
-- jobid, so resuming is a single update once the new chain of command is agreed. Nothing is
-- dropped, nothing is deleted, and no history is destroyed — cancelled rows keep their text, their
-- author and their timestamps, and stay queryable for ever.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.company_stand_down (
  id           bigserial primary key,
  stood_down_at timestamptz not null default now(),
  actor        text not null,
  reason       text not null,
  paused_jobs  jsonb not null default '[]'::jsonb,
  cancelled    jsonb not null default '{}'::jsonb,
  resumed_at   timestamptz
);
alter table public.company_stand_down enable row level security;
revoke all on public.company_stand_down from anon, authenticated;

comment on table public.company_stand_down is
  'A deliberate, reversible halt of the AI workforce. paused_jobs holds the cron jobids switched '
  'off so the resume is exact rather than a guess. Nothing here deletes anything.';

-- ---- 1. EVERY OPEN QUEUE TO ZERO -------------------------------------------------------------
-- Cancelled, not deleted. The reason travels with each row so nobody reading this in a month has
-- to guess why 527 tasks stopped on one afternoon.

-- org_tasks had NO terminal state meaning "stopped without being done and without failing". Its
-- CHECK allowed proposed/assigned/in_progress/blocked/done/failed/escalated only, so the choice was
-- between lying ('done' or 'failed') and adding the state that describes what actually happened.
-- The guard was right to refuse the update; the vocabulary was incomplete.
alter table public.org_tasks drop constraint if exists org_tasks_status_check;
alter table public.org_tasks add constraint org_tasks_status_check
  check (status = any (array['proposed','assigned','in_progress','blocked','done','failed','escalated','cancelled']));

update public.org_tasks
   set status = 'cancelled',
       result = coalesce(result, '{}'::jsonb) || jsonb_build_object(
         'cancelled_by', 'company stand-down 16 Aug 2026',
         'cancelled_because', 'Founder halted all work until the chain of command is rebuilt.')
 where status not in ('done','cancelled');

update public.agent_actions
   set status = 'cancelled', decided_at = now(), decided_by = 'company_stand_down'
 where status in ('pending','needs_review');

update public.phase_c_task
   set state = 'cancelled'
 where state = 'queued';

update public.crm_tasks
   set status = 'cancelled'
 where coalesce(status,'') <> 'done';

-- 'rejected' is this CHECK's terminal value; there is no 'withdrawn'. These are not re-litigated,
-- they are taken off the board.
update public.evolution_proposal
   set status = 'rejected'
 where status = 'proposed';

update public.opportunity
   set status = 'dismissed'
 where status = 'open';

-- founder_alerts has NO status column at all — id, level, event, detail, channel, created_at. It
-- is a pure log, so there is nothing to mark, and removing the rows is the only way to answer the
-- instruction. 372 of them; no foreign key refers to the table; it is the sole source of the
-- bell's Critical tier. This is the ONE place in this file where history is genuinely discarded,
-- and it is discarded because the table offers no other way to be cleared.
delete from public.founder_alerts;

update public.dead_letter
   set resolved_at = coalesce(resolved_at, now()),
       resolution = coalesce(resolution, 'abandoned at the 16 Aug 2026 company stand-down')
 where resolved_at is null;

-- ---- 2. STOP THE INTAKE ----------------------------------------------------------------------
-- The 69 active cron jobs that create work or escalations. Identified by reading each job's
-- command against the set of routines that INSERT into a work table, plus the named edge-function
-- runners — not by a hand-written list, so a job cannot be missed by forgetting it exists.

insert into public.company_stand_down (actor, reason, paused_jobs, cancelled)
select 'management@quotesdone.com',
  'Founder instruction, 16 Aug 2026: "no one should have a single task now until we fix the '
  'workflow and chain of command." Every open queue cancelled and every work-creating cron job '
  'paused. Cancelling alone would not hold: every raiser dedupes on an open row, so closing one '
  'releases its suppression and the queues refill within the hour. Backups, uptime and health '
  'probes are deliberately left running - standing the workforce down is not blinding the '
  'infrastructure.',
  (select coalesce(jsonb_agg(jsonb_build_object('jobid', j.jobid, 'jobname', j.jobname)
                             order by j.jobname), '[]'::jsonb)
     from cron.job j
    where j.active
      and (exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.prokind = 'f'
                      and pg_get_functiondef(p.oid) ~* 'insert\s+into\s+(public\.)?(org_tasks|agent_actions|phase_c_task|crm_tasks|founder_alerts|evolution_proposal|opportunity)'
                      and j.command ilike '%' || p.proname || '%')
        or j.command ~* '(agents|action_worker|cos_execute|workflow_dispatch|dept_plan|dept_learn|kpi_review|exec_meeting|os_review|ceo_questions|task_assign|event_dispatch)')),
  jsonb_build_object('org_tasks', 527, 'agent_actions', 71, 'evolution_proposal', 53,
                     'founder_alerts', 372, 'dead_letter', 122, 'opportunity', 19,
                     'phase_c_task', 8, 'crm_tasks', 6)
 where not exists (select 1 from public.company_stand_down s where s.resumed_at is null);

-- Pause them, reading the ids back out of the record just written so the two can never disagree.
select cron.alter_job((e->>'jobid')::bigint, active := false)
  from public.company_stand_down s,
       lateral jsonb_array_elements(s.paused_jobs) e
 where s.resumed_at is null
   and s.id = (select max(id) from public.company_stand_down where resumed_at is null);
