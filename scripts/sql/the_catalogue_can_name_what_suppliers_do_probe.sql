-- PROBE (pure, no DDL, aborted transaction) for the_catalogue_can_name_what_suppliers_do.sql.
-- Seat: sales_engineer. 12 Nov 2026, founder rulings 1647 / 1627 / 1628.
-- Run AFTER the file, or with it, rolled back: node scripts/ci/rehearse_sql.mjs scripts/sql/the_catalogue_can_name_what_suppliers_do.sql scripts/sql/the_catalogue_can_name_what_suppliers_do_probe.sql
-- It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back; session_replication_role = replica
-- stops every trigger for this transaction only, so nothing it writes queues a message.
--
-- ITS SUBJECT CANNOT REACH A PERSON: one matchable ZZ DEMO supplier at @example.invalid built by scripts/lib/demo_factory.mjs;
-- its capability row is rewritten here and rolls back. No inquiry is created, nothing is matched into inquiry_matches.
-- Every other supplier's capability and every lead are counted before and after and must not move.
--
-- WHAT IT ASKS:
--   1. every one of the 43 services is active, named in English and Arabic, and carries at least three aliases;
--   2. the founder's words resolve to a key: each staff kind of ruling 1647 (labourers, skilled trades, professional
--      experts, freelancers, drivers, security, cleaners, hospitality, office staff) and a word from each broad area
--      names exactly one service, the one expected;
--   3. a manpower supplier who ticked drivers is matched for a request naming drivers, and not for one naming waiters;
--   4. a manpower supplier who ticked office staff (hr_outsourcing.office_staff_outsourcing, the key the analysis's
--      labour_supply.office_admin_staff would have duplicated) is reached for it through the new adjacency;
--   5. a restaurant fit-out is the hospitality key, no longer the retail one.
do $probe$
declare
  f text := ''; o jsonb := '{}'::jsonb; v_a bigint; v_ids bigint[]; r record; v_owners text[];
  v_caps_before int; v_caps_after int; v_leads_before int; v_leads_after int;
  keys text[] := array[
    'labour_supply.drivers_operators','labour_supply.cleaners_housekeeping','labour_supply.hospitality_staff',
    'labour_supply.engineers_technicians','labour_supply.professional_staff','labour_supply.warehouse_factory',
    'labour_supply.promoters_merchandisers','labour_supply.freelancers',
    'interior_fitout.residential','interior_fitout.hospitality','interior_fitout.healthcare',
    'landscaping.design','landscaping.lighting','landscaping.pergolas_gazebos','landscaping.plants_trees_supply',
    'swimming_pools.pool_renovation','swimming_pools.heating_cooling','swimming_pools.jacuzzi_spa_sauna',
    'facilities_management.handyman','facilities_management.villa_amc','facilities_management.concierge_reception',
    'facilities_management.lifeguards','facilities_management.make_ready',
    'cleaning.contract_cleaning','cleaning.residential','cleaning.carpet_upholstery',
    'joinery.repairs','flooring.repairs',
    'building_materials.tiles','building_materials.paints','building_materials.gypsum_boards','building_materials.timber_plywood',
    'building_materials.hardware','building_materials.plumbing_fittings','building_materials.waterproofing_insulation',
    'electrical.earthing_lightning','logistics_moving.heavy_haulage',
    'event_management.brand_activations','event_management.weddings_private','event_management.event_decor',
    'signage.vehicle_branding','signage.digital_signage','signage.neon_signs'];
  words jsonb := $w${
    "labourers": "labour_supply.general", "tradesmen": "labour_supply.skilled",
    "professional staffing": "labour_supply.professional_staff", "freelancers": "labour_supply.freelancers",
    "engineers on secondment": "labour_supply.engineers_technicians", "drivers supply": "labour_supply.drivers_operators",
    "cleaners supply": "labour_supply.cleaners_housekeeping", "waiters": "labour_supply.hospitality_staff",
    "merchandisers": "labour_supply.promoters_merchandisers", "warehouse workers": "labour_supply.warehouse_factory",
    "office staff supply": "hr_outsourcing.office_staff_outsourcing", "توريد سائقين": "labour_supply.drivers_operators",
    "villa fit out": "interior_fitout.residential", "restaurant fit out": "interior_fitout.hospitality",
    "clinic fit out": "interior_fitout.healthcare", "garden design": "landscaping.design", "garden lighting": "landscaping.lighting",
    "gazebo": "landscaping.pergolas_gazebos", "date palms": "landscaping.plants_trees_supply", "jacuzzi": "swimming_pools.jacuzzi_spa_sauna",
    "pool leak repair": "swimming_pools.pool_renovation", "pool chiller": "swimming_pools.heating_cooling",
    "handyman": "facilities_management.handyman", "villa amc": "facilities_management.villa_amc", "lifeguards": "facilities_management.lifeguards",
    "office cleaning": "cleaning.contract_cleaning", "carpet cleaning": "cleaning.carpet_upholstery", "door repair": "joinery.repairs",
    "tile repair": "flooring.repairs", "porcelain tiles": "building_materials.tiles", "plywood": "building_materials.timber_plywood",
    "earthing": "electrical.earthing_lightning", "truck with driver": "logistics_moving.site_delivery",
    "heavy haulage": "logistics_moving.heavy_haulage", "roadshow": "event_management.brand_activations",
    "wedding planner": "event_management.weddings_private", "kosha": "event_management.event_decor",
    "car wrap": "signage.vehicle_branding", "digital signage": "signage.digital_signage", "neon sign": "signage.neon_signs"}$w$::jsonb;
