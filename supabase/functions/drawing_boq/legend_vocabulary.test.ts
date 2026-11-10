// legend_vocabulary — the ONE table of what a legend entry or a CAD block name calls a thing, across every trade
// (10 Nov 2026, sales_engineer; founder 10 Nov and ruling 1586). No model, no network.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/drawing_boq/legend_vocabulary.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { DEVICE_TYPES, deviceTypeOf } from './legend_vocabulary.ts';

const typeOf = (s: string) => deviceTypeOf(s)?.type ?? null;
/** A CAD block name is read the way boq_from_document reads it: "_" and "-" as spaces. */
const blockOf = (b: string) => typeOf(b.replace(/[_-]+/g, ' '));

Deno.test('the table: every row has a unique type, English, Arabic and a unit; every trade row a section', () => {
  const types = DEVICE_TYPES.map((d) => d.type);
  assertEquals(new Set(types).size, types.length, 'a type is listed twice');
  for (const d of DEVICE_TYPES) {
    assert(d.en && /[؀-ۿ]/.test(d.ar), `${d.type}: English and Arabic`);
    assert(d.unit === 'nos' || d.unit === 'm', d.type);
  }
  const sections = new Set(DEVICE_TYPES.map((d) => d.section).filter(Boolean));
  for (const s of ['Electrical devices', 'Fire fighting', 'HVAC', 'Sanitary fixtures', 'Drainage', 'Plumbing', 'Doors', 'Windows', 'Joinery', 'Furniture',
    'Kitchen equipment', 'Landscape', 'Lifts', 'Swimming pool', 'Signage', 'Racking', 'Structure', 'Scaffolding']) assert(sections.has(s), `no ${s} rows`);
});

Deno.test('fire alarm wording reads as it did before the table grew (the fire rows still come first)', () => {
  const want: [string, string][] = [
    ['FIRE ALARM CONTROL PANEL', 'fire_alarm_control_panel'], ['SMOKE DETECTOR c/w SOUNDER', 'smoke_detector_sounder'], ['OPTICAL SMOKE DETECTOR', 'smoke_detector'],
    ['HEAT DETECTOR', 'heat_detector'], ['MANUAL CALL POINT', 'manual_call_point'], ['WALL MOUNTED SOUNDER BEACON', 'wall_sounder_beacon'], ['SOUNDER', 'sounder'],
    ['كاشف دخان', 'smoke_detector'], ['FP200 GOLD', 'fire_rated_cable'],
  ];
  for (const [t, ty] of want) assertEquals(typeOf(t), ty, t);
});

