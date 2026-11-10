// The solution catalogue's code half (solution_catalogue.ts) over its data (solution_catalogue.json). No network.
// One case per trade family: a typical customer description, the trade that conversation is REASONED to be in (the request
// chat's category or the portal plan's slug: the catalogue is chosen by trade, never by the description's words, ruling 890),
// the options an expert puts for it, and the service keys the chosen one names for matching.
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/_shared/solution_catalogue.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { ADVISE_RULE, FAMILIES, heldProblem, optionOf, PROBLEMS, problemIndex, problemsFor, readSolution, serviceKeysOfChoice, solutionPatch,
  solutionsBlock, solutionStateText, stateServiceKeys } from './solution_catalogue.ts';

// [family, description, reasoned slug, problem, expected option codes, the option chosen, a service key it must name]
const CASES: [string, string, string, string, string[], string, string][] = [
  ['wall_finishes', 'I have a small customised MDF partition and want to cover it, PVC or a wrap sticker?', 'carpentry-joinery', 'cover_existing_board', ['pvc_wpc_panels', 'architectural_film', 'paint_or_laminate'], 'pvc_wpc_panels', 'wallpaper.wall_panels'],
  ['wall_finishes', 'عايز أعمل حيطة مميزة في الصالة', 'wallpaper', 'feature_wall', ['wallpaper', 'fluted_or_3d_panels', 'decorative_paint'], 'fluted_or_3d_panels', 'wallpaper.wall_panels'],
  ['painting', 'the outside of my villa is faded and has small cracks', 'painting', 'exterior_faded_cracked', ['exterior_repaint', 'elastomeric_texture', 'repair_then_repaint'], 'elastomeric_texture', 'painting.exterior'],
  ['painting', 'paint is bubbling on the wall behind the bathroom', 'painting', 'damp_stained_wall', ['fix_source_then_anti_damp', 'replaster_and_repaint', 'moisture_resistant_cladding'], 'fix_source_then_anti_damp', 'waterproofing.wet_areas'],
  ['gypsum_ceilings_partitions', 'بدي قسّم الصالون لغرفتين', 'gypsum', 'divide_a_room', ['gypsum_stud_partition', 'glass_partition', 'joinery_partition'], 'gypsum_stud_partition', 'gypsum.partitions'],
  ['gypsum_ceilings_partitions', 'bathroom ceiling has black spots and is sagging', 'gypsum', 'wet_area_ceiling_damage', ['fix_leak_and_replace_mr_board', 'metal_or_pvc_strip_ceiling'], 'fix_leak_and_replace_mr_board', 'plumbing.maintenance'],
  ['glass_and_glazing', 'our office needs glass partitions for two meeting rooms', 'glass', 'office_glass_partition', ['frameless_toughened', 'aluminium_framed_glazed', 'double_glazed_acoustic'], 'double_glazed_acoustic', 'glazing.partitions'],
  ['glass_and_glazing', 'ابي باب زجاج للشاور', 'glass', 'shower_enclosure', ['frameless_screen', 'framed_sliding', 'fixed_walk_in_panel'], 'frameless_screen', 'glazing.tempered_laminated'],
  ['windows_and_doors', 'my windows let in too much noise and dust', 'aluminium', 'windows_heat_noise_dust', ['thermal_break_double_glazed', 'upvc_double_glazed', 'reseal_and_film'], 'upvc_double_glazed', 'aluminium.windows_doors'],
  ['floors_and_tiles', 'bathroom tiles cracked', 'tiling', 'cracked_or_loose_tiles', ['replace_affected_tiles', 'full_retile', 'overlay_new_floor'], 'overlay_new_floor', 'flooring.parquet_vinyl'],
  ['floors_and_tiles', 'warehouse floor is dusty and stained with oil', 'epoxy-flooring', 'warehouse_or_garage_floor', ['epoxy_coating', 'polyurethane_screed', 'grind_and_seal'], 'epoxy_coating', 'flooring.epoxy'],
  ['stone_and_worktops', 'the marble in the lobby looks dull', 'marble-granite', 'marble_dull_or_stained', ['polish_restore', 'seal_and_maintain', 'replace_damaged_slabs'], 'polish_restore', 'marble_stone.stone_polishing'],
  ['waterproofing', 'السطح يسرّب مي لما تشتي', 'waterproofing', 'roof_leak', ['bituminous_membrane', 'liquid_membrane', 'inverted_roof_insulated'], 'inverted_roof_insulated', 'thermal_insulation.roof_insulation'],
  ['plumbing', 'water pressure upstairs is very weak', 'plumbing', 'low_water_pressure', ['booster_pump', 'clean_tank_and_lines', 'repipe'], 'booster_pump', 'plumbing.heaters_pumps'],
  ['plumbing', 'el 7ammam 9adeem w abi a3adla', 'plumbing', 'bathroom_renovation', ['full_renovation', 'fittings_swap', 'overlay_refresh'], 'full_renovation', 'waterproofing.wet_areas'],
  ['air_conditioning', 'المكيف ما يبرد', 'hvac', 'ac_not_cooling', ['service_and_repair', 'replace_with_inverter', 'maintenance_contract'], 'replace_with_inverter', 'hvac.supply_install'],
  ['electrical', 'I want an EV charger at my villa parking', 'electrical', 'ev_charger', ['ac_wallbox', 'dc_fast'], 'ac_wallbox', 'ev_charging.authority_approvals'],
  ['joinery', 'need wardrobes for the master bedroom', 'carpentry-joinery', 'wardrobe_storage', ['hinged_built_in', 'sliding_doors', 'walk_in_open'], 'sliding_doors', 'joinery.wardrobes'],
  ['kitchens', 'my kitchen works but looks old', 'kitchens', 'tired_kitchen', ['reface_or_wrap', 'doors_and_worktop', 'full_new_kitchen'], 'doors_and_worktop', 'marble_stone.worktops_vanities'],
  ['landscaping', 'the garden is just sand, want something green with kids playing', 'landscaping', 'garden_makeover', ['natural_lawn_irrigation', 'artificial_grass', 'hardscape_and_beds'], 'artificial_grass', 'landscaping.artificial_grass'],
  ['pools', 'pool water turned green', 'swimming-pools', 'pool_water_problem', ['clean_and_maintain', 'equipment_service'], 'clean_and_maintain', 'swimming_pools.pool_maintenance'],
  ['outdoor_shade', 'need shade over the terrace', 'tents-and-shade-structures', 'need_outdoor_shade', ['aluminium_louvre_pergola', 'tensile_shade_sail', 'car_park_shade'], 'tensile_shade_sail', 'tents_shades.shade_sails'],
  ['pests', 'cockroaches in the kitchen', 'pest', 'insects_indoors', ['gel_and_targeted', 'full_treatment_contract'], 'gel_and_targeted', 'pest_control.general_pest_control'],
  ['cleaning', 'moving out of my apartment next week, need it cleaned', 'cleaning', 'move_or_post_works_clean', ['deep_clean', 'post_construction_clean'], 'deep_clean', 'cleaning.deep_cleaning'],
  ['security_systems', 'need cameras for my shop', 'security', 'cameras_needed', ['ip_cameras_nvr', 'wireless_cloud_cameras'], 'ip_cameras_nvr', 'security_systems.cctv'],
  ['fire_safety', 'Civil Defence asked us to upgrade the fire alarm', 'safety', 'fire_alarm_system', ['conventional_alarm', 'addressable_alarm', 'maintenance_and_renewal'], 'addressable_alarm', 'fire_fighting.fire_alarm'],
  ['blinds_curtains', 'too much sun in the bedroom', 'blinds-curtains', 'too_much_sun_or_privacy', ['roller_blackout', 'curtains_lined', 'motorised'], 'roller_blackout', 'curtains_blinds.roller_blinds'],
  ['upholstery_furniture', 'majlis seating is worn out', 'upholstery', 'worn_sofa_or_majlis', ['reupholster', 'new_made_to_measure'], 'reupholster', 'upholstery.sofa'],
  ['smart_home_av_it', 'wifi does not reach the upstairs rooms', 'it-networking', 'weak_wifi_or_network', ['mesh_or_access_points', 'structured_cabling'], 'mesh_or_access_points', 'it_services.network_install'],
  ['solar', 'my DEWA bill is too high, can I add solar?', 'solar', 'cut_power_bills', ['grid_tied_pv', 'pv_with_battery', 'solar_water_heating'], 'grid_tied_pv', 'solar.grid_connection'],
  ['signage', 'need a new sign for my shop', 'signage', 'shop_sign', ['illuminated_3d_letters', 'lightbox', 'printed_panel'], 'lightbox', 'signage.lightbox'],
  ['office_and_shop_fitout', 'we leased an empty office unit, need it fitted out', 'fitout', 'empty_unit_to_fit_out', ['design_and_build', 'design_then_tender', 'light_refurbishment'], 'design_and_build', 'interior_fitout.turnkey'],
  ['building_and_structure', 'there is a long diagonal crack in the boundary wall', 'masonry', 'cracks_in_walls', ['plaster_repair', 'engineer_assessment'], 'engineer_assessment', 'engineering_consultancy.structural_design'],
  ['metalwork', 'the balcony railing is rusting', 'steel', 'gate_fence_or_rusty_railing', ['galvanised_painted_steel', 'stainless_or_glass', 'aluminium_fence'], 'stainless_or_glass', 'steel.stainless'],
  ['insulation_comfort', 'the top floor room is always hot', 'insulation', 'top_floor_too_hot', ['roof_insulation', 'reflective_roof_coating', 'window_solar_film'], 'roof_insulation', 'thermal_insulation.roof_insulation'],
  ['lifts', 'we want a lift in our villa', 'elevators', 'villa_lift_or_old_lift', ['home_lift', 'modernise', 'maintenance_contract'], 'home_lift', 'elevators.home_lifts'],
];

