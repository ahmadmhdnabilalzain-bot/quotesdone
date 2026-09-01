# Semantic retrieval — measured state and the real gap (28 Aug 2026)

Pipeline step 5 is "switch retrieval from keyword to semantic." Before switching anything, this is the
**measured** truth of how knowledge is retrieved in the estate today — it corrects the older shorthand
"5 of 6 routines use full-text, kb_match is the only vector one," which no longer matches the code.

## Embedding coverage (the store)

`kb_chunks` carries a generated `fts` tsvector AND an `embedding_gte` vector (gte-small, pgvector 0.8.0).

| table | rows | unembedded (`embedding_gte` null) |
|---|---|---|
| `company_faq` | 484 | **0** — the level-0 FAQ semantic path is whole |
| `kb_chunks` | 97,499 | **2,189** (2.2%) — invisible to `kb_match` until embedded |
| `leads` | 20,465 | 19,779 — supplier-lead matching, tied to the **paused** Apify acquisition; out of the knowledge scope |

The 2,189 unembedded `kb_chunks` are the knowledge-side coverage gap. The fix is the `kb_embed` edge
function (free in-region gte-small), which is **cron-driven and currently stood down**. gte-small runs
only in the Edge runtime (`Supabase.ai.Session('gte-small')`) — **Postgres/SQL cannot embed a query or
a chunk**, and the function is batch-limited to ~5–8 rows per invocation (WORKER_RESOURCE_LIMIT). So
draining 2,189 rows is ~274 invocations — a job for the backfill cron when the founder reactivates it,
not something to hand-drive under the stand-down.

## How each retrieval path actually works (measured)

| routine / path | method | notes |
|---|---|---|
| **`kb_search` (edge fn)** | **hybrid: gte-small vector (`kb_match`) + full-text, merged** | the best path, already built — but edge-only (embeds the query in the Edge runtime) |
| `kb_match` (SQL) | vector | takes a **pre-computed** query embedding; cannot embed on its own |
| `fn_faq_answer` (SQL) | vector | takes an embedding + min-similarity (the FAQ semantic answer) |
| `fn_classify_llm_failure` (SQL) | vector | semantic |
| `kb_query` (SQL) | full-text (`websearch_to_tsquery` on `fts`) | proper keyword retrieval |
| `fn_os_search` (SQL) | **naive `ILIKE '%q%'` on title/content/category, ordered by `effective_date desc`** | weakest: substring match ranked by recency, not relevance — part of the agent/OS-facing path |
| `fn_agent_context`, `fn_ws_knowledge`, `fn_org_exec_knowledge_fill` (SQL) | read `kb_chunks` by **category** (dump/filter), not by query relevance | the agent-context path does not rank by relevance at all |

**So the real gap is not "keyword vs vector" — it is that the agent-facing SQL paths
(`fn_agent_context`/`fn_os_search`/`fn_ws_knowledge`) retrieve by category or substring, while the one
relevance-ranked, semantic path (`kb_search`) is an edge function those SQL routines don't call.** SQL
can't embed, so a SQL routine can only be "semantic" by (a) calling `kb_search`/`kb_embed` over HTTP,
or (b) receiving a query embedding computed upstream.

## The switch — engineering plan (a dedicated session; still zero cost, but crosses the stand-down)

1. **Backfill the 2,189 unembedded `kb_chunks`** by letting the `kb_embed` cron run (or a bounded manual
   drain) — needs the founder's reactivation of that internal cron. Free, in-region, no business effect.
2. **Route the agent-facing retrieval through the hybrid `kb_search`** (edge) instead of `fn_os_search`'s
   ILIKE / the category dumps — i.e. the agent context path embeds its task query (Edge) and merges
   semantic + fts. This is a wiring change (SQL → edge HTTP for the embed step) and changes live agent
   behaviour, so it belongs to its own session with probes.
3. Leave `kb_query` (fts) as the deterministic fallback the hybrid path already blends in.

Until then, the highest-value, safe, zero-cost knowledge work is the ingestion pipeline (steps 2–4,
proven in `PIPELINE_PILOT_ISTQB.md`): collect + extract the cert corpus so there is more to retrieve.

## Note on the memory

The note `retrieval-is-keyword-not-vector` ("five of six routines use full-text; kb_match is the only
vector one") is **superseded by this measurement**: there are three SQL vector routines, `kb_search` is
already hybrid, and the sharper problem is the ILIKE/category agent-context paths, not fts-vs-vector.
