-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709121153   name: prompt_eval_harness
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.prompt_benchmarks(
  id bigint generated always as identity primary key,
  prompt_key text not null,
  name text not null,
  input text not null,
  rubric text not null,
  weight numeric not null default 1,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(prompt_key, name));
alter table public.prompt_benchmarks enable row level security;

create table if not exists public.prompt_eval_runs(
  id bigint generated always as identity primary key,
  prompt_key text not null,
  version int,
  score numeric,
  cases_total int,
  detail jsonb,
  created_at timestamptz not null default now());
alter table public.prompt_eval_runs enable row level security;

insert into public.decision_policy(key, value, description)
values('prompt_sensitive_pattern', to_jsonb('legal|finance|complian|security|quote_review'::text),
       'Prompt keys matching this regex always require founder approval; others may auto-promote when they beat the benchmark.')
on conflict (key) do update set value=excluded.value, description=excluded.description, updated_at=now();

insert into public.prompt_benchmarks(prompt_key,name,input,rubric,weight) values
('quote_review.system','messy_complete',
 'Review this supplier quote and return it in QuotesDone structured format:\nSupply & install 3x Daikin FTKF71 wall-split AC 24000BTU inverter, unit price AED 3,200 each; copper piping 30m @ AED 45/m; installation labour AED 1,500 lump sum. 1yr warranty. 60% advance.',
 'A good answer must: itemise every line with description, brand (Daikin), model (FTKF71), quantity, unit and unit price; keep copper piping and labour as separate lines; compute a correct subtotal/total from the given numbers WITHOUT inventing figures; surface the warranty (1yr) and payment terms (60% advance). Deduct heavily if it fabricates prices or merges lines into a lump sum.',1.5),
('quote_review.system','missing_fields',
 'Review this supplier quote: "Supply and install 5 split AC units for the villa. Total AED 25,000. Ready in 2 weeks."',
 'A good answer must FLAG the missing detail: no brand, no model, no capacity/spec, no per-unit price, no scope breakdown. It should request itemisation and NOT invent brands, models or unit prices. Deduct heavily if it fabricates specifics or accepts the lump sum as complete.',1.5),
('quote_review.system','padded_lump',
 'Review this supplier quote: "Complete MEP works for a 3BR apartment fit-out — AED 180,000 all inclusive."',
 'A good answer must flag that a single all-inclusive lump sum with no BOQ/line items is not acceptable for structured quoting, and ask for a broken-down scope (materials, brands, quantities, unit rates, labour). Must not invent a breakdown. Deduct if it treats the lump sum as a valid structured quote.',1),
('intake.system','vague_rfq',
 'Customer request: "I need AC for my villa in Dubai."',
 'A good answer must recognise the request is under-specified and ask targeted clarifying questions (number/size of rooms or tonnage, ducted vs split, brand preference, budget, timeline, exact area) and categorise it as HVAC/air-conditioning. Must not fabricate specifics or mark it RFQ-ready.',1),
('intake.system','detailed_rfq',
 'Customer request: "Supply and install 200 sqm of 60x60 porcelain floor tiles (matte, light grey), including screed and skirting, for an office in Business Bay, Dubai. Needed within 3 weeks. Budget ~AED 40,000."',
 'A good answer must extract structured intake: category (flooring/tiling), scope (supply + install porcelain 60x60 matte light grey, 200 sqm, screed + skirting), quantity (200 sqm), location (Business Bay, Dubai), timeline (3 weeks), budget (~40,000), and mark it RFQ-ready/complete. Deduct if it needlessly re-asks for info already given.',1)
on conflict (prompt_key,name) do nothing;
