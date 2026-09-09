-- THE SALES ENGINEER READS THE WHOLE ESTATE, AND A GAP BECOMES A TASK.
--
-- The founder, 9 September 2026, rejecting what shipped hours earlier: "that reply with 'i dont
-- have that...' should never happen. there is no reason for him not to know whatsoever."
--
-- He is right, and the cause is UNDER-READING, not an over-tight floor. fn_sales_assist searched
-- exactly one table. Measured on htdblwldjkcgjvmqkbeh, 9 Sep 2026:
--
--   kb_chunks            2,686,026 rows ·   166,093 embedded (6.18%) · hnsw kb_chunks_emb_hnsw + gin kb_chunks_fts
--   ops_knowledge            9,139 rows ·     9,139 embedded (100%)  · hnsw ops_knowledge_emb_hnsw + gin ops_knowledge_tsv_idx
--   agent_knowledge          2,556 rows ·       606 embedded (23.7%) · NO tsvector, NO vector index
--     of which agent_key like 'cat:%'  1,627 rows ·         0 embedded
--   sales_knowledge          1,136 rows ·     1,136 embedded (100%)  · hnsw + gin  <- the only one it read
--   support_knowledge          408 rows ·         0 embedded         · gin only
--   category_specs              56 rows · category_quote_specs 141 rows · neither indexed for search
--
-- So the seat was reading 1,136 of 2,699,462 records — 0.042% of what it is entitled to. The
-- refusal was not the floor working. It was the corpus being nearly empty.
--
-- FOUR THINGS THIS FILE DOES.
--
-- 1. agent_knowledge GETS A tsvector. It is the only corpus here with no text index at all, and
--    the 1,627 'cat:%' rows — the live per-category technical body — carry ZERO embeddings, so
--    without a lexical index they are unreachable by any means. A generated column, so it cannot
--    drift from the content the way a trigger-maintained one can.
--
-- 2. THE FLOORS STAY, and are extended rather than relaxed. A nearest neighbour is ALWAYS found;
--    removing the floor to stop the refusal would have made the seat answer nonsense confidently,
--    which for a procurement question is worse than a slow answer. Two admission routes:
--      VECTOR ROUTE  — cosine >= p_min_similarity (0.86, fn_faq_answer's number) AND a lexical
--                      match at ts_rank >= p_min_rank. Unchanged.
--      LEXICAL ROUTE — for rows that HAVE NO EMBEDDING and therefore cannot be put to the vector
--                      floor at all: 2,519,933 kb_chunks rows, 1,950 agent_knowledge rows, all 408
--                      support_knowledge rows, and both spec tables. A stricter lexical bar
--                      (LEX_ONLY_FLOOR below) stands in for the corroboration the vector would
--                      have given. It is applied ONLY where embedding_gte is null, so a row that
--                      HAS a vector and failed the floor can never sneak in through the side door.
--    Nonsense still falls through both: the lexical index is the one instrument in this estate
--    that returns nothing for nothing, and it gates both routes.
--
-- 3. A REFUSAL BECOMES AN ACTION. The old handoff string is deleted. When nothing clears the
--    floors the routine now (a) records the question in sales_knowledge_gap, deduplicated and
--    counted, and (b) opens an org_tasks row owned by sales_engineer — the seat is active and
--    available in org_agents, so the FK holds. The asker is told the task number and the owner.
--    Both happen INSIDE this routine, for the same reason the decision log does: a caller cannot
--    forget what it never had to remember.
--
-- 4. THE GAP IS QUERYABLE. sales_knowledge_gap is the acquisition backlog — what to buy or write
--    next, ordered by how often it was actually asked, not by guess:
--       select question, asks, refusal, nearest_corpus, best_similarity
--         from sales_knowledge_gap where status = 'open' order by asks desc, last_asked_at desc;
--
-- WHAT THIS DOES NOT FIX, stated because overstating it would be the failure mode. All 8 routes in
-- llm_route_health carry open_until = 2126-08-15 under the founder's own hold and
-- fn_kernel_paid_provider_gate denies globally while any route is held. The seat can RETRIEVE and
-- cannot REASON: it can hand back the right passage, it cannot fuse three passages into one answer
-- or restate one in the asker's own words. Widening the corpus raises coverage enormously and is
-- the right fix regardless; it does not buy synthesis. Embedding is unaffected — it is free, in
-- region, and served before the gate (Supabase.ai.Session('gte-small'), ai_gateway line ~204).
--
-- F&B IS OUT OF SCOPE and is excluded by slug, not by hope: the five 'cat:' slugs below hold 79
-- rows the company does not serve.

-- ── 1. THE MISSING TEXT INDEX ──────────────────────────────────────────────────────────────────
alter table public.agent_knowledge
  add column if not exists search tsvector
  generated always as (
    to_tsvector('english'::regconfig,
      coalesce(topic, '') || ' ' || coalesce(content, '') || ' ' || coalesce(agent_key, ''))
  ) stored;

create index if not exists agent_knowledge_search_idx on public.agent_knowledge using gin (search);

comment on column public.agent_knowledge.search is
  'Generated 9 Sep 2026. Without it the 1,627 cat:% rows — 0 of which are embedded — were unreachable by any search the estate could run.';

-- ── 2. THE COVERAGE GAP LEDGER ─────────────────────────────────────────────────────────────────
-- An unanswered question is the single most valuable signal for what knowledge to acquire next, so
-- it is stored as data rather than as a sentence in a chat log. Deduplicated on the normalised
-- question so `asks` is a real frequency and the backlog can be ordered by demand.
create table if not exists public.sales_knowledge_gap (
  id                bigserial primary key,
  question_norm     text not null unique,
  question          text not null,
  asks              integer not null default 1,
  first_asked_at    timestamptz not null default now(),
  last_asked_at     timestamptz not null default now(),
  refusal           text,
  -- How close the estate got. A gap at best_similarity 0.84 is a phrasing problem; one at 0.31 is
  -- a genuinely absent subject. Collapsing the two would waste the acquisition budget.
  best_similarity   numeric,
  best_lexical_rank numeric,
  nearest_corpus    text,
  task_id           bigint references public.org_tasks(id),
  status            text not null default 'open',
  closed_at         timestamptz,
  constraint sales_knowledge_gap_status_check
    check (status in ('open', 'knowledge_added', 'not_a_gap'))
);
create index if not exists sales_knowledge_gap_open_idx
  on public.sales_knowledge_gap (asks desc, last_asked_at desc) where status = 'open';

comment on table public.sales_knowledge_gap is
  'Every portal question the Sales Engineer could not answer from retrieval, deduplicated and counted. The knowledge acquisition backlog, ordered by demand. Written from inside fn_sales_assist.';

-- ── 3. RETRIEVAL ACROSS THE WHOLE ESTATE ───────────────────────────────────────────────────────
-- Same signature as the routine it replaces, so `create or replace` keeps the ACL and no second
-- overload is left behind holding the old behaviour.
create or replace function public.fn_sales_assist(
  p_text            text,
  p_embedding       vector(384),
  p_min_similarity  numeric default 0.86,
  p_min_rank        numeric default 0.05,
  p_k               integer default 5,
  p_actor           text    default 'sales_engineer'
) returns jsonb
language plpgsql
volatile                       -- writes the decision log, the gap ledger and a task
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_k         int := greatest(1, least(coalesce(p_k, 5), 20));
  -- Per-corpus candidate width. Wider than the answer width so the floors have something to reject
  -- and the decision log records the near-misses that justify the floor.
  v_wide      int := greatest(v_k * 4, 20);
  -- LEXICAL-ONLY ADMISSION BAR. Applied only to rows with no embedding, where there is no vector
  -- to corroborate with. Deliberately 4x p_min_rank's default: it is carrying the whole burden of
  -- proof on its own. Measured basis in the report accompanying this file.
  -- Floored at 0.20 but never BELOW p_min_rank, so a caller that raises the corroboration bar
  -- raises this one too. Without that tie the lexical-only route would be untestable: the probe
  -- that proves a floor bites by raising it above the best hit would leave this route wide open
  -- and conclude the floors do not fire. A gate nobody can prove fires is not a gate.
  c_lex_only  numeric := greatest(0.20, coalesce(p_min_rank, 0));
  -- ponytail: kb_chunks lexical route takes the first 4,000 index matches and ranks those, not the
  -- global best of 2.5m unembedded rows. Ranking every match of a common term would be a table
  -- scan on every portal message. Raise it, or embed the rest, if recall proves short.
  c_kb_scan   int := 4000;
  -- Out of scope by the company's own exclusion, and by slug so it cannot drift.
  c_fnb       text[] := array['cat:catering-companies','cat:bakery-equipment-suppliers',
                              'cat:food-processing-equipment-suppliers','cat:hospitality-supplies-companies',
                              'cat:cold-room-and-refrigeration-suppliers'];
  v_tq        tsquery;
  -- LEXEME OVERLAP — MEASURED, TRIED, AND REJECTED AS AN ADMISSION RULE. Recorded here because a
  -- rejected relaxation is worth more to the next reader than a silent one.
  --
  -- Over 18 realistic portal questions on 9 Sep 2026, all 5 that fell through did so at
  -- lexical_rank EXACTLY 0.0000 while their best vector hit sat at 0.888–0.916. Not weak evidence
  -- — NO lexical match at all, because websearch_to_tsquery ANDs every term and no single passage
  -- contains all of "dubai & supplier & cover & abu & dhabi". So lowering p_min_rank would have
  -- recovered nothing, and the measurement is what says so rather than a guess.
  --
  -- The obvious relaxation was to corroborate on lexeme OVERLAP instead: admit a row that clears
  -- cosine 0.86 and carries at least 40% of the question's own lexemes literally. It was built,
  -- applied and measured. "does a Dubai supplier cover Abu Dhabi as well" then returned a joinery
  -- FIRE-DOOR CERTIFICATION passage — cosine 0.888, lexemes "dubai" and "suppli" present, subject
  -- entirely wrong. A confidently wrong answer to a procurement question is the exact failure the
  -- floors exist to prevent, so the relaxation was reverted within the hour. The overlap count is
  -- still computed and logged as a DIAGNOSTIC, because it is the cheapest signal for which gaps
  -- are a phrasing problem and which are a genuinely absent subject — it is simply not allowed to
  -- admit anything.
  v_lex       text[];
  v_need      int;
  v_cands     jsonb  := '[]'::jsonb;
  v_cited     text[] := '{}';
  v_answer    jsonb  := '[]'::jsonb;
  v_refusal   text;
  v_norm      text;
  v_gap       public.sales_knowledge_gap%rowtype;
  v_task      bigint;
  v_best_sim  numeric;
  v_best_rank numeric;
  v_best_corp text;
  v_handoff   text;
begin
  if coalesce(btrim(p_text), '') = '' then
    return jsonb_build_object('ok', false, 'answered', false, 'refusal', 'empty_query');
  end if;

  v_tq := websearch_to_tsquery('english', p_text);
  select array_agg(distinct u.lexeme) into v_lex from unnest(to_tsvector('english', p_text)) u;
  v_need := least(coalesce(cardinality(v_lex), 0), greatest(2, ceil(0.4 * coalesce(cardinality(v_lex), 0))::int));

  -- Every corpus produces the same six columns so the union is a fact about provenance, not about
  -- shape. `route` records HOW a row could be admitted, and is what stops a vector-bearing row
  -- being let in on lexical evidence alone.
  create temporary table if not exists _sa_cand (
    corpus text, record_id text, title text, content text, provenance text,
    similarity numeric, lexical_rank numeric, has_vector boolean, lex_hits int default 0
  ) on commit drop;
  -- truncate, not delete: the estate has a guard that refuses an unqualified DELETE, and a
  -- WHERE-less delete on a scratch table is exactly what that guard exists to catch elsewhere.
  truncate table _sa_cand;

  -- sales_knowledge — the seat's own pack. 1,136 rows, 100% embedded.
  if p_embedding is not null then
    insert into _sa_cand
    select 'sales_knowledge', k.record_id, k.title, left(k.content, 4000),
           coalesce(k.record_type, '') || case when k.domain is null then '' else ' · ' || k.domain end
             || case when k.epistemic_status is null then '' else ' · ' || k.epistemic_status end,
           (1 - (k.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(k.search, v_tq), 0)::numeric * (case when k.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(k.search) u where u.lexeme = any (v_lex))
      from sales_knowledge k
     where k.embedding_gte is not null
     order by k.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _sa_cand
  select 'sales_knowledge', k.record_id, k.title, left(k.content, 4000),
         coalesce(k.record_type, ''), null::numeric, ts_rank(k.search, v_tq)::numeric, false, 0
    from sales_knowledge k
   where k.embedding_gte is null and k.search @@ v_tq
   order by ts_rank(k.search, v_tq) desc
   limit v_wide;

  -- ops_knowledge — 9,139 rows, 100% embedded, tsv + hnsw.
  if p_embedding is not null then
    insert into _sa_cand
    select 'ops_knowledge', o.record_id, o.title, left(o.content, 4000),
           coalesce(o.record_type, '') || case when o.authority_tier is null then '' else ' · authority ' || o.authority_tier end,
           (1 - (o.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(o.tsv, v_tq), 0)::numeric * (case when o.tsv @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(o.tsv) u where u.lexeme = any (v_lex))
      from ops_knowledge o
     where o.embedding_gte is not null
       and coalesce(o.supersession_state, 'current') = 'current'   -- never quote a superseded rule
     order by o.embedding_gte <=> p_embedding
     limit v_wide;
  end if;

  -- kb_chunks — 2,686,026 rows. Both routes matter here and the lexical one matters most: 93.8% of
  -- this corpus has no vector at all, so a vector-only reader sees 6% of the category and trade
  -- field body.
  if p_embedding is not null then
    insert into _sa_cand
    select 'kb_chunks', c.id::text, c.title, left(c.content, 4000),
           coalesce(c.source_kind, '') || case when c.category is null then '' else ' · ' || c.category end
             || case when c.citation is null then '' else ' · ' || c.citation end,
           (1 - (c.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(c.fts, v_tq), 0)::numeric * (case when c.fts @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(c.fts) u where u.lexeme = any (v_lex))
      from kb_chunks c
     where c.embedding_gte is not null
     order by c.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _sa_cand
  select 'kb_chunks', x.id::text, x.title, left(x.content, 4000),
         coalesce(x.source_kind, '') || case when x.category is null then '' else ' · ' || x.category end
           || case when x.citation is null then '' else ' · ' || x.citation end,
         null::numeric, ts_rank(x.fts, v_tq)::numeric, false, 0
    from (select c.id, c.title, c.content, c.source_kind, c.category, c.citation, c.fts
            from kb_chunks c
           where c.embedding_gte is null and c.fts @@ v_tq
           limit c_kb_scan) x
   order by ts_rank(x.fts, v_tq) desc
   limit v_wide;

  -- agent_knowledge — 2,556 rows. The 1,627 'cat:%' rows carry no embedding, which is exactly why
  -- section 1 of this file exists. F&B excluded by slug.
  if p_embedding is not null then
    insert into _sa_cand
    select 'agent_knowledge', a.id::text, a.topic, left(a.content, 4000),
           a.agent_key || case when a.layer is null then '' else ' · ' || a.layer end,
           (1 - (a.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(a.search, v_tq), 0)::numeric * (case when a.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(a.search) u where u.lexeme = any (v_lex))
      from agent_knowledge a
     where a.embedding_gte is not null
       and not (a.agent_key = any (c_fnb))
       and coalesce(a.validation_status, '') <> 'quarantined'
     order by a.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _sa_cand
  select 'agent_knowledge', a.id::text, a.topic, left(a.content, 4000),
         a.agent_key || case when a.layer is null then '' else ' · ' || a.layer end,
         null::numeric, ts_rank(a.search, v_tq)::numeric, false, 0
    from agent_knowledge a
   where a.embedding_gte is null and a.search @@ v_tq
     and not (a.agent_key = any (c_fnb))
     and coalesce(a.validation_status, '') <> 'quarantined'
   order by ts_rank(a.search, v_tq) desc
   limit v_wide;

  -- support_knowledge — 408 rows, tsvector only. Lexical is not a fallback here, it is the only
  -- instrument the table has.
  insert into _sa_cand
  select 'support_knowledge', s.record_id, s.title, left(s.body, 4000),
         coalesce(s.record_kind, '') || case when s.domain is null then '' else ' · ' || s.domain end,
         null::numeric, ts_rank(s.search, v_tq)::numeric, false, 0
    from support_knowledge s
   where s.search @@ v_tq
     and coalesce(s.runtime_index_eligible, true)
   order by ts_rank(s.search, v_tq) desc
   limit v_wide;

  -- category_specs / category_quote_specs — 56 and 141 rows, no index of any kind. Small enough to
  -- vectorise the tsquery on the fly, and they answer the single most common portal question there
  -- is: what does this category actually require.
  insert into _sa_cand
  select 'category_specs', cs.category, cs.label,
         left('Supplier requirements: ' || coalesce(cs.supplier_requirements::text, 'none recorded')
           || E'\nCompliance checklist: ' || coalesce(cs.compliance_checklist::text, 'none recorded')
           || E'\nQuote fields: ' || coalesce(cs.fields::text, 'none recorded'), 4000),
         'category spec · ' || cs.category, null::numeric,
         ts_rank(to_tsvector('english', coalesce(cs.category,'') || ' ' || coalesce(cs.label,'') || ' '
                 || coalesce(cs.supplier_requirements::text,'') || ' ' || coalesce(cs.compliance_checklist::text,'')), v_tq)::numeric,
         false, 0
    from category_specs cs
   where to_tsvector('english', coalesce(cs.category,'') || ' ' || coalesce(cs.label,'') || ' '
         || coalesce(cs.supplier_requirements::text,'') || ' ' || coalesce(cs.compliance_checklist::text,'')) @@ v_tq
   limit v_wide;

  insert into _sa_cand
  select 'category_quote_specs', q.id::text, q.label,
         left('Aspect: ' || coalesce(q.aspect, '—') || E'\nMandatory: ' || coalesce(q.mandatory::text, 'unknown')
           || E'\n' || coalesce(q.note, ''), 4000),
         'quote spec · ' || coalesce(q.spec_group, ''), null::numeric,
         ts_rank(to_tsvector('english', coalesce(q.spec_group,'') || ' ' || coalesce(q.aspect,'') || ' '
                 || coalesce(q.label,'') || ' ' || coalesce(q.note,'')), v_tq)::numeric,
         false, 0
    from category_quote_specs q
   where to_tsvector('english', coalesce(q.spec_group,'') || ' ' || coalesce(q.aspect,'') || ' '
         || coalesce(q.label,'') || ' ' || coalesce(q.note,'')) @@ v_tq
   limit v_wide;

  -- ADMISSION. A vector-bearing row must clear the cosine floor AND corroborate lexically. A row
  -- with no vector must clear the stricter lexical-only bar. Nothing else is admitted.
  with judged as (
    select c.*,
           (c.has_vector and c.similarity >= p_min_similarity and c.lexical_rank >= p_min_rank) as ok_vector,
           ((not c.has_vector) and c.lexical_rank >= c_lex_only)                                as ok_lexical
      from _sa_cand c
  ), ranked as (
    select j.*, (j.ok_vector or j.ok_lexical) as cited,
           row_number() over (
             order by (case when j.ok_vector or j.ok_lexical then 0 else 1 end),
                      (case when j.has_vector then 0 else 1 end),
                      j.similarity desc nulls last, j.lexical_rank desc) as rn
      from judged j
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'cleared_floor', coalesce(r.has_vector and r.similarity >= p_min_similarity, false),
      -- Diagnostic only, deliberately NOT an admission criterion. See the header note.
      'lex_hits', r.lex_hits, 'lex_overlap_would_admit', (v_need > 0 and r.lex_hits >= v_need),
      'corroborated', r.lexical_rank >= (case when r.has_vector then p_min_rank else c_lex_only end),
      'cited', r.cited) order by r.rn) filter (where r.rn <= 40), '[]'::jsonb),
    coalesce(array_agg(r.corpus || ':' || r.record_id order by r.rn)
             filter (where r.cited and r.rn <= v_k), '{}'),
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id, 'title', r.title,
      'provenance', r.provenance,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'content', r.content) order by r.rn) filter (where r.cited and r.rn <= v_k), '[]'::jsonb)
    into v_cands, v_cited, v_answer
    from ranked r;

  select max(similarity), max(lexical_rank) into v_best_sim, v_best_rank from _sa_cand;
  select corpus into v_best_corp from _sa_cand
   order by similarity desc nulls last, lexical_rank desc limit 1;

  if cardinality(v_cited) = 0 then
    v_refusal := case
      when (select count(*) from _sa_cand) = 0 then 'no_candidates'
      when coalesce(v_best_sim, 0) < p_min_similarity and coalesce(v_best_rank, 0) < c_lex_only
        then 'below_similarity_floor_and_lexical_bar'
      when coalesce(v_best_sim, 0) < p_min_similarity then 'below_similarity_floor'
      else 'not_corroborated_lexically' end;

    -- ── THE FALLBACK IS AN ACTION, NOT A SENTENCE ────────────────────────────────────────────
    -- The founder's objection was never to the honesty of "I do not have that". It was to nothing
    -- happening afterwards. Something happens now: the question is kept, counted, and owned.
    v_norm := left(lower(regexp_replace(btrim(p_text), '\s+', ' ', 'g')), 400);

    select * into v_gap from sales_knowledge_gap where question_norm = v_norm;

    if not found then
      insert into org_tasks (title, detail, status, tier, action_class, assigned_agent,
                             priority, requires_evidence, needs_founder)
      values (
        left('Answer an unanswered portal question: ' || btrim(p_text), 160),
        'A customer or supplier asked this in the portal and the Sales Engineer could not source an '
          || 'answer from any corpus it searches (sales_knowledge, ops_knowledge, kb_chunks, '
          || 'agent_knowledge, support_knowledge, category_specs, category_quote_specs).' || E'\n\n'
          || 'QUESTION: ' || btrim(p_text) || E'\n'
          || 'REFUSAL: ' || v_refusal || E'\n'
          || 'CLOSEST THE ESTATE GOT: corpus ' || coalesce(v_best_corp, 'none')
          || ', cosine ' || coalesce(round(v_best_sim, 4)::text, 'n/a')
          || ', lexical rank ' || coalesce(round(v_best_rank, 4)::text, 'n/a')
          || ' (floors: cosine ' || p_min_similarity || ', lexical corroboration ' || p_min_rank
          || ', lexical-only ' || c_lex_only || ').' || E'\n\n'
          || 'DONE MEANS: the knowledge exists in a searchable corpus and this question returns it. '
          || 'Then set sales_knowledge_gap.status to knowledge_added.',
        'assigned', 'advisory', 'knowledge_gap', 'sales_engineer', 3, true, false)
      returning id into v_task;

      insert into sales_knowledge_gap
        (question_norm, question, refusal, best_similarity, best_lexical_rank, nearest_corpus, task_id)
      values (v_norm, left(btrim(p_text), 2000), v_refusal,
              round(v_best_sim, 4), round(v_best_rank, 4), v_best_corp, v_task);
    else
      v_task := v_gap.task_id;
      update sales_knowledge_gap
         set asks = asks + 1, last_asked_at = now(), refusal = v_refusal,
             best_similarity = greatest(coalesce(best_similarity, 0), coalesce(round(v_best_sim, 4), 0)),
             best_lexical_rank = greatest(coalesce(best_lexical_rank, 0), coalesce(round(v_best_rank, 4), 0))
       where id = v_gap.id;
      -- Asked repeatedly is the definition of urgent. The task's priority follows the demand.
      update org_tasks set priority = least(9, greatest(priority, 3 + v_gap.asks)), updated_at = now()
       where id = v_task and status not in ('done', 'cancelled');
    end if;

    v_handoff :=
      'I have not got a sourced answer to that yet, and I will not guess at a procurement question. '
      || 'I have recorded it and opened task #' || coalesce(v_task::text, '?')
      || ', owned by the Sales Engineer, with your question kept word for word. '
      || 'It is being looked into and you will get an answer on it.';
  end if;

  insert into sales_decision_log
    (actor, action, query, min_similarity, min_rank, k, candidates, cited, answered, refusal)
  values
    (coalesce(p_actor, 'sales_engineer'), 'assist', left(p_text, 2000), p_min_similarity,
     p_min_rank, v_k, v_cands, v_cited, cardinality(v_cited) > 0, v_refusal);

  return jsonb_build_object(
    'ok', true,
    'answered', cardinality(v_cited) > 0,
    'records', v_answer,
    'cited', v_cited,
    'candidates', v_cands,
    'corpora', jsonb_build_array('sales_knowledge','ops_knowledge','kb_chunks','agent_knowledge',
                                 'support_knowledge','category_specs','category_quote_specs'),
    'floor', jsonb_build_object(
      'min_similarity', p_min_similarity, 'min_rank', p_min_rank, 'lexical_only', c_lex_only,
      'lexemes_in_question', coalesce(cardinality(v_lex), 0), 'lexeme_overlap_needed', v_need, 'k', v_k,
      'rule', 'a row with an embedding must clear the cosine floor AND match the all-terms lexical query at ts_rank >= min_rank. A row with no embedding cannot be put to the vector floor at all and must clear the stricter lexical-only bar instead. lexeme_overlap_needed is reported as a diagnostic only: admitting on partial overlap was measured and returned a topically wrong passage, so it does not admit. A nearest neighbour is always found; a lexical match is not.'),
    'refusal', v_refusal,
    'gap_recorded', case when cardinality(v_cited) = 0 then true else false end,
    'task_id', v_task,
    'handoff', v_handoff);
end
$fn$;

-- create or replace preserves the ACL; the original file already revoked public and that revoke
-- stands. Restated for a fresh database, where the create is not a replace.
revoke execute on function public.fn_sales_assist(text, vector, numeric, numeric, integer, text) from public;
