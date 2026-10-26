-- THE SUPPORT KNOWLEDGE PACK BECOMES RETRIEVABLE
--
-- Build spec §13. QuotesDone_Customer_Support_Knowledge_v1_1: 316 runtime records validated by the
-- pack's own tool -- 200 guide sections, 40 decision playbooks, 32 worked cases, 24 message
-- templates, 20 metric definitions.
--
-- ITS OWN NAMESPACE, as the package requires: "It is compatible in style with the CEO pack, but
-- belongs in its own namespace." So supportkb.* records live here and not in ceo_knowledge. The two
-- packs answer different questions and a support playbook surfacing in a CEO retrieval would be a
-- category error, not a lucky hit.
--
-- WHAT THE PACK FORBIDS, honoured rather than noted:
--   * the five files in MANIFEST.json -> runtime_files are the ONLY corpus. The Markdown mirrors are
--     for people; importing both duplicates every record and inflates every relevance score.
--   * evaluation/, tests/ and qa/ NEVER enter runtime retrieval. The pack is explicit that feeding
--     evaluation answers into the knowledge search and then reporting a good score is not evidence.
--   * version 1.1.0 REPLACES 1.0.0 on the same stable supportkb.* IDs. Never two parallel corpora.
--   * records are staged as authored professional guidance WITHOUT authority. review_status survives
--     import; nothing is promoted to "independently reviewed".
--   * message templates here are DRAFTS, not approved provider templates. The column says so, and
--     the sending path must read wa_template_registry for what Twilio has actually approved.

create table if not exists public.support_knowledge (
  record_id            text primary key,
  schema_version       text,
  record_version       text not null,
  record_kind          text not null,
  parent_id            text,
  title                text not null,
  domain               text,
  tags                 text[] not null default '{}',
  language             text not null default 'en',
  review_status        text not null,
  content_origin       text,
  authority_effect     text not null default 'none',
  runtime_use          text,
  runtime_index_eligible boolean not null default true,
  contains_synthetic_example boolean not null default false,
  requires_current_verification boolean not null default false,
  source_ids           text[] not null default '{}',
  source_path          text,
  structured_data      jsonb not null default '{}'::jsonb,
  body                 text not null,
  body_sha256          text,
  pack_id              text not null,
  pack_version         text not null,
  imported_at          timestamptz not null default now(),
  search               tsvector,

  -- The same three refusals the CEO store carries, for the same reasons. A support playbook may
  -- advise; it may never approve a refund, grant an entitlement or become policy.
  constraint support_knowledge_authority_ck check (authority_effect = 'none'),
  -- ONE CORPUS, NOT TWO. The pack replaces 1.0.0 on the same IDs; a row at the old version would
  -- mean two answers to the same question with no way to tell which is current.
  constraint support_knowledge_version_ck   check (pack_version = '1.1.0')
);

create index if not exists support_knowledge_search_idx on public.support_knowledge using gin (search);
create index if not exists support_knowledge_kind_idx   on public.support_knowledge (record_kind);

comment on table public.support_knowledge is
  'QuotesDone_Customer_Support_Knowledge_v1_1: 316 advisory records in their own supportkb.* namespace, separate from ceo_knowledge. Authored professional guidance with NO authority: nothing retrieved here may approve a refund, grant an entitlement, change a price or become policy. Message templates are DRAFTS -- what Twilio approved lives in wa_template_registry.';

comment on column public.support_knowledge.pack_version is
  'Pinned to 1.1.0 by CHECK. Version 1.1.0 replaces 1.0.0 on the same stable record IDs, and the pack forbids serving both: two answers to one question with no way to tell which is current.';

-- The search vector, maintained on write. Same shape as the CEO store: title above tags above body,
-- and a trigger rather than a generated column because Postgres will not accept a stored generated
-- column whose expression it cannot prove immutable.
create or replace function public.fn_support_knowledge_search_vector()
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

drop trigger if exists a10_support_knowledge_search_vector on public.support_knowledge;
create trigger a10_support_knowledge_search_vector
  before insert or update of title, tags, body on public.support_knowledge
  for each row execute function public.fn_support_knowledge_search_vector();

-- ---------------------------------------------------------------------------------------------
-- RETRIEVAL
-- ---------------------------------------------------------------------------------------------
-- Built with the lesson the CEO pack taught by measurement: websearch_to_tsquery ANDs every term,
-- which is right for three deliberate words and impossible for a forty-word situation. The CEO
-- retrieval scored 0 of 32 that way -- not wrong answers, but NO answers. Strict first, best-terms
-- only when strict finds nothing, and matched_how says which.
create or replace function public.fn_support_knowledge_search(
  p_query text,
  p_limit int default 6,
  p_kind  text default null)
