// AN ANSWER IS RECORDED UNDER THE SPEC IT ANSWERS (sales_engineer; evidence run of 10 Nov 2026, ledger 1604, finding b2).
// The request chat asked "MEP scope" and got "We need it finished by 15 December 2026."; it asked "Authority approvals and
// responsibility" and got "At least 2 years warranty on materials and installation.". Both were stored as the answers to
// the questions asked, and the request went "ready" with 20/20 filled. Now a reply that only states a date, money, a
// warranty or an emirate answers THAT and leaves the asked spec open; a detail the model cites must be the customer's own
// words; "Customer does not know: supplier to advise" still counts. Generalised to HVAC and staff transport (rulings
// 1579/1586). Offline: the handler runs on the twilio-free harness with a stub model; every party is ZZ DEMO.
// 12 Nov 2026 (founder rulings 1664/1666; LLM-first audit A6): where the MODEL files an answer is now the model's decision,
// told by rule 16 of the interview prompt; code no longer moves a model-filed value by a word list (slots.ts reconcileSlots).
// The assertions below that described that move are corrected to what the code now does, each with its reason; the
// held-spec reading by code (readHeldAnswer, with no model filing) keeps the guard. Proof that the model files the
// RFQ 164464 turn correctly is a paid replay of that one turn (the_models_filing_of_an_answer_stands.test.ts says which).
// Run: deno test --no-lock --node-modules-dir=none -A supabase/functions/inquiry_intake/an_answer_is_recorded_under_the_spec_it_answers.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { answersAnotherKind, statementKind, type SpecField } from './interview.ts';
import { readHeldAnswer, reconcileSlots } from './slots.ts';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const MEP = 'We need it finished by 15 December 2026.';
const WARRANTY = 'At least 2 years warranty on materials and installation.';
const FITOUT: SpecField[] = [
  { key: 'spec_mep_scope', question: 'MEP scope', type: 'text', required: true },
  { key: 'spec_authority_approvals_and_responsibility', question: 'Authority approvals and responsibility', type: 'text', required: true },
  { key: 'location', question: 'Where is the site or the delivery address, and in which emirate?', type: 'text', required: true },
  { key: 'timeline', question: 'By when do you need it done?', type: 'text', required: false },
] as SpecField[];
const slots = (fields: SpecField[], prev: Record<string, string>, det: Record<string, string>, extra: Record<string, unknown> = {}, said?: string) =>
  reconcileSlots(fields, prev, { brief: { details: det }, ...extra }, 'en', {}, [], said);

Deno.test('the exact transcript: the date and the warranty are not the MEP scope or the authority approvals', () => {
  // the held spec, read by code
  assertEquals(readHeldAnswer(FITOUT, 'spec_mep_scope', MEP), null);
  assertEquals(readHeldAnswer(FITOUT, 'spec_authority_approvals_and_responsibility', WARRANTY), null);
  // The model's details. Until 12 Nov code moved these two to the timeline and the warranty by a word list. Rulings
  // 1664/1666 (A6): the model's filing stands, so a model that files the date under the MEP scope is recorded as filed;
  // rule 16 of the prompt is what tells it not to. A model that follows rule 16 files the date where it answers:
  const misfiling = slots(FITOUT, { location: 'Business Bay, Dubai' }, { spec_mep_scope: MEP, spec_authority_approvals_and_responsibility: WARRANTY });
  assertEquals([misfiling.details.spec_mep_scope, misfiling.details.timeline], [MEP, undefined], 'code no longer re-files the model\'s answer');
  const s = slots(FITOUT, { location: 'Business Bay, Dubai' }, { timeline: MEP });
  assertEquals(s.missingKeys, ['spec_mep_scope', 'spec_authority_approvals_and_responsibility']);
  assertEquals(s.complete, false, 'not ready: two blocking specs are still open');
  assertEquals(s.details.timeline, MEP, 'the date is filed where it answers: the timeline');
});

