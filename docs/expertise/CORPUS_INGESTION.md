# Bulk corpus ingestion — the ~10,000-pages-per-agent path (28 Aug 2026)

The founder's bar for agent expertise is roughly **10,000 pages per agent**. That volume cannot be
hand-authored as `ops_knowledge` entries; it must live as a retrievable **corpus** and be pulled into
the prompt on demand, task-ranked. This is that path — built and verified end to end, zero cost.

## The two pieces

1. **Loader — `scripts/kb/ingest_extracted.mjs`.** Turns one extracted document (book-to-skill
   `full_text.txt`) into many `kb_chunks` rows: paragraph-aware chunking (~1,200 chars), page-marker /
   copyright / boilerplate stripped, mojibake sanitised to clean ASCII, tagged with a `category`,
   idempotent per `source_id`, batched insert. `fts` (tsvector) is generated on write and is
   immediately searchable; `embedding_gte` is backfilled later by the free in-region `kb_embed` path.

   ```bash
   node scripts/kb/ingest_extracted.mjs <full_text.txt> \
     --category <field> --source-id <id> --source-kind cert --citation "<cite>" --title-prefix "<p>"
   ```

2. **Retrieval wiring — `fn_agent_context_v3` now has a `field_corpus` section.** When a task is
   supplied it retrieves from `kb_chunks WHERE category = any(agent knowledge scope) AND fts @@
   task_tsquery`, ranked by `ts_rank`, top 12, budget-bounded. So the corpus reaches the agent, and it
   carries the passages that bear on the work — not a category dump. (SQL-side full-text today; the
   semantic/vector half is added when the query-embed edge path is wired — see
   `SEMANTIC_RETRIEVAL_STATE.md`.)

## Proven

- Ingested the full ISTQB CTFL v4.0.1 syllabus (~50 pages of body) → **174 `kb_chunks`** under
  `category='qa'` (which is in the QA agent's scope `[assurance, it, qa]`).
- `fn_agent_context_v3('ai_qa_specialist','test_design', <EP/BVA/decision task>)` now returns a
  `field_corpus` of **12 task-ranked ISTQB chunks** (Black-box Test Techniques, decision tables…),
  ranked by relevance to the task. No task → empty (correct). A finance agent asked about a VAT return
  pulls finance-scope chunks the same way.
- Phase A/B/C freeze drift 0; canonical routines 11/11; schema export identical.

## How categories map to agents

`kb_chunks.category` must equal one of the agent's knowledge-scope categories (org_role.knowledge_scopes
/ `fn_dept_scope(department)`). The existing corpus categories are supplier trades (construction-civil,
mep, testing-inspection, …) for the marketplace overlays; **functional-role cert knowledge is tagged
with the functional scope** (`qa`, `finance`, `legal`, …). Ingest each field's sources under its scope
category and they surface to that field's agents automatically.

## Scale (honest)

174 chunks ≈ 50 pages is one syllabus — ~0.5% of one agent's target. Reaching ~10,000 pages/agent is a
sustained collection effort: dozens of full standards / textbooks / syllabi per field, each run through
collect → extract → this loader. The machinery and the retrieval path now exist and are proven; the
remaining work is volume (and licensing judgement on which copyrighted sources the company may ingest —
a business call; government standards, laws and open materials are unambiguous). Embedding backfill
(free, in-region) upgrades this from full-text to semantic once the `kb_embed` cron runs.
