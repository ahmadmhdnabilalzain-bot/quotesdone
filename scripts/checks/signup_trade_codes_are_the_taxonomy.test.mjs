// THE SUPPLIER SIGN-UP FORM ASKS FOR A taxonomy_trade CODE, NOT FREE TEXT (15 Sep 2026, agent: customer_support).
//
// The sign-up trade was free text over 29 suggestions, 25 of which no taxonomy_trade code carries, so
// leads.sector never met fn_match_capability's exact-code overlap. The picker now offers the active
// codes. A supplier with no company cannot read taxonomy_trade, so the English labels are mirrored in
// serverCopy.ts TRADE_EN beside the Arabic TRADE_AR. This check fails if the two mirrors drift apart,
// if the form goes back to free-text suggestions, or if accept_terms stops following the checkbox.
// It reads source only — no network, no database, nobody is contacted.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { uaeMobile } from '../../src/components/portal/supplier/uaeMobile.ts';

const copy = readFileSync(new URL('../../src/components/portal/supplier/serverCopy.ts', import.meta.url), 'utf8');
const portal = readFileSync(new URL('../../src/components/portal/SupplierPortal.tsx', import.meta.url), 'utf8');
const keysOf = (name) => {
  const body = new RegExp(`const ${name}: Record<string, string> = \\{([\\s\\S]*?)\\n\\};`).exec(copy);
  assert.ok(body, `${name} not found in serverCopy.ts`);
  return [...body[1].matchAll(/(?:^|[\s,{])([a-z_]+):\s*'/g)].map((m) => m[1]);
};

// 42 -> 195 on 23 Sep 2026 (founder instructions 895/899/900, the_missing_trades_join_the_taxonomy_under_twelve_groups.sql).
// 195 -> 213 on 24 Sep 2026 (the trades a buyer names that were only a service under a neighbour).
// 213 -> 223 on 19 Oct 2026 (ten_uae_trades_the_taxonomy_still_missed_join_it.sql).
test('TRADE_EN and TRADE_AR carry the same 223 taxonomy_trade codes', () => {
  const en = keysOf('TRADE_EN'); const ar = keysOf('TRADE_AR');
  assert.equal(en.length, 223, 'TRADE_EN should mirror the 223 active taxonomy_trade codes');
  assert.deepEqual([...en].sort(), [...ar].sort());
});

test('the sign-up form offers codes, not the old free-text suggestions', () => {
  assert.ok(!/const CATEGORIES = \[/.test(portal), 'the 29-item free-text list is back');
  assert.ok(/TRADE_(?:CODES|GROUPS)/.test(portal) && /trade_not_listed/.test(portal), 'the code picker or its "not listed" answer is missing');
});

test('accept_terms follows the checkbox and the certificate failure is shown', () => {
  assert.ok(!/accept_terms: true/.test(portal), 'save_profile is sent accept_terms: true regardless of the checkbox');
  assert.ok(/terms_cert_failed/.test(portal), 'the kyc accept_terms failure is swallowed again');
});

test('UAE mobile numbers normalise to +9715XXXXXXXX and anything else is refused', () => {
  for (const v of ['0501234567', '050 123 4567', '+971 50 123 4567', '00971501234567', '971-50-123-4567', '501234567']) assert.equal(uaeMobile(v), '+971501234567', v);
  for (const v of ['', '0401234567', '+44 7700 900123', '05012345', '050123456789', 'abc']) assert.equal(uaeMobile(v), null, v);
});