Deno.test('a reply that addresses the spec counts; a date answers the timeline; "supplier to advise" counts', () => {
  const s = slots(FITOUT, {}, { spec_mep_scope: 'No MEP work; the sockets stay where they are', spec_authority_approvals_and_responsibility: 'Customer does not know: supplier to advise', location: 'Business Bay, Dubai' });
  assertEquals(s.complete, true);
  assert(readHeldAnswer(FITOUT, 'timeline', MEP), 'a date answers the timeline');
  assertEquals(readHeldAnswer(FITOUT, 'spec_mep_scope', 'Electrical only: move two sockets; no AC work'), 'Electrical only: move two sockets; no AC work');
});

Deno.test('a detail the model cites must be the customer\'s own words', () => {
  const said = 'ZZ DEMO the panels are old. MEP: no electrical or AC work near the wall.';
  const cited = slots(FITOUT, {}, { spec_mep_scope: 'No MEP works' }, { spec_evidence: { spec_mep_scope: 'no electrical or AC work near the wall' } }, said);
  assertEquals(cited.details.spec_mep_scope, 'No MEP works');
  const invented = slots(FITOUT, {}, { spec_mep_scope: 'No MEP works' }, { spec_evidence: { spec_mep_scope: 'the customer confirmed no MEP' } }, said);
  assertEquals(invented.details.spec_mep_scope, undefined);
  const uncited = slots(FITOUT, {}, { spec_mep_scope: 'No MEP works', location: 'Dubai' }, { spec_evidence: { location: 'Business Bay' } }, said + ' Business Bay');
  assertEquals([uncited.details.spec_mep_scope, uncited.details.location], [undefined, 'Dubai']);
});

Deno.test('every trade: HVAC and staff transport — money, an emirate or a date never answer another kind of spec', () => {
  const HVAC: SpecField[] = [{ key: 'system_type', question: 'What type of AC system is it (split, ducted, VRF, chilled water)?', type: 'text', required: true },
    { key: 'budget', question: 'Do you have a budget in mind?', type: 'text', required: false }] as SpecField[];
  assertEquals(readHeldAnswer(HVAC, 'system_type', 'Budget around AED 20,000'), null);
  // the model's filing (A6, 12 Nov): a model following rule 16 files the budget under the budget; code does not move it
  const h = slots(HVAC, {}, { budget: 'Budget around AED 20,000' });
  assertEquals([h.details.system_type, h.details.budget, h.complete], [undefined, 'Budget around AED 20,000', false]);
  assertEquals(readHeldAnswer(HVAC, 'system_type', 'Ducted split, 5 TR'), 'Ducted split, 5 TR');
  const BUS: SpecField[] = [{ key: 'spec_vehicle_type_and_seating_capacity', question: 'Vehicle type and seating capacity', type: 'text', required: true },
    { key: 'location', question: 'Where is the pick-up, and in which emirate?', type: 'text', required: true }] as SpecField[];
  assertEquals(readHeldAnswer(BUS, 'spec_vehicle_type_and_seating_capacity', 'Sharjah'), null);
  const b = slots(BUS, {}, { location: 'Sharjah' });
  assertEquals([b.details.spec_vehicle_type_and_seating_capacity, b.details.location], [undefined, 'Sharjah']);
  assertEquals(readHeldAnswer(BUS, 'spec_vehicle_type_and_seating_capacity', 'نحتاجه قبل 15 ديسمبر'), null, 'an Arabic date is a date');
  assert(readHeldAnswer(BUS, 'spec_vehicle_type_and_seating_capacity', '50-seater coach with AC'), 'a seating answer answers the seating');
});

