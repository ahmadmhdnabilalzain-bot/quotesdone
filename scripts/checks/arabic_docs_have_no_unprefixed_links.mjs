// Arabic content documents keep the reader in Arabic and keep Latin runs readable.
// Website audit, 14 Sep 2026: every Arabic legal page linked /terms/, /privacy/… with no /ar prefix
// (a shared link opened on a fresh device landed in English), the about page linked a retired path,
// the Supplier Agreement linked a route that 404s, and phone numbers read backwards in RTL.
//
// Fails when:
//   1. the shared helper src/lib/arabicDoc.ts stops prefixing links or isolating a phone (self-test);
//   2. any Arabic html in src/content/legal.json or marketing.json has an internal href without /ar
//      (blog links included — every post has Arabic since 14 Sep 2026), or uses the glossary-banned
//      job/function word (طلب/مشروع for a job, مهمة/دور for a function);
//   3. any html, either language, links a retired path (/app, /suppliers) or the old query-string
//      legal route;
//   4. after the render-time pass, a +971 number in an Arabic document is not bidi-isolated.
//
//   node scripts/checks/arabic_docs_have_no_unprefixed_links.mjs
import fs from 'node:fs';
import { arDoc } from '../../src/lib/arabicDoc.ts';

const read = (f) => JSON.parse(fs.readFileSync(new URL(`../../src/content/${f}.json`, import.meta.url), 'utf8'));
const fails = [];

// 1. self-test
const sample = '<p>الهاتف: +971 56 791 8605 · <a href="/terms/">الشروط</a> · <a href="mailto:a@b.co">a@b.co</a> · رقم 1633275</p>';
const once = arDoc(sample, 'ar');
if (!once.includes('href="/ar/terms/"')) fails.push('helper: internal link not prefixed');
if (!once.includes('<a href="tel:+971567918605" dir="ltr"><bdi dir="ltr">+971 56 791 8605</bdi></a>')) fails.push('helper: phone not isolated as a tel: link');
if (!once.includes('<bdi dir="ltr">1633275</bdi>') || !once.includes('<bdi dir="ltr">a@b.co</bdi>')) fails.push('helper: licence number or email not isolated');
if (arDoc(once, 'ar') !== once) fails.push('helper: not idempotent');
if (arDoc(sample, 'en') !== sample) fails.push('helper: touched English html');

const UNPREFIXED = /href="\/(?!ar[\/"]|_next)[^"]*"/g;
const BANNED_AR = /وظي?ف/g; // the job/function word and its employee sibling: طلب/مشروع/مهمة/دور instead
const RETIRED = new RegExp('href="(?:/ar)?/(?:ap' + 'p|supplier' + 's)(?:[/"?])|/legal\\?' + 'doc=', 'g');
const ISOLATED_PHONE = /(?<!<bdi dir="ltr">|tel:)\+971/g;
for (const f of ['legal', 'marketing']) {
  const J = read(f);
  for (const [slug, d] of Object.entries(J)) {
    for (const lo of ['en', 'ar']) {
      const h = d[lo]?.html || '';
      for (const m of h.matchAll(RETIRED)) fails.push(`${f}/${slug}/${lo}: retired path ${m[0]}`);
    }
    const ar = d.ar?.html || '';
    for (const m of ar.matchAll(UNPREFIXED)) fails.push(`${f}/${slug}/ar: unprefixed internal link ${m[0]}`);
    for (const m of ar.matchAll(BANNED_AR)) fails.push(`${f}/${slug}/ar: banned glossary term at …${ar.slice(Math.max(0, m.index - 30), m.index + 20)}…`);
    const out = arDoc(ar, 'ar').replace(/<[^>]*>/g, (t) => t.replace(/\+971/g, '')); // attributes do not count
    if (ISOLATED_PHONE.test(out)) fails.push(`${f}/${slug}/ar: a +971 number is not bidi-isolated after arDoc()`);
    ISOLATED_PHONE.lastIndex = 0;
  }
}

if (fails.length) { console.error('arabic_docs_have_no_unprefixed_links: FAIL\n  ' + fails.join('\n  ')); process.exit(1); }
console.log('arabic_docs_have_no_unprefixed_links: OK — every Arabic internal link is /ar-prefixed, no retired paths, every +971 number isolated');
