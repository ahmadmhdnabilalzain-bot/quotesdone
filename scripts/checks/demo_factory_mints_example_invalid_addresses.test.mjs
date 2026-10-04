// DEMO FACTORY ADDRESSES ARE @example.invalid (it_engineer, E2E stage 1 D9, 30 Sep 2026). The fixture convention is
// ZZ DEMO + @example.invalid; demo_factory minted qd-<tag>-...@example.com, which is how three "ZZ DEMO holds probe"
// leads of 22 Sep carried @example.com. Both domains are refused by every send guard (fn_is_demo_email), but only one
// is the convention. Teardown still matches @example.% so rows minted before this change are torn down too.
//   node --test scripts/checks/demo_factory_mints_example_invalid_addresses.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const s = readFileSync('scripts/lib/demo_factory.mjs', 'utf8');
test('every address demo_factory mints is on example.invalid, and teardown still reaches the old domain', () => {
  const minted = [...s.matchAll(/`qd-\$\{run\.tag\}-[^`]*`/g)].map((m) => m[0]);
  assert.ok(minted.length >= 2, 'the minted address templates were not found');
  for (const t of minted) assert.match(t, /@example\.invalid`$/, `demo_factory mints ${t}`);
  assert.match(s, /email like 'qd-\$\{tag\}-%@example\.%'/, 'teardown no longer matches both reserved domains');
});
