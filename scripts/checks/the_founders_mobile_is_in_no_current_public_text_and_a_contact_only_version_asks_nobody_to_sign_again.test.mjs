// THE FOUNDER'S PERSONAL MOBILE IS IN NO CURRENT PUBLIC LEGAL TEXT, AND A CONTACT-ONLY VERSION ASKS NOBODY TO SIGN AGAIN.
//
//   node --test scripts/checks/the_founders_mobile_is_in_no_current_public_text_and_a_contact_only_version_asks_nobody_to_sign_again.test.mjs
//
// 2 Nov 2026, seat: ceo. Ruling ledger 1482: the public calling number is +971 56 791 8605 and WhatsApp is
// +1 218 316 6814; the founder's personal mobile is printed in no current public text. Privacy 1.8, Cookie Policy
// 1.5 and Supplier Agreement v17 change the contact line and nothing else. Reads only the repository (the live
// registry is compared by the PROBE of scripts/sql/the_founders_mobile_leaves_the_current_legal_texts.sql).
//
//   1. no CURRENT legal text, in either language, prints the mobile; each prints the two public numbers;
//   2. the superseded Supplier Agreement v15 and v16 are byte-exact (the SHA-256 recorded on live acceptances);
//   3. each new version differs from the one it replaces ONLY in the contact line, label, date and change notice:
//      undoing exactly those edits reproduces the old text's pinned hash (privacy/cookie) or the archive (agreement);
//   4. a supplier who accepted v16 is not asked to accept v17 (portal, supplier_api, kyc); a v15 supplier is;
//   5. the superseded versions stay served (a signer's link) but are no longer listed in the sitemap.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { privacyAt18 } from '../lib/privacy_1_9.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
// supplier_api/index.ts names the whole function (index.ts plus its modules since 9 Nov 2026).
const whole = (p) => (p === 'supabase/functions/supplier_api/index.ts' ? functionSource('supplier_api') : read(p));
const legal = JSON.parse(read('src/content/legal.json'));
// 3 Nov 2026: Privacy 1.9 (one sentence on invitation opens, scripts/lib/privacy_1_9.mjs) replaced 1.8. The comparisons below
// are about 1.8, so they read 1.8 rebuilt from the current text with exactly the 1.9 edits undone (it throws if any is missing).
legal.privacy = { en: { ...legal.privacy.en, html: privacyAt18(legal.privacy.en.html, 'en') }, ar: { ...legal.privacy.ar, html: privacyAt18(legal.privacy.ar.html, 'ar') } };
const facts = JSON.parse(read('src/content/company_facts.json'));
const sha = (s) => createHash('sha256').update(s, 'utf8').digest('hex');
const MOBILE = /50[ .-]?931[ .-]?9355|509319355/;
const CALL = '+971 56 791 8605', WA = '+1 218 316 6814';
const archived = (k) => /-v\d+(?:\.\d+)?$/.test(k);
const CARD = /<div class="card"><p><strong>(?:What changed in version|ما الذي تغيّر في الإصدار) [\d.v]+ \(2 (?:November|نوفمبر) 2026\):<\/strong>[\s\S]*?<\/p><\/div>/;

test('no current legal text prints the mobile in either language, and each contact line gives the two public numbers', () => {
  for (const [k, v] of Object.entries(legal)) {
    if (archived(k)) continue;
    for (const g of ['en', 'ar']) assert.doesNotMatch(v[g].html, MOBILE, `${k}/${g} prints the founder's mobile`);
  }
  for (const k of ['privacy', 'cookie-policy', 'supplier-agreement']) for (const g of ['en', 'ar']) {
    assert.ok(legal[k][g].html.includes(CALL), `${k}/${g} lacks the calling number`);
    assert.ok(legal[k][g].html.includes(WA), `${k}/${g} lacks the WhatsApp number`);
  }
  assert.doesNotMatch(read('supabase/functions/_shared/supplier_agreement.ts'), MOBILE, 'the text a new supplier accepts prints the mobile');
});

