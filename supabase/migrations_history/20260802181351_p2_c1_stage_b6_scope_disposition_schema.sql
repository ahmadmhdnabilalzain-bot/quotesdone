-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802181351   name: p2_c1_stage_b6_scope_disposition_schema
-- SHA-256 of the applied SQL: 9027eb00f0d9dda56421ddee2cb9b15bd98027c826b0c1df0a0a16ccd0138e76
-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;
-- only this header was added, and it is excluded from the checksum.

-- P2-C1 STAGE B.6 (2/n) - the scope disposition model.
--
-- Exclusion is not a boolean. "MEP by others", "ELV optional", "HVAC next phase", "AHUs client
-- supplied" and "existing fire alarm to remain" are five different facts with five different
-- consequences, and a negation flag collapses them into one. Each is a DISPOSITION, held at trade
-- level and, where the sentence says so, at scope-component level.

create table if not exists public.scope_component (
  component text primary key, label_en text not null, label_ar text, sort_order int not null default 0
);
alter table public.scope_component enable row level security;
insert into public.scope_component (component, label_en, label_ar, sort_order) values
  ('design','Design','التصميم',1), ('supply','Supply','التوريد',2),
  ('installation','Installation','التركيب',3), ('testing','Testing','الاختبار',4),
  ('commissioning','Commissioning','التشغيل والتسليم',5),
  ('authority_approvals','Authority approvals','موافقات الجهات',6),
  ('maintenance','Maintenance','الصيانة',7), ('coordination','Coordination','التنسيق',8),
  ('complete_trade_scope','Complete trade scope','نطاق العمل الكامل',9)
on conflict (component) do nothing;

create table if not exists public.scope_disposition_kind (
  disposition           text primary key,
  contributes           boolean not null,
  requires_clarification boolean not null default false,
  is_conflict           boolean not null default false,
  label_en              text not null,
  rationale             text not null
);
alter table public.scope_disposition_kind enable row level security;

insert into public.scope_disposition_kind
  (disposition, contributes, requires_clarification, is_conflict, label_en, rationale) values
  ('included',      true,  false, false, 'Included','In our scope. The default when a trade is named with no qualifier.'),
  ('existing_only', true,  false, false, 'Existing installation only','There IS work - modification, integration, making good - but it is bounded by what already exists.'),
  ('excluded',      false, false, false, 'Excluded','Explicitly out of scope. Contributes nothing and asks nothing.'),
  ('by_others',     false, false, false, 'By others','Someone else is doing it. Different from excluded only in who, but the dispatch consequence is the same.'),
  ('client_supplied',false,false, false, 'Client supplied','The client provides it. At component level this restricts scope; at trade level there is nothing for a supplier to quote.'),
  ('optional',      false, true,  false, 'Optional','Might be wanted. Cannot contribute to a dispatch nobody has committed to.'),
  ('future_phase',  false, false, false, 'Future phase','Real work, wrong time. Excluded from the CURRENT dispatch, not from the relationship.'),
  ('proposed',      false, true,  false, 'Proposed','Raised by evidence, not yet confirmed by a person.'),
  ('unknown',       false, true,  false, 'Unknown','Evidence exists but says nothing about scope. Fail-closed.'),
  ('conflicted',    false, true,  true,  'Conflicted','Two statements of equal specificity disagree. Resolved by asking, never by preferring the last sentence.')
on conflict (disposition) do nothing;

comment on table public.scope_disposition_kind is
  'Only `included` and `existing_only` contribute to completeness and dispatch. Everything else is fail-closed by construction, so a new disposition cannot accidentally become dispatchable.';

create table if not exists public.scope_marker (
  id          bigserial primary key,
  marker_type text not null check (marker_type in ('disposition','component','exception','modification')),
  disposition text references public.scope_disposition_kind(disposition),
  component   text references public.scope_component(component),
  pattern     text not null,
  pattern_norm text,
  lang        text not null default 'en' check (lang in ('en','ar')),
  priority    int not null default 100,
  unique (marker_type, pattern, lang)
);
alter table public.scope_marker enable row level security;

