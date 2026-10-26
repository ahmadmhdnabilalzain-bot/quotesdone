-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802165657   name: p2_c1_stage_a_mep_trades_and_field_identities
-- SHA-256 of the applied SQL: 4292c43f11d1321d2817ce171c3744509c018de8c4127d2ed86abb737c01f129
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE A part 3 - the trades, and the field identities, DERIVED from the corpus.
--
-- Sharedness is not asserted here, it is tested. A candidate shared field is promoted to `shared`
-- only if every subcategory that asks for it asks the SAME question with the SAME answer type.
-- Anything that varies is forced trade-specific and flagged for founder review. This is the six-
-- condition rule from the approved amendment, mechanised: the cost of wrongly sharing is a wrong
-- dispatch, the cost of wrongly splitting is one extra question, so the test fails closed.

insert into public.mep_trade (trade_key, label_en, label_ar, sort_order) values
  ('hvac',      'HVAC',                     'التكييف والتهوية',       1),
  ('electrical','Electrical',               'الكهرباء',               2),
  ('plumbing',  'Plumbing & Sanitaryware',  'السباكة والأدوات الصحية', 3),
  ('fire',      'Fire & Life Safety',       'الحريق والسلامة',        4),
  ('elv',       'ELV & Security',           'التيار الخفيف والأمن',    5)
on conflict (trade_key) do nothing;

insert into public.mep_trade_route (trade_key, catalog_num, is_primary) values
  ('hvac', 9, true), ('electrical', 10, true), ('plumbing', 11, true),
  ('fire', 12, true), ('fire', 13, false), ('elv', 14, true)
on conflict (trade_key, catalog_num) do nothing;

create temporary table _cand (source_key text primary key, canonical text, forced_trade_specific boolean, note text) on commit drop;
insert into _cand values
  ('project_emirate',          'project_emirate',          false, null),
  ('project_stage',            'project_stage',            false, null),
  ('project_type',             'project_type',             false, null),
  ('site_location',            'site_location',            false, null),
  ('required_completion_date', 'required_completion_date', false, null),
  ('required_date',            'required_completion_date', false, null),
  ('authority_or_developer',   'authority_or_developer',   false, null),
  ('governing_documents',      'governing_documents',      false, null),
  ('site_access_constraints',  'site_access_constraints',  false, null),
  ('environmental_conditions', 'environmental_conditions', false, null),
  ('utilities_available',      'utilities_available',      false, null),
  ('brand_policy',             'brand_policy',             false, null),
  ('quantity_and_unit',        'quantity_and_unit',        true,  'Two answer types in the corpus (quantity_with_unit vs structured_number) and units differ by trade. Fails the identical-unit and identical-validation conditions on evidence.'),
  ('scope_mode',               'scope_mode',               true,  'QUESTION FOR FOUNDER. Two question texts ("required scope" vs "required commercial scope"). Split defensively: a shared supply-only answer satisfying an install-inclusive trade is a wrong dispatch.'),
  ('existing_system_interface','existing_system_interface',true,  'Interfaces are per trade. Route 8 and routes 12/13/14 also word this differently and are NOT merged.'),
  ('existing_system',          'existing_system',          true,  'As above; deliberately a separate identity from existing_system_interface because the question texts differ.'),
  ('testing_commissioning',    'testing_commissioning',    true,  'Testing and commissioning regimes differ by authority (DEWA vs Civil Defence vs water authority).'),
  ('warranty_maintenance',     'warranty_maintenance',     true,  'QUESTION FOR FOUNDER. Warranty terms differ by equipment class; split defensively.'),
  ('design_responsibility',    'design_responsibility',    true,  'QUESTION FOR FOUNDER. Design and calculation responsibility is usually per package, not per project.'),
  ('finish_colour',            'finish_colour',            true,  'Three different question texts, and mandatory in some subcategories and optional in others. Applicability differs, so it cannot be shared.'),
  ('installation_environment', 'installation_environment', true,  'Two distinct meanings in the corpus (buried/concealed/shaft location vs installation exposure) and two answer types. Explicitly NOT merged with environmental_conditions, which asks about ambient climate.');

create temporary table _src on commit drop as
select distinct m.subcategory_slug,
       case m.catalog_num when 9 then 'hvac' when 10 then 'electrical' when 11 then 'plumbing'
            when 12 then 'fire' when 13 then 'fire' when 14 then 'elv' end as trade_key,
       q.field_key, q.question_en, q.answer_type, q.unit, q.question_ar
  from public.kb_operational_route_map m
  join kb_stage.questions q on q.subcategory_slug = m.subcategory_slug
 where m.catalog_num in (9,10,11,12,13,14) and q.field_key is not null;

create temporary table _verdict on commit drop as
select c.canonical,
       bool_and(not c.forced_trade_specific) as allowed,
       count(distinct s.question_en)  as distinct_texts,
       count(distinct s.answer_type)  as distinct_types,
       (count(distinct s.question_en) = 1 and count(distinct s.answer_type) = 1) as consistent,
       min(s.question_en) as label_en, min(s.question_ar) as label_ar,
       min(s.answer_type) as answer_type, min(s.unit) as unit,
       string_agg(distinct c.note, ' ') as note
  from _cand c join _src s on s.field_key = c.source_key
 group by c.canonical;

insert into public.field_definition
  (field_id, scope, trade_key, label_en, label_ar, unit, answer_type,
   evidence_rule, review_status, review_note)
select 'shared.' || v.canonical, 'shared', null, v.label_en, v.label_ar, v.unit, v.answer_type,
       'Shared across every trade in the group: one answer, referenced, never copied.',
       'approved',
       'Promoted to shared by test: ' || v.distinct_texts || ' distinct question text(s), '
         || v.distinct_types || ' distinct answer type(s) across the corpus.'
  from _verdict v where v.allowed and v.consistent
on conflict (field_id) do nothing;

insert into public.field_definition
  (field_id, scope, trade_key, label_en, label_ar, unit, answer_type,
   evidence_rule, review_status, review_note)
select distinct s.trade_key || '.' || coalesce(c.canonical, s.field_key), 'trade_specific', s.trade_key,
       first_value(s.question_en) over w, first_value(s.question_ar) over w,
       first_value(s.unit) over w, first_value(s.answer_type) over w,
       'Trade-specific: this identity may only satisfy the ' || s.trade_key || ' workstream.',
       case when coalesce(v.note,'') ilike 'QUESTION FOR FOUNDER%' then 'question_for_founder' else 'approved' end,
       v.note
  from _src s
  left join _cand c on c.source_key = s.field_key
  left join _verdict v on v.canonical = c.canonical
 where c.source_key is null or c.forced_trade_specific or not v.consistent
window w as (partition by s.trade_key, coalesce(c.canonical, s.field_key) order by s.subcategory_slug)
on conflict (field_id) do nothing;

insert into public.field_definition_source (subcategory_slug, source_field_key, field_id)
select s.subcategory_slug, s.field_key,
       case when c.source_key is not null and not c.forced_trade_specific and v.consistent
            then 'shared.' || c.canonical
            else s.trade_key || '.' || coalesce(c.canonical, s.field_key) end
  from _src s
  left join _cand c on c.source_key = s.field_key
  left join _verdict v on v.canonical = c.canonical
on conflict (subcategory_slug, source_field_key) do nothing;
;