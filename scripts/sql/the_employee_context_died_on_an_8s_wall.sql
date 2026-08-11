-- THE EMPLOYEE RAN WITH NO EMPLOYMENT CONTEXT, ROUGHLY HALF THE TIME, AND NOTHING SAID SO.
--
-- MEASURED on production 11 Aug 2026 from agent_runs.counts, which agent_brain writes on every turn:
--
--   docs 08:50  prompt_chars 53,188  stable_chars 26,978   <- context present
--   docs 09:50  prompt_chars 16,691  stable_chars      0   <- context ABSENT
--   docs 10:50  prompt_chars 53,581  stable_chars 27,060
--   docs 11:50  prompt_chars 53,530  stable_chars 27,066
--   docs 12:50  prompt_chars 16,912  stable_chars      0   <- ABSENT
--   docs 13:50  prompt_chars 15,943  stable_chars      0   <- ABSENT
--   docs 14:50  prompt_chars 16,633  stable_chars      0   <- ABSENT
--
-- 36,641 characters of identity, company genome, risk register, employee record, authority limits,
-- profession and company knowledge simply were not there. agent_brain's layeredContext() does
-- `if(error || !data) return ''`, so the employee answered anyway, from the base prompt alone, and
-- both agent_runs and ai_cost_log recorded an ordinary successful turn.
--
-- THE WALL. PostgREST connects as `authenticator`, which carries statement_timeout=8s (service_role
-- has no override, so it inherits). Measured today:
--
--   fn_agent_context('docs', 24000)              7,302 ms
--   fn_agent_context('docs', 24000, <question>)  7,200 ms   (the query layers cost ~0.1 s, not the problem)
--   fn_ws_knowledge()                            9,697 ms   <- the whole budget, in one section
--   fn_ws_company()                                 22 ms
--
-- fn_agent_context executes the department's health_fn to build LAYER 3. For dept_key='knowledge'
-- (Administration & Operations) that is fn_ws_knowledge, a WORKSPACE DASHBOARD function, and it sits
-- either side of the 8-second line depending on cache warmth. That is exactly the alternating
-- pattern above.
--
-- WHERE THE 9.7 SECONDS GO — two sequential scans of kb_chunks (120,530 rows, wide text), from
-- explain (analyze) on production:
--
--   count(*) where source_kind='document'          2,183 ms   Seq Scan, 117,778 rows discarded
--   select * from kb_chunks order by created_at    1,424 ms   Parallel Seq Scan + top-N sort for 20 rows
--     desc limit 20
--
-- Neither column is indexed. The remainder is v_kb_coverage evaluated five times (86 ms each) and
-- the category group-by.
--
-- THE FIX IS TWO INDEXES, NOT A REWRITE. fn_ws_knowledge is also the Knowledge workspace panel the
-- founder opens, so the same two indexes pay twice, and rewriting a 60-line dashboard function to
-- save a section of an LLM prompt is the larger diff and the larger risk.
--
-- WHAT THIS DOES NOT DO: it does not make the failure loud. That half ships in the same change, in
-- agent_brain, because a context that vanishes silently is the defect and a faster query is only the
-- reason it currently vanishes.
--
-- Plain CREATE INDEX, not CONCURRENTLY: the management API runs this inside a transaction block,
-- where CONCURRENTLY is refused. kb_chunks takes roughly ten writes an hour (kb_embed, kb_deepen), so
-- a build measured in seconds is cheaper than the ceremony of working around it.

create index if not exists kb_chunks_source_kind_idx
  on public.kb_chunks using btree (source_kind);

create index if not exists kb_chunks_created_at_desc_idx
  on public.kb_chunks using btree (created_at desc);

analyze public.kb_chunks;
