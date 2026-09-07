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
| `fn_support_knowledge_search` | §10 knowledge retrieval | VERIFIED-LIVE | retrieval eval: 48/48 coverage, 0 evaluation leakage |
| `fn_support_context` | §10 grounded answering | VERIFIED-LIVE | retrieval eval: 48/48 coverage, 0 evaluation leakage |

**25 verified-live · 0 implemented but unasserted · 0 not deployed.**

The two retrieval functions are asserted by a different measure — coverage and leakage
across the 48 disclosed development scenarios — and the column says so, because a reader
should be able to see WHICH evidence stands behind a row rather than assume it is the same
as the row above. What that evaluation does NOT measure is whether the retrieved guidance
is the RIGHT guidance: the support scenarios ship no related_modules, so there is no ground
truth to score precision against, and inventing one would measure my expectations.

Reproduce with: `node scripts/kb/support_knowledge_retrieval_eval.mjs --scenarios <pack>/evaluation/scenarios.jsonl`

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
| `twilio_auth_token` | set |
| `twilio_wa_from` | set |

**Remaining setup values held only by the founder: `meta_access_token`.** These are recorded as capability limitations, not converted into an approval workflow.

### An MCP connection is not a runtime credential

The founder has Meta and Twilio connected in his Claude settings, and it is worth being
exact about what that does and does not settle, because the two connections are not the
same kind of thing and neither one closes the row above.

- **Meta** is a live account connection. Measured 7 Sep 2026: ad account `10151242677262668`
  (Ahmad Zain), ACTIVE, payment method on file, AED, minimum daily budget AED 3.69.
- **Twilio** is documentation search only — it queries docs and API schemas, not the
  account. It cannot yield the account auth token, so the signature-validation limitation
  in section 10 stands unchanged.

And the part that matters more than either: an MCP connection is authenticated as a
SESSION on the founder's desktop. A Supabase cron job firing at 03:00 cannot reach it, and
neither can an edge function. So Meta is reachable by an agent working beside him, and
still absent from the unattended runtime — which is the thing this build is for. Recording
the connection as though it satisfied `meta_access_token` would be the same error as a
credential that works in every environment except production.

## 7. Runtime state — held, not broken

Scheduled jobs: **1**, of which **0** are active.
Present: `wa_flush`. Failures in the last 24h: **6**.

This is the founder's 7 September instruction, not an outage: every job not owned by an
agent was deleted, and the WhatsApp agent's own jobs were kept and put on hold while the
build runs. An estate with no active job looks exactly like one that has fallen over, and
the whole difference is whether somebody asked for it — so it is reported with the reason.

Recovery is `update cron.job set active = true` on the held job, when he lifts the hold.
Any failures counted above are worth reading: during the deletion sweep this job failed six
times against a role that had just been removed, and stopped once nothing referenced it.

## 8. Exposure

Support functions executable by `anon` or `authenticated`: **0** (must be 0).

## 9. Scenario results

**112 scenarios defined across eleven groups, of which 81 are marked critical.**
This file counts them; it does not run them, so it reports none of them as passing.

Run `node scripts/checks/support_acceptance_scenarios.mjs`. It drives the live functions,
constraints and triggers inside transactions that end in a RAISE, so nothing survives the
run. A group that fails to RUN counts as a failure of every scenario in it, rather than
being quietly skipped — a harness that skips is a harness that always passes.

## 10. What is NOT verified here, stated plainly

- Whether the model answers an angry customer well, handles a mixed intent, or refuses an
  off-topic request gracefully. Those are properties of generated text. Everything
  structural underneath them is asserted; the text quality is not, and a harness claiming
  otherwise would be measuring the wrong subject.
- End-to-end delivery through Twilio and the email provider. The outbox is written and
  asserted; the provider leg is blocked by the channel policy above, for the reasons it
  states, and no scenario pretends otherwise.
- ~~Cryptographic proof of webhook origin~~ — RESOLVED. `twilio_auth_token` is stored, so
  `wa_inbound` now validates `X-Twilio-Signature` by HMAC-SHA1 with a constant-time
  comparison instead of falling back to the REST provenance lookup. A forged webhook now
  fails on proof rather than on a lookup. No code changed; the credential was the whole
  difference. Note it was supplied through a channel that saw the value, so rotating it
  (Console → API keys & tokens → request a secondary token → promote) is worth doing.

