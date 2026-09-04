-- THE DETERMINISTIC `agents` CRONS GO BACK ON THE CLOCK (4 Sep 2026). MASTER_PLAN A2.
--
-- Four jobs switched off with the 16 Aug 2026 stand-down (deactivation-is-not-death: 679, 29, 678 and
-- 26 prior runs, every one stopped on the same date). Each was READ for what it writes and sends
-- before this file turned it on:
--
--   8   agent_onboarding_hourly   run_agent('onboarding') -> agents edge fn. Reads leads pending with a
--                                 registration; queues agent_actions (approve_supplier, licence_expiring /
--                                 licence_expired; agent 'onboarding'); sets leads.lifecycle_stage. No
--                                 notifications, no email, no WhatsApp, no model call.
--   10  agent_followup_daily      run_agent('followup'). Inserts notifications nudge_reveal (to a
--                                 customer with quotes not revealed after 2 days) and nudge_quote (to a
--                                 matched supplier with no quote after 2 days); queues sla_* agent_actions
--                                 (agent 'followup'). No model call. Measured 4 Sep: customers 0,
--                                 inquiries 0, inquiry_matches 0 — nothing to nudge; a fixture customer or
--                                 supplier carries @example.invalid, which send_outbox refuses as a clean
--                                 skip and zzz_notifications_demo_guard holds when a rehearsal is declared.
--   119 category_sales_daily      fn_category_sales() — pure SQL; agent_actions hot_lead/supply_gap
--                                 (agent 'cat:<slug>') + its own agent_runs row. Nothing outbound.
--   15  agent_it_health_hourly    run_agent('it_health'). GETs the four public pages, writes health_checks,
--                                 queues 'it' incidents. It ALSO emailed admin_emails directly on a page
--                                 down — a second founder channel with no dedupe and no resolution. That
--                                 insert is removed from supabase/functions/agents/index.ts in the same
--                                 change: the red-view alerter (fn_red_view_alert) reads health_checks
--                                 ok=false and pages once per episode, level high, resolved when the page
--                                 is back.
--
-- Founder paging, checked: trg_page_high_agent_action pages only for agent ~ '^(finance|security|
-- operations)'; 'onboarding', 'followup', 'it' and 'cat:*' never match. No executor in
-- org_action_executor with notifies_human=true is reached by these jobs. fn_watch_failed_runs pages on
-- an agent_runs error row — these jobs write status ok on a clean run and none calls a model, so a held
-- model cannot produce an error row from them.
--
-- Accountable roles are the ones already recorded on the phase_c_component rows (agent_workforce_
-- capability_director / people_ops for 8 and 10; it_operations_engineer / product_eng for 15;
-- chief_revenue_officer / growth for 119), every one an active org_role. The wrap resets
-- authority_class to its default, so the committed class is put back after each wrap.
--
--   node scripts/apply_sql.mjs scripts/sql/reenable_agents_crons.sql --apply --ddl

begin;
do $$
begin
  perform public.fn_kernel_wrap_and_enable_cron(8,   'agent_workforce_capability_director', 'people_ops',  'routine_operational_decision');  -- agent_onboarding_hourly (23 * * * *)
  perform public.fn_kernel_wrap_and_enable_cron(10,  'agent_workforce_capability_director', 'people_ops',  'routine_operational_decision');  -- agent_followup_daily    (37 5 * * *)
  perform public.fn_kernel_wrap_and_enable_cron(119, 'chief_revenue_officer',               'growth',      'routine_operational_decision');  -- category_sales_daily    (30 5 * * *)
  perform public.fn_kernel_wrap_and_enable_cron(15,  'it_operations_engineer',              'product_eng', 'security_secret_rotation');      -- agent_it_health_hourly  (15 * * * *)
  update public.phase_c_component set authority_class = 'security_secret_rotation'
   where component_id = 'cron:agent_it_health_hourly' and authority_class is distinct from 'security_secret_rotation';

  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
    (8,   'agent_onboarding_hourly',
          'Via the agents edge function: INSERTs public.agent_actions (approve_supplier, licence_expiring/expired), UPDATEs public.leads.lifecycle_stage (a derived column; never status, approval or contact), INSERTs public.agent_runs.',
          'Hourly at :23, its own transaction. Reads leads by approval_status/registration_submitted_at; a committed scenario''s ZZ DEMO leads are uncommitted and invisible to it, and it never emails or messages anyone. close() asserts scenario rows by id/marker.'),
    (10,  'agent_followup_daily',
          'Via the agents edge function: INSERTs public.notifications (nudge_reveal to a customer, nudge_quote to a supplier — 0 candidates today: customers/inquiries/inquiry_matches are empty), INSERTs public.agent_actions (sla_refund, sla_review, sla_no_supply), INSERTs public.agent_runs.',
          'Daily 05:37 UTC, its own transaction. A scenario''s fixtures are uncommitted while it runs; committed fixtures carry @example.invalid, which send_outbox refuses as a clean skip and zzz_notifications_demo_guard holds when demo_rehearsal_active is set. close() asserts scenario rows by id/marker.'),
    (119, 'category_sales_daily',
          'Pure SQL: INSERTs public.agent_actions (hot_lead, supply_gap) and public.agent_runs.',
          'Daily 05:30 UTC, its own transaction. Reads inquiries/quotes/inquiry_matches of the real estate; a committed scenario''s fixtures are uncommitted and invisible. close() asserts scenario rows by id/marker.'),
    (15,  'agent_it_health_hourly',
          'Via the agents edge function: INSERTs public.health_checks (http probes of the four public pages; an agent_runs failure-rate row), INSERTs public.agent_actions (it incidents), INSERTs public.agent_runs. Since 4 Sep 2026 it sends NO notification itself; the red-view alerter pages on its health rows.',
          'Hourly at :15, its own transaction. Probes public URLs and the agent_runs failure rate — never a scenario row. close() asserts scenario rows by id/marker.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $$;
commit;

do $ctl$
begin
  if (select count(*) from cron.job where jobid in (8,10,15,119) and active and command ilike '%fn_kernel_cron_exec%') <> 4 then
    raise exception 'not all 4 agents crons are active and wrapped';
  end if;
  if exists (select 1 from public.phase_c_component c
              where c.component_id in ('cron:agent_onboarding_hourly','cron:agent_followup_daily','cron:category_sales_daily','cron:agent_it_health_hourly')
                and not exists (select 1 from public.org_role r where r.role_id = c.accountable_role_id and r.status = 'active')) then
    raise exception 'an agents cron carries an accountable role that does not resolve';
  end if;
  -- scoped to THESE jobs: six agents share the estate today and another's undocumented cron is not this file's finding
  if (select count(*) from public.cron_registry r where r.jobname in ('agent_onboarding_hourly','agent_followup_daily','category_sales_daily','agent_it_health_hourly')) <> 4 then
    raise exception 'one of the four agents crons is undocumented in cron_registry';
  end if;
end $ctl$;
