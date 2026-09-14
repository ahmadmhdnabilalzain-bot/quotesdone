// intake_requirements: every trade asks all four, nothing is assumed, and the post gate.
// deno test supabase/functions/_shared/intake_requirements.test.ts
//
// The founder, 14 Sep 2026: "for installation for example, we need to ask, cause maybe the customer
// will forget. we don't assume stuff". The source-level half (inquiry_intake answers as ACTOR and names
// no other seat) is scripts/checks/the_intake_is_the_sales_engineer.test.mjs; deno test runs with no
// read permission.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  ACTOR, VERSION, PROFILES, NO_PREFERENCE, requirementQuestions, parseRequirementAnswer, requirementsStep,
  toStored, toAnswers, validateStored, applyEdits, suggestions, forCard, supplierLine, type Answers,
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

Deno.test('a trade suggestion is shown, never recorded: the customer confirms it', () => {
  const st = requirementsStep('cleaning', { 'material.products': { v: 'eco' } }, null, '', {}, 'en', NOW);
  assertEquals(st.next!.key, 'installation');
  assertEquals(st.next!.suggested, 'Not needed for this job');
  assert(st.next!.text.includes('Suggested for this job: Not needed for this job. Tap it to confirm'));
  assertEquals(st.answers.installation, undefined, 'the suggestion is not an answer');
  assert(!st.complete);
  const done = requirementsStep('cleaning', st.answers, 'installation', 'Not needed for this job', {}, 'en', NOW);
  assertEquals(done.answers.installation, { v: 'not_needed' });
  assertEquals(done.next!.key, 'warranty');
  assertEquals(done.next!.suggested, 'Not needed');
  const ar = requirementsStep('cleaning', done.answers, null, '', {}, 'ar', NOW);
  assert(ar.next!.text.includes('المقترح لهذا العمل: غير مطلوب'));
});

Deno.test('what the category checklist heard is a suggestion too, not a silent answer', () => {
  const sug = suggestions('carpentry', { material_finish: 'Laminate', supply_install: 'Supply + installation', timeline: '2-4 weeks' }, NOW);
  assertEquals(sug['material.finish'], { v: 'laminate' });
  assertEquals(sug.installation, { v: 'yes' });
  assertEquals(sug.required_by!.date, '2026-10-12');
  assertEquals(suggestions('custom-furniture', { installation: 'Supply only / delivery only' }, NOW).installation, { v: 'supply_only' });
  const st = requirementsStep('carpentry', { 'material.board': { v: 'plywood' } }, null, '', { material_finish: 'Laminate' }, 'en', NOW);
  assertEquals(st.next!.key, 'material.finish', 'still asked');
  assertEquals(st.next!.suggested, 'Laminate');
  const dateStep = requirementsStep('carpentry', { ...answerAll('carpentry'), required_by: undefined as never }, null, '', { timeline: '2-4 weeks' }, 'en', NOW);
  assertEquals(dateStep.next!.suggested, 'By 2026-10-12');
  assert(dateStep.next!.options.includes('By 2026-10-12'), 'the suggestion can be tapped');
  assertEquals(parseRequirementAnswer(q('carpentry', 'required_by'), 'By 2026-10-12', NOW)!.date, '2026-10-12');
});

Deno.test('answers: chips in both languages, own words, and a bare "no" to installation is asked again', () => {
  const legs = q('custom-furniture', 'material.legs_base');
  assertEquals(parseRequirementAnswer(legs, 'Steel', NOW), { v: 'steel' });
  assertEquals(parseRequirementAnswer(legs, 'حديد (ستيل)', NOW), { v: 'steel' });
  assertEquals(parseRequirementAnswer(legs, "I don't care", NOW), { v: 'no_preference' });
  assertEquals(parseRequirementAnswer(legs, 'brushed brass', NOW), { v: 'other', note: 'brushed brass' });
  assertEquals(parseRequirementAnswer(legs, 'Other: brushed brass', NOW), { v: 'other', note: 'brushed brass' });

  const inst = q('custom-furniture', 'installation');
  assertEquals(parseRequirementAnswer(inst, 'Supply only, no installation', NOW), { v: 'supply_only' });
  assertEquals(parseRequirementAnswer(inst, 'توريد فقط، بدون تركيب', NOW), { v: 'supply_only' });
  assertEquals(parseRequirementAnswer(inst, 'not needed', NOW), { v: 'not_needed' });
  assertEquals(parseRequirementAnswer(inst, 'غير مطلوب لهذا العمل', NOW), { v: 'not_needed' });
  assertEquals(parseRequirementAnswer(inst, 'yes please', NOW), { v: 'yes' });
  assertEquals(parseRequirementAnswer(inst, 'not sure', NOW), { v: 'not_sure' });
  assertEquals(parseRequirementAnswer(inst, 'no', NOW), null, '"no" could be supply only or not needed: asked again');

  const war = q('custom-furniture', 'warranty');
  assertEquals(parseRequirementAnswer(war, 'Yes, at least 2 years', NOW), { v: 'yes', min_months: 24 });
  assertEquals(parseRequirementAnswer(war, 'yes, 3 years minimum', NOW), { v: 'yes', min_months: 36 });
  assertEquals(parseRequirementAnswer(war, 'Not needed', NOW), { v: 'not_needed', min_months: null });
  assertEquals(parseRequirementAnswer(war, 'غير مطلوب', NOW), { v: 'not_needed', min_months: null });
  assertEquals(parseRequirementAnswer(war, 'yes', NOW), null, 'yes with no minimum period is asked again');

  const when = q('custom-furniture', 'required_by');
  assertEquals(parseRequirementAnswer(when, 'Within 1 month', NOW), { v: 'date', date: '2026-10-14', text: 'Within 1 month' });
  assertEquals(parseRequirementAnswer(when, '15/11/2026', NOW)!.date, '2026-11-15');
  assertEquals(parseRequirementAnswer(when, 'hmm', NOW), null);
});

Deno.test('an earlier answer that is no longer valid (version 1 "no") is asked again', () => {
  const st = requirementsStep('flooring', { ...answerAll('flooring'), installation: { v: 'no' } }, null, '', {}, 'en', NOW);
  assertEquals(st.next!.key, 'installation');
  assertEquals(st.answers.installation, undefined);
});

Deno.test('summary-card edits are re-read and validated; the supplier line never carries a private note', () => {
  const base = toStored('custom-furniture', { ...answerAll('custom-furniture'), 'material.legs_base': { v: 'other', note: 'brass like my neighbour Ahmed has' } }, NOW);
  const { stored, invalid } = applyEdits('custom-furniture', base, { 'material.legs_base': 'Acrylic', installation: 'no', nope: 'x' }, NOW);
  assertEquals(invalid, ['installation', 'nope']);
  assertEquals(stored.materials.find((m) => m.component === 'legs_base')!.choice, 'acrylic');
  const line = supplierLine(base);
  assert(line.includes('Legs or base: their own specification (see the brief)'));
  assert(!line.includes('Ahmed'));
  assertEquals(forCard('custom-furniture', toAnswers(base), 'ar').find((c) => c.key === 'installation')!.answer, 'نعم، مع التركيب');
});
