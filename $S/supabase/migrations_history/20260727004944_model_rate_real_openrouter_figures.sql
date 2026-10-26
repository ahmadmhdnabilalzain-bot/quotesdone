-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727004944   name: model_rate_real_openrouter_figures
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.model_rate
  add column if not exists usd_per_m_prompt numeric,
  add column if not exists usd_per_m_output numeric,
  add column if not exists id_verified boolean not null default true,
  add column if not exists source_url text,
  add column if not exists verified_at date;

insert into public.model_rate (model, tier, in_aed_per_mtok, out_aed_per_mtok, usd_per_m_prompt, usd_per_m_output, id_verified, source_url, verified_at, note) values
('~anthropic/claude-haiku-latest','small', 1*3.6725,  5*3.6725,  1,   5,   false,'https://openrouter.ai/api/v1/models', current_date, 'Cheapest Anthropic model on OpenRouter. Router alias — the tilde-prefixed id has NOT been validated in a live request yet.'),
('anthropic/claude-sonnet-5',     'small', 2*3.6725, 10*3.6725,  2,  10,   true, 'https://openrouter.ai/api/v1/models', current_date, 'Best cost/capability ratio of the verified ids. Correct default for mechanical work.'),
('anthropic/claude-opus-4.8',     'large', 5*3.6725, 25*3.6725,  5,  25,   true, 'https://openrouter.ai/api/v1/models', current_date, 'Judgement tier. 2.5x sonnet.'),
('anthropic/claude-fable-5',      'large',10*3.6725, 50*3.6725, 10,  50,   true, 'https://openrouter.ai/api/v1/models', current_date, 'EXPENSIVE: 5x sonnet, 2x opus-4.8. Not a cheap tier despite the name.'),
('anthropic/claude-opus-4.8-fast','large',10*3.6725, 50*3.6725, 10,  50,   true, 'https://openrouter.ai/api/v1/models', current_date, 'Latency-optimised opus. Same price as fable-5.'),
('anthropic/claude-opus-4.7-fast','large',30*3.6725,150*3.6725, 30, 150,   true, 'https://openrouter.ai/api/v1/models', current_date, 'Most expensive Anthropic id on OpenRouter. No approved use case.')
on conflict (model) do update set
  tier=excluded.tier, in_aed_per_mtok=excluded.in_aed_per_mtok, out_aed_per_mtok=excluded.out_aed_per_mtok,
  usd_per_m_prompt=excluded.usd_per_m_prompt, usd_per_m_output=excluded.usd_per_m_output,
  id_verified=excluded.id_verified, source_url=excluded.source_url, verified_at=excluded.verified_at, note=excluded.note;

update public.model_policy
set model_primary  = 'anthropic/claude-sonnet-5',
    model_fallback = 'anthropic/claude-opus-4.8',
    rationale = rationale || ' [corrected 27 Jul 2026: was routed to claude-fable-5, which verified OpenRouter rates show is 5x claude-sonnet-5 and 2x claude-opus-4.8 — the opposite of a cheap tier.]'
where tier = 'small' and model_primary = 'anthropic/claude-fable-5';

insert into public.ai_governance_review (review_type, subject, finding, evidence, severity, action, status) values
('cost','Small-tier model routing',
 'The eight highest-volume task classes (classification, intent, JSON extraction, memory retrieval, missing-field detection, OCR cleanup, RFQ routing, supplier matching) were routed to anthropic/claude-fable-5 on the assumption it was the cheap tier. Verified OpenRouter rates put fable-5 at USD 10/50 per million tokens: 5x claude-sonnet-5 (USD 2/10) and 2x claude-opus-4.8 (USD 5/25). The declared FALLBACK was five times cheaper than the primary. The placeholder rates previously in model_rate had the ordering inverted, which is what made the error invisible.',
 'https://openrouter.ai/api/v1/models fetched 27 Jul 2026; model_rate',
 'high',
 'Small tier repointed to claude-sonnet-5 primary, claude-opus-4.8 fallback. A cheaper option exists (~anthropic/claude-haiku-latest at USD 1/5) but its tilde-prefixed id is unvalidated, so it stays out of the routing path until a live request confirms it.',
 'actioned'),
('model_approval','Haiku router alias',
 'anthropic/claude-haiku-latest is the cheapest Anthropic model on OpenRouter at USD 1/5 per million tokens, but appears only as a tilde-prefixed router alias. Whether that id is accepted in a chat/completions request is unverified.',
 'https://openrouter.ai/api/v1/models',
 'medium',
 'Make one real request with that id. If it resolves, register it and move every small-tier class onto it for a further 2x saving. If it does not, record the negative result so nobody retries it.',
 'open');

insert into public.institutional_memory (kind, subject_type, subject_id, headline, detail, outcome, learned_by, confidence, evidence_ref)
values ('lesson','model_policy','small_tier',
 'A model name that sounds small is not a price.',
 'The small tier was routed to claude-fable-5 on the assumption that a lighter-sounding name meant a lighter price, and model_rate carried placeholder figures that happened to invert the true ordering. The published rate is 5x claude-sonnet-5 and 2x claude-opus-4.8. The error sat in the highest-volume paths in the system, where it would have compounded fastest, and it was invisible because ai_cost_log had never recorded a single call.',
 'Rates are now fetched from the provider and stored with a source URL and verification date. No routing rule may name a model that has no verified row in model_rate.',
 'ai_governance_board', 1.0, 'model_rate; ai_governance_review; https://openrouter.ai/api/v1/models');
