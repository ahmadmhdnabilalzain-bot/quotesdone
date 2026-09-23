// intake_requirements: every trade asks all four, nothing is assumed, and the post gate. A TAPPED option is
// the answer; typed words are REASONED (decision point intake_requirements.parse) — here a mocked reasoner.
// deno test supabase/functions/_shared/intake_requirements.test.ts
//
// The founder, 14 Sep 2026: "for installation for example, we need to ask, cause maybe the customer
// will forget. we don't assume stuff". The source-level half (inquiry_intake answers as ACTOR and names
// no other seat) is scripts/checks/the_intake_is_the_sales_engineer.test.mjs; deno test runs with no
// read permission.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  ACTOR, VERSION, PROFILES, NO_PREFERENCE, requirementQuestions, parseRequirementAnswer, requirementsStep,
  toStored, toAnswers, validateStored, applyEdits, suggestions, forCard, supplierLine, askFor, answerFromReasoned, dateOf, monthsOf,
  type Answers, type Ans, type Reasoner, type ReqQuestion,
} from './intake_requirements.ts';

const NOW = new Date('2026-09-14T10:00:00Z');
const q = (cat: string, key: string) => requirementQuestions(cat).find((x) => x.key === key)!;
const keys = (cat: string) => requirementQuestions(cat).map((x) => x.key);
const ALL = [...Object.keys(PROFILES), 'some-future-trade'];
/** A complete, explicit answer set for any category: the first real option of each question. */
function answerAll(cat: string): Answers {
  const a: Answers = {};
  for (const x of requirementQuestions(cat)) a[x.key] = parseRequirementAnswer(x, x.options[0].en, NOW)!;
  return a;
}

Deno.test('the actor is the sales engineer, and it is what every stored answer is recorded under', () => {
  assertEquals(ACTOR, 'sales_engineer');
  const s = toStored('custom-furniture', answerAll('custom-furniture'), NOW);
  assertEquals(s.recorded_by, 'sales_engineer');
  assertEquals(s.version, VERSION);
  assertEquals(validateStored('custom-furniture', { ...s, recorded_by: 'customer_support' }).missing[0], 'recorded_by');
});

Deno.test('every trade asks all four: a material, installation, warranty and the date, never skipped', () => {
  for (const cat of ALL) {
    const qs = requirementQuestions(cat);
    const kinds = new Set(qs.map((x) => x.kind));
    for (const k of ['material', 'installation', 'warranty', 'required_by']) assert(kinds.has(k as never), `${cat} asks ${k}`);
    assertEquals(qs.slice(-3).map((x) => x.key), ['installation', 'warranty', 'required_by'], `${cat} order`);
  }
  // The trades #608 used to skip now ask, and a trade with no components of its own gets the open question.
  assertEquals(keys('movers'), ['material.main', 'installation', 'warranty', 'required_by']);
  assertEquals(keys('cleaning'), ['material.products', 'installation', 'warranty', 'required_by']);
  assertEquals(keys('engineering-and-architectural-consultancies'), ['material.main', 'installation', 'warranty', 'required_by']);
  assertEquals(keys('custom-furniture'), ['material.top_body', 'material.legs_base', 'material.hardware', 'installation', 'warranty', 'required_by']);
});

Deno.test('explicit "not needed" answers exist, and every question can be answered by a tap in both languages', () => {
  const inst = q('painting', 'installation').options.map((o) => o.v);
  assertEquals(inst, ['yes', 'supply_only', 'not_needed', 'not_sure']);
  assertEquals(q('painting', 'warranty').options.map((o) => o.v), ['yes_12', 'yes_24', 'yes_60', 'not_needed', 'not_sure']);
  for (const cat of ALL) for (const x of requirementQuestions(cat)) {
    assert(/[؀-ۿ]/.test(x.ar) && /[؀-ۿ]/.test(x.label_ar), `${cat} ${x.key} is in Arabic`);
    for (const o of x.options) assert(o.ar && o.en, `${cat} ${x.key} ${o.v} has both labels`);
    if (x.kind === 'material') assert(x.options.some((o) => o.v === NO_PREFERENCE.v), `${cat} ${x.key} offers No preference`);
    else assert(x.options.length >= 4, `${cat} ${x.key} has its explicit answers`);
  }
});

Deno.test('a request cannot post with ANY of the four unanswered, in any trade', () => {
  for (const cat of ALL) {
    const full = answerAll(cat);
    assertEquals(validateStored(cat, toStored(cat, full, NOW)), { ok: true, missing: [] }, cat + ' complete');
    for (const k of Object.keys(full)) {
      const { [k]: _drop, ...rest } = full;
      assertEquals(validateStored(cat, toStored(cat, rest, NOW)).missing, [k], `${cat} without ${k}`);
    }
  }
  assertEquals(validateStored('flooring', null).ok, false);
  const v1 = { ...toStored('flooring', answerAll('flooring'), NOW), version: 1 };
  assert(validateStored('flooring', v1).missing.includes('recorded_by'), 'a version-1 answer set is asked again, not trusted');
  const noPeriod = toStored('flooring', answerAll('flooring'), NOW); noPeriod.warranty = { required: 'yes', min_months: null };
  assertEquals(validateStored('flooring', noPeriod).missing, ['warranty']);
});

