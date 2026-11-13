---
name: checkpoint-13-nov-evening-anonymity-workflow-guard
description: "CHECKPOINT 13 Nov 2026 evening — READ FIRST. The founder stopped the session at 99% weekly usage (ledger 1691). Nothing new went live after 07:30 UTC. Seven branches hold reviewed-or-fixed work for anonymity (1683), the paid-reveal workflow (1685, 1688) and the replay guard; this note says the head, the state and the next step of each."
metadata:
  type: project
  modified: 2026-11-13
---

# Checkpoint, 13 Nov 2026, 21:25 UTC

The founder's words (ledger 1691): "I think we need to wrap up the work. The weekly usage is 99%." The session stopped
four running reviews and released nothing further. Everything it knew is in
`docs/reports/session_13_nov_2026_anonymity_workflow_guard/` (all independent reviews in `REVIEWS.md`, every work order,
every hand-back, the incident report). The founder invites supplier friends from Monday 16 Nov 2026 (ledger 1646).

## Live on main (35f9cec60), deploy parity 79 of 79 at 07:40 UTC
#1996 the licence reader; #1997 and #1998 the Dropbox tree and the two real suppliers re-filed; #1999 the backup worker's
clock. Nothing was merged, deployed or applied after 07:30 UTC.

## Branches, in release order (none merged, none live)

| # | branch | head | state | next step |
|---|---|---|---|---|
| 1 | `sales_engineer-anonymity-text-and-doors-released-together` | c3ac7bdbd | two independent FINAL reviews + an independent check of the fixes; the check's corrections applied as its own tested diff; 13 deno suites pass (only the known tesseract test fails, as on main); offline gate was 15 PASS, 0 FAIL when the session stopped (log not finished) | re-run the gate on the tree merged with main; open the PR with `anonymity_release_pull_request_text.md`; merge; deploy `supplier_portal` first, then the other 21 functions named there; apply `scripts/sql/before_a_reveal_a_supplier_portal_title_is_the_trade_and_the_emirate.sql`; MANIFEST line, delete the pending notes; parity; read one live supplier portal page and one customer quotation PDF |
| 2 | `it_engineer-a-suppliers-certificate-is-written-in-time-and-never-silently-lost` | 8502c8d5a | fix author reports all ten review items done (`hand_backs/GUARD_FIX.md`); the SECOND independent review was stopped unfinished (`progress/guard_review2.md`, work order `work_orders/guard_review2.md`) | finish that review; add the incident report to `docs/reports/` on the branch if not yet on main; merge; deploy kyc, compliance_archive, supplier_api; apply `a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one.sql` |
| 3 | `accountant-a-payment-is-known-booked-and-timed-from-the-moment-it-is-paid` | ea9c25c62 | round 5 fixed the final review's five items and 6a–f (`hand_backs/W1_W2_FIX.md`); its independent review was stopped unfinished (`progress/w1_w2_review5.md`) | finish the review (`work_orders/w1_w2_review5.md`); release by `docs/runbooks/a_paid_reveal_release_13_nov_2026.md` on the branch |
| 4 | `sales_engineer-a-paid-request-is-closed-and-everyone-on-it-is-told` | 75f60e2d3 | small fix done, same unfinished review | after #1 is on main add to `customer_api/actions/inquiry_lifecycle.ts`: `,reveal_open_until` at the end of `cols` and `reveal_open_until: i.reveal_open_until ?? null,` in `mapRow`; apply its SQL AFTER the money files |
| 5 | `ceo-every-seat-reads-one-pool-and-every-hand-over-comes-back` | fd95e8711 | round 3 fixed eleven items and the founder's four tests (`hand_backs/W3_FIX.md`); third review stopped unfinished (`progress/w3_review3.md`) | finish the review (`work_orders/w3_review3.md`); it must answer who calls `fn_seat_reports_done` in live code; then wire the callers of the 3-argument `fn_agent_may_act` (it_engineer/index.ts, accountant/actions/refunds.ts, accountant/actions/seat.ts, sales_engineer/actions/operator.ts) to the subject-aware form, or no seat ever asks the CEO; applies after 3 and 4 |
| 6 | `sales_engineer-a-drawing-reaches-a-supplier-with-no-owner-no-area-no-map` | 1f08602b7 | round 3 done, three-stub tables in `hand_backs/F3_AUTHOR.md`; third review stopped unfinished (`progress/f3_review3.md`) | finish the review (`work_orders/f3_review3.md`); still unwired: customer_api `verify_released_file`, the customer's confirm step, `seed_terms` on the CAD and WhatsApp routes (until then every vector PDF file is held and only previews go) |
| 7 | `customer_support-the-journey-proof-is-the-documents` | ec73879d1 | the journey harness; six free rehearsals; the Stripe payment step never completed in the test browser | the founder said to ignore the payment step (ledger 1689); run journeys A, B, B2, C with models on only after 1–5 are live; caps USD 1.0, 1.2, 1.4, 2.0 are approved (1689) |

`it_engineer-a-paid-reveal-is-known-to-every-seat-with-a-step` (f5ce86f4d) holds the gaps check the workflow branches answer.

## Rules learned today that bind the next session
- NOTHING is rehearsed on production (the incident report is in the reports folder; the memory note lands with branch 2).
  SQL is executed on a local Postgres 16 built from the mirror; `work_orders/COMMON.md` has the working recipe.
- The machine restarted twice and killed agents: every agent works from a written work order, pushes small steps and
  writes a progress note. Reviews written before a restart were found later in the review log: read it before re-running.
- Every fix was sent back by its reviewer at least once today, including the session's own five. Do not merge on an
  author's word.
- At most 5 agents; opus for fixes and final reviews.

## Waiting on the founder
Told him and not yet answered: the 27 empty Dropbox folders (his "move them"); the refund wording contradiction in
`src/content/legal.json` (:35 against :5); the accountant's standing authority to return an overcharge (proposed AED 500);
moving AED 284.41 from account 1150 into cost; quotation validity 30 days (agreement) against 14 (system); no new
quotations after a paid reveal; moving Monday's 07:37 Dubai paid weekly journey to Sunday; switching on the CEO seat's
judgement; "Download my data" on his iPhone again; enforcing the 99 named-but-unchecked authority grants; whether the CEO
may allow a seat one out-of-grant action for 24 h (never money, personal data or a switch).
Security (ledger 1690, the "wfx-loot" GitHub campaign): the repository shows no sign of it; he was asked to check his
account's security log, tokens and installed apps, and to switch Actions off in the repository settings.

## Not started
The model-based second reader for text; sign-up speed (3.4–3.9 s after the e-mail code, budget 3 s);
`fn_customer_support_campaign_list_tick` timing itself out; the Customers tree in Dropbox.
