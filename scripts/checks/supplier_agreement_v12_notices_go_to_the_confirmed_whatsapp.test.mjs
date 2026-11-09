// Supplier Agreement v12: clause 21's WhatsApp channel is the number the supplier confirmed, in BOTH languages;
// nothing else in the text moved; v11 stays word for word; the registry SQL, the exported text and the portal
// follow; and a formal notice's number depends on the version the supplier accepted.
//   node --test scripts/checks/supplier_agreement_v12_notices_go_to_the_confirmed_whatsapp.test.mjs
//
// 14 Sep 2026, agent: sales_engineer. Founder, the same day: "whatsapp number supplier confirmed." Reads only the
// repository; production is proved by the probe at the end of the SQL file when it is applied.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readSupplierPortal } from '../lib/portal_sources.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const legal = JSON.parse(read('src/content/legal.json'));
// v13 replaced v12 on 23 Sep 2026 (company_facts_agree_everywhere.test.mjs); v12's text is now the archive, kept word
// for word with one "superseded" line, so the v12 assertions read it there with that line removed.
const V12_SUPERSEDED = { en: '<div class="meta">Superseded on 23 September 2026 by version v13. This copy is kept for the record.</div>', ar: '<div class="meta">حلّ محلّها الإصدار v13 بتاريخ 23 سبتمبر 2026. تُحفظ هذه النسخة للسجل.</div>' };
const v12 = legal['supplier-agreement-v12'];
const sa = { en: { html: v12.en.html.replace(V12_SUPERSEDED.en, '') }, ar: { html: v12.ar.html.replace(V12_SUPERSEDED.ar, '') } };
const v11 = legal['supplier-agreement-v11'];
const text = (h) => h.replace(/<[^>]+>/g, ' ').replace(/&amp;/g, '&').replace(/&#39;/g, "'").replace(/\s+/g, ' ');
const clauses = (h) => Object.fromEntries(h.split(/(?=<h2>\d+\.)/).filter((s) => /^<h2>\d+\./.test(s)).map((s) => [Number(/^<h2>(\d+)/.exec(s)[1]), s.split(/<\/div>\n<div class="note">/)[0]]));
const SQL_FILE = 'scripts/sql/the_supplier_agreement_v12_whatsapp_notices_go_to_the_number_the_supplier_confirmed.sql';
const sql = read(SQL_FILE);

const C21_EN = 'a WhatsApp message to the WhatsApp number the Supplier confirmed in the supplier portal by entering a verification code sent to that number or, where the Supplier confirmed in the supplier portal that its registered mobile number is its WhatsApp number, to that registered mobile number';
const C21_AR = 'رسالة واتساب إلى رقم الواتساب الذي أكّده المورّد في بوابة المورّد بإدخال رمز تحقق أُرسل إلى ذلك الرقم، أو إلى رقم الهاتف المحمول المسجَّل للمورّد إذا أكّد المورّد في بوابة المورّد أن رقم هاتفه المحمول المسجَّل هو رقم الواتساب الخاص به';

test('v12 in both languages, clause 21 names the confirmed WhatsApp number and keeps SMS on the registered mobile', () => {
  const EN = text(sa.en.html), AR = text(sa.ar.html);
  assert.match(EN, /Version v12 · Last updated 14 September 2026/); assert.match(AR, /الإصدار v12 · آخر تحديث 14 سبتمبر 2026/);
  assert.ok(EN.includes(C21_EN)); assert.ok(AR.includes(C21_AR));
  assert.ok(EN.includes("(d) an SMS to the Supplier's registered mobile number."));
  assert.ok(AR.includes('(د) رسالة نصية قصيرة إلى رقم الهاتف المحمول المسجَّل للمورّد.'));
  assert.ok(EN.includes('registered mobile number and confirmed WhatsApp number current; a notice delivered to the details last registered or confirmed is validly served'));
  assert.ok(AR.includes('ورقم الواتساب المؤكَّد؛ ويكون الإشعار المسلَّم إلى آخر بيانات مسجَّلة أو مؤكَّدة إعلانًا صحيحًا'));
  assert.ok(!EN.includes("(c) a WhatsApp message to the Supplier's registered mobile number"), 'the v11 WhatsApp channel is still in v12');
});

test('the Arabic clause 21 has no English left in it', () => {
  const c21 = text(clauses(sa.ar.html)[21]).replace(/QuotesDone|management@quotesdone\.com/g, '');
  assert.doesNotMatch(c21, /[A-Za-z]/, c21);
});

test('only clause 21 changed: every other clause is v11 word for word, in both languages, numbered alike', () => {
  for (const lang of ['en', 'ar']) {
    const a = clauses(sa[lang].html), b = clauses(v11[lang].html);
    assert.deepEqual(Object.keys(a).map(Number), Array.from({ length: 35 }, (_, i) => i + 1));
    for (let i = 1; i <= 35; i++) if (i !== 21) assert.equal(a[i], b[i], `${lang} clause ${i} changed`);
    assert.notEqual(a[21], b[21]);
  }
});

test('v11 is archived word for word at /supplier-agreement/v11, with only its superseded line added', () => {
  const en = v11.en.html.replace('<div class="meta">Superseded on 14 September 2026 by version v12. This copy is kept for the record.</div>', '');
  const ar = v11.ar.html.replace('<div class="meta">حلّ محلّها الإصدار v12 بتاريخ 14 سبتمبر 2026. تُحفظ هذه النسخة للسجل.</div>', '');
  // the SHA-256 supplier_api stored for v11 acceptances (EN + '\n' + AR), from _shared/supplier_agreement.ts at v11
  assert.equal(createHash('sha256').update(en + '\n' + ar, 'utf8').digest('hex'), '3ea45ef6ab9180df2197c632b5948c7e868bc10bccf83bc9345abd4a70ae3b40');
  assert.ok(existsSync(join(ROOT, 'src/app/[locale]/supplier-agreement/v11/page.tsx')));
  assert.match(sa.en.html, /href="\/supplier-agreement\/v11\/"/); assert.match(sa.ar.html, /href="\/ar\/supplier-agreement\/v11\/"/);
});

test('the identity is the Trader License only: the old register number appears in nothing this version added', () => {
  for (const [n, s] of [['v12 en', sa.en.html], ['v12 ar', sa.ar.html], ['v11 archive', JSON.stringify(v11)], [SQL_FILE, sql],
    ['supplier_agreement.ts', read('supabase/functions/_shared/supplier_agreement.ts')]]) {
    assert.doesNotMatch(s, /2883503/, n);
  }
  assert.match(sa.en.html, /Trader License No\. 1633275/); assert.match(sa.ar.html, /رخصة تاجر رقم 1633275/);
});

test('the v12 archive is the text v12 suppliers signed, and the registry SQL carries the signed body of this text', () => {
  assert.ok(v12.en.html.includes(V12_SUPERSEDED.en) && v12.ar.html.includes(V12_SUPERSEDED.ar), 'the v12 archive has no superseded line');
  // the SHA-256 supplier_api stored for v12 acceptances (EN + '\n' + AR), from _shared/supplier_agreement.ts at v12
  assert.equal(createHash('sha256').update(sa.en.html + '\n' + sa.ar.html, 'utf8').digest('hex'), 'a18594ece25b97bb7c51aeade5e2ae19e2e97a9fa072dfcf63848f092873ad69');
  const r = spawnSync(process.execPath, [join(ROOT, 'scripts/legal/export_supplier_agreement.mjs'), '--check'], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  // the signed-body rule (reproduces v11's registered body, sha 0510081a…): each <div class="body">, the version
  // on the subtitle, cut before the operator note, the Arabic after the English.
  const inner = (h) => h.slice(h.indexOf('<div class="body">') + 18, h.indexOf('</div>\n<div class="note">'));
  const body = inner(sa.en.html).replace('QuotesDone.</div>', 'QuotesDone. Version 12 · governed by the laws of the United Arab Emirates.</div>')
    + '\n<div class="ar" dir="rtl" lang="ar">' + inner(sa.ar.html).replace('QuotesDone.</div>', 'QuotesDone. الإصدار 12 · تخضع لقوانين دولة الإمارات العربية المتحدة.</div>') + '</div>';
  const sha = createHash('sha256').update(body, 'utf8').digest('hex');
  assert.ok(sql.includes(body), 'the SQL does not carry the signed body of legal.json');
  assert.ok(sql.includes(`content_sha256 = '${sha}'`), 'the SQL does not pin the body hash');
  assert.match(sql, /set version = 'v12', effective_date = date '2026-09-14'/);
  assert.ok(read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(SQL_FILE), 'no MANIFEST line');
});

test('a notice follows the version accepted: v12 the confirmed number, v11 the registered mobile, older neither', () => {
  assert.match(sql, /create trigger a06_notifications_supplier_notice_follows_the_accepted_agreement before insert on public\.notifications/);
  assert.match(sql, /create trigger z06_supplier_notice_whatsapp_twin_under_v11 after insert on public\.notifications/);
  // #657's resolver is called, never copied
  assert.match(sql, /public\.fn_whatsapp_destination\('supplier', null, v_id, null\)/);
  assert.doesNotMatch(sql, /create (or replace )?function public\.fn_whatsapp_destination/);
  assert.match(sql, /to_regprocedure\('public\.fn_whatsapp_destination\(text, uuid, bigint, text\)'\) is null/);
  // the clause wording each version's notice cites is the text in legal.json
  const pol = JSON.parse(/'supplier_agreement_notice_clause',\s*\$j\$([\s\S]*?)\$j\$/.exec(sql)[1]);
  assert.ok(pol['12'].en.includes(C21_EN) && pol['12'].ar.includes(C21_AR));
  assert.ok(text(v11.en.html).includes(pol['11'].en.replace(/^Clause 21 \(v11\): /, '')));
  assert.ok(text(legal['supplier-agreement-v10'].en.html).includes(pol['10'].en.replace(/^Clause 21 \(v10\): /, '')));
  // the demand gate: v11 or later, not v12 only, and every payload carries the accepted version's clause
  assert.match(read('scripts/sql/the_accountant_chases_what_a_silent_supplier_owes.sql'), /\('supplier_charge_demand_min_agreement_version', '11'::jsonb/);
  assert.match(sql, /v_ver := \(v_route->>'version_no'\)::int;/);
  assert.match(sql, /'notice_clause_en', coalesce\(v_route->>'clause_en', ''\)/);
});

test('every routine the file creates pins search_path and is revoked from public, anon and authenticated', () => {
  const made = [...sql.matchAll(/create or replace function (public\.\w+)\(([^)]*)\)/g)];
  assert.ok(made.length >= 6);
  for (const [, name] of made) {
    assert.match(sql, new RegExp(`revoke execute on function ${name.replace('.', '\\.')}\\([^)]*\\) from public, anon, authenticated;`), name + ' is not revoked');
  }
  assert.equal((sql.match(/set search_path to 'public', 'pg_temp'/g) || []).length >= made.length, true);
});

test('the portal asks again, listing every change after the version accepted and linking what was accepted', () => {
  const portal = readSupplierPortal();
  const obj = /const AGREEMENT_CHANGES = (\{[\s\S]*?\n\});/.exec(portal)[1];
  const fn = /export function agreementChanges\(accepted, current, ar\) \{([\s\S]*?)\n\}/.exec(portal)[1];
  const changes = new Function('accepted', 'current', 'ar', `const AGREEMENT_CHANGES = ${obj};${fn}`);
  assert.equal(changes('v11', 'v12', false).length, 1);
  assert.match(changes('v11', 'v12', false)[0], /WhatsApp number you confirm in the portal/);
  assert.equal(changes('v10', 'v12', true).length, 5);
  assert.equal(changes('v12', 'v12', false).length, 0);
  const archived = JSON.parse(/export const ARCHIVED_AGREEMENTS = (\[[^\]]*\]);/.exec(portal)[1].replace(/'/g, '"'));
  for (const v of archived) assert.ok(legal['supplier-agreement-' + v] && existsSync(join(ROOT, `src/app/[locale]/supplier-agreement/${v}/page.tsx`)), v);
  assert.match(portal, /if \(needsReaccept\(me\)\) return <ReacceptTerms/);
});