Deno.test('every family has a typical case here, and the catalogue covers at least 20 families', () => {
  assert(FAMILIES.length >= 20, `${FAMILIES.length} families`);
  const covered = new Set(CASES.map((c) => c[0]));
  assertEquals(FAMILIES.map((f) => f.code).filter((f) => !covered.has(f)), [], 'a family with no deterministic case');
});

for (const [family, description, slug, problem, options, chosen, key] of CASES) {
  Deno.test(`${family}: "${description}" (reasoned trade ${slug}) -> ${options.join(' / ')}`, () => {
    const ps = problemsFor({ slug, max: 12 });
    const p = ps.find((x) => x.code === problem);
    assert(p, `${problem} is not offered for ${slug}: ${ps.map((x) => x.code).join(', ')}`);
    assertEquals(p.family, family);
    assertEquals(p.options.map((o) => o.code), options);
    // the block the model reads names every option with its reason and trade-off, by its key
    const block = solutionsBlock([p]);
    for (const o of p.options) assert(block.includes(`${problem}/${o.code}: ${o.en}`) && block.includes('Trade-off: ' + o.trade_off), o.code);
    assert(block.includes('then qualify: '), 'no qualifying questions');
    // the chosen option names the services matching gates on
    const keys = serviceKeysOfChoice({ problem, option: chosen });
    assert(keys.includes(key), `${problem}/${chosen} -> ${keys}`);
    // and the model's answer naming it becomes the state's choice with those keys
    const r = readSolution({ problem, options_offered: options.map((o) => problem + '/' + o), chosen_option: problem + '/' + chosen, condition: { object: description } });
    assertEquals(r.chosen_option?.option, chosen);
    assertEquals(solutionPatch(r).specs?.service_keys, keys.join(', '));
  });
}

