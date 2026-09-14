// intake_requirements — which questions each trade gets, how answers are read, and the post gate.
// deno test supabase/functions/_shared/intake_requirements.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  ACTOR, PROFILES, DEFAULT_PROFILE, NO_PREFERENCE, requirementQuestions, parseRequirementAnswer, requirementsStep,
  toStored, toAnswers, validateStored, applyEdits, prefill, forCard, supplierLine, type Answers,
} from './intake_requirements.ts';

const NOW = new Date('2026-09-14T10:00:00Z');
const q = (cat: string, key: string) => requirementQuestions(cat).find((x) => x.key === key)!;
const keys = (cat: string) => requirementQuestions(cat).map((x) => x.key);

// The source-level half (inquiry_intake answers as ACTOR and names no other seat) is
// scripts/checks/the_intake_is_the_sales_engineer.test.mjs: deno test runs with no read permission.
Deno.test('the actor is the sales engineer, and it is what every stored answer is recorded under', () => {
  assertEquals(ACTOR, 'sales_engineer');
  const s = toStored('custom-furniture', { required_by: { v: 'flexible', date: null, text: 'Flexible' } }, NOW);
  assertEquals(s.recorded_by, 'sales_engineer');
  assertEquals(validateStored('custom-furniture', { ...s, recorded_by: 'customer_support' }).missing[0], 'recorded_by');
});

Deno.test('question selection: a custom table asks top, legs, hardware, then installation, warranty and date', () => {
  assertEquals(keys('custom-furniture'), ['material.top_body', 'material.legs_base', 'material.hardware', 'installation', 'warranty', 'required_by']);
  const legs = q('custom-furniture', 'material.legs_base');
  for (const want of ['Steel', 'Wood', 'Acrylic', 'No preference']) assert(legs.options.some((o) => o.en === want), 'legs offer ' + want);
  assertEquals(keys('flooring'), ['material.grade', 'installation', 'warranty', 'required_by']);
  assertEquals(keys('carpentry-joinery'), ['material.board', 'material.finish', 'material.hardware', 'installation', 'warranty', 'required_by']);
  assertEquals(keys('painting'), ['material.brand', 'material.finish', 'warranty', 'required_by']);
});

Deno.test('applicability: pure services skip installation, trades with no warranty skip warranty', () => {
  assertEquals(keys('cleaning'), ['material.products', 'required_by']);
  assertEquals(keys('movers'), ['required_by']);
  assertEquals(keys('engineering-and-architectural-consultancies'), ['required_by']);
  assertEquals(keys('pest'), ['material.treatment', 'warranty', 'required_by'], 'pest control sells a service guarantee but installs nothing');
  assertEquals(keys('waterproofing'), ['material.system', 'warranty', 'required_by']);
  const cl = toStored('cleaning', { 'material.products': { v: 'eco' }, required_by: { v: 'flexible' } }, NOW);
  assertEquals(cl.installation, null);
  assertEquals(cl.warranty, null);
  assertEquals(cl.not_applicable, ['installation', 'warranty']);
});

Deno.test('an unknown category still asks: installation, warranty, one open material question, date', () => {
  assertEquals(keys('some-future-trade'), ['material.main', 'installation', 'warranty', 'required_by']);
  assertEquals(q('some-future-trade', 'material.main').options.map((o) => o.v), ['no_preference']);
  assertEquals(DEFAULT_PROFILE.install && DEFAULT_PROFILE.warranty, true);
});

Deno.test('every question and option exists in Arabic, and every material question offers No preference', () => {
  for (const cat of [...Object.keys(PROFILES), 'unknown-trade']) {
    for (const x of requirementQuestions(cat)) {
      assert(/[؀-ۿ]/.test(x.ar), `${cat} ${x.key} has an Arabic question`);
      assert(/[؀-ۿ]/.test(x.label_ar), `${cat} ${x.key} has an Arabic label`);
      for (const o of x.options) assert(o.ar && o.en, `${cat} ${x.key} ${o.v} has both labels`);
      if (x.kind === 'material') assert(x.options.some((o) => o.v === NO_PREFERENCE.v), `${cat} ${x.key} offers No preference`);
      if (x.kind !== 'material') assert(x.options.length >= 3, `${cat} ${x.key} is answerable by a tap`);
    }
  }
});

Deno.test('answers: tapped chips in both languages, the customer\'s own words, and an explicit not-sure', () => {
  const legs = q('custom-furniture', 'material.legs_base');
  assertEquals(parseRequirementAnswer(legs, 'Steel', NOW), { v: 'steel' });
  assertEquals(parseRequirementAnswer(legs, 'حديد (ستيل)', NOW), { v: 'steel' });
  assertEquals(parseRequirementAnswer(legs, 'wood please', NOW), { v: 'wood' });
  assertEquals(parseRequirementAnswer(legs, "I don't care", NOW), { v: 'no_preference' });
  assertEquals(parseRequirementAnswer(legs, 'لا يهم', NOW), { v: 'no_preference' });
  assertEquals(parseRequirementAnswer(legs, 'brushed brass', NOW), { v: 'other', note: 'brushed brass' });

  const inst = q('custom-furniture', 'installation');
  assertEquals(parseRequirementAnswer(inst, 'No, delivery only', NOW), { v: 'no' });
  assertEquals(parseRequirementAnswer(inst, 'لا، توريد فقط', NOW), { v: 'no' });
  assertEquals(parseRequirementAnswer(inst, 'yes please', NOW), { v: 'yes' });
  assertEquals(parseRequirementAnswer(inst, 'not sure', NOW), { v: 'not_sure' });
  assertEquals(parseRequirementAnswer(inst, 'blue', NOW), null, 'an unreadable answer is asked again, never guessed');

  const war = q('custom-furniture', 'warranty');
  assertEquals(parseRequirementAnswer(war, 'Yes, at least 2 years', NOW), { v: 'yes', min_months: 24 });
  assertEquals(parseRequirementAnswer(war, 'نعم، سنتان على الأقل', NOW), { v: 'yes', min_months: 24 });
  assertEquals(parseRequirementAnswer(war, 'yes, 3 years minimum', NOW), { v: 'yes', min_months: 36 });
  assertEquals(parseRequirementAnswer(war, '18 months', NOW), { v: 'yes', min_months: 18 });
  assertEquals(parseRequirementAnswer(war, 'لا أحتاج ضماناً', NOW), { v: 'no', min_months: null });
  assertEquals(parseRequirementAnswer(war, 'yes', NOW), null, 'yes with no minimum period is not an answer to "for how long"');

  const when = q('custom-furniture', 'required_by');
  assertEquals(parseRequirementAnswer(when, 'Within 1 month', NOW), { v: 'date', date: '2026-10-14', text: 'Within 1 month' });
  assertEquals(parseRequirementAnswer(when, 'خلال أسبوعين', NOW)!.date, '2026-09-28');
  assertEquals(parseRequirementAnswer(when, '15/11/2026', NOW)!.date, '2026-11-15');
  assertEquals(parseRequirementAnswer(when, 'flexible', NOW)!.v, 'flexible');
  assertEquals(parseRequirementAnswer(when, 'hmm', NOW), null);
});

