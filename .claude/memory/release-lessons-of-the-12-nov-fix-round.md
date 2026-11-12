---
name: release-lessons-of-the-12-nov-fix-round
description: "12 Nov 2026: what the fix round after the final audit taught about releasing without CI. The offline gate now runs the whole Deno suite (deno-suite step); run it the canonical way, never with -A; never pkill by pattern on a box agents share; apply_sql refuses text that is not on main; CPU-budget tests fail under load; what the registration certification cannot see."
metadata:
  type: feedback
  modified: 2026-11-12
---

Thirteen PRs went to production on 12 Nov 2026 (#1951 to #1962 and the bookkeeping) with GitHub Actions off (ledger 1564,
1648). These are the things that went wrong or nearly did, and what now prevents each.

1. **`--skip=npm-test` skipped the whole Deno suite.** #1953 reached `main` with two red Deno tests that per-folder runs on
   the branch had not reached (fixed in #1954). The gate now has a `deno-suite` step (`node scripts/checks/run.mjs
   --deno-only`, about 10 minutes, no token) that runs whenever `npm-test` is skipped. Prevented by: that step.
2. **Run the Deno suite the canonical way, never with `-A`.** `deno test -A supabase/functions` shows two failures that are
   not failures: `send_outbox/drill_send_faults.test.ts` "D3 DEMO.2" asserts Deno grants no network beyond 127.0.0.1 (true
   only under the runner's scoped grant), and `conversation_archive/document.test.ts` "brand fonts". Through
   `scripts/checks/run.mjs` the suite is 3,890 passed, 0 failed (measured 12 Nov). For a whole morning these two were
   carried as "known container failures"; a known failure is a place a real one hides.
3. **CPU-budget tests fail when the box is loaded.** With five agents running suites (load average 8 to 9),
   `drawing_boq/drawing_lengths.test.ts` "dense sheet", `pdf_native/the_month_calendar...` and `identity_text` "well under a
   second" failed, and passed alone. Re-run them alone before believing them; do not raise their budgets.
   The gate's `deno-suite` step therefore runs alone, after its other offline steps: on its first run beside `next-build` and
   `deno check` a dense-drawing budget test took 1,654 ms and failed.
4. **Never `pkill` by pattern.** Agents share the machine and run the same commands. A `pkill -f "deno test ..." --oldest`
   meant for a stopped run killed another gate's suite. Stop a background task by its task id; an agent stops only a
   process whose pid it started and whose working directory it checked.
5. **`apply_sql.mjs` refuses a file whose text is not on `origin/main`** ("not on origin/main and no PR found": the PR
   lookup uses GitHub GraphQL, which cloud sessions cannot reach). So a correction to a pending file is merged first and
   applied after, and its MANIFEST line follows in the next bookkeeping commit.
6. **Applies are recorded nowhere but the session.** The eighteen files of this round were put in MANIFEST order by
   reading the session transcript for the apply commands. Add the MANIFEST line and delete the pending note in the same
   sitting as the apply, or the order has to be reconstructed.
7. **Independent review found a blocker on every branch that looked finished**: a licence file moved by a background
   sweep, a spinner that could not be seen inside the portal's own stylesheet, a claim-by-name that let a hand-made
   request take a real company's listing, a WhatsApp draft sent in place of the database's answer ("your request has been
   cancelled" when it had asked for confirmation), a ticked service saved as "through a partner". None was visible in the
   author's own tests. The reviewer must run the real handler with adversarial input and look at the real page.
8. **What the registration certification cannot see.** Its phone-photo fixture is 0.08 MB, so it cannot see a large photo
   failing on a phone line (walk finding B1; the form now sends files of 3 MB or less untouched and scales larger photos to
   3,000 px). Its late-licence wait is the step's ceiling minus the time already spent, not a fixed 65 s. A speed step that
   lands in the first seconds after a five-minute mark can fail on Supabase's relay hold alone
   ([[a-five-minute-mark-holds-edge-calls-before-our-code]]). Headless Chromium is not Safari on an iPhone: keyboard
   raising, HEIC from the Files app and focus inside a tap are proven only on a real phone.
9. **A paid re-check must tag every call.** The WhatsApp re-check overspent its cap (USD 1.18 against 0.80) because re-asks
   of fixture turns carried no run tag and a reserved fixture number was not a fixture to the gateway
   (`fn_ai_subject_is_fixture`); #1958 stopped the re-asks and the fixture-number SQL is on the WhatsApp speed branch.
