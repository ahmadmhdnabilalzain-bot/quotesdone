// THE RANKING IS THE REVENUE EVENT, SO A WRONG RANKING IS THE EXPENSIVE FAILURE.
//
// quote_comparison decides which supplier the customer is shown first, and the customer pays 3% of
// the quote he reveals. Measured 8-22 Sep 2026: 2,455 of the 3,207 calls the estate has ever routed
// were this one class, and it is ~92% of the projected monthly bill. On 23 Sep 2026
// (founder_instruction 841) its model moved from anthropic/claude-sonnet-5 to
// qwen/qwen3.8-max-0902, and on 23 Sep 2026 again (founder_instruction 854) to openai/gpt-5.6-sol.
// Neither has ever been measured on this estate for anything.
//
// The failure that costs money is not a crash. It is a model handed two quotations whose scopes do
// not overlap — supply only against supply-and-install, 120 m2 against 300 m2, a rate against a
// lump sum — that invents a common basis and ranks them anyway. A crash is visible; that answer
// reads as helpful and is a wrong recommendation somebody pays to act on.
//
// WHAT THIS CHECK MEASURES, AND WHAT IT DOES NOT.
// It is a SOURCE check, deliberately. scripts/checks runs with no database token in CI, and
// llm_route_health.open_until is 2126-08-15, so no check may call a model: a check that needed one
// would be skipped in CI and would prove nothing in the only place it runs. So it asserts the three
// things that can be asserted without a model, the same way
// scripts/checks/the_triage_answer_fits_its_route.test.mjs reads its ceiling out of the owning SQL:
//   1. the prompt CONTAINS a refusal contract — words a grep can find, naming the key the code reads;
//   2. the code TREATS a refusal as a refusal — it strips the ranking keys, so a model that says
//      "not comparable" and fills top3 anyway cannot have that ranking reach the customer. This is
//      drawing_redact's NO_ANSWER pattern (verify_truncated / verify_unparseable / verify_exception
//      all fail CLOSED) applied to the ranking;
//   3. a ZZ DEMO fixture pair of genuinely non-comparable quotes EXISTS in the repository, so the
//      refusal can be replayed by a human or by the nightly journey rather than invented then.
//
// IT DOES NOT MEASURE that gpt-5.6-sol actually refuses. Nothing in this repository can, while the
// hold stands. That is the honest boundary: this check guarantees the contract and the fail-closed
// handling are present, not that the model honours them. The first real non-comparable pair is the
// measurement, and the fixture below is what makes replaying it a minute's work.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const FN = 'supabase/functions/quote_compare/index.ts';
const FIXTURE = 'scripts/fixtures/zz_demo_quotes_that_cannot_be_compared.json';
const src = readFileSync(FN, 'utf8');

test('the prompt tells the model to refuse rather than invent a common basis', () => {
  assert.match(src, /WHEN THE QUOTES CANNOT BE COMPARED/,
    `${FN}'s system prompt carries no refusal contract, so a model handed two quotations for different scopes has been asked only to rank them`);
  assert.match(src, /MUST NOT rank them/,
    'the contract must forbid ranking in words, not merely invite the model to "surface" that quotes differ');
  assert.match(src, /not_comparable_reason/,
    'the refusal must name what differs, or the customer is told "no ranking" with no reason');
  // The refusal keys must be in the declared JSON contract, not only in the prose above it: the
  // model returns STRICT JSON and fills the keys it is given.
  const contract = src.slice(src.indexOf('Return STRICT JSON ONLY'));
  assert.match(contract, /"not_comparable\\": boolean/,
    'not_comparable is described in the prose but is not one of the declared JSON keys, so a model that follows the contract literally has nowhere to put its refusal');
});

test('a refusal is honoured in code and fails closed, not trusted to the prompt', () => {
  assert.match(src, /parsed\.not_comparable === true/,
    `${FN} never reads not_comparable, so a refusal in the model's answer changes nothing the customer sees`);
  // The load-bearing part: the ranking keys are emptied. A model can set not_comparable AND fill
  // top3 — the contradiction must resolve to the safe side without anyone noticing it happened.
  const handler = src.slice(src.indexOf('parsed.not_comparable === true'), src.indexOf('// MODEL-FREE FALLBACK.'));
  assert.ok(handler.length > 0 && handler.length < 4000, 'the refusal handler should sit immediately before the model-free fallback');
  assert.match(handler, /parsed\.top3 = \[\]/, 'a refusal must empty top3; a ranking published beside a refusal is the defect');
  assert.match(handler, /parsed\.best_value_label = null/, 'a refusal must clear best_value_label');
  assert.match(handler, /parsed\.cheapest_label = null/, 'a refusal must clear cheapest_label — "cheapest" across non-comparable scopes is exactly the wrong number to publish');
  assert.match(handler, /logRun\(/, 'a refusal must be recorded, or nobody learns the model is refusing and why');
  assert.match(handler, /ranking_stripped/, 'record whether the model had ranked anyway: that counter is how we find out the new model does not honour the contract');
});

test('a ZZ DEMO pair that genuinely cannot be compared is kept in the repository', () => {
  assert.ok(existsSync(FIXTURE), `${FIXTURE} is missing, so replaying the refusal means inventing a pair at the time — and a pair invented to pass is not evidence`);
  const fx = JSON.parse(readFileSync(FIXTURE, 'utf8'));
  assert.equal(fx.expected.not_comparable, true, 'the fixture must expect a refusal');
  assert.deepEqual(fx.expected.top3, [], 'the fixture must expect no ranking');
  assert.equal(fx.quotes.length, 2, 'two quotations are enough to be non-comparable');
  // It must actually BE non-comparable, or the check is a tautology: different scope basis and a
  // different quantity, stated in the quotes themselves.
  const scopes = fx.quotes.map((q) => String(q.scope).toLowerCase());
  assert.ok(scopes.some((s) => s.includes('supply only')) && scopes.some((s) => s.includes('installation')),
    'the pair must differ in scope basis (supply only vs supply and installation), not merely in price');
  assert.ok(scopes.some((s) => s.includes('120')) && scopes.some((s) => s.includes('300')),
    'the pair must differ in quantity, so no rate can reconcile them');
  // Nothing in a fixture may be able to reach a person.
  const blob = JSON.stringify(fx);
  for (const m of blob.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/g) || []) {
    assert.match(m, /@example\.invalid$/, `${m} is not a reserved address — a fixture must be incapable of reaching a real person, not merely careful`);
  }
  assert.ok(fx.quotes.every((q) => String(q.supplier).startsWith('ZZ DEMO')), 'every supplier in the fixture must carry the ZZ DEMO marker');
});
