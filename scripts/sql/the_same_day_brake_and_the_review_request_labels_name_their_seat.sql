-- THE SAME-DAY BRAKE AND THE REVIEW-REQUEST LABELS NAME THEIR SEAT (10 Nov 2026, it_engineer).
--
-- MEASURED on production, 10 Nov 2026 (read-only): public.fn_writers_without_a_seat(7) returned two agent_runs labels
-- that no function_owner row, seat_duty and writer_seat row resolves, so every_run_label_and_cron_job_names_its_seat
-- failed on origin/main:
--   * invite_same_day_brake, 1 run (4 Nov 07:30 UTC): fn_invite_same_day_brake() calls
--     fn_invite_campaign_pause('invite_same_day_brake', ...), which logs the pause under its source. The brake is the
--     supplier invitation campaign's own guard (an_invitation_bounce_or_complaint_spike_stops_the_campaign_the_same_hour.sql,
--     marketing, ledger 993); the campaign's other labels (supplier_invites, invite_ramp) are already marketing's.
--   * review_request, 55 runs (2 Nov - 10 Nov): supabase/functions/_shared/review_request.ts logs a suppressed
--     review intake (status 'skipped'). Its header: "Seat: ceo; the intake is customer_support's" (founder ledger 1152);
--     ceo_agent's review_requests action runs it.
--
-- WHAT THIS CHANGES: two writer_seat rows. Nothing else: no routine, no table, no grant. Idempotent (on conflict).
-- WHAT THIS DOES NOT CHANGE: what either writer does or logs.
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('agent_runs_label', 'invite_same_day_brake', 'marketing',
   'fn_invite_same_day_brake -> fn_invite_campaign_pause(''invite_same_day_brake''): a bounce or complaint spike stops the day''s supplier invitations the same hour (ledger 993).',
   'scripts/sql/the_same_day_brake_and_the_review_request_labels_name_their_seat.sql'),
  ('agent_runs_label', 'review_request', 'ceo',
   'supabase/functions/_shared/review_request.ts: a request to review an automated decision enters fn_review_request_open (ledger 1152); a suppressed intake is logged skipped.',
   'scripts/sql/the_same_day_brake_and_the_review_request_labels_name_their_seat.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;
