---
name: retrieval-is-keyword-not-vector
description: "Knowledge retrieval — re-measured 28 Aug 2026: embeddings are now 98% covered and kb_search is hybrid; the sharper gap is the ILIKE/category agent-context paths."
metadata: 
  node_type: memory
  type: project
  originSessionId: 95f8dff2-f1de-4ffd-b43c-3c5d91878414
  modified: 2026-08-27T22:17:15.185Z
---

**Re-measured 28 Aug 2026 — the 11 Aug picture below has changed; verify before quoting either.**

Current state (see `docs/expertise/SEMANTIC_RETRIEVAL_STATE.md` for the full table):
- **Embedding coverage is now ~98%**: `kb_chunks` 95,310 of 97,499 embedded (2,189 unembedded);
  `company_faq` fully embedded (0 gap). `leads` is mostly unembedded but that is supplier-lead
  matching tied to the paused Apify acquisition, not the knowledge scope.
- **`kb_search` (edge fn) is already HYBRID** (gte-small vector via `kb_match` + full-text, merged) —
  the best path, but edge-only because gte-small runs only in the Edge runtime; **Postgres/SQL cannot
  embed a query**. Three SQL vector routines exist now: `kb_match`, `fn_faq_answer`,
  `fn_classify_llm_failure`. `kb_query` is the fts path.
- **The real gap is not fts-vs-vector.** The agent-facing SQL paths retrieve by category or by naive
  `ILIKE '%q%'` ordered by recency (`fn_os_search`), not by relevance — `fn_agent_context`,
  `fn_ws_knowledge`, `fn_org_exec_knowledge_fill` read `kb_chunks` by category dump. So agents get
  category-filtered, un-ranked knowledge, while the one relevance-ranked semantic path (`kb_search`)
  is an edge function those SQL routines don't call.

**How to apply:** the fix is to route the agent-context retrieval through `kb_search` (embed the task
query in Edge, merge semantic+fts) — a live-behaviour change for its own session with probes — and to
let the stood-down `kb_embed` cron drain the 2,189 unembedded chunks (free in-region; ~274 batched
invocations, so cron not hand-driven under the stand-down). Embedding itself is free — see
[[embedding-is-free-not-openrouter]] for the batch ceiling.

The old 11 Aug measurement (kept for history): named FTS routines `fn_kb_retrieve`,
`fn_dept_library_search`, `fn_ops_knowledge_search`, `fn_memory_search`, `kb_query`; 39% embedded
(47,042 of 120,530). Those routine names did not surface in the 28 Aug scan — the estate evolved.
Related: [[instruments-report-on-the-wrong-subject]], [[role-certification-map-exists]].
