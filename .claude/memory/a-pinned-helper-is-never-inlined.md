---
name: a-pinned-helper-is-never-inlined
description: "A SQL helper with SET search_path is never inlined, so as a per-row predicate it runs once a row at ~0.18 ms: an outside library call went from 131 ms to 808 ms. Put a column-only fast path at the call site and let the helper decide only what the columns cannot."
metadata:
  node_type: memory
  type: project
  modified: 2026-10-27T15:30:00.000Z
---

27 Oct 2026, customer_support, `scripts/sql/the_knowledge_library_tells_an_outside_audience_only_what_it_may_be_told.sql`.

The library readers needed one customer rule per row (`fn_knowledge_library_customer_facing(l.id)`). Measured on
production in a rolled-back transaction, over the 5,852 sales rows of the library:

- the same rule as an inlinable SQL function (no SET clause): 327 ms;
- the real helper (`language sql stable set search_path to 'public', 'pg_temp'`): 1,042 ms, ~0.18 ms a call;
- a column-only fast path at the call site, falling back to the helper: 21 ms, the same 5,844 rows.

**Why:** Postgres inlines a scalar SQL function only when it has no SET clause (and is not SECURITY DEFINER); a pinned
search_path, which the apply discipline and the Supabase advisor both require, forces a real call with a GUC save and
restore every row. The rule cannot drop the pin, so it cannot be fast inside the function.

**How to apply:** when a pinned helper becomes a per-row predicate over thousands of rows, write
`(cheap column test that is exactly the rule for the rows it clears) or helper(id)` at the call site, keep the helper as
the exact rule for everything else, prove the two agree on live data (same row count), and have a check hold every call
site to the one text. Time the outside and the internal call in the probe, not only the verdict.
