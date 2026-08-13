---
name: quotesdone-session
description: "ALWAYS APPLY on the QuotesDone repository. The founder's standing working rules: run continuously without check-ins, report only the single completion line or an honest hand-over, verify by execution in the same turn, deploy to BOTH Supabase projects, merge via PR, and never fabricate data to turn a gate green. Load this before doing any QuotesDone work — it governs how the session is run, not what is built."
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

A thing is fixed when it is **deployed to both Supabase projects and verified by measurement in the
same turn**. Not when it typechecks. Not when it reads correctly. Not "left for a later session".

- **Verify by EXECUTION, in the same turn.** Assert on a 200 **and** on a non-zero effect —
  `quote_compare` returned `{ok:false}` at HTTP 200 for weeks.
- **The aborted-transaction probe** is the tool for verifying a write without leaving one: do the
  write, count the effect, `raise exception` with the counts so it rolls back and the numbers still
  come out.
- **Never fabricate, back-date or mass-close data to turn a gate green.** If a fix makes a check
  HARDER because the old pass was false, that is correct — say so in the commit.
- **Never weaken a check.** A check that passes when the thing it checks is broken is worse than no
  check: it converts an outage into confidence.

## 5. Both projects, always

Production `htdblwldjkcgjvmqkbeh`, staging `pglpqrhvozwepymcuunn`. Nothing is left on staging.

```bash
node scripts/apply_sql.mjs <file.sql> --promote --ddl        # staging, then production, byte-identical
node scripts/deploy_functions.mjs --ref=<ref> [--production] <slugs>
node scripts/checks/project_parity.mjs                       # must print BOTH PROJECTS IN SYNC
```

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

1. GitHub Actions, Vercel, both Supabase projects swept for failures
   *(a zero-step Actions job means quota, not code)*
2. Row #3 scorer run **to completion** — `node scripts/staging/verify_os2_blueprint.mjs`
3. Pack scorecard re-run on **both** projects — `node scripts/kb/pack_scorecard.mjs --ref=… --packs=…`
4. `fn_os_portals_gates()` on **both**
5. `node scripts/checks/project_parity.mjs` → BOTH PROJECTS IN SYNC

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
