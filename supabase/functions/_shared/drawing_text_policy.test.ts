// drawing_text_policy — which words of a drawing may reach a supplier, and when a word is the customer's name.
// deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/drawing_text_policy.test.ts
//
// Second review of #967 (25 Sep 2026). Its probe fuzzy.ts measured the seed matcher both ways: spellings of the
// same Arabic name it missed ("RASHEED KARIM" for "Rashid Kareem"), and drawing words it withheld as if they were a
// name ("ORBITAL" for "Orbit", "KITCHEN" and "SWITCHED SPUR" for "Kitchens Plus", "CEILING HEIGHT" for "Marina
// Heights"). Every probe is a case here. Offline; the names are synthetic.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { fold, isDrawingContent, namesParty, seedHit } from './drawing_text_policy.ts';
import { seedTerms } from './anonymise.ts';
import { ID_TEXT } from './drawing_identity_text.ts';

Deno.test('a name in the spellings a drawing, an OCR and a customer use is the same name', () => {
  const tries: [Record<string, string>, string[]][] = [
    [{ name: 'Rashid Kareem' }, ['RASHEED KARIM', 'RASHED', 'KARIM', 'KAREM', 'KHAREEM', 'RSHID', 'R4SHID', 'RASH1D KAREEM', 'RASHEED', 'KAREEM', 'RASHIDKAREM', 'K A R E E M', 'QAREEM']],
    [{ name: 'Mohammed Al Mansoori', company: 'Emaar Properties' }, ['MOHAMED', 'MUHAMMAD', 'MOHAMMAD', 'MANSOURI', 'AL MANSURI', 'EMAR', 'EMAAR', 'EMMAR']],
    [{ name: 'Fatima Hassan', company: 'Nakheel' }, ['FATIMAH', 'FATMA', 'HASAN', 'HASSAN', 'NAKHIL', 'NAKHEAL']],
  ];
  for (const [src, probes] of tries) {
    const s = seedTerms(src);
    assertEquals(probes.filter((p) => !seedHit(p, s)), [], `missed for ${JSON.stringify(src)}`);
  }
  assertEquals(fold('RASHEED KARIM'), fold('Rashid Kareem'));
});

Deno.test('drawing words are not a name: whole tokens only, and never a seed word that is a trade word', () => {
  const content = `OFFICE 101|MEETING ROOM 102|CORRIDOR|MASTER BEDROOM|KITCHEN|MAJLIS|MAID ROOM|TOILET|BALCONY|STAIRCASE|RECEPTION|STORAGE|LAUNDRY|DRESSING|SMOKE DETECTOR|DOUBLE SOCKET OUTLET|SWITCHED SPUR|EMERGENCY LIGHT|DISTRIBUTION BOARD|FAN COIL UNIT|SUPPLY AIR DIFFUSER|RETURN AIR GRILLE|FIRE ALARM PANEL|MANUAL CALL POINT|HEAT DETECTOR|SPRINKLER HEAD|DOWNLIGHT|LIGHTING LAYOUT|POWER LAYOUT|GROUND FLOOR PLAN|FIRST FLOOR|ROOF PLAN|CEILING HEIGHT 3000|MASHRABIYA SCREEN|PRAYER ROOM|GUEST BEDROOM|FAMILY LIVING|SERVICE CORRIDOR|MECHANICAL ROOM|ELECTRICAL ROOM|GARAGE|DRIVER ROOM|STORE ROOM|CABINET|WARDROBE|MARBLE FLOORING|GYPSUM CEILING|CONCRETE SLAB|RETAINING WALL|STAIRCASE SECTION|HANDRAIL|MANHOLE|CHAMBER|MAINTENANCE|MANSARD ROOF|KITCHENS|TWO KITCHENS|MONITOR|CHARGER|RADIATOR|ACCESSORIES|CASHIER|ORBITAL|MANIFOLD|MANSION|FATIGUE|KARAOKE|SHAREDSPACE|CHAIR|EMERGENCY`.split('|');
  const customers: Record<string, string>[] = [
    { name: 'Rashid Kareem' }, { name: 'Mohammed Al Mansoori', company: 'Emaar Properties' }, { name: 'Fatima Hassan', company: 'Nakheel' },
    { name: 'Kareem Consulting', company: 'Orbit Design Studio' }, { name: 'Sara Ali', project: 'Palm Residence', company: 'Marina Heights Developers' },
    { name: 'Omar', company: 'Kitchens Plus' },
  ];
  for (const src of customers) {
    const s = seedTerms(src);
    assertEquals(content.filter((c) => seedHit(c, s)), [], `drawing words read as ${JSON.stringify(src)}`);
  }
  // The whole phrase is still the party.
  assert(seedHit('KITCHENS PLUS', seedTerms({ name: 'Omar', company: 'Kitchens Plus' })));
  assert(seedHit('MARINA HEIGHTS', seedTerms({ company: 'Marina Heights Developers' })));
});