/** A reasoner that answers from a table (question key -> answer), records what it was asked, and can be held. */
function reasoner(table: Record<string, Ans | null>, o: { held?: boolean } = {}) {
  const asked: [string, boolean][] = [];
  const fn: Reasoner = (x: ReqQuestion, justAsked: boolean) => { asked.push([x.key, justAsked]); return Promise.resolve(o.held ? undefined : (x.key in table ? table[x.key] : null)); };
  return { fn, asked };
}

Deno.test('a trade suggestion is shown, never recorded: the customer confirms it with a tap', async () => {
  const st = await requirementsStep('cleaning', { 'material.products': { v: 'eco' } }, null, '', {}, 'en', NOW);
  assertEquals(st.next!.key, 'installation');
  assertEquals(st.next!.suggested, 'Not needed for this job');
  assert(st.next!.text.includes('Suggested for this job: Not needed for this job. Tap it to confirm'));
  assertEquals(st.answers.installation, undefined, 'the suggestion is not an answer');
  const done = await requirementsStep('cleaning', st.answers, 'installation', 'Not needed for this job', {}, 'en', NOW);
  assertEquals(done.answers.installation, { v: 'not_needed' });
  assertEquals(done.next!.suggested, 'Not needed');
  const ar = await requirementsStep('cleaning', done.answers, null, '', {}, 'ar', NOW);
  assert(ar.next!.text.includes('المقترح لهذا العمل: غير مطلوب'));
});

Deno.test('the checklist suggests only what it recorded AS ONE OF THE OPTIONS; its free text is never read for a suggestion', () => {
  assertEquals(suggestions('carpentry', { material_finish: 'Laminate' }, NOW)['material.finish'], { v: 'laminate' });
  // "Supply + installation" and "2-4 weeks" are words; a suggestion is not worth reading them, so none is made.
  const sug = suggestions('carpentry', { supply_install: 'Supply + installation', timeline: '2-4 weeks', material_finish: 'shiny white' }, NOW);
  assertEquals([sug.installation, sug.required_by, sug['material.finish']], [undefined, undefined, undefined]);
});

Deno.test('a tapped option, in either language, is the answer without asking anyone; an ISO date is a date', () => {
  const legs = q('custom-furniture', 'material.legs_base');
  assertEquals(parseRequirementAnswer(legs, 'Steel', NOW), { v: 'steel' });
  assertEquals(parseRequirementAnswer(legs, 'حديد (ستيل)', NOW), { v: 'steel' });
  assertEquals(parseRequirementAnswer(q('custom-furniture', 'installation'), 'توريد فقط، بدون تركيب', NOW), { v: 'supply_only' });
  assertEquals(parseRequirementAnswer(q('custom-furniture', 'warranty'), 'Yes, at least 2 years', NOW), { v: 'yes', min_months: 24 });
  assertEquals(parseRequirementAnswer(q('custom-furniture', 'required_by'), 'Within 1 month', NOW), { v: 'date', date: '2026-10-14', text: 'Within 1 month' });
  assertEquals(parseRequirementAnswer(q('carpentry', 'required_by'), 'By 2026-10-12', NOW)!.date, '2026-10-12');
  // Typed words are NOT read here — each of these once decided an answer by a word list.
  for (const [key, text] of [['material.legs_base', "I don't care"], ['material.legs_base', 'brushed brass'], ['installation', 'yes please'], ['installation', 'not needed'],
    ['warranty', 'yes, 3 years minimum'], ['warranty', 'مش محتاج'], ['required_by', 'asap']] as const) {
    assertEquals(parseRequirementAnswer(q('custom-furniture', key), text, NOW), null, `${key}: "${text}" is reasoned, not matched`);
  }
});

Deno.test('typed words are reasoned: the asked question first, then what the customer already said, stopping at the first unanswered', async () => {
  const r = reasoner({ 'material.top_body': { v: 'glass' }, 'material.legs_base': { v: 'other', note: 'brushed brass' }, 'material.hardware': null });
  const st = await requirementsStep('custom-furniture', {}, 'material.top_body', 'a glass top please', {}, 'en', NOW, r.fn);
  assertEquals(st.answers['material.top_body'], { v: 'glass' });
  assertEquals(st.answers['material.legs_base'], { v: 'other', note: 'brushed brass' });
  assertEquals(st.next!.key, 'material.hardware');
  assertEquals(r.asked, [['material.top_body', true], ['material.legs_base', false], ['material.hardware', false]], 'stops at the first question not answered');
  // a reasoned "not answered" to the question just asked: asked again, never guessed
  const again = await requirementsStep('custom-furniture', {}, 'installation', 'the kitchen is on the first floor', {}, 'en', NOW, reasoner({ installation: null }).fn);
  assert(again.retry && !again.held);
  assertEquals(again.answers.installation, undefined);
});