test('the new versions are labelled in both languages and the one source of company facts names them', () => {
  // privacy 1.9 (3 Nov 2026) superseded 1.8; an_invitation_open_is_measured_on_a_tracked_share.test.mjs pins that step
  assert.deepEqual([facts.documents.privacy.version, facts.documents['cookie-policy'].version, facts.documents['supplier-agreement'].version], ['1.9', '1.5', 'v17']);
  assert.deepEqual(facts.documents['supplier-agreement'].carries_acceptance_from, ['v16']);
  assert.ok(facts.surfaces.archived_documents.includes('supplier-agreement-v16'));
  for (const [k, en, ar] of [['privacy', 'Version 1.8 · Last updated 2 November 2026', 'الإصدار 1.8 · آخر تحديث 2 نوفمبر 2026'], ['cookie-policy', 'Version 1.5 · Last updated 2 November 2026', 'الإصدار 1.5 · آخر تحديث 2 نوفمبر 2026'], ['supplier-agreement', 'Version v17 · Last updated 2 November 2026', 'الإصدار v17 · آخر تحديث 2 نوفمبر 2026']]) {
    assert.ok(legal[k].en.html.includes(en), `${k} EN label`);
    assert.ok(legal[k].ar.html.includes(ar), `${k} AR label`);
  }
  const mod = read('supabase/functions/_shared/supplier_agreement.ts');
  assert.match(mod, /SUPPLIER_AGREEMENT_VERSION = "v17"/);
  assert.ok(mod.includes(sha(legal['supplier-agreement'].en.html + '\n' + legal['supplier-agreement'].ar.html)), 'the exported hash is not the text');
});

test('the superseded Supplier Agreements are byte-exact: the hashes recorded on live acceptances still match', () => {
  const h = (k) => sha(legal[k].en.html + '\n' + legal[k].ar.html);
  assert.equal(h('supplier-agreement-v16'), '22f7d5ffbaacf06b2b0c1c537e320660234fa69211ac994313253b8e88b547e3', '44 live suppliers accepted exactly this text');
  assert.ok(h('supplier-agreement-v15').startsWith('7636dbcdb8'), 'v15 changed');
  assert.match(legal['supplier-agreement-v16'].en.html, /Version v16 · Last updated 19 October 2026/);
  assert.ok(legal['supplier-agreement-v16'].en.html.includes('+971 50 931 9355'), 'the frozen v16 must still read as it was signed');
});