Deno.test('the catalogue is general practice: no price, figure, currency or supplier anywhere; Arabic labels are Arabic', () => {
  // the words a person reads (codes and service keys are identifiers); "3D" is a kind of panel or letter, not a figure
  const text = FAMILIES.flatMap((f) => [f.en, f.ar, ...f.problems.flatMap((p) => [p.situation, p.qualify, ...p.options.flatMap((o) => [o.en, o.ar, o.why, o.trade_off, o.check ?? ''])])]).join('\n');
  assert(!/\d/.test(text.replace(/\b3D\b/g, '')), 'a digit in the catalogue (a figure or price): ' + (text.replace(/\b3D\b/g, '').match(/.{20}\d.{10}/)?.[0] ?? ''));
  assert(!/\b(AED|dirhams?|USD|price of|costs? about|per square)\b|درهم/i.test(text), 'a currency or price word');
  for (const f of FAMILIES) {
    assert(/[؀-ۿ]/.test(f.ar), f.code);
    assert(f.trades.length > 0, f.code + ' names no trade');
    for (const p of f.problems) {
      assert(p.options.length >= 2 && p.options.length <= 3, `${p.code}: ${p.options.length} options`);
      for (const o of p.options) {
        assert(/[؀-ۿ]/.test(o.ar), `${p.code}/${o.code} has no Arabic label`);
        assert(o.services.length && o.services.every((k) => /^[a-z0-9_]+\.[a-z0-9_]+$/.test(k)), `${p.code}/${o.code} services`);
        assert(o.why && o.trade_off, `${p.code}/${o.code} why / trade-off`);
      }
    }
  }
  assertEquals(PROBLEMS.size, FAMILIES.reduce((n, f) => n + f.problems.length, 0), 'a problem code is used twice');
});

