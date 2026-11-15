// A SPEC THE JOB DOES NOT NEED IS NEVER ASKED, AND NO QUESTION IS ASKED TWICE (15 Nov 2026, sales_engineer; journey A, tag 8288bec3).
// The pieces under journey_a_replay.test.ts's replay of that run, one property each, offline. The replay proves them together
// through the real handler; this file says which piece holds which property:
//   1. not_needed_when is data on the spec: a named spec answered, or the model's judgement WITH the customer's words, records the
//      spec as not needed (slots.ts reconcileSlots); a judgement with words the customer never wrote records nothing;
//   2. same_as: two specs that ask the same thing are asked once, and the second is answered by the first;
//   3. a spec is held after three ASKS, not three open turns (askedTurnsByKey), and the next question is one not yet asked;
//   4. with a model reading, the hold reads only a tapped option by code (tappedHeldAnswer);
//   5. the held reply asks the ONE question its buttons answer, offers the sales engineer only when no reply has, on voice_draft;
//   6. the four questions: a component the job does not have takes "Not needed for this job"; the next question is one not yet
//      asked; nothing is asked when every open one waits and the message answered something;
//   7. the pack loader carries not_needed_when as spec codes and refuses a label that is no spec of the checklist; packFields
//      hands it to the slots.
// Run: deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE --allow-read=. --allow-net=127.0.0.1 supabase/functions/inquiry_intake/a_spec_the_job_does_not_need_is_never_asked.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { askedTurnsByKey, heldReply, MAX_OPEN_TURNS, NOT_NEEDED_PREFIX, reconcileSlots, requirementsContract, requirementsFromModel, tappedHeldAnswer, VOICE_CLASS } from './slots.ts';
import type { SpecField } from './interview.ts';
import { requirementQuestions, requirementsStep, toStored, validateStored } from '../_shared/intake_requirements.ts';
import { checklistsOf, packFields, type TradeContext } from '../_shared/inquiry_trades.ts';
import { expertFieldsOf } from '../../../scripts/kb/load_trade_spec_checklists.mjs';

const CAP = 'spec_cooling_capacity', ROOM = 'spec_room_use_and_area_or_heat_load_calc';
const NN = { answered: [CAP], text: "each unit's cooling capacity is stated" };
const FIELDS: SpecField[] = [
  { key: CAP, question: 'Cooling capacity per unit', required: true },
  { key: ROOM, question: 'Room use and area or heat-load calc', required: true, not_needed_when: NN },
  { key: 'application_area', question: 'What is the space used for, and roughly how big is it?', required: true, not_needed_when: NN, same_as: ROOM },
  { key: 'scope', question: 'Supply only or supply and install?', required: true, options: ['Supply only', 'Supply and install'] },
  { key: 'system_type', question: 'What type of AC system?', required: true, options: ['Wall/floor split', 'Ducted (concealed) split', 'Package unit'] },
];
const SAID = 'ZZ DEMO: two of 1.5 TR and two of 2.0 TR. The four splits are replaced like for like.';
const read = (details: Record<string, string>, extra: Record<string, unknown> = {}, prev: Record<string, string> = {}, asked: Record<string, number> = {}) =>
  reconcileSlots(FIELDS, prev, { brief: { details }, ...extra }, 'en', asked, [], SAID);

