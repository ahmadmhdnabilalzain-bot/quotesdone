// THE "NEEDS A PERSON" CHOICE NAMES A SAFETY DANGER (it_engineer, 2 Nov 2026; #1392, customer_support's clause).
// A customer who reports an injury, a fire, gas, an electrical danger or a structural risk must reach a person even when
// they never ask for one, and a question that merely mentions safety as a topic must not. The model's behaviour on real
// messages is graded by scripts/e2e/the_widget_person_check_is_one_small_real_call.ts (ruling 1260: no stubbed model);
// this check keeps the clause itself from being edited away, in both options.
//   node --test scripts/checks/the_needs_a_person_choice_names_a_safety_danger.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../../supabase/functions/_shared/reasoned_decisions.ts', import.meta.url), 'utf8');
const option = (id) => new RegExp(`\\{ id: '${id}', meaning: '((?:[^'\\\\]|\\\\.)*)' \\}`).exec(src)?.[1] ?? '';

test('needs_a_person names every kind of safety danger the customer can report', () => {
  const m = option('needs_a_person');
  assert.ok(m, 'needs_a_person option not found in NEEDS_PERSON_OPTIONS');
  assert.match(m, /report a safety danger/i);
  for (const word of ['injury', 'fire', 'gas', 'electrical danger', 'structural risk']) assert.ok(m.includes(word), `needs_a_person no longer names: ${word}`);
  // the older reasons stay
  for (const word of ['speak to a human', 'complain', 'refund', 'legal action']) assert.ok(m.includes(word), `needs_a_person lost: ${word}`);
});

test('a question that only mentions safety, law or complaints as a topic still needs no person', () => {
  const m = option('no_person');
  assert.match(m, /merely mentions law, legality, refunds or complaints as a topic/);
});
