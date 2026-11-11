// JOURNEY A READS THE INTAKE'S ANSWER AS THE INTAKE WRITES IT, ANSWERS WHAT IT ASKS, AND JOURNEY B NEVER CALLS A REQUEST
// ROUTING DID NOT SEE A ROUTING RESULT. Seat: sales_engineer. 11 Nov 2026.
//
// MEASURED, nightly run 077cbbfc (10 Nov 2026): "8 turn(s), status=held, readiness=0", then "Supplier routing: 0 of 3 demo
// suppliers matched by the product". The run log (agent_runs, inquiry_intake, 22:11:15Z) held the truth: status_computed held,
// readiness 75. No gate had refused a supplier: the request was the harness's fallback (the portal never posted it), with no
// routing record, so fn_match_capability was never asked. Three harness faults, each replayed here:
//   1. readiness is an object on the wire ({filled, required, score}) and Number() of it is NaN -> 0;
//   2. the intake's own next_question was never answered (six fixed sentences + the first chip), so a spec stayed open for
//      slots.ts MAX_OPEN_TURNS and the intake held;
//   3. the routing step printed "0/3 matched by the product" for a request routing never saw.
// Fails on origin/main 57418c095: scripts/e2e/intake_answers.mjs does not exist and journeys.mjs reads Number(j.readiness).
//   node --test scripts/checks/journey_a_reads_the_intake_and_answers_what_it_asks.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const JOURNEYS = readFileSync('scripts/e2e/journeys.mjs', 'utf8');
const HANDLE = readFileSync('supabase/functions/inquiry_intake/handle.ts', 'utf8');

test('readiness is read from the shape inquiry_intake answers with', async () => {
  const { readinessOf } = await import('../e2e/intake_answers.mjs');
  // the wire shape of a normal turn (handle.ts final J(...)): an object AND readiness_score
  assert.match(HANDLE, /readiness: \{ filled: readinessFields\.filled/);
  assert.match(HANDLE, /readiness_score: Number\(out\.readiness\) \|\| 0/);
  assert.equal(readinessOf({ readiness: { filled: 3, required: 4, score: 75 }, readiness_score: 75 }), 75);
  assert.equal(readinessOf({ readiness: { filled: 3, required: 4, score: 75 } }), 75);
  assert.equal(readinessOf({ readiness: 40 }), 40);
  assert.equal(readinessOf({}, 55), 55);
  // the 077cbbfc reading, which this replaces
  assert.equal(Number({ filled: 3, required: 4, score: 75 }) || 0, 0);
  assert.doesNotMatch(JOURNEYS, /readiness = Number\(j2?\.readiness/, 'journeys.mjs must read readiness through readinessOf');
});

test('the question the intake asks is answered with the fact it asks for, or with one of its own options', async () => {
  const { answerFor } = await import('../e2e/intake_answers.mjs');
  assert.match(answerFor({ key: 'warranty', text: 'What warranty do you need?' }), /2 year/);
  assert.match(answerFor({ key: 'glass_type', text: 'Which glass do you need?' }), /6mm \+ 12mm/);
  assert.match(answerFor({ key: 'required_by', text: 'By when do you need it?' }), /30 November 2026/);
  assert.equal(answerFor({ key: 'opening', text: 'Which opening type?', options: ['Not sure', 'Sliding', 'Casement'] }), 'Sliding');
  assert.equal(answerFor({ key: 'x', text: 'Anything odd?', options: ["Don't know", 'Option A'] }), 'Option A');
  assert.equal(answerFor(null), '');
  // and journey a sends it, inside its budget, after the fixed sentences
  const at = JOURNEYS.indexOf('WHAT IT STILL ASKS, ANSWERED');
  assert.ok(at > 0 && at < JOURNEYS.indexOf("'the sales engineer interview reaches ready'"), 'journey a must answer the open question before judging the interview');
  assert.match(JOURNEYS.slice(at, at + 600), /answerFor\(last\.next_question\)/);
  assert.match(JOURNEYS.slice(at, at + 600), /Date\.now\(\) <= deadline/);
});

test('a held interview says why, from the harness subject\'s own held_reason', async () => {
  const { heldDetail } = await import('../e2e/intake_answers.mjs');
  assert.match(HANDLE, /\.\.\.heldReasonFor\(status, email, slotExhausted\)/);
  assert.equal(heldDetail({ status: 'held', held_reason: 'specs_unanswered: glass_type', missing_keys: ['glass_type'], next_question: { key: 'glass_type' } }),
    '; held_reason=specs_unanswered: glass_type; open=glass_type; next=glass_type');
  assert.equal(heldDetail({ status: 'ready' }), '');
  assert.match(JOURNEYS, /readiness=\$\{readiness\}\$\{heldDetail\(last\)\}/);
});

test('routing that never ran is reported as never run, and is still not a pass', () => {
  const at = JOURNEYS.indexOf("rep.step(J, 'routing invited the demo suppliers'");
  assert.ok(at > 0);
  const step = JOURNEYS.slice(JOURNEYS.lastIndexOf('const neverRouted', at), at + 900);
  assert.match(step, /const neverRouted = direct\.length > 0 && ctx\.requestVia === 'fallback' && !routing && !notPosted/);
  assert.match(step, /routing did not run: the portal did not post this request/);
  // the verdict is unchanged: only PASS when every supplier was matched, SKIP only for another run's contention or the measured hold
  assert.match(step, /direct\.length === 0 \? 'PASS' : concurrentOnly \|\| notPosted \? 'SKIP' : 'FAIL'/);
});
