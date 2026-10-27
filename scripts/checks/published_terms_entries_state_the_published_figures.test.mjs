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
// The retired circumvention wording (Supplier Agreement v10 to v12), scoped to the penalty so that an unrelated AED 15,000
// (a VAT-error exam question) or "three times" (lifetime value over acquisition cost) is not refused.
const RETIRED = [/\bAED 15,000 (?:per|or)\b/, /\b(?:three|3) (?:\(3\) )?times the fee\b/i, /\bthree-times-fee\b/i,
  /15,000 درهم(?: إماراتي)? (?:عن|لكل|أو)/, /ثلاثة (?:\(3\) )?أضعاف (?:ال)?رسوم/, /فثلاثة أضعافها/];
// The circumvention penalty itself: an amount paired with a multiple of the fee, in either language. Only this pairing is
// read in the INTERNAL packs too, so a tax penalty "10,000 درهم عن كل مخالفة" is never compared with the agreement.
const PAIRS_EN = [/AED ([\d,]+) per (?:incident|breach|account or incident),? or (\w+)(?: \(\d+\))? times the fee/gi, /AED ([\d,]+) or (\w+)-times-fee/gi];
const PAIRS_AR = [/([\d,]+) درهم(?: إماراتي)? (?:(?:عن|لكل) (?:كل )?(?:مخالفة|واقعة|حالة)،? )?أو (\S+)(?: \(\d+\))? أضعاف (?:ال)?رسوم/g];
const DERIVED_EN = /\b(\w+) times the fee is therefore (\d+)% of the quotation/gi;
const DERIVED_AR = /ف(\S+) أضعافها (\d+)% من قيمة العرض/g;

/** Every way this text states the circumvention penalty other than the published figures (any seat pack). */
export function penaltyFindings(en, ar) {
  const out = [];
  for (const re of RETIRED) { if (re.test(en)) out.push(`retired penalty wording ${re} (EN)`); if (re.test(ar)) out.push(`retired penalty wording ${re} (AR)`); }
  for (const re of PAIRS_EN) for (const m of en.matchAll(re))
    if (m[1] !== enPub[1] || m[2].toLowerCase() !== enPub[2].toLowerCase()) out.push(`EN "${m[0]}", published AED ${enPub[1]} / ${enPub[2]} times`);
  for (const re of PAIRS_AR) for (const m of ar.matchAll(re))
    if (m[1] !== arPub[1] || m[2] !== arPub[2]) out.push(`AR "${m[0]}", published ${arPub[1]} / ${arPub[2]} أضعاف`);
  for (const m of en.matchAll(DERIVED_EN)) if (m[1].toLowerCase() !== enPub[2].toLowerCase() || Number(m[2]) !== 3 * Number(enPub[3])) out.push(`EN "${m[0]}": ${enPub[2]} times a 3% fee is ${3 * Number(enPub[3])}%`);
  for (const m of ar.matchAll(DERIVED_AR)) if (m[1] !== arPub[2] || Number(m[2]) !== 3 * Number(arPub[3])) out.push(`AR "${m[0]}": ${arPub[2]} أضعاف رسوم 3% = ${3 * Number(arPub[3])}%`);
  return out;
}

/** Every reason a PUBLISHED entry's text disagrees with the published agreement; [] when it agrees. */
export function findings(en, ar) {
  const out = penaltyFindings(en, ar);
  if (TRANSLITERATED.test(ar)) out.push('brand in Arabic letters; write "QuotesDone"');
  for (const m of en.matchAll(EN_AMOUNT)) if (m[1] !== enPub[1]) out.push(`EN penalty AED ${m[1]}, published AED ${enPub[1]}`);
  for (const m of en.matchAll(EN_MULT)) if (m[1].toLowerCase() !== enPub[2].toLowerCase() && m[1] !== enPub[3]) out.push(`EN "${m[0]}", published "${enPub[2]} times the fee"`);
  for (const m of ar.matchAll(AR_AMOUNT)) if (m[1] !== arPub[1]) out.push(`AR penalty ${m[1]}, published ${arPub[1]}`);
  for (const m of ar.matchAll(AR_MULT)) if (m[1] !== arPub[2]) out.push(`AR "${m[0]}", published "${arPub[2]} أضعاف الرسوم"`);
  if (/non-response charge set in the Terms/i.test(en)) out.push('the non-response charge is set in the Supplier Agreement (clause 33), not the Terms');
  if (/عدم الاستجابة المحددة في الأحكام/.test(ar)) out.push('رسوم عدم الاستجابة تحددها اتفاقية المورّد (البند 33)، لا الأحكام');
  return out;
}

