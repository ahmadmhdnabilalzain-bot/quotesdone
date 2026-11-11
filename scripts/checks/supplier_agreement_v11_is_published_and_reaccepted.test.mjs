// Supplier Agreement v11: the five founder-approved changes are in BOTH languages, v10 stays readable,
// the exported text and the registry SQL follow, and a supplier on an older version is asked again.
//   node --test scripts/checks/supplier_agreement_v11_is_published_and_reaccepted.test.mjs
//
// 14 Sep 2026, agents: website (the text) and sales_engineer (re-acceptance). Founder, the same day:
// "do these: … 1. Add WhatsApp and SMS as formal notice channels … 2. Make the Arabic text the one that
// counts in court … 3. State that the total charge is a fixed amount … 4. Link the AED 250 fee to the law
// on agreed compensation … 5. Correct the licence wording in the agreement to match your actual trade
// licence." Reads only the repository; production is read by the_refund_ladder_texts_agree once applied.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readSupplierPortal } from '../lib/portal_sources.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const legal = JSON.parse(read('src/content/legal.json'));
// v12 replaced v11 the same day (supplier_agreement_v12_notices_go_to_the_confirmed_whatsapp.test.mjs); v11's text
// is now the archive, kept word for word, so the v11 assertions read it there.
const sa = legal['supplier-agreement-v11'];
const text = (h) => h.replace(/<[^>]+>/g, ' ').replace(/&amp;/g, '&').replace(/&#39;/g, "'").replace(/\s+/g, ' ');
const EN = text(sa.en.html), AR = text(sa.ar.html);
// The official wording of Civil Transactions Law (25/2025) Art 340(1), uaelegislation.gov.ae/en|ar/legislations/4011.
const A340_EN = 'The contracting parties may pre-determine the amount of compensation by stipulating it in the contract or in a subsequent agreement, subject to the provisions of the law.';
const A340_AR = 'يجوز للمتعاقدين أن يُحددا مقدمًا قيمة التعويض بالنص عليها في العقد أو في اتفاق لاحق، مع مراعاة أحكام القانون.';

test('both languages carry version v11 and the Arabic text governs', () => {
  assert.match(EN, /Version v11 · Last updated 14 September 2026/);
  assert.match(AR, /الإصدار v11 · آخر تحديث 14 سبتمبر 2026/);
  assert.match(EN, /The Arabic version of this document prevails for all purposes, including before the courts/);
  assert.match(AR, /النسخة العربية من هذا المستند هي المعتمدة لجميع الأغراض، بما في ذلك أمام المحاكم/);
  assert.match(EN, /The Arabic text prevails for all purposes, including before any court/);
  assert.match(AR, /يكون النص العربي هو المعتمد لجميع الأغراض، بما في ذلك أمام أي محكمة/);
  assert.doesNotMatch(EN, /English version of this document is the governing version/);
  assert.doesNotMatch(AR, /النسخة الإنجليزية من هذا المستند هي النسخة الحاكمة/);
});

test('the Arabic text is complete: the same 35 clauses, numbered alike', () => {
  const nums = (h) => [...h.matchAll(/<h2>(\d+)\./g)].map((m) => Number(m[1]));
  const en = nums(sa.en.html), ar = nums(sa.ar.html);
  assert.equal(en.length, 35); assert.deepEqual(ar, en);
  assert.deepEqual(en, Array.from({ length: 35 }, (_, i) => i + 1));
});

test('clause 21: WhatsApp and SMS are agreed notice channels, served on delivery', () => {
  for (const s of ['WhatsApp message to the Supplier', 'SMS to the Supplier', 'Article 81 of the Commercial Transactions Law', 'Article 9(1)(a) of the Civil Procedure Code', 'as recorded by the email, WhatsApp or SMS service provider']) assert.ok(EN.includes(s), 'EN clause 21 lacks: ' + s);
  for (const s of ['رسالة واتساب إلى رقم الهاتف المحمول المسجَّل', 'رسالة نصية قصيرة إلى رقم الهاتف المحمول المسجَّل', 'المادة (81) من قانون المعاملات التجارية', 'المادة (9) من قانون الإجراءات المدنية', 'وفق ما يسجّله مزوّد خدمة']) assert.ok(AR.includes(s), 'AR clause 21 lacks: ' + s);
});

test('clause 33: a sum certain once the notice issues, 9% simple from the due date, AED 250 under Art 340(1)', () => {
  assert.ok(EN.includes('a sum of money of a specified amount'));
  assert.ok(EN.includes('nine percent (9%) simple interest per annum from the due date until payment in full, and is never compounded'));
  assert.ok(EN.includes('Article 340(1) of the Civil Transactions Law (Federal Decree-Law No. 25 of 2025)'));
  assert.ok(EN.includes(A340_EN), 'EN does not quote Art 340(1) in the official English');
  assert.ok(AR.includes('مبلغًا نقديًا معيّن المقدار'));
  assert.ok(AR.includes('للبند (1) من المادة (340) من قانون المعاملات المدنية'));
  assert.ok(AR.includes(A340_AR), 'AR does not quote Art 340(1) in the official Arabic');
});

test('the licence is described as the DET licence prints it', () => {
  assert.match(EN, /Trader License No\. 1633275/); assert.match(AR, /رخصة تاجر رقم 1633275/);
  assert.ok(EN.includes('كوتس دن للتكنولوجيا') && AR.includes('كوتس دن للتكنولوجيا'), 'the Arabic trade name from the licence');
  assert.doesNotMatch(EN, /E-Trader|Professional\) Licence/); assert.doesNotMatch(AR, /تاجر إلكتروني \(مهني\)/);
});

