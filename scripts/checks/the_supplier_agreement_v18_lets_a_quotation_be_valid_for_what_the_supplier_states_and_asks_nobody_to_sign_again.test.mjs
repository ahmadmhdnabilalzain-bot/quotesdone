// SUPPLIER AGREEMENT v18: A QUOTATION IS VALID FOR THE PERIOD THE SUPPLIER STATES IN IT, AND NOBODY IS ASKED TO SIGN AGAIN.
//
//   node --test scripts/checks/the_supplier_agreement_v18_lets_a_quotation_be_valid_for_what_the_supplier_states_and_asks_nobody_to_sign_again.test.mjs
//
// 15 Nov 2026, seat: sales_engineer. Founder ruling, ledger 1697: "Quotation validity depends on what the supplier mentions in his
// quotation. No specific period". v17 clause 12 said "valid for 30 days from submission". The CEO's decision under founder ruling
// 1696: v18 carries v17 (the change only widens the supplier's freedom), so no supplier is asked to re-sign. Reads only the repository;
// the live registry is set by scripts/sql/the_supplier_agreement_v18_lets_a_quotation_be_valid_for_the_period_the_supplier_states.sql,
// whose verdict row checks it after the apply.
//   1. v17 is archived byte-exact: the SHA-256 recorded on every v17 acceptance (the v17 module's hash) still matches;
//   2. v18 differs from v17 ONLY in clause 12, the label and date, the change notice and the link to v17: undoing exactly those
//      edits gives the v17 text back, in both languages;
//   3. clause 12 says the period the supplier states, and that QuotesDone asks for one when none is stated, in EN and AR;
//   4. the one source of company facts, the exported module and the registry SQL name v18 and carry v17;
//   5. a v17 supplier is not asked to accept v18; the v17 text stays served for its signers.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { signedBody } from '../legal/company_facts.mjs';
import { applyState } from '../lib/pending_sql.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const legal = JSON.parse(read('src/content/legal.json'));
const facts = JSON.parse(read('src/content/company_facts.json'));
const sha = (s) => createHash('sha256').update(s, 'utf8').digest('hex');
const docSha = (k) => sha(legal[k].en.html + '\n' + legal[k].ar.html);
const V17_SIGNED = '54f23ad7935ca84f0ca5b7bcb10c8c00337e76154d934983211dc82aa6d9a47d';   // supplier_agreement.ts v17, on every v17 acceptance
const NAME = 'the_supplier_agreement_v18_lets_a_quotation_be_valid_for_the_period_the_supplier_states';
const CL12_EN = 'A quotation is valid for <b>the period the Supplier states in it</b> unless the Supplier refreshes or withdraws it before Reveal, and the Supplier is bound by a quotation that is revealed within that validity period. If a quotation states no period, QuotesDone asks the Supplier to state one; until the Supplier does, the quotation may be shown to the Customer marked “Validity: not stated by the supplier”.';
const CL12_AR = 'ويكون عرض السعر ساريًا <b>للمدة التي يذكرها المورّد فيه</b> ما لم يُحدّثه المورّد أو يسحبه قبل الكشف، ويكون المورّد ملزَمًا بعرض السعر الذي يُكشف عنه خلال مدة السريان تلك. وإذا لم يذكر عرض السعر مدة، تطلب QuotesDone من المورّد أن يذكرها؛ وإلى أن يذكرها، يجوز أن يُعرض عرض السعر على العميل مع عبارة «صلاحية العرض: لم يذكرها المورّد».';

test('v17 is archived byte-exact: the hash recorded on every v17 acceptance still matches', () => {
  assert.equal(docSha('supplier-agreement-v17'), V17_SIGNED);
  assert.match(legal['supplier-agreement-v17'].en.html, /Version v17 · Last updated 2 November 2026/);
  assert.ok(legal['supplier-agreement-v17'].en.html.includes('A quotation is valid for <b>30 days</b> from submission'), 'v17 must still read as it was signed');
  // the registry body rule reproduces the live v17 row (the hash the_founders_mobile_leaves_the_current_legal_texts.sql pinned)
  assert.equal(sha(signedBody(legal['supplier-agreement-v17'], '17')), 'c47600462a4678a9851919c7557743fe8c206c6527aac13bdb6064fc9e443374');
});

test('v18 differs from v17 only in clause 12, the label, the change notice and the link to v17', () => {
  const back = (html, pairs) => pairs.reduce((t, [from, to]) => { assert.equal(t.split(from).length, 2, 'expected exactly one: ' + from.slice(0, 60)); return t.replace(from, to); }, html);
  const cardEn = /<div class="card"><p><strong>What changed in version v18 \(15 November 2026\):<\/strong>[\s\S]*?<\/p><\/div>/.exec(legal['supplier-agreement'].en.html)?.[0];
  const cardAr = /<div class="card"><p><strong>ما الذي تغيّر في الإصدار v18 \(15 نوفمبر 2026\):<\/strong>[\s\S]*?<\/p><\/div>/.exec(legal['supplier-agreement'].ar.html)?.[0];
  assert.ok(cardEn && cardAr, 'the v18 change notice, in both languages');
  const v17 = legal['supplier-agreement-v17'];
  const card17 = (h) => /<div class="card"><p><strong>(?:What changed in version|ما الذي تغيّر في الإصدار) v17 [\s\S]*?<\/p><\/div>/.exec(h)[0];
  assert.equal(back(legal['supplier-agreement'].en.html, [['Version v18 · Last updated 15 November 2026', 'Version v17 · Last updated 2 November 2026'], [cardEn, card17(v17.en.html)],
    [CL12_EN, 'A quotation is valid for <b>30 days</b> from submission unless the Supplier refreshes or withdraws it before Reveal, and the Supplier is bound by a quotation that is revealed within that validity period.'],
    ['<a href="/supplier-agreement/v17/">v17 (2 November 2026)</a>, ', '']]), v17.en.html);
  assert.equal(back(legal['supplier-agreement'].ar.html, [['الإصدار v18 · آخر تحديث 15 نوفمبر 2026', 'الإصدار v17 · آخر تحديث 2 نوفمبر 2026'], [cardAr, card17(v17.ar.html)],
    [CL12_AR, 'ويكون عرض السعر ساريًا لمدة <b>30 يومًا</b> من تاريخ تقديمه ما لم يُحدّثه المورّد أو يسحبه قبل الكشف، ويكون المورّد ملزَمًا بعرض السعر الذي يُكشف عنه خلال مدة السريان تلك.'],
    ['<a href="/ar/supplier-agreement/v17/">v17 (2 نوفمبر 2026)</a>، ', '']]), v17.ar.html);
  assert.match(cardEn, /clause 12 only[\s\S]*a supplier who accepted v17 is not asked to accept again/);
  assert.match(cardAr, /البند 12 فقط[\s\S]*فالمورّد الذي قبل v17 لا يُطلب منه القبول مجددًا/);
});

