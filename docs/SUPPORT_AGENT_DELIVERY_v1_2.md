# Customer support agent — delivery report (v1.2 Full Autonomy)

Generated from the live database on 2026-09-07 by `scripts/checks/support_delivery_report.mjs`.
Every number here is read at run time. Nothing in this file is typed by hand, because a
hand-written status is accurate on the day it is written and misleading every day after.

## 1. The organisation

| role | title | status |
|---|---|---|
| `ceo` | Chief Executive (AI) | active |
| `customer_support` | Customer Support | active |

Reporting edge: `customer_support` → `ceo`, established by founder on 2026-09-07.

Active roles: **2**. Reporting edges: **1**.

## 2. Capability map, and what is actually verified

| capability | spec | state | asserted by |
|---|---|---|---|
| `fn_support_notify_new_quotation` | §3 new-quotation announcement | VERIFIED-LIVE | committed_quote_announced, draft_never_announced, supplier_name_absent_from_body |
| `fn_support_anonymity_scan` | §3 anonymity gate | VERIFIED-LIVE | scan_refuses_a_body_naming_the_supplier, outbox_refuses_an_unscanned_row |
| `fn_support_artifact_attachable` | §4 copy eligibility | VERIFIED-LIVE | unscanned_artifact_refused, stale_export_refused, oversized_falls_back_to_link, other_party_artifact_refused |
| `fn_support_deliver_artifact` | §4/§5 report and invoice delivery | VERIFIED-LIVE | approved_copy_is_attached, link_fallback_not_counted_as_delivery, link_message_never_says_attached |
| `fn_document_classify` | §6 one classifier for three paths | VERIFIED-LIVE | all_three_paths_use_one_classifier, portal_declared_type_beats_the_filename |
| `fn_support_receive_document` | §6 email and portal intake | VERIFIED-LIVE | email_path_files_the_licence, unclear_document_is_held_not_guessed, unstored_file_refused |
| `fn_wa_attach_document` | §6 WhatsApp intake | VERIFIED-LIVE | whatsapp_path_still_files |
| `fn_support_open_identity_challenge` | §7 identity challenge | VERIFIED-LIVE | code_goes_to_the_address_of_record, no_account_gives_the_same_answer, no_account_sends_no_mail |
| `fn_support_answer_identity_challenge` | §7 challenge answer | VERIFIED-LIVE | wrong_code_does_not_verify, correct_code_releases_the_held_document, a_used_code_cannot_be_replayed |
| `fn_licence_expiry_sweep` | §6 renewal chase | VERIFIED-LIVE | day_31_is_outside_the_window, day_30_is_the_first_day_asked, day_minus_1_is_expired |
| `fn_licence_ask_close_for_lead` | §15 obsolete reminders cancelled | VERIFIED-LIVE | email_arrival_stops_the_chase, portal_arrival_stops_the_chase, a_held_document_stops_nothing |
| `fn_support_investigate_refund` | v1.2 refund.inspect | VERIFIED-LIVE | settled_payment_is_eligible, pending_payment_is_not_a_refund_question, second_live_refund_prevented |
| `fn_ceo_decide_refund` | v1.2 CEO refund authority | VERIFIED-LIVE | decision_without_a_rationale_refused, deciding_twice_refused |
| `fn_refund_execute_authorized` | v1.2 refund.execute_authorized | VERIFIED-LIVE | execution_before_authorisation_refused, amount_mismatch_refused, currency_mismatch_refused, destination_is_derived_not_supplied |
| `fn_refund_read_status` | v1.2 refund.read_status | VERIFIED-LIVE | succeeded_still_owes_the_customer_a_message |
| `fn_case_record_verified_resolution` | v1.2 case.record_verified_resolution | VERIFIED-LIVE | case_cannot_close_over_a_moving_refund |
| `fn_ceo_request_decision` | v1.2 ceo.request_decision | VERIFIED-LIVE | ceo_decision_request_needs_a_recommendation, a_case_does_not_resolve_on_ceo_receipt |
| `fn_support_report_to_ceo` | §14 reporting edge | VERIFIED-LIVE | a_report_to_a_retired_role_is_refused, every_report_is_visible_in_the_ceo_queue |
| `fn_ceo_accept_support_report` | §14 acceptance | VERIFIED-LIVE | accepting_a_report_needs_a_receipt |
| `fn_support_open_reports` | §14 the CEO queue | VERIFIED-LIVE | a_report_is_not_closed_by_being_received |
| `fn_support_may_act` | v1.2 standing grant | VERIFIED-LIVE | ordinary_notification_is_covered_by_the_grant, an_unclassed_action_is_not_self_approved |
| `fn_founder_command_authenticate` | v1.2 authenticated commands | VERIFIED-LIVE | his_command_authenticates_from_his_number, a_stranger_typing_his_name_does_not |
| `fn_founder_command_admit` | v1.2 scope, sequence, idempotency | VERIFIED-LIVE | a_retry_is_the_same_command, an_older_instruction_cannot_reinstate |
| `fn_support_knowledge_search` | §10 knowledge retrieval | IMPLEMENTED | _no scenario asserts this_ |
| `fn_support_context` | §10 grounded answering | IMPLEMENTED | _no scenario asserts this_ |

