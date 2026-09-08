// THE REFUND LADDER TEXTS AGREE: the public site, the signed bodies, the registry and every knowledge store.
//
// 6 Sep 2026. The founder's refund ruling (5 working days from payment, chase at 3, his final call at 5, refund on
// no response, banks 7-14 working days, AED 250 + 9% p.a. recovered from the silent supplier) was built and put
// into the Terms, the Supplier Agreement and the Refund Policy. An adversarial read of production the same evening
// still found the OLD rule ("3 working days ... refunded automatically") in the company FAQ every agent reads, and
// the public legal pages labelled "Version v7" while the registry a customer signs against said v4 / 1.3 — a
// divergence that pre-existed and had been carried forward. This check reads production and the committed site
// content and asserts they say the same thing, so neither can drift alone again.
//
//   node --test scripts/checks/the_refund_ladder_texts_agree.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const q = (s) => sql(`set statement_timeout = '15s'; ${s}`);
const norm = (v) => String(v).trim().replace(/^v/i, '');
const EN_MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December'];
const AR_MONTHS = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
const fmt = (iso, months) => { const [y, m, d] = iso.split('-').map(Number); return `${d} ${months[m - 1]} ${y}`; };
// the site slug -> the registry slug the acceptance record cites
const SITE_TO_REGISTRY = { terms: 'customer-terms', privacy: 'privacy', 'cookie-policy': 'cookie-policy', 'refund-policy': 'refund-policy',
  'supplier-agreement': 'supplier-agreement', 'acceptable-use': 'acceptable-use', disclaimer: 'disclaimer', complaints: 'complaints-policy' };
// a sentence that ties a refund to three working days, other than the chase sentence of the ladder
const OLD_RULE = `exists (select 1 from regexp_matches(content, '[^.]*3 working days[^.]*', 'g') m where m[1] ~* 'refund' and m[1] !~* 'chase')`;

test('the public legal pages carry the registry version and date of the document they render', { skip: SKIP }, async () => {
  const legal = JSON.parse(readFileSync(join(ROOT, 'src/content/legal.json'), 'utf8'));
  const reg = Object.fromEntries((await q(`select slug, version, effective_date::text as d from public.legal_documents`)).map((r) => [r.slug, r]));
  const bad = [];
  for (const [site, docSlug] of Object.entries(SITE_TO_REGISTRY)) {
    const r = reg[docSlug]; if (!r) { bad.push(`${docSlug}: no registry row`); continue; }
    const en = legal[site]?.en?.html || '', ar = legal[site]?.ar?.html || '';
    const enHead = `Version ${r.version} · Last updated ${fmt(r.d, EN_MONTHS)}`;
    const arHead = `الإصدار ${r.version} · آخر تحديث ${fmt(r.d, AR_MONTHS)}`;
    if (!en.includes(enHead)) bad.push(`${site}.en: header is not "${enHead}"`);
    if (!ar.includes(arHead)) bad.push(`${site}.ar: header is not "${arHead}"`);
    // every other version the page names (the Terms' Permitted-use clause names its own) must be the same version;
    // the inline script that translates the word "Version" is not a version
    for (const m of en.matchAll(/Version (v?[0-9]+(?:\.[0-9]+)?)\b/g)) if (norm(m[1]) !== norm(r.version)) bad.push(`${site}.en names Version ${m[1]}, registry ${r.version}`);
    for (const m of ar.matchAll(/الإصدار (v?[0-9]+(?:\.[0-9]+)?)/g)) if (norm(m[1]) !== norm(r.version)) bad.push(`${site}.ar names الإصدار ${m[1]}, registry ${r.version}`);
  }
  assert.deepEqual(bad, []);
});

