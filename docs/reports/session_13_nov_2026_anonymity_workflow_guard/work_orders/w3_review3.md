# Brief: w3_review3 — third independent review of the shared pool (round 3 of the fix)
Read `SP/briefs/COMMON.md` first. You are an INDEPENDENT reviewer; you wrote none of this.
Worktree: /tmp/claude-0/review-w3-3 from `origin/ceo-every-seat-reads-one-pool-and-every-hand-over-comes-back`
(head fd95e8711; round 3 = the 5 commits after eed8432be). Local database: /tmp/pg-w3-3, port 55541.
It applies AFTER two siblings: `origin/accountant-a-payment-is-known-booked-and-timed-from-the-moment-it-is-paid`
(ea9c25c62) and `origin/sales_engineer-a-paid-request-is-closed-and-everyone-on-it-is-told` (75f60e2d3): apply their SQL
first, in the order of the runbook `docs/runbooks/a_paid_reveal_release_13_nov_2026.md` on the money branch.
Read: `SP/workflow/FIX_COMMON.md` (the founder's words, ruling 1688: his words are the acceptance test); REVIEW.md
"WORKFLOW W3 POOL 2" and its "re-run of 13 Nov evening" (eleven FIX items; the founder's four tests: (a) partly, (b)
partly, (c) partly, (d) FAILS); the work order `SP/briefs/w3_fix.md`; the author's account `SP/handbacks/W3_FIX.md`;
the earlier reviewer's scenario scripts in `SP/w3r2/`; `git diff eed8432be..fd95e8711`.
VERIFY LOCALLY (everything applied twice):
1. Items 1–11: each DONE-AND-PROVEN / NOT by your own scenario, re-using and extending `SP/w3r2/` (flood of 500; cap on
   day 2 and day 3; the three CEO decisions at +15 min, +5 h, +3 days; marketing silent; the CEO silent; a "waiting"
   answer; the timeline).
2. The founder's four tests as scenarios with real triggers, each HOLDS / FAILS with the rows:
   (a) verified customer and approved supplier: event, WHO did it, every seat reads it unaddressed;
   (b) paid reveal: the accountant's day says it; the sender reads the answer itself;
   (c) unanswered hand-over: the owing seat, the sender, the superior, once;
   (d) a seat without authority asks: the question reaches the CEO's model path; allow_once / refuse / ask_founder;
       the grant is single-use, subject-bound, expiring; never for money above the limit, a person's data or a switch;
       malformed answer; cap. ATTACK it: a seat asking for itself with a forged subject; asking 100 times; using a grant
       for a different amount, a different subject, after expiry, twice in parallel (two sessions at once); a grant
       created by anything other than the CEO's decision routine (direct insert as service role is expected to work:
       say who else can write the table: RLS, grants); a seat that asks for something the founder's hard rules forbid
       (messaging a real person, changing a switch): must be ask_founder or refuse, never allow_once, whatever the
       model answers.
   The author says (d) is NOT wired to today's TypeScript callers (it_engineer/index.ts, accountant/actions/refunds.ts,
   accountant/actions/seat.ts, sales_engineer/actions/operator.ts still call the 3-argument form). READ those four call
   sites and write the exact change each needs (lines), what the seat's own response should say when it has asked, and
   whether old function + new routine and new function + old routine are both safe in the deploy window.
3. The new order loop: `ceo.order` stays open until the seat reports (`fn_seat_reports_done`): WHO calls that routine
   in the live code today? If no seat's code path calls it, every order stays open forever and comes back as late: say
   so plainly, name the call sites that must call it, and what happens to an order nobody can ever report.
4. The CEO's model path: READ the prompt the question builds and the code that sends it: facts in, options out; cost
   per question (how many model calls, which model slot, an estimate in USD from the token counts you can count);
   what the daily cap of 30 costs at most; what happens when the model is down.
5. Leaks and exposure: every new routine revoked from public/anon/authenticated; RLS + policy on every new table
   (`ceo_grant_once` and the rest); no customer or supplier identity or price in a pool line a seat should not see
   (rulings 1683, 1686).
6. THE REAL APPLY: your own lock table from pg_locks for a first apply and a re-run, and for the dispatcher-drop file;
   with a live writer on agent_actions and on company_event open for 4 s: what the apply does (fails at lock_timeout:
   good) and what the writers experience. Time of the whole file. Is it safe to apply while the money/sales functions
   are already deployed, and before its own functions (if any) are?
7. `fn_emit_supplier_approved` is now defined in two files: which is the canonical owner
   (scripts/checks canonical routines / MANIFEST rules)? Is the later definition a superset?
8. 10 mutants of your own on round 3: caught by verdict / only by an error / survive.
9. Suites: deno of every function folder the branch touches and `_shared`; node checks `every_seat_reads_one_pool*`,
   `every_report_and_handoff_comes_back*`, the canonical-routines and manifest checks, the gaps check (state the lines).
VERDICT: MERGE or FIX (numbered: file:line, scenario, smallest fix), most harmful first; release steps; what the founder
must decide in plain words; under 55 lines. Append the full review to `SP/show/REVIEW.md` under "WORKFLOW W3 POOL 3".
Progress notes: `SP/progress/w3_review3.md`. Delete your cluster and worktree at the end.
