-- PROBE (pure, no DDL, aborted transaction) for the_same_work_under_two_keys_meets_at_the_service_gate.sql.
-- Seat: sales_engineer. 12 Nov 2026, founder rulings 1647 / 1628.
-- Run AFTER the catalogue file and this file, or with both, rolled back:
--   node scripts/ci/rehearse_sql.mjs <the catalogue file + this file> scripts/sql/the_same_work_under_two_keys_meets_at_the_service_gate_probe.sql
-- It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back; session_replication_role = replica
-- stops every trigger for this transaction only. Measured 12 Nov 2026 WITHOUT the file: 24 of the analysis's 26 directions
-- missed (directions_met 2); the review measured the tents/fencing and acoustic pairs and the twin of an implied key n -> n.
--
-- ITS SUBJECT CANNOT REACH A PERSON: one matchable ZZ DEMO supplier at @example.invalid (scripts/lib/demo_factory.mjs); its
-- capability row is rewritten per row and rolls back. No inquiry is created and nothing is matched into inquiry_matches.
-- Every other supplier's capability and every lead are counted before and after and must not move.
--
-- FOR EVERY ROW OF THE FILE (A -> B): the supplier holds A (A's trade, and A itself when A is a service; a trade code
-- A is held as his trade only), with the authority approvals of both trades (a real gate kept out of the way); the
-- request names B in B's trade. He must be matched. The CONTROL: the same request naming instead another service of B's
-- trade that A does not imply must NOT reach him, so a row opens B and not B's whole trade. Identity rows are asked both
-- ways because the file writes both; the twin rows prove an IMPLIED key now reaches its twin.
do $probe$
declare
  f text := ''; v_a bigint; v_hit int := 0; v_ctl int := 0; v_n int := 0; r record; v_ctl_key text; v_tr text;
  v_caps_before int; v_caps_after int; v_leads_before int; v_leads_after int;
