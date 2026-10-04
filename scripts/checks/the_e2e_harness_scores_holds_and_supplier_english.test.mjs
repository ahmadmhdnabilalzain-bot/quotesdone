// THE E2E HARNESS SCORES A HELD ARABIC DOCUMENT AS HELD AND A SUPPLIER DOCUMENT AS ENGLISH (it_engineer, E2E stage 1
// D4, 30 Sep 2026). Stage 1 filed FAIL for customer_api's HTTP 202 arabic_held under the model hold, and FAIL for a
// supplier inquiry PDF that was correctly English. Offline, over the harness source.
//   node --test scripts/checks/the_e2e_harness_scores_holds_and_supplier_english.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const audit = readFileSync('scripts/e2e/journey_audit_buttons.mjs', 'utf8');
const run = readFileSync('scripts/e2e/run.mjs', 'utf8');

test('arabic_held is HELD only for exactly that answer and only while the hold is on', () => {
  assert.match(audit, /lang === 'ar' && res\.status === 202 && res\.json\?\.code === 'arabic_held' \? await modelHold\(\) : null/);
  assert.match(audit, /pdfVerdict\(f, lang\) \? 'PASS' : held \? 'HELD' : 'FAIL'/);
  assert.match(run, /count\('HELD'\)/, 'the report does not count HELD steps');
  assert.match(run, /ok: count\('FAIL'\) === 0/, 'a HELD step must not turn the run red, and a FAIL still must');
});

test('a supplier inquiry PDF is expected in English whatever language is asked', () => {
  assert.match(audit, /pdfVerdict\(f, 'en'\) && !leaked\.length \? 'PASS' : 'FAIL'/);
});