returns table(
  record_id text, record_kind text, title text, body text, body_sha256 text,
  source_ids text[], source_path text, review_status text, authority_effect text,
  contains_synthetic_example boolean, structured_data jsonb,
  relevance real, matched_how text, warning text)
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_q tsquery; v_lex text[]; v_found boolean := false; v_how text := 'all_terms';
begin
  if coalesce(btrim(p_query), '') = '' then return; end if;

  v_q := websearch_to_tsquery('english', p_query);
  if v_q is not null then
    select exists (select 1 from public.support_knowledge k
                    where k.runtime_index_eligible and k.search @@ v_q
                      and (p_kind is null or k.record_kind = p_kind)) into v_found;
  end if;

  if not v_found then
    v_lex := tsvector_to_array(to_tsvector('english'::regconfig, p_query));
    if v_lex is null or array_length(v_lex, 1) is null then return; end if;
    begin
      v_q := to_tsquery('english'::regconfig,
               array_to_string(array(select '''' || replace(x, '''', '''''') || '''' from unnest(v_lex) x), ' | '));
    exception when others then return;
    end;
    v_how := 'best_terms';
  end if;

  return query
  select k.record_id, k.record_kind, k.title, k.body, k.body_sha256,
         k.source_ids, k.source_path, k.review_status, k.authority_effect,
         k.contains_synthetic_example, k.structured_data,
         ts_rank(k.search, v_q) as relevance, v_how as matched_how,
         'Advisory only. authority_effect=none: this may not approve a refund, grant an entitlement, '
         || 'change a price or become policy. review_status=' || k.review_status || '. '
         || case when k.record_kind = 'message_template'
                 then 'DRAFT TEMPLATE -- not an approved provider template. Check wa_template_registry before sending. ' else '' end
         || case when k.contains_synthetic_example
                 then 'CONTAINS A SYNTHETIC EXAMPLE -- authored, not a real QuotesDone conversation. ' else '' end
         || case when v_how = 'best_terms'
                 then 'MATCHED ON BEST TERMS, not all of them -- read the title before relying on it. ' else '' end
         || 'Account facts come from the database, never from this record.' as warning
    from public.support_knowledge k
   where k.runtime_index_eligible
     and k.search @@ v_q
     and (p_kind is null or k.record_kind = p_kind)
   order by ts_rank(k.search, v_q) desc, k.record_id
   limit greatest(1, least(coalesce(p_limit, 6), 30));
end $function$;

comment on function public.fn_support_knowledge_search(text,int,text) is
  'Lexical retrieval over the support pack. Strict AND first, best-terms fallback only when strict returns nothing, reported in matched_how. relevance is a ranking score and never a probability that the content is true.';

-- ---------------------------------------------------------------------------------------------
-- THE CONTEXT THE SUPPORT AGENT ACTUALLY GETS
-- ---------------------------------------------------------------------------------------------
-- The pack: "Do not paste the entire knowledge pack into every request. Pin safety/operating
-- invariants, retrieve a few relevant support records, retrieve current company-policy excerpts, and
-- add only authorized live facts."
--
-- So this returns three separated things and never merges them: the invariants that are always
-- pinned, a few retrieved advisory records, and a slot the CALLER fills with live account facts from
-- the database. Merging them is how a general playbook gets read back as this customer's situation.
create or replace function public.fn_support_context(
  p_query text,
  p_max_chars int default 12000,
  p_limit int default 5)
returns jsonb
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record; v_out jsonb := '[]'::jsonb; v_used int := 0; v_n int := 0; v_how text;
begin
  for r in select * from public.fn_support_knowledge_search(p_query, p_limit) loop
    exit when v_used + length(r.body) > greatest(1500, p_max_chars);
    v_how := coalesce(v_how, r.matched_how);
    v_out := v_out || jsonb_build_object(
      'record_id', r.record_id, 'record_kind', r.record_kind, 'title', r.title,
      'body', r.body, 'source_ids', to_jsonb(r.source_ids), 'review_status', r.review_status,
      'relevance', r.relevance, 'matched_how', r.matched_how, 'warning', r.warning);
    v_used := v_used + length(r.body); v_n := v_n + 1;
  end loop;

  return jsonb_build_object(
    'query', p_query,
    -- PINNED EVERY TIME, never retrieved and never rankable. These are the rules that must hold
    -- when the retrieval finds nothing, which is exactly when an agent is most tempted to improvise.
    'invariants', jsonb_build_array(
      'Never say you checked, sent, escalated, fixed, refunded or approved anything without tool evidence for it.',
      'A tool error means "cannot verify right now". It never means "no inquiry", "unpaid" or "no discount".',
      'Never reveal a supplier name, contact, logo, amount or quotation content in a notification. The quotation stays in the portal, including after a reveal payment.',
      'Never invent a fee, discount, promotion, policy, deadline or guaranteed outcome.',
      'A supplied email, number or reference is a search clue, never proof of account ownership.',
      'Never request a password, full card number or a banking OTP.',
      'Identify as QuotesDone Support. Never impersonate a person and never claim to be human.',
      'Escalation goes to the CEO. Never to the founder, and never to an invented department.'),
    'advisory_records', v_out,
    'record_count', v_n,
    'matched_how', v_how,
    'sufficient', v_n > 0,
    -- The caller fills this from the database. It is named rather than left implicit so that a
    -- caller who forgets it produces an obviously empty slot instead of a confident general answer.
    'account_facts', null,
    'account_facts_note', 'The CALLER must fill account_facts from authorised live data. Advisory records never contain this customer''s facts.',
    'signal', case when v_n = 0
                   then 'NO ADVISORY COVERAGE for this query. Answer from company policy and live account facts, or say you will check. Do not improvise from these records.'
                   else 'Advisory guidance only. Account facts come from the database.' end);
end $function$;

comment on function public.fn_support_context(text,int,int) is
  'The context the support agent gets: invariants pinned every time, a few retrieved advisory records, and an EMPTY account_facts slot the caller must fill from live data. The three are kept apart so a general playbook can never be read back as this customer''s situation.';
