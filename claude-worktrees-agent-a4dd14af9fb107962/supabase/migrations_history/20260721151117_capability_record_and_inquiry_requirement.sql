-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721151117   name: capability_record_and_inquiry_requirement
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Additive only. supplier_capabilities currently holds 0 rows and is read by exactly one
-- display function (fn_ws_supplier_360), so adding nullable columns carries no regression risk.

alter table public.supplier_capabilities
  add column if not exists trades              text[]  not null default '{}',
  add column if not exists roles               text[]  not null default '{}',
  add column if not exists products_norm       text[]  not null default '{}',
  add column if not exists project_types       text[]  not null default '{}',
  add column if not exists exclusions          text[]  not null default '{}',
  add column if not exists authority_approvals jsonb   not null default '{}'::jsonb,
  add column if not exists source_docs         jsonb   not null default '{}'::jsonb,
  add column if not exists confidence          jsonb   not null default '{}'::jsonb,
  add column if not exists completeness        numeric,
  add column if not exists extracted_at        timestamptz,
  add column if not exists extractor_version   text,
  add column if not exists review_status       text    not null default 'pending';

comment on column public.supplier_capabilities.exclusions is
  'Negative scope: what this supplier explicitly does NOT do. Used as a HARD GATE. This is the cheapest anti-spam mechanism in the system.';
comment on column public.supplier_capabilities.confidence is
  'Per-field confidence 0..1 from the extractor. Low-confidence fields must not be hard-gated on, and drive the human review queue.';
comment on column public.supplier_capabilities.source_docs is
  'Per-field provenance (document + page). Makes any bad match auditable back to the exact extracted claim.';
comment on column public.supplier_capabilities.review_status is
  'pending | auto_approved | needs_review | reviewed | rejected';

-- one capability row per supplier
create unique index if not exists ux_supplier_capabilities_supplier
  on public.supplier_capabilities (supplier_id);

-- gate-dimension indexes (array containment / overlap)
create index if not exists idx_supcap_trades     on public.supplier_capabilities using gin (trades);
create index if not exists idx_supcap_roles      on public.supplier_capabilities using gin (roles);
create index if not exists idx_supcap_emirates   on public.supplier_capabilities using gin (coverage_emirates);
create index if not exists idx_supcap_exclusions on public.supplier_capabilities using gin (exclusions);
create index if not exists idx_supcap_products   on public.supplier_capabilities using gin (products_norm);

-- ---------------- the customer side, deliberately the same shape ----------------
create table if not exists public.inquiry_requirement (
  inquiry_id        uuid primary key references public.inquiries(id) on delete cascade,
  trades_required   text[]  not null default '{}',
  role_required     text,
  emirate           text,
  authority_required text[] not null default '{}',
  products_norm     text[]  not null default '{}',
  brands_specified  text[]  not null default '{}',
  project_type      text,
  value_band        numeric,
  scope_type        text,
  confidence        jsonb   not null default '{}'::jsonb,
  missing_fields    text[]  not null default '{}',
  parsed_at         timestamptz not null default now(),
  parser_version    text
);

comment on table public.inquiry_requirement is
  'Customer inquiry normalised into the SAME controlled vocabulary as supplier_capabilities. Symmetry is what turns matching into set intersection instead of ILIKE text similarity.';

create index if not exists idx_inqreq_trades on public.inquiry_requirement using gin (trades_required);

-- ---------------- helper: map legacy free text onto the controlled vocabulary ----------------
-- Used by the extractor and the inquiry parser to normalise, and to backfill the existing base.
create or replace function public.fn_norm_trades(p_text text)
returns text[] language sql stable set search_path to 'public','pg_temp' as $$
  select coalesce(array_agg(distinct t.code order by t.code), '{}')
  from public.taxonomy_trade t
  where t.active
    and (lower(coalesce(p_text,'')) like '%'||lower(t.code)||'%'
      or exists (select 1 from unnest(t.aliases) a
                 where lower(coalesce(p_text,'')) like '%'||lower(a)||'%'));
$$;

create or replace function public.fn_norm_roles(p_text text)
returns text[] language sql stable set search_path to 'public','pg_temp' as $$
  select coalesce(array_agg(distinct r.code order by r.code), '{}')
  from public.taxonomy_role r
  where r.active
    and (lower(coalesce(p_text,'')) like '%'||lower(r.code)||'%'
      or exists (select 1 from unnest(r.aliases) a
                 where lower(coalesce(p_text,'')) like '%'||lower(a)||'%'));
$$;
