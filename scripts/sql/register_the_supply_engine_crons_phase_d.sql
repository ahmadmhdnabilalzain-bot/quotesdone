-- REGISTER the supply engine's crons as Phase D committed-scenario cron sources (3 Sep 2026).
--
-- fn_phase_d_committed_scenario_open refuses while any ACTIVE cron that reaches a kernel-watched
-- relation is unregistered ("every_active_cron_that_reaches_a_watched_relation_is_registered"), and
-- that refusal turns the kernel_positive_controls door fn_phase_d_committed_scenario_close red.
-- Measured after supply_engine_crons_run_through_the_kernel.sql: "3 unregistered: 322
-- supplier_discovery_daily, 59 doc_expiry_daily, 2 supplier_invites_daily". Jobs 155 and 162 were
-- registered before the stand-down with what their routines wrote THEN; both routines write more
-- now, and the rows say so.
--
-- `reaches` is what each routine was MEASURED to write (aborted-transaction probes and the first
-- kernel-traced runs, 3 Sep 2026). `quarantine` is why a committed ZZ DEMO scenario is not
-- contaminated: every one runs on its own tick in its own transaction, so it cannot see a scenario's
-- uncommitted fixture; the gap scan excludes ZZ DEMO / @example.invalid rows from every count; and
-- close() asserts that the rows THIS scenario created are gone by id/marker, not by a watermark.
--
--   node scripts/apply_sql.mjs scripts/sql/register_the_supply_engine_crons_phase_d.sql --apply --ddl

begin;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
  (322, 'supplier_discovery_daily',
   'fn_supplier_discovery_promote(300, 500): writes scrape_runs (its run row), leads (promoted staged directory rows, source yello_staging; the BEFORE triggers on leads set capability_score, lifecycle_stage and registration state on the same rows), lead_category and lead_category_scan (classification), yello_staging (stage promoted/duplicate), agent_runs.',
   'Supply discovery (3 Sep 2026). Own transaction on a daily tick; reads yello_staging, which no scenario writes, and cannot see a scenario''s uncommitted fixture; the leads it writes are real directory suppliers, never ZZ DEMO rows; close() asserts scenario rows by id/marker, so its writes do not move the watermark.'),
  (155, 'supply_gap_scan_daily',
   'fn_supply_gap_scan(): writes supply_health_snapshots (the daily supply-side snapshot), agent_actions (one coverage_gap record per category per week; trg_action_gate writes decision_log and kb_usage_log for each), agent_runs.',
   'Supply coverage measurement (3 Sep 2026). Own transaction on a daily tick; every count excludes ZZ DEMO / @example.invalid rows, so a committed fixture supplier is never read as coverage; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker.'),
  (59, 'doc_expiry_daily',
   'fn_doc_expiry_scan(): writes notifications (renewal requests to the supplier, held unless app_secrets.invite_enabled is true or the address is a reserved .invalid fixture), agent_actions (licence_expiring / licence_expired records; trg_action_gate writes decision_log and kb_usage_log), leads (matching_blocked / matching_block_reason through fn_reconcile_licence_blocks), agent_runs.',
   'Supplier verification (3 Sep 2026). Own transaction on a daily tick; cannot see a scenario''s uncommitted fixture; a committed fixture supplier with an expiring document gets a held outbox row and an action row of its own, both removed by close() by id/marker; matching_blocked is set only on approved suppliers with a lapsed licence date.'),
  (2, 'supplier_invites_daily',
   'enqueue_supplier_invites(): writes invite_schedule (the day''s plan) and agent_runs on every tick; only when app_secrets.invite_enabled is true also notifications (supplier_invite, queued), leads (invite_status, invited_at), and on a bounce pause app_secrets, founder_alerts and notifications (admin).',
   'Supplier invitations (3 Sep 2026). Own transaction on a daily tick; the send gate is closed until the founder''s go, so the tick writes one invite_schedule row and one agent_runs row about the real estate; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker.'),
  (162, 'company_indices_daily',
   'fn_company_indices(): writes company_index (maturity, marketplace health, energy), agent_runs, and — through fn_index_slowdown_watch at the end of every run — evolution_proposal and agent_actions (index_slowdown records; trg_action_gate writes decision_log and kb_usage_log) for any index that fell more than a point.',
   'Pure SQL measurement (3 Sep 2026). Own transaction on a daily tick; measures aggregate counts over committed rows only and cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker, so its writes do not move the watermark.')
on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;

do $proof$
declare v text;
begin
  select detail into v from public.fn_phase_d_committed_scenario_guards()
   where check_name = 'every_active_cron_that_reaches_a_watched_relation_is_registered';
  raise notice 'every_active_cron_that_reaches_a_watched_relation_is_registered: %', v;
  if v ~ '\y(322|155|59|2|162) (supplier_discovery_daily|supply_gap_scan_daily|doc_expiry_daily|supplier_invites_daily|company_indices_daily)' then
    raise exception 'a supply engine cron is still unregistered: %', v;
  end if;
end $proof$;

commit;
