# Rebuild seeds (knowledge data)

These `.seed.sql` files contain the knowledge DATA that was loaded via the REST API
(not through migrations). Load them into a fresh database AFTER running the migrations,
so the repo is a complete one-command rebuild source.

Load order (after `supabase/migrations/`):
1. `agent_knowledge.seed.sql`   — 511 rows: all agent + _global knowledge (management, marketing, IT, finance, legal, trades, canon core, writing voice, paid-media, gstack, humanizer...).
2. `dept_library.seed.sql`      — 1456 rows: the queryable depth stores (IT/finance/legal/procurement libraries + the 36 company-canon Q&A under department='company').
3. `marketing_library.seed.sql` — 317 rows: the UAE marketing library depth store.
4. `canon_eval_questions.seed.sql` — 79 rows: the omniscience scoreboard question bank.
5. `brand_assets.seed.sql`      — 27 rows: hosted brand-asset URL manifest.

`company_vision` and `org_agents` are seeded by their migration
(`20260724_company_vision_and_omniscience.sql`), not here.

Idempotent where a natural key exists (`on conflict do nothing`); otherwise intended for a fresh schema.
The raw source libraries are archived under `knowledge/` (the UAE library + brand-kit zips).
