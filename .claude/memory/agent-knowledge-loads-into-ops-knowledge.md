---
name: agent-knowledge-loads-into-ops-knowledge
description: "Cert/domain knowledge reaches agents via fn_agent_context_v3 -> fn_context_slice -> ops_knowledge (role/dept/category scoped, tsv-ranked); NOT agent_knowledge or kb_chunks"
metadata: 
  node_type: memory
  type: project
  originSessionId: 95f8dff2-f1de-4ffd-b43c-3c5d91878414
  modified: 2026-08-27T22:53:30.642Z
---

Measured 28 Aug 2026 (full detail: `docs/expertise/AGENT_KNOWLEDGE_PATH.md`). To make an agent
certification-grade, load its knowledge into **`public.ops_knowledge`**, NOT `agent_knowledge` and NOT
`kb_chunks`.

`fn_agent_context_v3` (the prompt builder for every agent — agent_brain/action_worker/dept_plan/etc.)
sources domain/professional knowledge through **`fn_context_slice`**, which reads `ops_knowledge` where
`runtime_eligible AND supersession_state='current' AND layer=<slice>`, scoped by:
- `role_specific` → `role_key = any(agent's packaged role_ids)` (from org_role_identity)
- `department_shared` → `dept_key = any(fn_dept_scope(agent.department))`
- `category_specialist` → `category_key`
- `company_core` → `scope_type='company'`
…and RANKS by `ts_rank(tsv, fn_task_tsquery(task_text))` (`tsv` is generated). So knowledge only
surfaces when it is (a) in ops_knowledge with the right scope, and (b) topically matched by the task.

Three traps that cost time:
1. `agent_knowledge` is read by v3 ONLY for `layer='experience' AND validation_status='validated'`
   (≤8 rows). Cert knowledge loaded there as `profession`/`author_verified` does NOT surface — the
   `profession` layer is never read by v3. (Existing exam-sourced profession rows are invisible too.)
2. `kb_chunks` (97k embedded corpus) is NOT on the agent-context path — it feeds `kb_search`/`kb_match`
   (FAQ, classification). Embedding backfill helps those, not agent expertise. See
   [[retrieval-is-keyword-not-vector]].
3. The V2 knowledge packs gave each role a competency MAP (what to master) but not the technique
   CONTENT. Their own `certification_rule`: "not certified by file ingestion — must pass blind
   evaluations" — so the exam loop (step 6) is mandatory; ingestion only makes knowledge retrievable.

**UPDATE 28 Aug (corpus path):** the founder's bar is ~10,000 pages/agent, which cannot be hand-authored
ops_knowledge — it is a CORPUS. `fn_agent_context_v3` was wired with a `field_corpus` section that, when
a task is supplied, retrieves from **`kb_chunks WHERE category = any(fn_dept_scope(agent.department))
AND fts @@ fn_task_tsquery(task)`**, ts_rank-ranked, top 12, budgeted. So bulk knowledge now reaches
agents: ingest a field's sources into `kb_chunks` tagged with a category that equals one of the agent's
`fn_dept_scope` values (QA→`qa`, legal→`legal`, finance→`finance`…), and it surfaces task-ranked.
Loader: `scripts/kb/ingest_extracted.mjs` (chunks an extracted doc into kb_chunks, fts generated,
embeddings backfilled later by the free in-region kb_embed). Docs: `docs/expertise/CORPUS_INGESTION.md`,
`AGENT_KNOWLEDGE_PATH.md`. Two fields seeded (ISTQB→qa 174 chunks; UAE Companies Law→legal 199 chunks).
`ops_knowledge` role_specific is still the place for curated high-signal anchors; the corpus is the bulk.

**How to apply:** proven loader is `scripts/sql/expertise_istqb_ctfl_qa_test_design.sql` (ISTQB CTFL →
QA role_keys). Mirror it: ops_knowledge role_specific/department_shared, ~24 NOT NULL fields set from
an existing row's shape, `tsv` auto-generated, `runtime_eligible=true`. Verify with
`fn_agent_context_v3(agent, task_class, task_text)` → the content appears in `role_knowledge`,
task-ranked. QA packaged role_keys: qa-and-testing-{reviewer-auditor,director,operations-specialist,
analyst-controller}. See [[role-certification-map-exists]].
