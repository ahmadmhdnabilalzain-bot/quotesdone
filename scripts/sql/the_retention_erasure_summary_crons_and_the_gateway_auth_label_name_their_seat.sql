-- THE RETENTION, ERASURE AND SUMMARY CRONS AND THE GATEWAY-AUTH RUN LABEL NAME THEIR SEAT.
--
-- Assigned: it_engineer — the ownership register public.writer_seat is its (every_run_label_and_cron_job_names_its_seat.sql).
-- Founder rule, 7 Sep 2026: "no job/task should exist if it doesnt belong to an agent".
--
-- MEASURED 7 Oct 2026 01:30 UTC on production (wiring audit, ledger 1162): fn_writers_without_a_seat(7)
-- returned four writers with no seat, so scripts/checks/every_run_label_and_cron_job_names_its_seat.test.mjs
-- is red against production:
--   cron_job conversation_retention_daily        (6 Oct, file header "Assigned: it_engineer")
--   cron_job pdpl_erasure_daily                  (6 Oct, file header "Assigned: it_engineer")
--   cron_job inquiry_conversation_summary_daily  (6 Oct, file header "Assigned: sales_engineer")
--   agent_runs_label llm_gateway_auth (8 runs)   (supabase/functions/_shared/llm.ts, the gateway credential fallback)
-- The three crons were added on 6 Oct with their seat in prose only; the register never learned them.
-- CHANGE: each is registered under the seat its own file names; llm_gateway_auth under it_engineer,
--   which owns model spend and credential health (seat_duty it_engineer.model_spend / credential_rotation_age).
-- NOT CHANGED: the jobs keep their cron schedules (retention purges in batches of 500 at 23:20 UTC; moving
--   them onto the seat clock would change when a delete runs, which is a separate decision).
-- prevented by: scripts/checks/every_run_label_and_cron_job_names_its_seat.test.mjs (already present; red before this file)

insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'conversation_retention_daily', 'it_engineer',
   'fn_conversation_retention_purge(500) daily 23:20 UTC: conversation text removed five years after the account goes quiet.',
   'scripts/sql/the_retention_erasure_summary_crons_and_the_gateway_auth_label_name_their_seat.sql'),
  ('cron_job', 'pdpl_erasure_daily', 'it_engineer',
   'fn_pdpl_tick() daily 23:50 UTC: carries out data-subject erasure requests where no law requires the data kept.',
   'scripts/sql/the_retention_erasure_summary_crons_and_the_gateway_auth_label_name_their_seat.sql'),
  ('cron_job', 'inquiry_conversation_summary_daily', 'sales_engineer',
   'fn_inquiry_conversation_summary_run(50) daily 23:40 UTC: structured summary of a closed, 90-day-quiet inquiry (ledger 1127).',
   'scripts/sql/the_retention_erasure_summary_crons_and_the_gateway_auth_label_name_their_seat.sql'),
  ('agent_runs_label', 'llm_gateway_auth', 'it_engineer',
   'llm.ts gatewayCredential fallback: records when the model gateway answered with a fallback credential.',
   'scripts/sql/the_retention_erasure_summary_crons_and_the_gateway_auth_label_name_their_seat.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

select case
  when exists (select 1 from public.fn_writers_without_a_seat(7))
    then 'PROBE FAILED: writers without a seat remain: '
         || (select string_agg(kind || ':' || name, ', ') from public.fn_writers_without_a_seat(7))
  else 'PROBE OK' end as verdict;
