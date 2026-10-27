---
name: the-funnel-was-all-fixtures
description: Every quote.received (52/52) and rfq.created (12/12) event the company had ever recorded was a demo row carrying AED 1.9M of fake value; purged 16 Aug 2026.
metadata: 
  node_type: memory
  type: project
  originSessionId: 0f302c30-995c-49f2-be5e-72182155ebd1
  modified: 2026-08-16T05:59:27.801Z
---

Found 16 Aug 2026. `company_event` — the ledger the funnel tiles and marketplace analytics read —
was **100% fixture data** for the whole funnel: `quote.received` 52 of 52, `rfq.created` 12 of 12,
`payment.received` 7 of 8, carrying **AED 1,917,033** of fake quote value and **AED 412,875** of
fees never earned. Purged; the funnel now reads 0/0/1.

The scan that found it matters as much as the finding. A per-table scan generated from
`information_schema` over every text/varchar/char/json/jsonb column beat the hand-picked table list
the previous audit used. **The first version concatenated a row's columns with `||`, which returns
NULL if ANY column is null, and reported 46 rows; coalescing each column first reported 186.**
The in-database scanner `fn_demo_marker_scan` reports only ~30 — it excludes jsonb and misses the
hyphenated `ZZ-DEMO` variant. See [[demo-fixture-convention]].

Kept deliberately, because they only *mention* the convention: `decision_policy`
`demo_rehearsal_active` is a live safety switch that holds notifications during a rehearsal;
`undo_log` is its audit trail; `qa_fixture_purge_archive` and `escalations_archive_20260724` are
records of previous purges.

**Why:** the founder kept asking "where do these numbers come from". For the funnel the answer was
"a fixture seeded in August", and no display fix would have touched it.

**How to apply:** when a metric looks implausible for a pre-revenue company, check whether its
source rows carry the fixture markers before debugging the calculation. And never trust a marker
scan that concatenates columns without `coalesce`.
