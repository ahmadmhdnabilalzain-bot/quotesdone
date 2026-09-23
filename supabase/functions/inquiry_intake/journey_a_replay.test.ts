// Harness journey a (scripts/e2e/journeys.mjs) and the 21 Sep audit request, replayed through the intake's state
// machine. Since 23 Sep 2026 typed words are REASONED (interview.answers, intake_requirements.parse): these replays
// run the reasoning HELD (what a customer meets under the model hold) and with a reasoned reading supplied.
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
import { requirementsStep, toStored, validateStored, type Answers, type Reasoner } from '../_shared/intake_requirements.ts';

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

Deno.test('journey a UNDER THE HOLD: the prose fills nothing by its words; open questions keep the reply, option questions are tapped', async () => {
  assertEquals(detectCat(JOURNEY_A[0]), 'aluminium');
  let st: InterviewState = { details: {}, asked_key: null };
  // Turn 1: the whole paragraph. Held: not one field is read off it (it once set scope from "supplied and installed").
  let step = interviewStep(ALUMINIUM, st, { stated: null, answer: JOURNEY_A[0] }, 'en');
  assertEquals(step.details, {});
  assertEquals(step.next!.key, 'element');
  // The customer taps "Windows" — the answer, as it is.
  st = { details: step.details, asked_key: 'element' };
  step = interviewStep(ALUMINIUM, st, { choice: { key: 'element', option: 'Windows (sliding/casement)' }, stated: null }, 'en');
  assertEquals(step.next!.key, 'dimensions_qty');
  // An open question: the typed reply is kept in the customer's own words.
  st = { details: step.details, asked_key: 'dimensions_qty' };
  step = interviewStep(ALUMINIUM, st, { stated: null, answer: '40 windows, 1200 x 1500 mm' }, 'en');
  assertEquals(step.details.dimensions_qty, '40 windows, 1200 x 1500 mm');
  st = { details: step.details, asked_key: step.next!.key };
  step = interviewStep(ALUMINIUM, st, { choice: { key: 'scope', option: 'Supply and install' }, stated: null }, 'en');
  st = { details: step.details, asked_key: step.next!.key };
  step = interviewStep(ALUMINIUM, st, { stated: null, answer: 'Private villa, Dubai Marina, ground and first floor' }, 'en');
  assert(step.complete);
  // The sales engineer's four, by taps (a typed "yes" is not read while held).
  let req: Answers = {}; let asked: string | null = null;
  const held: Reasoner = () => Promise.resolve(undefined);
  const typedYes = await requirementsStep('aluminium', {}, 'installation', 'yes please', step.details, 'en', NOW, held);
  assert(typedYes.held && !typedYes.answers.installation);
  for (const tap of [null, 'Thermal-break (insulated)', 'Double glazed', 'Yes, install it', 'Yes, at least 2 years', 'Within 3 months']) {
    const rs = await requirementsStep('aluminium', req, asked, tap ?? '', step.details, 'en', NOW, held);
    req = rs.answers; asked = rs.next ? rs.next.key : null;
  }
  const stored = toStored('aluminium', req, NOW);
  assertEquals(validateStored('aluminium', stored).ok, true);
  assertEquals(stored.materials.map((m) => [m.component, m.choice]), [['profile', 'thermal_break'], ['glass', 'double']]);
});

// ── Customer audit 21 Sep 2026, finding 8a / 8f ──────────────────────────────────────────────────
// The auditor's own two messages (inquiry_intake c99beee8, 21 Sep 2026). Measured before the fix: after the
// category questions the sales engineer asked all four requirement questions again ("6 LEFT"). With the
// reasoning LIVE (here: the reading the reasoning returns, supplied), what was stated is never asked again.
const ELECTRICAL: SpecField[] = [
  { key: 'scope', type: 'multiselect', required: true, options: ['New wiring (first fix)', 'Rewiring', 'DB board supply & install', 'Lighting', 'Power sockets', 'Data & TV points', 'AC power points', 'DEWA new connection', 'DEWA load upgrade', 'Testing & certification only'], question: 'What electrical work?', question_plain_en: 'What electrical work do you need?' },
  { key: 'property_area', type: 'text', required: true, options: [], question: 'Property type, built-up area (m²) and number of rooms/zones?', question_plain_en: 'What kind of property is it, roughly how big, and how many rooms?' },
  { key: 'supply_phase', type: 'select', required: true, options: ['Single-phase', 'Three-phase', 'Not sure', 'Utility supply not yet available'], question: 'Supply type?', question_plain_en: 'Single-phase or three-phase?' },
  { key: 'location', type: 'text', required: true, options: [], question: 'Which emirate/area?', question_plain_en: 'Which emirate and area?' },
];
const AUDIT = 'Electrical works for a ZZ DEMO 4-bedroom villa in Khalifa City A, Abu Dhabi. Supply and install 500 m of 4 mm2 copper cable (BS EN 50525, LSZH) and 3 x 12-way DB boards with MCBs (IEC 61439, Schneider or ABB), plus 60 double sockets and 24 switches (MK Logic or Legrand). Installation and 2-year warranty required. Site is ready for first fix; work must finish by 30 November 2026.';

Deno.test('finding 8a, reasoning live: what the auditor stated is filled from the reasoned reading and never asked again', async () => {
  const q = (value: string) => ({ value, evidence: value });
  const step = interviewStep(ELECTRICAL, { details: {}, asked_key: null }, { stated: {
    scope: q('Supply and install 500 m of 4 mm2 copper cable'), location: q('Khalifa City A, Abu Dhabi'),
  } }, 'en');
  assertEquals(step.next!.key, 'property_area', 'exactly the one thing not stated is asked');
  const NOW21 = new Date('2026-09-21T09:00:00Z');
  const reading: Record<string, { v: string; min_months?: number; date?: string; text?: string; note?: string }> = {
    'material.cables_devices': { v: 'other', note: 'Schneider or ABB; MK Logic or Legrand' }, installation: { v: 'yes' },
    warranty: { v: 'yes', min_months: 24 }, required_by: { v: 'date', date: '2026-11-30', text: '30 November 2026' },
  };
  const asked: string[] = [];
  const reason: Reasoner = (x) => { asked.push(x.key); return Promise.resolve(reading[x.key] ?? null); };
  const rs = await requirementsStep('electrical', {}, null, '', {}, 'en', NOW21, reason);
  assert(rs.complete, 'all four were stated in the first message: nothing is asked');
  assertEquals(asked, ['material.cables_devices', 'installation', 'warranty', 'required_by']);
  assertEquals(validateStored('electrical', toStored('electrical', rs.answers, NOW21)).ok, true);
  assert(AUDIT.includes('Schneider or ABB'));
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
