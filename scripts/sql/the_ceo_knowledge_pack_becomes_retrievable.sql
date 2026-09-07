-- THE CEO KNOWLEDGE PACK BECOMES RETRIEVABLE
--
-- The founder supplied CEO_Knowledge_Pack_v1 (400 records, 225 files, validated by the pack's own
-- tool: fingerprint 73a55921dcf311996552d55d05ed9fe42dc4fc615689091983a2646f362e9471) with an
-- explicit instruction: deliver populated content and WORKING RETRIEVAL, not empty folders, a list
-- of topics, or a claim that the model already knows this.
--
-- THIS IS A SEPARATE STORE ON PURPOSE. The pack's own retrieval contract is blunt about it: the
-- application supplies authenticated company policy, targets, metrics and permissions; the retriever
-- supplies reusable advisory guidance; and the two are NOT interchangeable. Mixing 264 generic
-- guidance sections into ops_knowledge -- which holds this company's own operating facts -- would let
-- a piece of general advice be read back later as something QuotesDone had established. So it lives
-- here, labelled, and every reader can tell which kind of thing it is holding.
--
-- WHAT THE PACK FORBIDS, honoured here:
--   * review_status must survive import. It is NOT normalised to 'approved'; the column is text and
--     every row carries 'authored_not_independently_reviewed' exactly as authored.
--   * authority_effect is 'none' on every record and is stored, not dropped. Nothing retrieved from
--     here may approve an action, change a target or promote itself into policy.
--   * a decision card's logic is EXPLANATORY TEXT. It is stored as text and there is no evaluator,
--     no DSL and no path by which it can execute.
--   * the Markdown under knowledge/ is a human-readable duplicate of the JSONL and is NOT imported.
--     Indexing both would double every hit and inflate every relevance score.
--   * evaluation/ is NOT imported. Feeding the evaluation answers into the knowledge search and then
--     reporting a good score would be marking my own homework.

create table if not exists public.ceo_knowledge (
  record_id            text primary key,
  schema_version       text not null,
  record_version       text not null,
  record_kind          text not null,
  parent_id            text,
  title                text not null,
  domain               text not null,
  tags                 text[] not null default '{}',
  language             text not null default 'en',
  company_scope        text not null,
  audience             text[] not null default '{}',
  created_on           date,
  review_status        text not null,
  content_origin       text not null,
  authority_effect     text not null,
  runtime_use          text not null,
  runtime_index_eligible boolean not null,
  external_execution_enabled boolean not null,
  contains_synthetic_example boolean not null,
  requires_current_verification boolean not null,
  verification_note    text,
  source_ids           text[] not null default '{}',
  source_support       text,
  related_modules      text[] not null default '{}',
  source_path          text,
  body                 text not null,
  body_sha256          text,
  extra                jsonb not null default '{}'::jsonb,
  pack_fingerprint     text not null,
  imported_at          timestamptz not null default now(),
  -- A PLAIN COLUMN WITH A TRIGGER, not a generated column. Postgres refuses a stored generated
  -- column whose expression it cannot prove immutable, and this one composes several functions over
  -- an array; the trigger below does the identical work at write time with no such restriction, and
  -- it keeps the vector correct on UPDATE as well as INSERT.
  search               tsvector,
  -- The pack's four kinds of content, kept apart because the founder asked for exactly that
  -- separation: general business knowledge, industry knowledge, verified company facts, and lessons
  -- from real company decisions. Everything in THIS pack is one of the first two. Nothing in it is a
  -- verified company fact and nothing in it is a lesson from a real QuotesDone decision -- the pack
  -- says so itself, and the constraint makes it impossible to import one as if it were.
  constraint ceo_knowledge_scope_ck  check (company_scope in ('generic','industry')),
  constraint ceo_knowledge_authority_ck check (authority_effect = 'none'),
  constraint ceo_knowledge_exec_ck   check (external_execution_enabled = false)
);


-- The search vector, maintained on write. Title weighted above tags, tags above body, so a query
-- that names a module by its title outranks one that merely mentions the words somewhere in a body.
create or replace function public.fn_ceo_knowledge_search_vector()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  new.search :=
      setweight(to_tsvector('english'::regconfig, coalesce(new.title,'')), 'A')
   || setweight(to_tsvector('english'::regconfig, coalesce(array_to_string(new.tags,' '),'')), 'B')
   || setweight(to_tsvector('english'::regconfig, coalesce(new.body,'')), 'C');
  return new;
end $function$;

drop trigger if exists a10_ceo_knowledge_search_vector on public.ceo_knowledge;
create trigger a10_ceo_knowledge_search_vector
  before insert or update of title, tags, body on public.ceo_knowledge
  for each row execute function public.fn_ceo_knowledge_search_vector();

create index if not exists ceo_knowledge_search_idx on public.ceo_knowledge using gin (search);
create index if not exists ceo_knowledge_kind_idx   on public.ceo_knowledge (record_kind, domain);

comment on table public.ceo_knowledge is
  'CEO_Knowledge_Pack_v1: 400 advisory records. GENERIC AND INDUSTRY GUIDANCE ONLY -- never this company''s own facts, and never a lesson from a real QuotesDone decision. Three CHECK constraints enforce that: company_scope may not be a company fact, authority_effect must be none, and external execution must be false. Nothing retrieved from this table may approve an action, change a target or promote itself into policy.';

