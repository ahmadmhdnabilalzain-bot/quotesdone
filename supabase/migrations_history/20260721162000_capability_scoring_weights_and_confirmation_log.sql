-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721162000   name: capability_scoring_weights_and_confirmation_log
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Scoring weights live as DATA so they can be tuned without a code change or deploy.
-- Note: emirate is deliberately absent. UAE suppliers work across emirates; location is used
-- ONLY to check emirate-specific regulatory approval (civil defence / SIRA / utility), never to rank.
insert into public.decision_policy (key, value, description) values
 ('score_w_product',      '40'::jsonb, 'Points: supplier lists the specific product/material the customer asked for.'),
 ('score_w_brand',        '20'::jsonb, 'Points: supplier carries/is authorised for the brand the customer named.'),
 ('score_w_project_type', '15'::jsonb, 'Points: supplier has done this project type (office fit-out, villa, retail, industrial).'),
 ('score_w_track_record', '15'::jsonb, 'Points: response + quote reliability from supplier_perf.'),
 ('score_w_size_fit',     '10'::jsonb, 'Points: job value sits inside the supplier''s normal project range.'),
 ('match_relevance_floor','35'::jsonb, 'Minimum score to dispatch. Below this we do NOT contact the supplier even on an LLM fit verdict — protects suppliers from marginal inquiries.'),
 ('match_max_fanout',      '5'::jsonb, 'Max suppliers contacted for a single-trade inquiry.'),
 ('match_max_fanout_per_trade','3'::jsonb, 'Max suppliers per trade when a multi-trade job is SPLIT, so a split job does not contact more suppliers overall than a combined one.')
on conflict (key) do nothing;

-- What the supplier actually agreed to. Immutable log, one row per confirmation round.
-- Operational purpose: when a supplier disputes a match months later, show exactly what they confirmed.
create table if not exists public.supplier_capability_confirmation (
  id            uuid primary key default gen_random_uuid(),
  supplier_id   bigint not null,
  version       int    not null default 1,
  proposed      jsonb  not null default '{}'::jsonb,   -- what the agent extracted from documents
  confirmed     jsonb  not null default '{}'::jsonb,   -- what the supplier agreed to (source of truth)
  supplier_added jsonb not null default '{}'::jsonb,   -- what the supplier added that we missed
  exclusions    text[] not null default '{}',          -- answer to "anything here you do NOT take on?"
  source_docs   jsonb  not null default '{}'::jsonb,
  confirmed_at  timestamptz,
  confirmed_via text,                                   -- portal | email | admin
  agent_version text,
  created_at    timestamptz not null default now()
);
create index if not exists idx_supcapconf_supplier on public.supplier_capability_confirmation (supplier_id, version desc);

comment on table public.supplier_capability_confirmation is
  'Immutable record of each scope-confirmation round. The supplier validates their own capability, so extraction error is corrected at source and we hold their explicit agreement to what they will receive.';

-- what the agent still needs before the supplier can submit
alter table public.supplier_capabilities
  add column if not exists missing_fields  text[] not null default '{}',
  add column if not exists confirmed_at    timestamptz,
  add column if not exists confirmed_version int;

comment on column public.supplier_capabilities.confirmed_at is
  'Set only when the supplier has confirmed the scope. Matching should require this — an unconfirmed extraction must never generate supplier contact.';
