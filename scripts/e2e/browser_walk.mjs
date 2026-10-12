// scripts/e2e/browser_walk.mjs — the real-browser walk of founder ledger 1160 (it_engineer, QA for all seats).
//
//   node scripts/e2e/browser_walk.mjs public            # public site, desktop+iPhone 13, EN+AR, both domains
//   node scripts/e2e/browser_walk.mjs portals ids.json  # signed-in walks for the sandbox run's demo identities
//   node scripts/e2e/browser_walk.mjs journeys ids.json # uploads, terms re-accept, Stripe TEST success+decline, rating, export, unsubscribe
//   node scripts/e2e/browser_walk.mjs remeasure /services/cleaning 3
//   node scripts/e2e/browser_walk.mjs index             # (re)write browser/index.html + link from INDEX.html
//
// Founder, ledger 1160: "test like a real user, in a real browser, not only through code". Journeys a-h
// drive the funnel mostly by API; this walks every PAGE as a visitor sees it and measures, per page:
// console errors, failed requests (4xx/5xx/aborted), load time (>4 s flagged), horizontal overflow,
// raw "messages." i18n keys, English on an Arabic customer page, Arabic on a supplier page (suppliers
// are English only), and controls that are unnamed or dead. Every page gets a screenshot; every journey
// a video.
//
// NOTHING REACHES A PERSON. Public pages are read only; the contact form, the job box and the support chat
// are filled but NEVER submitted (no anonymous model call, no untagged row). Journeys and portal walks run
// only through sandboxGate(): the stage-2 run tag, its open models_allowed window, and its own identities.
// Portal walks use ONLY identities on @example.invalid (refused otherwise); a session for an existing
// demo user is obtained by the Auth admin API setting a fresh password on THAT demo user, which sends
// nothing. Builds on browser.mjs (signedInPage, shot, realErrors) rather than beside it.
import { chromium, devices } from 'playwright';
import { mkdirSync, writeFileSync, readFileSync, existsSync, readdirSync, renameSync } from 'node:fs';
import { join } from 'node:path';
import { launch, signedInPage, realErrors, IGNORABLE_CONSOLE } from './browser.mjs';

export const OUT = process.env.QD_WALK_OUT || 'C:/Users/Opera/Desktop/QuotesDone Sandbox Test 2026-10/browser';
const SITE = process.env.QD_SITE || 'https://quotesdone.com';
const SLOW_MS = 4000;
export const VIEWS = {
  desktop: { viewport: { width: 1440, height: 900 } },
  mobile: { ...devices['iPhone 13'] },
};

const SERVICES = ['aluminium-glass', 'ac-maintenance', 'ac-duct-cleaning', 'cctv-security', 'cleaning', 'curtains-blinds',
  'electrical', 'facilities-management', 'false-ceiling', 'flooring', 'handyman', 'interior-design', 'joinery-kitchens',
  'landscaping', 'movers', 'painting', 'pest-control', 'plumbing', 'signage', 'smart-home', 'solar', 'swimming-pools',
  'tiling-marble', 'waterproofing', 'aluminium-glass-in-dubai'];
export const PUBLIC_PAGES = ['/', '/how-it-works', '/services', ...SERVICES.map((s) => '/services/' + s), '/supplier', '/about',
  '/faq', '/how-we-verify', '/contact', '/terms', '/supplier-agreement', '/privacy', '/cookie-policy', '/refund-policy',
  '/acceptable-use', '/disclaimer', '/complaints', '/blog', '/u/unsubscribe'];

