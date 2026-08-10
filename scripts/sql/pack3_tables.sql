-- The three artefacts of the AI autonomy pack that had no table at all: the tool/connector
-- matrix (22), the recommended model catalogue (14), and the per-identity model policies
-- (96 target employees + 24 current production agents). Scorecard put this pack at 28.6%
-- because only the 32 task classes had anywhere to live.
--
-- These are the pack's RECOMMENDATIONS, kept separate from what production actually runs:
-- model_policy stays the live routing table and model_registry stays the live model list.
-- Nothing here changes a route by existing.
create table if not exists public.ai_tool_matrix (
  tool text primary key,
  current_status text, priority text, required_before_launch text,
  purpose text, recommendation text, code_dependency text,
  package_version text not null default 'v2026.07.31',
  imported_at timestamptz not null default now()
);

create table if not exists public.model_catalog (
  model_id text primary key,
  tier_role text, price_input_usd_per_m numeric, price_output_usd_per_m numeric,
  context text, best_for text, deployment_note text,
  package_version text not null default 'v2026.07.31',
  imported_at timestamptz not null default now()
);

create table if not exists public.model_policy_by_identity (
  identity_key text not null,
  scope text not null check (scope in ('target_employee','current_agent')),
  department text, title text, deterministic_first text,
  primary_model text, fallback_model text, escalation_model text,
  max_output_tokens int, reasoning_effort text, manager text, authority_tier text, note text,
  package_version text not null default 'v2026.07.31',
  imported_at timestamptz not null default now(),
  primary key (identity_key, scope)
);

revoke all on public.ai_tool_matrix, public.model_catalog, public.model_policy_by_identity from anon, authenticated;
