-- THE SALES ENGINEER GETS ITS OWN KNOWLEDGE BODY
--
-- QuotesDone_Sales_Engineer_Knowledge_v1 (package_id QD-SALES-ENGINEER, version 1.0.0). Measured
-- from the extracted pack on 9 Sep 2026: records/knowledge.jsonl carries 1,136 records -- 896
-- qualification_field, 128 sector_guide, 32 worked_case, 28 metric, 27 operating_guide, 15
-- technical_decision_guide, 10 reasoning_guide. Every record_id is unique and every title+content
-- body is distinct (1,136 distinct sha256 over title+content).
--
-- ITS OWN NAMESPACE, and its own table, for the reason support_knowledge has one: the CEO pack, the
-- support pack and this pack answer different questions, and a sector qualification field surfacing
-- in a support retrieval is a category error rather than a lucky hit. It is NOT agent_knowledge --
-- non-`cat:` rows there have no natural unique key, so a repeat import duplicates instead of
-- updating -- and it is NOT ops_knowledge.
--
-- WHAT THE PACK FORBIDS, honoured rather than noted:
--   * manifest.json -> runtime_files names ONE file: records/knowledge.jsonl. Recursive folder
--     ingestion would import 2,532 records (2.23x): the Markdown mirrors under knowledge/ (+212),
--     the SQLite index (+1,136) and the eval scenarios (+48). The loader refuses any path that is
--     not records/*.jsonl.
--   * evaluation/, tests/, tools/, quality/ and the build prompts NEVER enter runtime retrieval.
--   * authority_effect is `none` on all 1,136 records and the CHECK below pins it there. A
--     knowledge record may DESCRIBE authority; it may never CARRY it.
--   * every record is epistemic_status=authored_guidance_not_expert_certified and
--     review_status=package_validated_not_live_approved. There is NO confidence gradation in this
--     pack; nothing here invents one, and nothing is promoted to "reviewed" on import.
--   * jurisdiction is `UAE_applicability_must_be_resolved` on every record -- stored verbatim, not
--     silently resolved to "UAE".
--
-- content_sha256 IS NOT sha256(content). The pack's tools/knowledge.py:canonical_hash computes it
-- over the whole record MINUS that field. So it is stored VERBATIM as the pack's own integrity
-- token, and a separately computed body_sha256 over title+content is what this estate dedupes on.
-- Recomputing the pack's hash naively would produce a mismatch and prove nothing.

-- ---------------------------------------------------------------------------------------------
-- 1. THE KNOWLEDGE BODY
-- ---------------------------------------------------------------------------------------------
create table if not exists public.sales_knowledge (
  record_id            text primary key,
  record_type          text not null,
  domain               text,
  title                text not null,
  content              text not null,
  structured_data      jsonb not null default '{}'::jsonb,
  source_ids           text[] not null default '{}',
  epistemic_status     text not null,
  jurisdiction         text,
  pack_id              text not null,
  pack_version         text not null,
  record_version       text not null,
  -- OURS: sha256 over title + '\n' + content. This is what a repeat import compares and what a
  -- collision report is built from.
  body_sha256          text not null,
  -- THEIRS: the pack's canonical hash of the whole record minus this field. Stored verbatim.
  content_sha256       text not null,
  runtime_index_eligible boolean not null default true,
  authority_effect     text not null default 'none',
  tags                 text[] not null default '{}',
  updated_at           timestamptz,
  ingested_at          timestamptz not null default now(),
  embedding_gte        vector(384),
  search               tsvector,

  -- A sales record may advise on what to ask and what to check. It may never approve, price,
  -- commit or become policy.
  constraint sales_knowledge_authority_ck check (authority_effect = 'none')
);

create index if not exists sales_knowledge_search_idx on public.sales_knowledge using gin (search);
create index if not exists sales_knowledge_type_idx   on public.sales_knowledge (record_type);
-- THE ANN INDEX agent_knowledge NEVER GOT. Without it a semantic retrieval over 1,136 rows is a
-- sequential scan of 1,136 384-dimension distance computations; that is survivable at this size
-- and stops being survivable the moment a second pack lands in the same table.
create index if not exists sales_knowledge_emb_hnsw
  on public.sales_knowledge using hnsw (embedding_gte vector_cosine_ops);

comment on table public.sales_knowledge is
  'QuotesDone_Sales_Engineer_Knowledge_v1: 1,136 advisory records in their own QD-SE-* namespace, separate from support_knowledge, ceo_knowledge, agent_knowledge and ops_knowledge. Authored guidance with NO authority (CHECK pins authority_effect=none): nothing retrieved here may approve, price, commit or become policy. Every record is package_validated_not_live_approved -- the pack carries no confidence gradation and none was invented on import.';

comment on column public.sales_knowledge.content_sha256 is
  'The PACK''s own canonical hash: sha256 over the whole record minus this field (tools/knowledge.py:canonical_hash). It is NOT sha256(content). Stored verbatim as an integrity token; never recomputed here.';
comment on column public.sales_knowledge.body_sha256 is
  'THIS estate''s dedupe key: sha256 over title || E''\n'' || content. Measured distinct across all 1,136 records at import.';
comment on column public.sales_knowledge.jurisdiction is
  'Verbatim from the pack: UAE_applicability_must_be_resolved on every record. The pack does not assert UAE applicability; it asserts that applicability must be resolved before use.';

-- The search vector, maintained on write -- a trigger rather than a generated column because
-- Postgres will not accept a stored generated column whose expression it cannot prove immutable.
create or replace function public.fn_sales_knowledge_search_vector()
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

drop trigger if exists a10_sales_knowledge_search_vector on public.sales_knowledge;
create trigger a10_sales_knowledge_search_vector
  before insert or update of title, tags, content on public.sales_knowledge
  for each row execute function public.fn_sales_knowledge_search_vector();

-- ---------------------------------------------------------------------------------------------
-- 2. THE 128-FAMILY TAXONOMY
-- ---------------------------------------------------------------------------------------------
-- contracts/sector_registry.json: 128 families, each with exactly 7 questions (896 = 128 x 7,
-- measured; the registry's question set and field_catalog.json are the same 896 field_keys).
--
-- maps_to_trades IS DELIBERATELY EMPTY. The estate has FOUR live taxonomies --
-- catalog_supplier_categories (86 rows, 13,906 leads bound), catalog_subcategories (470),
-- taxonomy_trade (40, 15,305 capability rows bound), taxonomy_role (8) -- plus a hardcoded fifth.
-- A wrong mapping does not fail loudly; it silently re-routes live bindings. The candidate mapping
-- is reported in docs/sales-engineer/TAXONOMY_MAPPING.md and stays a report until it is decided.
create table if not exists public.sales_sector (
  sector_id       text primary key,
  group_key       text,
  title           text not null,
  scope           text,
  maps_to_trades  text[] not null default '{}'
);

comment on table public.sales_sector is
  'The 128 sector families of QuotesDone_Sales_Engineer_Knowledge_v1. This is the PACK''s taxonomy, not the live one.';
comment on column public.sales_sector.maps_to_trades is
  'Deliberately empty. The estate has four live taxonomies with live bindings (13,906 leads on catalog_supplier_categories; 15,305 capability rows on taxonomy_trade); a wrong mapping breaks them silently. Candidates are reported in docs/sales-engineer/TAXONOMY_MAPPING.md and this column stays empty until that mapping is decided.';

-- ---------------------------------------------------------------------------------------------
-- 3. THE 896 QUALIFICATION FIELDS
-- ---------------------------------------------------------------------------------------------
-- field_key is '<sector_id>.<field>' on all 896 -- measured: 0 field_keys whose prefix is not a
-- sector_id -- so the FK is real, not decorative.
create table if not exists public.sales_qualification_field (
  field_key         text primary key,
  sector_id         text not null references public.sales_sector(sector_id) on delete cascade,
  question          text not null,
  answer_type       text,
  ask_only_if       text,
  criticality       text,
  unknown_handling  text
);

create index if not exists sales_qualification_field_sector_idx
  on public.sales_qualification_field (sector_id);

comment on table public.sales_qualification_field is
  'The 896 qualification fields of the pack, 7 per sector family. ask_only_if and unknown_handling are the pack''s own restraint rules: a field is asked only when live evidence has not already answered it.';

-- ---------------------------------------------------------------------------------------------
-- 4. GRANTS -- THIS IS INTERNAL KNOWLEDGE
-- ---------------------------------------------------------------------------------------------
-- Nothing here is public. A browser holding an anon key must not be able to read the qualification
-- playbook, and a signed-in customer must not either: knowing which seven questions decide a
-- match, and what a wrong-match trap looks like, is the product.
revoke all on public.sales_knowledge          from anon, authenticated;
revoke all on public.sales_sector             from anon, authenticated;
revoke all on public.sales_qualification_field from anon, authenticated;

alter table public.sales_knowledge           enable row level security;
alter table public.sales_sector              enable row level security;
alter table public.sales_qualification_field enable row level security;
-- No policies: RLS with no policy denies every non-superuser, non-owner role. service_role bypasses
-- RLS, which is exactly the reach the loader and the edge functions need and no more. RLS is here
-- as well as the revoke because a later blanket `grant ... on all tables in schema public` -- the
-- kind a migration writes without reading this file -- would undo the revoke and not the RLS.
--
-- fn_sales_knowledge_search_vector is not revoked here: it is `create or replace`, which preserves
-- the existing ACL, and it is a SECURITY INVOKER trigger function carrying no privilege of its own.
