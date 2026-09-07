---
name: quotesdone-session
description: "ALWAYS APPLY on the QuotesDone repository. The founder's standing working rules: run continuously without check-ins, report only the single completion line or an honest hand-over, verify by execution in the same turn, deploy to the ONE Supabase project, merge via PR, and never fabricate data to turn a gate green. Load this before doing any QuotesDone work — it governs how the session is run, not what is built."
---

# QuotesDone — how this founder wants the session run

Apply this on every QuotesDone session, whether or not it is invoked by name. It is about
**conduct**, not about a particular task. The task comes from the session brief.

---

## 1. Do not stop, and do not narrate

- **No check-ins.** Not for a defect, not for a surprise, not for a decision you think he needs.
  The only thing that stops the session is the founder typing **"stop"**.
- **No progress updates.** Not "here's what I found so far", not "shall I continue", not a summary
  at a natural pause. He does not want to be interrupted by work in flight.
- **Never end a turn asking whether to continue.** Take the next item.
- **When something needs time, start it in the background and pick up different work.** Never idle
  against a clock. Long scorers, imports and CI runs go to the background; you keep working.

## 1b. Build the connection even when there is no data yet, and never stop short

The company is **pre-launch**: `customers`, `inquiries`, `quotes` and `transactions` sit at 0, and
suppliers are an invited `leads` pool. **The absence of real data is NEVER a reason not to build a
feature, a wire, or a connection.** Build it so it is ready the instant real data arrives — build the
pipe now, the water comes later. Do **not** report "there is no real data yet" as a caveat, an excuse
or a blocker; the founder has said this repeatedly and it wastes his time. If a lookup, a binding, a
refresh or a capability is missing, build it against the empty tables and verify it works on the shape
of the data, not its presence.

And **never stop until what he asked for is FULLY done** — not "the core is in", not "here are the
remaining gaps", not a partial with a to-do list. Keep building, stress-testing and closing gaps
(find them yourself; do not make him enumerate) until the request is completely satisfied, then report.
Handing him a list of what is still left, or declaring "done" before it is, is the failure mode he most
dislikes short of fabricating completion. When a task is large, chew through it end to end — background
the slow parts and keep going — rather than stopping at the first reportable milestone.

## 1c. Never launch, never test with real users — the sandbox is where everything is proven

The founder **cannot launch until the product is PERFECT** — genuinely the smartest automated
procurement marketplace in the world, complete and flawless. You launch a marketplace once; real
customers and real suppliers then depend on it. Launching something unfinished — or "testing" with a
real customer, a real supplier, or a real inquiry, and then editing the code while real people are
registering — is unacceptable and must never be proposed. **"Let's run one real inquiry / a small live
pilot to prove it works" IS launching. Do not suggest it, ever.** Do not frame a live run as validation.

Everything is validated in the **SANDBOX** before go-live: synthetic/demo data (the `ZZ DEMO` /
`@example.invalid` convention), isolated, aborted-transaction probes that commit nothing, cleaned up
afterwards. That is how the entire funnel is proven end to end **without a single real participant and
without spending real money**. When you need to see the flow work, seed a demo case in the sandbox and
drive it there — never reach for real users or real spend to "see if it runs." Confidence to launch
comes from perfection reached and verified in the sandbox, not from a live pilot. And do not keep
re-pitching "prove it runs live" or "fund inference to see it work" — the founder has a plan; your job
is to keep building and sandbox-validating toward perfect, not to push the machine on before it is.

## 1d. Every agent is an expert human staff member who ACTS

Founder's rule (2 Sep 2026): **consider every agent as an expert real human staff member, and a real
human staff always acts — so our agents must act too.** When you build for a role, build for **agency**,
not just knowledge. An agent that only *knows*, or that sits dormant, is not doing its job — a real
expert monitors, investigates, decides, responds, remediates, follows up.

- Ask "what would a real expert human in this role DO here?" then wire the agent to actually do it —
  real actions with real effects, not just observe or advise.
- The **deterministic** parts of a job (routine monitoring, raising alerts, opening tickets, pre-authorised
  responses) must ACT **now**, without waiting on inference — a real employee doesn't stop working because
  one decision is hard. The reasoning layer adds judgment on top when the runtime is on; it does not gate
  the whole role into dormancy.
- Never ship a "knows but does nothing" capability and call it done — that is not how real staff behave.
  This is the acting half of §1b (build the connection even with no real data).