**23 verified-live · 2 implemented but unasserted · 0 not deployed.**

The two unasserted rows are the knowledge-retrieval functions. They are exercised by the
retrieval evaluation rather than by the scenario harness, and are listed as IMPLEMENTED
here rather than borrowing the other evaluation's result.

## 3. Authority: the standing grant

| grant | action class | scope | limit | current |
|---|---|---|---|---|
| `support.document_intake` | document | Accept, quarantine, scan and file a supplier document arriving on any of the three intake paths. | Canonical verification decides validity; support records receipt, never approval. | yes |
| `support.notify` | notification | Send the deterministic quotation, report, invoice and licence notifications on either channel. | Anonymity scan must pass; the outbox CHECK enforces it. | yes |
| `support.refund_investigate` | refund | Investigate a refund request end to end: gather evidence, check settlement, entitlement and duplicates, and put a decision to the CEO service. | Investigation only. Execution requires a CEO refund decision; support never authorises its own. | yes |
| `support.reply` | conversation | Answer any customer or supplier message from live account facts and approved company knowledge. | No authority to change a price, an entitlement or a permission by conversation. | yes |

| constitution revision | final internal authority | founder approval required | founder escalation allowed |
|---|---|---|---|
| 1.2 | ceo | false | false |

Founder commands on record: **27**, of which **0** are in a non-terminal state.
Routes into `clarification_required`: **0**.
Commands claiming authentication with no basis behind it: **0**.

## 4. Knowledge ingestion

| corpus | records | indexed | carrying authority |
|---|---|---|---|
| support | 407 | 407 | 0 |
| CEO | 508 | 508 | 0 |

Authority must be zero in both. A retrieved record that can confer authority is the
injection route the spec names, and it is measured here rather than promised.

## 5. Channels — real statuses, with the reason

| channel | status | reason |
|---|---|---|
| `email_outreach_domain` | blocked | Not needed at the founder's volumes. A second domain is worth buying only if supplier invitations ever exceed roughly 50 a day, or if complaints appear on quotesdone.com. Kept in the policy so the arithmetic can price that option if the volume ever justifies i |
| `email_transactional_domain` | blocked | Founder set the volume at 10 a day for month one, rising 5 a day each month. That volume is safe. What is NOT yet safe is the list: 16,167 of 19,896 addresses have never been verified and the measured bounce on what was actually sent is 10%, five times the 2%  |
| `phone_call` | blocked | Still NO OPERATOR. The founder receives calls; he did not say he would make hundreds of outbound cold calls, and no seat in this company can dial a phone. The cap below is what one hired human would carry. |
| `whatsapp` | blocked | CORRECTED 7 Sep 2026 after reading Twilio's Content API directly. Ten templates ARE approved, including quotesdone_supplier_doc_expiry_en (21 Jul, UTILITY) which is exactly what the licence renewal flow needs, and quotesdone_supplier_quote_accepted_en (3 Sep)  |
| `email_partnership` | open | Founder ruling: one a day until the list of counterparties is finished. This is a finite pipeline of named organisations, not a rate channel, and one carefully written email a day to a chamber, an association or a distributor carries no meaningful domain risk. |
| `founder_direct_uae` | open | The founder receives and replies personally on +971509319355, by phone and on WhatsApp. Inbound from a supplier who chooses to make contact carries no platform risk and no consent question, because they initiated it. |
| `partnership_introduction` | open | The founder is the operator. An association will not take a meeting with software, but it will take one with the founder of a UAE company holding a DET licence. This is a finite set of maybe twenty to forty organisations, approached once and properly. |

## 6. Configuration, and the exact remaining setup blockers

| key | state |
|---|---|
| `founder_public_name` | set |
| `founder_public_phone` | set |
| `meta_access_token` | ABSENT — no row at all |
| `public_site_url` | set |
| `stripe_secret_key` | set |
| `twilio_wa_from` | set |

**Remaining setup values held only by the founder: `meta_access_token`.** These are recorded as capability limitations, not converted into an approval workflow.

## 7. Exposure

Support functions executable by `anon` or `authenticated`: **0** (must be 0).

## 8. Scenario results

Run `node scripts/checks/support_acceptance_scenarios.mjs`. It drives the live functions,
constraints and triggers inside transactions that end in a RAISE, so nothing survives the
run. A group that fails to RUN counts as a failure of every scenario in it, rather than
being quietly skipped — a harness that skips is a harness that always passes.

## 9. What is NOT verified here, stated plainly

- Whether the model answers an angry customer well, handles a mixed intent, or refuses an
  off-topic request gracefully. Those are properties of generated text. Everything
  structural underneath them is asserted; the text quality is not, and a harness claiming
  otherwise would be measuring the wrong subject.
- End-to-end delivery through Twilio and the email provider. The outbox is written and
  asserted; the provider leg is blocked by the channel policy above, for the reasons it
  states, and no scenario pretends otherwise.