Deno.test('held: nothing is filled from typed words, the question stays open to tap, and nothing else is asked of the model', async () => {
  const r = reasoner({}, { held: true });
  const st = await requirementsStep('custom-furniture', {}, 'installation', 'yes please install it', {}, 'en', NOW, r.fn);
  assert(st.held && st.retry);
  assertEquals(st.answers, {});
  assertEquals(st.next!.key, 'material.top_body');
  assertEquals(r.asked, [['installation', true]], 'held once: the rest is not asked');
  // a tap still works under the hold — no model is needed for it
  const tap = await requirementsStep('custom-furniture', {}, 'installation', 'Yes, install it', {}, 'en', NOW, r.fn);
  assertEquals(tap.answers.installation, { v: 'yes' });
});

Deno.test('the reasoned choice becomes an answer: options, own words, a period, a date — and "not answered" is nothing', () => {
  const legs = q('custom-furniture', 'material.legs_base');
  assertEquals(answerFromReasoned(legs, 'no_preference', {}, NOW), { v: 'no_preference' });
  assertEquals(answerFromReasoned(legs, 'other', { note: { value: 'brushed brass', evidence: 'legs in brushed brass' } }, NOW), { v: 'other', note: 'brushed brass' });
  assertEquals(answerFromReasoned(legs, 'other', {}, NOW), null, 'own words with no words is not an answer');
  const war = q('custom-furniture', 'warranty');
  assertEquals(answerFromReasoned(war, 'yes_period', { period: { value: '3 years', evidence: 'a 3 years warranty' } }, NOW), { v: 'yes', min_months: 36 });
  assertEquals(answerFromReasoned(war, 'yes_period', { period: { value: 'a long time', evidence: 'for a long time' } }, NOW), null);
  const when = q('custom-furniture', 'required_by');
  assertEquals(answerFromReasoned(when, 'date', { date: { value: '30 November 2026', evidence: 'finish by 30 November 2026' } }, NOW)!.date, '2026-11-30');
  assertEquals(answerFromReasoned(when, 'date', { date: { value: '15/11/2026', evidence: 'by 15/11/2026' } }, NOW)!.date, '2026-11-15');
  assertEquals(answerFromReasoned(when, 'flexible', {}, NOW), { v: 'flexible', date: null, text: 'Flexible, no fixed date' });
  assertEquals(answerFromReasoned(q('custom-furniture', 'installation'), 'not_answered', {}, NOW), null);
  assertEquals([dateOf('2020-01-01', NOW), monthsOf('18 months'), monthsOf('two years')], [null, 18, null], 'a past date is not a deadline; a number word is not parsed');
});

Deno.test('the question as think() is asked it: every option, "not answered", and the free part only where an option needs one', () => {
  const inst = askFor(q('custom-furniture', 'installation'));
  assertEquals(inst.options.map((o) => o.id), ['yes', 'supply_only', 'not_needed', 'not_sure']);
  assertEquals(inst.fields, undefined);
  const legs = askFor(q('custom-furniture', 'material.legs_base'));
  assert(legs.options.some((o) => o.id === 'other' && o.meaning.includes('decision.fields.note')));
  assertEquals(legs.fields?.map((f) => f.key), ['note']);
  assertEquals(askFor(q('custom-furniture', 'required_by')).fields?.map((f) => f.key), ['date']);
});

Deno.test('an earlier answer that is no longer valid (version 1 "no") is asked again', async () => {
  const st = await requirementsStep('flooring', { ...answerAll('flooring'), installation: { v: 'no' } }, null, '', {}, 'en', NOW);
  assertEquals(st.next!.key, 'installation');
  assertEquals(st.answers.installation, undefined);
});

Deno.test('summary-card edits are taps, re-read and validated; the supplier line never carries a private note', () => {
  const base = toStored('custom-furniture', { ...answerAll('custom-furniture'), 'material.legs_base': { v: 'other', note: 'brass like my neighbour Ahmed has' } }, NOW);
  const { stored, invalid } = applyEdits('custom-furniture', base, { 'material.legs_base': 'Acrylic', installation: 'no', nope: 'x' }, NOW);
  assertEquals(invalid, ['installation', 'nope']);
  assertEquals(stored.materials.find((m) => m.component === 'legs_base')!.choice, 'acrylic');
  const line = supplierLine(base);
  assert(line.includes('Legs or base: their own specification (see the brief)'));
  assert(!line.includes('Ahmed'));
  assertEquals(forCard('custom-furniture', toAnswers(base), 'ar').find((c) => c.key === 'installation')!.answer, 'نعم، مع التركيب');
});
