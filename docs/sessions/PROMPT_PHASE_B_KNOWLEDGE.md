# Phase B — prompt for the next session

Copy the block below into a new session. It is self-contained.

---

Load the `quotesdone-session` skill first, then read
`docs/phase-a/PHASE_A_FOUNDER_APPROVED_BASELINE.md`. Start Phase B.

## Phase A is frozen — do not touch it

Founder-approved 15 Aug 2026, tagged `phase-a-founder-approved-2026-08-15`, baseline recorded in
`org_phase_baseline`. **10 active departments · 90 canonical roles · 86 category overlays · 0 Phase A
organization violations.**

Do not redesign it, do not re-run a Phase A pass, do not "improve" the org chart. A statement-level
guard (`z90_phase_a_freeze`) refuses any change to those counts unless a formal change request is
stated in the same transaction. If Phase B genuinely needs a role that does not exist, that is a
Phase A change request with evidence — bring it to me, do not just set the change reason.

Confirm it is still frozen before you start and again before you finish:

```
select * from public.fn_phase_a_baseline_drift();     -- must be 0 rows
```

## What Phase B is

**Every AI employee must actually hold the knowledge its job needs** — from all sessions, not just
recent ones. Build what is missing. Test, build, test again, until each employee reads like twenty
years in its field rather than like a job title.

Phase B owns exactly what Phase A was forbidden to touch: knowledge content, knowledge scopes,
tools, KPI bindings, authority rows, model policy, retrieval and runtime readiness.

## Where it actually stands — measured 15 Aug 2026, not remembered

| | |
|---|---|
| `kb_chunks` | 97,499 · **84,219 embedded (86.4%)** |
| `agent_knowledge` | 2,055 rows |
| `employee_knowledge` | 900 rows across **66 of 90 active employees** |
| **active employees with NO knowledge row at all** | **24** |
| `ops_knowledge` · `knowledge_domain` | 8,256 · 107 |
| roles with no `knowledge_scopes` | 1 — `product_ux_designer`, deliberately deferred from Phase A |

## The first deliverable, and it costs nothing

**A per-agent knowledge inventory.** All 90 employees: what each holds, which layers, how many
records, where it came from, and what its job needs that it does not have. I asked for this and have
not seen it. It is free — no model call — and everything else in Phase B should be argued from it
rather than from an assumption about which agents are thin.

Start there. The 24 employees with nothing are the obvious first finding, but do not stop at the
count — say what each of them is supposed to know.

## The four deferred Phase A items — close these, they are yours

`product_ux_designer` carries `runtime_enabled = false` and is reported by
`fn_phase_a_deferred_items()` as `DEFERRED_TO_LATER_PHASES`:

`no_kpi` · `no_knowledge` · `no_authority` · `no_tools`

Closing them is Phase B work: give it a knowledge scope, a KPI, an authority row and whatever tool
it genuinely needs, then flip `runtime_enabled` to true. **Do not give it a tool to satisfy a
count** — the tools comparable specialists hold include `supplier_approve_clean` and `match_inquiry`,
and a UX designer holding those is worse than a red check.

## Money — read this before anything that spends

**Every OpenRouter route is still held open-circuit in `llm_route_health` (8 routes).** Phase A spent
USD 0.00. Do not release the hold on your own initiative.

Most of Phase B is free: inventory, gap analysis, ingestion, embedding (`kb_embed` uses an in-region
gte-small model and costs nothing — batch above 5 returns HTTP 546, so add invocations, never batch
size), retrieval wiring and deterministic tests.

The only part that genuinely needs paid inference is **judging whether an answer reads like an
expert**. Before that: tell me what you want to run, what it will cost in AED, and wait. Then release
only what that run needs. Known figures — the medium tier ran AED 0.12/case on Gate B; the large tier
has never been measured, so do not quote it as if it had.

## How to run the session

- No check-ins and no step-by-step updates. Work until done, then reply once.
- Do not ask me technical questions. Decide, do it, and tell me what you decided. Escalate only
  money, destructive production changes, and things only I can know.
- One Supabase project: `htdblwldjkcgjvmqkbeh`. Staging was deleted on 15 Aug; do not recreate it.
- Verify by execution in the same turn, never by "it typechecks". Use the aborted-transaction probe
  to prove a write without leaving one.
- Never weaken a check or fabricate data to turn a gate green. If a fix makes a check harder because
  the old pass was false, say so.
- Commit and merge via PR. Deploy with `node scripts/apply_sql.mjs <file> --apply`, which reads the
  definition back out of the database afterwards.

End with the one line if it is all true, or an honest hand-over naming exactly what is unfinished.
