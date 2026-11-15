// Harness journey a (scripts/e2e/journeys.mjs), replayed through the deterministic intake with no model.
// deno test supabase/functions/inquiry_intake/journey_a_replay.test.ts
//
// Harness run 6 (14 Sep 2026) reported: with the paid model on hold the request "stays at needs_info
// forever". This replays the harness's own six messages through the same pieces index.ts runs on the
// live path — classify, the category interview (interview.ts), the sales engineer's questions
// (_shared/intake_requirements.ts) — and reports, turn by turn, what was asked and what was filled.
//
// ALUMINIUM is production's category_specs row for `aluminium`, read 14 Sep 2026.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { utilityText } from './classify.ts';
import { interviewStep, type SpecField, type InterviewState } from './interview.ts';
import { requirementsStep, statedAnswers, toStored, validateStored, type Answers } from '../_shared/intake_requirements.ts';

const ALUMINIUM: SpecField[] = [
  { key: 'element', type: 'multiselect', options: ['Windows (sliding/casement)', 'Doors', 'Kitchen / wardrobe shutters', 'Cladding / composite panel (ACP)', 'Handrails / railing', 'Pergola / shade', 'Partitions'], question: 'What aluminium work?', required: true, question_plain_en: 'What do you need in aluminium — windows, doors, railings, cladding or something else?' },
  { key: 'dimensions_qty', type: 'text', options: [], question: 'Sizes (W x H mm) per unit and quantity (or total m²)?', required: true, question_plain_en: 'How many pieces, and roughly how wide and tall is each one?' },
  { key: 'system_finish', type: 'select', options: ['Powder-coated (RAL)', 'Anodized', 'Thermal-break system', 'Supplier to recommend'], question: 'System & finish preference?', required: false },
  { key: 'glazing', type: 'select', options: ['Single glazed', 'Double glazed', 'Tinted / reflective', 'Frosted', 'No glass'], question: 'Glass infill (if any)?', required: false },
  { key: 'scope', type: 'select', options: ['Supply and install', 'Supply only'], question: 'Scope?', required: true, question_plain_en: 'Should the supplier also install it, or only deliver it?' },
  { key: 'location', type: 'text', options: [], question: 'Property type, emirate/area, floor, access?', required: true, question_plain_en: 'What kind of property is it, and which emirate and area?' },
  { key: 'timeline', type: 'select', options: ['Within 2 weeks', '2-4 weeks', '1-2 months', 'Flexible'], question: 'Timeline?', required: false },
];
const NOW = new Date('2026-09-14T12:00:00Z');

const JOURNEY_A = [
  'We need 40 aluminium windows supplied and installed for a private villa in Dubai Marina. Sizes 1200 x 1500 mm, double glazed, powder coated white.',
  'Installation is required, including removal of the old windows. We need a 2 year warranty covering materials and workmanship.',
  'Materials: thermal break aluminium frames, double glazed 6-12-6 glass, powder coated RAL 9016. Delivery needed by 30 November 2026.',
  'Ground and first floor, direct vehicle access, no crane needed. Budget is open.',
  'Please proceed with these details.', 'Yes, that is correct.',
];

function replay(turns: string[]) {
  let st: InterviewState = { details: {}, asked_key: null };
  let req: Answers = {}; let reqAsked: string | null = null;
  const said: string[] = []; const log: string[] = [];
  let readyAt = 0;
  for (const [i, t] of turns.entries()) {
    said.push(t);
    const step = interviewStep(ALUMINIUM, st, t, said.join(' \n '), 'en');
    st = { details: step.details, asked_key: step.next ? step.next.key : null };
    if (!step.complete) { log.push(`turn ${i + 1}: filled [${step.filled_now.join(', ')}] -> asks "${step.next!.text}"`); continue; }
    const rs = requirementsStep('aluminium', req, reqAsked, t, step.details, 'en', NOW, said.join(' \n '));
    req = rs.answers; reqAsked = rs.next ? rs.next.key : null;
    if (rs.next) { log.push(`turn ${i + 1}: category done; sales engineer asks "${rs.next.text}" (${rs.filled}/${rs.total})`); continue; }
    log.push(`turn ${i + 1}: READY`); if (!readyAt) readyAt = i + 1;
  }
  return { log, readyAt, stored: toStored('aluminium', req, NOW), details: st.details };
}

