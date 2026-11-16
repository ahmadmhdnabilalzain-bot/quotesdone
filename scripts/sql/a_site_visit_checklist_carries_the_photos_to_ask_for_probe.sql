-- PROBE (pure, no DDL, aborted transaction) for a_site_visit_checklist_carries_the_photos_to_ask_for.sql.
-- Seat: sales_engineer. 15 Nov 2026.
-- Run LOCALLY after the definition (or with it), rolled back. It always ends in raise exception 'CHK<<json>>', so every row it
-- writes rolls back. Its row belongs to a trade code no taxonomy holds (zz_demo_probe_trade) and names no person; nothing here
-- sends, queues or hands anything off. The real rows are counted (and hashed) before and after and must not move.
--   a  a row in the loader's shape with photos_to_ask is accepted and read back whole
--   b  photos_to_ask that is not an array, or longer than six, or set without a site-visit sentence, is refused
--   c  the existing rows take the default [] (no photo is asked until the loader runs)
--   d  the table stays closed: RLS on, anon and authenticated cannot read it
do $$
declare fail text := ''; v_before int; v_after int; h_before text; h_after text; r record; v_defaults int; v_all int;
  t text := 'zz_demo_probe_trade';
  v_specs jsonb := '[{"code":"spec_unit_type","label_en":"unit type"}]';
  v_photos jsonb := '[{"shot":"Each indoor unit, from the front","shot_ar":"كل وحدة داخلية، من الأمام","from":"replacements"},{"shot":"Where the water from the unit drains","shot_ar":"مكان تصريف المياه من الوحدة","from":"drainage"}]';
begin
  select count(*), md5(coalesce(string_agg(trade_code || topic_id || specs::text || photos_to_ask::text, '|' order by trade_code, topic_id), ''))
    into v_before, h_before from public.trade_spec_checklist where trade_code <> t;
  select count(*) filter (where photos_to_ask = '[]'::jsonb), count(*) into v_defaults, v_all from public.trade_spec_checklist where trade_code <> t;
  insert into public.trade_spec_checklist (trade_code, topic_id, topic, specs, site_visit_required_when, photos_to_ask, source_pack)
  values (t, t || ':spec-split-ac', 'ZZ DEMO probe checklist', v_specs, 'ZZ DEMO a site visit is needed for replacements to check drainage', v_photos, 'zz_demo_probe.json');
  select * into r from public.trade_spec_checklist where trade_code = t;
  if jsonb_array_length(r.photos_to_ask) <> 2 or r.photos_to_ask->0->>'from' <> 'replacements' or r.photos_to_ask->1->>'shot_ar' <> 'مكان تصريف المياه من الوحدة'
    then fail := fail || 'the photos did not read back whole; '; end if;
  begin
    update public.trade_spec_checklist set photos_to_ask = '{"shot":"x"}'::jsonb where trade_code = t;
    fail := fail || 'photos_to_ask that is not an array was accepted; ';
  exception when check_violation then null; end;
  begin
    update public.trade_spec_checklist set photos_to_ask = (select jsonb_agg(jsonb_build_object('shot', 'zz ' || g, 'from', 'drainage')) from generate_series(1, 7) g) where trade_code = t;
    fail := fail || 'seven photos were accepted; ';
  exception when check_violation then null; end;
  begin
    update public.trade_spec_checklist set site_visit_required_when = null where trade_code = t;
    fail := fail || 'photos without a site-visit sentence were accepted; ';
  exception when check_violation then null; end;
  if v_defaults <> v_all then fail := fail || 'an existing row does not carry the default []; '; end if;
  if not (select relrowsecurity from pg_class where oid = 'public.trade_spec_checklist'::regclass) then fail := fail || 'RLS is off; '; end if;
  if has_table_privilege('anon', 'public.trade_spec_checklist', 'select') or has_table_privilege('authenticated', 'public.trade_spec_checklist', 'select')
    then fail := fail || 'the table is readable by anon or authenticated; '; end if;
  delete from public.trade_spec_checklist where trade_code = t;
  select count(*), md5(coalesce(string_agg(trade_code || topic_id || specs::text || photos_to_ask::text, '|' order by trade_code, topic_id), ''))
    into v_after, h_after from public.trade_spec_checklist where trade_code <> t;
  if v_after <> v_before or h_after <> h_before then fail := fail || 'real rows moved; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'real_rows', v_before, 'real_rows_after', v_after, 'real_rows_with_default', v_defaults);
end $$;
