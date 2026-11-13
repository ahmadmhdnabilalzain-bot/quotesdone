# Company workflow fix round, 13 Nov 2026: common brief

Repository /home/user/quotesdone: do NOT work in that checkout. Make your own worktree from origin/main under
/tmp/claude-0/ as your brief names it; remove it when you hand back. QuotesDone: UAE B2B procurement marketplace
run by AI seats; Supabase project htdblwldjkcgjvmqkbeh (Postgres + Deno edge functions), Next.js site in src/.

## Read first
- `.claude/CLAUDE.md`; `.claude/memory/MEMORY.md` and the notes it indexes on seats, hand-overs, the books, the
  reveal, refunds, documents on our template, demo fixtures, "the model reads first"; the skills
  `.claude/skills/quotesdone-apply-discipline/SKILL.md` and
  `.claude/skills/quotesdone-organised-like-an-auditor-will-read-it/SKILL.md` (binding for SQL and for where
  things live); `.claude/skills/quotesdone-work-is-assigned/SKILL.md` (read the LIVE seats).
- THE AUDIT you are fixing: `/tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/workflow/REPORT.md`
  (read all of it), and its failing check on branch `it_engineer-a-paid-reveal-is-known-to-every-seat-with-a-step`
  (`scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs` + its fixture): 17 tests, 5 hold, 12
  gaps. Your work is done when the gaps in YOUR scope pass on your branch (cherry-pick or re-create the check file
  in your branch under the same path so the branches meet; do not weaken an assertion; where an assertion was
  wrong, say why).

## The founder's words (ledger public.founder_instruction 1685, 1687, 1688, 13 Nov 2026)
"…all the agents who are relevant and have a step … are aware. So when the sales engineer is sharing a comparison
report, then the customer … selected one quotation and he paid the reveal fee, was the accountant aware that this
is the invoice that we received? Is it kept in the books properly? Is the CEO aware that we made that sales? Is
the sales engineer aware that the customer paid and now he closed this project totally, and now the accountant
will start the timer from the day of payment for the refund window that we have? Is the whole workflow tested
this way?" — "VAT is not for us … our reveal fee quotation should be excluding VAT 100%." — "it should feel like a
real company. It's not like a very simple logic 1 + 1 = 2. … That's why we are using AI, not just code … we need
the judgment, the logic, the reasonability. … an established company … with these 5-6 staff, and they are
operating like real people. … How they communicate with each other, how is the authority given from one and
approvals from 1 to 2. It's a loop. It's never like this agent is done with this task, he just sends an output
and he doesn't know what happens after that. No, there is like a shared pool where they all know what's going on
around. … everyone should know."

## Rules
- A seat that must JUDGE (a mismatch, an exception, a refund request, an unusual payment) judges with the model
  through the seat's existing model path, with the facts in front of it and its decision written where the next
  seat reads it; the straight-through bookkeeping stays code (fast, exact). Say for every step which it is.
- Every hand-over closes: the receiver's outcome is written back and the sender can read it.
- Money is exact: fils, the fee = rate x the quotation total EXCLUDING VAT, the customer pays the fee and nothing
  else, no VAT line, the journal balances, numbers never change after posting (reversal entries only).
- Demo and real: a ZZ DEMO payment must leave the SAME chain a real one does, kept apart from the real books (a
  shadow tagged by run), so the chain can be proven before a real customer pays. Nothing a demo does may reach a
  real person or the real ledger.
- No call to production except SELECT-only reads
  (`NODE_USE_ENV_PROXY=1 node /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/q.mjs <file.sql>`,
  last statement's result only). No paid model call, no deploy, no apply, no merge, no switch change, no message
  to anyone. SQL goes in `scripts/sql/<name>.sql` with a `_probe.sql` and a pending note exactly as the
  apply-discipline skill says (revoke + pinned search_path on every routine, RLS + policy on every table, every
  overload enumerated); rehearse with `node scripts/ci/rehearse_sql.mjs` (rolled back by design).
- Never print a secret or a real person's details; never touch leads 19398 and 158318.
- Stay inside the files your brief gives you; name anything you need from another agent's files in the hand-back.
- Tests before hand-back: deno tests of every function folder you touched
  (`--no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE --allow-read=. --allow-net=127.0.0.1`),
  the checks that own your subject run one file at a time with node, the canonical routine manifest check.
- Commits: seat prefix as briefed; every commit message ends with exactly:
  `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01MHFn2pe3REUYi65EDVrW7G`
  and names no other model anywhere. Push the branch; open no pull request.
- Disk is tight: no videos, clean up what you generate.

## Hand-back (under 60 lines)
1. Each gap in your scope: CLOSED (file:line; the assertion that now passes) / NOT CLOSED (why) / NEEDS THE FOUNDER.
2. The chain after your change, as a table: step | seat | model or code | what it writes | who reads it.
3. Tests and probes run, with counts; the gaps check's pass/fail lines on your branch.
4. SQL to apply, functions to deploy, in order; what a deploy changes for a real customer the first minute.
5. What you are unsure of.