Deno.test('journey a: the harness\'s own messages reach a postable request with no model', () => {
  const r = replay(JOURNEY_A);
  console.log(r.log.join('\n'));
  console.log('details:', JSON.stringify(r.details));
  console.log('requirements:', JSON.stringify(r.stored));
  assert(r.readyAt > 0 && r.readyAt <= JOURNEY_A.length, `not ready after ${JOURNEY_A.length} turns`);
  assertEquals(validateStored('aluminium', r.stored).ok, true);
  // Measured 14 Sep 2026 before the fix: never ready in six turns, with the warranty sentence stored as
  // the quantity and "Please proceed with these details." as the glass. Every answer below is the
  // customer's own statement, read where they said it.
  assertEquals(r.readyAt, 3);
  assertEquals(r.details.dimensions_qty, '40 windows, 1200 x 1500 mm');
  assertEquals(r.details.scope, 'Supply and install');
  assertEquals(r.stored.installation, { required: 'yes' });
  assertEquals(r.stored.warranty, { required: 'yes', min_months: 24 });
  assertEquals(r.stored.required_by.date, '2026-11-30');
  assertEquals(r.stored.materials.map((m) => [m.component, m.choice]), [['profile', 'thermal_break'], ['glass', 'double']]);
});

// ── Customer audit 21 Sep 2026, finding 8a / 8f ──────────────────────────────────────────────────
// The auditor's own two messages (inquiry_intake c99beee8, 21 Sep 2026), replayed through the same
// pieces. Measured before the fix: after the category questions the sales engineer asked all four
// requirement questions again ("6 LEFT") and the brand question twice more; DEWA was named for an
// Abu Dhabi job. ELECTRICAL is production's category_specs row for `electrical` (required fields).
const ELECTRICAL: SpecField[] = [
  { key: 'scope', type: 'multiselect', required: true, options: ['New wiring (first fix)', 'Rewiring', 'DB board supply & install', 'Lighting', 'Power sockets', 'Data & TV points', 'AC power points', 'DEWA new connection', 'DEWA load upgrade', 'Testing & certification only'], question: 'What electrical work?', question_plain_en: 'What electrical work do you need?' },
  { key: 'property_area', type: 'text', required: true, options: [], question: 'Property type, built-up area (m²) and number of rooms/zones?', question_plain_en: 'What kind of property is it, roughly how big, and how many rooms?' },
  { key: 'supply_phase', type: 'select', required: true, options: ['Single-phase', 'Three-phase', 'Not sure', 'Utility supply not yet available'], question: 'Supply type?', question_plain_en: 'Single-phase or three-phase?' },
  { key: 'location', type: 'text', required: true, options: [], question: 'Which emirate/area?', question_plain_en: 'Which emirate and area?' },
];
const AUDIT = [
  'Electrical works for a ZZ DEMO 4-bedroom villa in Khalifa City A, Abu Dhabi. Supply and install 500 m of 4 mm2 copper cable (BS EN 50525, LSZH) and 3 x 12-way DB boards with MCBs (IEC 61439, Schneider or ABB), plus 60 double sockets and 24 switches (MK Logic or Legrand). Installation and 2-year warranty required. Site is ready for first fix; work must finish by 30 November 2026.',
  'It is a 4-bedroom villa, about 450 m2 built-up, 9 rooms. Three-phase supply. As I said: MK Logic or Legrand for switches and sockets, Schneider or ABB DBs, supplier to install, 2-year warranty minimum, finished by 30 November 2026.',
];