Deno.test('selection is by trade and by the held problem, never by words; codes reach the families that do that work', () => {
  // the founder's example under three reasonable trades the model may choose: the same situation is offered every time
  for (const slug of ['carpentry-joinery', 'wallpaper', 'fitout', 'painting']) assert(problemsFor({ slug }).some((p) => p.code === 'cover_existing_board') || slug === 'painting', slug);
  // a taxonomy code (the whole taxonomy, ledger 1586) reaches the families whose options name its services
  assert(problemsFor({ codes: ['swimming_pools'] }).some((p) => p.code === 'pool_water_problem'));
  assert(problemsFor({ codes: ['elevators'] }).some((p) => p.code === 'villa_lift_or_old_lift'));
  // a trade the catalogue does not cover gets nothing (the trade's packs and the model's own expertise advise instead)
  assertEquals(problemsFor({ codes: ['staff_transport'] }), []);
  assertEquals(problemsFor({ slug: 'movers' }), []);
  // the held problem comes first whatever the trade
  assertEquals(problemsFor({ slug: 'hvac', held: 'roof_leak' })[0].code, 'roof_leak');
  // no trade yet: the index names every situation
  const idx = problemIndex();
  for (const code of PROBLEMS.keys()) assert(idx.includes(code), code);
});

Deno.test('the ADVISE rule: options when deciding, then qualify; never a pitch, a price or a supplier; a choice is final', () => {
  assert(/two or three suitable options/.test(ADVISE_RULE) && /trade-off/.test(ADVISE_RULE));
  assert(/budget/.test(ADVISE_RULE) && /sizes or quantities/.test(ADVISE_RULE));
  assert(/Never a sales pitch, never volunteer a price, never name a supplier/.test(ADVISE_RULE));
  assert(/do not offer options again/.test(ADVISE_RULE) && /children's room/.test(ADVISE_RULE));
  assert(/own expertise in that trade/.test(ADVISE_RULE), 'the catalogue is not the boundary (ledger 1586)');
});

Deno.test('a model answer: catalogue keys kept, an option outside the catalogue kept by its words, a fake key dropped', () => {
  const r = readSolution({ problem: 'cover_existing_board', options_offered: ['cover_existing_board/pvc_wpc_panels', 'cover_existing_board/made_up', 'fabric wall upholstery'],
    chosen_option: 'fabric wall upholstery', condition: { object: 'MDF partition', constraints: ['kids room', 'small'], colour: 'ignored' }, budget: 'about 3k' });
  assertEquals(r.options_offered, [{ problem: 'cover_existing_board', option: 'pvc_wpc_panels' }, { problem: null, option: 'fabric wall upholstery' }]);
  assertEquals(r.chosen_option, { problem: null, option: 'fabric wall upholstery', label: 'fabric wall upholstery' });
  assertEquals(r.condition, { object: 'MDF partition', constraint: 'kids room, small' });
  assertEquals(serviceKeysOfChoice(r.chosen_option), [], 'an option outside the catalogue names no service');
  assertEquals(solutionPatch(r).specs, undefined);
  assertEquals(readSolution(null).chosen_option, null);
  assertEquals(optionOf('nope/nothing'), null);
});

Deno.test('the solution so far, for the next turn: offered, chosen (and the change), the held problem and its keys', () => {
  const st = { condition: { object: { value: 'MDF partition' }, problem: { value: 'cover_existing_board' } },
    options_offered: [{ problem: 'cover_existing_board', option: 'pvc_wpc_panels' }, { problem: 'cover_existing_board', option: 'architectural_film' }],
    chosen_option: { problem: 'cover_existing_board', option: 'architectural_film', changed_from: { problem: 'cover_existing_board', option: 'pvc_wpc_panels' } },
    specs: { service_keys: { value: 'interior_fitout.decoration, wallpaper.supply_install' } } };
  const t = solutionStateText(st);
  assert(t.includes('PVC or WPC decorative wall panels') && t.includes('THEY CHOSE: Architectural vinyl film wrap'), t);
  assert(t.includes('earlier they chose PVC or WPC decorative wall panels') && t.includes('Do not offer options again'), t);
  assert(solutionStateText(st, 'ar').includes('تغليف بفيلم فينيل معماري'));
  assertEquals(heldProblem(st), 'cover_existing_board');
  assertEquals(stateServiceKeys(st), ['interior_fitout.decoration', 'wallpaper.supply_install']);
  assertEquals(solutionStateText(null), '');
});