test('Privacy 1.8, Cookie Policy 1.5 and Supplier Agreement v17 differ from what they replace only in contact line, label and notice', () => {
  const LI_PRIV_EN = '<li>Phone: +971 50 931 9355 (licence record: +971 56 791 8605)</li>', LI_NEW_EN = '<li>Phone: +971 56 791 8605</li><li>WhatsApp: +1 218 316 6814</li>';
  const LI_PRIV_AR = '<li>الهاتف: +971 50 931 9355 (سجل الرخصة: +971 56 791 8605)</li>', LI_NEW_AR = '<li>الهاتف: +971 56 791 8605</li><li>واتساب: +1 218 316 6814</li>';
  const back = (html, pairs) => pairs.reduce((t, [from, to]) => { assert.ok(t.includes(from), 'expected edit not found: ' + from.slice(0, 50)); return t.replace(from, to); }, html.replace(CARD, ''));
  // privacy 1.7's own change notice is pinned out of the comparison: the hash is of 1.7 with that notice removed
  assert.equal(sha(back(legal.privacy.en.html, [['Version 1.8 · Last updated 2 November 2026', 'Version 1.7 · Last updated 19 October 2026'],
    ['Phone: +971 56 791 8605; WhatsApp: +1 218 316 6814', 'Phone: +971 50 931 9355 (the number on our licence record is +971 56 791 8605)'], [LI_NEW_EN, LI_PRIV_EN]])),
  '1c74432f28d18cd8b3b4ee92b65c199a6f89d25be4c774ecab608492fee6863c', 'privacy EN differs from 1.7 beyond the contact line');
  assert.equal(sha(back(legal.privacy.ar.html, [['الإصدار 1.8 · آخر تحديث 2 نوفمبر 2026', 'الإصدار 1.7 · آخر تحديث 19 أكتوبر 2026'],
    ['الهاتف: +971 56 791 8605؛ واتساب: +1 218 316 6814', 'الهاتف: +971 50 931 9355 (الرقم المسجّل في سجل رخصتنا هو +971 56 791 8605)'], [LI_NEW_AR, LI_PRIV_AR]])),
  'a08768a285574b6d1b277c59c5dc4efa1b37131a574de138b0a10e706ac2a773', 'privacy AR differs from 1.7 beyond the contact line');
  assert.equal(sha(back(legal['cookie-policy'].en.html, [['Version 1.5 · Last updated 2 November 2026', 'Version 1.4 · Last updated 23 September 2026'], [LI_NEW_EN, LI_PRIV_EN]])),
    'c112f732a530c2bbdff5e7b1284ef806a24cacdb54c8a31c8dea5485a9e42b80', 'cookie EN differs from 1.4 beyond the contact line');
  assert.equal(sha(back(legal['cookie-policy'].ar.html, [['الإصدار 1.5 · آخر تحديث 2 نوفمبر 2026', 'الإصدار 1.4 · آخر تحديث 23 سبتمبر 2026'], [LI_NEW_AR, LI_PRIV_AR]])),
    'b6380d629e19f630af104f403b7089d948f4ba2989173b36cf129dd305adedb8', 'cookie AR differs from 1.4 beyond the contact line');
  // the agreement: undoing the edits must give the archived v16, character for character
  const sa = legal['supplier-agreement'], v16 = legal['supplier-agreement-v16'];
  assert.equal(back(sa.en.html, [['Version v17 · Last updated 2 November 2026', 'Version v16 · Last updated 19 October 2026'],
    [' · +971 56 791 8605 · WhatsApp +1 218 316 6814</p>', ' · +971 50 931 9355</p>'], ['<a href="/supplier-agreement/v16/">v16 (19 October 2026)</a>, ', '']]), v16.en.html);
  assert.equal(back(sa.ar.html, [['الإصدار v17 · آخر تحديث 2 نوفمبر 2026', 'الإصدار v16 · آخر تحديث 19 أكتوبر 2026'],
    [' · +971 56 791 8605 · واتساب +1 218 316 6814</p>', ' · +971 50 931 9355</p>'], ['<a href="/ar/supplier-agreement/v16/">v16 (19 أكتوبر 2026)</a>، ', '']]), v16.ar.html);
});

test('the privacy 1.8 and cookie 1.5 Arabic say the same as the English: both numbers, same sections', () => {
  for (const k of ['privacy', 'cookie-policy']) {
    const n = (h) => (h.match(/\+\d[\d ]{8,}\d/g) || []).filter((x) => [CALL, WA].includes(x)).length;
    assert.equal(n(legal[k].ar.html), n(legal[k].en.html), k);
  }
  assert.match(legal.privacy.ar.html, /البندان 1 و11/);
});

test('a supplier who accepted v16 is not asked to accept v17; a v15 supplier is, once', () => {
  const portal = readSupplierPortal();
  const src = /export function needsReaccept\(me\) \{([\s\S]*?)\n\}/.exec(portal)?.[1];
  assert.ok(src, 'needsReaccept not found');
  const needs = new Function('me', src);
  // the server answers terms_stands from app_secrets supplier_terms_carries_from
  assert.equal(needs({ accepted_terms_at: 'x', accepted_terms_version: 'v16', terms_current: 'v17', terms_stands: true }), false, 'v16 stands under v17');
  assert.equal(needs({ accepted_terms_at: 'x', accepted_terms_version: 'v15', terms_current: 'v17', terms_stands: false }), true);
  assert.equal(needs({ accepted_terms_at: 'x', accepted_terms_version: 'v16', terms_current: 'v17' }), true, 'an older server without the answer falls back to the strict compare');
  assert.match(portal, /ARCHIVED_AGREEMENTS = \[[^\]]*'v16'\]/);
  // `me` (supplier_api/lib/me_row.ts since 11 Nov 2026) reads the two keys beside the row and applies the same rule,
  // acceptanceStands over currentSupplierTermsVersion and supplierTermsCarriedFrom; me_row.test.ts proves it answers as
  // supplierAcceptanceStands did, case by case.
  assert.match(whole('supabase/functions/supplier_api/index.ts'), /currentSupplierTermsVersion\(once\),\s*supplierTermsCarriedFrom\(once\)/, 'me reads the current version and the versions it carries');
  for (const [f, rx] of [['supabase/functions/supplier_api/index.ts', /terms_stands: (?:await supplierAcceptanceStands\(secretVal, data\.accepted_terms_version\)|acceptanceStands\(data\.accepted_terms_version, current, carried\))/],
    ['supabase/functions/supplier_api/index.ts', /await supplierAcceptanceStands\(secretVal, sup\.accepted_terms_version\)/],
    ['supabase/functions/kyc/index.ts', /!\(await supplierAcceptanceStands\(sec, \(lead as any\)\?\.accepted_terms_version\)\)/]]) {
    assert.match(whole(f), rx, `${f} still compares versions strictly`);
  }
  for (const f of ['supabase/functions/supplier_api/index.ts', 'supabase/functions/kyc/index.ts']) assert.doesNotMatch(whole(f), /accepted_terms_version\s*(?:===|!==)\s*(?:curV|await currentSupplierTermsVersion)/, f + ' compares strictly');
  assert.match(read('supabase/functions/_shared/supplier_terms.ts'), /supplier_terms_carries_from/);
});