create or replace function public.trg_scope_marker_norm()
returns trigger language plpgsql as $fn$
begin new.pattern_norm := public.fn_norm_text(new.pattern); return new; end $fn$;
drop trigger if exists scope_marker_norm on public.scope_marker;
create trigger scope_marker_norm before insert or update on public.scope_marker
  for each row execute function public.trg_scope_marker_norm();

-- priority: lower number wins. Longer, more specific phrases must be tested first, or
-- "supplied by client" is read as "by client".
insert into public.scope_marker (marker_type, disposition, pattern, lang, priority) values
  ('disposition','client_supplied','supplied by the client','en',10),
  ('disposition','client_supplied','supplied by client','en',10),
  ('disposition','client_supplied','client supplied','en',10),
  ('disposition','client_supplied','client-supplied','en',10),
  ('disposition','client_supplied','free issue','en',10),
  ('disposition','client_supplied','owner supplied','en',10),
  ('disposition','client_supplied','توريد العميل','ar',10),
  ('disposition','client_supplied','توريد المالك','ar',10),
  ('disposition','client_supplied','يوردها العميل','ar',10),
  ('disposition','by_others','by the main contractor','en',20),
  ('disposition','by_others','by main contractor','en',20),
  ('disposition','by_others','not in our scope','en',20),
  ('disposition','by_others','outside our scope','en',20),
  ('disposition','by_others','by others','en',25),
  ('disposition','by_others','by the others','en',25),
  ('disposition','by_others','by the owner','en',25),
  ('disposition','by_others','by owner','en',25),
  ('disposition','by_others','by the client','en',25),
  ('disposition','by_others','by client','en',25),
  ('disposition','by_others','من قبل المقاول الرئيسي','ar',20),
  ('disposition','by_others','ليست ضمن نطاق','ar',20),
  ('disposition','by_others','خارج نطاق','ar',20),
  ('disposition','by_others','من قبل الغير','ar',25),
  ('disposition','by_others','على الغير','ar',25),
  ('disposition','by_others','بواسطه الغير','ar',25),
  ('disposition','by_others','من قبل العميل','ar',25),
  ('disposition','future_phase','future phase','en',30),
  ('disposition','future_phase','later phase','en',30),
  ('disposition','future_phase','next phase','en',30),
  ('disposition','future_phase','future stage','en',30),
  ('disposition','future_phase','phase 2','en',30),
  ('disposition','future_phase','phase two','en',30),
  ('disposition','future_phase','مرحله لاحقه','ar',30),
  ('disposition','future_phase','مرحله مستقبليه','ar',30),
  ('disposition','future_phase','المرحله الثانيه','ar',30),
  ('disposition','optional','if required','en',40),
  ('disposition','optional','as an option','en',40),
  ('disposition','optional','optional','en',40),
  ('disposition','optional','اختياري','ar',40),
  ('disposition','optional','ان لزم','ar',40),
  ('disposition','optional','عند الطلب','ar',40),
  ('disposition','existing_only','existing','en',50),
  ('disposition','existing_only','to remain','en',50),
  ('disposition','existing_only','retained','en',50),
  ('disposition','existing_only','الحالي','ar',50),
  ('disposition','existing_only','القائم','ar',50),
  ('disposition','existing_only','يبقي','ar',50),
  ('disposition','excluded','not required','en',60),
  ('disposition','excluded','not needed','en',60),
  ('disposition','excluded','excluded','en',60),
  ('disposition','excluded','excluding','en',60),
  ('disposition','excluded','omit','en',60),
  ('disposition','excluded','without','en',60),
  ('disposition','excluded','no','en',65),
  ('disposition','excluded','غير مطلوب','ar',60),
  ('disposition','excluded','مستثني','ar',60),
  ('disposition','excluded','مستثناه','ar',60),
  ('disposition','excluded','استبعاد','ar',60),
  ('disposition','excluded','لا يشمل','ar',60),
  ('disposition','excluded','باستثناء','ar',60),
  ('disposition','excluded','بدون','ar',60),
  ('disposition','included','by the contractor','en',70),
  ('disposition','included','by contractor','en',70),
  ('disposition','included','to be provided','en',70),
  ('disposition','included','in scope','en',70),
  ('disposition','included','included','en',75),
  ('disposition','included','required','en',75),
  ('disposition','included','من قبل المقاول','ar',70),
  ('disposition','included','مشمول','ar',75),
  ('disposition','included','مشموله','ar',75),
  ('disposition','included','مطلوب','ar',75),
  ('disposition','included','مطلوبه','ar',75),
  ('disposition','included','يشمل','ar',75)