Deno.test('1. a named spec answered records the specs that need it no more as not needed, with why', () => {
  const s = read({ [CAP]: '2 x 1.5 TR, 2 x 2.0 TR', system_type: 'Wall/floor split' }, { spec_evidence: { [CAP]: 'two of 1.5 TR and two of 2.0 TR', system_type: 'The four splits' } });
  assert(s.details[ROOM].startsWith(NOT_NEEDED_PREFIX) && s.details[ROOM].includes('cooling capacity'), s.details[ROOM]);
  assertEquals(s.details.application_area, s.details[ROOM], 'the same question takes the same answer');
  assertEquals(s.missingKeys, ['scope']);
});
Deno.test('1. only a REAL answer makes a spec unnecessary: not "does not know", not another not-needed value, not an unknown key (review, 15 Nov)', () => {
  for (const [label, details, unknown] of [
    ['supplier to advise', { [CAP]: 'Customer does not know: supplier to advise' }, []],
    ['a not-needed value', { [CAP]: NOT_NEEDED_PREFIX + 'zz' }, []],
    ['a key they said they do not know', { [CAP]: 'ZZ DEMO not sure' }, [CAP]],
  ] as [string, Record<string, string>, string[]][]) {
    const s = reconcileSlots(FIELDS, details, { brief: { details: {} } }, 'en', {}, unknown, SAID);
    assertEquals(s.details[ROOM], undefined, label);
    assert(s.askableKeys!.includes(ROOM), label + ': the room size is not asked');
  }
});
Deno.test('1. the model judges the condition in words: recorded only with the customer\'s own words', () => {
  const ok = read({}, { not_needed: { [ROOM]: 'two of 1.5 TR and two of 2.0 TR.' } });
  assert(ok.details[ROOM]?.startsWith(NOT_NEEDED_PREFIX), 'the model\'s judgement with their words is recorded');
  assertEquals(ok.evidence?.[ROOM], 'two of 1.5 TR and two of 2.0 TR.', 'the words it came from are kept');
  const invented = read({}, { not_needed: { [ROOM]: 'the customer has a heat-load calculation' } });
  assertEquals(invented.details[ROOM], undefined, 'words the customer never wrote record nothing');
  assert(invented.misfiled?.some((m) => m.key === ROOM && m.reason === 'no_customer_words'));
  const noCondition = read({}, { not_needed: { scope: 'The four splits are replaced like for like.' } });
  assertEquals(noCondition.details.scope, undefined, 'a spec with no not_needed_when cannot be declared not needed');
});
Deno.test('2. same_as: the slug\'s field is never asked on its own while the trade\'s spec asks it', () => {
  const s = read({});
  assert(!s.askableKeys!.includes('application_area'), JSON.stringify(s.askableKeys));
  assert(s.missingKeys.includes('application_area'), 'it is still required (dispatch scores it), only not asked twice');
  const answered = read({ [ROOM]: 'Two bedrooms 4 x 4 m, majlis 6 x 5 m' });
  assertEquals(answered.details.application_area, 'Two bedrooms 4 x 4 m, majlis 6 x 5 m');
});
Deno.test('3. held after three ASKS, not three open turns; the next question is one not yet asked', () => {
  // five turns open but asked once: not exhausted (journey A was held at turn 4 by open turns)
  const turns = Array.from({ length: 5 }, (_, i) => ({ role: 'assistant', text: 'q', slots: { missing_keys: ['scope', 'system_type'], asked_keys: i === 0 ? ['scope'] : [] } }));
  const asked = askedTurnsByKey(turns);
  assertEquals(asked, { scope: 1 });
  const s = read({}, {}, {}, asked);
  assertEquals(s.exhausted, []);
  assertEquals(s.askableKeys![0], CAP, 'one not yet asked comes first');
  assertEquals(s.askableKeys!.at(-1), 'scope', 'the one already waiting comes last');
  // a turn stamped before asked_keys existed still counts its open keys, as before
  assertEquals(askedTurnsByKey([{ role: 'assistant', slots: { missing_keys: ['scope'] } }]), { scope: 1 });
  const exhausted = read({}, {}, {}, { scope: MAX_OPEN_TURNS });
  assert(exhausted.exhausted.includes('scope'));
});
Deno.test('3. every open spec waiting and the message answered something: nothing is asked; answered nothing: asked again', () => {
  const all = { [CAP]: 1, [ROOM]: 1, scope: 1, system_type: 1 };
  assertEquals(read({ system_type: 'Wall/floor split' }, { spec_evidence: { system_type: 'The four splits' } }, {}, all).waiting, true);
  assertEquals(read({ system_type: 'Wall/floor split' }, {}, { system_type: 'Wall/floor split' }, all).waiting, false, 'nothing new: a waiting question is asked again');
  assertEquals(read({ system_type: 'Wall/floor split', zz_notes: 'ZZ DEMO a key outside the checklist' }, {}, { system_type: 'Wall/floor split' }, all).waiting, false,
    'a key outside the checklist is no answer: it never silences a waiting question');
});
Deno.test('4. with a model reading, only a tapped option of the held spec is read by code', () => {
  assertEquals(tappedHeldAnswer(FIELDS, 'system_type', 'package unit'), 'Package unit');
  assertEquals(tappedHeldAnswer(FIELDS, 'system_type', 'The power points and isolators are already there; you only connect to them.'), null);
  assertEquals(tappedHeldAnswer(FIELDS, 'system_type', 'Yes, remove the old split units and take them away.'), null);
  assertEquals(tappedHeldAnswer(FIELDS, CAP, '2 x 1.5 TR'), null, 'a free-text spec has no tap');
});
Deno.test('5. the held reply asks the one question its buttons answer, offers the sales engineer once, on voice_draft', async () => {
  const seen: { system: string; input: string }[] = []; const classes: string[] = [];
  // deno-lint-ignore no-explicit-any
  const deps = { gate: () => Promise.resolve(null), embed: () => Promise.resolve(null),
    rpc: (fn: string, a: Record<string, unknown>) => { if (fn === 'fn_ai_route') classes.push(String(a?.p_task_class)); return Promise.resolve({ data: null, error: null }); },
    llm: (_p: string, system: string, input: string) => { seen.push({ system, input }); return Promise.resolve({ content: JSON.stringify({ answer: 'ZZ DEMO held reply.' }), model: 'm' }); } } as any;
  const ask = { text: 'What type of AC system?', options: ['Wall/floor split', 'Ducted (concealed) split', 'Package unit'] };
  const first = await heldReply(deps, FIELDS, ['system_type', 'scope'], 'en', 'x', [], undefined, { ask, offerSettle: true });
  assertEquals(first.by, 'model');
  const facts = seen[0].system + seen[0].input;
  assert(facts.includes('THE ONE QUESTION TO ASK NOW (ask exactly this, in plain words): What type of AC system?') && facts.includes('They can tap one of: Wall/floor split | Ducted (concealed) split | Package unit'), facts.slice(0, 600));
  assert(/do not ask them now/.test(facts) && facts.includes('Supply only or supply and install?'), 'the other open spec is named as open, not asked');
  assert(/sales engineer will help settle/i.test(facts), 'the first held reply offers the sales engineer');
  await heldReply(deps, FIELDS, ['system_type'], 'en', 'x', [], undefined, { ask, offerSettle: false });
  assert(!/sales engineer will help settle/i.test(seen[1].system + seen[1].input), 'offered again on a later turn');
  assert(classes.length && classes.every((c) => c === VOICE_CLASS), 'not the voice_draft task: ' + classes.join(','));
});
Deno.test('6. the four questions: ducting not needed is an answer, and the next question is one not yet asked', () => {
  const duct = requirementQuestions('hvac').find((q) => q.key === 'material.ducting')!;
  assert(duct.options.some((o) => o.v === 'not_needed' && o.en === 'Not needed for this job'));
  assert(requirementsContract('hvac').includes('"not_needed" when the job installs no new ductwork'), 'the model is told when ducting is not needed');
  assertEquals(requirementsFromModel('hvac', { 'material.ducting': 'not_needed' })['material.ducting'], { v: 'not_needed' });
  // the post gate customer_api runs at create (inquiry_create.ts validateStored) accepts it, and a supplier reads it in words
  const stored = toStored('hvac', { 'material.brand': { v: 'premium' }, 'material.ducting': { v: 'not_needed' }, installation: { v: 'yes' }, warranty: { v: 'yes', min_months: 24 }, required_by: { v: 'date', date: '2026-12-15', text: '15 December 2026' } }, new Date('2026-11-15T10:00:00Z'));
  assertEquals(validateStored('hvac', stored).ok, true, JSON.stringify(validateStored('hvac', stored)));
  assertEquals(stored.materials.find((m) => m.component === 'ducting')?.choice_en, 'Not needed for this job');
  assertEquals(requirementsQuestionsWithout('cleaning'), false, 'a component with no condition offers no "not needed"');
  const now = new Date('2026-11-15T10:00:00Z');
  const prev = { 'material.brand': { v: 'premium' }, 'material.ducting': { v: 'not_needed' }, installation: { v: 'yes' } };
  const first = requirementsStep('hvac', prev, null, 'x', {}, 'en', now, '', { modelRead: true, asked: {} });
  assertEquals(first.next?.key, 'warranty');
  const rotated = requirementsStep('hvac', prev, 'warranty', 'ZZ DEMO remove the old units', {}, 'en', now, '', { modelRead: true, asked: { warranty: 1 } });
  assertEquals(rotated.next?.key, 'required_by', 'the one not yet asked comes before the waiting one');
  const waiting = requirementsStep('hvac', prev, 'required_by', 'ZZ DEMO the outdoor units are on the roof', {}, 'en', now, '', { modelRead: true, asked: { warranty: 1, required_by: 1 }, recordedNow: true });
  assertEquals([waiting.next, waiting.waiting, waiting.complete], [null, true, false], 'every open one waits and the message answered something: nothing asked');
  const again = requirementsStep('hvac', prev, 'required_by', 'ZZ DEMO ok', {}, 'en', now, '', { modelRead: true, asked: { warranty: 1, required_by: 1 } });
  assertEquals(again.next?.key, 'warranty', 'a message that answered nothing: the waiting question is asked again');
});
function requirementsQuestionsWithout(cat: string): boolean { return requirementQuestions(cat).some((q) => q.kind === 'material' && q.options.some((o) => o.v === 'not_needed')); }
Deno.test('7. the pack loader writes not_needed_when as codes, refuses a stranger, and packFields hands it to the slots', () => {
  const specs = [{ code: CAP, label_en: 'cooling capacity (BTU/h, TR or kW) per unit' }, { code: ROOM, label_en: 'room use and area or heat-load calc' }];
  const entry = { id: 'zz:spec', blocking: ['cooling capacity (BTU/h, TR or kW) per unit', 'room use and area or heat-load calc'], spec_guide: [
    { spec: 'room use and area or heat-load calc', blocking: true, not_needed_when: { answered: ['cooling capacity (BTU/h, TR or kW) per unit'], text: 'capacity stated' } }] };
  const ex = expertFieldsOf(entry, specs);
  assertEquals(ex.refused, []);
  assertEquals(ex.spec_guide[0].not_needed_when, { answered: [CAP], text: 'capacity stated' });
  const bad = expertFieldsOf({ ...entry, spec_guide: [{ ...entry.spec_guide[0], not_needed_when: { answered: ['ceiling height'], text: 'x' } }] }, specs);
  assert(bad.refused.some((r: string) => r.includes('ceiling height')), JSON.stringify(bad.refused));
  const row = { trade_code: 'hvac', topic_id: 'zz:spec', topic: 'zz', specs, spec_guide: ex.spec_guide, blocking: ex.blocking, site_visit_required_when: null, pack_order: 0 };
  const ctx: TradeContext = { codes: ['hvac'], trades: [], services: [], specs: { hvac: specs }, approvals: {}, checklists: checklistsOf([row]) };
  assertEquals(packFields(ctx).find((f) => f.key === ROOM)?.not_needed_when, { answered: [CAP], text: 'capacity stated' });
});
