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
import { detectCat, utilityText } from './classify.ts';
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
  assertEquals(detectCat(JOURNEY_A[0]), 'aluminium');
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
  assertEquals(detectCat(AUDIT[0]), 'electrical');
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
