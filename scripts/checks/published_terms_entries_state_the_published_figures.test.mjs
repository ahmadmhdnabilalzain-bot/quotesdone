// A PACK ENTRY THAT CUSTOMERS ARE GIVEN STATES THE PUBLISHED FIGURES, IN THE PUBLISHED NAME. Seat: customer_support.
// 27 Oct 2026.
//
// An entry of kind 'published_terms' in knowledge/seats/<seat>.json loads into its seat's table WITHOUT the tag
// 'audience:internal' (scripts/kb/verified_packs.mjs isOwnEntry), so think(), the portal chat and the portal corpus give
// it to customers, suppliers and visitors (#1660, #1661). Measured on 27 Oct 2026 in the customer_support pack, before
// this check:
//   - customer_support:company-hard-rules-marketplace@ar stated the circumvention penalty as AED 15,000 or three
//     times the fee. That is the wording of Supplier Agreement v10 to v12. The live agreement (v13 to v15) and the
//     entry's own English say AED 20,000 per incident or five times the fee.
//   - that entry and customer_support:company-pricing@ar wrote the brand in Arabic letters. The published pages and the
//     Arabic register (every_arabic_message_is_written_not_translated) keep "QuotesDone" in Latin letters.
//   - company-pricing said the non-response charge is "set in the Terms". The Terms never mention it; Supplier
//     Agreement clause 33 sets it.
//
// The figures are not typed into this file. They are read from the CURRENT published Supplier Agreement in
// src/content/legal.json (the source the /supplier-agreement page renders), in English and in Arabic. A
// published_terms entry may state the penalty only with those figures, and may never carry the retired AED 15,000 /
// three-times wording or the transliterated brand.
//   node --test scripts/checks/published_terms_entries_state_the_published_figures.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const plain = (html) => String(html).replace(/<[^>]+>/g, ' ').replace(/&[a-z#0-9]+;/gi, ' ').replace(/\s+/g, ' ');

// ── the published figures, read from the live agreement ─────────────────────────────────────────────────────────
const legal = JSON.parse(readFileSync(join(ROOT, 'src/content/legal.json'), 'utf8'));
const EN_AGR = plain(legal['supplier-agreement'].en.html);
const AR_AGR = plain(legal['supplier-agreement'].ar.html);
const enPub = EN_AGR.match(/agreed compensation of AED ([\d,]+) per incident, or (\w+) \((\d+)\) times the fee/);
const arPub = AR_AGR.match(/تعويض اتفاقي قدره ([\d,]+) درهم إماراتي عن كل واقعة، أو (\S+) \((\d+)\) أضعاف الرسوم/);

// ── what an entry says about the penalty ─────────────────────────────────────────────────────────────────────────
// English: "AED 20,000 per incident or five times the fee"; Arabic: "20,000 درهم عن كل مخالفة أو خمسة أضعاف الرسوم".
const EN_AMOUNT = /AED ([\d,]+) per (?:incident|breach|account or incident)/gi;
const EN_MULT = /\b(\w+|\d+) times the fee\b/gi;
const AR_AMOUNT = /([\d,]+) درهم(?: إماراتي)? (?:عن|لكل) (?:كل )?(?:مخالفة|واقعة|حالة)/g;
const AR_MULT = /(\S+)(?: \(\d+\))? أضعاف الرسوم/g;
const TRANSLITERATED = /(?:كوتس|كويتس|كوتيس) ?دن/;
const RETIRED = [/\bAED 15,000\b/, /\b(?:three|3) (?:\(3\) )?times the fee\b/i, /15,000 درهم/, /ثلاثة (?:\(3\) )?أضعاف/];

