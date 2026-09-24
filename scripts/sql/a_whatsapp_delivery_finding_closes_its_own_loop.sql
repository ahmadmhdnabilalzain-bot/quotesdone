-- A WHATSAPP DELIVERY FINDING CLOSES ITS OWN LOOP ONCE IT CLEARS.
--
-- Assigned: it_engineer (originator of the it.finding handoff). 24 Sep 2026.
-- Finding: duty:handoff_sla:it.finding:customer_support:unclosed (IT notification 65901).
--
-- MEASURED, read-only against htdblwldjkcgjvmqkbeh, 24 Sep 2026:
--   handoff #58198 (it_engineer -> customer_support, it.finding, duty:whatsapp_delivery:no_final_status:whatsapp)
--   was answered the same second it was sent (22 Sep 14:46Z): customer_support said its playbook has no
--   deterministic remedy. The finding CLOSED at 22 Sep 21:31:05Z and has not reopened (one row for the key,
--   closed_at set). 29 s later fn_it_loop_reverify parked the handoff at awaiting_learning, because
--   fn_it_playbook_for('duty:whatsapp_delivery:...') returns nothing: it_playbook has no row whose prefix
--   covers the whatsapp_delivery duty, so fn_it_learning_from_playbook cannot fill it_incident #320
--   (cause, fix, regression_check all null) and trigger z62 keeps the loop open. It has waited since.
--
-- The auto-close already exists (fn_it_loop_reverify -> fn_it_learning_from_playbook -> fn_seat_handoff_complete)
-- and works for every class the playbook covers; the gap is only the missing class. This adds it, then
-- runs the reverify once so #58198 closes at apply rather than at the next hourly tick. The handoff_sla
-- duty closes the SLA finding on its next tick, when no handoff is late.
--
-- prevented by: scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs
--
--   node scripts/apply_sql.mjs scripts/sql/a_whatsapp_delivery_finding_closes_its_own_loop.sql --apply --ddl

insert into public.it_playbook (failure_class, issue_prefix, remedy, remedy_routine, not_automatable_reason, regression_check, typical_cause, added_by) values
  ('whatsapp_delivery', 'duty:whatsapp_delivery:', null, null,
   'A WhatsApp delivery fault is Twilio''s status callback (wa_status) or its 30-minute backstop poll going silent, or a real delivery failure rate; the remedy is a code or configuration change to that path, not a routine a seat can run.',
   'fn_it_whatsapp_delivery_health (IT duty whatsapp_delivery, hourly); scripts/sql/every_whatsapp_says_whether_it_arrived_probe.sql; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   'A WhatsApp message Twilio accepted had no final delivery report 24 hours after it was sent, so the delivery rate could not be trusted. Measured 22 Sep 2026: 1 of 4 accepted messages over 7 days (1 delivered, 1 read, 0 failed); the finding cleared the same day at 21:31Z and had not reopened by 24 Sep.',
   'it_engineer')
on conflict (failure_class) do update set issue_prefix = excluded.issue_prefix,
  not_automatable_reason = excluded.not_automatable_reason, regression_check = excluded.regression_check,
  typical_cause = excluded.typical_cause;

select public.fn_it_loop_reverify();

select case
  when (public.fn_it_playbook_for('duty:whatsapp_delivery:no_final_status:whatsapp')).failure_class is distinct from 'whatsapp_delivery'
    then 'PROBE FAILED: the playbook does not cover duty:whatsapp_delivery:'
  when exists (select 1 from public.agent_actions where id = 58198 and status <> 'done')
    then 'PROBE FAILED: handoff 58198 is still ' || (select status from public.agent_actions where id = 58198)
  else 'PROBE OK' end as verdict;
