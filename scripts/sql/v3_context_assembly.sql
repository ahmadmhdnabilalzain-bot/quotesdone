-- The V3 assembler is a distinct name: fn_agent_context already exists in two text-returning
-- overloads that every edge function calls. A third overload of the same name would have been
-- resolvable by argument count today and ambiguous the first time a default changed.
-- Stage 5 — one authoritative context-assembly path.
--
-- Before this, an agent's prompt was built from agent_knowledge rows filtered by agent_key
-- and nothing else: no department inheritance, no role identity, no task class, no category,
-- no freshness, no budget, and no record of what was retrieved. fn_agent_context is the one
-- path that assembles a task-time context and names every record it used, so the decision
-- trace can carry the knowledge ids instead of a prose summary.
--
-- Deterministic rules (authority, KPI definitions, decision playbooks, policy) are returned
-- as structured rows from SQL, never from a similarity search. Narrative is ranked lexically
-- against the task text and cut to the caller's character budget.

-- One narrative slice: deterministic filters first (layer, scope, runtime eligibility,
-- supersession), lexical ranking second, and a hard character budget last. Returns the
-- record ids alongside the text so the caller can record what it actually read.
-- fn_context_slice IS NOT DEFINED HERE ANY MORE (14 Aug 2026).
-- It lived in three files and was silently reverted twice in one session; the second revert kept
-- the filter but dropped the `match` label that fn_knowledge_gap counts, so the gap signal fired
-- on every task. Authoritative definition: scripts/sql/v3_repair_03_retrieval.sql
-- Apply that file after this one. Do not re-add a copy here.


revoke all on function fn_context_slice(text, text[], text, text, tsquery, integer) from public;

-- fn_agent_context_v3 IS NOT DEFINED HERE ANY MORE (14 Aug 2026).
-- It lived in three files and was silently reverted twice in one session; the second revert kept
-- the filter but dropped the `match` label that fn_knowledge_gap counts, so the gap signal fired
-- on every task. Authoritative definition: scripts/sql/v3_repair_05_ctx_v3_query.sql
-- Apply that file after this one. Do not re-add a copy here.

revoke all on function fn_agent_context_v3(text, text, text, text, integer) from public;
grant execute on function fn_agent_context_v3(text, text, text, text, integer) to service_role;