Deno.test('finding 8a: the auditor\'s electrical request is never asked what it already stated', () => {
  const NOW21 = new Date('2026-09-21T09:00:00Z');
  let st: InterviewState = { details: {}, asked_key: null };
  let req: Answers = {}; let reqAsked: string | null = null;
  const said: string[] = []; const asked: string[] = [];
  for (const t of AUDIT) {
    said.push(t);
    const step = interviewStep(ELECTRICAL, st, t, said.join(' \n '), 'en');
    st = { details: step.details, asked_key: step.next ? step.next.key : null };
    if (!step.complete) { asked.push(step.next!.key); continue; }
    const rs = requirementsStep('electrical', req, reqAsked, t, step.details, 'en', NOW21, said.join(' \n '));
    req = rs.answers; reqAsked = rs.next ? rs.next.key : null;
    if (rs.next) asked.push(rs.next.key);
  }
  // Turn 1 states everything but the property size, so exactly one question is asked; turn 2 answers it.
  assertEquals(asked, ['property_area']);
  assertEquals(st.details.scope, 'New wiring (first fix), DB board supply & install, Power sockets');
  assertEquals(st.details.property_area, 'It is a 4-bedroom villa, about 450 m2 built-up, 9 rooms.');
  assertEquals(st.details.supply_phase, 'Three-phase');
  const stored = toStored('electrical', req, NOW21);
  assertEquals(validateStored('electrical', stored).ok, true);
  assertEquals(stored.installation, { required: 'yes' });
  assertEquals(stored.warranty, { required: 'yes', min_months: 24 });
  assertEquals(stored.required_by.date, '2026-11-30');
  assertEquals(stored.materials.map((m) => [m.component, m.choice, m.note]), [['cables_devices', 'other', 'Schneider or ABB; MK Logic or Legrand']]);
  // The first message alone already answers all four, so the "left" count never includes them.
  assertEquals(Object.keys(statedAnswers('electrical', AUDIT[0], NOW21)).sort(), ['installation', 'material.cables_devices', 'required_by', 'warranty']);
});

Deno.test('finding 8f: the utility is the emirate\'s own: ADDC in Abu Dhabi, never DEWA', () => {
  assertEquals(utilityText('Contractor approved by DEWA or the relevant emirate utility', 'Abu Dhabi'), 'Contractor approved by ADDC');
  assertEquals(utilityText('DEWA / the relevant emirate authority', 'Abu Dhabi'), 'ADDC');
  assertEquals(utilityText('DEWA / the relevant emirate authority', 'Sharjah'), 'SEWA');
  assertEquals(utilityText('DEWA / the relevant emirate authority', 'Ras Al Khaimah'), 'Etihad WE');
  assertEquals(utilityText('DEWA / the relevant emirate authority', 'Dubai'), 'DEWA');
  assertEquals(utilityText('DEWA / the relevant emirate authority', null), 'DEWA / the relevant emirate authority', 'unknown emirate: unchanged');
  assertEquals(utilityText('هيئة كهرباء ومياه دبي / السلطة المختصة في الإمارة', 'Abu Dhabi', 'ar'), 'شركة أبوظبي للتوزيع');
  assertEquals(utilityText('the relevant emirate authority', 'Abu Dhabi'), 'the relevant emirate authority', 'a licence authority is not a utility');
});

// ── JOURNEY A OF 15 NOV 2026 (live run, models on, tag 8288bec3; SP report lines ~190-360) ───────────────────────────
// A scripted customer asked to replace four wall splits and service three ducted units in his villa, and answered in his
// own order. Live, the chat asked "supply and install?" three times after he had said it, asked room sizes six times after
// he had given every unit's capacity, asked a ducting preference for a SERVICE of existing ducted units, put another
// question's answer buttons under the message, and closed every turn with the same sales-engineer sentence.
// Here his twelve typed lines go through the REAL handler (offline: fetch and env stubbed, _shared/twilio_free_harness.ts)
// with a STAND-IN MODEL that returns what a faithful reader of each line returns (labelled ZZ DEMO, not recorded output):
// every spec the conversation has answered so far, under its key, with the customer's own words. What is measured is what
// CODE then does with a faithful reading: which question it asks, which buttons go with it, when it is ready.
// HVAC is production's category_specs row for `hvac` (read 15 Nov 2026), with the not_needed_when that
// scripts/sql/the_hvac_room_size_is_not_asked_once_each_units_capacity_is_known.sql adds; the checklist is the repository
// pack (knowledge/packs/hvac.json) mapped by the loader, as the blocking test reads it.
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { checklistsOf as loaderRows } from '../../../scripts/kb/load_trade_spec_checklists.mjs';
import { requirementQuestions } from '../_shared/intake_requirements.ts';

