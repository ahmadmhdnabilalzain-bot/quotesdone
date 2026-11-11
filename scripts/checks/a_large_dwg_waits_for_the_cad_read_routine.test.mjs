// A LARGE DWG WAITS FOR THE CAD READ ROUTINE, AND THE NIGHTLY JOURNEY EXPECTS EXACTLY THAT. Seat: sales_engineer. 11 Nov 2026.
//
// MEASURED, nightly run 077cbbfc (10 Nov 2026): every_drawing_format_is_read reported "the CAD worker read it ... status queued
// after 258 s, 0 lines", then was SIGTERMed at drawing_journeys_into_report's 12-minute ceiling. Since #1908 (lib/drawings.ts
// CAD_READER_ROUTINE) nothing starts a worker: GitHub Actions is off (ledger 1564) and a queued job is read by the "QuotesDone —
// CAD read worker (every 2 h)" routine, which runs scripts/cad_read_worker.ts and claims every queued job (fn_cad_read_claim).
// The harness still polled four minutes for a worker nobody starts. This holds the harness to the designed path, and holds
// the product to it too: no dispatch to GitHub comes back.
//   node --test scripts/checks/a_large_dwg_waits_for_the_cad_read_routine.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { functionSource } from '../lib/function_sources.mjs';

const H = readFileSync('scripts/e2e/every_drawing_format_is_read.mjs', 'utf8');
const at = H.indexOf("const big = await drawing(bigBytes");
const big = H.slice(at, H.indexOf('THE ELEMENT SCORE PER FORMAT', at));

test('without --run-worker the large DWG is expected queued, claimable by the routine, and the customer told who has it', () => {
  assert.ok(big.length > 500, 'the large-DWG block was not found');
  const plain = big.slice(big.indexOf('if (!RUN_WORKER) {'), big.indexOf('} else {'));
  assert.ok(plain.length > 100, 'the default (no worker) branch is missing');
  assert.match(plain, /the large DWG waits for the CAD read routine/);
  assert.match(plain, /held_for === 'sales_engineer'/);
  assert.match(plain, /proname = 'fn_cad_read_claim'/);
  assert.doesNotMatch(plain, /setTimeout/, 'the default branch must not wait for a worker nobody starts');
  assert.doesNotMatch(big, /i < 24/, 'the 4-minute poll is gone');
});

test('with --run-worker the harness is the routine\'s run, and the job must then be read', () => {
  const worker = big.slice(big.indexOf('} else {'));
  assert.match(worker, /scripts\/cad_read_worker\.ts/);
  assert.match(worker, /'the CAD worker read it and the customer receives the take-off', st\?\.json\?\.status === 'done' && n > 0/);
});

test('the product starts no worker: the routine reads the queue and nothing is dispatched to GitHub', () => {
  const api = functionSource('customer_api');
  assert.match(api, /export const CAD_READER_ROUTINE = 'QuotesDone — CAD read worker \(every 2 h\)'/);
  assert.match(api, /export const CAD_READER_EVERY_MS = 2 \* 60 \* 60_000/);
  // code only: the routine's own header explains that nothing reaches GitHub, in words this pattern would otherwise match
  const code = api.split('\n').filter((l) => !/^\s*(\/\/|\*)/.test(l)).join('\n');
  assert.doesNotMatch(code, /api\.github\.com|workflow_dispatch|dispatches['"`]/, 'a GitHub Actions dispatch came back');
});
