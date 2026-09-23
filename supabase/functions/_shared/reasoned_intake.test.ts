// reasoned_intake — every batch-B4 decision through think() with a MOCKED model: answered each way, held ->
// null and filed in the sales engineer's queue under its own surface, a reply that is not one of the options
// or has no verbatim evidence -> refused, never used. No network, no env, no paid call.
// deno test --no-lock supabase/functions/_shared/reasoned_intake.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import {
  boqMatch, briefTrades, drawingVocabulary, emirateOf, interviewAnswers, quoteTextFacts, requirementAnswer, scopeNotes, serviceInstallRequest, serviceInstallWork,
  supplierQuestion, supplierReply, urgencyOf, vatBasis, NOT_STATED,
} from './reasoned_intake.ts';

const J = (x: unknown) => JSON.stringify(x);
const PLAN = J({ steps: [{ id: 's1', goal: 'read what was written', needs_knowledge: false }], facts: [] });
function mock(synth: unknown[], o: { held?: boolean } = {}) {
  const rpcs: [string, Record<string, unknown>][] = []; const calls: Phase[] = [];
  const queue = synth.map((x) => (typeof x === 'string' ? x : J(x)));
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.held ? { allowed: false, rule: 'founder_hold', held: 1, routes: 8 } : { allowed: true }) as GateAnswer),
    llm: (phase) => {
      calls.push(phase);
      const content = phase === 'decompose' ? PLAN : phase === 'synthesise' ? queue.shift() ?? null : null;
      return Promise.resolve({ content, model: 'qwen/qwen3.8-max-0902' } as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => { rpcs.push([fn, args]); return Promise.resolve({ data: fn === 'fn_reason_hold' ? 77 : [], error: null }); },
  };
  return { deps, rpcs, calls };
}
const heldRow = (m: ReturnType<typeof mock>) => m.rpcs.find(([f]) => f === 'fn_reason_hold')?.[1];

Deno.test('emirate: reasoned from any spelling; "not stated" is an answer; held files the question and guesses nothing', async () => {
  const a = await emirateOf(mock([{ answer: 'Khalifa City A is in Abu Dhabi.', decision: { choice: 'Abu Dhabi' } }]).deps, { conversation: 'villa in Khalifa City A' });
  assertEquals(a.value, 'Abu Dhabi');
  assertEquals((await emirateOf(mock([{ answer: 'No place was named.', decision: { choice: NOT_STATED } }]).deps, { conversation: 'a villa' })).value, NOT_STATED);
  const m = mock([], { held: true });
  const h = await emirateOf(m.deps, { conversation: 'a crack in the wall in RAK', dedupeKey: 'intake_emirate:ZZ1', subject: { intake_id: 'ZZ1' } });
  assertEquals(h.value, null);
  assertEquals([heldRow(m)?.p_surface, heldRow(m)?.p_dedupe_key, heldRow(m)?.p_seat], ['classify.urgency_emirate', 'intake_emirate:ZZ1', 'sales_engineer']);
  assertEquals(m.calls.length, 0, 'no model under the hold');
});

Deno.test('urgency: an option or nothing — a choice that is not an option is refused and never used', async () => {
  assertEquals((await urgencyOf(mock([{ answer: 'Water is leaking now.', decision: { choice: 'emergency' } }]).deps, { conversation: 'water pouring from the ceiling' })).value, 'emergency');
  const bad = await urgencyOf(mock([{ answer: 'Soon.', decision: { choice: 'soon' } }, { answer: 'Soon.', decision: { choice: 'asap' } }]).deps, { conversation: 'today please' });
  assertEquals(bad.value, null);
  assertEquals(bad.result.status, 'held');
});

Deno.test('interview answers: filled only with the customer\'s own words as evidence', async () => {
  const conv = 'We need 40 aluminium windows for a villa in Dubai Marina.';
  const ok = await interviewAnswers(mock([{ answer: 'Location and quantity are stated.', decision: { fields: { location: { value: 'Dubai Marina', evidence: 'villa in Dubai Marina' }, dimensions_qty: { value: '40 aluminium windows', evidence: 'We need 40 aluminium windows' } } } }]).deps,
    { conversation: conv, category: 'aluminium', fields: [{ key: 'location', question: 'where?' }, { key: 'dimensions_qty', question: 'how many?' }] });
  assertEquals(Object.keys(ok.value!).sort(), ['dimensions_qty', 'location']);
  // an invented value (not in the customer's words) is refused both passes: held, nothing filled
  const inv = await interviewAnswers(mock([{ answer: 'x', decision: { fields: { location: { value: 'Jumeirah', evidence: 'Jumeirah villa' } } } }, { answer: 'x', decision: { fields: { location: { value: 'Jumeirah', evidence: 'Jumeirah villa' } } } }]).deps,
    { conversation: conv, category: 'aluminium', fields: [{ key: 'location', question: 'where?' }] });
  assertEquals(inv.value, null);
});

