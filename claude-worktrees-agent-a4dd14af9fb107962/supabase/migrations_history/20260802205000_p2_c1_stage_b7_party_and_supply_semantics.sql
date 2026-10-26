-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802205000   name: p2_c1_stage_b7_party_and_supply_semantics
-- SHA-256 of the applied SQL: bc0d12d829932f3e4f41fc7c045952ee5fa85bcf0cc6c29c04ae27d48167f216
-- Recovered by scripts/recover_one.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B.7 (1/6) - PART 3: the semantic model behind excluded / by_others / client_supplied.
--
-- Stage B.6 decided these three by matching whole phrases. That is why "fire fighting is not in our
-- scope" was read as by_others: the phrase sat in the by_others list. But "not in our scope" names
-- no one. It removes scope from us and stops. "by the main contractor" removes the same scope AND
-- says who now holds it. Those are different facts and the phrase list cannot tell them apart,
-- because the distinction is not lexical - it is whether a RESPONSIBLE PARTY is identified.
--
-- So the vocabulary is split into its parts and the classification is composed from them:
--
--   removal marker           - scope leaves us              ("not in our scope", "ليست ضمن نطاق")
--   party marker             - who now holds it, and which side they are on
--                              third_party  : someone else in the supply chain (others, main contractor)
--                              counterparty : the buying side (client, owner, employer, customer)
--   attribution connector    - the grammar that BINDS a party to the work ("by", "من قبل")
--   supply anchor            - the component being attributed ("supply", "free issue", "توريد")
--
--   removal + no party                     -> excluded
--   removal + identified party             -> by_others
--   supply anchor + attributed counterparty-> client_supplied ON THE SUPPLY COMPONENT
--
-- A party that is merely mentioned is not a responsible party. "The client's tower" identifies
-- nobody; "by the client" does. Attribution is required, and it is grammar, so it lives in the
-- table too rather than being spelled out inside a function.
--
-- Every classification records which rule fired, which party was found, in which role, and from
-- which clause - so a wrong answer can be traced to the rule that produced it.

alter table public.scope_marker
  add column if not exists party_class text,
  add column if not exists resolution  text not null default 'fixed';

alter table public.scope_marker drop constraint if exists scope_marker_party_class_check;
alter table public.scope_marker add constraint scope_marker_party_class_check
  check (party_class is null or party_class in ('third_party','counterparty'));

alter table public.scope_marker drop constraint if exists scope_marker_resolution_check;
alter table public.scope_marker add constraint scope_marker_resolution_check
  check (resolution in ('fixed','party_dependent'));

alter table public.scope_marker drop constraint if exists scope_marker_marker_type_check;
alter table public.scope_marker add constraint scope_marker_marker_type_check
  check (marker_type in ('disposition','component','exception','modification',
                         'party','attribution','supply_anchor'));

comment on column public.scope_marker.party_class is
  'For marker_type=party only. third_party is someone else in the supply chain; counterparty is the buying side. Only a counterparty can make a component client_supplied - "supply by the main contractor" is by_others, not client_supplied.';
comment on column public.scope_marker.resolution is
  'fixed: the disposition column is the answer. party_dependent: the marker states only that scope leaves us; whether that is excluded or by_others is decided by whether a responsible party is identified.';

-- ---------------------------------------------------------------- removal, no party named
-- These four were by_others. They name nobody, so by_others was an assertion the text does not
-- make. They become party_dependent: excluded by default, by_others only when the sentence
-- actually identifies who now holds the scope.
update public.scope_marker
   set disposition = 'excluded', resolution = 'party_dependent', priority = 20
 where marker_type = 'disposition'
   and pattern in ('not in our scope','outside our scope','ليست ضمن نطاق','خارج نطاق');