begin
  set local session_replication_role = replica;
  select count(*) into v_leads_before from public.leads;

  -- 1. the services
  for r in select k, s.label_en, s.label_ar, coalesce(cardinality(s.aliases), 0) as n
             from unnest(keys) k left join public.taxonomy_trade_service s on s.active and s.trade_code || '.' || s.code = k loop
    if r.label_en is null then f := f || r.k || ' is not an active service; ';
    elsif r.label_ar !~ '[ء-ي]' or r.label_en ~ '[ء-ي]' then f := f || r.k || ' is not named in English and Arabic; ';
    elsif r.n < 3 then f := f || r.k || ' has fewer than three aliases; '; end if;
  end loop;
  if exists (select 1 from public.taxonomy_trade_service where trade_code || '.' || code in ('labour_supply.office_admin_staff', 'logistics_moving.trucking')) then
    f := f || 'a duplicate the analysis proposed was added; ';
  end if;

  -- 2. the words name exactly the service expected (fn_service_alias_owners: the queue's own name comparison)
  for r in select key as w, value as want from jsonb_each_text(words) loop
    v_owners := public.fn_service_alias_owners(public.fn_service_alias_norm(r.w));
    if v_owners is distinct from array[r.want] then f := f || '"' || r.w || '" names ' || coalesce(array_to_string(v_owners, '+'), 'nothing') || ', not ' || r.want || '; '; end if;
  end loop;

  -- 3 and 4. a ZZ DEMO manpower supplier
  select l.id into v_a from public.leads l
   where l.company_name ~* '^\s*(zz|qd)\s*demo' and l.email like '%@example.invalid'
     and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
   order by l.id limit 1;
  if v_a is null then raise exception 'CHK<<{"verdict":"PROBE FAILED: no matchable ZZ DEMO supplier at @example.invalid"}>>'; end if;
  select count(*) into v_caps_before from public.supplier_capabilities where supplier_id <> v_a;
  delete from public.supplier_availability where supplier_id = v_a;
  insert into public.supplier_capabilities (supplier_id, trades, roles, services, confirmed_at, confirmed_version)
  values (v_a, array['labour_supply'], array['contractor'], array['labour_supply.drivers_operators'], now(), 1)
  on conflict (supplier_id) do update set trades = array['labour_supply'], roles = array['contractor'],
    services = array['labour_supply.drivers_operators'], services_removed = '{}', excluded_trades = '{}', coverage_emirates = '{}',
    authority_approvals = '{}'::jsonb, min_project_value = null, max_project_value = null, confirmed_at = now();
  if not exists (select 1 from public.fn_match_capability(array['labour_supply'], 'executes', p_limit := 100000,
                   p_services := array['labour_supply.drivers_operators']) m where m.supplier_id = v_a) then
    f := f || 'a manpower supplier who ticked drivers was not matched for drivers; ';
  end if;
  if exists (select 1 from public.fn_match_capability(array['labour_supply'], 'executes', p_limit := 100000,
               p_services := array['labour_supply.hospitality_staff']) m where m.supplier_id = v_a) then
    f := f || 'a manpower supplier who ticked only drivers was matched for waiters; ';
  end if;
  update public.supplier_capabilities set services = array['hr_outsourcing.office_staff_outsourcing'] where supplier_id = v_a;
  if not exists (select 1 from public.fn_match_capability(array['hr_outsourcing'], 'executes', p_limit := 100000,
                   p_services := array['hr_outsourcing.office_staff_outsourcing']) m where m.supplier_id = v_a) then
    f := f || 'a manpower supplier who ticked office staff was not reached for office staff; ';
  end if;

  -- 5. a restaurant is not a shop
  if exists (select 1 from public.taxonomy_trade_service where trade_code = 'interior_fitout' and code = 'retail'
               and aliases && array['restaurant fit out', 'تجهيز مطاعم']) then
    f := f || 'interior_fitout.retail still names restaurant fit-out; ';
  end if;

  select count(*) into v_caps_after from public.supplier_capabilities where supplier_id <> v_a;
  select count(*) into v_leads_after from public.leads;
  if v_caps_after <> v_caps_before or v_leads_after <> v_leads_before then f := f || 'real rows moved; '; end if;
  o := jsonb_build_object('services', cardinality(keys), 'words', (select count(*) from jsonb_object_keys(words)),
                          'active_services', (select count(*) from public.taxonomy_trade_service where active));
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when f = '' then 'PROBE OK' else 'PROBE FAILED: ' || f end) || o;
end $probe$;