Deno.test('fail closed: a short word passes only from the closed list; anything unknown, foreign or disguised is withheld', () => {
  for (const t of ['DAR', 'WSP', 'ARUP', 'ZZ', 'ORB', 'OR BI T', '<> BY DAR', 'ZZ ORBIT', 'NORTH GATE LLC', '0RB1T', 'ORB\u00cdT', 'K', 'K A R E E M', 'VILLA 12 JUMEIRAH', 'al@', 'kx.ae', 'T 050']) {
    assert(!isDrawingContent(t), `"${t}" passed as drawing content`);
  }
  for (const t of ['OFFICE 101', 'SD - SMOKE DETECTOR', 'DB-01', '63A TPN', '12 WAYS', '2x13A', 'L1', 'FFL +0.150', 'SPLIT AC 2.5 TR', 'DATA OUTLET CAT6', 'CABLE SIZE 4C x 16 SQMM XLPE/SWA', 'REFER TO MEP SPECIFICATION', 'CONTRACTOR TO VERIFY ON SITE', 'EXISTING WALL TO BE DEMOLISHED', 'POWDER ROOM', 'SWIMMING POOL', 'VANITY', 'SHOWER', '<>', '600x600', 'OFFICE 1@1']) {
    assert(isDrawingContent(t), `"${t}" was withheld`);
  }
  assert(!namesParty('CONTRACTOR TO VERIFY ON SITE') && namesParty('CONTRACTOR: ZZ OMEGA CONTRACTING') && namesParty('ZZORBITENGINEERING'));
});

Deno.test('the phone forms the review drew are contacts', () => {
  for (const t of ['(04) 123-4567', '04.123.4567', '0 5 0 1 2 3 4 5 6 7', '050 1234 567', '050 123 4567', '04 123 4567']) assert(ID_TEXT.test(t), t);
  for (const t of ['6000', '+0.150', '1:100', '600x600', '3000 4500', '12345']) assert(!ID_TEXT.test(t), `${t} read as a phone`);
});

// ── third review of #967 (25 Sep 2026): its fuzzy2.ts and over3.ts ───────────────────────────────────────────────
Deno.test('third review: a trade word is never a fuzzy match for a name ("PANEL" is not "Patel")', () => {
  const content = `PANEL|FIRE ALARM PANEL|ACCESS PANEL|TILES|FLOOR TILES|FLOORS|RAMPS|RAMP|METERS|METER|RISERS|RISER|SHOWER|POWER|TOWER|LOWER|SENSOR|SENSORS|SOCKET|SOCKETS|SAFETY|MIRROR|MOTOR|HEATER|WATER|CHILLER|BOILER|DAMPER|DAMPERS|MANHOLE|CABLE|CABLES|TABLE|STABLE|BASIN|BASINS|SINKS|SLAB|SLABS|STAIR|STAIRS|GATES|PLATES|PLANT|PLANTER|RAILING|CEILING|MARBLE|GRANITE|CARPET|CARPETS|KITCHEN|GARAGE|GARDEN|MAJLIS|MASTER|DINING|LIVING|LAUNDRY|PANTRY|STORE|LOBBY|OFFICE|BEDROOM|TOILET|SALON|DRIVER|DRIVERS|SERVANT|NURSERY|SAUNA|DECK|LAWN|POOL|PUMP|PUMPS|VALVE|VALVES|TRAYS|TRUNKING|CONDUIT|ISOLATOR|SWITCH|BUTTON|SPEAKER|CAMERA|READER|LIGHTING|LUMINAIRE|DOWNLIGHT|MANIFOLD`.split('|');
  const custs = ['Rajesh Patel', 'Maria Torres', 'Jose Flores', 'Ana Ramos', 'Mark Santos', 'Joy Reyes', 'Liza Mendoza', 'Paolo Castillo', 'Rico Soriano', 'Jun Pascual', 'Tess Mercado', 'Sanjay Mehta', 'Anil Kumar', 'Priya Nair', 'Vikram Reddy', 'Suresh Pillai', 'Rohit Shetty', 'Deepak Sharma', 'Amit Shah', 'Imran Khan', 'George Mathew', 'Ravi Menon', 'Khalid Al Falasi', 'Saeed Al Mansoori', 'Hamdan Al Ketbi', 'Obaid Al Suwaidi', 'Mariam Al Hashimi', 'Salem Al Nuaimi', 'Sultan Al Mazrouei', 'Ali Tower'];
  for (const name of custs) { const s = seedTerms({ name }); assertEquals(content.filter((t) => seedHit(t, s)), [], `drawing words read as ${name}`); }
  // The names themselves, in their other spellings, still are.
  for (const [name, probes] of [['Rajesh Patel', ['PATIL', 'PATTEL', 'RAJESH']], ['Maria Torres', ['TORES', 'TORRES']], ['Obaid Al Suwaidi', ['OBEID', 'SUWEIDI', 'SWAIDI']], ['Khalid Al Falasi', ['KHALED', 'FALASEE', 'FALLASI']]] as [string, string[]][]) {
    const s = seedTerms({ name });
    assertEquals(probes.filter((p) => !seedHit(p, s)), [], `missed for ${name}`);
  }
});