const HVAC: SpecField[] = [
  { key: 'system_type', type: 'select', options: ['Wall/floor split', 'Ducted (concealed) split', 'Cassette', 'VRF/VRV', 'Chiller (air/water-cooled)', 'Package unit', 'FAHU/AHU (fresh air)', 'Not sure - need site survey'], question: 'What type of AC system?', required: true, question_plain_en: 'What kind of air conditioning — wall split units, hidden ducted, ceiling cassettes, a central system, or should the supplier survey and advise?' },
  { key: 'application_area', type: 'text', options: [], question: 'What is the space used for (office, villa, retail, restaurant, server room, warehouse), and roughly what area in m² and ceiling height?', required: true, question_plain_en: 'What is the space used for, and roughly how big is it?',
    not_needed_when: { answered: ['spec_cooling_capacity'], text: "each unit's cooling capacity is stated (BTU/h, TR or kW), or the existing units are replaced like for like" },
    same_as: 'spec_room_use_and_area_or_heat_load_calc' },
  { key: 'new_or_replace', type: 'select', options: ['New installation', 'Replacement of existing', 'Extension of existing', 'Service / repair / maintenance'], question: 'Is this new, replacement, or a service/repair?', required: true, question_plain_en: 'Is this a new installation, replacing old units, adding more, or a repair?' },
  { key: 'load_basis', type: 'select', options: ['Yes, I have heat-load calc / MEP drawings', 'No - supplier to size it'], question: 'Do you have a cooling-load calculation or MEP drawings?', required: false, question_plain_en: 'Do you have engineering drawings for the cooling, or should the supplier work out the size?' },
  { key: 'brand_tier', type: 'select', options: ['Premium (Daikin/Mitsubishi/Trane/Carrier)', 'Mid (LG/Gree/O-General)', 'Economy', 'Best value - recommend'], question: 'Preferred brand tier / efficiency?', required: false, question_plain_en: 'Would you like a premium brand, mid-range, economy, or the best value?' },
  { key: 'electrical_supply', type: 'select', options: ['Single-phase 230V', 'Three-phase 400V', 'Not sure'], question: 'Electrical supply available?', required: false, question_plain_en: 'Do you know whether the power supply is single-phase or three-phase? "Not sure" is fine.' },
  { key: 'scope', type: 'select', options: ['Supply only', 'Supply and install', 'Turnkey (incl. ducting, MEP drawings, testing & commissioning)'], question: 'Scope?', required: true, question_plain_en: 'Should the supplier only deliver, install, or do everything including ducts and testing?' },
  { key: 'amc', type: 'select', options: ['Yes, include AMC', 'No', 'Not sure'], question: 'Include an annual maintenance contract (AMC)?', required: false, question_plain_en: 'Would you like a yearly maintenance contract included?' },
  { key: 'location', type: 'text', options: [], question: 'Which emirate/area, floor level, and condenser location (roof/wall/ground)?', required: true, question_plain_en: 'Which emirate and area, which floor, and where can the outdoor unit go — roof, wall or ground?' },
  { key: 'timeline', type: 'select', options: ['Within 2 weeks', '2-4 weeks', '1-2 months', 'Flexible'], question: 'When do you need it done?', required: false, question_plain_en: 'When do you need it done?' },
];
// His twelve typed lines, in his order (the thirteenth was a tap on the ducting question this fix no longer asks).
const JOURNEY_A_15NOV = [
  'Hello. I need the air conditioning in my villa sorted out. It is Villa 15, Al Barsha 2, Dubai. Four of the wall-mounted split units are old and no longer cool, I want them replaced with new ones, and the three ducted units serviced.',
  'For the three ducted units: full cleaning of coils and filters, drain line cleaning and a gas pressure check, one visit.',
  'Reuse the existing copper pipes if they are in good condition, otherwise allow up to 5 metres of new insulated pipe per unit.',
  'Inverter units, please.',
  'Two bedrooms have 1.5 ton units and the majlis and living room have 2 ton units, so two of 1.5 TR and two of 2.0 TR. The three ducted units are 3 TR each.',
  'The power points and isolators are already there; you only connect to them.',
  'Supply and installation of the four new split units, plus the service of the three ducted units.',
  'Daikin, Mitsubishi Electric or Gree, inverter, R32 or R410A.',
  'Yes, remove the old split units and take them away.',
  'We need it done by 15 December 2026.',
  'Indoor units on the ground and first floor; the outdoor units are on the roof, reached by a fixed ladder.',
  'At least 2 years on the installation and 5 years on the compressors.',
];
// What a faithful reader records at each line: [key, value, the customer's words it came from]. Cumulative per turn.
const READS: [string, string, string][][] = [
  [['system_type', 'Wall/floor split; Ducted (concealed) split', 'Four of the wall-mounted split units are old'],
   ['new_or_replace', 'Replacement of existing; Service / repair / maintenance', 'I want them replaced with new ones, and the three ducted units serviced'],
   ['location', 'A villa in Dubai', 'It is Villa 15, Al Barsha 2, Dubai'],
   ['spec_unit_type', '4 wall splits (replace); 3 ducted splits (service)', 'Four of the wall-mounted split units are old and no longer cool, I want them replaced with new ones, and the three ducted units serviced'],
   ['spec_number_of_units_per_type', '4 wall splits; 3 ducted units', 'Four of the wall-mounted split units are old and no longer cool, I want them replaced with new ones, and the three ducted units serviced']],
  [],
  [['spec_copper_pipe_length_included_per_unit', 'Reuse existing pipes if sound, else up to 5 m new insulated pipe per unit', 'otherwise allow up to 5 metres of new insulated pipe per unit']],
  [['spec_inverter_or_fixed_speed', 'Inverter', 'Inverter units, please.']],
  [['spec_cooling_capacity', '2 x 1.5 TR (bedrooms), 2 x 2.0 TR (majlis, living room); ducted 3 x 3 TR', 'so two of 1.5 TR and two of 2.0 TR. The three ducted units are 3 TR each.']],
  [['spec_electrical_isolator_and_cabling_scope', 'Existing power points and isolators; connect only', 'The power points and isolators are already there; you only connect to them.']],
  [['scope', 'Supply and install', 'Supply and installation of the four new split units']],
  [['spec_brand_preference_or_equivalent_tier', 'Daikin, Mitsubishi Electric or Gree', 'Daikin, Mitsubishi Electric or Gree'], ['spec_refrigerant', 'R32 or R410A', 'R32 or R410A']],
  [['spec_old_unit_removal_and_refrigerant_recover', 'Remove and take away the old split units', 'remove the old split units and take them away']],
  [['timeline', 'By 15 December 2026', 'We need it done by 15 December 2026.']],
  [['spec_outdoor_unit_mounting', 'Roof, reached by a fixed ladder', 'the outdoor units are on the roof, reached by a fixed ladder']],
  [['spec_warranty', '2 years installation, 5 years compressor', 'At least 2 years on the installation and 5 years on the compressors.']],
];
// The four questions as the faithful reader returns them (requirements), cumulative by the line they were said at.
const REQS: Record<string, unknown>[] = [
  { 'material.ducting': 'not_needed' }, {}, {}, {}, {}, {}, { installation: 'yes' }, { 'material.brand': { other: 'Daikin, Mitsubishi Electric or Gree' } }, {},
  { required_by: { date: '2026-12-15', text: '15 December 2026' } }, {}, { warranty: { months: 24 } },
];
function faithful(n: number): Record<string, unknown> {
  const details: Record<string, string> = {}, evidence: Record<string, string> = {}, requirements: Record<string, unknown> = {};
  for (let i = 0; i < n; i++) { for (const [k, v, ev] of READS[i]) { details[k] = v; evidence[k] = ev; } Object.assign(requirements, REQS[i]); }
  return { category: 'hvac', trades: ['hvac'], urgency: 'normal', status: 'needs_info', assistant_message: 'ZZ DEMO stand-in reply', claims_ready: false,
    questions: [], readiness: 50, missing: [], dialect: 'english', trade_codes: ['hvac'], service_keys: [], checklist_topics: ['hvac:spec-split-ac'], site_visit: [],
    condition: {}, problem: '', options_offered: [], chosen_option: '', budget: '', requirements, changed_answers: [], answer_to_question: '', spec_evidence: evidence, unknown_keys: [],
    brief: { summary: 'ZZ DEMO replace 4 wall splits, service 3 ducted units, villa in Dubai', category: 'hvac', scope: '', quantity: '', location: 'A villa in Dubai',
      site_location: 'Villa 15, Al Barsha 2, Dubai', emirate: 'Dubai', al_ain: false, timeline: '', budget: '', details } };
}
const ROOT_A = new URL('../../../', import.meta.url);
// deno-lint-ignore no-explicit-any
const hvacRows = () => loaderRows(JSON.parse(Deno.readTextFileSync(new URL('knowledge/packs/hvac.json', ROOT_A))), 'hvac.json').map(({ refused: _r, ...r }: any) => r);
const JA = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const EMAIL_A = 'zz-demo-journey-a-15nov@example.invalid';

