-- THE SEVEN PARKED IT-FINDING FAMILIES OF 27 OCT EACH HAVE A PLAYBOOK CLASS WITH A MEASURED CAUSE.
--
-- Agent: it_engineer. 27 Oct 2026. Data only: seven it_playbook rows. No routine, no table, no handoff closed.
--
-- MEASURED (read-only, production htdblwldjkcgjvmqkbeh, 27 Oct 2026 ~19:30 UTC): 8 cleared it.finding handoffs sat
-- at awaiting_learning because no it_playbook prefix covers their issue key (the check
-- scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs is red on them):
--   99513   support_reply_sla:email                                   customer_support
--   100357  acct:charge_audit:charge:29ac49f5-1f4e-4dc5-989a-479143f7ac8c  accountant
--   122120  duty:org_task_queue:knowledge_gap:customer_support         customer_support
--   141261  invite_m365_lane_refused                                  ceo
--   149663  acct:expenses:no_document                                 accountant
--   150604  duty:expiry:tls:quotesdone.ae                             ceo
--   254305  duty:cost_watch:openrouter                                ceo
--   254960  duty:org_task_queue:knowledge_gap:sales_engineer           sales_engineer
--
-- EVERY typical_cause BELOW IS MEASURED FROM THAT INCIDENT'S OWN HISTORY, and says which occurrence it was read from:
-- the handoff's finding_evidence, it_engineer_finding (evidence, seen_count, started/closed, close_note),
-- it_finding_closure, and the rows the evidence names (inbound_messages 159-160, charge_audit, org_tasks and
-- sales_knowledge_gap, expense_entries, it_expiry). One reading is from outside the database: the certificate
-- quotesdone.ae serves, read over TLS on 27 Oct (Let's Encrypt, notBefore 2026-10-11 12:57:33Z, notAfter
-- 2027-01-09 12:57:32Z). Where a part of a cause could not be measured the text says "not established".
-- A class covers the family; its cause describes the occurrences measured, not every future one.
--
-- WHAT THIS DOES NOT DO: close any handoff (fn_it_attach_learning does that, per handoff, when its incident carries a
-- cause, a fix and a check), write any finding, or change an existing class (on conflict do nothing).
--
-- Prevented by: scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs, the verdict
-- row at the end of this file, and its probe
-- scripts/sql/the_seven_parked_it_finding_families_of_27_october_each_have_a_measured_playbook_class_probe.sql.
--   node scripts/apply_sql.mjs scripts/sql/the_seven_parked_it_finding_families_of_27_october_each_have_a_measured_playbook_class.sql --apply --ddl --seat it_engineer

