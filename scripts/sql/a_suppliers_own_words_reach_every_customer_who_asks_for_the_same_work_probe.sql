-- PROBE (pure, no DDL, aborted transaction) for a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work.sql.
-- Seat: sales_engineer. 10 Nov 2026, founder ledger 1573 / 1579 / 1586.
-- Run AFTER the definition, or with it, rolled back (scripts/ci/rehearse_sql.mjs <file> <this probe>). It always ends in
-- raise exception 'CHK<<json>>', so every row it writes rolls back. session_replication_role = replica stops every trigger
-- for this transaction only, so nothing it writes queues a message or a notice.
--
-- ITS SUBJECTS CANNOT REACH A PERSON: two matchable demo suppliers at @example.invalid that scripts/lib/demo_factory.mjs
-- built, named 'ZZ DEMO ...' (makeSupplier) or 'QD Demo ...' (the bulk corpus, --corpus; 10 Nov 2026 the #1880 apply
-- stopped here with only one ZZ DEMO left while 25 QD Demo corpus suppliers stood ready)
-- built (it creates no supplier: an approved one needs the founder's mandatory six); their capability rows are rewritten here
-- and roll back. No inquiry is created, nothing is matched into inquiry_matches, nothing is queued or sent. Every other
-- supplier's capability and every lead are counted before and after and must not move.
--
-- THE MATRIX is supabase/functions/_shared/general_matching.fixtures.json, projected below (the check
-- a_suppliers_own_words_reach_every_customer_in_every_trade.test.mjs holds the two equal). For each of its 44 rows, in all
-- 12 taxonomy groups: supplier A holds what the code path read from his own words (sk, his trade st), supplier B is the
-- row's control from another group, and fn_match_capability is asked with the customer's taxonomy code (ct, never an
-- intake slug) and the keys read from the customer's words (ck). A must be matched, B never.
-- A holds the mandatory authority approvals of his trades (the gate is real and stays); B holds none.
--   then the confusables (a neighbour that must stay out, or an adjacent/implied firm that must come in),
--   the request that names NO service (the gate is exactly its trades: an adjacent supplier is not reached),
--   the similarity weight at 1000 changes no set (ranking only),
--   the alias loop (propose, seen again, approve, refuse a name of another service, reject),
--   the curated seed and the adjacency rows are in place, and the new routines and tables are closed to anon.
do $probe$
declare
  mx jsonb := $mx${"rows":[
 {"f":"wall_panels","st":"wallpaper","sk":["wallpaper.wall_panels","wallpaper.film_wrap"],"ct":"joinery","ck":["wallpaper.wall_panels"],"control":"home_lifts"},
 {"f":"film_wrap","st":"wallpaper","sk":["wallpaper.film_wrap"],"ct":"interior_fitout","ck":["wallpaper.film_wrap"],"control":"home_lifts"},
 {"f":"aluminium_windows","st":"aluminium","sk":["aluminium.windows_doors"],"ct":"aluminium","ck":["aluminium.windows_doors"],"control":"solar"},
 {"f":"shower_glass","st":"glazing","sk":["glazing.partitions"],"ct":"glazing","ck":["glazing.partitions"],"control":"fire_alarm"},
 {"f":"false_ceiling","st":"gypsum","sk":["gypsum.false_ceiling"],"ct":"interior_fitout","ck":["gypsum.false_ceiling"],"control":"generator_rental"},
 {"f":"interior_painting","st":"painting","sk":["painting.interior"],"ct":"painting","ck":["painting.interior"],"control":"ro_plant"},
 {"f":"epoxy","st":"flooring","sk":["flooring.epoxy"],"ct":"flooring","ck":["flooring.epoxy"],"control":"patient_monitors"},
 {"f":"roof_waterproofing","st":"waterproofing","sk":["waterproofing.roof"],"ct":"waterproofing","ck":["waterproofing.roof"],"control":"fall_protection"},
 {"f":"ac_maintenance","st":"hvac","sk":["hvac.maintenance_amc"],"ct":"hvac","ck":["hvac.maintenance_amc"],"control":"forklifts"},
 {"f":"leak_repair","st":"plumbing","sk":["plumbing.maintenance"],"ct":"plumbing","ck":["plumbing.maintenance"],"control":"laser_cutting"},
 {"f":"lighting","st":"electrical","sk":["electrical.lighting"],"ct":"electrical","ck":["electrical.lighting"],"control":"catalogues"},
 {"f":"kitchens","st":"joinery","sk":["joinery.kitchens"],"ct":"joinery","ck":["joinery.kitchens"],"control":"exhibition_stands"},
 {"f":"blinds","st":"curtains_blinds","sk":["curtains_blinds.roller_blinds"],"ct":"curtains_blinds","ck":["curtains_blinds.roller_blinds"],"control":"cartons"},
 {"f":"sofa","st":"upholstery","sk":["upholstery.sofa"],"ct":"upholstery","ck":["upholstery.sofa"],"control":"labels"},
 {"f":"irrigation","st":"landscaping","sk":["landscaping.irrigation"],"ct":"landscaping","ck":["landscaping.irrigation"],"control":"topo_survey"},
 {"f":"pool_maintenance","st":"swimming_pools","sk":["swimming_pools.pool_maintenance"],"ct":"swimming_pools","ck":["swimming_pools.pool_maintenance"],"control":"legal_translation"},
 {"f":"termites","st":"pest_control","sk":["pest_control.termite_treatment"],"ct":"pest_control","ck":["pest_control.termite_treatment"],"control":"networking"},
 {"f":"deep_cleaning","st":"cleaning","sk":["cleaning.deep_cleaning"],"ct":"cleaning","ck":["cleaning.deep_cleaning"],"control":"pos"},
 {"f":"cctv","st":"security_systems","sk":["security_systems.cctv"],"ct":"security_systems","ck":["security_systems.cctv"],"control":"labour_transport"},
 {"f":"shop_signs","st":"signage","sk":["signage.shop_signs"],"ct":"signage","ck":["signage.shop_signs"],"control":"car_leasing"},
 {"f":"worktops","st":"marble_stone","sk":["marble_stone.worktops_vanities"],"ct":"marble_stone","ck":["marble_stone.worktops_vanities"],"control":"ac_maintenance"},
 {"f":"steel_structure","st":"steel","sk":["steel.structural_steel"],"ct":"steel","ck":["steel.structural_steel"],"control":"ac_maintenance"},
 {"f":"car_park_shades","st":"tents_shades","sk":["tents_shades.car_park_shades"],"ct":"tents_shades","ck":["tents_shades.car_park_shades"],"control":"ac_maintenance"},
 {"f":"home_lifts","st":"elevators","sk":["elevators.home_lifts"],"ct":"elevators","ck":["elevators.home_lifts"],"control":"film_wrap"},
 {"f":"solar","st":"solar","sk":["solar.pv_install"],"ct":"solar","ck":["solar.pv_install"],"control":"aluminium_windows"},
 {"f":"fire_alarm","st":"fire_fighting","sk":["fire_fighting.fire_alarm"],"ct":"fire_fighting","ck":["fire_fighting.fire_alarm"],"control":"shower_glass"},
 {"f":"generator_rental","st":"power_generators","sk":["power_generators.generator_rental"],"ct":"event_equipment_rental","ck":["power_generators.generator_rental"],"control":"false_ceiling"},
 {"f":"ro_plant","st":"water_treatment","sk":["water_treatment.ro_plants"],"ct":"water_treatment","ck":["water_treatment.ro_plants"],"control":"interior_painting"},
 {"f":"patient_monitors","st":"medical_equipment","sk":["medical_equipment.patient_monitors"],"ct":"medical_equipment","ck":["medical_equipment.patient_monitors"],"control":"epoxy"},
 {"f":"fall_protection","st":"safety_equipment","sk":["safety_equipment.fall_protection"],"ct":"safety_equipment","ck":["safety_equipment.fall_protection"],"control":"roof_waterproofing"},
 {"f":"forklifts","st":"material_handling","sk":["material_handling.forklifts_sale_rent"],"ct":"material_handling","ck":["material_handling.forklifts_sale_rent"],"control":"ac_maintenance"},
 {"f":"laser_cutting","st":"cnc_machining","sk":["cnc_machining.laser_waterjet_cutting"],"ct":"cnc_machining","ck":["cnc_machining.laser_waterjet_cutting"],"control":"leak_repair"},
 {"f":"catalogues","st":"commercial_printing","sk":["commercial_printing.brochures_catalogues"],"ct":"commercial_printing","ck":["commercial_printing.brochures_catalogues"],"control":"lighting"},
 {"f":"exhibition_stands","st":"exhibition_stands","sk":["exhibition_stands.custom_stands"],"ct":"event_management","ck":["exhibition_stands.custom_stands"],"control":"kitchens"},
 {"f":"cartons","st":"corrugated_packaging","sk":["corrugated_packaging.regular_slotted_cartons"],"ct":"corrugated_packaging","ck":["corrugated_packaging.regular_slotted_cartons"],"control":"blinds"},
 {"f":"labels","st":"labels_sleeves","sk":["labels_sleeves.self_adhesive_labels"],"ct":"labels_sleeves","ck":["labels_sleeves.self_adhesive_labels"],"control":"sofa"},
 {"f":"topo_survey","st":"land_survey","sk":["land_survey.topographic_survey"],"ct":"land_survey","ck":["land_survey.topographic_survey"],"control":"irrigation"},
 {"f":"legal_translation","st":"translation_interpretation","sk":["translation_interpretation.certified_legal_translation"],"ct":"translation_interpretation","ck":["translation_interpretation.certified_legal_translation"],"control":"pool_maintenance"},
 {"f":"networking","st":"it_services","sk":["it_services.network_install"],"ct":"it_services","ck":["it_services.network_install"],"control":"termites"},
 {"f":"pos","st":"pos_retail","sk":["pos_retail.pos_terminals"],"ct":"pos_retail","ck":["pos_retail.pos_terminals"],"control":"deep_cleaning"},
 {"f":"labour_transport","st":"staff_transport","sk":["staff_transport.labour_transport"],"ct":"staff_transport","ck":["staff_transport.labour_transport"],"control":"cctv"},
 {"f":"car_leasing","st":"vehicle_leasing","sk":["vehicle_leasing.long_term_leasing"],"ct":"vehicle_leasing","ck":["vehicle_leasing.long_term_leasing"],"control":"shop_signs"},
 {"f":"scaffolding","st":"scaffolding","sk":["scaffolding.rental"],"ct":"scaffolding","ck":["scaffolding.rental"],"control":"home_lifts"},
 {"f":"crane_hire","st":"heavy_equipment","sk":["heavy_equipment.crane_hire"],"ct":"heavy_equipment","ck":["heavy_equipment.crane_hire"],"control":"home_lifts"}],
 "conf":[
 {"name":"vinyl flooring is not PVC wall panels","inquiry":"wall_panels","st":"flooring","sk":["flooring.parquet_vinyl"],"expect":"excluded","ct":null},
 {"name":"a label and sticker printer is not a film-wrap applicator","inquiry":"film_wrap","st":"packaging","sk":["packaging.labels"],"expect":"excluded","ct":null},
 {"name":"a pool builder in landscaping does not get weekly pool cleaning","inquiry":"pool_maintenance","st":"landscaping","sk":["landscaping.pools"],"expect":"excluded","ct":null},
 {"name":"an aluminium window maker (adjacent to glazing) does not get a shower partition","inquiry":"shower_glass","st":"aluminium","sk":["aluminium.windows_doors"],"expect":"excluded","ct":null},
 {"name":"an exterior-only painter does not get interior painting","inquiry":"interior_painting","st":"painting","sk":["painting.exterior"],"expect":"excluded","ct":null},
 {"name":"a sofa upholsterer (adjacent to curtains and blinds) does not get roller blinds","inquiry":"blinds","st":"upholstery","sk":["upholstery.sofa"],"expect":"excluded","ct":null},
 {"name":"a plant-hire firm (adjacent) without forklifts does not get a forklift rental","inquiry":"forklifts","st":"heavy_equipment","sk":["heavy_equipment.earthmoving"],"expect":"excluded","ct":null},
 {"name":"an access-platform renter (adjacent to heavy equipment) does not get a crane","inquiry":"crane_hire","st":"scaffolding","sk":["scaffolding.access_platforms"],"expect":"excluded","ct":null},
 {"name":"a law firm with no translation service (adjacent) does not get a sworn translation","inquiry":"legal_translation","st":"legal_services","sk":[],"expect":"excluded","ct":null},
 {"name":"an interior decorator is reached for PVC wall panels through adjacency and the curated implication","inquiry":"wall_panels","st":"interior_fitout","sk":["interior_fitout.decoration"],"expect":"matched","ct":null},
 {"name":"an AC installer is reached for AC servicing through the curated implication","inquiry":"ac_maintenance","st":"hvac","sk":["hvac.supply_install"],"expect":"matched","ct":null},
 {"name":"a forklift dealer is reached for a forklift request classified under heavy equipment","inquiry":"forklifts","st":"material_handling","sk":["material_handling.forklifts_sale_rent"],"expect":"matched","ct":"heavy_equipment"}]}$mx$::jsonb;
  r jsonb; c jsonb; ctl jsonb; v jsonb;
  v_a bigint; v_b bigint; f text := ''; o jsonb := '{}'::jsonb;
  v_pos int := 0; v_neg int := 0; v_conf int := 0; v_sim int := 0;
  v_set0 bigint[]; v_set1 bigint[]; v_why text; v_id bigint; v_id2 bigint;
  v_caps_before int; v_caps_after int; v_leads_before int; v_leads_after int;
  v_ids bigint[];
begin
  set local session_replication_role = replica;
  select count(*) into v_leads_before from public.leads;

  -- the two matchable ZZ DEMO suppliers the factory built (scripts/lib/demo_factory.mjs: the mandatory six, @example.invalid);
  -- their capability rows are rewritten for each row below and every change rolls back with the raise
  select array_agg(l.id order by l.id) into v_ids from (
    select l.id from public.leads l
     where l.company_name ~* '^\s*(zz|qd)\s*demo' and l.email like '%@example.invalid'
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
     order by l.id limit 2) l;
  if coalesce(cardinality(v_ids), 0) < 2 then
    raise exception 'CHK<<{"verdict":"PROBE FAILED: fewer than two matchable ZZ DEMO suppliers at @example.invalid to stand in for the matrix"}>>';
  end if;
  v_a := v_ids[1]; v_b := v_ids[2];
  select count(*) into v_caps_before from public.supplier_capabilities where supplier_id not in (v_a, v_b);
  delete from public.supplier_availability where supplier_id in (v_a, v_b);   -- "no row" = available (rolled back)
  insert into public.supplier_capabilities (supplier_id, trades, roles, services, confirmed_at, confirmed_version)
  values (v_a, '{}', array['contractor'], '{}', now(), 1), (v_b, '{}', array['contractor'], '{}', now(), 1)
  on conflict (supplier_id) do update set trades = '{}', roles = array['contractor'], services = '{}', services_removed = '{}',
    excluded_trades = '{}', coverage_emirates = '{}', min_project_value = null, max_project_value = null, confirmed_at = now();

  -- 1. THE MATRIX: every row's supplier is matched, every row's control never
  for r in select * from jsonb_array_elements(mx->'rows') loop
    select x into ctl from jsonb_array_elements(mx->'rows') x where x->>'f' = r->>'control';
    update public.supplier_capabilities set
      trades = array(select distinct t from (select r->>'st' as t union select split_part(k, '.', 1) from jsonb_array_elements_text(r->'sk') k) z order by t),
      services = array(select jsonb_array_elements_text(r->'sk'))
     where supplier_id = v_a;
    -- the trade's mandatory authority approvals (DEWA, SIRA, Civil Defence ...) are a real gate: A holds those of his trades
    update public.supplier_capabilities sc set authority_approvals = coalesce((
      select jsonb_object_agg(a, true) from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(sc.trades)), '{}'::jsonb)
     where sc.supplier_id = v_a;
    update public.supplier_capabilities set
      trades = array(select distinct t from (select ctl->>'st' as t union select split_part(k, '.', 1) from jsonb_array_elements_text(ctl->'sk') k) z order by t),
      services = array(select jsonb_array_elements_text(ctl->'sk'))
     where supplier_id = v_b;
    v_ids := array(select m.supplier_id from public.fn_match_capability(array[r->>'ct'], 'executes', p_limit := 100000,
                     p_services := array(select jsonb_array_elements_text(r->'ck'))) m where m.supplier_id in (v_a, v_b));
    if v_a = any(v_ids) then v_pos := v_pos + 1; else f := f || (r->>'f') || ': its supplier was not matched; '; end if;
    if v_b = any(v_ids) then f := f || (r->>'f') || ': the control ' || (r->>'control') || ' was matched; '; else v_neg := v_neg + 1; end if;
    if r->>'f' = 'wall_panels' then
      select m.why into v_why from public.fn_match_capability(array[r->>'ct'], 'executes', p_limit := 100000,
               p_services := array(select jsonb_array_elements_text(r->'ck'))) m where m.supplier_id = v_a;
      o := o || jsonb_build_object('pvc_why', v_why);
      -- NO SERVICE NAMED: the gate is exactly the request's trades (joinery), so the wallpaper supplier is not reached
      if exists (select 1 from public.fn_match_capability(array[r->>'ct'], 'executes', p_limit := 100000) m where m.supplier_id = v_a) then
        f := f || 'a request naming no service reached an adjacent trade; ';
      end if;
    end if;
    -- RANKING ONLY: the similarity weight at 1000 admits nobody new and drops nobody (first 8 rows)
    if v_sim < 8 then
      v_set0 := array(select m.supplier_id from public.fn_match_capability(array[r->>'ct'], 'executes', p_limit := 100000,
                        p_services := array(select jsonb_array_elements_text(r->'ck'))) m order by 1);
      update public.decision_policy set value = '1000'::jsonb where key = 'score_w_service_similarity';
      v_set1 := array(select m.supplier_id from public.fn_match_capability(array[r->>'ct'], 'executes', p_limit := 100000,
                        p_services := array(select jsonb_array_elements_text(r->'ck'))) m order by 1);
      update public.decision_policy set value = '10'::jsonb where key = 'score_w_service_similarity';
      if v_set0 is distinct from v_set1 then f := f || (r->>'f') || ': the similarity weight changed who is matched; '; end if;
      v_sim := v_sim + 1;
    end if;
  end loop;

  -- 2. THE CONFUSABLES: A is the inquiry row's own supplier (control), B the confusable
  for c in select * from jsonb_array_elements(mx->'conf') loop
    select x into r from jsonb_array_elements(mx->'rows') x where x->>'f' = c->>'inquiry';
    update public.supplier_capabilities set
      trades = array(select distinct t from (select c->>'st' as t union select split_part(k, '.', 1) from jsonb_array_elements_text(c->'sk') k) z order by t),
      services = array(select jsonb_array_elements_text(c->'sk'))
     where supplier_id = v_b;
    v_ids := array(select m.supplier_id from public.fn_match_capability(array[coalesce(c->>'ct', r->>'ct')], 'executes', p_limit := 100000,
                     p_services := array(select jsonb_array_elements_text(r->'ck'))) m where m.supplier_id = v_b);
    if (c->>'expect' = 'matched') = (v_b = any(v_ids)) then v_conf := v_conf + 1;
    else f := f || (c->>'name') || ' (expected ' || (c->>'expect') || '); '; end if;
  end loop;

  -- 3. THE ALIAS LOOP
  -- 12 Nov 2026 (a_demo_supplier_never_feeds_the_alias_queue.sql): v_a and v_b are ZZ DEMO suppliers, and a demo supplier's
  -- words are now refused (26 of 28 open proposals had come from demo fixtures). The loop is asked with no supplier (the
  -- routine's null branch, never a real lead), so "seen again" is counted on `seen` and supplier_ids stays empty; the
  -- refusal itself is asserted first.
  v := public.fn_service_alias_propose(v_a, '[{"phrase":"MDF wall decor panels","key":"wallpaper.wall_panels"}]'::jsonb);
  if v->>'refused' is distinct from 'demo_supplier' then f := f || 'a demo supplier fed the alias queue: ' || v::text || '; '; end if;
  v := public.fn_service_alias_propose(null, '[{"phrase":"MDF wall decor panels","key":"wallpaper.wall_panels"},
                                              {"phrase":"Wall panels","key":"wallpaper.wall_panels"},
                                              {"phrase":"cctv","key":"wallpaper.wall_panels"},
                                              {"phrase":"x","key":"wallpaper.wall_panels"},
                                              {"phrase":"Gold leaf gilding","key":"wallpaper.no_such_service"}]'::jsonb);
  o := o || jsonb_build_object('propose', v);
  if (v->>'proposed')::int <> 2 or (v->>'skipped')::int <> 3 then f := f || 'propose: expected 2 filed and 3 skipped, got ' || v::text || '; '; end if;
  v := public.fn_service_alias_propose(null, '[{"phrase":"mdf  wall decor panels","key":"wallpaper.wall_panels"}]'::jsonb);
  if (v->>'seen_again')::int <> 1 then f := f || 'the same phrase from a second supplier was not counted again; '; end if;
  select id into v_id from public.service_alias_proposal where phrase_norm = 'mdf wall decor panels' and trade_code = 'wallpaper' and code = 'wall_panels';
  if (select seen from public.service_alias_proposal where id = v_id) <> 2 then
    f := f || 'the proposal was not counted twice; ';
  end if;
  v := public.fn_service_alias_decide(v_id, 'approved', '');
  if v->>'code' <> 'decider_required' then f := f || 'a decision without a decider was accepted; '; end if;
  v := public.fn_service_alias_decide(v_id, 'approved', 'sales_engineer', 'probe');
  if not coalesce((v->>'ok')::boolean, false) or not exists (select 1 from public.taxonomy_trade_service where trade_code = 'wallpaper' and code = 'wall_panels' and 'mdf wall decor panels' = any(aliases)) then
    f := f || 'an approved phrase did not join the service''s aliases: ' || v::text || '; ';
  end if;
  if (public.fn_service_alias_decide(v_id, 'rejected', 'sales_engineer'))->>'code' <> 'already_decided' then f := f || 'a decided proposal was decided again; '; end if;
  select id into v_id2 from public.service_alias_proposal where phrase_norm = 'cctv' and trade_code = 'wallpaper' and code = 'wall_panels';
  v := public.fn_service_alias_decide(v_id2, 'approved', 'sales_engineer');
  if v->>'code' <> 'alias_names_another_service' or not (v->'other' ? 'security_systems.cctv') then f := f || 'a name of another service was approved: ' || v::text || '; '; end if;
  if exists (select 1 from public.taxonomy_trade_service where trade_code = 'wallpaper' and code = 'wall_panels' and 'cctv' = any(aliases)) then f := f || 'a refused alias was written; '; end if;
  v := public.fn_service_alias_decide(v_id2, 'rejected', 'sales_engineer', 'names CCTV');
  if not coalesce((v->>'ok')::boolean, false) then f := f || 'a rejection failed; '; end if;
  if exists (select 1 from public.service_alias_proposal where source <> 'curated' and status = 'proposed'
               and (supplier_ids && array[v_a, v_b] or phrase_norm in ('mdf wall decor panels', 'cctv'))) then
    f := f || 'a probe proposal is still open; ';
  end if;

  -- 4. the curated seed, the new service and the adjacency are in place
  if (select count(*) from public.service_alias_proposal where source = 'curated' and status = 'approved') < 400 then f := f || 'fewer than 400 curated aliases are recorded; '; end if;
  if not exists (select 1 from public.taxonomy_trade_service where trade_code = 'wallpaper' and code = 'wall_panels' and 'pvc decorative panels' = any(aliases))
     or not exists (select 1 from public.taxonomy_trade_service where trade_code = 'wallpaper' and code = 'film_wrap' and active and 'vinyl wrap' = any(aliases))
     or not exists (select 1 from public.taxonomy_trade_service where trade_code = 'vehicle_leasing' and code = 'long_term_leasing' and 'monthly car rental' = any(aliases)) then
    f := f || 'a curated alias or the film-wrap service is missing; ';
  end if;
  if (select count(*) from public.taxonomy_trade_adjacent where active) < 40 then f := f || 'fewer than 40 adjacent pairs; '; end if;
  o := o || jsonb_build_object('curated', (select count(*) from public.service_alias_proposal where source = 'curated'),
                               'adjacent_pairs', (select count(*) from public.taxonomy_trade_adjacent where active));

  -- 5. closed to the public roles
  if has_function_privilege('anon', 'public.fn_service_alias_decide(bigint,text,text,text)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_service_alias_propose(bigint,jsonb,text)', 'execute')
     or has_function_privilege('anon', 'public.fn_service_alias_owners(text)', 'execute')
     or has_function_privilege('anon', 'public.fn_match_capability(text[],text,text[],text[],text,numeric,text,integer,text[])', 'execute') then
    f := f || 'a routine is executable by anon or authenticated; ';
  end if;
  if has_table_privilege('anon', 'public.service_alias_proposal', 'select') or has_table_privilege('authenticated', 'public.taxonomy_trade_adjacent', 'select') then
    f := f || 'a new table is readable by anon or authenticated; ';
  end if;

  -- 6. nothing real moved
  select count(*) into v_caps_after from public.supplier_capabilities where supplier_id not in (v_a, v_b);
  select count(*) into v_leads_after from public.leads;
  if v_caps_after <> v_caps_before or v_leads_after <> v_leads_before then f := f || 'real rows moved; '; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when f = '' then 'PROBE OK' else 'PROBE FAILED: ' || f end,
    'rows', jsonb_array_length(mx->'rows'), 'matched', v_pos, 'controls_kept_out', v_neg,
    'confusables_right', v_conf, 'confusables', jsonb_array_length(mx->'conf'), 'similarity_sets_checked', v_sim) || o;
end $probe$;
