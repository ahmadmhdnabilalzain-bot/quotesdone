-- A CLEARED WHATSAPP-DELIVERY FINDING CLOSES ITS HANDOFF FROM THE PLAYBOOK (24 Sep 2026; seat: it_engineer, for customer_support).
--
-- Founder, 14 Sep 2026 (instruction 207): "nothing literally should ever be a one way communication". GAPS.md
-- (24 Sep, customer support gap 5): an it.finding handoff to customer_support was answered but never closed.
--
-- MEASURED (24 Sep 2026, production, read-only):
--   * it_engineer_finding duty:handoff_sla:it.finding:customer_support:unclosed, seen 31 times, names handoff
--     #58198 (22 Sep 18:46 Dubai): "1 whatsapp message(s) sent over 24 hours ago have no delivery report from
--     Twilio", issue key duty:whatsapp_delivery:no_final_status:whatsapp.
--   * That finding CLOSED on 22 Sep 21:31 UTC, and no WhatsApp/SMS row with a Twilio SID sent in the last 7 days is
--     now without a final status. customer_support replied inside its window.
--   * The handoff is still pending because fn_it_loop_reverify parked it at awaiting_learning: its it_incident
--     (#320) has no cause, fix or regression_check, and it_playbook has NO row whose issue_prefix covers
--     duty:whatsapp_delivery: -- so fn_it_learning_from_playbook returns null and the handoff waits for a human
--     that no clock or addressee ever reaches. The same trap holds for duty:sender:template: (whatsapp_template has
--     no typical_cause), which parks the four template handoffs #48400-#48403 the day their templates are approved.
--
-- WHAT THIS CHANGES: the playbook learns the two WhatsApp classes, each with a cause written from the measurement
-- in the file that built its detector. On its next tick fn_it_loop_reverify (unchanged) fills incident #320 from
-- the row, closes #58198, and duty:handoff_sla:it.finding:customer_support:unclosed clears on the hour after.
-- Nothing is closed by id or by hand: the loop that owns the close does it.
--
-- WHAT THIS DOES NOT CHANGE: the four template findings stay OPEN -- Meta still reports the templates 'received'
-- (not approved), which is instruction 859's outstanding business-initiated template test, not a code fault.
--
-- Prevented by: scripts/checks/a_cleared_whatsapp_finding_closes_its_handoff.test.mjs (both classes carry a cause, and in an
-- aborted transaction the reverify loop closes a parked ZZ DEMO handoff of this class) and the verdict row below.
--   node scripts/apply_sql.mjs scripts/sql/a_cleared_whatsapp_delivery_finding_closes_its_handoff_from_the_playbook.sql --apply --ddl

insert into public.it_playbook (failure_class, issue_prefix, remedy, remedy_routine, not_automatable_reason, regression_check, typical_cause, added_by) values
  ('whatsapp_delivery', 'duty:whatsapp_delivery:',
   'customer_support owns the send; the finding closes itself when every Twilio-accepted message has a final report (wa_status callback or its 30-minute backstop poll, fn_twilio_status_poll_claim) or is marked unreadable, and a failed one comes back to the seat that asked as failed with Twilio''s code in plain words.',
   null, null,
   'scripts/checks/every_twilio_send_reports_its_status.test.mjs, with scripts/sql/every_whatsapp_says_whether_it_arrived_probe.sql',
   'A WhatsApp or SMS that Twilio accepted had no final delivery report 24 hours later. Measured 22 Sep 2026 (every_whatsapp_says_whether_it_arrived.sql): the sender had no status callback and nothing polled a message''s status; after the callback and the backstop poll were added, the one message found this way got its report within hours and the finding closed at 21:31 UTC. A message still without a report is either still in flight at Meta or unreadable, which is raised separately as status_unreadable.',
   'it_engineer')
on conflict (failure_class) do update set issue_prefix = excluded.issue_prefix, remedy = excluded.remedy,
  regression_check = excluded.regression_check, typical_cause = excluded.typical_cause;

-- whatsapp_template exists (the_it_engineer_playbook_knows_what_duties_19_to_24_find.sql) with its not-automatable
-- reason and no cause; only the cause is added, nothing it already says is rewritten.
update public.it_playbook
   set typical_cause = 'A WhatsApp template was not in the approved state. Measured 22-24 Sep 2026: login_code_en/ar and supplier_account_notice_en/ar were reported by Twilio Content as received, i.e. submitted and awaiting Meta''s review; a business-initiated template cannot be sent until Meta approves it (instruction 859).'
 where failure_class = 'whatsapp_template' and coalesce(btrim(typical_cause), '') = '';

-- Verdict row (read-only; this file defines no routine, so nothing to roll back).
select case
  when (public.fn_it_playbook_for('duty:whatsapp_delivery:no_final_status:whatsapp')).failure_class is distinct from 'whatsapp_delivery'
    then 'PROBE FAILED: the whatsapp_delivery class does not cover its own issue key'
  when (public.fn_it_playbook_for('duty:sender:template:login_code_ar')).failure_class is distinct from 'whatsapp_template'
    then 'PROBE FAILED: the whatsapp_template class does not cover its own issue key'
  else 'PROBE OK' end as verdict;