// ---- the per-page measurements -----------------------------------------------------------------
/** Attach listeners once per page; returns a bag the checks drain per step. */
export function instrument(page) {
  const bag = { console: [], failed: [] };
  page.on('console', (m) => { if (m.type() === 'error') bag.console.push(m.text().slice(0, 300)); });
  page.on('pageerror', (e) => bag.console.push('pageerror: ' + String(e.message).slice(0, 300)));
  page.on('response', (r) => { if (r.status() >= 400) bag.failed.push(`${r.status()} ${r.request().method()} ${r.url().slice(0, 200)}`); });
  page.on('requestfailed', (r) => {
    const why = r.failure()?.errorText || '';
    if (/ERR_ABORTED|NS_BINDING_ABORTED/.test(why) && /_rsc=|\/_next\//.test(r.url())) return;   // router prefetch cancelled by navigation
    bag.failed.push(`FAILED ${why} ${r.url().slice(0, 200)}`);
  });
  return bag;
}
const THIRD_PARTY = /googletagmanager|google-analytics|doubleclick|facebook|clarity\.ms|vercel-insights|_vercel\/(insights|speed)/i;

/** DOM facts a person would notice: overflow, raw keys, wrong language, unnamed controls. */
async function domFacts(page) {
  return page.evaluate(() => {
    // A closed <details> keeps its content laid out (content-visibility), so rect > 0 and innerText '' - the supplier
    // portal's Account and bell menus read as 3 unnamed controls and as overflow (walk f4294be8). Not on screen: skipped.
    const vis = (el) => { if (el.closest('details:not([open]) > :not(summary)')) return false; const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
    const text = document.body?.innerText || '';
    const de = document.documentElement;
    const overflowX = Math.max(de.scrollWidth, document.body.scrollWidth) - window.innerWidth;
    const wide = [];
    if (overflowX > 2) for (const el of document.querySelectorAll('body *')) {
      const r = el.getBoundingClientRect();
      if (vis(el) && (r.right > window.innerWidth + 2 || r.left < -2) && getComputedStyle(el).position !== 'fixed') {
        wide.push((el.tagName + (el.id ? '#' + el.id : '') + (el.className && typeof el.className === 'string' ? '.' + el.className.split(' ')[0] : '')).slice(0, 60));
        if (wide.length > 4) break;
      }
    }
    const keys = [...new Set((text.match(/\bmessages\.[\w.]+/g) || []).concat(text.match(/\b[a-z]+(?:\.[a-z_]+){2,}\b/g) || []).filter((k) => /^messages\.|_|\./.test(k) && !/\.(com|ae|ai|invalid|pdf|png|jpg)$/.test(k)))].slice(0, 10);
    // Language share over visible words (brand + common tokens removed).
    const words = text.replace(/QuotesDone|WhatsApp|AED|PDF|UAE|DET|TDRA|Stripe|Google|LLC|FZ|https?:\S+|\S+@\S+/g, ' ').split(/\s+/).filter((w) => w.length > 2);
    const latin = words.filter((w) => /^[A-Za-z][A-Za-z'’-]+[.,:;!?)]*$/.test(w));
    const arabic = words.filter((w) => /[\u0600-\u06FF]/.test(w));
    const latinSample = [...new Set(latin)].slice(0, 15);
    const unnamed = [];
    for (const el of document.querySelectorAll('button, a[href], [role=button]')) {
      if (!vis(el)) continue;
      const name = (el.getAttribute('aria-label') || el.innerText || el.title || el.querySelector('img[alt]')?.alt || '').trim();
      if (!name) unnamed.push(el.outerHTML.slice(0, 90));
    }
    return { dir: de.dir || getComputedStyle(de).direction, lang: de.lang, overflowX, wide, keys, latinN: latin.length, arabicN: arabic.length,
             wordsN: words.length, latinSample, unnamed: unnamed.slice(0, 5), unnamedN: unnamed.length, title: document.title };
  }).catch((e) => ({ error: String(e.message).slice(0, 120) }));
}

/** Verdict for one page. audience: 'public' | 'customer' | 'supplier'. */
export function judge(f, { lang, audience, ms, bag, url }) {
  const issues = [];
  const cons = realErrors(bag.console).filter((e) => !IGNORABLE_CONSOLE.some((re) => re.test(e)));
  const failed = bag.failed.filter((x) => !THIRD_PARTY.test(x));
  if (f.error) issues.push({ sev: 'high', what: 'page did not evaluate: ' + f.error });
  if (cons.length) issues.push({ sev: 'medium', what: `${cons.length} console error(s): ${cons.slice(0, 3).join(' | ')}` });
  if (failed.length) issues.push({ sev: failed.some((x) => /^5|FAILED/.test(x)) ? 'high' : 'medium', what: `${failed.length} failed request(s): ${failed.slice(0, 4).join(' | ')}` });
  if (ms > SLOW_MS) issues.push({ sev: 'low', what: `slow load ${ms} ms (> ${SLOW_MS})` });
  if (f.overflowX > 2) issues.push({ sev: 'medium', what: `horizontal overflow ${f.overflowX}px: ${f.wide.join(', ')}` });
  if (f.keys?.some((k) => /^messages\./.test(k))) issues.push({ sev: 'high', what: 'raw translation key(s) on screen: ' + f.keys.join(', ') });
  if (lang === 'ar' && audience !== 'supplier') {
    if (f.dir !== 'rtl') issues.push({ sev: 'high', what: `Arabic page not RTL (dir=${f.dir})` });
    const share = f.wordsN ? f.latinN / f.wordsN : 0;
    if (share > 0.15) issues.push({ sev: 'medium', what: `English on an Arabic page: ${Math.round(share * 100)}% Latin words, e.g. ${f.latinSample.join(' ')}` });
  }
  if (audience === 'supplier' && f.arabicN > 3) issues.push({ sev: 'medium', what: `Arabic on a supplier page (suppliers are English only): ${f.arabicN} Arabic words` });
  if (f.unnamedN) issues.push({ sev: 'low', what: `${f.unnamedN} control(s) with no accessible name: ${f.unnamed.slice(0, 2).join(' ')}` });
  return { url, status: issues.some((i) => i.sev !== 'low') ? 'FAIL' : 'PASS', ms, issues, facts: f };
}

// ---- the report ----------------------------------------------------------------------------------
export class Report {
  constructor(name) { this.name = name; this.steps = []; this.file = join(OUT, name + '.json'); }
  add(s) { this.steps.push({ at: new Date().toISOString(), ...s }); writeFileSync(this.file, JSON.stringify(this.steps, null, 1)); }
}
const slug = (p) => (p === '/' ? 'home' : p.replace(/^\//, '').replace(/[^a-z0-9]+/gi, '_')).slice(0, 60);

/** One context per (viewport, language) with a video; returns { ctx, page, bag, close() }. */
export async function openCtx(browser, view, lang, videoDir) {
  mkdirSync(videoDir, { recursive: true });
  const ctx = await browser.newContext({ ...VIEWS[view], locale: lang === 'ar' ? 'ar-AE' : 'en-GB', recordVideo: { dir: videoDir, size: view === 'mobile' ? { width: 390, height: 844 } : { width: 1280, height: 800 } } });
  const page = await ctx.newPage();
  const bag = instrument(page);
  return { ctx, page, bag, close: async (name) => { const v = page.video(); await ctx.close(); if (v && name) { try { renameSync(await v.path(), join(videoDir, name + '.webm')); } catch { /* keep the random name */ } } } };
}

/** Visit a URL, time it, screenshot it, judge it. */
export async function visit(page, bag, url, shotFile, meta) {
  bag.console.length = 0; bag.failed.length = 0;
  const t0 = Date.now();
  let nav = null;
  try { nav = await page.goto(url, { waitUntil: 'load', timeout: 45000 }); } catch (e) { bag.failed.push('NAV ' + String(e.message).slice(0, 120)); }
  const ms = Date.now() - t0;
  await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  if (nav && nav.status() >= 400) bag.failed.push(`${nav.status()} DOCUMENT ${url}`);
  const f = await domFacts(page);
  await page.screenshot({ path: shotFile, fullPage: true }).catch(() => page.screenshot({ path: shotFile }).catch(() => {}));
  return { ...judge(f, { ...meta, ms, bag, url }), shot: shotFile };
}

// ---- PUBLIC --------------------------------------------------------------------------------------
async function walkPublic(browser) {
  for (const view of ['desktop', 'mobile']) for (const lang of ['en', 'ar']) {
    const J = `public_${view}_${lang}`;
    const dir = join(OUT, 'public', `${view}_${lang}`);
    mkdirSync(dir, { recursive: true });
    const rep = new Report(J);
    const { page, bag, close } = await openCtx(browser, view, lang, join(OUT, 'videos'));
    for (const p of (process.env.QD_WALK_ONLY ? process.env.QD_WALK_ONLY.split(',') : PUBLIC_PAGES)) {
      const url = SITE + (lang === 'ar' && !p.startsWith('/u/') ? '/ar' + (p === '/' ? '' : p) : p);
      const r = await visit(page, bag, url, join(dir, slug(p) + '.png'), { lang, audience: 'public' });
      rep.add({ journey: J, step: p, ...r });
      console.log(`${r.status} ${J} ${p} ${r.ms}ms ${r.issues.map((i) => i.sev[0] + ':' + i.what.slice(0, 90)).join(' ; ')}`);
      if (p === '/') await homeExtras(page, bag, dir, rep, J, lang);
      if (p === '/contact') await contactForm(page, dir, rep, J);
    }
    await close(J);
  }
  if (process.env.QD_WALK_ONLY) return;
  // The .ae domain, once.
  const rep = new Report('public_ae_once');
  const { page, bag, close } = await openCtx(browser, 'desktop', 'en', join(OUT, 'videos'));
  mkdirSync(join(OUT, 'public', 'ae'), { recursive: true });
  for (const u of ['https://quotesdone.ae', 'https://www.quotesdone.ae', 'https://quotesdone.ae/ar']) {
    const r = await visit(page, bag, u, join(OUT, 'public', 'ae', slug(u.replace(/https:\/\//, '')) + '.png'), { lang: u.endsWith('/ar') ? 'ar' : 'en', audience: 'public' });
    r.finalUrl = page.url();
    rep.add({ journey: 'public_ae', step: u + ' -> ' + r.finalUrl, ...r });
    console.log(`${r.status} ae ${u} -> ${r.finalUrl}`);
  }
  await close('public_ae_once');
}

/** Cookie banner (fresh context shows it), the job check box, and the support chat widget. */
async function homeExtras(page, bag, dir, rep, J, lang) {
  const step = async (name, fn) => {
    bag.console.length = 0; bag.failed.length = 0;
    let ok = false, detail = '';
    try { [ok, detail] = await fn(); } catch (e) { detail = 'threw: ' + String(e.message).slice(0, 160); }
    const file = join(dir, 'home_' + name + '.png');
    await page.screenshot({ path: file }).catch(() => {});
    const errs = realErrors(bag.console), failed = bag.failed.filter((x) => !THIRD_PARTY.test(x));
    const issues = [];
    if (!ok) issues.push({ sev: 'high', what: detail });
    if (errs.length) issues.push({ sev: 'medium', what: 'console: ' + errs.slice(0, 2).join(' | ') });
    if (failed.length) issues.push({ sev: 'medium', what: 'failed: ' + failed.slice(0, 3).join(' | ') });
    rep.add({ journey: J, step: 'home: ' + name, status: issues.some((i) => i.sev !== 'low') ? 'FAIL' : 'PASS', detail, issues, shot: file });
    console.log(`${ok ? 'PASS' : 'FAIL'} ${J} home:${name} ${detail.slice(0, 150)}`);
  };
  await step('cookie_banner', async () => {
    const b = page.locator('[role=dialog], [class*=cookie i], [id*=cookie i]').filter({ hasText: lang === 'ar' ? /ملفات|كوكي|تعريف/ : /cookie/i }).first();
    const seen = await b.isVisible().catch(() => false);
    if (!seen) return [false, 'cookie banner not visible on a first visit'];
    const btn = b.getByRole('button').filter({ hasText: lang === 'ar' ? /رفض|الضرورية|فقط|حسن|موافق/ : /reject|necessary|decline|got it|ok/i }).first();
    const has = await btn.count();
    if (has) { await btn.click(); await page.waitForTimeout(600); }
    const gone = !(await b.isVisible().catch(() => false));
    return [has > 0 && gone, `banner visible; decline button ${has ? 'pressed' : 'MISSING'}; hidden after: ${gone}`];
  });
  await step('job_check_box', async () => {
    const box = page.locator('textarea, input[type=text]').first();
    if (!(await box.count())) return [false, 'no job text box on the homepage'];
    await box.click(); await box.fill(lang === 'ar' ? 'أحتاج تركيب نوافذ ألمنيوم لفيلا في دبي، ٦ نوافذ' : 'I need 6 aluminium windows installed in a villa in Dubai');
    await page.waitForTimeout(500);
    const go = page.getByRole('button').filter({ hasText: lang === 'ar' ? /افحص|تحقق|ابدأ|اطلب|أرسل|التالي|عروض/ : /check my job|check|start|next|continue/i }).first();
    if (!(await go.count())) return [false, 'no button next to the job box'];
    // STOPS BEFORE SUBMIT (review of #1270): an anonymous press on production can reach a model and write a
    // row no run tag covers. Asserted: the box takes text and the button is present and enabled.
    const enabled = await go.isEnabled();
    return [enabled, `filled; "${(await go.innerText()).trim().slice(0, 40)}" present, enabled: ${enabled} — NOT pressed`];
  });
  await step('support_chat', async () => {
    await page.goto(SITE + (lang === 'ar' ? '/ar' : ''), { waitUntil: 'load' });
    const opener = page.locator('button[aria-label*="Ask QuotesDone" i], button[aria-label*="اسأل"], button[aria-label*="chat" i], button[aria-label*="help" i], button[aria-label*="محادث"], button[aria-label*="مساعد"], [class*=chat i] button').first();
    if (!(await opener.count())) return [false, 'no support chat launcher found'];
    await opener.click(); await page.waitForTimeout(1200);
    const input = page.locator('textarea:visible, input[type=text]:visible').last();
    if (!(await input.count())) return [false, 'chat opened but no input'];
    await input.fill(lang === 'ar' ? 'كيف تعمل الخدمة؟' : 'How does QuotesDone work?');
    // STOPS BEFORE SEND (review of #1270): an anonymous visitor's question is a live model call outside any
    // tagged window. Reply quality is measured by the support scenario suite, not here.
    return [await input.isEditable(), 'opened; question typed — NOT sent (no model call outside a sandbox window)'];
  });
}

/** Fill the contact form with demo values and STOP before submit (never sends). */
async function contactForm(page, dir, rep, J) {
  const fields = await page.locator('form input:visible, form textarea:visible').count();
  try {
    await page.locator('form input[type=email]').first().fill('qd-browserwalk@example.invalid').catch(() => {});
    await page.locator('form input[name*=name i], form input[autocomplete=name]').first().fill('ZZ DEMO Browser Walk').catch(() => {});
    await page.locator('form textarea').first().fill('ZZ DEMO — browser walk, not sent.').catch(() => {});
  } catch { /* reported below */ }
  const submit = await page.locator('form button[type=submit], form button').count();
  const file = join(dir, 'contact_filled_not_sent.png');
  await page.screenshot({ path: file, fullPage: true }).catch(() => {});
  rep.add({ journey: J, step: 'contact form (filled, not submitted)', status: fields && submit ? 'PASS' : 'FAIL', detail: `${fields} fields, ${submit} buttons`, issues: fields && submit ? [] : [{ sev: 'high', what: 'contact form missing fields or submit' }], shot: file });
}

// ---- PORTALS (signed in as the sandbox run's demo identities) ------------------------------------
/** A session for an EXISTING demo user: admin sets a fresh password on that @example.invalid user only. */
export async function demoSessionFactory(email) {
  if (!/@example\.invalid$/i.test(email)) throw new Error(`refused: ${email} is not a demo identity`);
  const { keys, BASE } = await import('../lib/demo_factory.mjs');
  const { ANON, SERVICE } = await keys();
  const h = { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' };
  const list = await (await fetch(`${BASE}/auth/v1/admin/users?per_page=50&filter=${encodeURIComponent(email)}`, { headers: h })).json();
  const u = (list.users || []).find((x) => x.email?.toLowerCase() === email.toLowerCase());
  if (!u) throw new Error('no auth user for ' + email);
  const password = 'Walk-' + Math.random().toString(36).slice(2) + 'A1!';
  const up = await fetch(`${BASE}/auth/v1/admin/users/${u.id}`, { method: 'PUT', headers: h, body: JSON.stringify({ password }) });
  if (!up.ok) throw new Error('admin password set failed ' + up.status);
  return async () => {
    const r = await fetch(`${BASE}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
    const s = await r.json(); if (!s.access_token) throw new Error('sign-in failed ' + r.status); return s;
  };
}

/** customers.locale for a demo customer: the language the portal must render once signed in. */
async function registeredLocale(email) {
  const { read } = await import('./fixtures.mjs');
  const l = (await read(`select locale from public.customers where email = ${sq(email)} and is_demo`))[0]?.locale;
  return l === 'ar' ? 'ar' : 'en';
}

/** Walk every tab a portal offers: click each nav item, screenshot, judge. */
export async function walkPortal(browser, who, view, lang) {
  const J = `${who.kind}_${who.label}_${view}_${lang}`;
  const dir = join(OUT, who.kind + 's', `${who.label}_${view}_${lang}`);
  mkdirSync(dir, { recursive: true });
  const rep = new Report(J);
  // A real phone (isMobile, touch), not a desktop window resized: signedInPage owns both (walk f4294be8 resized).
  const { ctx, page } = await signedInPage(browser, who, { lang, viewport: view });
  const bag = instrument(page);
  const base = SITE + (lang === 'ar' ? '/ar' : '') + (who.kind === 'customer' ? '/me' : '/portal');
  // THE ACCOUNT'S LANGUAGE DECIDES ONCE SIGNED IN, NOT THE URL (founder 14 Sep 2026, src/lib/documentLocale.ts adoptLocale):
  // an English-registered customer opening /ar/me is moved to /me in English, an Arabic one on /me to /ar/me. Walk
  // f4294be8 judged C1 on /ar/me as Arabic and reported the product doing exactly that as "not RTL". Judge the
  // registered language, and check the URL followed it. Suppliers are English only.
  const want = who.kind === 'customer' ? await registeredLocale(who.email) : 'en';
  let r = await visit(page, bag, base, join(dir, '00_landing.png'), { lang: want, audience: who.kind });
  if (who.kind === 'customer') {
    await page.waitForFunction((w) => document.documentElement.lang === w, want, { timeout: 15000 }).catch(() => {});
    r.url = page.url();
    const onAr = /^\/ar(\/|$)/.test(new URL(page.url()).pathname);
    if (onAr !== (want === 'ar')) { r.status = 'FAIL'; r.issues.unshift({ sev: 'high', what: `registered language ${want} but the URL stayed ${new URL(page.url()).pathname}` }); }
    if (want !== lang) r.note = `opened ${base}; account registered ${want}, so judged as ${want}`;
  }
  rep.add({ journey: J, step: 'landing', ...r });
  console.log(`${r.status} ${J} landing ${r.ms}ms ${r.issues.map((i) => i.what.slice(0, 80)).join(' ; ')}`);
  // NAV ITEMS A PERSON CAN PRESS (walk f4294be8): allInnerTexts also returned the hidden sidebar (md:hidden / display:none
  // on a phone) and the desktop-hidden phone tab bar, so "More" was pressed on desktop and "Overview" on a phone matched
  // the hidden sidebar button first; each waited out its timeout and that wait was reported as a 5.3 s / 35 s "slow load".
  // Labels come from visible items, plus the phone's "More" sheet; a label is pressed where it is visible, opening the
  // sheet only when it lives there; the supplier portal has no sheet, so nothing waits on one.
  const navSel = 'nav a:visible, nav button:visible';
  const more = page.locator('button[aria-controls="qd-nav-more"]:visible');
  // While the sheet is open its backdrop (fixed, inset-0) lies over the tab bar, so a tap on "More" lands on the backdrop,
  // which closes the sheet - the same result for a person. A pointer click from the walk is refused as intercepted, so the
  // toggle is dispatched instead.
  const openSheet = async (open) => { if (await more.count() && (await more.getAttribute('aria-expanded')) !== String(open)) { await more.dispatchEvent('click'); await page.waitForTimeout(300); } };
  const textsNow = async () => (await page.locator(navSel).allInnerTexts().catch(() => [])).map((s) => s.trim().split('\n')[0].trim()).filter(Boolean);
  let labelsAll = await textsNow();
  // Only the sheet's section rows: its language, theme and sign-out buttons are not tabs (pressing the language one
  // re-registers the account's language).
  if (await more.count()) { await openSheet(true); labelsAll = labelsAll.concat((await page.locator('#qd-nav-more [role=group] button:visible').allInnerTexts()).map((x) => x.trim()).filter(Boolean)); await openSheet(false); }
  const moreLabel = (await more.count()) ? (await more.innerText()).trim() : null;
  const labels = [...new Set(labelsAll)].filter((l) => l !== moreLabel).slice(0, 20);
  let i = 1;
  for (const label of labels) {
    bag.console.length = 0; bag.failed.length = 0;
    const byLabel = () => page.locator(navSel).filter({ hasText: new RegExp('^\\s*' + label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?:\\s|$)') }).first();
    await openSheet(false);
    if (!(await byLabel().count())) await openSheet(true);
    const t0 = Date.now();
    const clicked = await byLabel().click({ timeout: 5000 }).then(() => true).catch(() => false);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    const f = await domFacts(page);
    const file = join(dir, String(i++).padStart(2, '0') + '_' + slug(label) + '.png');
    await page.screenshot({ path: file, fullPage: true }).catch(() => {});
    r = judge(f, { lang: want, audience: who.kind, ms: Date.now() - t0, bag, url: page.url() });
    if (!clicked) { r.status = 'FAIL'; r.issues.unshift({ sev: 'high', what: `nav item "${label}" could not be pressed` }); }
    rep.add({ journey: J, step: 'tab: ' + label, ...r, shot: file });
    console.log(`${r.status} ${J} tab:${label} ${r.issues.map((x) => x.what.slice(0, 80)).join(' ; ')}`);
  }
  await ctx.close();
}

async function walkPortals(browser, idsFile) {
  // { tag, walk:[{kind:'customer'|'supplier', email, label}] } — read-only tab walk, still the run's identities only.
  const ids = JSON.parse(readFileSync(idsFile, 'utf8'));
  const closed = await sandboxGate({ tag: ids.tag, ...Object.fromEntries((ids.walk || []).map((w, i) => ['w' + i, w])) }) ||
    ((ids.walk || []).some((w) => !new RegExp(`^qd-${ids.tag}-`, 'i').test(w.email)) ? 'identities not of run ' + ids.tag : null);
  if (closed) { console.log('SKIP portals — ' + closed); return; }
  for (const w of ids.walk) {
    const newSession = await demoSessionFactory(w.email);
    const who = { ...w, newSession };
    for (const view of ['desktop', 'mobile']) for (const lang of w.kind === 'supplier' ? ['en'] : ['en', 'ar']) {
      try { await walkPortal(browser, who, view, lang); } catch (e) { new Report(`${w.kind}_${w.label}_${view}_${lang}_error`).add({ step: 'walk', status: 'FAIL', issues: [{ sev: 'high', what: String(e.message).slice(0, 300) }] }); console.log('FAIL walk', w.email, e.message); }
    }
  }
}

// ---- JOURNEY STEPS (need the sandbox run's demo data) ----------------------------------------------
// ids.json for `journeys`: { customer:{email,label}, customerAr:{email,label}, supplier:{email,label} }.
// Every identity must be @example.invalid (demoSessionFactory refuses otherwise). Stripe is TEST only:
// the hosted page must be a cs_test_ session or the step refuses to type a card.
const DECLINE_CARD = '4000 0000 0000 0002';
const sq = (v) => `'${String(v).replace(/'/g, "''")}'`;

async function jstep(rep, J, page, dir, name, fn) {
  const t0 = Date.now(); let ok = false, detail = '';
  try { [ok, detail] = await fn(); } catch (e) { detail = 'threw: ' + String(e.message).slice(0, 200); }
  const file = join(dir, slug(name) + '.png');
  await page.screenshot({ path: file, fullPage: true }).catch(() => {});
  const status = ok === 'SKIP' ? 'SKIP' : ok ? 'PASS' : 'FAIL';
  rep.add({ journey: J, step: name, status, ms: Date.now() - t0, detail, issues: status === 'PASS' ? [] : [{ sev: status === 'SKIP' ? 'low' : 'high', what: detail }], shot: file });
  console.log(`${status} ${J} ${name} — ${detail.slice(0, 160)}`);
}

/** THE REQUEST BOX IS BEHIND "New request" (walk f4294be8): the dashboard has no textarea, so the terms step's fill
 *  waited 30 s and the drawing step found no file input. Press the button a customer presses, then return the box. */
export async function openNewRequest(page, lang) {
  const box = page.locator('#qd-intake-input');
  if (!(await box.isVisible().catch(() => false))) {
    await page.getByRole('button', { name: lang === 'ar' ? /طلب جديد/ : /new request/i }).first().click({ timeout: 10000 });
    await box.waitFor({ state: 'visible', timeout: 20000 });
  }
  return box;
}

async function customerJourney(browser, w, lang, view) {
  const { read, write } = await import('./fixtures.mjs');
  const { demoOfficePlanPng } = await import('../lib/demo_pdf.mjs');
  const { payHostedTestCheckout, TEST_CARD } = await import('./stripe_test_checkout.mjs');
  const J = `journey_customer_${w.label}_${view}_${lang}`;
  const dir = join(OUT, 'customers', `${w.label}_journey_${view}_${lang}`); mkdirSync(dir, { recursive: true });
  const rep = new Report(J);
  const who = { kind: 'customer', ...w, newSession: await demoSessionFactory(w.email) };
  const { ctx, page } = await signedInPage(browser, who, { lang, viewport: view });
  const me = SITE + (lang === 'ar' ? '/ar' : '') + '/me';
  await page.goto(me, { waitUntil: 'load' }); await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});

  // 1. Terms re-accept inline prompt: put THIS demo customer one version behind, then send a request.
  await jstep(rep, J, page, dir, 'terms re-accept inline prompt', async () => {
    const cur = (await read(`select value from public.app_secrets where key='customer_terms_version'`))[0]?.value;
    const orig = (await read(`select tos_version from public.customers where email = ${sq(w.email)} and is_demo`))[0]?.tos_version;
    if (orig === undefined) return [false, 'refused: no demo customer row for ' + w.email];
    let verdict;
    try {
      await write(`update public.customers set tos_version = 'v1' where email = ${sq(w.email)} and is_demo`, 'walk: terms one version behind (demo only)');
      await page.reload({ waitUntil: 'load' }); await page.waitForTimeout(3000);
      const box = await openNewRequest(page, lang);
      await box.fill(lang === 'ar' ? 'ZZ DEMO: أحتاج دهان شقة غرفتين في دبي' : 'ZZ DEMO: paint a two-bedroom apartment in Dubai');
      await box.press('Enter'); await page.waitForTimeout(6000);
      const alert = page.locator('[role=alert]').filter({ has: page.locator('input[type=checkbox]') }).first();
      if (!(await alert.isVisible().catch(() => false))) verdict = [false, `no inline re-accept prompt after send (current terms ${cur})`];
      else {
        await alert.locator('input[type=checkbox]').check(); await alert.getByRole('button').last().click(); await page.waitForTimeout(5000);
        const now = (await read(`select tos_version from public.customers where email = ${sq(w.email)}`))[0]?.tos_version;
        verdict = [now === cur, `prompt shown, ticked and accepted; tos_version after accept ${now} (want ${cur})`];
      }
    } finally {
      // RESTORED WHATEVER HAPPENED (review of #1270), then read back: a demo customer left a version behind
      // would make every later run meet the prompt for a reason this step created.
      await write(`update public.customers set tos_version = ${sq(orig)} where email = ${sq(w.email)} and is_demo`, 'walk: restore tos_version (demo only)');
    }
    const back = (await read(`select tos_version from public.customers where email = ${sq(w.email)}`))[0]?.tos_version;
    if (back !== orig) return [false, `${verdict?.[1] || ''}; RESTORE FAILED: tos_version ${back}, was ${orig}`];
    return [verdict[0], `${verdict[1]}; restored to ${back} (verified)`];
  });

  // 2. Drawing/photo upload on a new request (spec questions incl. "not sure" follow in the chat).
  await jstep(rep, J, page, dir, 'new request: drawing upload + spec answer "not sure"', async () => {
    const png = join(dir, 'zz_demo_plan.png'); writeFileSync(png, demoOfficePlanPng());
    await openNewRequest(page, lang);
    const input = page.locator('input[type=file]').first();
    if (!(await input.count())) return [false, 'no file input on the new-request screen'];
    await input.setInputFiles(png); await page.waitForTimeout(15000);
    const notSure = page.getByRole('button').filter({ hasText: lang === 'ar' ? /لست متأكد|غير متأكد/ : /not sure/i }).first();
    const ns = await notSure.count();
    if (ns) { await notSure.click(); await page.waitForTimeout(6000); }
    const body = await page.locator('body').innerText();
    return [/zz_demo_plan/i.test(body), `drawing named on screen: ${/zz_demo_plan/i.test(body)}; "not sure" offered: ${ns > 0}`];
  });

  // 3. Quotes and the comparison report (top-3 + full list).
  await jstep(rep, J, page, dir, 'quotes and comparison report', async () => {
    await page.locator('nav a, nav button').filter({ hasText: lang === 'ar' ? /طلبات|عروض/ : /request|quote/i }).first().click().catch(() => {});
    await page.waitForTimeout(4000);
    const body = await page.locator('body').innerText();
    return [/AED|درهم/.test(body), `prices on screen: ${/AED|درهم/.test(body)}; comparison words: ${/top|compare|مقارنة|أفضل/i.test(body)}`];
  });

  // 4-5. Reveal checkout: success (4242) then decline (0002), Stripe TEST only.
  for (const [name, card] of [['reveal checkout: test card success', TEST_CARD.number], ['reveal checkout: test card decline', DECLINE_CARD]]) {
    await jstep(rep, J, page, dir, name, async () => {
      const btn = page.getByRole('button').filter({ hasText: lang === 'ar' ? /كشف|اكشف|ادفع/ : /reveal|unlock|pay/i }).first();
      if (!(await btn.count())) return ['SKIP', 'no reveal button visible (needs an unrevealed quote)'];
      const [pop] = await Promise.all([page.waitForEvent('popup', { timeout: 8000 }).catch(() => null), btn.click()]);
      const sp = pop || page;
      await sp.waitForURL(/checkout\.stripe\.com/, { timeout: 30000 });
      if (!/cs_test_/.test(sp.url())) return [false, 'refused: checkout is not a TEST session'];
      await sp.locator('#cardNumber').waitFor({ timeout: 20000 });
      if (card === TEST_CARD.number) await payHostedTestCheckout(sp);
      else {
        await sp.locator('#cardNumber').fill(card); await sp.locator('#cardExpiry').fill(TEST_CARD.expiry); await sp.locator('#cardCvc').fill(TEST_CARD.cvc);
        await sp.locator('#billingName').fill(TEST_CARD.name).catch(() => {});
        if (await sp.locator('#billingCountry').count()) await sp.locator('#billingCountry').selectOption('AE');
        await sp.locator('button[type=submit]').click();
      }
      await sp.waitForTimeout(12000);
      await sp.screenshot({ path: join(dir, slug(name) + '_stripe.png') }).catch(() => {});
      if (card === DECLINE_CARD) {
        const onStripe = /checkout\.stripe\.com/.test(sp.url());
        const declined = onStripe && /declined/i.test(await sp.locator('body').innerText());
        if (onStripe) await sp.goto(me).catch(() => {});
        return [declined, `decline message on Stripe and no return: ${declined}`];
      }
      return [/quotesdone/.test(sp.url()), 'returned to ' + sp.url().slice(0, 100)];
    });
  }

  // 6. Post-reveal supplier details + rating.
  await jstep(rep, J, page, dir, 'post-reveal supplier details and rating', async () => {
    await page.goto(me, { waitUntil: 'load' }); await page.waitForTimeout(4000);
    const body = await page.locator('body').innerText();
    const star = page.getByRole('button', { name: /Rate 5 of 5|5 من 5/ }).first();
    if (!(await star.count())) return ['SKIP', `no rating stars visible (needs a revealed supplier); contact details shown: ${/\+971|@/.test(body)}`];
    const [res] = await Promise.all([page.waitForResponse((r) => (r.request().postData() || '').includes('rate_supplier'), { timeout: 30000 }).catch(() => null), star.click()]);
    return [!!res && res.status() < 400, `rate_supplier HTTP ${res?.status()}`];
  });

  // 7. Account page: terms version block + data export/erase request, STOP before the code.
  await jstep(rep, J, page, dir, 'account: terms version + data export request (stopped before code)', async () => {
    await page.locator('nav a, nav button, button').filter({ hasText: lang === 'ar' ? /الحساب|حسابي/ : /account/i }).first().click().catch(() => {});
    await page.waitForTimeout(3000);
    const ver = /v\d+|version|الإصدار/i.test(await page.locator('body').innerText());
    // Named controls (PrivacyControls.tsx, #1273). Export is read-only; erase is driven only to the code box:
    // the code goes to an @example.invalid address that is never delivered, and it is never entered.
    const exp = page.getByTestId('privacy-export'), erase = page.getByTestId('privacy-erase');
    if (!(await exp.count()) || !(await erase.count())) return [false, `terms version shown: ${ver}; NO data export/erase control on the account page`];
    const dl = page.waitForEvent('download', { timeout: 15000 }).catch(() => null);
    await exp.click(); const file = await dl;
    await page.getByTestId('privacy-erase-ack').check(); await erase.click();
    const codeBox = await page.getByTestId('privacy-code').waitFor({ timeout: 15000 }).then(() => true).catch(() => false);
    return [ver && !!file && codeBox, `terms version shown: ${ver}; export downloaded: ${!!file}; erase code box shown: ${codeBox} (not filled, nothing erased)`];
  });
  await ctx.close();
}

/** The unsubscribe link with a REAL token for a demo supplier; GET only, the confirm is never pressed. */
async function unsubscribeStep(browser, sup) {
  if (!/@example\.invalid$/i.test(sup.email)) throw new Error('refused: not a demo identity');
  const { read } = await import('./fixtures.mjs');
  const { createHmac } = await import('node:crypto');
  const key = (await read(`select value from public.app_secrets where key='unsubscribe_signing_key'`))[0]?.value;
  const t = createHmac('sha256', key).update(sup.email.toLowerCase()).digest('hex').slice(0, 20);   // = unsubscribe/index.ts tok()
  const rep = new Report('journey_unsubscribe_real_token');
  for (const view of ['desktop', 'mobile']) {
    const dir = join(OUT, 'suppliers', 'unsubscribe_' + view); mkdirSync(dir, { recursive: true });
    const { page, bag, close } = await openCtx(browser, view, 'en', join(OUT, 'videos'));
    const r = await visit(page, bag, `${SITE}/u/unsubscribe?e=${encodeURIComponent(sup.email)}&t=${t}`, join(dir, 'confirm_page.png'), { lang: 'en', audience: 'supplier' });
    const body = await page.locator('body').innerText().catch(() => '');
    if (!(await page.locator('button, input[type=submit]').count())) { r.status = 'FAIL'; r.issues.push({ sev: 'high', what: 'valid token but no confirm button: ' + body.slice(0, 120) }); }
    rep.add({ journey: 'unsubscribe', step: `${view}: GET with a valid token (confirm NOT pressed)`, ...r, detail: body.slice(0, 160) });
    console.log(`${r.status} unsubscribe ${view} ${body.slice(0, 100).replace(/\n/g, ' ')}`);
    await close('journey_unsubscribe_' + view);
  }
}

/** Licence upload on registration: supplier_registration_walk.mjs already owns it (own demo lead, own teardown). */
async function supplierRegistration() {
  const { spawnSync } = await import('node:child_process');
  const r = spawnSync(process.execPath, ['scripts/e2e/supplier_registration_walk.mjs', '--lang', 'en', '--vp', 'desktop,mobile'], { encoding: 'utf8', timeout: 900000, env: { ...process.env, QD_FIXTURES: '1' } });
  const out = (r.stdout || '') + (r.stderr || '');
  writeFileSync(join(OUT, 'supplier_registration_walk.log'), out);
  new Report('journey_supplier_registration_licence').add({ step: 'registration with licence upload (supplier_registration_walk.mjs)', status: r.status === 0 ? 'PASS' : 'FAIL',
    detail: out.split('\n').slice(-6).join(' | ').slice(0, 400), issues: r.status === 0 ? [] : [{ sev: 'high', what: `exit ${r.status}: ` + out.split('\n').filter((l) => /FAIL/.test(l)).slice(0, 3).join(' | ') }] });
  console.log('supplier registration walk exit', r.status);
}

/**
 * THE SANDBOX GATE (review of #1270). Journeys send requests, attach drawings and pay reveals, so they can
 * reach a model and write rows. They run ONLY on the stage-2 run's own data, inside its open window:
 *   - ids.tag names the run; its rehearsal_window row is open, models_allowed, and not expired;
 *   - every identity's email is that run's (qd-<tag>-…@example.invalid), so every row it writes carries the tag
 *     and the run's cleanup removes it.
 * Anything else is refused before a browser opens. Returns null when open, else the reason.
 */
export async function sandboxGate(ids) {
  const tag = String(ids.tag || '');
  if (!/^[0-9a-f]{8}$/.test(tag)) return 'ids.tag missing or not a run tag';
  const who = ['customer', 'customerAr', 'supplier'].map((k) => ids[k]).filter(Boolean);
  const bad = who.filter((w) => !new RegExp(`^qd-${tag}-[a-z]+\\d+@example\\.invalid$`, 'i').test(w.email));
  if (bad.length) return 'identities not of run ' + tag + ': ' + bad.map((w) => w.email).join(', ');
  const { read } = await import('./fixtures.mjs');
  const r = await read(`select count(*)::int n from public.rehearsal_window where run_tag = ${sq('qd_run:' + tag)}
                          and ended_at is null and models_allowed and expires_at > now()`);
  return r[0]?.n > 0 ? null : `no open models_allowed window for qd_run:${tag}`;
}

async function walkJourneys(browser, idsFile) {
  const ids = JSON.parse(readFileSync(idsFile, 'utf8'));
  const closed = await sandboxGate(ids);
  if (closed) {
    new Report('journeys_refused').add({ step: 'sandbox gate', status: 'SKIP', detail: closed, issues: [{ sev: 'low', what: 'journeys not run: ' + closed }] });
    console.log('SKIP journeys — ' + closed);
    return;
  }
  for (const view of ['desktop', 'mobile']) {
    if (ids.customer) await customerJourney(browser, ids.customer, 'en', view).catch((e) => console.log('FAIL customer journey', e.message));
    if (ids.customerAr) await customerJourney(browser, ids.customerAr, 'ar', view).catch((e) => console.log('FAIL customerAr journey', e.message));
  }
  if (ids.supplier) await unsubscribeStep(browser, ids.supplier);
  await supplierRegistration();
}

/** N cold loads of one page on iPhone 13, a fresh context each. */
async function remeasure(browser, path = '/services/cleaning', n = 3) {
  const rep = new Report('remeasure_' + slug(path) + '_mobile');
  const dir = join(OUT, 'public', 'remeasure'); mkdirSync(dir, { recursive: true });
  for (let i = 1; i <= n; i++) {
    const ctx = await browser.newContext({ ...VIEWS.mobile }); const page = await ctx.newPage(); const bag = instrument(page);
    const r = await visit(page, bag, SITE + path, join(dir, `${slug(path)}_${i}.png`), { lang: 'en', audience: 'public' });
    rep.add({ journey: 'remeasure', step: `${path} mobile cold load ${i}`, ...r });
    console.log(`${r.status} remeasure ${path} #${i} ${r.ms} ms`);
    await ctx.close();
  }
}

// ---- the index -----------------------------------------------------------------------------------
export function writeIndex() {
  const files = readdirSync(OUT).filter((f) => f.endsWith('.json'));
  const esc = (s) => String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);
  const rel = (p) => p ? p.replace(/\\/g, '/').replace(OUT.replace(/\\/g, '/') + '/', '') : '';
  let pass = 0, fail = 0, body = '';
  for (const f of files.sort()) {
    const steps = JSON.parse(readFileSync(join(OUT, f), 'utf8'));
    const p = steps.filter((s) => s.status === 'PASS').length; pass += p; fail += steps.length - p;
    body += `<h3>${esc(f.replace('.json', ''))} — ${p}/${steps.length} PASS</h3><table><tr><th>step</th><th>verdict</th><th>ms</th><th>issues</th><th>shot</th></tr>` +
      steps.map((s) => `<tr><td>${esc(s.step)}</td><td class="${s.status === 'PASS' ? 'ok' : 'bad'}">${s.status}</td><td>${s.ms ?? ''}</td><td>${(s.issues || []).map((i) => `<div>[${i.sev}] ${esc(i.what)}</div>`).join('')}</td><td>${s.shot ? `<a href="${esc(rel(s.shot))}">png</a>` : ''}</td></tr>`).join('') + '</table>';
  }
  const vids = existsSync(join(OUT, 'videos')) ? readdirSync(join(OUT, 'videos')).filter((v) => v.endsWith('.webm')) : [];
  writeFileSync(join(OUT, 'index.html'), `<!doctype html><meta charset="utf-8"><title>Browser walk</title><style>body{font:14px system-ui;margin:24px}table{border-collapse:collapse;margin-bottom:18px}td,th{border:1px solid #ccc;padding:3px 6px;vertical-align:top}.ok{color:#080}.bad{color:#b00;font-weight:600}</style>
<h1>Browser walk (founder ledger 1160)</h1><p>${pass} PASS · ${fail} FAIL · generated ${new Date().toISOString()} by scripts/e2e/browser_walk.mjs</p>
<h2>Videos</h2><ul>${vids.map((v) => `<li><a href="videos/${esc(v)}">${esc(v)}</a></li>`).join('')}</ul>${body}`);
  const idx = join(OUT, '..', 'INDEX.html');
  if (existsSync(idx)) {
    const html = readFileSync(idx, 'utf8');
    if (!html.includes('browser/index.html')) writeFileSync(idx, html.replace(/<h2>Folders<\/h2>/, `<h2>Browser walk</h2><p><a href="browser/index.html">browser/index.html</a> — real-browser walk, desktop + iPhone 13, EN + AR, PASS/FAIL per step</p><h2>Folders</h2>`));
  }
  console.log(`index: ${pass} PASS, ${fail} FAIL`);
}

// ---- main ------------------------------------------------------------------------------------------
if (import.meta.url === `file:///${process.argv[1].replace(/\\/g, '/')}` || process.argv[1]?.endsWith('browser_walk.mjs')) {
  mkdirSync(OUT, { recursive: true });
  const mode = process.argv[2] || 'public';
  if (mode === 'index') { writeIndex(); process.exit(0); }
  const browser = await launch();
  try {
    if (mode === 'public') await walkPublic(browser);
    else if (mode === 'portals') await walkPortals(browser, process.argv[3]);
    else if (mode === 'journeys') await walkJourneys(browser, process.argv[3]);
    else if (mode === 'remeasure') await remeasure(browser, process.argv[3] || '/services/cleaning', Number(process.argv[4] || 3));
  } finally { await browser.close(); writeIndex(); }
}
