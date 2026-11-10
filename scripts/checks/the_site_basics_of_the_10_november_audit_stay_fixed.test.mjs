// THE SITE BASICS OF THE 10 NOV 2026 AUDIT STAY FIXED — what a source reading can hold.
// The audit and its live measurements: docs/reports/2026-11-10-website-ux-seo-checklist-audit.md
// (customer_support, with marketing for the search items). The wrong-URL 404 has its own check:
// a_wrong_url_gets_the_designed_404_in_its_language.test.mjs.
//
//   node --test scripts/checks/the_site_basics_of_the_10_november_audit_stay_fixed.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { fitTitle, TITLE_MAX } from '../../src/lib/titleFit.ts';
import { takeByClass, closeUnclosedBody, dropFirstH1 } from '../../src/lib/docHtml.ts';

const ROOT = join(import.meta.dirname, '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const json = (p) => JSON.parse(read(p));
const len = (s) => [...s].length;
// JSX with its comments blanked, so a sentence that explains a rule can never satisfy it.
const code = (s) => s.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, (m) => m.replace(/[^\n]/g, ' '));

test('titles: a brand or call-to-action tail is dropped only while the title is over 60 characters', () => {
  assert.equal(TITLE_MAX, 60);
  // measured on production: 111 of 146 sitemap titles were longer than 60, almost all because of these tails
  assert.equal(fitTitle('Smart Home Automation in the UAE — Get Free Quotes | QuotesDone'), 'Smart Home Automation in the UAE — Get Free Quotes');
  assert.equal(fitTitle('Swimming Pool Construction & Maintenance in the UAE — Get Free Quotes | QuotesDone'), 'Swimming Pool Construction & Maintenance in the UAE');
  assert.equal(fitTitle('كاميرات المراقبة (CCTV) وأنظمة الأمن في الإمارات — احصل على عروض أسعار مجانية | QuotesDone'), 'كاميرات المراقبة (CCTV) وأنظمة الأمن في الإمارات');
  // a title that fits is never touched, and a title long for its own words is left to its owner
  assert.equal(fitTitle('Plumbing Services in the UAE — Get Free Quotes | QuotesDone'), 'Plumbing Services in the UAE — Get Free Quotes | QuotesDone');
  assert.equal(fitTitle('About QuotesDone — QuotesDone'), 'About QuotesDone — QuotesDone');
  assert.equal(fitTitle('How much does AC repair & maintenance cost in the UAE? (2026 price guide)'), 'How much does AC repair & maintenance cost in the UAE? (2026 price guide)');
});

test('titles: every service page title fits in 60 characters in both languages, and stays unique', () => {
  const services = json('src/content/services.json');
  const seen = new Map();
  for (const [slug, v] of Object.entries(services)) for (const lang of ['en', 'ar']) {
    // ServiceDoc substitutes the place; the parent page reads "the UAE" / «الإمارات»
    const raw = v[lang].title.replace(/\{\{LOC_THE\}\}/g, lang === 'ar' ? 'الإمارات' : 'the UAE').replace(/\{\{LOC\}\}/g, lang === 'ar' ? 'الإمارات' : 'UAE').replace(/&amp;/g, '&');
    const t = fitTitle(raw);
    assert.ok(len(t) <= TITLE_MAX, `/${lang === 'ar' ? 'ar/' : ''}services/${slug}: ${len(t)} characters: ${t}`);
    assert.ok(!seen.has(t), `${slug}/${lang} has the same title as ${seen.get(t)}`);
    seen.set(t, `${slug}/${lang}`);
  }
});

