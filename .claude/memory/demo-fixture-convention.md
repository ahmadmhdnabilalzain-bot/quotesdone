---
name: demo-fixture-convention
description: There are TWO demo conventions in leads, not one — ZZ DEMO/@example.invalid and QD Demo/@example.com/source=demo_factory/tag qd_demo. A filter knowing only the first misses a whole family.
metadata:
  type: reference
---

Demo rows are marked in the **data**, not the schema — and there are **two** conventions. A filter
that knows only the first silently leaves the second standing.

| Convention | Markers |
|---|---|
| hand-written fixtures | `company_name ilike 'ZZ DEMO%'`, `email ilike '%@example.invalid'` |
| demo_factory output | `company_name ilike 'QD Demo%'`, `email ilike '%@example.com'`, `source = 'demo_factory'`, `tags && array['qd_demo']` |

Measured 15 Aug 2026 while emptying the marketplace:

- **production** 20,471 leads → 6 match, **all** of them `ZZ DEMO`, **0** `demo_factory`
- **staging** 58 leads → 56 match (6 `ZZ DEMO` + 50 `demo_factory`)

So a purge written against the first convention alone would have cleaned production by luck and
left 50 fake companies on staging. Always count each marker separately before deleting, and check
both projects — the families are not distributed the same way.

`supplier_capabilities` is `ON DELETE CASCADE` on `leads`; **`supplier_score` is not** — it keys on
`lead_id` with no cascade, so deleting leads leaves orphan score rows behind (6 on production, 56 on
staging). That is a count reading "20,471 suppliers scored" for companies that no longer exist.

Related: [[a-key-written-in-two-shapes]] — same lesson, different table: never resolve to the first
matching shape, enumerate them all.
