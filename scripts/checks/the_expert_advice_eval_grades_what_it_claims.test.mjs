// THE EXPERT-ADVICE EVAL GRADES WHAT IT CLAIMS (10 Nov 2026). Seat: sales_engineer. Subject: scripts/eval/expert_advice_bank.mjs
// and scripts/eval/expert_advice_eval.mjs (founder ledger 1572, 1579, 1586). Offline: the eval's own selftest, so a grader that
// passes a bad conversation (a re-ask, a made-up price, a company named, no options, the wrong trade) fails here before anyone
// spends a dirham running it, and the bank keeps every taxonomy group (two openings each) in all five registers.
//   node --test scripts/checks/the_expert_advice_eval_grades_what_it_claims.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

test('the eval selftest: every grader catches its bad case; 12 groups x 2+ openings x 5 registers', () => {
  const r = spawnSync(process.execPath, [fileURLToPath(new URL('../eval/expert_advice_eval.mjs', import.meta.url)), 'selftest'], { encoding: 'utf8', env: { ...process.env, QD_OFFLINE: '1' } });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /SELFTEST OK: 135 conversations, 27 openings, 12 groups/);
});
