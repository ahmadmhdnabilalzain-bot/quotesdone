-- THE IT ENGINEER GETS A KNOWLEDGE BODY THAT NEVER INVENTS A CVE
--
-- The founder, 9 Sep 2026, on what the IT seat must be: "about his knowledge, you have to keep him
-- really capable of such tasks" -- the tasks being, in his words, to "monitor everything ... in the
-- app and the website", to catch "a bug when a customer registers" or "the generated comparison
-- report is lagging", and to "monitor cyber attacks or hackers or malware files from customers or
-- suppliers".
--
-- WHAT THAT ASKS FOR, AND WHAT IT DOES NOT. It asks for a seat that can DIAGNOSE A LIVE SYSTEM.
-- That is a different body of knowledge from security theory, and the estate already holds the
-- second one: public.ops_knowledge carries 165 rows at layer 'it_security_deep', all embedded, all
-- runtime-eligible, covering the OWASP LLM top ten against this codebase, the auth and identity
-- model, the RLS and grant surface, the edge-function attack surface, PCI/PDPL mapping, MITRE
-- threat modelling and an auto-refreshed live-posture binding. Measured 9 Sep 2026, not assumed
-- from the session brief, which said ~164.
--
-- SO THIS BODY EXTENDS THAT ONE AND SUPERSEDES NONE OF IT. Not one it_security_deep row is
-- rewritten, retired or contradicted here, and fn_it_engineer_assist reads BOTH corpora so the
-- seat retrieves across the union rather than from a fork. What the 165 do not hold -- checked by
-- reading their titles, not inferred -- is the diagnostic half: how a fault in THIS system
-- presents, which instrument to read first, and the reasoning lenses this codebase has paid real
-- money to learn. A status column is not a delivery record. Zero cannot tell a dead guard from an
-- idle system. A guard that fires when the system works. A queue with no consumer. A finished
-- capability with no entry point. An instrument measuring the wrong subject. Those are worth more
-- to a monitoring agent than another restatement of OWASP.
--
-- WHAT IS DELIBERATELY NOT STATED, AND WHY IT IS ENFORCED RATHER THAN PROMISED. The accountant's
-- body holds no tax rate it cannot source. The equivalent failure for this seat is worse, because
-- it is confident and checkable and wrong: a fabricated CVE number, a claim that some version of
-- some component is vulnerable, or an assertion about what patch level this estate is running.
-- This session cannot browse the web and cannot read a vulnerability feed, so any such statement
-- would be invented. Six banned SHAPES are scanned for by the loader, which refuses the whole run
-- on a hit -- see scripts/kb/load_it_engineer_knowledge_pack.mjs -- and the eval proves the guard
-- bites by feeding it strings that carry each shape, because zero refusals cannot distinguish a
-- dead guard from a clean corpus. That is the same lens this file is teaching, applied to itself.
--
-- The word "CVE" is not banned; the identifier is. A record that explains HOW to determine whether
-- a published advisory reaches this estate is exactly what the seat needs. A record that names
-- CVE-2026-12345 is a hallucination with a checksum.
--
-- THE EVALUATION QUESTIONS ARE NOT IN THE CORPUS. They live in
-- scripts/kb/it_engineer_knowledge_retrieval_eval.mjs, in executable code, and the loader's
-- allowlist admits only records/*.jsonl. The estate has a documented defect where exam answers
-- leaked into the corpus an agent retrieves and 557 rows had to be quarantined; the separation is
-- structural, not a convention.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_gets_a_knowledge_body_that_never_invents_a_cve.sql --apply --ddl

-- ---------------------------------------------------------------------------------------------
-- 1. THE KNOWLEDGE BODY
-- ---------------------------------------------------------------------------------------------
-- Its own table, for the reason accountant_knowledge has one: a chart-of-accounts record surfacing
-- in an incident retrieval is a category error rather than a lucky hit. ops_knowledge stays where
-- it is and is read alongside, never merged into.
create table if not exists public.it_engineer_knowledge (
  record_id            text primary key,
  record_type          text not null,
  domain               text,
  title                text not null,
  content              text not null,
  structured_data      jsonb not null default '{}'::jsonb,
  source_ids           text[] not null default '{}',
  -- HONEST LABELLING IS A COLUMN, NOT A COMMENT. Eight values, each saying something different
  -- about how far the record may be trusted, and the CHECK stops a ninth being invented by a later
  -- import that finds the taxonomy inconvenient:
  --   method_engineering              authored diagnostic and operational method; not specific to
  --                                   this estate and does not go stale when a component changes
  --   diagnostic_lens                 a reasoning pattern this codebase has already paid for, with
  --                                   the incident that taught it
  --   estate_architecture_measured    a fact about THIS estate, obtained by measurement, with the
  --                                   query or file that produced it named in the record
  --   failure_signature               how a specific failure actually presents here and which
  --                                   instrument to read first
  --   security_posture_no_version_claim  security content naming no CVE, no version and no patch
  --                                   level -- what to look for and where, not what is unpatched
  --   resolve_from_live_system        the record EXISTS to say the answer is not held here, and to
  --                                   name the query, log or endpoint that holds it
  --   company_governance_ruling       a founder ruling bounding what this seat may do
  --   company_record_generated        generated by the loader from a live table; never typed
  epistemic_status     text not null,
  jurisdiction         text,
  pack_id              text not null,
  pack_version         text not null,
  body_sha256          text not null,
  runtime_index_eligible boolean not null default true,
  authority_effect     text not null default 'none',
  tags                 text[] not null default '{}',
  updated_at           timestamptz,
  ingested_at          timestamptz not null default now(),
  embedding_gte        vector(384),
  search               tsvector,

  -- A knowledge record may DESCRIBE authority. It may never CARRY it. Pinned, not trusted.
  constraint it_engineer_knowledge_authority_ck check (authority_effect = 'none'),
  constraint it_engineer_knowledge_epistemic_ck check (epistemic_status in (
    'method_engineering', 'diagnostic_lens', 'estate_architecture_measured', 'failure_signature',
    'security_posture_no_version_claim', 'resolve_from_live_system', 'company_governance_ruling',
    'company_record_generated'))
);

create index if not exists it_engineer_knowledge_search_idx on public.it_engineer_knowledge using gin (search);
create index if not exists it_engineer_knowledge_type_idx   on public.it_engineer_knowledge (record_type);
create index if not exists it_engineer_knowledge_epi_idx    on public.it_engineer_knowledge (epistemic_status);
create index if not exists it_engineer_knowledge_emb_hnsw
  on public.it_engineer_knowledge using hnsw (embedding_gte vector_cosine_ops);

comment on table public.it_engineer_knowledge is
  'QuotesDone IT Engineer Knowledge v1 (QD-IT-ENGINEER). Authored diagnostic method, the diagnostic lenses this codebase has paid for, the measured architecture of THIS estate, the failure signatures the founder named, and security operations grounded here. It states NO CVE identifier, NO version-specific vulnerability claim, NO patch level and NO CVSS score: this session cannot read a vulnerability feed, so any such statement would be invented. Six banned shapes are scanned by the loader, which refuses the whole run on a hit. It EXTENDS public.ops_knowledge layer it_security_deep (165 rows) and supersedes none of it. authority_effect is CHECK-pinned to none.';

comment on column public.it_engineer_knowledge.epistemic_status is
  'How far the record may be trusted, CHECK-constrained to eight values. security_posture_no_version_claim means the record names no CVE, version or patch level; resolve_from_live_system means the record exists to say the answer is NOT held here and to name the query or log that holds it; estate_architecture_measured means the fact was measured and the record names the measurement; company_record_generated means the loader wrote it from a live table and it is never hand-typed.';

comment on column public.it_engineer_knowledge.body_sha256 is
  'sha256 over title || E''\n'' || content. The dedupe key and the change detector: a re-run compares it to decide inserted / updated / unchanged, and clears the embedding of anything whose body moved.';

-- The search vector, maintained on write. A trigger rather than a generated column because Postgres
-- will not accept a stored generated column whose expression it cannot prove immutable.
create or replace function public.fn_it_engineer_knowledge_search_vector()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  new.search :=
      setweight(to_tsvector('english'::regconfig, coalesce(new.title,'')), 'A')
   || setweight(to_tsvector('english'::regconfig, coalesce(array_to_string(new.tags,' '),'')), 'B')
   || setweight(to_tsvector('english'::regconfig, coalesce(new.content,'')), 'C');
  return new;
end $function$;

drop trigger if exists a10_it_engineer_knowledge_search_vector on public.it_engineer_knowledge;
create trigger a10_it_engineer_knowledge_search_vector
  before insert or update of title, tags, content on public.it_engineer_knowledge
  for each row execute function public.fn_it_engineer_knowledge_search_vector();

-- ---------------------------------------------------------------------------------------------
-- 2. RETRIEVAL, WITH A FLOOR AND LEXICAL CORROBORATION
-- ---------------------------------------------------------------------------------------------
-- AN UNFILTERED VECTOR SEARCH ALWAYS RETURNS A NEAREST NEIGHBOUR. "A nearest neighbour is always
-- found" is a lens this estate keeps paying for, and it is worse here than almost anywhere else:
-- ask an unfiltered index "is this uploaded file malware" and you get the most malware-shaped
-- passage in a 9,000-row corpus, returned with the same confidence whether or not it is about the
-- file in front of you. An operator acting on that during an incident acts on a coincidence.
--
-- So the two-part admission proven on fn_sales_assist and fn_accountant_assist is applied here
-- unchanged in shape, and deliberately unchanged in its constants, because those constants were
-- measured on real corpora rather than chosen:
--
--   * A row WITH an embedding must clear the cosine floor AND corroborate literally. Semantic
--     proximity alone does not admit, ever.
--   * Corroboration has two routes, OR-ed with each other and AND-ed with the floor. The all-terms
--     route (ts_rank against websearch_to_tsquery) and literal lexeme overlap. The second route
--     exists because the first was measured on the accountant's corpus and found to return EXACTLY
--     ts_rank 0.0000 on 9 of 35 realistic questions whose correct record sat at cosine 0.887-0.933:
--     websearch_to_tsquery ANDs every term, so one filler adverb defeats it. That is a phrasing
--     lottery, not a corroboration bar.
--   * The overlap threshold is 0.60, and that number is inherited rather than re-chosen. An
--     overlap route at 0.40 was built, applied, measured and REVERTED on the sales corpus: it
--     admitted a joinery fire-door passage to a supplier-coverage question on 2 lexemes out of 5.
--     2/5 is 0.40 and does not clear 0.60. The requirement is the greater of 60% and two lexemes,
--     so a short question cannot slip through on one common word.
--   * A row WITHOUT an embedding cannot be put to the vector floor at all, so it must clear a
--     stricter lexical-only bar, floored at 0.20 but never below p_min_rank -- tied so that a probe
--     which raises p_min_rank to prove the floor bites closes this route too. A gate nobody can
--     prove fires is not a gate.
--
-- THE COSINE FLOOR IS 0.83 HERE AND NOT 0.86, AND THAT IS THE ONE CONSTANT DELIBERATELY CHANGED
-- FROM THE ACCOUNTANT'S. It was measured on THIS corpus on 9 Sep 2026 rather than inherited,
-- because a threshold fitted to one corpus's embedding geometry is not a safety property of
-- another. The sweep asked, at floor 0.50 so every candidate was visible, two questions: for
-- twelve in-scope questions, what similarity does the CORRECT record sit at and does it
-- corroborate; and for out-of-scope questions, what is the highest similarity reached by any
-- candidate that corroborates at all.
--
--   floor   in-scope admitted   out-of-scope admitted
--   0.83    11/12              0/6
--   0.84    10/12              0/6
--   0.85     7/12              0/6
--   0.86     5/12              0/6
--
-- THE FINDING IS THE SECOND COLUMN. Not one out-of-scope query produced a single corroborated
-- candidate anywhere in the top forty, at any floor, including at 0.50. On this corpus the
-- CORROBORATION gate does one hundred per cent of the out-of-scope rejection and the cosine floor
-- contributes nothing to safety -- it only removes correct answers. Holding it at 0.86 would have
-- refused six of twelve questions this seat exists to answer, and refused them during incidents,
-- while making the system no safer by any measurement available.
--
-- 0.83 rather than lower, because the floor is not useless in principle: it is the only thing
-- standing behind corroboration if a future record ever shares enough vocabulary with an unrelated
-- question, and the nearest out-of-scope similarity measured was 0.8368 with too few lexeme hits.
-- Verified end to end at 0.83 against eight out-of-scope questions -- nonsense, another country's
-- tax filing, a vehicle repair, a visa question, a recipe, a geography question -- and all eight
-- were refused. The twelfth in-scope question is refused for CORROBORATION rather than similarity
-- and is a genuine corpus gap; it is reported by the eval rather than papered over by moving a
-- number until it passes.
--
-- WHY BOTH CORPORA. The seat's own body holds the diagnostic half; ops_knowledge layer
-- it_security_deep holds the security half, and the rest of ops_knowledge holds how the company
-- actually operates. An incident question frequently turns on a company rule rather than on
-- engineering -- what may be told to a supplier, who may approve a refund -- and a seat that
-- cannot see those answers half a question. Superseded ops_knowledge rows are excluded: never
-- quote a rule that has been replaced.
--
-- THIS FUNCTION WRITES NOTHING. Deliberately. fn_sales_assist records a gap and opens a task on a
-- refusal, which is right for a customer waiting on a portal. It is wrong here, because it would
-- make every probe of the floor a production write, and this estate has already been bitten by
-- rehearsals that paged the founder. The refusal is returned to the caller, which owns what to do
-- with it -- and during an incident the caller is the thing that should decide, not the index.
-- ponytail: no gap table and no task on refusal. Add one when there is a live caller whose
-- unanswered questions need counting across sessions; the eval script measures coverage today.
create or replace function public.fn_it_engineer_assist(
  p_text            text,
  p_embedding       vector default null,
  p_min_similarity  numeric default 0.83,   -- measured on THIS corpus; see the sweep above
  p_min_rank        numeric default 0.05,
  p_k               integer default 5,
  p_min_overlap     numeric default 0.60)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_k         int := greatest(1, least(coalesce(p_k, 5), 20));
  v_wide      int := greatest(v_k * 4, 20);
  c_lex_only  numeric := greatest(0.20, coalesce(p_min_rank, 0));
  v_tq        tsquery;
  v_lex       text[];
  v_nlex      int;
  v_need      int;
  v_cands     jsonb  := '[]'::jsonb;
  v_cited     text[] := '{}';
  v_answer    jsonb  := '[]'::jsonb;
  v_refusal   text;
  v_best_sim  numeric;
  v_best_rank numeric;
  v_best_lex  int;
  v_best_corp text;
  v_handoff   text;
begin
  if coalesce(btrim(p_text), '') = '' then
    return jsonb_build_object('ok', false, 'answered', false, 'refusal', 'empty_query');
  end if;

  v_tq := websearch_to_tsquery('english', p_text);
  select array_agg(distinct u.lexeme) into v_lex from unnest(to_tsvector('english', p_text)) u;
  v_nlex := coalesce(cardinality(v_lex), 0);
  -- The greater of 60% and two lexemes, so a short question cannot be admitted on one common word.
  v_need := case when v_nlex = 0 then 2147483647
                 else greatest(least(2, v_nlex), ceil(coalesce(p_min_overlap, 0.60) * v_nlex)::int) end;

  create temporary table if not exists _ite_cand (
    corpus text, record_id text, title text, content text, provenance text,
    similarity numeric, lexical_rank numeric, has_vector boolean, lex_hits int default 0
  ) on commit drop;
  -- truncate, not delete: the estate refuses an unqualified DELETE, and a WHERE-less delete on a
  -- scratch table is exactly the shape that guard exists to catch elsewhere.
  truncate table _ite_cand;

  -- it_engineer_knowledge -- the seat's own body.
  if p_embedding is not null then
    insert into _ite_cand
    select 'it_engineer_knowledge', k.record_id, k.title, left(k.content, 4000),
           coalesce(k.record_type, '') || case when k.domain is null then '' else ' · ' || k.domain end
             || ' · ' || k.epistemic_status,
           (1 - (k.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(k.search, v_tq), 0)::numeric * (case when k.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(k.search) u where u.lexeme = any (v_lex))
      from it_engineer_knowledge k
     where k.embedding_gte is not null and k.runtime_index_eligible
     order by k.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _ite_cand
  select 'it_engineer_knowledge', k.record_id, k.title, left(k.content, 4000),
         coalesce(k.record_type, '') || ' · ' || k.epistemic_status,
         null::numeric, ts_rank(k.search, v_tq)::numeric, false, 0
    from it_engineer_knowledge k
   where k.embedding_gte is null and k.runtime_index_eligible and k.search @@ v_tq
   order by ts_rank(k.search, v_tq) desc
   limit v_wide;

  -- ops_knowledge -- the 165 it_security_deep rows plus how this company actually operates.
  if p_embedding is not null then
    insert into _ite_cand
    select 'ops_knowledge', o.record_id, o.title, left(o.content, 4000),
           coalesce(o.layer, '') || case when o.module is null then '' else ' · ' || o.module end
             || case when o.authority_tier is null then '' else ' · authority ' || o.authority_tier end,
           (1 - (o.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(o.tsv, v_tq), 0)::numeric * (case when o.tsv @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(o.tsv) u where u.lexeme = any (v_lex))
      from ops_knowledge o
     where o.embedding_gte is not null
       and coalesce(o.supersession_state, 'current') = 'current'
     order by o.embedding_gte <=> p_embedding
     limit v_wide;
  end if;

  -- ADMISSION. The cosine floor is a hard AND for every vector-bearing row; corroboration may come
  -- from either the all-terms rank or literal lexeme overlap, and one of the two is required.
  with judged as (
    select c.*,
           (c.has_vector and c.similarity >= p_min_similarity
             and (c.lexical_rank >= p_min_rank or c.lex_hits >= v_need))     as ok_vector,
           ((not c.has_vector) and c.lexical_rank >= c_lex_only)             as ok_lexical
      from _ite_cand c
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
      'lex_hits', r.lex_hits, 'lex_needed', v_need,
      'corroborated', case when r.has_vector then (r.lexical_rank >= p_min_rank or r.lex_hits >= v_need)
                           else r.lexical_rank >= c_lex_only end,
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

  select max(similarity), max(lexical_rank), max(lex_hits)
    into v_best_sim, v_best_rank, v_best_lex from _ite_cand;
  select corpus into v_best_corp from _ite_cand
   order by similarity desc nulls last, lexical_rank desc limit 1;

  if cardinality(v_cited) = 0 then
    v_refusal := case
      when (select count(*) from _ite_cand) = 0 then 'no_candidates'
      when coalesce(v_best_sim, 0) < p_min_similarity and coalesce(v_best_rank, 0) < c_lex_only
        then 'below_similarity_floor_and_lexical_bar'
      when coalesce(v_best_sim, 0) < p_min_similarity then 'below_similarity_floor'
      else 'not_corroborated_lexically' end;
    v_handoff :=
      'I do not have a sourced answer to that, and I will not guess during an incident. '
      || 'If the question is whether a specific published vulnerability reaches this estate, that '
      || 'is deliberately not held in my knowledge: I hold no CVE identifier, no version-specific '
      || 'vulnerability claim and no patch level, because I cannot read a vulnerability feed and an '
      || 'invented one is worse than none. Determine it against the component''s own advisory and '
      || 'the version the platform actually reports. If the question is about live state, read the '
      || 'live state: the answer is in the database, the edge logs or the deploy history, not here.';
  end if;

  return jsonb_build_object(
    'ok', true,
    'answered', cardinality(v_cited) > 0,
    'records', v_answer,
    'cited', v_cited,
    'candidates', v_cands,
    'corpora', jsonb_build_array('it_engineer_knowledge', 'ops_knowledge'),
    'floor', jsonb_build_object(
      'min_similarity', p_min_similarity, 'min_rank', p_min_rank, 'lexical_only', c_lex_only,
      'min_overlap', p_min_overlap, 'lexemes_in_question', v_nlex, 'lexeme_overlap_needed', v_need,
      'best_similarity', round(v_best_sim, 4), 'best_lexical_rank', round(v_best_rank, 4),
      'best_lex_hits', v_best_lex, 'nearest_corpus', v_best_corp, 'k', v_k,
      'rule', 'a row with an embedding must clear the cosine floor -- always -- AND corroborate literally by one of two routes: the all-terms lexical query at ts_rank >= min_rank, or at least lexeme_overlap_needed of the question''s own lexemes present verbatim in the row. A row with no embedding cannot be put to the vector floor at all and must clear the stricter lexical-only bar instead. A nearest neighbour is always found; a literal match is not.'),
    'refusal', v_refusal,
    'handoff', v_handoff);
end
$function$;

-- A freshly created SECURITY DEFINER routine is executable by PUBLIC until it is not.
revoke execute on function public.fn_it_engineer_assist(text, vector, numeric, numeric, integer, numeric) from public;
revoke execute on function public.fn_it_engineer_assist(text, vector, numeric, numeric, integer, numeric) from anon, authenticated;

comment on function public.fn_it_engineer_assist(text, vector, numeric, numeric, integer, numeric) is
  'IT engineer retrieval over it_engineer_knowledge and ops_knowledge (including the 165 it_security_deep rows). A vector-bearing row must clear the cosine floor -- always -- AND corroborate literally, either by the all-terms lexical query or by carrying at least p_min_overlap of the question''s own lexemes verbatim; a row with no vector must clear a stricter lexical-only bar. Returns answered:false with a refusal reason rather than the nearest neighbour, because during an incident a confident wrong answer is acted on. Writes nothing, so probing the floor has no production side effect.';

-- ---------------------------------------------------------------------------------------------
-- 3. GRANTS -- THIS IS INTERNAL KNOWLEDGE, AND MORE SENSITIVE THAN MOST
-- ---------------------------------------------------------------------------------------------
-- This body describes where the secrets live, which functions do not require a JWT, which guards
-- swallow their own failures and how to reach the scheduler. That is a map of the estate's soft
-- spots. A browser holding an anon key must not read it, and a signed-in customer or supplier must
-- not either.
revoke all on public.it_engineer_knowledge from anon, authenticated;
alter table public.it_engineer_knowledge enable row level security;
-- No policies: RLS with no policy denies every non-superuser, non-owner role. service_role bypasses
-- RLS, which is exactly the reach the loader and the edge function need and no more. The RLS is
-- here AS WELL AS the revoke because a later blanket `grant ... on all tables in schema public` --
-- the kind a migration writes without reading this file -- would undo the revoke and not the RLS.
--
-- fn_it_engineer_knowledge_search_vector is not revoked: it is `create or replace`, which preserves
-- any existing ACL, and it is a SECURITY INVOKER trigger function carrying no privilege of its own.

-- ---------------------------------------------------------------------------------------------
-- 4. THE MODEL PAIR, PINNED BY IDENTITY
-- ---------------------------------------------------------------------------------------------
-- THE PRICE LADDER, READ OUT OF public.model_rate ON 9 SEP 2026 RATHER THAN RECALLED. USD per
-- million tokens, prompt / output, for the nine approved and active models:
--
--   openai/gpt-5.6-luna            small    0.20 /  1.20
--   google/gemini-3.1-flash-lite   small    0.25 /  1.50
--   qwen/qwen3.7-plus              small    0.32 /  1.28
--   ~anthropic/claude-haiku-latest medium   1.00 /  5.00   (cheapest cache-capable model)
--   google/gemini-3.5-flash        medium   1.50 /  9.00
--   anthropic/claude-sonnet-5      large    2.00 / 10.00
--   anthropic/claude-opus-4.8      xlarge   5.00 / 25.00
--   anthropic/claude-fable-5.1     xlarge  10.00 / 50.00
--   openai/gpt-6-astra             xlarge  10.00 / 50.00
--
-- WHAT THIS SEAT'S WORK ACTUALLY IS, because the tier follows from that and not from the word
-- "capable". Detection is deterministic and free: a threshold crossed, a queue depth, a 5xx rate,
-- a file that is not what its extension says. The model is called at the SECOND step -- when a
-- detection has fired and something must decide what it means and what to do -- over a large,
-- messy, low-signal context of logs, schema and function bodies. That is a long-context precision
-- task under time pressure, not a strategy task, and getting the root cause wrong costs far more
-- than the token difference between two tiers.
--
--   PRIMARY  anthropic/claude-sonnet-5   large, 2.00 / 10.00, 200k context.
--     The cheapest model in the estate that is genuinely a reasoning model. Against the tier below
--     it: haiku at 1.00 / 5.00 is half the price, and half the price of a wrong root cause during
--     an outage is not a saving. Against the tier above it: opus-4.8 is 2.5x on output and
--     fable-5.1 and gpt-6-astra are 5x. Those three are where the CEO and the sales engineer sit,
--     and correctly so -- their work is judgement, produced occasionally, where a better answer is
--     worth 5x. This seat fires on every detection, all day, so a 5x output price is a standing
--     bill for a capability the task does not turn on. Sonnet-5's registry note says it is the
--     "current default for everything" and "should become the exception, not the rule"; this is one
--     of the places it should remain the rule, and the reason is written down rather than assumed.
--
--   FALLBACK ~anthropic/claude-haiku-latest   medium, 1.00 / 5.00, 200k context.
--     Chosen over the three cheaper small-tier models for two measured reasons. It is the only
--     cache-capable model in the registry and its own note records that cache reads are a tenth of
--     prompt price -- and this seat's prompt is a large STABLE prefix (the estate's architecture)
--     followed by a small volatile suffix (today's alert), which is precisely the shape caching
--     pays for. And it shares a family with the primary, so a failover does not also change how
--     tools and refusals are expressed mid-incident. A fallback that behaves differently from the
--     primary is a second incident inside the first.
--
--   ESCALATION anthropic/claude-opus-4.8   xlarge, 5.00 / 25.00, quality_score 1.0000.
--     Not the daily driver. For the incident the primary could not resolve -- reserved, so its
--     price is paid per incident rather than per detection. gpt-6-astra and fable-5.1 at 10 / 50
--     were rejected here for the same reason: at escalation volume the extra 2x buys nothing this
--     seat's questions turn on, and opus-4.8's registry note already scopes it to hard analysis.
--
-- WHAT IT DISPLACES, AND THIS IS THE REAL FINDING. There is an existing identity row, key 'it',
-- scope current_agent, pointing at primary deepseek/deepseek-v4-flash, fallback qwen/qwen3.7-flash,
-- escalation anthropic/claude-opus-5. Measured 9 Sep 2026: NONE of those three model ids exists in
-- public.model_registry and none has a row in public.model_rate. So the IT seat's registered
-- routing today names three models that are not approved, not active, and carry no price the
-- estate can bill against. That is not a cheaper choice than sonnet-5, it is an unpriced one --
-- exactly the "unclassified call lands somewhere unintended" failure the accountant's identity pin
-- was created to stop, in its worst form. The 'it' row is left in place and untouched, because
-- another agent owns the seat's runtime and may be reading it; the new 'it_engineer' row is
-- authoritative for the seat being built and every model it names is approved, active and priced.
--
-- THE OPENROUTER HOLD IS IN FORCE AND IS NOT TOUCHED HERE. fn_kernel_paid_provider_gate refuses
-- every paid route. Registering a pair is a routing declaration, not a call: it is what makes the
-- routing correct on the day the hold lifts, and it costs nothing today. No paid call is attempted
-- by this file or by anything it installs. Embedding for this knowledge body runs through
-- Supabase.ai gte-small in-region, which is free and short-circuits before the paid gate.
insert into public.model_policy_by_identity (
  identity_key, scope, department, title, deterministic_first,
  primary_model, fallback_model, escalation_model,
  max_output_tokens, reasoning_effort, manager, authority_tier, note, package_version, imported_at)
values (
  'it_engineer', 'current_agent', null, 'IT engineer (monitoring, diagnosis, security operations)', 'Yes',
  'anthropic/claude-sonnet-5', '~anthropic/claude-haiku-latest', 'anthropic/claude-opus-4.8',
  2200, 'high', null, null,
  'Founder''s build order 9 Sep 2026: keep this seat "really capable" of monitoring the app and the website, catching a registration bug or a lagging comparison report, and watching for attacks and malware. Tier chosen against the measured price ladder in public.model_rate, not by name. Primary sonnet-5 (large, 2.00/10.00 USD per Mtok, 200k ctx) is the cheapest real reasoning model in the registry; the xlarge tier the CEO and sales engineer use costs 5x on output and this seat fires on every detection rather than occasionally. Fallback haiku-latest is the only cache-capable model in the registry and this seat''s prompt is a large stable prefix plus a small volatile alert, which is the shape caching pays for; it also shares a family with the primary, so a failover does not change tool and refusal behaviour mid-incident. Escalation opus-4.8 (quality_score 1.0000) is reserved for the incident the primary could not resolve, so its price is per incident not per detection. DISPLACES the unpriced routing on identity_key ''it'', whose primary deepseek/deepseek-v4-flash, fallback qwen/qwen3.7-flash and escalation anthropic/claude-opus-5 have NO row in model_registry and NO row in model_rate (measured 9 Sep 2026). deterministic_first stays Yes: detection, thresholds and the free in-region gte-small embedding run without a model at all, and must stay there. The OpenRouter hold is in force; this is a routing declaration, not a call.',
  '1.0.0', now())
-- The primary key is (identity_key, scope), not identity_key alone, so the conflict target names
-- both. Getting this wrong is not a warning: Postgres refuses the statement outright.
on conflict (identity_key, scope) do update set
  title = excluded.title, deterministic_first = excluded.deterministic_first,
  primary_model = excluded.primary_model, fallback_model = excluded.fallback_model,
  escalation_model = excluded.escalation_model, max_output_tokens = excluded.max_output_tokens,
  reasoning_effort = excluded.reasoning_effort, note = excluded.note,
  package_version = excluded.package_version, imported_at = excluded.imported_at;

-- EVERY MODEL THE NEW ROW NAMES MUST BE APPROVED, ACTIVE AND PRICED. Asserted here rather than
-- believed, and it fails the apply rather than printing a warning nobody reads. This is the whole
-- point of the row: an identity pin that names an unregistered model is worse than no pin, because
-- it looks like a decision.
do $$
declare v_bad text;
begin
  select string_agg(m, ', ') into v_bad
    from (select unnest(array['anthropic/claude-sonnet-5', '~anthropic/claude-haiku-latest',
                              'anthropic/claude-opus-4.8']) as m) t
   where not exists (select 1 from public.model_registry r
                      where r.model_id = t.m and r.approved and r.active)
      or not exists (select 1 from public.model_rate  x where x.model = t.m);
  if v_bad is not null then
    raise exception 'it_engineer identity names model(s) that are not approved+active in model_registry or not priced in model_rate: %', v_bad;
  end if;
end $$;