/** Every reason this entry text disagrees with the published agreement; [] when it agrees. */
export function findings(en, ar) {
  const out = [];
  for (const re of RETIRED) { if (re.test(en)) out.push(`retired penalty wording ${re} (EN)`); if (re.test(ar)) out.push(`retired penalty wording ${re} (AR)`); }
  if (TRANSLITERATED.test(ar)) out.push('brand in Arabic letters; write "QuotesDone"');
  for (const m of en.matchAll(EN_AMOUNT)) if (m[1] !== enPub[1]) out.push(`EN penalty AED ${m[1]}, published AED ${enPub[1]}`);
  for (const m of en.matchAll(EN_MULT)) if (m[1].toLowerCase() !== enPub[2].toLowerCase() && m[1] !== enPub[3]) out.push(`EN "${m[0]}", published "${enPub[2]} times the fee"`);
  for (const m of ar.matchAll(AR_AMOUNT)) if (m[1] !== arPub[1]) out.push(`AR penalty ${m[1]}, published ${arPub[1]}`);
  for (const m of ar.matchAll(AR_MULT)) if (m[1] !== arPub[2]) out.push(`AR "${m[0]}", published "${arPub[2]} أضعاف الرسوم"`);
  if (/non-response charge set in the Terms/i.test(en)) out.push('the non-response charge is set in the Supplier Agreement (clause 33), not the Terms');
  if (/عدم الاستجابة المحددة في الأحكام/.test(ar)) out.push('رسوم عدم الاستجابة تحددها اتفاقية المورّد (البند 33)، لا الأحكام');
  return out;
}

const published = [];
for (const f of readdirSync(join(ROOT, 'knowledge/seats')).filter((x) => /^[a-z_]+\.json$/.test(x))) {
  const pack = JSON.parse(readFileSync(join(ROOT, 'knowledge/seats', f), 'utf8'));
  for (const e of pack.entries) if (e.kind === 'published_terms') published.push({ file: f, e });
}

test('the published Supplier Agreement states the penalty in both languages (the check reads its figures there)', () => {
  assert.ok(enPub, 'the English Supplier Agreement no longer states "agreed compensation of AED N per incident, or W (n) times the fee"');
  assert.ok(arPub, 'the Arabic Supplier Agreement no longer states the agreed compensation in the expected form');
  assert.equal(enPub[1], arPub[1], 'the English and Arabic agreements state different amounts');
  assert.equal(enPub[3], arPub[3], 'the English and Arabic agreements state different multiples');
  assert.match(EN_AGR, /33\. Response obligation and non-response charge/, 'clause 33 no longer sets the non-response charge');
});

test('the rule refuses the wordings found on 27 Oct 2026 and passes the corrected ones', () => {
  for (const [en, ar] of [
    ['', 'والمورد المخالف يلتزم بمبلغ 15,000 درهم عن كل مخالفة أو ثلاثة أضعاف الرسوم أيهما أعلى'],
    ['', 'لكوتس دن مصدران للدخل'],
    ['', 'وكوتس دن وسيط تعريف وتيسير فقط'],
    ['A supplier breach costs AED 20,000 per incident or 3 times the fee.', ''],
    ['A supplier who fails to respond after a reveal owes the non-response charge set in the Terms.', ''],
    ['owes AED 25,000 per incident or five times the fee', ''],
  ]) assert.notDeepEqual(findings(en, ar), [], en || ar);
  assert.deepEqual(findings('A supplier who breaches this owes AED 20,000 per incident or five times the fee, whichever is higher.',
    'والمورد المخالف يلتزم بمبلغ 20,000 درهم عن كل مخالفة أو خمسة أضعاف الرسوم أيهما أعلى. لـ QuotesDone مصدران للدخل.'), []);
});

test('the entries customers are given are published_terms (the check is not vacuous)', () => {
  const ids = published.map((p) => p.e.id);
  for (const id of ['customer_support:company-pricing', 'customer_support:company-hard-rules-marketplace', 'customer_support:what-does-it-cost-published-prices'])
    assert.ok(ids.includes(id), `${id} is not kind published_terms`);
});

test('every published_terms entry states the published figures, in the published name', () => {
  const bad = [];
  for (const { file, e } of published)
    for (const why of findings(e.body_en, [e.body_ar, e.topic_ar ?? ''].join('\n'))) bad.push(`${file} ${e.id}: ${why}`);
  assert.deepEqual(bad, []);
});
