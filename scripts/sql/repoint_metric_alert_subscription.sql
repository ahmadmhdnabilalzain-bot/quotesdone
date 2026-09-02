-- Dead subscription (flagged by fn_company_connectivity_register, class dead_subscription):
-- the active subscription 'metric.alert' -> 'analytics_director' points at an INACTIVE agent. The
-- dispatcher (fn_event_dispatch) joins company_event -> event_subscription -> org_agents on agent_key
-- without running the resolver, so every metric.alert is delivered to a dormant agent and dies there.
--
-- analytics_director was superseded by intel_director (Data & Intelligence Director, active) — the
-- runtime resolver already maps fn_org_agent_resolve('analytics_director') -> 'intel_director'. This
-- migrates the subscription itself to that active successor and retires the dead one.
--
--   node scripts/apply_sql.mjs scripts/sql/repoint_metric_alert_subscription.sql --apply --ddl

begin;

insert into public.event_subscription (agent_key, event_type, reason, active)
values ('intel_director', 'metric.alert',
        'Investigate and act on metric alerts (repointed from the retired analytics_director role)', true)
on conflict (agent_key, event_type) do update set active = true, reason = excluded.reason;

update public.event_subscription
   set active = false,
       reason = reason || ' [retired 2026-09-02: role superseded by intel_director]'
 where agent_key = 'analytics_director' and event_type = 'metric.alert';

commit;
