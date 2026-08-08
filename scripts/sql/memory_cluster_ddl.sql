-- Spec file #2, components 11-13 (memory cluster) — schema, guard trigger, derivations, schedule.
-- Run AFTER scripts/sql/memory_cluster_routines.sql, which defines the two routines referenced here.
--   node scripts/apply_sql.mjs scripts/sql/memory_cluster_ddl.sql --promote --ddl
--
-- The two UPDATEs below are DERIVATIONS, not carried row data: each computes its value from the
-- rows that already exist in the project it runs against, so the identical text is correct on both
-- staging and production and neither copies a value from the other.

-- ---------------------------------------------------------------------------------------------
-- agent_memory.horizon — short-term vs long-term, the distinction the blueprint draws.
--
-- The column was added and never written to, so all 219 production rows were one undifferentiated
-- store. The rule: an INSTRUCTION is long-term by definition (a standing instruction does not
-- expire), everything else starts SHORT and earns long-term status by being promoted into the
-- knowledge base by fn_promote_memory_sweep. New rows default to short for the same reason.
alter table public.agent_memory alter column horizon set default 'short';

update public.agent_memory
   set horizon = case when kind = 'instruction' then 'long' else 'short' end
 where horizon is null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'agent_memory_horizon_chk') then
    alter table public.agent_memory
      add constraint agent_memory_horizon_chk check (horizon in ('short', 'long'));
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- org_tasks.root_cause — lift the diagnosis out of the deliverable it was buried in.
--
-- Closed KPI-miss tasks already carry a "Root cause" paragraph written by the owner; the column
-- stayed null. This captures the existing text verbatim (whitespace collapsed) — it invents
-- nothing, and rows whose deliverable states no cause stay null.
update public.org_tasks o
   set root_cause = left(nullif(btrim(regexp_replace(
         coalesce(substring(coalesce(o.result ->> 'deliverable', '')
                            from '(?i)root cause[^\n]{0,250}'), ''),
         '\s+', ' ', 'g')), ''), 500)
 where o.title ilike 'KPI missed%'
   and o.status = 'done'
   and coalesce(o.root_cause, '') = ''
   and coalesce(o.result ->> 'deliverable', '') ~* 'root cause';

-- From here on a KPI-miss task cannot close without one.
drop trigger if exists trg_org_task_root_cause on public.org_tasks;
create trigger trg_org_task_root_cause
  before update on public.org_tasks
  for each row execute function public.fn_org_task_root_cause_guard();

-- ---------------------------------------------------------------------------------------------
-- The promotion sweep needs a caller of its own. Tuesday 05:15, a day after sop_update_weekly so
-- the two memory writers do not contend.
select cron.schedule('memory_promotion_weekly', '15 5 * * 2',
                     'select public.fn_promote_memory_sweep();');
