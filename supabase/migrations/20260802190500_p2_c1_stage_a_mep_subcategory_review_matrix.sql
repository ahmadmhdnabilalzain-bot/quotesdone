-- P2-C1 STAGE A - the eleven-subcategory review matrix required before Stage B.
-- Applied as migration 20260802170530 p2_c1_stage_a_mep_subcategory_review_matrix.
--
-- Primary trade is DERIVED: each of route 8's eleven subcategories belongs to exactly one of
-- routes 9/10/11, verified - zero subcategories map to two trades. Secondary applicability is
-- never automatic: it is a named question with a named reason, and it stays unapproved until the
-- founder answers it.

create table if not exists public.mep_subcategory_review (
  subcategory_slug     text primary key,
  subcategory_number   integer,
  name_en              text not null,
  primary_trade        text not null references public.mep_trade(trade_key),
  primary_source       text not null,
  secondary_trades     text[] not null default '{}',
  secondary_status     text not null default 'none'
                         check (secondary_status in ('none','question_for_founder','approved')),
  secondary_rationale  text,
  mandatory_questions  integer,
  optional_questions   integer,
  shared_identities    integer,
  technical_identities integer,
  shared_mandatory     integer,
  technical_mandatory  integer,
  authorities_named    text[],
  question_ownership   text not null,
  review_status        text not null default 'question_for_founder'
                         check (review_status in ('approved','question_for_founder')),
  rationale            text,
  updated_at           timestamptz not null default now()
);
alter table public.mep_subcategory_review enable row level security;

comment on table public.mep_subcategory_review is
  'P2-C1 Stage A deliverable. MEP owns shared project fields only; it does not own duplicated child-trade technical fields. Every row starts as a question for the founder - nothing here promotes itself to approved.';

insert into public.mep_subcategory_review
  (subcategory_slug, subcategory_number, name_en, primary_trade, primary_source,
   mandatory_questions, optional_questions, shared_identities, technical_identities,
   shared_mandatory, technical_mandatory, authorities_named, question_ownership, rationale)
select m.subcategory_slug, s.subcategory_number, s.name_en,
       case m2.catalog_num when 9 then 'hvac' when 10 then 'electrical' when 11 then 'plumbing' end,
       'derived from kb_operational_route_map: this subcategory maps to route ' || m2.catalog_num
         || ' and to no other trade route',
       count(*) filter (where q.mandatory),
       count(*) filter (where not q.mandatory),
       count(distinct fs.field_id) filter (where fs.field_id like 'shared.%'),
       count(distinct fs.field_id) filter (where fs.field_id not like 'shared.%'),
       count(distinct fs.field_id) filter (where q.mandatory and fs.field_id like 'shared.%'),
       count(distinct fs.field_id) filter (where q.mandatory and fs.field_id not like 'shared.%'),
       (select array_agg(distinct x.auth order by x.auth)
          from kb_stage.questions q2
          cross join lateral (select unnest(array['DEWA','SEWA','DCD','Civil Defence','DoE','du']) auth) x
         where q2.subcategory_slug = m.subcategory_slug and q2.payload::text ilike '%'||x.auth||'%'),
       'MEP (route 8) owns the shared project fields only. Every technical field on this row is '
         || 'owned by the ' || case m2.catalog_num when 9 then 'HVAC' when 10 then 'electrical' when 11 then 'plumbing' end
         || ' workstream and may not satisfy any other trade.',
       'Primary trade is unambiguous in the data. Question counts are the raw corpus rows; the '
         || 'identity columns are what the customer is actually asked after shared fields collapse to one.'
  from public.kb_operational_route_map m
  join kb_stage.subcategories s on s.subcategory_slug = m.subcategory_slug
  join public.kb_operational_route_map m2
    on m2.subcategory_slug = m.subcategory_slug and m2.catalog_num in (9,10,11)
  join kb_stage.questions q on q.subcategory_slug = m.subcategory_slug
  left join public.field_definition_source fs
    on fs.subcategory_slug = q.subcategory_slug and fs.source_field_key = q.field_key
 where m.catalog_num = 8
 group by m.subcategory_slug, s.subcategory_number, s.name_en, m2.catalog_num
on conflict (subcategory_slug) do nothing;

-- Secondary applicability: named, reasoned, and NOT approved by this session.
update public.mep_subcategory_review set
  secondary_trades = v.trades, secondary_status = 'question_for_founder', secondary_rationale = v.why
from (values
  ('ducting-grilles-diffusers-and-accessories', array['fire'],
   'Fire and smoke dampers sit in the duct but are certified under Civil Defence. Does the damper question belong to HVAC or to fire?'),
  ('pipes-and-fittings-all-types', array['fire'],
   'Sprinkler pipework is pipework, but route 12 owns fire-pumps-sprinklers-valves-and-fittings. Overlap must be decided, not inherited.'),
  ('electrical-cables-wiring-and-accessories', array['fire','elv'],
   'Fire-rated cable and ELV containment are electrical products with fire and ELV acceptance criteria.'),
  ('generators-ups-and-power-systems', array['fire'],
   'Life-safety power supply to fire systems is a Civil Defence requirement, not just an electrical one.'),
  ('lighting-general-emergency-and-architectural', array['fire'],
   'Emergency lighting and exit signage is a separate subcategory under routes 12 and 13. The same product is described in two places; one owner must be chosen.'),
  ('switchgear-panels-and-distribution-boards', array['fire'],
   'Fireman switch and life-safety circuit segregation are switchgear features with a fire acceptance path.')
) as v(slug, trades, why)
where mep_subcategory_review.subcategory_slug = v.slug;
