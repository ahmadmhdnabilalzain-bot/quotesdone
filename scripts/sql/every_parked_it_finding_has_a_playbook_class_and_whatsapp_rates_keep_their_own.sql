-- EVERY PARKED IT FINDING HAS A PLAYBOOK CLASS, AND THE WHATSAPP RATE ITEMS KEEP THEIR OWN WAIT.
--
-- Agent: it_engineer. 29 Sep 2026. Two production checks failed on origin/main 55beee5.
--
-- MEASURED (read-only, production htdblwldjkcgjvmqkbeh, 29 Sep 2026)
--   1. a_cleared_whatsapp_finding_closes_its_handoff: fn_it_playbook_for('duty:whatsapp_delivery:failure_rate:whatsapp')
--      answered 'whatsapp_delivery', so the no-final-report cause would be written onto a failure-rate incident.
--      Two files own the one row: a_cleared_whatsapp_delivery_finding_closes_its_handoff_from_the_playbook.sql
--      (MANIFEST 1795) narrowed the prefix to 'duty:whatsapp_delivery:no_final_status:' on review, and
--      a_whatsapp_delivery_finding_closes_its_own_loop.sql (MANIFEST 1797, applied after it) set it back to
--      'duty:whatsapp_delivery:' with the same failure_class, so the later file won and the review finding returned.
--   2. a_cleared_it_finding_never_parks_for_want_of_a_playbook_class: seven cleared it.finding handoffs sat at
--      awaiting_learning because no it_playbook prefix covered their key at all:
--        96965  duty:integration:twilio_whatsapp_sender          (customer_support)
--        99514  duty:delivery:request:80605, 100813 ...:100464   (customer_support)
--        100470 watch:run_silent:ai_gateway                      (ceo)
--        100487 watch:refusal_rate:claim_lookup, 100488 ...:supplier_portal (sales_engineer)
--        100653 seat_duty:sales_engineer.supplier_performance    (sales_engineer)
--
-- WHAT THIS DOES
--   * whatsapp_delivery goes back to the no_final_status prefix it was reviewed for, and a second class,
--     whatsapp_delivery_other, covers the rest of the duty's keys WITHOUT a typical_cause: failure_rate:* and
--     status_unreadable:* are covered (never parked for want of a class) and keep waiting for their own learning
--     (fn_it_playbook_for returns no class while the cause is empty - the gate doing its job).
--   * one class per uncovered key family, each naming what the IT engineer actually does and why a seat cannot run
--     it as a routine. None is given a typical_cause: no cause has been measured for these families, and a cause is
--     recorded only when one is (fn_it_attach_learning), never invented to close a loop.
--
-- Prevented by: scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs,
-- scripts/checks/a_cleared_whatsapp_finding_closes_its_handoff.test.mjs and the verdict row at the end of this file.
--   node scripts/apply_sql.mjs scripts/sql/every_parked_it_finding_has_a_playbook_class_and_whatsapp_rates_keep_their_own.sql --apply --ddl --seat it_engineer

begin;

update public.it_playbook set issue_prefix = 'duty:whatsapp_delivery:no_final_status:'
 where failure_class = 'whatsapp_delivery';

insert into public.it_playbook (failure_class, issue_prefix, remedy, remedy_routine, not_automatable_reason, regression_check, typical_cause, added_by) values
  ('whatsapp_delivery_other', 'duty:whatsapp_delivery:', null, null,
   'A WhatsApp failure rate or an unreadable status is a real delivery fault at Twilio or Meta, or a change to the wa_status callback path; it has a cause of its own to measure and no routine a seat can run.',
   'fn_it_whatsapp_delivery_health (IT duty whatsapp_delivery, hourly); scripts/checks/a_cleared_whatsapp_finding_closes_its_handoff.test.mjs',
   null, 'it_engineer'),
  ('integration_down', 'duty:integration:', null, null,
   'An integration the probe reads as down (a provider, a sender, a key) is restored at the provider or by rotating its credential; the integration duty re-probes every tick and closes the finding itself when the provider answers healthy.',
   'the IT integration duty (edge_health_probe, one row per probe); scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer'),
  ('delivery_request_unconfirmed', 'duty:delivery:request:', null, null,
   'A delivery request with no confirmed outcome is answered by the seat that owns the send (the outbox, a provider callback); the delivery duty closes the finding when it no longer finds the request.',
   'the IT delivery duty (it_engineer.delivery); scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer'),
  ('run_silent', 'watch:run_silent:', null, null,
   'A subject that stopped running is restarted where it runs (a cron job, an edge tick, a provider hold); the silence watch measures the gap against the subject''s own cadence and clears when it runs again.',
   'fn_it_detect (detector run_silent); scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer'),
  ('refusal_rate', 'watch:refusal_rate:', null, null,
   'A surface refusing most of its callers is either a guard doing its job or a broken path; which one is decided by reading the refusals, and the fix is a code or configuration change to that surface.',
   'fn_it_detect (detector refusal_rate); scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer'),
  ('seat_duty_failing', 'seat_duty:', null, null,
   'A seat duty that fails every run is a defect in its routine (fn_seat_duties_tick records the error); the fix is a change to that routine by the seat that owns it, after which the next run clears the finding.',
   'fn_seat_duties_tick; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer')
on conflict (failure_class) do update set issue_prefix = excluded.issue_prefix,
  not_automatable_reason = excluded.not_automatable_reason, regression_check = excluded.regression_check;

commit;

select case
  when (public.fn_it_playbook_for('duty:whatsapp_delivery:no_final_status:whatsapp')).failure_class is distinct from 'whatsapp_delivery'
    then 'PROBE FAILED: the no-final-report cause no longer covers its own key'
  when (public.fn_it_playbook_for('duty:whatsapp_delivery:failure_rate:whatsapp')).failure_class is not null
    then 'PROBE FAILED: a failure-rate incident inherits a cause that is not its own'
  when exists (select 1 from public.agent_actions a
                where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status in ('pending', 'failed')
                  and a.detail ? 'awaiting_learning'
                  and not exists (select 1 from public.it_playbook b
                                   where left(a.detail->>'issue_key', length(b.issue_prefix)) = b.issue_prefix))
    then 'PROBE FAILED: a parked it.finding handoff still has no playbook class'
  else 'PROBE OK' end as verdict;
