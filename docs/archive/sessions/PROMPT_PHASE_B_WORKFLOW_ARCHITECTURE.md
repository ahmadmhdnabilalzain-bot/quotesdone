# Phase B — prompt for the next session

**The package is committed to this repository at `docs/phase-b/package/`. Nothing needs attaching.**
All 60 files were verified against `SHA256SUMS.txt` on 15 Aug 2026, and every count the package
declares was confirmed against its own registries: 30 workflows · 257 steps · 161 handoffs · 56
business objects · 54 rules · 32 gates · 50 exceptions · 34 SLA policies · 347 events · 14/35
workflow states and transitions · 11/19 step states and transitions · 30 workflow files.

Copy the block below into a new session. It is self-contained.

---

Load the `quotesdone-session` skill first. Then read, in this order, from
`docs/phase-b/package/`:

1. `START_HERE.md`
2. `PHASE_B_PRODUCTION_DIRECT_PROTOCOL.md`
3. `PHASE_B_MASTER_SPEC.md`
4. `PHASE_B_INVARIANTS.md`
5. `CLAUDE_PHASE_B_MASTER_PROMPT.md`
6. `PHASE_B_CURRENT_CODE_RECONCILIATION_POLICY.md`, the machine-readable registries, and all 30
   files in `workflows/`

Then execute Phase B. The package is already in the repository — verify its checksums yourself
rather than trusting this line.

## Phase A is founder-approved and frozen

Do not alter: the 10 departments · the 90 canonical roles · reporting lines · reviewer
relationships · the 86 category-overlay authority boundaries · founder-reserved decisions.

Verify before you start and again before you finish:

```
select * from public.fn_phase_a_baseline_drift();            -- must be 0 rows
select count(*) from public.fn_phase_a_organization_violations();  -- must be 0
```

A statement-level guard (`z90_phase_a_freeze`) refuses any change to the approved counts.
**If the workflow analysis reveals a genuine organizational defect, write a formal Phase A change
request with evidence and STOP that specific change — bring it to me.** Do not set
`app.phase_a_change_reason` to get past the guard. Everything else in Phase B continues while that
one item waits.

## This is Phase B only: complete business workflow architecture

Reconcile every current frontend, API, Edge Function, database function, trigger, cron, event,
queue, portal and state path against the 30 canonical workflows. Implement the canonical workflow,
step, state, transition, handoff, business-rule, gate, exception, SLA and founder-boundary
registries.

Classify every current path as exactly one of:
`CANONICAL_KEEP` · `CANONICAL_BETTER_KEEP` · `CANONICAL_PARTIAL` · `DUPLICATE_PATH` ·
`CONFLICTING_PATH` · `DEAD_CODE` · `UNOWNED` · `OUT_OF_SCOPE` · `PHASE_C_WIRING_GAP`

**Do not report a runtime path as connected because its table or function exists.** This is the
single most repeated defect in this estate: a finished capability with no entry point, a guard that
has never fired, a queue nothing reads, a number measuring something other than what it names. Ask
what actually calls it, and whether it has ever run. `PHASE_C_WIRING_GAP` is the honest answer for
unconnected runtime code, and using it is not a failure.

## Do NOT work on

Knowledge · tools · models · prompts · decision traces · synthetic accounts · certification ·
runtime professional testing. Those are later phases. Do not activate any workflow, cron job, route,
provider or autonomous process. Do not create synthetic customers, suppliers, inquiries, payments or
notifications. Do not send email, SMS or WhatsApp.

## Zero paid inference — this one is absolute

Every OpenRouter route is held open-circuit in `llm_route_health` (8 routes). **Phase B needs none
of them. Do not release the hold, and do not ask me to.** Phase B must finish with OpenRouter
requests = 0 and paid inference cost = USD 0.00. Any paid inference request is a phase failure.

## What this repository already is, so you do not rediscover it

- **One Supabase project: `htdblwldjkcgjvmqkbeh`.** Staging was deleted 15 Aug 2026. Do not
  recreate it, do not write a check that reads it.
- **Deploy with** `node scripts/apply_sql.mjs <file> --apply [--ddl]`. A bare invocation is a dry
  run. It reads the definition back out of the database afterwards; that read-back is what makes the
  exit code mean anything.
- **A multi-statement file is ONE implicit transaction.** That is what makes the aborted rehearsal
  work: send the exact committed bytes with a trailing `raise exception` that first reads the
  post-change counts, so the numbers come out and nothing commits. Then prove the production
  fingerprint is unchanged.
- **CI lints migrations** (`squawk`). Put `set lock_timeout` and `set statement_timeout` at the top,
  add CHECK constraints `not valid` then `validate`, and use `bigint` not `int`.
- **`scripts/sql` is append-only.** To change something, add a new file.
- Useful starting facts, measured 15 Aug: `workflow_step` holds **19** runtime workflows as ordered
  steps; `org_workflow_ownership` holds the **30** organizational workflows with one accountable
  owner each; `org_workflow_step` holds step-level ownership for **W22 only**. Those three are not
  the same subject, and reconciling them is Phase B's job — measure them yourself before believing
  this paragraph.

## How to run the session

- No check-ins and no step-by-step updates. Work until done, then reply once.
- Do not ask me technical questions. Decide, do it, and tell me what you decided. Escalate only
  money, destructive production changes, and things only I can know.
- Verify by execution in the same turn, never by "it typechecks" or "the table exists".
- Never weaken a check or fabricate data to turn a gate green. If a fix makes a check harder because
  the old pass was false, say so.
- Commit and merge via PR, never straight to main.
- Roll back automatically if any mandatory Phase A or Phase B invariant fails after deployment, and
  report `PHASE_B_NOT_READY`.

Produce the 16 deliverables the master prompt lists, under `docs/phase-b/`.

End with exactly `PHASE_B_READY_FOR_FOUNDER_APPROVAL` or `PHASE_B_NOT_READY`.
