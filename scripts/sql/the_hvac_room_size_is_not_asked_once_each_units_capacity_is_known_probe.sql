-- PROBE for the_hvac_room_size_is_not_asked_once_each_units_capacity_is_known.sql (sales_engineer, 15 Nov 2026).
-- A pure probe: it always raises CHK<<...>>, so nothing it reads or writes is kept. It reads only category_specs.
-- After the file is applied (or with it, in the same rolled-back transaction), the hvac row must hold, on application_area,
-- not_needed_when {answered: [spec_cooling_capacity], text} and same_as spec_room_use_and_area_or_heat_load_calc, and on
-- system_type same_as spec_unit_type; the field count must still be 10, every field must keep its key, required flag and
-- options, and no other category may carry either attribute.
do $probe$
declare
  f jsonb; v_bad text := ''; n int; n_other int;
begin
  select fields into f from public.category_specs where category = 'hvac';
  if f is null then raise exception 'CHK<<PROBE FAILED: no hvac row>>'; end if;
  if jsonb_array_length(f) <> 10 then v_bad := v_bad || ' fields=' || jsonb_array_length(f); end if;
  select count(*) into n from jsonb_array_elements(f) x
   where x->>'key' = 'application_area' and x->'not_needed_when'->'answered' = '["spec_cooling_capacity"]'::jsonb
     and x->'not_needed_when'->>'text' = 'each unit''s cooling capacity is stated (BTU/h, TR or kW)'
     and x->>'same_as' = 'spec_room_use_and_area_or_heat_load_calc' and (x->>'required')::boolean;
  if n <> 1 then v_bad := v_bad || ' application_area'; end if;
  select count(*) into n from jsonb_array_elements(f) x where x->>'key' = 'system_type' and x->>'same_as' = 'spec_unit_type' and (x->>'required')::boolean
     and jsonb_array_length(x->'options') = 8;
  if n <> 1 then v_bad := v_bad || ' system_type'; end if;
  select count(*) into n from jsonb_array_elements(f) x where coalesce(x->>'key', '') = '';
  if n <> 0 then v_bad := v_bad || ' keyless=' || n; end if;
  select count(*) into n_other from public.category_specs c, jsonb_array_elements(c.fields) x
   where c.category <> 'hvac' and (x ? 'not_needed_when' or x ? 'same_as');
  if n_other <> 0 then v_bad := v_bad || ' other_categories=' || n_other; end if;
  if v_bad = '' then raise exception 'CHK<<PROBE OK: hvac application_area and system_type carry their attributes; 10 fields; no other category touched>>';
  else raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
end $probe$;
