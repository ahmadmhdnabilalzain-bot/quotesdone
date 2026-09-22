-- kb_query READS THE INDEX INSTEAD OF SCANNING EVERY CHUNK (22 Sep 2026, it_engineer, CONN-01).
--
-- WHAT WAS MEASURED. 379 statement-timeout cancellations in 48 hours, all of them this routine.
-- kb_chunks is 148,326 rows and ~8 GB. inquiry_intake calls it up to twice a turn
-- (supabase/functions/inquiry_intake/index.ts, the specialist field-knowledge block) with no budget of
-- its own and a `catch (_e) {}` around it, so a customer waited up to 2 x 8 s for knowledge that never
-- arrived and nothing anywhere said the retrieval had failed.
--
-- WHY IT SCANNED. The body was:
--
--     where coalesce(p_query,'') = '' or c.fts @@ q.tsq
--
-- One WHERE clause covering two different questions. `coalesce(p_query,'') = ''` does not mention the
-- table, so it cannot be pushed into an index, and an OR with a non-indexable side makes the WHOLE
-- predicate non-indexable: the planner has no choice but to read every row and evaluate the OR on each
-- one. The GIN index kb_chunks_fts existed the entire time and could not be used.
--
-- It was also `LANGUAGE sql ... SET search_path`, and a SET clause makes a SQL function ineligible for
-- inlining, so there was never a chance of the caller's planner seeing through it to the real predicate.
--
-- WHAT THIS CHANGES. The two questions become two branches, each planned on its own:
--   * a real query  -> `c.fts @@ v_tsq` alone, with the tsquery in a plpgsql variable so it reaches the
--                      plan as a parameter and the Bitmap Index Scan on kb_chunks_fts is available;
--   * an empty one  -> there is nothing to rank by, so it is the most recently loaded chunks, by id,
--                      filtered by category (kb_chunks_cat_id_idx) rather than ranked across the whole
--                      table. BY ID AND NOT BY effective_date: there is no index on effective_date, so
--                      ordering by it would sort all 148k rows to answer a query that asked for nothing.
--                      id descending is the primary key read backwards.
--
-- The signature and the result columns are unchanged, and CREATE OR REPLACE keeps the existing grants
-- (this routine is not SECURITY DEFINER; it runs as its caller and always has).
--
-- BEHAVIOUR CHANGE, STATED. In the empty-query case the old body ranked every row at rank 0 (or 0.4 for
-- the matching category) and returned whichever 8 the sort happened to surface, which was effectively
-- arbitrary. The new branch returns the newest chunks of the asked-for category. That is a different
-- answer, and a defensible one; the old answer was not defensible, it was an accident of a tie-break.

create or replace function public.kb_query(p_query text, p_category text default null, p_limit integer default 8)
returns table(source_kind text, category text, title text, snippet text, citation text, effective_date date, rank real)
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_lim int := greatest(1, least(coalesce(p_limit, 8), 25));
  v_tsq tsquery;
begin
  v_tsq := websearch_to_tsquery('english', coalesce(p_query, ''));

  -- A query of nothing, or of nothing but stop words, has no lexemes to match: websearch_to_tsquery
  -- returns an empty tsquery, which matches no row. Ranking is meaningless either way, so both land here.
  if coalesce(btrim(p_query), '') = '' or v_tsq::text = '' then
    return query
      select r.source_kind, r.category, r.title, r.snippet, r.citation, r.effective_date, r.rnk
        from (
          select c.source_kind, c.category, c.title, left(c.content, 700) as snippet, c.citation, c.effective_date,
                 0::real as rnk, c.id
            from public.kb_chunks c
           where p_category is null or c.category = p_category
           order by c.id desc
           limit v_lim
        ) r
       order by r.id desc;
    return;
  end if;

  return query
    select r.source_kind, r.category, r.title, r.snippet, r.citation, r.effective_date, r.rnk
      from (
        select c.source_kind, c.category, c.title, left(c.content, 700) as snippet, c.citation, c.effective_date,
               (ts_rank(c.fts, v_tsq)
                + case when p_category is not null and c.category = p_category then 0.4 else 0 end)::real as rnk
          from public.kb_chunks c
         where c.fts @@ v_tsq
      ) r
     order by r.rnk desc nulls last, r.effective_date desc nulls last
     limit v_lim;
end
$fn$;

-- Not SECURITY DEFINER, so there is no definer privilege to revoke; the search_path is pinned anyway
-- because the body names kb_chunks and websearch_to_tsquery unqualified in one place each and a routine
-- that resolves against the caller's path is a routine whose behaviour is the caller's to change.
comment on function public.kb_query(text, text, integer) is
  'Full-text retrieval over kb_chunks. Two branches so the GIN index kb_chunks_fts is reachable: '
  'a real query matches on fts; an empty one returns the newest chunks of the category. CONN-01, 22 Sep 2026.';