async function replay15Nov() {
  type Row = Record<string, unknown>;
  const w = { n: 0, writer: [] as Row[][], sys: [] as string[], intake: { id: 'ii-zz-ja15', email: EMAIL_A, status: 'needs_info', turns: [] as Row[], customer_id: 'c-zz-ja15', category: null, brief: {} } as Row };
  const rows = hvacRows();
  const stub: Stub = {
    user: { id: 'u-zz-ja15', email: EMAIL_A },
    rows: { customers: [{ id: 'c-zz-ja15', locale: 'en' }], category_specs: [{ category: 'hvac', label: 'Air conditioning', fields: HVAC }],
      taxonomy_trade: [{ code: 'hvac', label: 'HVAC', group_code: 'mep_building_systems', authority_required: [] }], taxonomy_trade_service: [], trade_spec_checklist: rows, sales_knowledge: [] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      if (u.pathname === '/functions/v1/ai_gateway') {
        const b = await req.clone().json().catch(() => ({}));
        if (typeof b.sys === 'string' && b.sys.includes('Return STRICT JSON only')) { w.sys[w.n - 1] = b.sys; return JA({ ok: true, model: 'stub/model', content: JSON.stringify(faithful(w.n)) }); }
        w.writer[w.n - 1].push(b);   // every other call this turn: the reply writer (and the exact-spec reader, which gets no usable answer)
        return JA({ ok: true, model: 'stub/model', content: JSON.stringify({ answer: 'ZZ DEMO voiced reply.' }) });
      }
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      if (t === 'inquiry_state' && req.method === 'GET') return JA([]);
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return JA([{ ...w.intake }]);
        if (req.method === 'PATCH') { Object.assign(w.intake, await req.clone().json()); return JA([]); }
      }
      return undefined;
    },
  };
  const h = await loadFunction('inquiry_intake', () => import('./index.ts'));
  const out: { n: number; sys: string; status: string; next: { key: string | null; text: string; options: string[] | null } | null; message: string; details: Row; writer: Row[] }[] = [];
  for (const line of JOURNEY_A_15NOV) {
    w.n++; w.writer.push([]);
    const r = await invoke(h, stub, { intake_id: 'ii-zz-ja15', turn_id: 't-zz-ja15-' + w.n, lang: 'en', text: line });
    if (r.status !== 200) throw new Error(`turn ${w.n}: HTTP ${r.status} ${JSON.stringify(r.json).slice(0, 300)}`);
    const brief = (w.intake.brief ?? {}) as Row;
    out.push({ n: w.n, sys: w.sys[w.n - 1] ?? '', status: String(r.json.status), next: r.json.next_question ?? null, message: String(r.json.assistant_message ?? ''), details: (brief.details ?? {}) as Row, writer: w.writer[w.n - 1] });
    if (r.json.status === 'ready') break;
  }
  return out;
}

