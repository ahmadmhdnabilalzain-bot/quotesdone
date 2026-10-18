// The stage-2 interview answers what was ASKED, by key, from a fact sheet (it_engineer, 7 Oct 2026).
// Run fe7ba9c4 sent "standard specification, please assume typical values" after four scripted turns
// and no interview reached ready. This fails if the filler comes back or a key goes unanswered.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { factSheet } from './fact_sheet.mjs';

const KEYS = { // category_specs required keys of the 11 stage-2 trades, read on production 7 Oct 2026
  aluminium: ['element', 'dimensions_qty', 'scope', 'location'], joinery: ['item_type', 'quantity_size', 'finish', 'scope', 'location_floor'],
  electrical: ['scope', 'property_area', 'supply_phase', 'location'], elevators: ['type', 'stops', 'capacity', 'new_mod'],
  flooring: ['floor_type', 'area_sqm', 'areas', 'supply_install', 'removal_levelling'], glazing: ['element', 'dimensions_qty', 'glazing_performance', 'scope', 'location'],
  hvac: ['system_type', 'application_area', 'new_or_replace', 'scope', 'location'], landscaping: ['scope', 'area_sqm', 'location'],
  painting: ['scope', 'area', 'surface_prep', 'location'], plumbing: ['scope', 'fixture_count', 'scope_mode', 'location'],
  waterproofing: ['area', 'issue', 'area_sqm', 'supply_install', 'location'],
};

test('every required checklist key of every stage-2 trade is answered from the sheet, in both languages', () => {
  for (const [trade, keys] of Object.entries(KEYS)) for (const lang of ['en', 'ar']) {
    const f = factSheet(trade, { lang, emirate: 'Sharjah' });
    for (const k of keys) {
      const a = f.answerFor({ required_gate: { missing_keys: [k] } });
      assert.ok(a.startsWith(k + ': '), `${trade}/${lang} ${k} -> ${a.slice(0, 60)}`);
      assert.doesNotMatch(a, /assume typical values/);
    }
  }
});

test('the sales engineer questions get option values; material is the first option or a deliberate not sure', () => {
  const f = factSheet('plumbing', {});
  assert.equal(f.answerFor({ next_question: { key: 'installation' } }), 'yes');
  assert.equal(f.answerFor({ next_question: { key: 'warranty' } }), 'yes_24');
  assert.equal(f.answerFor({ next_question: { key: 'required_by' } }), 'm1');
  assert.equal(f.answerFor({ next_question: { key: 'material.pipes', options: ['PPR', 'No preference'] } }), 'PPR');
  assert.equal(factSheet('plumbing', { notSure: true }).answerFor({ next_question: { key: 'material.pipes', options: ['PPR'] } }), 'Not sure');
});

// Run f4294be8 (12 Oct 2026): the test above passed while `issue` was answered with "Replacement of
// existing items" and `finish` with "Standard commercial grade" - an answer existed, it did not answer
// the question, and C9/C6 were asked 13 times. The answer must carry the fact asked for.
test('waterproofing issue says leak or preventive; joinery finish names a finish, in both languages', () => {
  const ask = (trade, lang, k) => factSheet(trade, { lang }).answerFor({ required_gate: { missing_keys: [k] } });
  assert.match(ask('waterproofing', 'en', 'issue'), /^issue: No leak .*preventive/);
  assert.match(ask('waterproofing', 'ar', 'issue'), /^issue: لا يوجد تسرب.*وقائي/);
  assert.match(ask('joinery', 'en', 'finish'), /^finish: Laminate/);
  assert.match(ask('joinery', 'ar', 'finish'), /^finish: لامينيت/);
  const whole = factSheet('waterproofing', {}).answerFor({ missing: ['Is there a leak now, or is this to prevent one?'] });
  assert.match(whole, /leak: No leak/, 'a question text gets the whole sheet, and the sheet carries the leak fact');
});

test('a question text, never a key, gets the whole sheet, not filler', () => {
  const a = factSheet('aluminium', { emirate: 'Ajman' }).answerFor({ missing: ['Any preference for the glass? Tap one.'] });
  assert.match(a, /location: Villa in Ajman/);
  assert.match(a, /lines: Line 1: aluminium windows x 20, 1200 x 1500 mm/);
});