Deno.test('legend phrasing of every trade, English and Arabic', () => {
  const want: [string, string][] = [
    // electrical
    ['TWIN SWITCHED SOCKET OUTLET 13A', 'socket_outlet'], ['1 GANG LIGHT SWITCH', 'light_switch'], ['RECESSED LED DOWNLIGHT', 'light_fitting'], ['EMERGENCY LIGHT', 'emergency_light'],
    ['EXIT SIGN', 'exit_sign'], ['DISTRIBUTION BOARD', 'distribution_board'], ['DATA OUTLET RJ45', 'data_outlet'], ['CCTV CAMERA', 'cctv_camera'], ['مقبس', 'socket_outlet'], ['وحدة إنارة طوارئ', 'emergency_light'],
    // fire fighting
    ['PENDENT SPRINKLER', 'sprinkler_head'], ['FIRE EXTINGUISHER CO2', 'fire_extinguisher'], ['FIRE HOSE REEL', 'fire_hose_reel'], ['LANDING VALVE', 'landing_valve'], ['طفاية حريق', 'fire_extinguisher'],
    // HVAC
    ['SUPPLY AIR DIFFUSER 600x600', 'supply_diffuser'], ['LINEAR SLOT DIFFUSER', 'linear_diffuser'], ['RETURN AIR GRILLE', 'return_grille'], ['FIRE DAMPER', 'fire_damper'],
    ['VOLUME CONTROL DAMPER', 'volume_damper'], ['EXHAUST FAN', 'exhaust_fan'], ['FAN COIL UNIT', 'fan_coil_unit'], ['DUCTED SPLIT UNIT', 'split_unit'], ['THERMOSTAT', 'thermostat'], ['ناشر هواء', 'supply_diffuser'],
    // plumbing / sanitary / drainage
    ['WALL HUNG WC', 'water_closet'], ['WASH HAND BASIN', 'wash_basin'], ['KITCHEN SINK', 'kitchen_sink'], ['SHOWER TRAY', 'shower'], ['BATHTUB', 'bathtub'], ['URINAL', 'urinal'],
    ['FLOOR DRAIN', 'floor_drain'], ['INSPECTION CHAMBER', 'manhole'], ['WATER HEATER 80L', 'water_heater'], ['مرحاض', 'water_closet'], ['مغسلة', 'wash_basin'], ['شطاف', 'bidet_spray'],
    // architecture / joinery / furniture
    ['FIRE RATED DOOR 60 MIN', 'fire_door'], ['SLIDING DOOR', 'sliding_door'], ['DOUBLE LEAF DOOR', 'double_door'], ['SINGLE LEAF DOOR 900', 'door'], ['ALUMINIUM WINDOW', 'window'],
    ['KITCHEN CABINET BASE UNIT', 'kitchen_cabinet'], ['WARDROBE', 'wardrobe'], ['VANITY UNIT', 'vanity_unit'], ['RECEPTION COUNTER', 'counter'], ['WORKSTATION', 'workstation'], ['باب', 'door'], ['نافذة', 'window'],
    // commercial kitchen
    ['KITCHEN EXHAUST HOOD', 'kitchen_hood'], ['DEEP FAT FRYER', 'fryer'], ['REACH-IN CHILLER', 'refrigerator'], ['DISHWASHER', 'dishwasher'], ['SS WORK TABLE', 'work_table'],
    // landscape
    ['DATE PALM', 'palm_tree'], ['TREE', 'tree'], ['SHRUB', 'shrub'], ['POP-UP SPRAY', 'irrigation_sprinkler'], ['BOLLARD LIGHT', 'light_bollard'], ['نخلة', 'palm_tree'],
    // lifts, pools, signage, racking, structure, scaffolding
    ['PASSENGER LIFT', 'lift'], ['ESCALATOR', 'escalator'], ['مصعد', 'lift'], ['UNDERWATER LIGHT', 'pool_light'], ['SKIMMER', 'pool_skimmer'], ['SAND FILTER', 'pool_filter'],
    ['WAYFINDING SIGN', 'directional_sign'], ['PALLET RACKING', 'pallet_rack_bay'], ['STEEL COLUMN', 'column'], ['BASE PLATE', 'base_plate'], ['SCAFFOLD TOWER', 'scaffold_tower'],
  ];
  const wrong = want.filter(([t, ty]) => typeOf(t) !== ty).map(([t, ty]) => `${t}: ${typeOf(t)} (want ${ty})`);
  assertEquals(wrong, []);
});

Deno.test('CAD block names of every trade', () => {
  const want: [string, string][] = [['DOOR-SGL', 'door'], ['DOOR_900', 'door'], ['WIN-1200', 'window'], ['DIFFUSER_SQ_600', 'supply_diffuser'], ['RETURN_GRILLE', 'return_grille'], ['FCU', 'fan_coil_unit'],
    ['WC_WALLHUNG', 'water_closet'], ['PALM_TREE', 'palm_tree'], ['POOL_LIGHT', 'pool_light'], ['SKIMMER', 'pool_skimmer'], ['SPRINKLER-PENDENT', 'sprinkler_head'], ['EXTINGUISHER', 'fire_extinguisher'], ['SMOKE_DET', 'smoke_detector']];
  assertEquals(want.filter(([b, ty]) => blockOf(b) !== ty).map(([b, ty]) => `${b}: ${blockOf(b)} (want ${ty})`), []);
});

Deno.test('a room name, a note or a tag is not a device', () => {
  for (const t of ['KITCHEN', 'LIVING', 'BATH ROOM', 'MASTER BEDROOM', 'PARKING BAY', 'RANGE 0-100', 'SKT', 'SD', 'ALL POINTS AT 450 AFFL', 'GROUND FLOOR PLAN'])
    assertEquals(typeOf(t), null, t);
  // An exit door is a door, never an exit sign.
  assertEquals(typeOf('EXIT DOOR'), 'door');
});