Deno.test('third review: two-letter codes alone are withheld; bare digit runs of 6 or more are withheld', () => {
  for (const t of ['DP', 'EL', 'DB', 'SS', 'MS', 'HD', 'AL', 'MZ', 'TP', 'SP', 'GL', 'SK', 'AL BAR', 'CU', 'ST']) assert(!isDrawingContent(t), `"${t}" drawn alone`);
  for (const t of ['DP', 'SD', 'AL BAR']) assert(isDrawingContent(t, { codeContext: true }), `"${t}" withheld in its context`);
  for (const t of ['UP', 'DN', 'A/C', 'W.C.', 'MDB', 'NTS']) assert(isDrawingContent(t), `"${t}" withheld`);
  for (const t of ['123456', '345-0123', '12345 678', '050 000', '(04) 1234567']) assert(!isDrawingContent(t), `"${t}" drawn`);
  for (const t of ['6000', '12345', '600 45']) assert(isDrawingContent(t), `"${t}" withheld`);
  assert(isDrawingContent('1504,68', { dimension: true }), 'a dimension of 6 digits was withheld');
});

// over3.ts: 138 labels as printed on UAE villa and fit-out MEP and architectural drawings. Measured 25 Sep 2026: at
// 2f221cb7 the policy withheld 54 of them (39%); now 8 (5.8%) - a party label (VIDEO DOOR PHONE) and seven drainage
// codes of two letters that are also initials, which are drawn beside their symbol or in a legend row.
export const UAE_LABELS = `MAID'S ROOM|DRIVER'S ROOM|GUEST W.C.|LADIES MAJLIS|MEN'S MAJLIS|BBQ AREA|SPLIT A/C UNIT|A/C|LED DOWNLIGHT|LED STRIP LIGHT|PIR SENSOR|USB SOCKET|EV CHARGER|WEATHERPROOF SOCKET|IP65 LUMINAIRE|CEILING SPEAKER|FLOOR BOX|COVE LIGHT|PENDANT LIGHT|CHANDELIER|WALL LIGHT|BOLLARD LIGHT|FLOODLIGHT|BULKHEAD|SHAVER SOCKET|COOKER CONTROL UNIT|TV POINT|SATELLITE OUTLET|HDMI OUTLET|DATA POINT|TELEPHONE OUTLET|FUSED SPUR|20A DP SWITCH|45A DP SWITCH|WATER HEATER 80L|GEYSER|EXHAUST FAN|DB-G1|SMDB-1F|MDB|KWH METER|ELV CABINET|FACP|MCP|SMOKE DETECTOR|HEAT DETECTOR|FIRE EXTINGUISHER|EXIT SIGN|EMERGENCY LIGHT|SECTION A-A|DETAIL 1|SCALE 1:100|NTS|FFL +0.00|UP|DN|1ST FLOOR PLAN|GROUND FLOOR PLAN|ROOF PLAN|KITCHEN|DIRTY KITCHEN|PANTRY|STORE|LAUNDRY|WALK-IN CLOSET|MASTER BEDROOM|BEDROOM 2|FAMILY LIVING|FORMAL DINING|PRAYER ROOM|WUDU|STAIRCASE|LIFT|ELECTRICAL ROOM|GUARD ROOM|SWIMMING POOL|POOL PUMP ROOM|OUTDOOR KITCHEN|CAR PARKING|GATE|BOUNDARY WALL|GRID LINE|NORTH|FALSE CEILING|GYPSUM BOARD CEILING|MDF DOOR|UPVC WINDOW|ALUMINIUM WINDOW|GLASS BALUSTRADE|MARBLE FLOORING|PORCELAIN TILES|WET AREA|WATERPROOFING|CABLE TRAY 300x50|CONDUIT 25MM|2C x 2.5 SQMM|4C x 16 SQMM XLPE/SWA|RCBO 32A|MCB 20A|SPD|CT METER|PV PANEL|INVERTER|SOLAR WATER HEATER|DOOR BELL|INTERCOM|VIDEO DOOR PHONE|CCTV CAMERA|NVR|WIFI ACCESS POINT|MOTORIZED CURTAIN|DIMMER|KEYCARD SWITCH|DND/MUR|HOTEL KEY CARD|LIGHTING CONTROL PANEL|KNX|DALI|BMS|GAS DETECTOR|GAS LEAK DETECTOR|LPG CYLINDER|WATER TANK|GRAY WATER|SEPTIC TANK|SOAKAWAY|MANHOLE|IC|FCO|GT|FD|FWD|RWP|SVP|DP|VP|SP|WP`.split('|');
Deno.test('third review: the 138 UAE villa and MEP labels - under 10% withheld, and exactly the measured ones', () => {
  const withheld = UAE_LABELS.filter((l) => !isDrawingContent(l));
  assertEquals(UAE_LABELS.length, 138);
  assert(withheld.length / UAE_LABELS.length < 0.1, `${withheld.length} of 138 withheld: ${JSON.stringify(withheld)}`);
  assertEquals(withheld, ['VIDEO DOOR PHONE', 'IC', 'GT', 'FD', 'DP', 'VP', 'SP', 'WP']);
});