Deno.test('the guard decides only the four universal kinds; anything else is the question\'s', () => {
  assertEquals([MEP, WARRANTY, 'Budget around AED 20,000', 'Dubai', 'ضمان سنتين على المواد والتركيب'].map(statementKind), ['required_by', 'warranty', 'budget', 'location', 'warranty']);
  for (const t of ['In Business Bay, Dubai', 'No MEP work, just the panels', '8 mm PVC panels, 2440 x 1220', 'Building management approves; the contractor arranges it', 'yes', '2 years'])
    assertEquals(statementKind(t), null, t);
  assertEquals(answersAnotherKind({ key: 'warranty', question: 'Do you need a warranty?' }, WARRANTY), null, 'a warranty answers the warranty');
});

// ── the real handler, replaying the held turn of the evidence run ───────────────────────────────────────────────────
type Row = Record<string, unknown>;
const EMAIL = 'zz-demo-b2-customer@example.invalid';
const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
Deno.test('RFQ 164464 replayed on the real handler: the warranty reply to "authority approvals" does not make the request ready', async () => {
  const h = await loadFunction('inquiry_intake', () => import('./index.ts'));
  const checklist = [{ trade_code: 'interior_fitout', topic_id: 'interior_fitout:fitout-spec-checklist', topic: 'fit-out', pack_order: 0,
    specs: [{ code: 'spec_mep_scope', label_en: 'MEP scope' }, { code: 'spec_authority_approvals_and_responsibility', label_en: 'Authority approvals and responsibility' }],
    blocking: ['spec_mep_scope', 'spec_authority_approvals_and_responsibility'], spec_guide: [], site_visit_required_when: null }];
  const model = { category: 'fitout', trades: ['fitout'], status: 'ready', claims_ready: true, assistant_message: 'Thank you, that is everything.', questions: [], missing: [], readiness: 100, dialect: 'english',
    trade_codes: ['interior_fitout'], service_keys: [], condition: {}, problem: '', options_offered: [], chosen_option: '', budget: '',
    // The stand-in MISFILES exactly as in RFQ 164464 (main's own stand-in). Since 12 Nov the blocking specs close only on the
    // model's own confirmation of the filing (spec_evidence {words, answers}); this one confirms nothing, so both stay open.
    brief: { summary: 'PVC panels', details: { describe: 'ZZ DEMO replace PVC panels', spec_mep_scope: MEP, spec_authority_approvals_and_responsibility: WARRANTY } } };
  const sys: string[] = [];
  const turns = [
    { role: 'user', text: 'ZZ DEMO In our office in Business Bay, Dubai, we have an MDF partition wall covered with PVC wall panels. We want the old PVC panels removed and new PVC wall panels installed.' },
    { role: 'assistant', text: 'What is the MEP scope?' }, { role: 'user', text: MEP },
    { role: 'assistant', text: 'Who handles the authority approvals?', slots: { reply: { next_question: { key: 'spec_authority_approvals_and_responsibility' } } } },
  ];
  const intake: Row = { id: 'ii-zz-b2', email: EMAIL, status: 'held', turns, customer_id: 'c-zz-b2', category: 'fitout',
    brief: { category: 'fitout', category_by: 'reasoning', asked_on_hold: true, asked_key: 'spec_authority_approvals_and_responsibility', details: { describe: 'ZZ DEMO replace PVC panels' }, state: 'interview' } };
  const stub: Stub = {
    user: { id: 'u-zz-b2', email: EMAIL },
    rows: { customers: [{ id: 'c-zz-b2', locale: 'en' }], category_specs: [{ category: 'fitout', label: 'fitout', fields: [{ key: 'describe', type: 'text', question: 'Describe it', required: true }] }],
      taxonomy_trade: [{ code: 'interior_fitout', label: 'Interior fit-out', group_code: 'construction_building', authority_required: [] }], taxonomy_trade_service: [], trade_spec_checklist: checklist, sales_knowledge: [] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      const r = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (u.pathname.startsWith('/functions/v1/')) {
        const body = await req.clone().json().catch(() => ({}));
        if (body.fn === 'inquiry_intake' && body.response_format) { sys.push(String(body.sys ?? '')); return J({ ok: true, content: JSON.stringify(model), model: 'stub/model' }); }
        return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO: noted.' }), model: 'stub/model' });
      }
      if (r) return J(r === 'rl_check' ? true : null);
      if (t === 'inquiry_state' && req.method === 'GET') return J([{ conv_key: 'intake:ii-zz-b2', surface: 'request_chat', specs: {}, unknown: {}, asked: {}, message_count: 4, status: 'open', trade_codes: ['interior_fitout'] }]);
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return J([{ ...intake }]);
        if (req.method === 'PATCH') { Object.assign(intake, await req.clone().json()); return J([]); }
      }
      return undefined;
    },
  };
  const r = await invoke(h, stub, { intake_id: 'ii-zz-b2', text: WARRANTY, turn_id: 't-zz-b2-3', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  assert(r.json.status !== 'ready', 'went ready on a warranty reply to "authority approvals": ' + JSON.stringify(r.json).slice(0, 300));
  const open = (r.json.blocking as { open: string[] }).open;
  assert(open.includes('spec_mep_scope') && open.includes('spec_authority_approvals_and_responsibility'), JSON.stringify(open));
  // where the answer goes is the model's instruction, with this incident's own two sentences in it
  assert(sys[0]?.includes('"We need it finished by 15 December" answers the date, never "MEP scope"'), 'rule 16 is in the prompt');
});

// ── 12 Nov 2026 (independent review of #1979): a misfiling model cannot make a request ready ─────────────────────────────
const BLOCKING = FITOUT.map((f) => ({ ...f, blocking: f.required })) as SpecField[];
Deno.test('a blocking spec closes only when the model confirms the words answer THAT question; nothing is moved', () => {
  const said = 'ZZ DEMO ' + MEP + ' ' + WARRANTY + ' Business Bay, Dubai';
  // misfiled, and the model's own confirmation says the words answer other questions: not recorded, nothing moved
  const told = slots(BLOCKING, {}, { spec_mep_scope: MEP, spec_authority_approvals_and_responsibility: WARRANTY, location: 'Business Bay, Dubai' },
    { spec_evidence: { spec_mep_scope: { words: MEP, answers: 'timeline' }, spec_authority_approvals_and_responsibility: { words: WARRANTY, answers: 'warranty' }, location: { words: 'Business Bay, Dubai', answers: 'location' } } }, said);
  assertEquals([told.details.spec_mep_scope, told.details.spec_authority_approvals_and_responsibility, told.details.timeline], [undefined, undefined, undefined]);
  assertEquals(told.complete, false);
  assertEquals((told.misfiled ?? []).map((m) => `${m.key}:${m.reason}:${m.answers}`), ['spec_mep_scope:answers_another_question:timeline', 'spec_authority_approvals_and_responsibility:answers_another_question:warranty']);
  // misfiled with no confirmation at all (the RFQ 164464 stand-in): not recorded either
  const bare = slots(BLOCKING, {}, { spec_mep_scope: MEP, spec_authority_approvals_and_responsibility: WARRANTY, location: 'Business Bay, Dubai' }, {}, said);
  assertEquals(bare.complete, false);
  // a confirmed filing closes the spec; a duration asked for is its own answer
  const ok = slots(BLOCKING, {}, { spec_mep_scope: 'No MEP work', spec_authority_approvals_and_responsibility: 'Building management', location: 'Business Bay, Dubai' },
    { spec_evidence: { spec_mep_scope: { words: 'No MEP work', answers: 'spec_mep_scope' }, spec_authority_approvals_and_responsibility: { words: 'Building management', answers: 'spec_authority_approvals_and_responsibility' }, location: { words: 'Business Bay, Dubai', answers: 'location' } } },
    'ZZ DEMO No MEP work. Building management. Business Bay, Dubai');
  assertEquals(ok.complete, true);
});
