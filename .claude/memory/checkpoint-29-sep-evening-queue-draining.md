---
name: checkpoint-29-sep-evening-queue-draining
description: "READ FIRST on resume, 30 Sep afternoon handover: what is live, the release queue, running fixes, founder rulings of the day, next steps (stage 2 E2E awaits his go)"
metadata:
  node_type: memory
  type: project
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-10-04T23:59:49.865Z
---

**Handover, 30 Sep 2026 afternoon. The founder's session limit was reached.**

**Live today:** #1138 refund second-seat, #1140/#1152/#1160/#1166 model matrix (GLM replaced; PROBE OK, 74 routes, 156 pairs, 77 classes), #1137/#1144 export registry (315+ tables), #1141, #1142, #1143, #1150/#1151 (supplier walk 20/20 on the name-match path), #1153 chat, #1155 (partial), #1164, #1167, #1168, #1169.

**Queue at handover** (the release operator merges one at a time):
- #1157, #1159, #1165, #1163 (the CEO memo MUST apply before 2 Oct 06:00 Dubai), #1162, #1170, #1172;
- then #1147, #1158 (safe-replay), #1149 together with #1154, #1156, #1171 (year plan; check that it edits an applied file).

**Being built:**
- #1173: payment rows plus supplier_pay charging only the remainder.
- The D7 follow-up: the mobile panel is offset by the real 69 px tab bar.

**Unfinished at the stop:** the CEO improvement sweep must settle in one run: every missed target gets exactly 1 improvement, and a second run opens 0 (it proposed duplicates, and opened 2 for 5 missed). Check its PR, or restart it. The operator's diagnosis: there are no real duplicates (unique source key). Root cause: `fn_ceo_improvement_sweep` proposes before it closes, capped at 20 open per seat, so each run only half-acts. Fix: close first, then propose, in a new file. #1171's edit to the applied 24 Sep file was reverted (history untouched).

**#1173 is blocked by review on three money gaps:**
- the bank routine must refuse overpayment and already-paid or reversed dues;
- record who entered each payment, with access restricted to the accountant path;
- a Stripe row records the amount Stripe actually charged, not a recomputed one.

**#1174** (panel sized from the real tab bar) is approved and gets labelled after the current batch.

**4 Oct resume (ledger 1092, freeze lifted):** 12+ agents running: operator v5, #1173, IT digest, ledger-95 proof, pipeline, no-source + AI-on exam, deps, and T1/T2-T3/T4-T5/T6-T7. The subagent cap of 20 was hit.

**QUEUED, not started: the knowledge restructure (1085), with a corrected plan.**
- kb_chunks is 8 GB on disk but only 468 MB live; about 7.3 GB is dead space.
- The bilingual model already exists (`knowledge_vector_ml` with e5-small, `fn_reason_retrieve_ml`), but the exam only scores the English path.
- Stages:
  1. Gate the ml path.
  2. One `knowledge_library`.
  3. Embed the kept kb_chunks rows.
  4. Paged trim of `qd_kb_pack` and the duplicates.
  5. Prove recall in EN and AR.
- The VACUUM FULL / pg_repack rewrite needs the founder's go and an off-hours window.

Start it when agent slots free up.

**ALSO QUEUED: the accountant ingests the September 2026 Mashreq statement.** The founder shared `C:\Users\Opera\Downloads\statement.pdf` on 5 Oct; rendered pages are in scratchpad/stmt.
- Opening 582.96, closing 59.25.
- Debits: 41.05 (card, USD 10.80, 26/09), 275.01 (card, USD 72.36, 29/09), VAT 9.95, maintenance fee 199.00. Credit: interest 1.30.
- 208.95 uncollected for August.
- Available balance 1,059.25 at the 02/10 issue, so about AED 1,000 came in early October (probably capital).

Record it through the mailbox intake path, idempotently; never hand-book.

**5 Oct, the founder's sequence (ledger 1094–1096):**
1. Finish the knowledge build, including the kb_chunks rewrite in an off-hours window (GO given).
2. Merge everything.
3. Directly run a FINAL CHECK.
4. Then he activates OpenRouter (lifts the hold) and starts the campaign.

The Sept card receipts and the account settings are later.

**New rules today:**
- Only the release operator applies `review-approved`.
- Never push to a labelled PR.
- SQL files never carry their own BEGIN/COMMIT.

**Founder rulings today (ledger 1056–1091):**
- The model matrix (1056).
- No founder approval of blogs; the CEO reviews with reasons; blogs are market topics (1058/1059).
- The upgrade freeze until the week of 5 Oct (1062).
- The task-ownership audit (1063).
- Settings deferred (1064–1067).
- GLM replaced, not just removed (1068).
- The exam must test real LLM answers in varied wording, and every miss is fixed (1084).
- The knowledge restructure plus Arabic-capable search next week (1085).
- Interest: 12% agreed for v14, 9% default, simple only (1086).
- Card fee: 3% only, since a surcharge is illegal under CR 66/2023 (1087).
- Keep the 24 trade pages (1088).
- No enterprise accounts (removed).
- Keep key rotation, but ignore Meta and any founder-required credential (1090).
- Year plan totals unchanged, with the enterprise volume moved to customer accounts (1091).

**Next steps:**
1. Drain the queue.
2. Re-run the ledger reconciliation and prove the 95 "merged-only" done rows live.
3. The final sweep.
4. Ask the founder's go for stage 2 E2E (AI on for demo traffic only, about USD 3–5).
5. Then the founder lifts the hold and the campaign starts.

Also see [[open-follow-ups-29-sep]] (items 1–30) and [[upgrade-backlog-after-queue-zero]].

**5 Oct 14:05Z, deliverability (ledger 1114):** the GoDaddy MX for `hello` is added (10 inbound-smtp.us-east-1.amazonaws.com) and read back from ns29. `invite_lane_enabled` is true (since 13:55:48Z). `invite_enabled` is still unset, so the campaign is OFF. The lane seed scored mail-tester 10/10, From invite@hello.quotesdone.com, DKIM d=hello.quotesdone.com. Still open: the GlockApps panel (the founder clicks Start Smart Test), and moving DMARC on hello to quarantine in 2–4 weeks. pg_cron has been empty since 7 Sep; send_outbox runs on another scheduler, about every 5 minutes.