Deno.test('journey A of 15 Nov: a faithful reading is recorded where it was said, nothing answered is asked again, and it reaches ready', async () => {
  const turns = await replay15Nov();
  const log = turns.map((t) => `turn ${t.n} ${t.status}: asks ${t.next ? `[${t.next.key}] ${t.next.text}${t.next.options ? ' {' + t.next.options.join(' | ') + '}' : ''}` : 'nothing'}`);
  console.log(log.join('\n'));
  const asked = turns.map((t) => t.next?.key ?? (t.next ? 'text:' + t.next.text : null)).filter((k): k is string => !!k);
  // supply and install is recorded at the line that said it (line 7) and never asked after
  const at7 = turns.find((t) => t.n === 7)!;
  assertEquals(at7?.details.scope, 'Supply and install', 'supply and install was not recorded at the line that said it');
  assert(!turns.filter((t) => t.n >= 7).some((t) => t.next?.key === 'scope' || t.next?.key === 'installation'), 'supply/install asked after it was answered: ' + log.join('; '));
  // no question asked twice
  assertEquals(asked.filter((k, i) => asked.indexOf(k) !== i), [], 'a question was asked twice: ' + log.join('; '));
  // room size is never asked once each unit's capacity is known (line 5); ducting is never asked of a service-only ducted scope
  const ROOM = ['application_area', 'spec_room_use_and_area_or_heat_load_calc'];
  assert(!turns.filter((t) => t.n >= 5).some((t) => ROOM.includes(String(t.next?.key))), 'room size asked after every capacity was given: ' + log.join('; '));
  assert(asked.filter((k) => ROOM.includes(k)).length <= 1, 'room size asked twice under two keys (the slug\'s field and the trade\'s spec): ' + log.join('; '));
  // once capacity is known, both room-size specs are recorded as not needed, and a supplier reads why
  const last = turns.at(-1)!;
  for (const k of ROOM) assert(String(last.details[k] ?? '').startsWith('Not needed for this job: '), k + ' = ' + String(last.details[k]));
  assert(!asked.includes('material.ducting'), 'ducting asked for a service of existing ducted units');
  // it reaches ready within his twelve lines
  assertEquals(turns.at(-1)!.status, 'ready', log.join('\n'));
});

