---
name: a-picker-that-walks-its-own-successes
description: "An oldest-first backfill picker on a plain index gets slower with every row it embeds; the fix is a partial index on the un-done rows, and the gate that assumes an empty company reddens on the first real customer"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-06T10:58:52.774Z
---

Two findings from 6 Sep 2026, both "the number measured the wrong subject":

1. **kb_embed's oldest-first claim** ordered on `kb_chunks_created_at_desc_idx` and filtered `embedding_gte is null`. EXPLAIN idle: Rows Removed by Filter 99,466, 34,280 buffers, 98 ms — the embedded prefix the scan walks past grows by ~60 rows a minute, so the picker degrades with every success and hits PostgREST's 8 s wall under load (three timeouts on 6 Sep while seven sessions drove the DB). Fix: `kb_chunks_unembedded_created_idx on (created_at) where embedding_gte is null` (scripts/sql/the_embedding_picker_reads_a_partial_index.sql), built CONCURRENTLY as a single statement (a one-statement API call is not a transaction block).

2. **phase_d_dispatch_reaches_executed** asserted `count(customers) = 0` inside its aborted drive. That measured whether the company had customers, not whether the drive wrote one; a real person registered at 07:38 UTC and PR #524 went red on him. Fix: snapshot the four business tables before the drive and assert the DELTA is 0, as ai_cost_log and cron.job already were.

**Why:** a check or a picker whose cost or verdict depends on how far the company has progressed (rows embedded, customers signed) is measuring progress, not the thing it claims. **How to apply:** for backfills, index the remaining set, never the whole table; for gates against production, assert deltas inside the probe, never absolute business counts. See [[against-production-gates-vs-a-running-company]] and [[a-check-held-open-by-pre-fix-rows]].
