-- ---------------------------------------------------------------------------
-- MODEL REGISTRY — the priced catalogue the router chooses from.
--
-- Before this, llm_policy approved exactly three models: claude-sonnet-5,
-- claude-opus-4.8 and gte-small. There was no cheap tier in existence, so 100% of
-- 143 logged calls went to Sonnet (77%) or Opus (23%). The router could not have
-- routed cheaply even if it had been running.
--
-- Prices are USD per token as published by OpenRouter on 28 Jul 2026, stored per
-- MILLION tokens for readability. cache_read is the number that matters most here:
-- on Anthropic it is 10% of the prompt price, and 94% of our spend is input.
-- ---------------------------------------------------------------------------

create table if not exists model_registry (
  model_id            text primary key,
  provider            text not null,
  tier                text not null check (tier in ('small','medium','large','xlarge')),
  in_per_mtok_usd     numeric not null,
  out_per_mtok_usd    numeric not null,
  cache_read_per_mtok_usd  numeric,
  cache_write_per_mtok_usd numeric,
  supports_cache      boolean not null default false,
  supports_streaming  boolean not null default true,
  context_len         integer,
  approved            boolean not null default true,
  active              boolean not null default true,
  quality_score       numeric,        -- filled by fn_model_benchmark from real outcomes
  note                text,
  updated_at          timestamptz not null default now()
);
alter table model_registry enable row level security;
revoke all on model_registry from public, anon, authenticated;

insert into model_registry
  (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd, cache_read_per_mtok_usd, cache_write_per_mtok_usd, supports_cache, context_len, note)
values
  -- SMALL: classification, extraction, routing, short structured output.
  ('google/gemini-3.1-flash-lite','google','small', 0.25, 1.50, null, null, false, 1048576,
   'Cheapest mainstream model. 8x cheaper input than Sonnet. Default for classification and extraction.'),
  ('qwen/qwen3.7-plus','qwen','small', 0.32, 1.28, null, null, false, 1000000,
   'Second small option; cheaper output than Flash-Lite. Used as the small-tier fallback.'),

  -- MEDIUM: drafting, summarising, customer replies.
  ('~anthropic/claude-haiku-latest','anthropic','medium', 1.00, 5.00, 0.10, 1.25, true, 200000,
   'Cheapest cache-capable model. Cache reads are 1/10th of prompt price - the right home for anything with a large stable prefix.'),
  ('google/gemini-3.5-flash','google','medium', 1.50, 9.00, null, null, false, 1048576,
   'Long-context medium option for document work. No prompt caching.'),

  -- LARGE: reasoning, planning, negotiation.
  ('anthropic/claude-sonnet-5','anthropic','large', 2.00, 10.00, 0.20, 2.50, true, 200000,
   'Current default for everything. Should become the exception, not the rule.'),

  -- XLARGE: only where the decision genuinely justifies it.
  ('anthropic/claude-opus-4.8','anthropic','xlarge', 5.00, 25.00, 0.50, 6.25, true, 200000,
   'Strategy, contracts, arbitration. 20x the input cost of Flash-Lite.')
on conflict (model_id) do update set
  provider=excluded.provider, tier=excluded.tier,
  in_per_mtok_usd=excluded.in_per_mtok_usd, out_per_mtok_usd=excluded.out_per_mtok_usd,
  cache_read_per_mtok_usd=excluded.cache_read_per_mtok_usd,
  cache_write_per_mtok_usd=excluded.cache_write_per_mtok_usd,
  supports_cache=excluded.supports_cache, context_len=excluded.context_len,
  note=excluded.note, updated_at=now();

-- What a call would cost on each model, so routing decisions and the dashboard can
-- speak in money rather than tiers.
create or replace function fn_model_cost_usd(
  p_model text, p_in_tokens integer, p_out_tokens integer, p_cached_in_tokens integer default 0)
returns numeric
language sql stable
set search_path = public, pg_temp
as $$
  select round(
      ( (greatest(coalesce(p_in_tokens,0) - coalesce(p_cached_in_tokens,0), 0)::numeric / 1000000) * r.in_per_mtok_usd
      + (coalesce(p_cached_in_tokens,0)::numeric / 1000000) * coalesce(r.cache_read_per_mtok_usd, r.in_per_mtok_usd)
      + (coalesce(p_out_tokens,0)::numeric / 1000000) * r.out_per_mtok_usd
      )::numeric, 6)
  from model_registry r where r.model_id = p_model;
$$;

revoke execute on function fn_model_cost_usd(text,integer,integer,integer) from public, anon, authenticated;

comment on table model_registry is
  'Priced model catalogue with real OpenRouter pricing (28 Jul 2026). Replaces llm_policy as the routing source. Adds the small tier that did not previously exist anywhere in the system.';