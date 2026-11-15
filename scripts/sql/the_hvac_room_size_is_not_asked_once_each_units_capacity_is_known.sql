-- THE HVAC ROOM SIZE IS NOT ASKED ONCE EACH UNIT'S CAPACITY IS KNOWN, AND IT IS ASKED ONCE, NOT TWICE.
--
-- Subject: category_specs.fields of `hvac`, the field application_area. Owner seat: sales_engineer. Written 15 Nov 2026.
--
-- MEASURED: journey A of 15 Nov 2026 (live, models on, tag 8288bec3). A customer replacing four wall splits and servicing three
-- ducted units gave every unit's capacity ("two of 1.5 TR and two of 2.0 TR ... the three ducted units are 3 TR each") and was
-- still asked the room sizes six times. Two specs ask the same thing: this field ("What is the space used for, and roughly how
-- big is it?", required) and the placed trade's blocking spec spec_room_use_and_area_or_heat_load_calc (knowledge/packs/hvac.json,
-- "room use and area or heat-load calc"), so the chat asked it under each key.
--
-- WHAT IT WRITES. Two attributes inside the application_area field object, read by inquiry_intake (interview.ts SpecField):
--   not_needed_when {answered: ["spec_cooling_capacity"], text}: once the pack's cooling capacity per unit holds an answer, or the
--     model judges the condition in `text` holds (citing the customer), the field is recorded as "Not needed for this job: <text>"
--     and never asked; dispatch's required check reads it as answered and a supplier reads why;
--   same_as "spec_room_use_and_area_or_heat_load_calc": asked once, as the trade's spec, and answered by its answer.
-- And on system_type ("What kind of air conditioning — wall split units, hidden ducted, ...?"), the same question as the pack's blocking
-- spec_unit_type ("unit type (wall split / ducted / cassette / floor)"): same_as "spec_unit_type" (review of 15 Nov 2026, item 4: a
-- held request listed both).
-- `key`, `question`, `required` and `options` are NOT touched (`key` is what fn_rfq_required_check scores). The pack's own guide
-- row carries the same condition (knowledge/packs/hvac.json; written to trade_spec_checklist.spec_guide by
-- scripts/kb/load_trade_spec_checklists.mjs --apply).
--
-- THE GUARD is a property: afterwards the hvac row has exactly one application_area field and it carries both attributes, and
-- the number of fields is unchanged. If the field was renamed or removed since 15 Nov, the guard raises and the update rolls back
-- (scripts/apply_sql.mjs sends the file as one transaction). Proved LOCAL on 15 Nov 2026 (Postgres 16, a stand-in category_specs
-- holding production's hvac row): applied, re-applied unchanged, other categories untouched, and the guard raised on a removed field.
-- Idempotent: re-running writes the same values. Data only: no routine, table or grant.

update public.category_specs cs
   set fields = (
     select jsonb_agg(case when f->>'key' = 'application_area'
                           then f || jsonb_build_object(
                                  'not_needed_when', jsonb_build_object(
                                    'answered', jsonb_build_array('spec_cooling_capacity'),
                                    'text', 'each unit''s cooling capacity is stated (BTU/h, TR or kW)'),
                                  'same_as', 'spec_room_use_and_area_or_heat_load_calc')
                           when f->>'key' = 'system_type'
                           then f || jsonb_build_object('same_as', 'spec_unit_type')
                           else f end order by o)
       from jsonb_array_elements(cs.fields) with ordinality as e(f, o))
 where cs.category = 'hvac';

do $guard$
declare n_fields int; n_marked int; n_unit int;
begin
  select jsonb_array_length(fields),
         (select count(*) from jsonb_array_elements(fields) f
           where f->>'key' = 'application_area'
             and f->'not_needed_when'->'answered' ? 'spec_cooling_capacity'
             and coalesce(f->'not_needed_when'->>'text', '') <> ''
             and f->>'same_as' = 'spec_room_use_and_area_or_heat_load_calc')
         ,(select count(*) from jsonb_array_elements(fields) f where f->>'key' = 'system_type' and f->>'same_as' = 'spec_unit_type')
    into n_fields, n_marked, n_unit
    from public.category_specs where category = 'hvac';
  if n_marked is distinct from 1 then
    raise exception 'hvac application_area: expected one field with not_needed_when and same_as, found %', coalesce(n_marked, 0);
  end if;
  if n_unit is distinct from 1 then
    raise exception 'hvac system_type: expected one field with same_as spec_unit_type, found %', coalesce(n_unit, 0);
  end if;
  if n_fields is distinct from 10 then
    raise exception 'hvac fields: expected the 10 read on 15 Nov 2026, found % (the row changed; review before re-running)', n_fields;
  end if;
end
$guard$;
