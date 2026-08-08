# PAUSED 2026-08-06 ~16:00 UTC — rows #2 and #3, both resumable without re-deriving anything

## ROW #2 (OS.txt) — 107/110 (97%). Baseline at session start was 47/110.
`node scripts/staging/verify_os_blueprint.mjs` — 110 checks, read-only, PRODUCTION, ~10 min.

**Three remain, and NONE of them needs code written today.**

1. `comp-10-02-gather-data` — **CLOCK-BLOCKED ONLY.** The mechanism is fixed and deployed to both
   projects. 29 `kind='action_gate'` rows written before the 10:45 UTC repair carry hard-coded
   `sources='[]'`, and `decision_log` is append-only — `declog_immutable` RAISES on UPDATE and
   DELETE — so they cannot be corrected. The last one leaves the 24-hour window at
   **2026-08-07 10:15:03 UTC**. Re-run the check after that and it reads MET with no code change.
2. `comp-14-should-escalate` — **CLOCK-BLOCKED ONLY.** Same shape. 34 routed escalations name no
   party (30 `Secretary`, 4 `cat:signage`), all written before 10:49:05 UTC, all immutable ledger
   rows. Observed draining: 35 at 12:35, 34 at 13:16. Window empties **2026-08-07 10:49:05 UTC**.
3. `contract-consolidation` — **NOT a code gap. A throughput/capacity decision that is the
   founder's.** 127 of 675 deliveries closed = 19% against a required 50%. The closing side is
   built and running end to end (fn_event_consolidate on cron; 371 correlation chains rolled up;
   9 `priority.updated` emitted and all 9 delivered). The blocker is that the organisation closes
   ~4.4 tasks/day while the bus produced 329 events/day. Back-pressure (cap 25 open bus tasks per
   department) is deployed and stops the denominator diluting further, but no standing
   back-pressure task has been closed yet, so **the ratio has not moved and must not be claimed**.

   **The founder's options, unchanged:** (a) wait — the arithmetic now improves on its own because
   one closure of a standing task returns a result to EVERY delivery attached to it; (b) raise
   `cos_execute`'s per-run budget or cron frequency — roughly 4x LLM spend on a company with zero
   revenue; (c) give event-derived tasks a guaranteed share of each `cos_execute` run.
   **Do NOT** mass-close tasks, back-date closures, or reorder the queue purely because a check
   scores it — all three were considered and refused.

> **DO NOT re-derive any of this.** `docs/sessions/ROW2_WORKLIST.md` (45 requirements triaged with
> evidence), `SCORER_DEFECTS.md` (76), `SCORER_DEFECTS_ROUND2.md` (72), `SCORER_DEFECTS_ROUND3.md`
> (92, split real-gap vs loose-check). The scorer survived three adversarial rounds and is FROZEN;
> 74 loose checks are deliberately documented rather than chased.

## ROW #3 (OS 2.txt) — NOT MEASURED. Scorer built but never run to completion.
`scripts/staging/verify_os2_blueprint.mjs` + `scripts/staging/os2_blueprint/*.mjs` (6 modules:
screens_1_9, screens_10_17, layers_1_8, layers_9_15, sections_21_40, ui_closure).

**Status: the modules exist and were self-tested per-section by their authors, but the FULL run was
never completed and the adversarial refutation phase was killed part-way.** So there is no
trustworthy number for row #3 yet. The prior audit's figure was 1/59 (2%) — treat that as the last
known measurement, not as current truth.

**First action on resume:** run `node scripts/staging/verify_os2_blueprint.mjs` to completion (it is
slow — every check is a sequential rate-limited management-API read; several minutes is normal and
is NOT a hang), then finish the refutation round before quoting any percentage.

**Row #3's defining fact, already measured:** it carries 21 BUILT_BUT_UNREAD items. Production
computes an autonomous company every night and displays none of it. `graph_nodes` — 323 nodes,
300 edges, rebuilt by an ACTIVE nightly cron, **zero readers** in routines, views, crons, edge
functions and `src/` — is the worked example, and it feeds three things the file asks for:
Mission Control, the Company Brain and the Interactive Company Map.

**Dependencies are wired and the build is green** (typecheck clean, 492/492 static pages):
`components.json` created, 11 shadcn components added, 9 pre-existing verified hash-identical.

## THE FIVE SCORER DEFECT CLASSES — carry these into every future row
Row #2's scorer failed adversarial review three times (76 → 72 → 92 defects) and reported a false
110/110 before they were found. All five are pre-empted in row #3's modules; check they hold.
1. **The only reader is the writer.** Passing a COLUMN name to a helper built for TABLE names makes
   its self-exclusion inert, so the UPDATE counts as a read. Exclude the writer BY NAME, deduplicate
   pg_proc OVERLOADS, and never count a view as a reader unless something reads the VIEW.
2. **Population standing in for delivery.** 17 rows matched vs 3 actually rendered.
3. **One row scores a whole mechanism.** Where the requirement says EVERY/EACH, use a per-row NOT
   EXISTS, never a global count > 0. Bound recency, require a coverage ratio.
4. **Satisfiable by flipping a flag.** Any excuse flag needs a written reason AND a dated expiry.
5. **Evidence that does not compute the verdict** — no hardcoded prose, same population as the
   verdict.
Plus: never interpolate table content into a LIKE PATTERN unescaped (`_` is a wildcard), and never
write a check no implementation could satisfy — over-hardening is as much a failure as loosening.