insert into public.it_playbook (failure_class, issue_prefix, remedy, remedy_routine, not_automatable_reason, regression_check, typical_cause, added_by) values
  ('support_first_reply_late', 'support_reply_sla:', null, null,
   'Each occurrence is read: a real customer message is answered by customer_support on its own channel; a sender nobody can answer (an automated no-reply address) is exempted in fn_support_reply_watch_tick, never answered for the sake of the clock.',
   'fn_support_reply_watch_tick re-raises support_reply_sla:<channel>; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   'Measured on the one occurrence (handoff 99513, 24 Sep - 23 Oct 2026): the 2 email messages counted (inbound_messages 159 and 160, 23 Sep 17:23Z and 17:26Z, to info@) were automated LinkedIn "Verify your business email address" mails from a security-noreply sender, which no one can answer. The no-reply exemption added 19 Oct matches only a sender local part that BEGINS with no-reply, so security-noreply stayed counted. The key closed 23 Oct 17:46Z because both messages left the watch''s 30-day window, not because they were answered: replied_at is still null on both.',
   'it_engineer (27 Oct 2026)'),
  ('charge_off_formula', 'acct:charge_audit:', null, null,
   'A LIVE-mode charge off the reveal formula is a pricing or fee-basis defect: the accountant corrects it and refunds an overcharge on the CEO''s approval. A Stripe TEST-mode charge moves no money; its audit stays in charge_audit and is not raised.',
   'fn_accountant_charge_audit_record re-raises acct:charge_audit:charge:<transaction>; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   'Measured on the one occurrence (handoff 100357, reveal 29ac49f5, 24 Sep - 19 Oct 2026, 544 sightings): a Stripe TEST-mode charge (livemode false) for a demo customer''s reveal, paid through the Checkout Session flow with no fee_basis on the payment and so priced at the international basis: AED 816.37 charged against the formula''s AED 777.60 (3% of AED 25,920), the AED 38.77 difference recorded as absorbed Stripe processing cost. The key closed 19 Oct 04:30Z when #1496 stopped the charge audit raising test-mode charges. charge_audit holds that one row (resolved_at null) and no live-mode charge has been audited.',
   'it_engineer (27 Oct 2026)'),
  ('org_task_queue_stuck', 'duty:org_task_queue:', null, null,
   'A queued task the consumer cannot finish is read for what it waits on; when the record it points at already carries the answer, fn_org_task_consume_tick closes it from that record (fact_close), and a consumer that keeps answering not_yet against a judged record is a defect in the consumer.',
   'fn_org_task_consume_tick re-raises duty:org_task_queue:<class>:<seat>; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   'Measured on the two occurrences that parked (handoff 122120, customer_support, 30 Sep: 1 task; handoff 254960, sales_engineer, 14-18 Oct: 27 tasks): all 28 were knowledge_gap tasks whose sales_knowledge_gap record had already been judged not_a_gap, while the consumer kept answering not_yet ("the question waits for the sales engineer''s reasoning") for up to 33 attempts. The judgement sat on the gap ledger and was never carried back to the queue. fn_org_task_consume_tick closed all 28 by fact_close on 19 Oct 2026 between 05:45Z and 17:15Z. 20 of the 27 sales_engineer tasks were ZZ DEMO questions. The occurrences open on 25 and 27 Oct were not read for this cause.',
   'it_engineer (27 Oct 2026)'),
  ('invite_m365_lane_refused', 'invite_m365_lane_refused', null, null,
   'A refused app credential is replaced at the Microsoft Entra application by its owner; nothing in the estate can mint it. send_outbox closes the finding on the first sendMail Graph accepts.',
   'supabase/functions/send_outbox/m365_lane.ts raises and closes invite_m365_lane_refused; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   'Measured on the one occurrence (handoff 141261, 5 - 20 Oct 2026): Microsoft''s token endpoint refused the invitation lane''s app credentials (HTTP 401, invalid_client) although MS_TENANT_ID, MS_CLIENT_ID and MS_CLIENT_SECRET were all set, so supplier_invite, supplier_invite_seed and supplier_invite_nudge were held (never sent through Resend; all other mail unaffected). It cleared 20 Oct 04:31Z when Graph sendMail accepted a message (HTTP 202). What changed the credential is not established: production records no it_credential_rotation row for it.',
   'it_engineer (27 Oct 2026)'),
  ('expense_without_document', 'acct:expenses:', null, null,
   'A booked expense with no receipt is matched by the accountant''s sweep when the receipt is forwarded to the expenses mailbox; an entry for which no document can exist (a measured accrual, or a payment the founder documented by statement) is exempted by its source in fn_accountant_expense_duty.',
   'fn_accountant_expense_duty re-raises acct:expenses:no_document; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   'Measured on the one occurrence (handoff 149663, 7 - 19 Oct 2026, 1 entry at the handoff growing to 12): every undocumented entry (expense_entries 1438-1728, AED 0.27 to 85.88, charged 7-18 Oct) had source accountant:openrouter_daily, the accountant''s own daily accrual of OpenRouter usage, for which no per-day receipt exists. The key closed 19 Oct 04:30Z when #1496 stopped the expenses duty counting that source; the 12 entries still carry no document.',
   'it_engineer (27 Oct 2026)'),
  ('expiry_inside_warning', 'duty:expiry:', null, null,
   'A date inside its warning is checked against the thing in service before anyone renews: a stale reading is fixed in the reader (supabase/functions/_shared/it_duty_readings.ts), a real expiry is renewed by the item''s owner by its it_expiry route.',
   'fn_it_expiry_measured re-raises duty:expiry:<item>; supabase/functions/_shared/it_duty_readings.test.ts; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   'Measured on the one occurrence (handoff 150604, tls:quotesdone.ae, 10 - 27 Oct 2026, 311 sightings): the reading, from crt.sh, gave the certificate as expiring 2026-11-09, inside the 30-day warning, from 10 Oct 16:01Z. The certificate quotesdone.ae serves was issued 11 Oct 12:57Z (Let''s Encrypt, valid to 2027-01-09, read over TLS on 27 Oct), so from 11 Oct the finding was a stale reading, not an unrenewed certificate. The reading moved to 2027-01-09 and the key closed 27 Oct 05:16Z. Why the TLS-handshake reading (#1496, on main 19 Oct) first took effect then is not established.',
   'it_engineer (27 Oct 2026)'),
  ('model_spend_rise', 'duty:cost_watch:', null, null,
   'A rise is explained, never capped (founder rule: the watch never blocks). The seat named in the top rise decides whether that model use is justified; the cost_watch duty closes the finding when a 7-day window no longer rises over the one before.',
   'fn_it_cost_watch_tick re-raises duty:cost_watch:<provider>; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   'Measured on the one occurrence (handoff 254305, openrouter, 13 - 27 Oct 2026): OpenRouter spend in ai_cost_log rose week on week from AED 0.00 to 58.73 (top rise: conversation_reply with no seat named, on anthropic/claude-sonnet-5.5, AED 0.00 to 28.02), and at its last breach from AED 58.73 to 393.82 (top rise: ceo internal_judgement on anthropic/claude-opus-5.5, AED 6.74 to 148.46). The key closed 27 Oct 10:16Z when the cost_watch duty no longer found a rise, 14 days after it opened.',
   'it_engineer (27 Oct 2026)')
on conflict (failure_class) do nothing;

select case
  when exists (select 1 from public.agent_actions a
                where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status in ('pending', 'failed')
                  and a.detail ? 'awaiting_learning'
                  and not exists (select 1 from public.it_playbook b
                                   where left(a.detail->>'issue_key', length(b.issue_prefix)) = b.issue_prefix))
    then 'PROBE FAILED: a parked it.finding handoff still has no playbook class'
  when (select count(*) from public.it_playbook
         where failure_class in ('support_first_reply_late', 'charge_off_formula', 'org_task_queue_stuck', 'invite_m365_lane_refused',
                                 'expense_without_document', 'expiry_inside_warning', 'model_spend_rise')
           and added_by = 'it_engineer (27 Oct 2026)' and typical_cause like 'Measured on %') <> 7
    then 'PROBE FAILED: a class is missing, was already there with other content, or carries no measured cause'
  else 'PROBE OK' end as verdict;