test('superseded versions are served for a signer but not listed in the sitemap', () => {
  assert.ok(existsSync(join(ROOT, 'src/app/[locale]/supplier-agreement/v16/page.tsx')));
  assert.match(read('src/app/[locale]/supplier-agreement/v16/page.tsx'), /slug="supplier-agreement-v16"/);
  assert.match(read('src/app/sitemap.xml/route.ts'), /if \(\/-v\\d\+\(\?:\\\.\\d\+\)\?\$\/\.test\(slug\)\) continue;/);
  assert.match(read('src/components/LegalDoc.tsx'), /robots: \{ index: false/);
});

// 2 Nov 2026 (ceo, ledger 1482, the coordinator's follow-up): the LIVE SYSTEM must not hand the mobile to anyone either. The mobile
// stays only server-side (login_otp, voice_otp read it; they never print it), in the archived signed agreements, in tests, and in
// history (SQL files already applied, reports).
import { readdirSync, statSync } from 'node:fs';
import { readSupplierPortal } from '../lib/portal_sources.mjs';
const walk = (d, out = []) => { for (const n of readdirSync(join(ROOT, d))) { const p = d + '/' + n; const s = statSync(join(ROOT, p)); if (s.isDirectory()) { if (n !== 'node_modules') walk(p, out); } else out.push(p); } return out; };
test('no served or sent source prints the mobile: functions, schema mirror, seeds, knowledge, messages, site', () => {
  const files = ['src', 'messages', 'knowledge', 'supabase/functions', 'supabase/schema', 'supabase/seeds', 'ai-organization'].flatMap((d) => (existsSync(join(ROOT, d)) ? walk(d) : []))
    .filter((p) => /\.(ts|tsx|mjs|js|json|md|sql|html|txt)$/.test(p))
    .filter((p) => !/\.test\.(ts|mjs)$/.test(p) && p !== 'src/content/legal.json' && !/\/login_otp\/|\/voice_otp\//.test(p) && !/^src\/lib\/(arabicDoc|blogBidi|ltrDirection)\.ts$/.test(p));
  const bad = files.filter((p) => MOBILE.test(readFileSync(join(ROOT, p), 'utf8')));
  assert.deepEqual(bad, []);
});

test('the three replies that gave the mobile now give the public numbers, and the SQL that changes production says so', () => {
  const mirror = read('supabase/schema/full_schema/09_functions_fn_s.sql') + read('supabase/schema/full_schema/10_functions_fn_t_onwards.sql');
  for (const fn of ['fn_wa_route', 'fn_text_did_not_survive_reply', 'fn_support_knowledge_gap']) {
    const i = mirror.indexOf(`CREATE OR REPLACE FUNCTION public.${fn}(`); assert.ok(i >= 0, fn);
    const body = mirror.slice(i, mirror.indexOf('$function$', mirror.indexOf('$function$', i) + 10));
    assert.ok(body.includes(CALL) && body.includes(WA), `${fn} lacks a public number`);
    assert.doesNotMatch(body, MOBILE, `${fn} prints the mobile`);
  }
  const sql = read('scripts/sql/the_live_system_gives_out_the_public_numbers_and_never_the_founders_mobile.sql');
  assert.doesNotMatch(sql, /\+971 50 931 9355|\+971509319355|050 931 9355/, 'the SQL itself must not print the mobile (its probe patterns are regexes, not the number)');
  for (const s of ['update public.company_faq', 'update public.social_reply_library', 'md5(answer)', 'PROBE OK', 'PROBE FAILED', 'fn_wa_route', 'fn_text_did_not_survive_reply', 'fn_support_knowledge_gap']) assert.ok(sql.includes(s), 'SQL lacks ' + s);
  assert.ok(read('scripts/sql/MANIFEST.txt').includes('scripts/sql/the_live_system_gives_out_the_public_numbers_and_never_the_founders_mobile.sql'));
});

test('the five kb_chunks that carried the mobile are corrected by an md5-guarded, manifest-listed file that re-embeds only them', () => {
  const f = 'scripts/sql/the_corporate_kit_chunks_give_the_public_numbers_and_never_the_founders_mobile.sql';
  const sql = read(f);
  for (const id of [177478, 177480, 177482, 177483, 177484]) assert.match(sql, new RegExp(`where id = ${id} and md5\\(content\\) = '[0-9a-f]{32}'`), `chunk ${id} is not md5-guarded`);
  assert.equal((sql.split('\n').filter((l) => !l.startsWith('--')).join('\n').match(/embedding_gte = null/g) || []).length, 5, 'exactly the five changed chunks are re-embedded');
  assert.doesNotMatch(sql, /update public\.kb_chunks set [^;]*\n\s*where (?!id = )/, 'an update that is not by id');
  for (const s of ['PROBE OK', 'PROBE FAILED', 'fn_kb_embed_dispatch', 'vector_dims(embedding_gte) = 384']) assert.ok(sql.includes(s), 'SQL lacks ' + s);
  const code = sql.split('\n').filter((l) => l.trim() && !l.startsWith('--'));
  assert.ok(/^update public\.kb_chunks/.test(code[0]), 'a comment line lost its leading dashes: ' + code[0]);
  assert.ok(read('scripts/sql/MANIFEST.txt').includes(f));
});

// 3 Nov 2026 (customer_support): the three legacy public.pages rows (about and the two pre-design home backups) carried it too.
// No reader serves them; they are corrected, not deleted, by an md5-guarded file whose probe counts 0 pages rows with the mobile.
test('the legacy site pages are corrected by an md5-guarded, manifest-listed file whose probe counts no pages row with the mobile', () => {
  const f = 'scripts/sql/the_legacy_site_pages_carry_the_public_numbers_and_never_the_founders_mobile.sql';
  const sql = read(f), probe = read(f.replace(/\.sql$/, '_probe.sql'));
  assert.doesNotMatch(sql + probe, /\+971 50 931 9355|\+971509319355|050 931 9355/, 'the SQL itself must not print the mobile');
  for (const slug of ['about', 'home_backup_predesign', 'home-ar_backup_predesign']) assert.match(sql, new RegExp(`\\('${slug}', '[0-9a-f]{32}'\\)`), `${slug} is not md5-guarded`);
  assert.doesNotMatch(sql.split('\n').filter((l) => !l.startsWith('--')).join('\n'), /delete\s+from/i, 'a legacy row is deleted');
  for (const s of [CALL, WA, 'wa.me/12183166814', 'tel:+971567918605', 'PROBE OK', 'PROBE FAILED']) assert.ok(sql.includes(s), 'SQL lacks ' + s);
  assert.match(probe, /n_mobile <> 0/);
  assert.match(probe, /raise exception 'CHK<<%>>'/);
  assert.ok(read('scripts/sql/MANIFEST.txt').includes(f));
});

test('the registry SQL carries the carry list and archives the three texts it replaces', () => {
  const sql = read('scripts/sql/the_founders_mobile_leaves_the_current_legal_texts.sql');
  assert.match(sql, /supplier_terms_carries_from/);
  for (const s of ["'supplier-agreement-v16'", "'privacy-v1.7'", "'cookie-policy-v1.4'", 'PROBE OK', 'PROBE FAILED']) assert.ok(sql.includes(s), 'SQL lacks ' + s);
  assert.ok(read('scripts/sql/MANIFEST.txt').includes('scripts/sql/the_founders_mobile_leaves_the_current_legal_texts.sql'));
});
