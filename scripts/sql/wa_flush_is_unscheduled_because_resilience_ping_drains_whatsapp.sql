-- WA_FLUSH IS UNSCHEDULED BECAUSE RESILIENCE_PING DRAINS WHATSAPP (30 Sep 2026; seat: customer_support).
--
-- Senior-hire audit, customer_support 6: cron.job wa_flush (jobid 34, every 2 minutes, active = false).
--
-- WHAT WAS MEASURED (30 Sep 2026, production, read-only):
--   * cron.job holds two rows: wa_flush (inactive) and ceo-strategy-memo-monthly (active).
--   * wa_flush only POSTs to the send_whatsapp edge function with an internal credential. It does nothing else.
--   * send_whatsapp is called today by resilience_ping (supabase/functions/resilience_ping/index.ts, the
--     send_whatsapp step added by scripts/sql/the_founders_whatsapp_queue_gets_a_consumer_again.sql, which put
--     send_whatsapp into fn.resilience_ping's scope). That step replaced wa_flush on 9 Sep.
--   * public.phase_d_committed_scenario_cron still carries its row for jobid 34
--     (scripts/sql/wa_flush_is_registered_for_the_scenario_door.sql). A register row for a job that does not exist
--     points at nothing, so it goes with the job.
--
-- No job exists without a purpose (founder, 7 Sep 2026): the job is removed, not left inactive.
--   node scripts/apply_sql.mjs scripts/sql/wa_flush_is_unscheduled_because_resilience_ping_drains_whatsapp.sql --apply --ddl

do $$
begin
  if exists (select 1 from cron.job where jobname = 'wa_flush') then
    perform cron.unschedule('wa_flush');
  end if;
  if to_regclass('public.phase_d_committed_scenario_cron') is not null then
    delete from public.phase_d_committed_scenario_cron where jobname = 'wa_flush';
  end if;
end $$;

select case when exists (select 1 from cron.job where jobname = 'wa_flush')
            then 'PROBE FAILED: wa_flush is still scheduled'
            else 'PROBE OK: wa_flush is unscheduled' end as verdict;