begin
  set local session_replication_role = replica;
  select count(*) into v_leads_before from public.leads;
  select l.id into v_a from public.leads l
   where l.company_name ~* '^\s*(zz|qd)\s*demo' and l.email like '%@example.invalid'
     and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
   order by l.id limit 1;
  if v_a is null then raise exception 'CHK<<{"verdict":"PROBE FAILED: no matchable ZZ DEMO supplier at @example.invalid"}>>'; end if;
  select count(*) into v_caps_before from public.supplier_capabilities where supplier_id <> v_a;
  delete from public.supplier_availability where supplier_id = v_a;
  insert into public.supplier_capabilities (supplier_id, trades, roles, services, confirmed_at, confirmed_version)
  values (v_a, '{}', array['contractor'], '{}', now(), 1)
  on conflict (supplier_id) do update set trades = '{}', roles = array['contractor'], services = '{}', services_removed = '{}',
    excluded_trades = '{}', coverage_emirates = '{}', min_project_value = null, max_project_value = null, confirmed_at = now();

  for r in select * from (values
      ('landscaping.pools', 'swimming_pools.pool_construction', true),
      ('swimming_pools.pool_construction', 'landscaping.pools', true),
      ('cleaning.pest_control', 'pest_control.general_pest_control', true),
      ('pest_control.general_pest_control', 'cleaning.pest_control', true),
      ('cleaning.facility_management', 'facilities_management.integrated_fm', true),
      ('facilities_management.integrated_fm', 'cleaning.facility_management', true),
      ('security_systems.guarding', 'security_guarding.manned_guarding', true),
      ('security_guarding.manned_guarding', 'security_systems.guarding', true),
      ('upholstery.curtains', 'curtains_blinds.curtains', true),
      ('curtains_blinds.curtains', 'upholstery.curtains', true),
      ('water_treatment.tank_cleaning_disinfection', 'water_treatment_services.water_tank_cleaning_disinfection', true),
      ('water_treatment_services.water_tank_cleaning_disinfection', 'water_treatment.tank_cleaning_disinfection', true),
      ('gypsum.plastering', 'masonry_blockwork.plastering', true),
      ('masonry_blockwork.plastering', 'gypsum.plastering', true),
      ('civil_works.blockwork', 'masonry_blockwork.blockwork', true),
      ('masonry_blockwork.blockwork', 'civil_works.blockwork', true),
      ('joinery.wooden_doors', 'doors.wooden_doors', true),
      ('doors.wooden_doors', 'joinery.wooden_doors', true),
      ('civil_works.demolition', 'demolition_works.building_demolition', true),
      ('demolition_works.building_demolition', 'civil_works.demolition', true),
      ('engineering_consultancy.architectural_design', 'design_consultancy.architectural_design', true),
      ('design_consultancy.architectural_design', 'engineering_consultancy.architectural_design', true),
      ('interior_fitout.interior_design', 'design_consultancy.interior_design', true),
      ('design_consultancy.interior_design', 'interior_fitout.interior_design', true),
      ('tents_shades.car_park_shades', 'fencing_shades.car_park_shades', true),
      ('fencing_shades.car_park_shades', 'tents_shades.car_park_shades', true),
      ('tents_shades.tensile_structures', 'fencing_shades.tensile_structures', true),
      ('fencing_shades.tensile_structures', 'tents_shades.tensile_structures', true),
      ('tents_shades.shade_sails', 'fencing_shades.sail_shades', true),
      ('fencing_shades.sail_shades', 'tents_shades.shade_sails', true),
      ('waterproofing.acoustic', 'thermal_insulation.acoustic_insulation', true),
      ('thermal_insulation.acoustic_insulation', 'waterproofing.acoustic', true),
      ('labour_supply.office_admin_staff', 'hr_outsourcing.office_staff_outsourcing', true),
      ('hr_outsourcing.office_staff_outsourcing', 'labour_supply.office_admin_staff', true),
      ('labour_supply.receptionists', 'facilities_management.concierge_reception', true),
      ('facilities_management.concierge_reception', 'labour_supply.receptionists', true),
      ('waterproofing.thermal', 'thermal_insulation.roof_insulation', false),
      ('waterproofing.thermal', 'thermal_insulation.wall_insulation', false),
      ('civil_works', 'masonry_blockwork.blockwork', false),
      ('civil_works', 'masonry_blockwork.plastering', false),
      ('civil_works.new_construction', 'masonry_blockwork.blockwork', false),
      ('civil_works.new_construction', 'masonry_blockwork.plastering', false),
      ('interior_fitout.decoration', 'curtains_blinds.curtains', false),
      ('interior_fitout.turnkey', 'doors.wooden_doors', false),
      ('aluminium.pergolas_shades', 'landscaping.pergolas_gazebos', false),
      ('av_it.audio_visual', 'signage.digital_signage', false)
    ) x(a, b, same)
  loop
    v_n := v_n + 1;
    v_tr := split_part(r.a, '.', 1);
    if r.same is distinct from (select i.same from public.service_implication i where i.active and i.from_code = r.a
                                   and i.implies_trade || '.' || i.implies_code = r.b) then
      f := f || r.a || ' -> ' || r.b || ' is not the file''s row (same = ' || r.same || '); ';
    end if;
    update public.supplier_capabilities sc set trades = array[v_tr],
      services = case when position('.' in r.a) > 0 then array[r.a] else '{}'::text[] end,
      authority_approvals = coalesce((select jsonb_object_agg(a, true) from public.taxonomy_trade t, unnest(t.authority_required) a
                                       where t.code in (v_tr, split_part(r.b, '.', 1))), '{}'::jsonb)
     where sc.supplier_id = v_a;
    if exists (select 1 from public.fn_match_capability(array[split_part(r.b, '.', 1)], 'executes', p_limit := 100000,
                 p_services := array[r.b]) m where m.supplier_id = v_a) then v_hit := v_hit + 1;
    else f := f || r.a || ' was not reached for ' || r.b || '; '; end if;
    select s.trade_code || '.' || s.code into v_ctl_key from public.taxonomy_trade_service s
     where s.active and s.trade_code = split_part(r.b, '.', 1) and s.trade_code || '.' || s.code <> r.b
       and not (s.trade_code || '.' || s.code = any(public.fn_services_effective(
                  case when position('.' in r.a) > 0 then array[r.a] else '{}'::text[] end, array[v_tr], '{}')))
     order by s.sort, s.code limit 1;
    if v_ctl_key is null then f := f || 'no control service in the trade of ' || r.b || '; ';
    elsif exists (select 1 from public.fn_match_capability(array[split_part(r.b, '.', 1)], 'executes', p_limit := 100000,
                    p_services := array[v_ctl_key]) m where m.supplier_id = v_a) then
      f := f || r.a || ' was reached for ' || v_ctl_key || ', which it does not imply; ';
    else v_ctl := v_ctl + 1; end if;
  end loop;
  -- thermal insulation is roofs AND walls: no longer identity with roof insulation alone
  if exists (select 1 from public.service_implication where same and 'waterproofing.thermal' in (from_code, implies_trade || '.' || implies_code)) then
    f := f || 'waterproofing.thermal is still marked the same work as roof insulation; ';
  end if;

  select count(*) into v_caps_after from public.supplier_capabilities where supplier_id <> v_a;
  select count(*) into v_leads_after from public.leads;
  if v_caps_after <> v_caps_before or v_leads_after <> v_leads_before then f := f || 'real rows moved; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when f = '' then 'PROBE OK' else 'PROBE FAILED: ' || f end,
    'rows_met', v_hit, 'controls_kept_out', v_ctl, 'rows', v_n);
end $probe$;