Deno.test('the post gate: every applicable answer present, a warranty has a period, recorded by the sales engineer', () => {
  const full: Answers = { 'material.grade': { v: 'mid' }, installation: { v: 'yes' }, warranty: { v: 'yes', min_months: 12 }, required_by: { v: 'date', date: '2026-10-01', text: 'x' } };
  assertEquals(validateStored('flooring', toStored('flooring', full, NOW)), { ok: true, missing: [] });
  const { warranty: _w, ...noWarranty } = full;
  assertEquals(validateStored('flooring', toStored('flooring', noWarranty, NOW)).missing, ['warranty']);
  const noPeriod = toStored('flooring', full, NOW); noPeriod.warranty = { required: 'yes', min_months: null };
  assertEquals(validateStored('flooring', noPeriod).missing, ['warranty']);
  const foreign = { ...toStored('flooring', full, NOW), recorded_by: 'someone_else' };
  assert(validateStored('flooring', foreign).missing.includes('recorded_by'));
  assertEquals(validateStored('flooring', null).ok, false);
  assertEquals(validateStored('flooring', toStored('flooring', { ...full, 'material.grade': { v: NO_PREFERENCE.v } }, NOW)).ok, true, '"No preference" is an answer');
  assertEquals(toAnswers(toStored('flooring', full, NOW)), { ...full, 'material.grade': { v: 'mid', note: null } }, 'stored -> answers round-trips');
});

Deno.test('the category interview is not asked twice: a stated finish, scope and timeline carry over', () => {
  const pre = prefill('carpentry', { material_finish: 'Laminate', supply_install: 'Supply + installation', timeline: '2-4 weeks' }, NOW);
  assertEquals(pre['material.finish'], { v: 'laminate' });
  assertEquals(pre.installation, { v: 'yes' });
  assertEquals(pre.required_by!.date, '2026-10-12');
  assertEquals(prefill('custom-furniture', { installation: 'Supply only / delivery only' }, NOW).installation, { v: 'no' });
  assertEquals(prefill('carpentry', { material_finish: 'Not sure' }, NOW)['material.finish'], undefined, 'not sure there is asked here');
});

Deno.test('one question at a time; an unreadable answer is asked again with retry set', () => {
  let st = requirementsStep('glass', {}, null, '', {}, 'en', NOW);
  assertEquals(st.next!.key, 'material.frame');
  assertEquals(st.remaining.length, 4);
  st = requirementsStep('glass', st.answers, 'material.frame', 'Frameless', {}, 'en', NOW);
  assertEquals(st.next!.key, 'installation');
  st = requirementsStep('glass', st.answers, 'installation', 'purple', {}, 'en', NOW);
  assert(st.retry); assertEquals(st.next!.key, 'installation');
  const ar = requirementsStep('glass', st.answers, 'installation', 'نعم، مع التركيب', {}, 'ar', NOW);
  assertEquals(ar.next!.text, 'هل تحتاج ضماناً، وما أقل مدة تقبلها؟');
  assert(ar.next!.options.includes('لست متأكداً'));
});

Deno.test('the summary card edits are re-read and validated; the supplier line never carries a private note', () => {
  const base = toStored('custom-furniture', { 'material.top_body': { v: 'solid_wood' }, 'material.legs_base': { v: 'other', note: 'brass like my neighbour Ahmed has' }, 'material.hardware': { v: 'no_preference' }, installation: { v: 'yes' }, warranty: { v: 'no', min_months: null }, required_by: { v: 'flexible' } }, NOW);
  const { stored, invalid } = applyEdits('custom-furniture', base, { 'material.legs_base': 'Acrylic', warranty: 'banana', nope: 'x' }, NOW);
  assertEquals(invalid, ['warranty', 'nope']);
  assertEquals(stored.materials.find((m) => m.component === 'legs_base')!.choice, 'acrylic');
  const line = supplierLine(base);
  assert(line.includes('Legs or base — their own specification (see the brief)'));
  assert(!line.includes('Ahmed'));
  const card = forCard('custom-furniture', toAnswers(base), 'ar');
  assertEquals(card.find((c) => c.key === 'installation')!.answer, 'نعم، مع التركيب');
  assertEquals(base.display.ar.find((r) => r.key === 'required_by')!.value, 'مرن، لا يوجد موعد محدد');
});
