---
name: a-nearest-neighbour-is-always-found
description: "gte-small cosine over ops_knowledge has a random-pair median of 0.837 (p90 0.872, p99 0.939) — an absolute similarity floor cannot separate a determination from noise; corroborate by the step's own lexemes and restrict to actionable record kinds"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-04T06:59:25.671Z
---

4 Sep 2026, MASTER_PLAN A1. The first four workflow steps the deterministic branch closed applied
`metric_definition "Rework rate"` to "Evidence: KPI scoreboard, OS health, goal periods" at 0.887,
and their candidate lists were FLAT (0.887, 0.886, 0.880, 0.879, 0.878). Measured on 3,600 random
in-scope pairs of runtime-eligible ops_knowledge rows: p05 0.788, **p50 0.837**, p90 0.872, p99 0.939.
The apply floor was 0.42. The genuine reveal-fee matches proven on 2 Sep scored 0.886–0.904 — the
same band as noise.

**Why:** a kNN always returns a top-1; with a small embedding model the whole corpus sits in a
narrow cosine band, so "match 0.887" is a coin-toss above the random median and a review-queue row
does not make a noise close honest.

**How to apply (fn_apply_playbook, scripts/sql/apply_playbook_needs_corroboration.sql):**
- retrieve only ACTIONABLE kinds (decision_playbook, decision_rule, standard_operating_procedure,
  exception_playbook) — the top-20 by cosine over all kinds is dominated by metric definitions and
  failure cases, so the SOP that does fit never reaches the applier;
- require keyword corroboration from the step's OWN words (process + step text, not the trigger
  JSON: a context blob adds dozens of lexemes and made "8 of 28" fail a step whose own text was
  covered): ≥2 lexemes and ≥30% of them in the record's tsv, plus cosine ≥0.85;
- measure the corpus noise before choosing any floor: `1-(a.e <=> b.e)` over random pairs.
Proven: "Define the metric and why it matters" → SOP 01 Metric Definition (0.878, 2 terms);
"Detect from health, drift or a failed gate" now runs uptime_check instead of a playbook;
"Change proposed, with the metric it should move and the baseline captured" correctly finds NO
corroborated playbook (nearest "north-star metric" 0.833) and parks awaiting the model.
Related: [[reasoning-layer-semantic-retrieval]], [[never-state-what-you-have-not-measured]].