on conflict (marker_type, pattern, lang) do nothing;

insert into public.scope_marker (marker_type, component, pattern, lang, priority) values
  ('component','authority_approvals','authority approvals','en',10),
  ('component','authority_approvals','authority approval','en',10),
  ('component','authority_approvals','approvals','en',15),
  ('component','authority_approvals','موافقات','ar',10),
  ('component','authority_approvals','اعتمادات','ar',10),
  ('component','commissioning','commissioning','en',20),
  ('component','commissioning','تشغيل','ar',20),
  ('component','installation','installation','en',20),
  ('component','installation','installed','en',20),
  ('component','installation','install','en',25),
  ('component','installation','تركيب','ar',20),
  ('component','supply','supplied','en',20),
  ('component','supply','supply','en',25),
  ('component','supply','توريد','ar',20),
  ('component','testing','testing','en',20),
  ('component','testing','test','en',25),
  ('component','testing','اختبار','ar',20),
  ('component','testing','فحص','ar',20),
  ('component','design','design','en',20),
  ('component','design','تصميم','ar',20),
  ('component','maintenance','maintenance','en',20),
  ('component','maintenance','صيانه','ar',20),
  ('component','coordination','coordination','en',20),
  ('component','coordination','coordinate','en',20),
  ('component','coordination','تنسيق','ar',20)
on conflict (marker_type, pattern, lang) do nothing;

insert into public.scope_marker (marker_type, pattern, lang, priority) values
  ('exception','except','en',10), ('exception','excluding','en',10),
  ('exception','apart from','en',10), ('exception','without','en',10),
  ('exception','عدا','ar',10), ('exception','باستثناء','ar',10), ('exception','بدون','ar',10),
  ('modification','modifications','en',10), ('modification','modification','en',10),
  ('modification','alteration','en',10), ('modification','upgrade','en',10),
  ('modification','تعديلات','ar',10), ('modification','تعديل','ar',10), ('modification','ترقيه','ar',10)
on conflict (marker_type, pattern, lang) do nothing;

create table if not exists public.inquiry_scope_disposition (
  id             bigserial primary key,
  group_id       bigint not null references public.inquiry_workstream_group(id) on delete cascade,
  trade_key      text references public.mep_trade(trade_key),
  scope_component text not null references public.scope_component(component)
                   default 'complete_trade_scope',
  disposition    text not null references public.scope_disposition_kind(disposition),
  specificity    integer not null,
  source_kind    text not null check (source_kind in ('customer_text','structured_answer','document_extraction')),
  evidence_source text not null,
  evidence_score numeric(4,3) not null,
  score_basis    text not null default 'rule_weight_provisional',
  clause_index   integer,
  clause_text    text,
  matched_marker text,
  reason         text not null,
  confirmation_status text not null default 'inferred'
                   check (confirmation_status in ('inferred','confirmed','rejected')),
  confirmed_by   text, confirmed_at timestamptz,
  actor          text,
  created_at     timestamptz not null default now()
);
alter table public.inquiry_scope_disposition enable row level security;
create index if not exists inquiry_scope_disposition_group_idx
  on public.inquiry_scope_disposition (group_id, trade_key, scope_component);

drop trigger if exists inquiry_scope_disposition_append_only on public.inquiry_scope_disposition;
create trigger inquiry_scope_disposition_append_only
  before update or delete on public.inquiry_scope_disposition
  for each row execute function public.trg_p2c1_append_only();

comment on table public.inquiry_scope_disposition is
  'Append-only. Every disposition keeps its trade, component, source, evidence score and basis, the clause it came from, the marker that matched, the reason and its confirmation status. Specificity: 0 umbrella+complete, 1 umbrella+component, 2 trade+complete, 3 trade+component, 4 structured selection.';
;