test('titles: buildMeta fits the <title> and keeps the full title on the social cards', () => {
  const seo = code(read('src/lib/seo.ts'));
  assert.match(seo, /title: fitTitle\(title\),/);
  assert.match(seo, /openGraph: \{[\s\S]*?\n {6}title,/);
  assert.match(seo, /twitter: \{ card: 'summary_large_image', title,/);
});

test('legal pages: the Supplier Agreement body is closed at render, every document keeps one <h1>, the file is untouched', () => {
  const legal = json('src/content/legal.json');
  // the hash 44 live suppliers accepted (the_founders_mobile_..._asks_nobody_to_sign_again pins the same value)
  const sha = (k) => createHash('sha256').update(legal[k].en.html + '\n' + legal[k].ar.html, 'utf8').digest('hex');
  assert.equal(sha('supplier-agreement-v16'), '22f7d5ffbaacf06b2b0c1c537e320660234fa69211ac994313253b8e88b547e3');
  let repaired = 0;
  for (const [slug, v] of Object.entries(legal)) for (const lang of ['en', 'ar']) {
    const raw = v[lang].html;
    const html = closeUnclosedBody(raw);
    if (html !== raw) repaired++;
    const body = takeByClass(html, 'body');
    assert.ok(body, `${slug}/${lang}: .body has no end, so the page would print the whole file`);
    assert.ok(!/class="nav"|class="dochead"/.test(body.el), `${slug}/${lang}: .body swallows the switcher or the head`);
    assert.ok(!body.el.includes('class="note"'), `${slug}/${lang}: the note would print twice`);
    assert.equal((dropFirstH1(body.el).match(/<h1\b/g) || []).length, 0, `${slug}/${lang}: a second <h1> under the hero`);
    // a balanced document comes back byte-for-byte
    if (!/^supplier-agreement/.test(slug)) assert.equal(html, raw, `${slug}/${lang} was changed though it was balanced`);
  }
  // measured 10 Nov 2026: the current v17 and the archived v10, v11, v12, v13, v14, v15, v16, in both languages
  assert.equal(repaired, 16, `the render repaired ${repaired} documents`);
  const doc = code(read('src/components/LegalDoc.tsx'));
  assert.match(doc, /const html = closeUnclosedBody\(arDoc\(d\.html, locale\)\);/);
  assert.match(doc, /const bodyEl = dropFirstH1\(takeByClass\(html, 'body'\)\?\.el \?\? html\);/);
  assert.match(doc, /dropFirstH1\(takeByClass\(closeUnclosedBody\(d\.html\), 'body'\)/, 'the meta description is read from the closed body');
});

test('tap targets: the phone header CTA and menu button are 44 px, the logo link is 44 px tall', () => {
  const nav = code(read('src/components/AudienceNav.tsx'));
  const cta = /className="btn-key qd-magnet ([^"]+)"/.exec(nav)?.[1] ?? '';
  assert.match(cta, /(^| )h-11( |$)/, 'the header "Get quotes" measured 93x36 at 390 px');
  const menu = code(read('src/components/MobileNav.tsx'));
  const btn = /aria-controls=\{panelId\}[\s\S]*?className="([^"]+)"/.exec(menu)?.[1] ?? '';
  assert.match(btn, /(^| )h-11 w-11( |$)/, 'the menu button measured 36x36 at 390 px');
  const head = code(read('src/components/SiteHeader.tsx'));
  assert.match(head, /aria-label="QuotesDone"\s+className="group flex min-h-11 /);
});

test('one-time codes: every code field asks the phone to autofill it', () => {
  const SRC = join(ROOT, 'src');
  const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : n.endsWith('.tsx') ? [p] : []; });
  const missing = [];
  let fields = 0;
  for (const p of walk(SRC)) {
    for (const m of code(readFileSync(p, 'utf8')).matchAll(/<(?:Input|input)\b(?:[^>]|=>)*?\/>/g)) {
      const tag = m[0];
      // a code field: a numeric field labelled or bound as a code (sign-in, e-mail, SMS, WhatsApp, privacy)
      if (!/inputMode="numeric"/.test(tag) || !/code|Code/.test(tag)) continue;
      fields++;
      if (!/autoComplete="one-time-code"/.test(tag)) missing.push(p.slice(SRC.length + 1) + ': ' + tag.slice(0, 90));
    }
  }
  assert.ok(fields >= 8, `found ${fields} code fields; the sweep is not reading the portals`);
  assert.deepEqual(missing, []);
});

test('the contact form: its result is announced, the phone field opens the phone keypad', () => {
  const mk = json('src/content/marketing.json');
  for (const lang of ['en', 'ar']) {
    const form = /<form id="cform"[\s\S]*?<\/form>/.exec(mk.contact[lang].html)?.[0] ?? '';
    assert.match(form, /<div id="cmsg" role="status" aria-live="polite"/, `${lang}: a sent / failed message is not read out`);
    assert.match(form, /<input name="phone" type="tel"/, `${lang}: the phone field opens a letter keyboard`);
    assert.match(form, /<input name="email"[^>]* type="email" required/, `${lang}: the email field lost its validation`);
  }
});

test('the request form: one post per press', () => {
  const nr = code(read('src/components/me/NewRequest.tsx'));
  const submit = /const submit = async \(acceptTermsVersion = null\) => \{([\s\S]*?)\n {2}\};/.exec(nr)?.[1] ?? '';
  assert.match(submit, /if \(posting\.current\) return;/);
  assert.match(submit, /finally \{ posting\.current = false; \}/);
});

test('the complaint lookup is not indexed', () => {
  const page = code(read('src/app/[locale]/complaints/status/page.tsx'));
  assert.match(page, /robots: \{ index: false, follow: true \}/);
});

test('price tables line their digits up', () => {
  const css = read('src/app/globals.css');
  assert.match(css, /\.qd-prose :is\(th, td\) \{[^}]*font-variant-numeric: tabular-nums;/);
  assert.match(code(read('src/components/PriceGuide.tsx')), /className="tabular shrink-0 font-mono/);
});

test('both portals link the Privacy Policy from the account data controls', async () => {
  const ctl = code(read('src/components/portal/PrivacyControls.tsx'));
  assert.match(ctl, /<a href=\{lang === 'ar' \? '\/ar\/privacy' : '\/privacy'\}[^>]*>\{pt\(lang, 'policy'\)\}<\/a>/);
  const { pt } = await import('../../src/components/portal/privacy.ts');
  assert.equal(pt('en', 'policy'), 'Read our Privacy Policy');
  assert.equal(pt('ar', 'policy'), 'اطّلعوا على سياسة الخصوصية');
  // the controls are mounted in both portals' account settings
  assert.match(read('src/components/me/dashboard/AccountSettings.tsx'), /PrivacyControls/);
  assert.match(read('src/components/portal/supplier/SupplierSettings.tsx'), /PrivacyControls/);
});
