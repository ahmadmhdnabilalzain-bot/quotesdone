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
import { readSupplierPortal } from '../lib/portal_sources.mjs';

const copy = readFileSync(new URL('../../src/components/portal/supplier/serverCopy.ts', import.meta.url), 'utf8');
const portal = readSupplierPortal();
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

// RE-PINNED 12 Nov 2026 (sales_engineer; founder ruling 1672: "there was something like pick your category. Let's not add that
// option ... let these things be extracted automatically from the company profile and the trade license"). The sign-up used to
// offer the 223 codes; it now offers no trade and no name at all: the reading of the licence and profile proposes the trades,
// which he confirms on the Services step. The free-text list must stay gone too.
test('the sign-up asks no trade and no company name: create_company is sent neither (ruling 1672)', () => {
  const onb = readFileSync(new URL('../../src/components/portal/supplier/core/Onboarding.tsx', import.meta.url), 'utf8');
  assert.ok(!/const CATEGORIES = \[/.test(portal), 'the 29-item free-text list is back');
  assert.doesNotMatch(onb, /TRADE_(?:CODES|GROUPS)|trade_not_listed|<select\b/, 'the trade picker is back on the sign-up');
  assert.doesNotMatch(onb, /setCname|autoComplete="organization"/, 'a company-name box is back on the sign-up');
  const call = onb.slice(onb.indexOf("action: 'create_company'"), onb.indexOf('}, token)', onb.indexOf("action: 'create_company'")));
  assert.ok(call.length > 0, 'the sign-up no longer calls create_company');
  assert.doesNotMatch(call, /company_name|category/, 'the sign-up sends a typed name or a trade again');
});

test('accept_terms follows the checkbox and the certificate failure is shown', () => {
  assert.ok(!/accept_terms: true/.test(portal), 'save_profile is sent accept_terms: true regardless of the checkbox');
  assert.ok(/terms_cert_failed/.test(portal), 'the kyc accept_terms failure is swallowed again');
});

test('UAE mobile numbers normalise to +9715XXXXXXXX and anything else is refused', () => {
  for (const v of ['0501234567', '050 123 4567', '+971 50 123 4567', '00971501234567', '971-50-123-4567', '501234567']) assert.equal(uaeMobile(v), '+971501234567', v);
  for (const v of ['', '0401234567', '+44 7700 900123', '05012345', '050123456789', 'abc']) assert.equal(uaeMobile(v), null, v);
});
