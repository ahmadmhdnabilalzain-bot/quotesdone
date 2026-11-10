---
name: a-hand-run-apply-loop-stops-at-the-first-failed-probe
description: "LESSON 10 Nov 2026: a hand-written apply loop applied a file whose pre-apply probe had FAILED; use apply_new_manifest_lines or set -e, never `cmd | tail || break`"
metadata:
  type: lesson
  modified: 2026-11-10
---

**What happened (10 Nov 2026, #1880 apply).** `apply_new_manifest_lines.mjs` correctly STOPPED at
`a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work.sql`: its probe answered PROBE FAILED ("fewer than two
matchable ZZ DEMO suppliers"), a fixture problem, not a matching one. To resume the remaining files the session wrote a bash
loop `node rehearse_sql.mjs ... | tail -1 || break; node apply_sql.mjs ...`. The `|| break` tested `tail`'s exit code, not the
rehearsal's, so the failed rehearsal did not stop the loop and the file was APPLIED without a passing probe.

**Outcome.** No harm: the same probe with its name filter widened to the factory's bulk-corpus names ('QD Demo ...') answered
PROBE OK on the applied state, rolled back (44/44 rows, 12/12 confusables), and the probe and its check now accept both names.
But the rule "never apply without PROBE OK" was broken by the tooling, not by a decision.

**Rule.**
- Resume an interrupted apply by re-running `scripts/ci/apply_new_manifest_lines.mjs` on a range that starts AFTER the files
  already applied, or call its three steps per file with `set -euo pipefail`. Never `cmd | tail` in a gate.
- A probe that depends on standing fixtures must find what the factory actually builds: `makeSupplier` names 'ZZ DEMO ...',
  `--corpus` names 'QD Demo ...'. Build stand-ins with `QD_FIXTURES=1 QD_NO_STALE_SWEEP=1 node scripts/lib/demo_factory.mjs
  --corpus 2 --keep` (25 suppliers, one per trade; QD_NO_STALE_SWEEP avoids the demo_factory <-> e2e/fixtures import cycle
  that otherwise exits 13 with "unsettled top-level await").
