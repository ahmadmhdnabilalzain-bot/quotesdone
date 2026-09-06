-- WA_FLUSH IS REGISTERED FOR THE SCENARIO DOOR (6 Sep 2026).
--
-- the_founder_alert_has_a_whatsapp_template_and_the_company_knows_its_templates.sql put cron 34
-- (wa_flush, every two minutes, the only drainer of channel='whatsapp' notifications) back on through
-- fn_kernel_wrap_and_enable_cron(34, 'it_operations_engineer', 'product_eng'). fn_phase_d_committed_scenario_guards
-- requires every active cron that reaches a watched relation to hold a phase_d_committed_scenario_cron
-- row saying what it reaches and how a committed scenario is quarantined from it; job 34 had none, so
-- the scenario door has been red since the re-enable. This is that row.
--
--   node scripts/apply_sql.mjs scripts/sql/wa_flush_is_registered_for_the_scenario_door.sql --apply --ddl

begin;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (34, 'wa_flush',
  'UPDATEs public.notifications where channel = ''whatsapp'' (status queued -> sent / failed, attempts, sent_at, last_error) through the send_whatsapp edge function, which sends only a template whose messaging_template row Twilio reports approved and skips-with-reason otherwise; INSERTs public.agent_runs.',
  'Every two minutes in its own transaction. A committed scenario''s WhatsApp rows are ZZ DEMO / @example.invalid / Twilio reserved test numbers, which zzz_notifications_demo_guard and send_whatsapp refuse before any provider call; the drainer therefore never delivers a scenario row, and close() asserts scenario rows by id/marker.')
on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;

do $$
begin
  if not exists (select 1 from public.phase_d_committed_scenario_cron where jobid = 34) then
    raise exception 'cron 34 is not registered for the scenario door';
  end if;
end $$;

commit;
