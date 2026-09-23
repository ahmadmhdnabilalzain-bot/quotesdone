// The post-deploy smoke reports a reasoning-only step as SKIP only while the product's own gate says the
// model hold is on (scripts/e2e/journeys.mjs modelHold). Seat: it_engineer. 23 Sep 2026.
//
// The smoke's copy of the hold rules must be the product's (supabase/functions/_shared/llm_hold.ts
// HOLD_RULES): a rule the product adds that the smoke lacks would turn a held product into 14 findings
// again, and a rule the smoke keeps that the product dropped would excuse a real failure as "held".
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const rulesIn = (file) => {
  const m = readFileSync(file, 'utf8').match(/HOLD_RULES\s*=\s*new Set\(\[([^\]]*)\]\)/);
  assert.ok(m, `${file}: no HOLD_RULES set`);
  return [...m[1].matchAll(/'([^']+)'/g)].map((x) => x[1]).sort();
};

test('the smoke excuses exactly the hold rules the product obeys', () => {
  assert.deepEqual(rulesIn('scripts/e2e/journeys.mjs'), rulesIn('supabase/functions/_shared/llm_hold.ts'));
});