insert into public.scope_marker (marker_type, disposition, pattern, lang, priority, resolution) values
  ('disposition','excluded','out of our scope','en',20,'party_dependent'),
  ('disposition','excluded','not within our scope','en',20,'party_dependent'),
  ('disposition','excluded','not part of our scope','en',20,'party_dependent'),
  ('disposition','excluded','not part of our package','en',20,'party_dependent'),
  ('disposition','excluded','outside the scope of our works','en',20,'party_dependent'),
  ('disposition','excluded','excluded from our scope','en',20,'party_dependent'),
  ('disposition','excluded','removed from our scope','en',20,'party_dependent'),
  ('disposition','excluded','not our scope','en',22,'party_dependent'),
  ('disposition','excluded','ليس ضمن نطاق','ar',20,'party_dependent'),
  ('disposition','excluded','ليست من نطاق','ar',20,'party_dependent'),
  ('disposition','excluded','ليس من نطاق','ar',20,'party_dependent'),
  ('disposition','excluded','خارج نطاق اعمالنا','ar',20,'party_dependent'),
  ('disposition','excluded','مستبعد من نطاقنا','ar',20,'party_dependent')
on conflict (marker_type, pattern, lang) do nothing;

-- ---------------------------------------------------------------- who
-- `contractor` alone is deliberately absent. In this business "by the contractor" means US, and
-- Stage B.6 already classifies it as included. Only qualified contractor roles are third parties.
insert into public.scope_marker (marker_type, pattern, lang, priority, party_class) values
  ('party','others','en',10,'third_party'),
  ('party','other contractor','en',10,'third_party'),
  ('party','another contractor','en',10,'third_party'),
  ('party','main contractor','en',10,'third_party'),
  ('party','principal contractor','en',10,'third_party'),
  ('party','general contractor','en',10,'third_party'),
  ('party','civil contractor','en',10,'third_party'),
  ('party','specialist contractor','en',10,'third_party'),
  ('party','nominated subcontractor','en',10,'third_party'),
  ('party','nominated sub-contractor','en',10,'third_party'),
  ('party','third party','en',10,'third_party'),
  ('party','separate contractor','en',10,'third_party'),
  ('party','الغير','ar',10,'third_party'),
  ('party','مقاول رئيسي','ar',10,'third_party'),
  ('party','مقاول اخر','ar',10,'third_party'),
  ('party','مقاول منفصل','ar',10,'third_party'),
  ('party','طرف ثالث','ar',10,'third_party'),
  ('party','مقاول متخصص','ar',10,'third_party'),
  ('party','client','en',10,'counterparty'),
  ('party','owner','en',10,'counterparty'),
  ('party','employer','en',10,'counterparty'),
  ('party','customer','en',10,'counterparty'),
  ('party','end user','en',10,'counterparty'),
  ('party','end-user','en',10,'counterparty'),
  ('party','عميل','ar',10,'counterparty'),
  ('party','مالك','ar',10,'counterparty'),
  ('party','زبون','ar',10,'counterparty'),
  ('party','صاحب عمل','ar',10,'counterparty'),
  ('party','مستخدم نهائي','ar',10,'counterparty')
on conflict (marker_type, pattern, lang) do nothing;

-- ---------------------------------------------------------------- the grammar that binds a party
-- Attribution is what turns a mention into a responsibility. "The client's tower" identifies
-- nobody; "by the client" does. Kept in the table so the rule is inspectable, not buried in a
-- function body.
insert into public.scope_marker (marker_type, pattern, lang, priority) values
  ('attribution','by','en',10),
  ('attribution','from','en',10),
  ('attribution','من قبل','ar',10),
  ('attribution','بواسطه','ar',10),
  ('attribution','من طرف','ar',10),
  ('attribution','علي عاتق','ar',10)
on conflict (marker_type, pattern, lang) do nothing;

-- ---------------------------------------------------------------- what is being supplied
-- The component words `supply`/`supplied`/`توريد` are already component markers. These are the
-- SUPPLY ANCHORS: every deterministic way of saying that material or equipment is being provided,
-- including the ones that carry no component word at all ("free issue").
insert into public.scope_marker (marker_type, pattern, lang, priority) values
  ('supply_anchor','supply','en',10),
  ('supply_anchor','supplies','en',10),
  ('supply_anchor','supplied','en',10),
  ('supply_anchor','supplying','en',10),
  ('supply_anchor','provide','en',10),
  ('supply_anchor','provides','en',10),
  ('supply_anchor','provided','en',10),
  ('supply_anchor','providing','en',10),
  ('supply_anchor','provision','en',10),
  ('supply_anchor','furnish','en',10),
  ('supply_anchor','furnished','en',10),
  ('supply_anchor','free issue','en',10),
  ('supply_anchor','free issued','en',10),
  ('supply_anchor','free-issue','en',10),
  ('supply_anchor','توريد','ar',10),
  ('supply_anchor','توفير','ar',10),
  ('supply_anchor','تزويد','ar',10),
  ('supply_anchor','يورد','ar',10),
  ('supply_anchor','يوفر','ar',10),
  ('supply_anchor','يزود','ar',10),
  ('supply_anchor','سيورد','ar',10),
  ('supply_anchor','سيوفر','ar',10)