Deno.test('a requirement: the option and its free part; "not answered" is an answer; held files it per question', async () => {
  const ask = { key: 'material.legs_base', question: 'Any preference for the legs?', options: [{ id: 'steel', meaning: 'Steel' }, { id: 'other', meaning: 'their own words — ALSO set decision.fields.note' }], fields: [{ key: 'note', question: 'their words' }] };
  const r = await requirementAnswer(mock([{ answer: 'They want brass legs.', decision: { choice: 'other', fields: { note: { value: 'brushed brass', evidence: 'legs in brushed brass' } } } }]).deps,
    { ask, conversation: 'I would like the legs in brushed brass please', justAsked: true });
  assertEquals(r.value, { choice: 'other', fields: { note: { value: 'brushed brass', evidence: 'legs in brushed brass' } } });
  assertEquals((await requirementAnswer(mock([{ answer: 'The reply is about the delivery date.', decision: { choice: 'not_answered' } }]).deps, { ask, conversation: 'deliver by Friday', justAsked: true })).value?.choice, 'not_answered');
  const m = mock([], { held: true });
  assertEquals((await requirementAnswer(m.deps, { ask, conversation: 'steel', justAsked: true, dedupeKey: 'intake_req:ZZ1:material.legs_base' })).value, null);
  assertEquals(heldRow(m)?.p_surface, 'intake_requirements.parse');
});

Deno.test('brief trades: a set, each trade with the brief\'s own words; a key that is not a taxonomy code is dropped', async () => {
  const r = await briefTrades(mock([{ answer: 'Glazing and aluminium are asked for.', decision: { fields: { glazing: { value: 'glass partitions', evidence: 'glass partitions for the office' } } } }]).deps,
    { brief: 'ZZ DEMO: glass partitions for the office', trades: [{ code: 'glazing', label: 'Glazing' }, { code: 'aluminium', label: 'Aluminium' }] });
  assertEquals(r.value, ['glazing']);
  const m = mock([], { held: true });
  assertEquals((await briefTrades(m.deps, { brief: 'signage', trades: [{ code: 'signage', label: 'Signage' }], dedupeKey: 'brief_trades:ZZ', subject: { inquiry_id: 'ZZ' } })).value, null);
  assertEquals([heldRow(m)?.p_surface, (heldRow(m)?.p_subject as { inquiry_id: string }).inquiry_id], ['sales_engineer.brief_trades', 'ZZ']);
});

Deno.test('VAT basis and the quote form\'s own text are reasoned; held -> null', async () => {
  assertEquals((await vatBasis(mock([{ answer: 'They are below the threshold.', decision: { choice: 'not_registered' } }]).deps, { text: 'we are a small company, no VAT' })).value, 'not_registered');
  assertEquals((await vatBasis(mock([], { held: true }).deps, { text: 'prices + VAT' })).value, null);
  const f = await quoteTextFacts(mock([{ answer: 'Line 1 names Jotun.', decision: { fields: { line_1_brand: { value: 'Jotun', evidence: 'Brand: Jotun' }, installation_included: { value: 'Installation included', evidence: 'Installation included, 5 days' } } } }]).deps,
    { lines: [{ n: 1, description: 'Internal walls, Brand: Jotun' }], scope: 'Installation included, 5 days' });
  assertEquals(Object.keys(f.value!).sort(), ['installation_included', 'line_1_brand']);
});

Deno.test('drawing vocabulary and keyed notes: texts copied from the drawing; held -> null', async () => {
  const v = await drawingVocabulary(mock([{ answer: 'The legend names two devices.', decision: { fields: { 'device:smoke_detector': { value: 'SMOKE DETECTOR', evidence: 'SMOKE DETECTOR' }, drawing_type: { value: 'FIRE ALARM SYSTEM LAYOUT', evidence: 'GROUND FLOOR FIRE ALARM SYSTEM LAYOUT' } } } }]).deps,
    { texts: ['SMOKE DETECTOR', 'MCP'], title: 'GROUND FLOOR FIRE ALARM SYSTEM LAYOUT', types: [{ type: 'smoke_detector', en: 'Smoke detector' }] });
  assertEquals(v.value?.['device:smoke_detector'].value, 'SMOKE DETECTOR');
  const n = await scopeNotes(mock([{ answer: 'Note 1 is work; note 2 remains.', decision: { fields: { 'scope|M1:1': { value: 'PROVIDE MAN BARS', evidence: 'PROVIDE MAN BARS AT EXTERIOR WALL' } } } }]).deps,
    { notes: [{ key: 'M1:1', text: 'PROVIDE MAN BARS AT EXTERIOR WALL' }, { key: 'M1:2', text: 'EXISTING DUCT TO REMAIN' }] });
  assertEquals(n.value, { scope: ['M1:1'], demolish: [] });
  const m = mock([], { held: true });
  assertEquals((await scopeNotes(m.deps, { notes: [{ key: 'M1:1', text: 'x' }] })).value, null);
  assertEquals(heldRow(m)?.p_surface, 'drawing_boq.vocabulary');
});

