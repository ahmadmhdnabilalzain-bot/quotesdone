-- Triage the 5 stand-down-era silent-failure incidents the re-enabled watchdog re-escalates.
--
-- fn_os_incident_watchdog (re-enabled 2 Sep) correctly re-escalates overdue high OPEN incidents. Five
-- were opened Aug 13-15 by fn_edge_health_scan for functions that "produced no effect". None is a live
-- defect the founder must be paged about every 24h; each has an accurate disposition below. This does
-- NOT touch phase_c_component, so it does not affect the PCCR-008 freeze amendment.
--
-- WHY EACH (measured 2 Sep 2026):
--   dropbox_backup  FALSE POSITIVE. The edge_expectation heartbeat checks agent='dropbox_backup', a
--                   defunct name. The live backup runs as agent='dropbox_sync' (last 2026-09-01, and
--                   dropbox_sync_daily/dropbox_backup_scan crons are active). Fix the heartbeat to the
--                   live agent (verdict becomes ALIVE); backups are running.
--   dept_learn      INFERENCE-BOUND, intentionally held. Produces org_memory lessons only via the AI
--   dept_plan       gateway; OpenRouter is off by the founder's standing decision, so no heartbeat is
--   gen_category_   EXPECTED. Flagging an intentionally-held inference function as a silent failure is
--     knowledge     a false alarm. Deactivate the expectation; re-activate when OpenRouter is funded.
--   dr_drill        Deterministic monthly DR drill; cron held by the 16 Aug stand-down. Not a data
--                   -loss risk (backups run via dropbox_sync). Re-enabling a state-changing cron now
--                   re-drifts the frozen component registry, so it is DEFERRED until PCCR-008 is
--                   ratified. Tracked by an org_task; expectation deactivated until re-enabled.
--
--   node scripts/apply_sql.mjs scripts/sql/triage_standdown_silent_failure_incidents.sql --apply --ddl

begin;

-- 1. dropbox_backup: point the health check at the live agent. Backups run; the name was stale.
update public.edge_expectation
   set heartbeat_sql = 'select max(started_at) from public.agent_runs where agent = ''dropbox_sync''',
       purpose = coalesce(purpose,'') || ' [2 Sep 2026: heartbeat re-pointed from the defunct agent ''dropbox_backup'' to the live ''dropbox_sync''; dropbox_sync_daily/dropbox_backup_scan crons are active.]'
 where fn_key = 'dropbox_backup';

-- 2. Intentionally-held functions: deactivate the expectation (a held function is not expected to beat).
update public.edge_expectation
   set active = false,
       purpose = coalesce(purpose,'') || ' [2 Sep 2026: expectation DEACTIVATED — inference-bound, held pending OpenRouter funding; no heartbeat is expected while the paid-provider hold is on. Re-activate when OpenRouter is funded and the cron is re-enabled.]'
 where fn_key in ('dept_learn','dept_plan','gen_category_knowledge');

update public.edge_expectation
   set active = false,
       purpose = coalesce(purpose,'') || ' [2 Sep 2026: expectation DEACTIVATED — monthly DR drill cron held by the 16 Aug stand-down; re-enable deferred until PCCR-008 is founder-ratified (re-enabling a state-changing cron now re-drifts the frozen component registry). Tracked by org_task. Re-activate on re-enable.]'
 where fn_key = 'dr_drill';

-- 3. Resolve the open incidents with their accurate disposition (any open silent_failure for these keys).
update public.os_incidents
   set status = 'resolved', resolved_by = 'security', resolved_at = now(),
       resolution = case
         when detail->>'fn_key' = 'dropbox_backup' then
           'False positive: the check monitored the defunct agent name dropbox_backup. Backups run live as dropbox_sync (last 2026-09-01; dropbox_sync_daily/dropbox_backup_scan crons active). Heartbeat re-pointed to the live agent.'
         when detail->>'fn_key' = 'dr_drill' then
           'Monthly DR drill cron held by the 16 Aug stand-down. Not a data-loss risk (backups run via dropbox_sync). Re-enable deferred until PCCR-008 is ratified; tracked by org_task. Expectation deactivated until re-enabled.'
         else
           'Inference-bound function (' || (detail->>'fn_key') || '): produces no effect only because the paid-provider (OpenRouter) hold is on — the founder''s intentional constraint, not a defect. Expectation deactivated; re-activate when OpenRouter is funded.'
       end
 where status = 'open'
   and kind = 'silent_failure'
   and detail->>'fn_key' in ('dept_learn','dept_plan','gen_category_knowledge','dr_drill','dropbox_backup');

-- 4. Track the one genuine deferral (dr_drill re-enable), deduplicated on title.
insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
select 'assurance', 'Re-enable the monthly DR drill after PCCR-008 is ratified',
       'dr_drill_monthly was held by the 16 Aug stand-down. Re-enabling it (a state-changing cron) re-drifts the frozen phase_c_component registry, so it waits until the founder ratifies PCCR-008. On re-enable: wrap it as a traced kernel component, declare it statically, and re-activate its edge_expectation (fn_key dr_drill).',
       'proposed', 'gated', false, 'incident_fix'
 where not exists (select 1 from public.org_tasks
                    where title = 'Re-enable the monthly DR drill after PCCR-008 is ratified'
                      and status <> 'done');

commit;
