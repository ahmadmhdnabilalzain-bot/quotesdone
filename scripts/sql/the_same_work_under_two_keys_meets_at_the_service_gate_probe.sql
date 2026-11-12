-- PROBE (pure, no DDL, aborted transaction) for the_same_work_under_two_keys_meets_at_the_service_gate.sql.
-- Seat: sales_engineer. 12 Nov 2026, founder rulings 1647 / 1628.
-- Run AFTER the file, or with it, rolled back:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/the_same_work_under_two_keys_meets_at_the_service_gate.sql scripts/sql/the_same_work_under_two_keys_meets_at_the_service_gate_probe.sql
-- It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back; session_replication_role = replica
-- stops every trigger for this transaction only. Measured 12 Nov 2026 WITHOUT the file: 24 of the 26 directions miss (directions_met 2).
--
-- ITS SUBJECT CANNOT REACH A PERSON: one matchable ZZ DEMO supplier at @example.invalid (scripts/lib/demo_factory.mjs); its
-- capability row is rewritten per direction and rolls back. No inquiry is created and nothing is matched into
-- inquiry_matches. Every other supplier's capability and every lead are counted before and after and must not move.
--
-- FOR EACH OF THE 13 PAIRS, BOTH WAYS: the supplier holds key A (and A's trade, and the authority approvals of both
-- trades, a real gate kept out of the way); the request names key B in B's trade. He must be matched. The CONTROL: the
-- same request naming instead another service of B's trade that A does not imply must NOT reach him, so the pair
-- meets as identity and does not open B's whole trade.
do $probe$
declare
  f text := ''; v_a bigint; v_hit int := 0; v_ctl int := 0; r record; v_ctl_key text;
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

  for r in
    select x.a, x.b from (values
      ('landscaping.pools', 'swimming_pools.pool_construction'),
      ('cleaning.pest_control', 'pest_control.general_pest_control'),
      ('cleaning.facility_management', 'facilities_management.integrated_fm'),
      ('security_systems.guarding', 'security_guarding.manned_guarding'),
      ('upholstery.curtains', 'curtains_blinds.curtains'),
      ('water_treatment.tank_cleaning_disinfection', 'water_treatment_services.water_tank_cleaning_disinfection'),
      ('gypsum.plastering', 'masonry_blockwork.plastering'),
      ('civil_works.blockwork', 'masonry_blockwork.blockwork'),
      ('joinery.wooden_doors', 'doors.wooden_doors'),
      ('waterproofing.thermal', 'thermal_insulation.roof_insulation'),
      ('civil_works.demolition', 'demolition_works.building_demolition'),
      ('engineering_consultancy.architectural_design', 'design_consultancy.architectural_design'),
      ('interior_fitout.interior_design', 'design_consultancy.interior_design')
    ) p(k1, k2), lateral (values (p.k1, p.k2), (p.k2, p.k1)) x(a, b)
  loop
    update public.supplier_capabilities sc set trades = array[split_part(r.a, '.', 1)], services = array[r.a],
      authority_approvals = coalesce((select jsonb_object_agg(a, true) from public.taxonomy_trade t, unnest(t.authority_required) a
                                       where t.code in (split_part(r.a, '.', 1), split_part(r.b, '.', 1))), '{}'::jsonb)
     where sc.supplier_id = v_a;
    if exists (select 1 from public.fn_match_capability(array[split_part(r.b, '.', 1)], 'executes', p_limit := 100000,
                 p_services := array[r.b]) m where m.supplier_id = v_a) then v_hit := v_hit + 1;
    else f := f || r.a || ' was not reached for ' || r.b || '; '; end if;
    select s.trade_code || '.' || s.code into v_ctl_key from public.taxonomy_trade_service s
     where s.active and s.trade_code = split_part(r.b, '.', 1) and s.trade_code || '.' || s.code <> r.b
       and not (s.trade_code || '.' || s.code = any(public.fn_services_effective(array[r.a], array[split_part(r.a, '.', 1)], '{}')))
     order by s.sort, s.code limit 1;
    if v_ctl_key is null then f := f || 'no control service in the trade of ' || r.b || '; ';
    elsif exists (select 1 from public.fn_match_capability(array[split_part(r.b, '.', 1)], 'executes', p_limit := 100000,
                    p_services := array[v_ctl_key]) m where m.supplier_id = v_a) then
      f := f || r.a || ' was reached for ' || v_ctl_key || ', which is not the same work; ';
    else v_ctl := v_ctl + 1; end if;
  end loop;

  select count(*) into v_caps_after from public.supplier_capabilities where supplier_id <> v_a;
  select count(*) into v_leads_after from public.leads;
  if v_caps_after <> v_caps_before or v_leads_after <> v_leads_before then f := f || 'real rows moved; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when f = '' then 'PROBE OK' else 'PROBE FAILED: ' || f end,
    'directions_met', v_hit, 'controls_kept_out', v_ctl, 'directions', 26);
end $probe$;