Deno.test('a trade\'s services are install work or supply, reasoned once per trade; held -> null, queued for the column', async () => {
  const services = [{ code: 'structured_cabling', label_en: 'Structured cabling' }, { code: 'hardware_supply', label_en: 'Hardware supply' }];
  const r = await serviceInstallWork(mock([{ answer: 'Cabling is site work; hardware supply is goods.', decision: { fields: { structured_cabling: { value: 'cabling', evidence: 'Structured cabling' } } } }]).deps, { trade_code: 'it_services', services });
  assertEquals(r.value, { structured_cabling: true, hardware_supply: false });
  const m = mock([], { held: true });
  assertEquals((await serviceInstallWork(m.deps, { trade_code: 'it_services', services })).value, null);
  assertEquals([heldRow(m)?.p_surface, heldRow(m)?.p_dedupe_key, (heldRow(m)?.p_subject as { trade_code: string }).trade_code], ['service_rewrite.install', 'service_install:it_services', 'it_services']);
  // the request the SQL queue mirrors (fn_service_install_queue): one field per service, keyed by its code
  assertEquals(serviceInstallRequest({ trade_code: 'x', services }).decision.fields.map((f) => f.key), ['structured_cabling', 'hardware_supply']);
});

Deno.test('the BOQ match: "Line N" copied from the listing; a line is used once; held -> null with the key the replay checks', async () => {
  const lines = [{ n: 1, description: 'Ceiling emulsion painting' }, { n: 2, description: 'Jotun Fenomastic, internal walls' }];
  const boq = [{ n: 1, description: 'Internal wall painting' }, { n: 2, description: 'Ceiling painting' }, { n: 3, description: 'Doors' }];
  const r = await boqMatch(mock([{ answer: 'Walls are line 2, ceiling line 1.', decision: { fields: {
    boq_1: { value: 'Line 2', evidence: 'Line 2: Jotun Fenomastic, internal walls' }, boq_2: { value: 'Line 1', evidence: 'Line 1: Ceiling emulsion painting' }, boq_3: { value: 'Line 1', evidence: 'Line 1: Ceiling emulsion painting' } } } }]).deps, { boq, lines });
  assertEquals(r.value, { '1': 2, '2': 1 }, 'BOQ line 3 cannot reuse line 1');
  const m = mock([], { held: true });
  assertEquals((await boqMatch(m.deps, { boq, lines, dedupeKey: 'qr_match:R1:k', subject: { review_id: 'R1', key: 'k' } })).value, null);
  assertEquals([heldRow(m)?.p_surface, (heldRow(m)?.p_subject as { key: string }).key], ['supplier_api.quote_review_match', 'k']);
});

Deno.test('a supplier reply and a supplier question: reasoned; held -> null, each on its own surface', async () => {
  const r = await supplierReply(mock([{ answer: 'Validity stated.', decision: { fields: { validity: { value: '30 days', evidence: 'validity 30 days' } } } }]).deps,
    { text: 'validity 30 days please', points: [{ key: 'validity', question: 'validity?' }] });
  assertEquals(r.value?.validity.value, '30 days');
  const m = mock([], { held: true });
  assertEquals((await supplierReply(m.deps, { text: 'x', points: [{ key: 'validity', question: 'v' }], dedupeKey: 'qr_reply:M1', subject: { review_id: 'R', message_id: 'M1' } })).value, null);
  assertEquals(heldRow(m)?.p_surface, 'supplier_api.quote_review_reply');
  const q = await supplierQuestion(mock([{ answer: 'No — a business below AED 375,000 is not VAT-registered and needs no TRN; reply "not VAT registered".', reasoning: ['rules: no TRN below the threshold'], cited: [], confidence: 0.9 }]).deps,
    { question: 'Do I need a TRN?', open: ['State the VAT basis.'], job: '151767', language: 'en' });
  assertEquals(q.status, 'answered');
  const qm = mock([], { held: true });
  assertEquals((await supplierQuestion(qm.deps, { question: 'Do I need a TRN?', open: [], job: '1', language: 'en', dedupeKey: 'qr_question:M2', subject: { review_id: 'R', message_id: 'M2' } })).status, 'held');
  assertEquals(heldRow(qm)?.p_surface, 'supplier_api.quote_review_question');
  assert(!qm.calls.length);
});
