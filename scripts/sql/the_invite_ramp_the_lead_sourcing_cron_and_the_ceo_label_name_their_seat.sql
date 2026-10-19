-- THE INVITE RAMP, THE LEAD-SOURCING CRON AND THE CEO RUN LABEL NAME THEIR SEAT.
--
-- Assigned: marketing (defect fix approved by the coordinator, 13 Oct 2026).
-- Founder rule, 7 Sep 2026: "no job/task should exist if it doesnt belong to an agent".
--
-- MEASURED: scripts/checks/every_run_label_and_cron_job_names_its_seat.test.mjs is red against production;
-- fn_writers_without_a_seat(7) lists three writers with no seat:
--   agent_runs_label invite_ramp          (fn_invite_ramp, the supplier invitation ramp)
--   cron_job         lead_sourcing_batch  (the_marketing_seat_finds_new_complete_supplier_leads_every_day.sql)
--   agent_runs_label ceo                  (runs logged under the seat's own name)
-- CHANGE: invite_ramp and lead_sourcing_batch are registered under marketing; the ceo label under ceo.
-- prevented by: scripts/checks/every_run_label_and_cron_job_names_its_seat.test.mjs (already present; red before this file)

insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('agent_runs_label', 'invite_ramp', 'marketing',
   'fn_invite_ramp: the daily supplier invitation ramp under the founder''s weekly cap.',
   'scripts/sql/the_invite_ramp_the_lead_sourcing_cron_and_the_ceo_label_name_their_seat.sql'),
  ('cron_job', 'lead_sourcing_batch', 'marketing',
   'fn_lead_sourcing_kick() every 10 minutes: one supplier lead sourcing batch in the marketing function.',
   'scripts/sql/the_invite_ramp_the_lead_sourcing_cron_and_the_ceo_label_name_their_seat.sql'),
  ('agent_runs_label', 'ceo', 'ceo',
   'Runs the chief executive seat logs under its own name.',
   'scripts/sql/the_invite_ramp_the_lead_sourcing_cron_and_the_ceo_label_name_their_seat.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

select case
  when (select count(*) from public.writer_seat o join public.org_role r on r.role_id = o.owner_seat and r.status = 'active'
         where (o.kind, o.name) in (('agent_runs_label', 'invite_ramp'), ('cron_job', 'lead_sourcing_batch'), ('agent_runs_label', 'ceo'))) <> 3
    then 'PROBE FAILED: not all three resolve to an active seat'
  when exists (select 1 from public.fn_writers_without_a_seat(7))
    then 'PROBE FAILED: writers without a seat remain: '
         || (select string_agg(kind || ':' || name, ', ') from public.fn_writers_without_a_seat(7))
  else 'PROBE OK' end as verdict;
