---
name: reasoning-layer-semantic-retrieval
description: "how agents now retrieve their OWN operating knowledge by meaning (vector), not keyword; the Step 4 build"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-02T20:34:55.304Z
---

Built 2-3 Sep 2026 (Step 4 of [[ten-step-autonomous-company-build]]). The founder's requirement:
agents reason from MEANING, not keyword cross-matching. Before: the deep reference corpus (kb_chunks)
was already hybrid semantic+keyword via the `kb_search` edge fn, but the agent's OWN operating
knowledge — `ops_knowledge` (authority, policy, decision playbooks, failure modes, department library)
— was retrieved ONLY by tsquery and had NO embedding column ([[retrieval-is-keyword-not-vector]]).

What exists now:
- `ops_knowledge.embedding_gte vector(384)` + HNSW cosine index + a partial index over unembedded rows
  (the backfill picker; without it the "next unembedded" scan times out under update churn).
- `fn_ops_knowledge_match(query_embedding vector(384), p_agent_key, k)` — cosine NN scoped EXACTLY as
  fn_agent_context_v3 scopes an agent (fn_org_agent_resolve → department via fn_dept_scope → packaged
  role ids from org_role_identity → company/external). SECURITY DEFINER, execute revoked from public.
- `kb_embed` edge fn embeds ops_knowledge too (free in-region gte-small, `Supabase.ai.Session('gte-small')`,
  384-dim). Target allowlist gained an idcol/orderby so ops_knowledge keys on record_id. Cron
  `kb_embed_ops_knowledge` (every minute, net.http_post, cred_cron_knowledge) drains it.
- `agent_brain` (the runtime) has `retrieveOps()`: embeds the task once and calls fn_ops_knowledge_match,
  injecting the result as a prompt layer — the operating-knowledge half of "reason from meaning". This
  is the wiring that makes it non-dead-code (the previous dev left the hook in fn_context_slice unwired).
- 565 senior-expert deep records authored (finance 94, legal 90, growth 91, marketplace 97,
  customer_experience 92, data_intel 101) by parallel Claude domain-expert agents, UAE professional
  standard, NO fabricated statutory figures, refund→founder as governing authority. Source of truth:
  `scripts/kb/deep_knowledge/*.jsonl`; ingest via `scripts/kb/ingest_deep_knowledge.mjs` (dept-scoped;
  layer mapped to the ops_knowledge_layer_ck allow-list; tsv is a GENERATED column — never insert it).

PROVEN by execution: a natural-language reveal-fee refund task retrieved the exactly-right playbooks by
meaning (top "I paid to reveal but the supplier never responded" 0.904; "What a complete refund case
for the founder must contain" 0.886); keyword search missed 7 of 8, ranking generic FAQ above the
playbooks. The final reasoning STEP still runs on the paid model (OpenRouter, off until launch); the
knowledge + linkage + semantic retrieval are all built and provable now because embedding is free.
