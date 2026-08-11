-- SECOND HALF OF THE 8-SECOND WALL: v_kb_coverage, five full scans of kb_chunks per call.
--
-- After the two indexes in the_employee_context_died_on_an_8s_wall.sql, fn_ws_knowledge fell from
-- 9,697 ms to 5,212 ms and fn_agent_context('docs') from 7,302 ms to 4,057 ms. Still not safe against
-- an 8-second PostgREST wall. explain (analyze) on production names the whole remainder:
--
--   coverage        (jsonb_agg over v_kb_coverage)   1,079 ms
--   coverage_kpis.gaps      (count where 'gap')      1,425 ms
--   coverage_kpis.thin      (count where 'thin')     1,507 ms
--   coverage_kpis.covered   (count where 'covered')    982 ms
--   coverage_kpis.total     (count over the view)      145 ms
--                                                   --------
--                                                   5,138 ms of the 5,212
--
-- v_kb_coverage aggregates count(k.id) grouped by catalogue slug. `id` is not in kb_chunks_cat, so
-- four of the five evaluations cannot use it and fall back to a SEQ SCAN of all 120,530 rows
-- (~1,000-1,400 ms each). The fifth — total — only needs the category and gets an index-only scan at
-- 145 ms. That 10x gap between two evaluations of the same view IS the diagnosis.
--
-- The covering index makes all five index-only. kb_chunks_cat becomes redundant the moment this
-- exists — same leading column, strictly less stored — so it is dropped rather than left to be
-- maintained on every insert for nothing.
--
-- Not attempted here: collapsing the five evaluations into one CTE inside fn_ws_knowledge. It would
-- save another ~600 ms, and it means rewriting a 60-line dashboard function the founder's Knowledge
-- workspace renders, to save a section of an LLM prompt. The index pays every caller of
-- v_kb_coverage — the workspace, the coverage KPIs, the gap detector — and is one line.

create index if not exists kb_chunks_cat_id_idx
  on public.kb_chunks using btree (category) include (id);

drop index if exists public.kb_chunks_cat;

analyze public.kb_chunks;
