W3_FIX hand-back. Branch ceo-every-seat-reads-one-pool-and-every-hand-over-comes-back: eed8432be -> fd95e8711, 5 commits, pushed. Nothing applied, deployed or rehearsed on production; prod reads were 2 light SELECTs; no model call (stub answers through fn_reason_held_resolve). LOCAL = PG16 /tmp/pg-w3-r3 with money ea9c25c62 + sales 75f60e2d3 (re-fetched at the end; both had moved); cluster and worktree removed. sql = scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql.
ITEMS (all DONE; each proved by an assertion in the probe, and each assertion killed its mutant: 16 of 16)
1 owed work seen: fn_handoff_owing_seat sql:587; fn_seat_pool_waiting sql:603 (NO ANSWER YET / YOU ARE LATE / Waiting on you, grouped by kind / ANSWERED FOR YOU). LOCAL flood: 500 supplier.applied give the SE one line, "500 hand-over(s) (500 event.act)". reveal.reconcile is owed by the accountant.
2 silent seat: matched with ~*; a "waiting" answer or no seat named means the receiver. Probe C; "the CEO seat to approve" resolves to ceo.
3 decisions open work: fix_now and chase open a ceo.order that stays open until the seat reports (fn_seat_reports_done; fn_ceo_orders_reported sql:1255). The report lands on the decision and files IT's re-verify. Escalation skips rows with ceo_decision before their date (sql:1370). LOCAL: 3 decisions, nothing bounced at +15 min or +5 h. A late order goes to the CEO.
4 escalation goes to the silent seat's superior; founder only when the CEO is silent. LOCAL: marketing silent -> ceo; CEO silent -> founder.
5 cap counts re-arms (plan.rearmed_at, sql:822). LOCAL day 2: 30 live, never above 30 (was 46).
6 no stall: create or replace trigger only. Dispatcher body is a no-op; its trigger is dropped later in the_department_dispatcher_trigger_goes_once_its_body_is_a_no_op.sql (+ pending note; refuses while the old body exists). lock_timeout 1500ms. Re-run DDL is guarded.
7 fn_ceo_fix_seats sql:880 and fn_ceo_finding_guard sql:898. A choice not offered decides nothing.
8 fn_pool_say reads detail.silence (sql:378), else "no seat has taken it".
9 probe makes room (asked_today+50) before case B.
10 seed: accountant hears payment.received, handoff.payment.received.sent, reveal.paid.sent, reveal.reconcile.sent. Money lines show first in the day.
11 the timeline prints evidence.reply on a pending answered row (sql:438) and on a done CEO decision.
FOUNDER'S TESTS (all HOLD, in the probe and in the LOCAL scenarios)
(a) supplier.approved carries approved_by (fn_emit_supplier_approved sql:1521, reads approval_decided_by): "sales_engineer: a supplier was approved: <co> (steel, Sharjah)". customer.verified fires once, at kyc terms acceptance (z41 trigger, sql:1538): verified_by "the platform", told_by customer_support. All 6 seats count both in their day; 0 hand-overs.
(b) Accountant's day: "a customer paid the reveal fee of AED 135.00 on request 1 (painting, Dubai)". The SE reads "reveal.reconcile to accountant -- answered: exception; waiting on ...".
(c) SE reads "YOU ARE LATE: knowledge.request #8 from customer_support". CS reads "NO ANSWER YET: sales_engineer owes ... (escalated to ceo)". The CEO is asked once.
(d) fn_agent_may_act 5-arg (sql:962): a refusal with route ceo_case_decision files a ceo.authority question to the CEO (who/what/why/facts) inside the cap. The answer is allow_once / refuse / ask_founder (fn_reason_apply_ceo__authority sql:1213), and allow_once is never possible on money above the limit, a person's data or a switch. ceo_grant_once is used once, for that subject only, and expires. A malformed answer grants nothing and is asked again. The cap holds.
(d) covers: code that calls the subject-aware form. NOT covered: today's TS callers (it_engineer, accountant refunds, SE operator) still use the 3-arg form, and nothing files for them. The 99 named-but-unchecked grants stay off; the 21 no-grant points have no rule.
CHAIN: step | seat | model/code | writes | read by
finding filed | ceo duty | code | held question (cap) | CEO's think()
decide | ceo | MODEL | evidence.ceo_decision + ceo.order/decision_closed | IT (timeline), ordered seat (Waiting on you)
report fix | seat | code (fn_seat_reports_done) | order done + reported_done + decision_closed to IT | IT, CEO's day
overdue | pool tick | code | detail.silence, overdue event | silent seat (YOU ARE LATE), sender (NO ANSWER YET), superior
chase/wait | ceo | MODEL | ceo.order to the silent seat | that seat; closes when the late row is answered
authority ask | seat | code | ceo.authority hand-over | CEO's think() -> MODEL -> grant row/reply | asking seat (ANSWERED FOR YOU)
verified | kyc / SE | code | customer.verified / supplier.approved(approved_by) | all seats' day and timeline
COUNTS: probe OK on 2 applies (148/129 ms) after money+sales x2. Sibling probes: note OK, sales OK; money main and 1150 need prod/ledger data (as before). Mutants 16/16. Node: pool check 8 pass + 1 skip (release rehearsal); handoff check 6/6; manifest 0 findings; canonical_routines, manifest_applies_at_merge 8/8, live_seat 7/7, apply_sql_signs 4/4. Gaps check 5 pass / 12 fail, unchanged and outside my scope (GAP 7 [ceo] needs the founder-brief line in the money file). Deno _shared+ceo_agent: 2275 pass, 1 fail (known catalogue_read tesseract), 1 ignored. Cost per write (LOCAL, unchanged): event 0.04->0.31 ms, hand-over 1.5-2.0->2.2-2.5 ms.
LOCKS (LOCAL pg_locks) | first apply | re-run
agent_actions, company_event, customers, seat_judgement | SHARE ROW EXCLUSIVE | same
event_subscription | ACCESS EXCLUSIVE (taken after the waiting locks) | SHARE ROW EXCLUSIVE
event_delivery | ACCESS EXCLUSIVE | none
new pool tables | ACCESS EXCLUSIVE (new tables) | SHARE UPDATE EXCLUSIVE
dispatcher-drop file | ACCESS EXCLUSIVE company_event | -
With a 4 s open agent_actions writer, the apply fails at 1.7 s and the worst event insert is 198 ms (first) / 54 ms (re-run); before, 1,584 ms.
FOUNDER DECIDES: (1) wire seats to ask the CEO (switch the 3 TS callers to the subject-aware form) and whether to enforce the 99 unchecked grants; (2) that the CEO may allow a seat ONE out-of-grant action for 24 h, but never money, personal data or a switch; (3) no seat verifies a customer by hand, kyc does: fine?
UNSURE: the probe writes 2 rolled-back storage.objects rows (the six-items gate needs them). fn_emit_supplier_approved is now also defined here (first owner event_emitters_five_missing_classes.sql). A re-apply after the drop file recreates a no-op trg_company_event_dispatch() with no trigger. Timeline lines cut at 160 chars. Model cost per question is 1 or 3 calls (unmeasured). The 3-arg fn_agent_may_act is executable by anon/authenticated in the mirror (not mine). Review item 11 of 11:39 (PK-defeating lookups) not done.