const all = [];
for (const f of readdirSync(join(ROOT, 'knowledge/seats')).filter((x) => /^[a-z_]+\.json$/.test(x))) {
  const pack = JSON.parse(readFileSync(join(ROOT, 'knowledge/seats', f), 'utf8'));
  for (const e of pack.entries) all.push({ file: f, e });
}
const published = all.filter((p) => p.e.kind === 'published_terms');

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
  // the internal entries' wordings of 27 Oct 2026 (accountant books the penalty from these)
  for (const [en, ar] of [
    ['Three times the fee is therefore 9% of the quotation value, which exceeds AED 15,000 only when the quotation is above about AED 166,667', ''],
    ['The AED 15,000 or three-times-fee clause is an anti-circumvention penalty, not a fee cap.', ''],
    ['', 'والجزاء التعاقدي على المورّد 15,000 درهم لكل واقعة أو ثلاثة أضعاف الرسوم أيهما أعلى'],
    ['', 'فثلاثة أضعافها 9% من قيمة العرض'],
    ['', 'بند 15,000 درهم أو ثلاثة أضعاف الرسوم عقوبة لمنع الالتفاف'],
    ['circumvention by a supplier costs AED 20,000 per incident or 3 times the fee', ''],
    ['', 'غرامته 20,000 درهم لكل حالة أو ثلاثة أضعاف الرسوم'],
  ]) assert.notDeepEqual(penaltyFindings(en, ar), [], en || ar);
  for (const [en, ar] of [
    ['Five times the fee is therefore 15% of the quotation value, which exceeds AED 20,000 only when the quotation is above about AED 133,333', 'فخمسة أضعافها 15% من قيمة العرض'],
    ['The AED 20,000 or five-times-fee clause is an anti-circumvention penalty, not a fee cap.', 'بند 20,000 درهم أو خمسة أضعاف الرسوم عقوبة لمنع الالتفاف'],
    ['We found an error of AED 15,000 in a filed VAT return.', 'وعدم الاحتفاظ بالسجلات 10,000 درهم عن كل مخالفة'],
    ['', 'تتجاوز القيمة الدائمة ثلاثة أضعاف تكلفة الاكتساب'],
  ]) assert.deepEqual(penaltyFindings(en, ar), [], en || ar);
  assert.deepEqual(findings('A supplier who breaches this owes AED 20,000 per incident or five times the fee, whichever is higher.',
    'والمورد المخالف يلتزم بمبلغ 20,000 درهم عن كل مخالفة أو خمسة أضعاف الرسوم أيهما أعلى. لـ QuotesDone مصدران للدخل.'), []);
});

test('the entries customers are given are published_terms (the check is not vacuous)', () => {
  const ids = published.map((p) => p.e.id);
  for (const id of ['customer_support:company-pricing', 'customer_support:company-hard-rules-marketplace', 'customer_support:what-does-it-cost-published-prices'])
    assert.ok(ids.includes(id), `${id} is not kind published_terms`);
});

test('every seat-pack entry, internal included, states the circumvention penalty at the published figures', () => {
  const bad = [];
  let stated = 0;
  for (const { file, e } of all) {
    const text = [e.body_en, e.body_ar, e.topic ?? '', e.topic_ar ?? ''];
    if ([...PAIRS_EN, ...PAIRS_AR].some((re) => text.some((t) => new RegExp(re.source, re.flags.replace('g', '')).test(t)))) stated++;
    for (const why of penaltyFindings([e.body_en, e.topic].join('\n'), [e.body_ar, e.topic_ar ?? ''].join('\n'))) bad.push(`${file} ${e.id}: ${why}`);
  }
  // 7 on 27 Oct 2026: customer_support, accountant (3), ceo (2) and it_engineer state it
  assert.ok(stated >= 7, `only ${stated} entries state the penalty; the pattern no longer reads the packs`);
  assert.deepEqual(bad, []);
});

test('every published_terms entry states the published figures, in the published name', () => {
  const bad = [];
  for (const { file, e } of published)
    for (const why of findings(e.body_en, [e.body_ar, e.topic_ar ?? ''].join('\n'))) bad.push(`${file} ${e.id}: ${why}`);
  assert.deepEqual(bad, []);
});
