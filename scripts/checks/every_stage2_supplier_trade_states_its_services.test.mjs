// EVERY STAGE-2 SUPPLIER TRADE STATES ITS SERVICES (19 Oct 2026, it_engineer).
//
// MEASURED, run 0a717394: 6 of 9 requests (electrical, plumbing, flooring, joinery, glazing,
// landscaping) routed to nobody, agent_runs 'match' candidates=0. fn_match_capability gates on
// services when the request names one, and fn_services_effective('{}', [trade], '{}') is '{}' for
// every trade, so a supplier that confirmed no service is never a candidate. fixtures.mjs only had a
// service sentence for aluminium, gypsum and painting, so the other demo suppliers confirmed none.
// Not time-dependent: hvac passed because its brief happened to name no service.
//
// WHAT THIS FAILS ON. A trade in stage2's SUPPLIER_TRADES with no SERVICE_WORDS sentence in fixtures.mjs.
//   node --test scripts/checks/every_stage2_supplier_trade_states_its_services.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (p) => readFileSync(fileURLToPath(new URL(p, import.meta.url)), 'utf8');

test('every stage2 supplier trade has a service sentence, so its demo supplier is matchable', () => {
  const stage2 = read('../e2e/stage2.mjs');
  const fixtures = read('../e2e/fixtures.mjs');
  const trades = JSON.parse(stage2.match(/SUPPLIER_TRADES\s*=\s*(\[[^\]]*\])/)[1].replace(/'/g, '"'));
  const block = fixtures.match(/const SERVICE_WORDS = \{([\s\S]*?)\n\};/)[1];
  const stated = new Set([...block.matchAll(/^\s*([a-z_]+):\s*'/gm)].map((m) => m[1]));
  const missing = trades.filter((t) => !stated.has(t));
  assert.deepEqual(missing, [], `no SERVICE_WORDS sentence for ${missing.join(', ')}: those demo suppliers confirm no service and match nobody`);
});