test('v10 stays readable, with its date, at /supplier-agreement/v10', () => {
  const old = legal['supplier-agreement-v10'];
  assert.ok(old?.en?.html && old?.ar?.html);
  assert.match(text(old.en.html), /Version v10 · Last updated 14 September 2026/);
  assert.match(text(old.en.html), /Superseded on 14 September 2026 by version v11/);
  assert.match(text(old.ar.html), /حلّ محلّها الإصدار v11 بتاريخ 14 سبتمبر 2026/);
  assert.match(text(old.en.html), /Notices to the Supplier may be sent to the registered email or shown in the supplier portal/);
  assert.ok(existsSync(join(ROOT, 'src/app/[locale]/supplier-agreement/v10/page.tsx')));
  // 2 Nov 2026 (ceo, ledger 1482): the sitemap no longer LISTS a superseded version (they print the founder's former mobile); the page stays served and noindex.
  assert.match(read('src/app/sitemap.xml/route.ts'), /if \(\/-v\\d\+\(\?:\\\.\\d\+\)\?\$\/\.test\(slug\)\) continue;/);
  assert.match(sa.en.html, /href="\/supplier-agreement\/v10\/"/); assert.match(sa.ar.html, /href="\/ar\/supplier-agreement\/v10\/"/);
});

test('the exported agreement text and the registry SQL are v11', () => {
  // The exported module moved to v12 (asserted by the v12 check); the export must still match legal.json.
  const r = spawnSync(process.execPath, [join(ROOT, 'scripts/legal/export_supplier_agreement.mjs'), '--check'], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  const f = 'scripts/sql/the_supplier_agreement_v11_arabic_governs_and_notices_reach_whatsapp.sql';
  const sql = read(f);
  assert.ok(read('scripts/sql/MANIFEST.txt').split('\n').includes(f), 'no MANIFEST line');
  assert.match(sql, /set version = 'v11', effective_date = date '2026-09-14'/);
  assert.ok(sql.includes(A340_EN) && sql.includes(A340_AR), 'the signed body carries both languages');
});

test('a supplier on an older version is asked again, and the record is read server-side', () => {
  const api = functionSource('supplier_api');
  assert.match(api, /accepted_terms_at,accepted_terms_version,/);
  // `me` reads terms_version beside the row since 11 Nov 2026 (supplier_api/lib/me_row.ts), with the handler's secretVal
  assert.match(api, /terms_current: (?:await secretVal\('terms_version'\)|termsCurrent)/);
  assert.match(api, /supplierOf\(admin, email, secretVal\)/, 'me must read the version from app_secrets (secretVal), never from the browser');
  assert.match(api, /once\('terms_version'\)/);
  const acc = api.slice(api.indexOf("if (action === 'accept_terms')"), api.indexOf("if (action === 'settings')"));
  assert.ok(acc.length > 100, 'no accept_terms action');
  // 15 Sep 2026: the record is built in one place for every writer (supplier_api twice, kyc), so the
  // action is checked for calling it and the helper for what it records.
  assert.ok(acc.includes('supplierTermsRecord(secretVal, clientIp(req)'), 'accept_terms does not build the record server-side');
  const helper = read('supabase/functions/_shared/supplier_terms.ts');
  for (const s of ["sec('terms_version')", 'accepted_terms_at:', 'accepted_terms_version: v', 'accepted_terms_ip: ip', 'accepted_terms_sha256:']) assert.ok(helper.includes(s), 'the terms record does not carry ' + s);
  assert.doesNotMatch(acc, /body\.terms_version/, 'the browser must not choose the version');
  const portal = readSupplierPortal();
  const src = /export function needsReaccept\(me\) \{([\s\S]*?)\n\}/.exec(portal)?.[1];
  assert.ok(src, 'needsReaccept not found');
  const needs = new Function('me', src);
  assert.equal(needs({ accepted_terms_at: 'x', accepted_terms_version: 'v10', terms_current: 'v11' }), true);
  assert.equal(needs({ accepted_terms_at: 'x', accepted_terms_version: 'v11', terms_current: 'v11' }), false);
  assert.equal(needs({ accepted_terms_at: null, accepted_terms_version: null, terms_current: 'v11' }), false, 'never accepted is onboarding, not re-acceptance');
  assert.equal(needs({ accepted_terms_at: 'x', accepted_terms_version: 'v10', terms_current: null }), false);
  assert.equal(needs(null), false);
  assert.match(portal, /if \(needsReaccept\(me\)\) return <ReacceptTerms/);
  assert.match(portal, /call\('supplier_api', \{ action: 'accept_terms' \}, token\)/);
});