comment on column public.ceo_knowledge.review_status is
  'Carried verbatim from the pack. Every row reads authored_not_independently_reviewed. It is NOT normalised to approved: the pack warns explicitly against solving a filter mismatch by promoting the corpus.';

comment on column public.ceo_knowledge.contains_synthetic_example is
  'True where the record contains a worked example that was authored, not observed. Every worked case in this pack is synthetic and labelled as such -- none of it is QuotesDone experience.';

-- ---------------------------------------------------------------------------------------------
-- RETRIEVAL
-- ---------------------------------------------------------------------------------------------
-- Lexical ranking, which is what the pack itself ships and what it recommends until a measured
-- benefit justifies the cost of embeddings. Every field the retrieval contract lists as a minimum is
-- returned, and the score is returned as `relevance` rather than anything resembling a probability
-- that the content is true.
create or replace function public.fn_ceo_knowledge_search(
  p_query text,
  p_limit int default 8,
  p_kind  text default null,
  p_domain text default null)
returns table(
  record_id text, record_version text, record_kind text, title text, domain text,
  body text, body_sha256 text, source_ids text[], source_path text,
  review_status text, authority_effect text, contains_synthetic_example boolean,
  requires_current_verification boolean, relevance real, warning text)
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_q tsquery;
begin
  if coalesce(btrim(p_query),'') = '' then
    return;  -- an empty query retrieves nothing rather than everything
  end if;
  -- websearch_to_tsquery tolerates ordinary phrasing without throwing on punctuation, which a raw
  -- to_tsquery does not.
  v_q := websearch_to_tsquery('english', p_query);
  if v_q is null then return; end if;

  return query
  select k.record_id, k.record_version, k.record_kind, k.title, k.domain,
         k.body, k.body_sha256, k.source_ids, k.source_path,
         k.review_status, k.authority_effect, k.contains_synthetic_example,
         k.requires_current_verification,
         ts_rank(k.search, v_q) as relevance,
         -- The warning travels WITH the row, because a caller who forgets it is the failure mode
         -- this whole store is shaped against.
         'Advisory only. authority_effect=none: this may not approve an action, change a target or '
         || 'become policy. review_status=' || k.review_status || '. '
         || case when k.contains_synthetic_example
                 then 'CONTAINS A SYNTHETIC EXAMPLE -- it is authored, not QuotesDone experience. ' else '' end
         || case when k.requires_current_verification
                 then 'REQUIRES CURRENT VERIFICATION against an authoritative company source. ' else '' end
         || 'Current company facts come from the application, never from this record.' as warning
    from public.ceo_knowledge k
   where k.runtime_index_eligible
     and k.search @@ v_q
     and (p_kind is null or k.record_kind = p_kind)
     and (p_domain is null or k.domain = p_domain)
   order by ts_rank(k.search, v_q) desc, k.record_id
   limit greatest(1, least(coalesce(p_limit, 8), 50));
end $function$;

comment on function public.fn_ceo_knowledge_search(text,int,text,text) is
  'Lexical retrieval over the CEO knowledge pack. Returns every field the pack''s retrieval contract lists as a minimum, and a per-row warning stating that the content is advisory, carries no authority, and is not this company''s facts. relevance is a ranking score and NEVER a probability that the content is true.';

-- CONTEXT ASSEMBLY, bounded by characters, exactly as the pack's own loader is. It returns an
-- explicit insufficient-context signal rather than an empty string, because "no answer" and "no
-- coverage" are different things and a caller must be able to tell them apart.
create or replace function public.fn_ceo_context(
  p_query text,
  p_max_chars int default 18000,
  p_limit int default 8)
returns jsonb
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record;
  v_out jsonb := '[]'::jsonb;
  v_used int := 0;
  v_n int := 0;
begin
  for r in select * from public.fn_ceo_knowledge_search(p_query, p_limit) loop
    exit when v_used + length(r.body) > greatest(2000, p_max_chars);
    v_out := v_out || jsonb_build_object(
      'record_id', r.record_id, 'record_kind', r.record_kind, 'title', r.title,
      'domain', r.domain, 'body', r.body, 'body_sha256', r.body_sha256,
      'source_ids', to_jsonb(r.source_ids), 'source_path', r.source_path,
      'review_status', r.review_status, 'authority_effect', r.authority_effect,
      'relevance', r.relevance, 'warning', r.warning);
    v_used := v_used + length(r.body);
    v_n := v_n + 1;
  end loop;

  return jsonb_build_object(
    'query', p_query,
    'records', v_out,
    'record_count', v_n,
    'chars_used', v_used,
    'sufficient', v_n > 0,
    'signal', case when v_n = 0
                   then 'INSUFFICIENT CONTEXT -- nothing in the CEO knowledge pack matched this query. Say so rather than answering from memory.'
                   else 'Advisory context only. Company facts, targets, budgets and permissions must be read from the application, not from these records.' end,
    'pack_fingerprint', (select max(pack_fingerprint) from public.ceo_knowledge));
end $function$;

comment on function public.fn_ceo_context(text,int,int) is
  'Assembles a character-bounded advisory context for the CEO. Returns sufficient=false with an explicit INSUFFICIENT CONTEXT signal when nothing matches, so that "the pack has no coverage" can never be mistaken for "the pack agrees".';
