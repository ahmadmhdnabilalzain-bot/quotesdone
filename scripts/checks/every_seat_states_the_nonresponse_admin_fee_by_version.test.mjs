// EVERY SEAT STATES THE NON-RESPONSE ADMIN FEE BY AGREEMENT VERSION (24 Sep 2026; seats ceo, customer_support,
// marketing, accountant, it_engineer).
//
// MEASURED 24 Sep 2026: the seat packs stated the supplier non-response administrative fee three ways at once
// (AED 500 in ceo/accountant/it_engineer English, AED 250 in their Arabic and in customer_support). The live
// Supplier Agreement v13 (effective 23 Sep 2026, clause 33(b), founder instruction 965) says AED 500; a supplier
// who accepted v12 or earlier owes AED 250 (company_facts.json nonresponse_admin_fee_aed, supplier_charge.ts
// adminFeeAed()). The site copy says "AED 500 (AED 250 until you accept Supplier Agreement v13)".
//
// THE RULE: in knowledge/seats/*.json, any sentence that states the admin fee as an amount must state the
// CURRENT amount from src/content/company_facts.json, and if it also states the older amount it must name the
// version (v12 / v13, or the Arabic 12 / 13). An amount that is neither is a finding. The two figures are read
// from company_facts.json, so a v14 change moves this check with it instead of forking it.
//
//   node --test scripts/checks/every_seat_states_the_nonresponse_admin_fee_by_version.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const root = new URL('../../', import.meta.url);
const facts = JSON.parse(readFileSync(new URL('src/content/company_facts.json', root), 'utf8'));
const fee = JSON.stringify(facts).match(/"nonresponse_admin_fee_aed":\{"value":(\d+)[^}]*?"was":(\d+)/);
assert.ok(fee, 'company_facts.json no longer carries nonresponse_admin_fee_aed {value, was}');
const [NOW, WAS] = [fee[1], fee[2]];

// One clause of a body that talks about the admin fee: EN "admin(istrative|istration) fee", AR "إداري / إدارية".
const clauses = (s) => s.split(/(?<=[.;؛])\s+|\n+/).filter((c) => /admin(?:istrative|istration)?\s+fee|AED\s*\d+\s+admin|إداري|إدارية/i.test(c));
const amounts = (c) => [...c.matchAll(/(?:AED\s*)?(\d[\d,]*)\s*(?:AED|درهم|درهماً|درهمًا)?/g)].map((m) => m[1].replace(/,/g, ''));

test(`every seat states the admin fee as AED ${NOW}, and AED ${WAS} only with its agreement version`, () => {
  const bad = [];
  for (const f of readdirSync(new URL('knowledge/seats/', root)).filter((n) => n.endsWith('.json'))) {
    const pack = JSON.parse(readFileSync(new URL('knowledge/seats/' + f, root), 'utf8'));
    for (const e of pack.entries) for (const k of ['body_en', 'body_ar']) for (const c of clauses(e[k] ?? '')) {
      if (!/non.?respon|silent|recover|عدم (?:ال)?(?:رد|استجابة)|الصامت|يُسترد|المسترد|المردود/i.test(c)) continue;   // other admin fees (licence, tax) are not this fee
      const a = amounts(c);
      if (!a.includes(NOW) && !a.includes(WAS)) continue;
      if (a.includes(WAS) && !(a.includes(NOW) && /v1[23]|الإصدار 1[23]|12 أو ما قبله/.test(c))) bad.push(`${e.id} ${k}: states AED ${WAS} without the current AED ${NOW} and the version`);
    }
  }
  assert.deepEqual(bad, []);
});