test('the signed bodies name the version the registry holds, and the terms pins are intact', { skip: SKIP }, async () => {
  const rows = await q(`
    select d.slug, d.version, (regexp_matches(p.html, 'Version (v?[0-9]+)', 'g'))[1] as named
      from public.legal_documents d join public.pages p on p.slug = replace(d.source, 'pages:', '')
     where d.source like 'pages:%'`);
  const bad = rows.filter((r) => norm(r.named) !== norm(r.version)).map((r) => `${r.slug}: body names ${r.named}, registry ${r.version}`);
  assert.deepEqual(bad, []);
  assert.ok(rows.length >= 2, 'both agreements are registered from a page');
  // 9 Sep 2026: public.fn_terms_integrity() was dropped from production on 7 Sep 2026 (scripts/sql/DROPPED.txt).
  // Its subject — the app_secrets pins and the two pages bodies — is alive, so the same three properties are read
  // here directly from those tables: the pin's sha matches the live signed body, the pin is for the declared
  // version, and the published page is byte-identical to the signed body. Nothing was weakened.
  const integ = await q(`
    with s as (
      select 'supplier'::text kind,
             (select value from public.app_secrets where key='terms_version') dv,
             (select value from public.app_secrets where key='terms_sha256_supplier_version') pv,
             (select value from public.app_secrets where key='terms_sha256_supplier') psha,
             (select encode(sha256(convert_to(value,'UTF8')),'hex') from public.app_secrets where key='supplier_terms_html') lsha,
             (select encode(sha256(convert_to(html,'UTF8')),'hex') from public.pages where slug='legal_supplier_body') pubsha
      union all
      select 'customer',
             (select value from public.app_secrets where key='customer_terms_version'),
             (select value from public.app_secrets where key='terms_sha256_customer_version'),
             (select value from public.app_secrets where key='terms_sha256_customer'),
             (select encode(sha256(convert_to(html,'UTF8')),'hex') from public.pages where slug='legal_terms_body'),
             (select encode(sha256(convert_to(html,'UTF8')),'hex') from public.pages where slug='legal_terms_body')
    )
    select kind, dv, pv, psha, lsha, pubsha,
           (psha is not distinct from lsha) and (dv is not distinct from pv) and (pubsha is not distinct from lsha) as ok
      from s`);
  assert.equal(integ.length, 2, 'both pins are readable');
  assert.deepEqual(integ.filter((r) => !r.ok), [], 'terms pins intact');
  // a pin of null on both sides is "not distinct" and would pass silently — the pins must actually be there
  assert.deepEqual(integ.filter((r) => !(r.dv && r.pv && r.psha && r.lsha && r.pubsha)), [], 'no pin is null');
});

test('no knowledge store still ties a refund to 3 working days', { skip: SKIP }, async () => {
  const r = (await q(`
    select 'ops_knowledge' as store, count(*)::int as n from public.ops_knowledge where record_id like 'qd-company:%' and ${OLD_RULE}
    union all select 'agent_knowledge', count(*)::int from public.agent_knowledge where ${OLD_RULE}
    union all select 'kb_chunks', count(*)::int from public.kb_chunks where source_kind in ('trade','company_faq') and ${OLD_RULE}
    union all select 'company_faq', count(*)::int from (select answer as content from public.company_faq) f where ${OLD_RULE}`));
  assert.deepEqual(r.filter((x) => x.n > 0), [], JSON.stringify(r));
  const faq = await q(`select count(*)::int as n from public.ops_knowledge where record_id like 'qd-company:faq-%' and content ~ '5 working days'`);
  assert.ok(faq[0].n >= 2, 'the rendered FAQ records state the 5-working-day ladder');
});

test('the public FAQ (marketing.json) states the ladder in both languages', () => {
  const mk = JSON.parse(readFileSync(join(ROOT, 'src/content/marketing.json'), 'utf8'));
  const bad = [];
  for (const loc of ['en', 'ar']) {
    const html = mk.faq[loc].html;
    for (const m of html.matchAll(/<div class="a">([\s\S]*?)<\/div>/g)) {
      const a = m[1];
      const three = /3 working days|3 أيام عمل|ثلاثة أيام عمل/.test(a), refund = /refund|استرداد/i.test(a), chase = /chase|نتابع/i.test(a);
      if (three && refund && !chase) bad.push(`${loc}: ${a.slice(0, 90)}`);
    }
  }
  assert.deepEqual(bad, []);
});