on conflict (marker_type, pattern, lang) do nothing;

-- ---------------------------------------------------------------- deterministic client-supply forms
-- The semantic rule below does the work. These remain as fixed markers because they are complete
-- statements on their own and must classify even in a clause with no separate supply component.
insert into public.scope_marker (marker_type, disposition, pattern, lang, priority) values
  ('disposition','client_supplied','supply by client','en',10),
  ('disposition','client_supplied','supply by the client','en',10),
  ('disposition','client_supplied','supplied by the owner','en',10),
  ('disposition','client_supplied','supplied by the employer','en',10),
  ('disposition','client_supplied','supplied by the customer','en',10),
  ('disposition','client_supplied','client to supply','en',10),
  ('disposition','client_supplied','client will supply','en',10),
  ('disposition','client_supplied','client shall supply','en',10),
  ('disposition','client_supplied','client to provide','en',10),
  ('disposition','client_supplied','client will provide','en',10),
  ('disposition','client_supplied','owner to supply','en',10),
  ('disposition','client_supplied','employer to supply','en',10),
  ('disposition','client_supplied','customer to supply','en',10),
  ('disposition','client_supplied','free issue by the employer','en',10),
  ('disposition','client_supplied','free issue by the client','en',10),
  ('disposition','client_supplied','free issued by the client','en',10),
  ('disposition','client_supplied','free issue material','en',10),
  ('disposition','client_supplied','employer supplied','en',10),
  ('disposition','client_supplied','customer supplied','en',10),
  ('disposition','client_supplied','توريد صاحب العمل','ar',10),
  ('disposition','client_supplied','توريد الزبون','ar',10),
  ('disposition','client_supplied','يوفرها العميل','ar',10),
  ('disposition','client_supplied','يوردها المالك','ar',10),
  ('disposition','client_supplied','العميل يورد','ar',10),
  ('disposition','client_supplied','العميل يوفر','ar',10),
  ('disposition','client_supplied','من توريد العميل','ar',10),
  ('disposition','client_supplied','توريد من العميل','ar',10)
on conflict (marker_type, pattern, lang) do nothing;

-- ---------------------------------------------------------------- source evidence
-- A composed classification is only defensible if it says what it composed. Without these columns
-- "by_others" and "excluded" look identical in the record and the next reviewer cannot tell
-- whether a party was found or assumed.
alter table public.inquiry_scope_disposition
  add column if not exists classification_basis text,
  add column if not exists responsible_party    text,
  add column if not exists party_class          text,
  add column if not exists party_role           text,
  add column if not exists party_clause_index   integer,
  add column if not exists sentence_index       integer;

comment on column public.inquiry_scope_disposition.classification_basis is
  'Which rule produced this disposition: fixed_marker, removal_unattributed, removal_attributed, excluded_upgraded_to_by_others, supply_attributed_counterparty, umbrella_default or clause_default.';
comment on column public.inquiry_scope_disposition.responsible_party is
  'The party term that was actually found in the text, or null when none was. Null with disposition=excluded is the evidence that nobody was named.';
comment on column public.inquiry_scope_disposition.party_role is
  'attributed (bound by a connector: "by the client"), subject ("the client will supply"), idafa (Arabic genitive: "توريد العميل") or inline_marker (the party is part of the disposition phrase itself).';
comment on column public.inquiry_scope_disposition.party_clause_index is
  'The clause the party was found in. Party detection is clause-scoped: a party named in a neighbouring clause is deliberately NOT borrowed, because "fire alarm not required, CCTV by the client" attributes nothing about the fire alarm. Excluded and by_others have identical dispatch consequences, so the conservative reading costs reporting granularity and never a wrong dispatch.';
comment on column public.inquiry_scope_disposition.sentence_index is
  'The sentence the clause came from. Recorded so that a reviewer can see the boundary each rule respected.'
;