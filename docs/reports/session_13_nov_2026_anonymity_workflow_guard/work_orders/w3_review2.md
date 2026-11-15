# Brief: w3_review2 — second independent review of the shared pool and the CEO's judgement
Read `SP/briefs/COMMON.md` first. You are an INDEPENDENT reviewer.
Worktree: /tmp/claude-0/review-w3-2 from `origin/ceo-every-seat-reads-one-pool-and-every-hand-over-comes-back`
(head eed8432be). Local database: /tmp/pg-w3-2, port 55491.
Read: `SP/workflow/FIX_COMMON.md` (the founder's words, ruling 1688: a real company, a shared pool, every hand-over is a
loop, judgement by the model, authority and approvals); `SP/workflow/REPORT.md`; REVIEW.md section "WORKFLOW W3 POOL 1"
(the first review: "the CEO seat decides nothing"); the author's account `SP/handbacks/W3_AUTHOR.md`;
`docs/architecture/the-office.md`, `docs/runbooks/apply-the-shared-pool.md`; `git diff origin/main...HEAD`.
Round 2 claims: `fn_ceo_takes_it_finding`; duty `ceo.company_pool` (model judgement, cap 30/day); surfaces
`ceo.it_finding` / `ceo.overdue_handoff`; `fn_pool_keys` → `subject_link`; seed 794 rows / 303 types.
VERIFY LOCALLY (apply the branch's SQL twice; run its probes):
1. THE FOUNDER'S OWN TESTS, each run as a scenario and reported HOLDS / FAILS with the rows that prove it:
   (a) the sales engineer finishes verifying a customer: can the IT engineer and every other seat read it from the pool
   without being addressed? (b) a paid reveal: accountant, CEO, sales engineer, customer support each see it and each
   one's outcome is written back where the sender reads it; (c) a hand-over nobody answers: who notices, when, and what
   happens next (does it come back to the sender AND reach the CEO?); (d) an approval "from 1 to 2": a seat asks for
   something it has no authority for: who decides, where is the decision written, can the asker read it?
2. The CEO duty: is it a REAL judgement (the model receives facts and may answer differently on different facts) or a
   template? Read the prompt and the code path; run it with three stub model answers (act / wait / escalate to the
   founder) and one malformed answer; the daily cap; what happens at call 31; what happens when the model is down
   (nothing lost? retried?); a flood of 500 pool events in an hour (cost bound, queue, no storm of hand-overs).
3. `subject_link` and any trigger on hot tables (inquiries, quotes, handoffs, org tasks): the cost per write (time 1,000
   inserts with and without), the locks its creation takes at apply (lock table per statement with lock_timeout 1500ms).
4. Leaks: can a pool row carry a customer's or supplier's identity or a price to a seat or surface that must not have
   it (the anonymity ruling 1683/1686)? Can anon/authenticated read the pool (RLS, grants, every routine revoked)?
5. The seed: 794 rows / 303 types: sample 30: are they true to the code that emits them, or invented?
6. Conflicts with the two sibling branches (`origin/accountant-a-payment-is-known-booked-and-timed-from-the-moment-it-is-paid`
   5747d5f62 and `origin/sales_engineer-a-paid-request-is-closed-and-everyone-on-it-is-told` 5acacfaf2): same routines
   replaced by both? order of apply? `git merge-tree` conflicts?
7. Authority: the audit found 1 grant checked in code, 99 named and not checked, 21 none. What does this branch change
   of that, and what is DANGEROUS if it ships as is (a seat that may now act on money, messages or a real person)?
8. Deno suites of every function folder the diff touches; the node checks it adds, offline.
VERDICT: MERGE or FIX (numbered: file:line, scenario, smallest fix), most harmful first; what the founder must decide in
plain words; the apply/deploy order relative to the two siblings; under 55 lines. Append the full review to
`SP/show/REVIEW.md` under "WORKFLOW W3 POOL 2".