test('clause 12 states the period the supplier states, and no period of QuotesDone\'s own, in both languages', () => {
  const clause = (h) => h.slice(h.indexOf('<h2>12.'), h.indexOf('<h2>13.'));
  const en = clause(legal['supplier-agreement'].en.html), ar = clause(legal['supplier-agreement'].ar.html);
  assert.ok(en.includes(CL12_EN)); assert.ok(ar.includes(CL12_AR));
  assert.doesNotMatch(en, /30 days/); assert.doesNotMatch(ar, /30 يوم/);
});

test('company facts, the exported module and the registry SQL name v18, and v18 carries v17', () => {
  const sa = facts.documents['supplier-agreement'];
  assert.deepEqual([sa.version, sa.date, sa.carries_acceptance_from], ['v18', '2026-11-15', ['v17']]);
  assert.ok(facts.surfaces.archived_documents.includes('supplier-agreement-v17'));
  for (const [g, label] of [['en', 'Version v18 · Last updated 15 November 2026'], ['ar', 'الإصدار v18 · آخر تحديث 15 نوفمبر 2026']]) assert.ok(legal['supplier-agreement'][g].html.includes(label), g);
  const mod = read('supabase/functions/_shared/supplier_agreement.ts');
  assert.match(mod, /SUPPLIER_AGREEMENT_VERSION = "v18"/);
  assert.ok(mod.includes(`SUPPLIER_AGREEMENT_SHA256 = '${docSha('supplier-agreement')}'`), 'the exported hash is not the v18 text');
  const sql = read(`scripts/sql/${NAME}.sql`);
  const body = /update public\.pages set html = \$qd_supplier\$([\s\S]*?)\$qd_supplier\$/.exec(sql)?.[1];
  assert.equal(body, signedBody(legal['supplier-agreement'], '18'), 'the registry body is legal.json v18 by the body rule');
  assert.ok(sql.includes(`'${sha(body)}'`), 'the verdict pins the v18 registry hash');
  assert.match(sql, /insert into public\.app_secrets \(key, value, updated_at\) values \('supplier_terms_carries_from', 'v17', now\(\)\)/);
  assert.match(sql, /update public\.app_secrets set value = 'v18', updated_at = now\(\) where key in \('terms_version', 'supplier_terms_version', 'terms_sha256_supplier_version'\);/);
  assert.match(sql, /where d\.slug = 'supplier-agreement' and d\.version = 'v17'\non conflict \(slug\) do nothing;/, 'v17 archived before the body is replaced');
  assert.ok(sql.indexOf("'archived:' || d.slug") < sql.indexOf('update public.pages set html'));
  assert.doesNotMatch(sql, /^\s*(begin|commit)\s*;/im);
  // waiting with a reason, or applied (16 Nov, 0db1eacfc) with a MANIFEST line: never both, never neither
  const st = applyState(`scripts/sql/${NAME}.sql`);
  assert.ok(st.applied !== (st.note !== null), 'pending and in MANIFEST at once, or neither');
  if (st.note !== null) assert.ok(st.note.length > 40);
});

test('a supplier who accepted v17 is not asked to accept v18; the v17 text stays served for its signers', async () => {
  const agreement = read('src/components/portal/supplier/core/Agreement.tsx');
  const src = /export function needsReaccept\(me\) \{([\s\S]*?)\n\}/.exec(agreement)?.[1];
  const needs = new Function('me', src);
  assert.equal(needs({ accepted_terms_at: 'x', accepted_terms_version: 'v17', terms_current: 'v18', terms_stands: true }), false, 'v17 stands under v18');
  assert.match(agreement, /ARCHIVED_AGREEMENTS = \[[^\]]*'v17'\]/);
  assert.match(agreement, /\n  18: \{\n    en: \['A quotation is valid for the period you state in it/);
  // the server's answer: acceptanceStands over the current version and supplier_terms_carries_from (deno: _shared/supplier_terms.test.ts)
  assert.match(read('supabase/functions/_shared/supplier_terms.ts'), /supplier_terms_carries_from/);
  assert.ok(existsSync(join(ROOT, 'src/app/[locale]/supplier-agreement/v17/page.tsx')));
  assert.match(read('src/app/[locale]/supplier-agreement/v17/page.tsx'), /slug="supplier-agreement-v17"/);
});
