W3 (ceo), second iteration: done, pushed to `ceo-every-seat-reads-one-pool-and-every-hand-over-comes-back` (8befcb5e2 + eed8432be). Nothing applied, deployed or rehearsed on production; reads were light, time-bounded SELECTs. The Postgres 16 cluster (/tmp/pg-w3-author, port 55453) and the worktree are deleted.

**Results (LOCAL = PG16 from the mirror; READ = code; SELECT = prod read)**
- LOCAL: file + probe answer PROBE OK. All 10 mutants caught: the reviewer's M1, M2, M3a, M3b, M4, M5, plus N1 (decides nothing), N2 (escalation to nobody), N3 (rival in a supplier's block), N4 (seed wipe).
- Checks: `every_seat_reads_one_pool` 8 pass, 1 skip (the release rehearsal); `every_report_and_handoff_comes_back` 6/6; manifest 0 findings.
- Deno: 164 pass (seat_pool, ceo_judges_it_findings, think*, ai_reply*, support_reply*, ceo_agent).
- Gaps check: 5 hold, 12 gaps, none of them in my scope.
- `decision_points_are_reasoned` without a token fails identically with my changes stashed: 7 pass, 13 fail.
- With the token, earlier in this session, it ran: 18 pass, 2 fail. Its production tests run aborted transactions, so I did not repeat it.

**1. The CEO decides**
- `fn_ceo_takes_it_finding` replaces the CEO's code acknowledgement. It answers only "waiting: ceo judgement".
- Duty `ceo.company_pool` files 5 a tick, most severe and oldest first, as held questions; the existing replay runs think().
- `ceo.it_finding` choices: fix_now:<seat> (7 days), accept_risk (asked again in 14 days), duplicate_of:<id>, needs_founder:{money | destructive_production_change | fact_only_he_holds}.
- `ceo.overdue_handoff` choices: chase / wait / needs_founder.
- Prompt: "IT finding #N: '<title>' (<severity>, open since, seen N times). As CEO, decide what happens next and give the reason", with the finding's evidence and the pool block.
- Model: the routine route via `EASY_DUTY_SURFACE`, not the Opus route; not gated on `ceo_model_slot`. Model hold and demo rules apply.
- Where it lands: the decision is written on the hand-over (`evidence.ceo_decision`), and the it_engineer's next step is filed as `ceo.decision_closed`.
- An invalid answer or no answer decides nothing, and the finding is asked again the next day.
- Cap is data (`decision_policy.ceo_daily_judgements`): 30 a day, AED 0.50.
- Cost: AED 0.0106 per call (SELECT: 561 CEO routine calls, 30 days), 1 call per finding → AED 0.32/day at the cap, ~AED 2.3 over ~7 days for the 216-finding backlog.
- Still open: the it_engineer, as originator, still closes the it.finding itself; that loop's file is the money branch's.

**Why the CEO "stopped on 1 Nov":** nothing broke. The think.answer judgements were knowledge-quiz questions (323 on 19 Oct, 6 on 27 Oct, 5 on 1–2 Nov), never operational decisions. `ceo_model_slot` has never existed (app_secrets has only `social_model_enabled`), so `ceo_agent`'s judgement has never run. The accountant is idle the same way: 0 judgements in 7 days.

**2. Escalation:** the due check is in the WHERE. The silent seat is the seat its `awaiting` names, else the sender if it was answered and it closes the kind, else the receiver. It goes once to the CEO as a held question, or, for the CEO's own items, to the founder: once a day through `fn_notify_founder` (kind `ceo_needs_the_founder`). Two lines for fn_founder_brief are in `docs/runbooks/apply-the-shared-pool.md` §3. I kept customer_support as the silent seat on the 4 support.case_open rows, because it still owes the customer the answer.

**3. Coverage (SELECT, 30 days, 24,371 hand-overs):** 15,048 (62%) resolve to a customer, supplier, request, quote, payment or refund; 23,917 (98%) to some subject, findings included. The remaining 454 are CEO-internal records. One resolver, `fn_pool_keys` → `subject_link`, filled by triggers and back-filled in batches.

**The founder's test, printed (LOCAL)**
- IT on a supplier: "the platform (automatic): a supplier was approved"; company today "1 supplier.approved".
- Sales engineer on a request: "accountant: reveal.paid to sales_engineer -- answered: customer receipt sent, chosen supplier told", plus the quotes.
- CEO's day: "a customer paid the reveal fee of AED 135.00 on request 2 (painting, Dubai)".
- Sales engineer on the customer: "customer_support: complaint.due to customer_support -- open".
- A supplier's own block: "a quotation was received" (his own only; no seat names, amounts or the rival).

**Other items:** the block order is your hand-overs, then the subject, then the company today, ≤1,200 + header ≤1,300; TS no longer cuts. The context never builds the digest. Busy day (LOCAL): digest 234–365 ms, context 4–5 ms. Seed: 794 rows / 303 types, owners are producers, merged and never wiped. request.step_failed and supplier.applied file `event.act` hand-overs. Failed deliveries are not routed: their result already carries retry_request_id and escalation. A revise/reject deliberation goes back to its author as `deliberation.rework`; 0 of 36 verdicts were agree.

**Apply runbook (`docs/runbooks/apply-the-shared-pool.md`)**
- Off-peak; `lock_timeout` 1500ms; re-run on a lock timeout.
- The busy-table statements are last: triggers on company_event/agent_actions/seat_judgement and the dispatcher-trigger drop. Held only until commit (40 ms locally).
- No index files: the pool reads subject_link and key ranges.
- Then one release rehearsal (`QD_POOL_RELEASE_REHEARSAL=1`), then deploy the think/ai_reply/support_reply importers, ceo_agent and resilience_ping.
- I also changed rows the money-side branch seeded: the `seat_handoff_kind` handler for it.finding→ceo, and new kinds `event.act` and `deliberation.rework`.

**Authority gaps:** 1 grant named and checked in code, 99 named but not checked, 21 with no grant. Dangerous ones for the founder:
- Two unsubscribe points: customer_support changes a person's consent with no grant.
- `org_task.faq_answered`: org_authority has 0 rows.
- `marketing.outreach_reply`: `sales.invitation` is inactive, yet in 7 days the campaign sent 52 supplier_invite (customer_support), 20 nudges (sales_engineer) and 258 invite_m365_seed (it_engineer). It runs under the founder's switches (invite_enabled=false, supplier_outreach_golive=true) and no standing grant.

**Unsure:**
- Local data artefacts: without org_agents rows, hand-overs were re-addressed to `brief`; fixed locally by loading the six seats.
- Event ids can commit out of order, so the digest's id watermark may miss a late commit.
- The release probe inserts ZZ DEMO customers, leads, inquiries and transactions; those tables' triggers run inside the rolled-back transaction.