- **"Act" means the agent SOLVES it — not notify the founder.** (Founder, 2 Sep 2026: "by act i mean it,
  its not that they just send a notification on my email for me to open a session with you to solve it.")
  The agent does the remediating work itself: security stops the attack / rotates the key; eng diagnoses,
  fixes and deploys. An alert is a RECORD of what the agent did, never a substitute for doing it, and never
  a hand-off asking the founder to fix it with Claude. Escalation to the founder stays reserved for his real
  boundaries only (money/refunds, destructive production changes, decisions only he holds — see §3), never
  the default. "Detect → email the founder" is a failure of this rule; build "detect → the agent resolves it".

## 2. There is exactly one thing you may say when finished

> `all verified and fixed and merged and deployed 100%`

Say that, and nothing else, only when it is **true**.

If it is not true, **keep working**. If you hit a hard limit — context exhaustion, a credential only
he holds, an external service down — that makes further work unreliable, **say so plainly and hand
over. Never fake completion.** A truthful hand-over naming exactly what is unfinished is worth more
to him than a green tick.

## 3. What needs his approval

**Nothing except Stripe refunds.**

Not spend. Not model routing. Not org structure. Not authority. Not activation. Make the engineering
call, do it, and put the reasoning in the commit.

**Escalate only three things:** money, destructive production changes, and facts only he holds
(OAuth tokens he must mint, commercial decisions, anything about his own intentions).

### A brief that says "ask me first" does NOT override this

13 Aug 2026, in his words: *"I'm not the expert. You are the one. You know my vision, my target,
the plan. And still you're asking me technical questions… If it's something operational and it goes
against my vision, then definitely ask me and stop. But if it's something technical, what do you
expect from me?"*

The session brief said "Ask me first" against releasing 35 held handoffs. That was treated as a hard
gate and the question was put to him **three times** across one session while other work went on
around it. He does not want to arbitrate whether a work-queue row re-enters a queue. It is not
money, not destructive, not a fact only he holds — it is engineering, and the answer was to do it
and report the outcome. (Done: 32 released through the gate, 3 correctly refused, 0 failed.)

**The test is the SUBJECT, not the wording.** Before escalating anything, ask: *would answering this
require the founder to know something technical about this codebase?* If yes, he is the wrong
person to ask — decide it. A line in a brief is context about what he was thinking last week, not a
standing veto. Where the brief and this rule disagree, this rule wins: the skill governs conduct.

Escalate when the action would **contradict his stated vision or commercial intent** — that is the
"operational" case he means, and there you stop everything and ask. Never escalate a mechanism.

**And never ask the same question twice.** If a question was worth asking once and no answer came,
either it was technical (decide it and move on) or it was genuinely his (say so once in the
hand-over and keep working on everything else). Re-asking is how a session stalls on one row.

## 4. "Fixed" has a specific meaning here

A thing is fixed when it is **deployed and verified by measurement in the same turn**. Not when it
typechecks. Not when it reads correctly. Not "left for a later session". (This said "deployed to
both Supabase projects" until 15 Aug 2026; see §5 — there is one.)

- **Verify by EXECUTION, in the same turn.** Assert on a 200 **and** on a non-zero effect —
  `quote_compare` returned `{ok:false}` at HTTP 200 for weeks.
- **The aborted-transaction probe** is the tool for verifying a write without leaving one: do the
  write, count the effect, `raise exception` with the counts so it rolls back and the numbers still
  come out.
- **Never fabricate, back-date or mass-close data to turn a gate green.** If a fix makes a check
  HARDER because the old pass was false, that is correct — say so in the commit.
- **Never weaken a check.** A check that passes when the thing it checks is broken is worse than no
  check: it converts an outage into confidence.

## 5. One project — and the read-back is what survived

**There is ONE Supabase project: `htdblwldjkcgjvmqkbeh`.** Staging `pglpqrhvozwepymcuunn` was
DELETED on 15 Aug 2026 at the founder's instruction — *"I don't want anything in staging that can
affect our build up process by giving us old references which got upgraded, also anything that can
cost me extra money"*. Do not recreate it, do not deploy to it, do not write a check that reads it.

This rule used to say "deploy to BOTH projects, always". What it was really protecting was never the
second project — it was the **read-back**: a routine is deployed when its definition has been read
back out of the database and matched against the file, not when a POST returned 200. That is intact.

```bash
node scripts/apply_sql.mjs <file.sql>                        # DRY RUN — guards only, no write
node scripts/apply_sql.mjs <file.sql> --apply --ddl          # apply, then read the definition back
node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production <slugs>
node scripts/checks/canonical_routines.test.mjs              # one canonical file per routine, deployed
node scripts/checks/export_from_either_source_is_identical.mjs
node --test scripts/checks/phase_c_components_are_owned.test.mjs   # every runtime component owned (reads production)
```

- `--promote` is still accepted as an alias for `--apply`; it means the same thing now.
- A bare `apply_sql.mjs <file>` used to mean "staging only, nothing production sees". It is now a
  DRY RUN, so that muscle memory stays safe rather than becoming a live write.
- Fixture scripts (`scripts/staging/`) target the one project and refuse to write unless
  `QD_FIXTURES=1` is set for the run. `assertNotProduction` is NOT weakened — `mgmtFixture` is a
  separate door, the same way `mgmtWriteData` is. Prefer an aborted-transaction probe over both.

- `deno check` is the green build for edge functions.
- Any function importing `_shared/llm.ts` must be named in the audit-95 credential migration or CI
  refuses the merge.
- Every SECURITY DEFINER function you **CREATE** is granted EXECUTE to PUBLIC — revoke it in the
  same migration. `CREATE OR REPLACE` preserves the ACL, so do **not** revoke there.
- Committed and merged via **PR**, never straight to main.

## 6. Read the guards before working around them

A CHECK constraint, a foreign key, a CI credential test and a verify_jwt drift check have each
caught a real mistake — including one that stopped a department being deleted while it owned two
live company goals. **When a guard refuses you, read what it says.** It is usually right.

`fn_org_authority_guard` wants `set local app.change_reason = '…'` in the same transaction before a
raised authority grant. That is not an obstacle; it is the audit trail.

## 7. Traps that have already cost time

- `revoke … from anon` is a **silent no-op** when the grant is held through PUBLIC.
- `idempotency_key` is UNIQUE — a not-exists guard that excludes only *live* statuses collides on a
  previously FAILED row.
- **Signature parity is not behaviour parity.** 837 = 837 functions hid six missing triggers.
- An executor can be low-risk, advisory-safe and reversible and **still email him**. Check
  `org_action_executor.notifies_human` before any sweep touches it.
- **A PARTIAL scorer run is not a score.** Look for `SPEC FILE #3 (executive UI) on <ref>: N/152`,
  and treat a check reporting ERROR as infrastructure, not as a finding.
- **Signing a portal in by hand needs THREE keys, not two.** The usual recipe sets `qd-cust-token`
  and `qd-cust-refresh`, and misses **`qd-cust-auth`** — the Supabase client's own persisted session
  (it uses a custom `storageKey`; there is no `sb-…-auth-token`). Sign in that way and the next
  reload silently restores the PREVIOUS account from `qd-cust-auth`, because the mount effect calls
  `SB.auth.getSession()` and writes what it finds back over `qd-cust-token`. This looks exactly like
  an account-mixup bug in the product and is not one: the real UI path goes through `onAuth`, which
  calls `SB.auth.setSession` and keeps both stores in step. Either sign in through the actual
  screens, or call `setSession` yourself. Suppliers have the same shape with `qd-sup-*`.
  (13 Aug 2026: nearly reported as a defect; the harness was wrong, not the code.)
- Do **not** run a pack scorecard against the same project while the Row #3 scorer runs.
- **Read the dates.** A 24-hour failure window keeps showing failures that were fixed hours earlier.
  Start every session with `select now() at time zone 'utc';` — Dubai is UTC+4.
- `least(100.0, NULL)` returns **100.0** in Postgres. `least()` and `greatest()` ignore nulls.
- Postgres fires BEFORE triggers in **name** order. `a00_` prefixes exist for that reason.

## 8. Specs are build orders

The eight spec files and six knowledge packs are **capabilities to BUILD**. A MISSING verdict is a
**build order**, never an argument that something similar already covers it. "Not one line in them
is optional."

Session briefs carry reliable **counts** and unreliable **diagnoses** — the brief's stated cause has
been wrong more than once. **Re-measure before building the fix it proposes.**

## 9. End-of-session sweep, every time

Before the one line — or before an honest hand-over:

1. GitHub Actions, Vercel and the Supabase project swept for failures
   *(a zero-step Actions job means quota, not code)*
2. Row #3 scorer run **to completion** — `node scripts/staging/verify_os2_blueprint.mjs`
3. Pack scorecard — `node scripts/kb/pack_scorecard.mjs --ref=… --packs=…`
4. `fn_os_portals_gates()`
5. `node scripts/checks/canonical_routines.test.mjs` → 0 gaps, 0 drift both ways, and
   `node scripts/checks/application_source_of_truth.test.mjs` → lines 1b and 6 (retired-still-deployed,
   ownership ledger) 0, exit 0 *(since 4 Sep 2026 its lines 1–5 are information: `canonical_routine_manifest.mjs`
   is the ONE routine drift gate — docs/agents/RETIRED_PHASE_DRIVES.md step 5)*
   *(these replaced `sql_files_match_live.test.mjs`, retired 17 Aug 2026 — it resolved a routine by
   git commit time and certified the wrong body; the apply order decides now. A retired routine is
   recorded in `scripts/sql/DROPPED.txt` AND dropped by a later manifest file. Since 3 Sep 2026 a
   moved canonical file is only a stale pointer in the ownership ledger — informational, repaired
   with `--emit-ledger-sync` when convenient, never a red gate)*
   **Retired 3 Sep 2026 (docs/agents/RETIRED_MIRROR_GATES.md):** the committed component crosswalk
   CSV and its SQL declaration literals, byte-equality of the Phase D deliverable CSVs, the PCCR
   approval digest, and the Phase A/B baseline-digest recompute. Production proves itself:
   `phase_c_components_are_owned`, the kernel boards, the connectivity register and the Phase D
   drives read the database directly. Do NOT re-emit a CSV to make a gate green.
6. `node scripts/checks/export_from_either_source_is_identical.mjs --write` after the LAST apply →
   byte-identical, 0 project refs embedded
7. `node scripts/verify_deploy_parity.mjs --ref=htdblwldjkcgjvmqkbeh --all` → every edge function carries the repo's code

8. *(retired 2 Sep 2026 — the founder removed the phase freezes totally. 4 Sep 2026: `fn_phase_a_baseline_drift`
   and `fn_phase_b_baseline_drift` were DROPPED (Phase E, `scripts/sql/phase_e_retire_the_frozen_baseline_boards.sql`);
   the organisation's validity is asserted by `fn_phase_a_organization_violations()` = 0 inside the boards)*
9. *(retired with 8)*

**AND AS OF 7 SEPTEMBER 2026 THERE IS NO ORGANISATION, NO WORKFLOW AND NO KERNEL GATE EITHER.**

The founder dismantled the structure in four rulings that day, in his words: *"actually remove the
whole organization chart that you made cause its trash"*; *"so no departments from now"* and *"no
tasks excepts what i confirm"*; *"dont link everything to CEO. i didnt say that. keep them unlinked
now till we come up with the new structure"*; and *"remove everything except the company knowledge,
terms and conditions and website related stuff and my decisions which i shared earlier. i dont want
any pre programmed workflow as things will totally be different"*, then *"i said remove the kernel
gates"*. When I archived the chart before deleting it he said *"not archive. remove totally"*.

**What the company is now:** two seats — `ceo` and `customer_support` (the WhatsApp agent) — with no
departments, no tasks, no workflows, no handoffs, no subscriptions, no executors and no kernel
write/trace gates. 1,664 components are deliberately UNOWNED and stay that way until he sets the new
structure.

**Do not** invent a third agent, write a department into anything, create a task he has not
confirmed, rebuild a workflow registry, or re-attach a kernel gate. If work fits neither seat, that
is the finding — say it and stop. See `.claude/skills/quotesdone-work-is-assigned/SKILL.md`.

**Two guards survived on purpose and must stay:** the TRUNCATE guard on 100+ tables (a whole-table
wipe is never a workflow, always a mistake), and `anon_cannot_execute_security_definer` in CI —
that one is security, not structure.

**Thirteen checks were RETIRED**, not weakened, because every noun they asserted was deliberately
deleted: the kernel positive controls, the Phase C injected-defect guards, the write guard, active
signal types, company_is_fully_wired, application_source_of_truth, three Phase D checks, the kernel
boards, the failed-scheduled-run reader, and both org-connectivity checks. Each is
`scripts/checks/<name>.RETIRED.mjs` with a header saying what it checked and why it is gone. **Do
not resurrect them.** When the new structure exists, write new checks against THAT structure.
A check edited until it goes green against an empty schema asserts nothing while still looking like
a guard — which is worse than no check.

Still green and still guarding: `kernel_invariants`, `cancellation_reaches_the_kernel`,
`every_discharge_claim_reaches_its_table`, `anon_cannot_execute_security_definer`,
`phase_c_components_are_owned` (rewritten: a component that NAMES an owner names a live one, and no
component names a department), `canonical_routine_manifest`,
`export_from_either_source_is_identical`, `receipts_never_wait_on_the_founder`.

---
**THERE ARE NO PHASE FREEZES. THERE ARE NO PHASE GATES.** Founder ruling, 7 Sep 2026, in his
own words: *"phase A to D where steps to make sure the structure was fine. their freezes or implied
limits should be removed totally. i dont want any limits in the workflow"* and *"the only thing on
hold open router. any other limit or freeze or gates that is affecting us should be removed.
otherwise we will never be able to finish this code"*.

Phases A to D were scaffolding for getting the structure right. They did their job. Nothing about
them constrains work any more:

- Workflow ownership, workflow order, states and transitions, gates, business rules, handoff
  accountability, category-overlay authority, departments, canonical roles and overlays are all
  **freely changeable**. No change request, no `app.phase_a_change_reason`, no
  `app.phase_b_change_reason`, no approval.
- The digest guard `z90_phase_b_freeze` was removed 2 Sep 2026. The baseline drift boards
  `fn_phase_a_baseline_drift` and `fn_phase_b_baseline_drift` were dropped 4 Sep 2026. The last
  three statement guards — `a10_phase_b_workflow_owner_guard`, `a10_phase_b_owner_guard` and
  `a10_phase_b_handoff_guard`, with their functions — were dropped 7 Sep 2026
  (`scripts/sql/the_last_phase_b_guards_come_off_because_the_founder_removed_every_limit.sql`).
- **Do not reinstate any of them**, and do not write a new check that asserts a phase baseline is
  unchanged. A structure that cannot move cannot be corrected, and the live organisation has moved
  since those registers were written.

**The ONE thing still on hold is OpenRouter.** That is the founder's only standing limit.

**What stays, and is not a limit:** the append-only triggers on `org_phase_baseline` and
`phase_b_change_request` (they stop history being rewritten, they refuse no change), and every
guard that protects correctness rather than structure — CHECK constraints, foreign keys,
`fn_org_authority_guard`, credential tests, verify_jwt drift. Section 6 still applies to those.

**Phase B approval never claimed the runtime works.** Wiring gaps recorded in
`public.phase_b_phase_c_wiring_gap` are real work, not Phase B defects.

Steps 5–7 replace `project_parity.mjs`, retired 15 Aug 2026 with the project it compared against.
See `docs/agents/RETIRED_TWO_PROJECT_CHECKS.md`. **Do not reintroduce a check that reads
`pglpqrhvozwepymcuunn`** — it 404s, and a 404 read as "no drift" is a green light over nothing.

Only when all of it is clean does the one line go out.

## 10. Never state anything you are not 100% sure of

Standing instruction from the founder, 11 Aug 2026. It applies to **every** statement — findings,
audit verdicts, commit messages, answers to his questions, and offhand remarks alike.

- **State what you measured, not what it implies.** "The scan covered text columns in `public` for
  three patterns and found X" is honest. "There is no demo data" is a claim about everything you did
  not look at.
- **A narrow check does not license a broad claim.** This rule was created because a search of
  *column names* for `is_demo`/`is_test` returned nothing and that was reported as "nothing marks a
  row as demo today". Six clearly-marked demo suppliers had existed since 7 Aug — the convention was
  `ZZ DEMO — …` in the name and `@example.invalid` in the email, in the data, not in the schema.
- **Say the boundary out loud.** Name what the measurement covered and what it did not. An unbounded
  verdict from a bounded check is the same defect as a scorer reporting on the wrong subject.
- **If you are not sure, measure it or say you are not sure.** Both are acceptable. Guessing
  confidently is not, and neither is padding a guess with hedging language so it reads as knowledge.
- This does not license silence or endless checking. Measure, then speak plainly about what you
  measured.
