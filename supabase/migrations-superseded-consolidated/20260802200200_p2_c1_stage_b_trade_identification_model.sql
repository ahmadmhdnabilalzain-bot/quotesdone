-- P2-C1 STAGE B (3/6) - TRADE IDENTIFICATION, the data model.
-- Applied as p2_c1_stage_b_trade_identification_model.
--
-- Five sources, in descending authority: structured customer answers, explicit trade names in
-- customer text, a scope rule ("full MEP package" means the three core trades), subcategory
-- aliases from the imported corpus (4,335 EN + 3,920 AR across routes 9-14), and approved
-- document extraction.
--
-- The rule that shapes everything: a document may PROPOSE a trade, never activate one.

create table if not exists public.mep_trade_pattern (
  id          bigserial primary key,
  trade_key   text references public.mep_trade(trade_key) on delete cascade,
  kind        text not null check (kind in ('trade_name','umbrella','scope_full','scope_only')),
  pattern     text not null,
  lang        text not null default 'en' check (lang in ('en','ar')),
  unique (kind, pattern, lang)
);
alter table public.mep_trade_pattern enable row level security;

comment on table public.mep_trade_pattern is
  'Deterministic surface forms, matched with word boundaries and never as substrings - otherwise "ac" fires inside "access control".';

insert into public.mep_trade_pattern (trade_key, kind, pattern, lang) values
  ('hvac','trade_name','hvac','en'), ('hvac','trade_name','h\.v\.a\.c','en'),
  ('hvac','trade_name','air conditioning','en'), ('hvac','trade_name','air-conditioning','en'),
  ('hvac','trade_name','mechanical ventilation','en'), ('hvac','trade_name','heating ventilation','en'),
  ('hvac','trade_name','تكييف','ar'), ('hvac','trade_name','التكييف','ar'),
  ('electrical','trade_name','electrical','en'), ('electrical','trade_name','electrics','en'),
  ('electrical','trade_name','power distribution','en'),
  ('electrical','trade_name','كهرباء','ar'), ('electrical','trade_name','الكهرباء','ar'),
  ('electrical','trade_name','كهربائية','ar'),
  ('plumbing','trade_name','plumbing','en'), ('plumbing','trade_name','sanitary','en'),
  ('plumbing','trade_name','sanitaryware','en'), ('plumbing','trade_name','drainage','en'),
  ('plumbing','trade_name','سباكة','ar'), ('plumbing','trade_name','صحية','ar'),
  ('fire','trade_name','fire fighting','en'), ('fire','trade_name','firefighting','en'),
  ('fire','trade_name','fire protection','en'), ('fire','trade_name','fire alarm','en'),
  ('fire','trade_name','life safety','en'), ('fire','trade_name','sprinkler','en'),
  ('fire','trade_name','حريق','ar'), ('fire','trade_name','إطفاء','ar'),
  ('elv','trade_name','elv','en'), ('elv','trade_name','extra low voltage','en'),
  ('elv','trade_name','low current','en'), ('elv','trade_name','structured cabling','en'),
  ('elv','trade_name','security systems','en'), ('elv','trade_name','cctv','en'),
  ('elv','trade_name','تيار خفيف','ar'),
  (null,'umbrella','mep','en'), (null,'umbrella','m\.e\.p','en'),
  (null,'umbrella','electromechanical','en'), (null,'umbrella','electro-mechanical','en'),
  (null,'umbrella','كهروميكانيك','ar'),
  (null,'scope_full','full','en'), (null,'scope_full','complete','en'),
  (null,'scope_full','entire','en'), (null,'scope_full','whole','en'),
  (null,'scope_full','turnkey','en'), (null,'scope_full','package','en'),
  (null,'scope_full','comprehensive','en'), (null,'scope_full','all trades','en'),
  (null,'scope_full','all disciplines','en'), (null,'scope_full','كامل','ar'),
  (null,'scope_full','شامل','ar'),
  (null,'scope_only','only','en'), (null,'scope_only','just','en'),
  (null,'scope_only','solely','en'), (null,'scope_only','exclusively','en'),
  (null,'scope_only','فقط','ar')
on conflict (kind, pattern, lang) do nothing;

create table if not exists public.inquiry_trade_candidate (
  id                   bigserial primary key,
  group_id             bigint not null references public.inquiry_workstream_group(id) on delete cascade,
  trade_key            text not null references public.mep_trade(trade_key),
  status               text not null default 'proposed'
                         check (status in ('proposed','confirmed','rejected','inactive')),
  evidence_source      text not null
                         check (evidence_source in ('structured_answer','customer_text','scope_rule',
                                                    'alias','document_extraction')),
  match_reason         text not null,
  confidence           numeric(4,3) not null check (confidence >= 0 and confidence <= 1),
  requires_confirmation boolean not null default true,
  proposed_at          timestamptz not null default now(),
  confirmed_at         timestamptz, confirmed_by text,
  rejected_at          timestamptz, rejected_by text, rejection_reason text,
  inactivated_at       timestamptz,
  activated_at         timestamptz,
  workstream_id        bigint references public.inquiry_workstream(id),
  unique (group_id, trade_key)
);
alter table public.inquiry_trade_candidate enable row level security;

comment on table public.inquiry_trade_candidate is
  'One row per trade ever considered for this inquiry. proposed -> confirmed -> inactive, or proposed -> rejected. Rows are never deleted: a rejected trade is a decision, and a decision with no record is a decision nobody can review.';

create table if not exists public.inquiry_trade_candidate_evidence (
  id               bigserial primary key,
  candidate_id     bigint not null references public.inquiry_trade_candidate(id) on delete cascade,
  evidence_source  text not null,
  matched_term     text,
  subcategory_slug text,
  catalog_num      integer,
  document_id      text,
  document_approved boolean,
  confidence       numeric(4,3),
  detail           jsonb,
  recorded_at      timestamptz not null default now()
);
alter table public.inquiry_trade_candidate_evidence enable row level security;

drop trigger if exists trade_candidate_evidence_append_only on public.inquiry_trade_candidate_evidence;
create trigger trade_candidate_evidence_append_only
  before update or delete on public.inquiry_trade_candidate_evidence
  for each row execute function public.trg_p2c1_append_only();

create table if not exists public.inquiry_trade_clarification (
  id           bigserial primary key,
  group_id     bigint not null references public.inquiry_workstream_group(id) on delete cascade,
  question_en  text not null,
  question_ar  text,
  options      text[] not null,
  reason       text not null,
  asked_at     timestamptz not null default now(),
  answered_at  timestamptz, answered_by text, answer text[]
);
alter table public.inquiry_trade_clarification enable row level security;

create unique index if not exists inquiry_trade_clarification_open_uidx
  on public.inquiry_trade_clarification (group_id) where answered_at is null;

comment on table public.inquiry_trade_clarification is
  'At most one open clarification per inquiry, enforced by the partial unique index. "Ambiguous evidence asks ONE clarification" is a promise about the customer''s experience, so it is a constraint rather than a convention.';

create or replace function public.fn_text_matches_pattern(p_text text, p_pattern text)
returns boolean language sql immutable as $fn$
  select p_text ~* ('(^|[^[:alnum:]])' || p_pattern || '($|[^[:alnum:]])');
$fn$;

revoke all on function public.fn_text_matches_pattern(text, text) from public, anon, authenticated;
