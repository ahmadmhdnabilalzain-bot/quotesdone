# Brief: w3_fix — round 3 of the shared pool: owed work is seen, the right seat is chased, the CEO's decision makes someone act, a seat can ask permission
Read `SP/briefs/COMMON.md` first. You are the FIX author (commit prefix `ceo:`).
Branch: `ceo-every-seat-reads-one-pool-and-every-hand-over-comes-back` (head eed8432be). Worktree: /tmp/claude-0/fix-w3-r3.
Local database: /tmp/pg-w3-r3, port 55521.
Read: `SP/workflow/FIX_COMMON.md` (the founder's words, ruling 1688: read them twice; they are the acceptance test);
REVIEW.md sections "WORKFLOW W3 POOL 2" (11:39) and its "re-run of 13 Nov evening" (exact lines, scenarios, scripts in
`SP/w3r2/`); the earlier author's account `SP/handbacks/W3_AUTHOR.md`; `docs/architecture/the-office.md` and
`docs/runbooks/apply-the-shared-pool.md` on the branch.
sql = `scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql`.

## The eleven review items: all decided, do them all
1. sql:1379 `fn_seat_pool_waiting`: a seat SEES the work it owes: count rows whose awaiting names this seat
   (case-insensitive) or whose handler answered 'waiting'. Proof: the reviewer's flood (500 supplier.applied → the sales
   engineer's block shows them, bounded and summarised, not 500 lines); reveal.reconcile shows for the accountant.
2. sql:1803: the silent seat is found case-insensitively (`~*`); when awaiting names no seat, the RECEIVER is the silent
   one, never the sender. A "waiting" reply is not an answer.
3. The CEO's decision makes someone act and does not bounce: a `fix_now` decision opens a hand-over to the named seat
   that stays OPEN until that seat reports done (not closed in 0 s); rows carrying a ceo_decision are not escalated
   again until their review or due date; when the seat reports, the CEO's task closes and the finding's sender reads it.
4. sql:1811: escalation goes to the SILENT seat's superior; to the founder only when the CEO himself is silent.
5. The daily cap of CEO questions counts re-armed questions too (day 2 showed 46 live against a cap of 30).
6. The apply must not stall event writes: `create or replace trigger` (no drop + create), the old dispatcher's body
   becomes a no-op and its trigger is dropped later in a separate file with its own pending note; `set local
   lock_timeout = '1500ms'`; give the lock table of the file for a first apply and for a re-run, LOCAL from pg_locks.
7. `accept_risk` is not offered when the finding is critical or touches security or money; `fix_now` is offered only to
   seats whose duties cover the subject (a security fault is not handed to marketing).
8. sql:1192-1194: the digest reads `d->'silence'->>'silent_seat'` ("? owes the next move" must never print; when the
   seat is unknown say "no seat has taken it").
9. The probe is not data-dependent: it passes on a day with 30 CEO questions already asked.
10. The seed gives the accountant `payment.received` and the reveal digest rows.
11. The timeline prints the answer itself (evidence.reply) on a row the sender is waiting on.

## The founder's four tests: each must HOLD, proven as a scenario in the probe
(a) A seat finishes verifying a customer or a supplier: there is an event for BOTH (add the customer-verified event at
    the place the code verifies a customer: find it; do not invent a new verification), it records WHICH seat did it,
    and every other seat reads it from the pool without being addressed.
(b) A paid reveal: the accountant's digest of that day SAYS the payment; the sender of a hand-over reads the ANSWER, not
    only "answered".
(c) A hand-over nobody answers: the seat that owes it is told it is late; the sender reads that it is late and who owes
    it; the silent seat's superior is asked once.
(d) "Approvals from 1 to 2" (today FAILS: `fn_agent_may_act` returns route 'ceo_case_decision' and nothing files it):
    when a seat is refused for lack of authority with that route, a question is FILED to the CEO through the same
    judged path as an IT finding (duty `ceo.company_pool`, inside the daily cap), carrying who asks, what, why and the
    facts; the CEO's model answers allow_once / refuse / ask_founder; the answer is written where the asking seat reads
    it (its pool block and the hand-over's reply); allow_once creates a single-use, time-limited grant row that
    `fn_agent_may_act` honours ONCE for that exact action and subject; anything touching money above the seat's limit,
    a real person's data, or a switch is ask_founder only (never allow_once). Probe: the three answers, the single use
    (second attempt refused), expiry, a malformed model answer (nothing granted, asked again), the cap.
    Do NOT turn on enforcement of the 99 named-but-unchecked grants (the founder has not decided it); list what (d)
    now covers and what it does not.

## Limits
No model call (stub the model in tests; say for every step whether it is model or code). No change to money routines
(another branch owns them: `accountant-...`; this branch must apply cleanly AFTER the money and sales branches' SQL:
fetch `origin/accountant-a-payment-is-known-booked-and-timed-from-the-moment-it-is-paid` and
`origin/sales_engineer-a-paid-request-is-closed-and-everyone-on-it-is-told` at their current heads and apply their files
first LOCAL; another agent is editing those two branches this evening, so re-fetch before your final proof).
PROVE (LOCAL): money + sales + pool applied twice, every probe OK; the reviewer's scenarios in `SP/w3r2/` re-run:
flood, cap day 2, the three CEO decisions 15 minutes later (no bounce), marketing silent → not the founder; cost per
write (event insert, hand-over insert) before/after; deno suites of every function folder touched; the node checks
`every_seat_reads_one_pool*`, `every_report_and_handoff_comes_back*` and the gaps check (state pass/fail lines).
Update `docs/architecture/the-office.md` and the runbook to what is true now.
Push small commits; progress notes in `SP/progress/w3_fix.md`.
HAND-BACK (under 55 lines; also `SP/handbacks/W3_FIX.md`): items 1–11 and tests (a)–(d): DONE (file:line, probe) / NOT
DONE (why); the chain table (step | seat | model or code | writes | read by); counts; the lock table; what the founder
must decide in plain words; what you are unsure of.
