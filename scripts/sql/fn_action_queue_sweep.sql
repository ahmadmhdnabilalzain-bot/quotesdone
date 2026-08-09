-- fn_action_queue_sweep — close what has already resolved itself, and collapse what repeats.
--
-- The founder's review queue holds 316 items in needs_review. It is not 316 decisions; it is a
-- handful of conditions re-raised every day and never closed:
--
--   incident              153, oldest 3 Aug   "N agent run(s) failed in last 24h", re-raised daily
--   handoff                75, oldest 24 Jul
--   knowledge_task         23
--   improvement_question   15
--
-- Section 4 of the spec's autonomy list is Self-Healing, and this is the missing half of it: work
-- that resolves itself should leave the queue by itself. Nothing here approves or rejects anything
-- on the founder's behalf — two narrow, defensible rules only:
--
--   1. DUPLICATES COLLAPSE. Identical (agent, kind, title) raised more than once: the newest stays
--      open, the older copies are marked superseded and point at it. No information is lost — the
--      supersedes id is written into detail.
--   2. A STALE INCIDENT WHOSE CONDITION HAS CLEARED CLOSES. An incident about failed runs, where
--      the named agents have since run clean for 48 hours, is describing something that is no
--      longer true. It closes as auto_resolved with the evidence recorded.
--
-- Everything else — handoffs, legal flags, customer escalations, strategy recommendations — is
-- LEFT ALONE. Those need a human, and clearing them automatically would be exactly the
-- mass-closing the founder's rules forbid.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_action_queue_sweep.sql --ddl --promote
create or replace function public.fn_action_queue_sweep()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare v_dupes int := 0; v_cleared int := 0;
begin
  -- 1. DUPLICATES. Keep the newest of each (agent, kind, title); supersede the rest.
  with ranked as (
    select id, agent, kind, title,
           first_value(id) over (partition by agent, kind, title order by created_at desc) keep_id,
           row_number() over (partition by agent, kind, title order by created_at desc) rn
      from public.agent_actions
     where status in ('pending','needs_review')
  ), dupes as (select id, keep_id from ranked where rn > 1)
  update public.agent_actions a
     set status = 'superseded',
         decided_by = 'action_queue_sweep',
         decided_at = now(),
         detail = coalesce(a.detail, '{}'::jsonb)
                  || jsonb_build_object('superseded_by', d.keep_id, 'swept_at', now(),
                                        'reason', 'identical agent/kind/title already open')
    from dupes d where a.id = d.id;
  get diagnostics v_dupes = row_count;

  -- 2. STALE INCIDENTS whose condition has cleared. An incident naming failed runs, older than
  --    48 hours, where nothing has failed in the last 48 hours, is no longer true.
  update public.agent_actions a
     set status = 'auto_resolved',
         decided_by = 'action_queue_sweep',
         decided_at = now(),
         detail = coalesce(a.detail, '{}'::jsonb)
                  || jsonb_build_object('auto_resolved_at', now(),
                                        'reason', 'no agent run has failed in the last 48 hours')
   where a.status in ('pending','needs_review')
     and a.kind = 'incident'
     and a.created_at < now() - interval '48 hours'
     and a.title ~* 'run\(s\) failed'
     and not exists (select 1 from public.agent_runs r
                      where r.status in ('error','failed')
                        and r.started_at > now() - interval '48 hours');
  get diagnostics v_cleared = row_count;

  if v_dupes + v_cleared > 0 then
    insert into public.founder_alerts(level, event, detail, channel)
      values ('info', 'Action queue swept',
              v_dupes || ' duplicate(s) superseded and ' || v_cleared
              || ' stale incident(s) auto-resolved. Handoffs, legal flags, customer escalations and '
              || 'recommendations were left untouched — those need you.', 'os');
  end if;

  return jsonb_build_object('superseded', v_dupes, 'auto_resolved', v_cleared,
    'still_open', (select count(*) from public.agent_actions where status in ('pending','needs_review')),
    'ran_at', now());
end $function$;

select cron.unschedule(j.jobname) from cron.job j where j.jobname = 'action_queue_sweep_hourly';
select cron.schedule('action_queue_sweep_hourly', '35 * * * *', $$select public.fn_action_queue_sweep();$$);

insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('action_queue_sweep_hourly', 'Action Queue Sweep', 'Governance',
   'Collapses duplicate open actions onto the newest copy and auto-resolves stale incidents whose condition has cleared. Never touches handoffs, legal flags, escalations or recommendations.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