Deno.test('journey A of 15 Nov: every message\'s buttons belong to the question in it, and the sales engineer is offered at most once', async () => {
  const turns = await replay15Nov();
  const fieldOpts = (k: string) => HVAC.find((f) => f.key === k)?.options ?? requirementQuestions('hvac').find((q) => q.key === k)?.options.map((o) => o.en) ?? [];
  let offers = 0;
  for (const t of turns) {
    const written = JSON.stringify(t.writer);
    if (t.next) {
      assert(written.includes('THE ONE QUESTION TO ASK NOW') && written.includes(JSON.stringify(t.next.text).slice(1, -1)), `turn ${t.n}: the reply was not written around the question its card asks`);
      if (t.next.options) {
        assert(t.next.key, `turn ${t.n}: buttons on a question with no key`);
        const allowed = new Set([...fieldOpts(String(t.next.key)), ...(((t.next as { suggested?: string }).suggested) ? [String((t.next as { suggested?: string }).suggested)] : [])]);
        for (const o of t.next.options) assert(allowed.has(o), `turn ${t.n}: button "${o}" does not answer [${t.next.key}] ${t.next.text}`);
      }
    } else assert(!written.includes('THE ONE QUESTION TO ASK NOW'), `turn ${t.n}: no question card, but the writer was told to ask one`);
    if (/sales engineer will help settle/i.test(written)) offers++;
  }
  assert(offers <= 1, `the sales engineer was offered on ${offers} turns`);
});

Deno.test('journey A of 15 Nov: the interview\'s system prompt is the same on every turn once the trade is placed, so the gateway\'s cache serves it', async () => {
  // MEASURED live (ai_cost_log, SELECT): 13 interview calls, 0 cached tokens read, 9,128-13,685 written on every call.
  const turns = await replay15Nov();
  const placed = turns.filter((t) => t.n >= 2);
  assert(placed.length >= 5 && placed.every((t) => t.sys.length > 2000), 'the interview prompt was not captured');
  for (const t of placed.slice(1)) assertEquals(t.sys === placed[0].sys, true, `turn ${t.n}: the system prompt changed (the turn's records belong in the message)`);
  assert(!placed[0].sys.includes('OPEN SPECS NOW (required') && !placed[0].sys.includes('RECORDED (what the customer'), 'per-turn records are back in the system prompt');
});
