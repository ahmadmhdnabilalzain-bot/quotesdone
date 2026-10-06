// scripts/e2e/browser_walk.mjs — the real-browser walk of founder ledger 1160 (it_engineer, QA for all seats).
//
//   node scripts/e2e/browser_walk.mjs public            # public site, desktop+iPhone 13, EN+AR, both domains
//   node scripts/e2e/browser_walk.mjs portals ids.json  # signed-in walks for the sandbox run's demo identities
//   node scripts/e2e/browser_walk.mjs index             # (re)write browser/index.html + link from INDEX.html
//
// Founder, ledger 1160: "test like a real user, in a real browser, not only through code". Journeys a-h
// drive the funnel mostly by API; this walks every PAGE as a visitor sees it and measures, per page:
// console errors, failed requests (4xx/5xx/aborted), load time (>4 s flagged), horizontal overflow,
// raw "messages." i18n keys, English on an Arabic customer page, Arabic on a supplier page (suppliers
// are English only), and controls that are unnamed or dead. Every page gets a screenshot; every journey
// a video.
//
// NOTHING REACHES A PERSON. Public pages are read only; the contact form is filled but never submitted.
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
    const vis = (el) => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
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
    const before = page.url();
    await go.click(); await page.waitForTimeout(4000);
    const txt = (await page.locator('body').innerText()).slice(0, 4000);
    const moved = page.url() !== before;
    return [moved || /aluminium|ألمنيوم|trade|sign|تسجيل|email|بريد/i.test(txt), `pressed "${(await go.innerText()).trim().slice(0, 40)}"; url ${moved ? 'changed to ' + page.url() : 'unchanged'}`];
  });
  await step('support_chat', async () => {
    await page.goto(SITE + (lang === 'ar' ? '/ar' : ''), { waitUntil: 'load' });
    const opener = page.locator('button[aria-label*="Ask QuotesDone" i], button[aria-label*="اسأل"], button[aria-label*="chat" i], button[aria-label*="help" i], button[aria-label*="محادث"], button[aria-label*="مساعد"], [class*=chat i] button').first();
    if (!(await opener.count())) return [false, 'no support chat launcher found'];
    await opener.click(); await page.waitForTimeout(1200);
    const input = page.locator('textarea:visible, input[type=text]:visible').last();
    if (!(await input.count())) return [false, 'chat opened but no input'];
    await input.fill(lang === 'ar' ? 'كيف تعمل الخدمة؟' : 'How does QuotesDone work?');
    await input.press('Enter');
    await page.waitForTimeout(15000);
    const body = await page.locator('body').innerText();
    const ar = (body.match(/[\u0600-\u06FF]+/g) || []).length;
    return [true, `asked; ${lang === 'ar' ? 'arabic words on page after reply: ' + ar : 'reply waited 15 s'}`];
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

/** Walk every tab a portal offers: click each nav item, screenshot, judge. */
async function walkPortal(browser, who, view, lang) {
  const J = `${who.kind}_${who.label}_${view}_${lang}`;
  const dir = join(OUT, who.kind + 's', `${who.label}_${view}_${lang}`);
  mkdirSync(dir, { recursive: true });
  const rep = new Report(J);
  const { ctx, page, consoleErrors } = await signedInPage(browser, who, { lang, viewport: 'desktop' });
  // signedInPage owns the session injection; our viewport + video ride on a fresh page in that context is not possible,
  // so re-create with the same init by resizing for mobile.
  if (view === 'mobile') await page.setViewportSize(VIEWS.mobile.viewport);
  const bag = instrument(page);
  const base = SITE + (lang === 'ar' ? '/ar' : '') + (who.kind === 'customer' ? '/me' : '/portal');
  let r = await visit(page, bag, base, join(dir, '00_landing.png'), { lang, audience: who.kind });
  rep.add({ journey: J, step: 'landing', ...r });
  console.log(`${r.status} ${J} landing ${r.ms}ms ${r.issues.map((i) => i.what.slice(0, 80)).join(' ; ')}`);
  const navSel = view === 'mobile' ? 'nav a, nav button, button[aria-controls="qd-nav-more"]' : 'nav a, nav button';
  const labels = [...new Set((await page.locator(navSel).allInnerTexts().catch(() => [])).map((s) => s.trim()).filter(Boolean))].slice(0, 20);
  let i = 1;
  for (const label of labels) {
    bag.console.length = 0; bag.failed.length = 0;
    const t0 = Date.now();
    if (view === 'mobile') await page.locator('button[aria-controls="qd-nav-more"]').first().click().catch(() => {});
    const el = page.locator(navSel).filter({ hasText: label }).first();
    const clicked = await el.click({ timeout: 5000 }).then(() => true).catch(() => false);
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    const f = await domFacts(page);
    const file = join(dir, String(i++).padStart(2, '0') + '_' + slug(label) + '.png');
    await page.screenshot({ path: file, fullPage: true }).catch(() => {});
    r = judge(f, { lang, audience: who.kind, ms: Date.now() - t0, bag, url: page.url() });
    if (!clicked) { r.status = 'FAIL'; r.issues.unshift({ sev: 'high', what: `nav item "${label}" could not be pressed` }); }
    rep.add({ journey: J, step: 'tab: ' + label, ...r, shot: file });
    console.log(`${r.status} ${J} tab:${label} ${r.issues.map((x) => x.what.slice(0, 80)).join(' ; ')}`);
  }
  await ctx.close();
}

async function walkPortals(browser, idsFile) {
  const ids = JSON.parse(readFileSync(idsFile, 'utf8'));   // [{kind:'customer'|'supplier', email, label}]
  for (const w of ids) {
    const newSession = await demoSessionFactory(w.email);
    const who = { ...w, newSession };
    for (const view of ['desktop', 'mobile']) for (const lang of w.kind === 'supplier' ? ['en'] : ['en', 'ar']) {
      try { await walkPortal(browser, who, view, lang); } catch (e) { new Report(`${w.kind}_${w.label}_${view}_${lang}_error`).add({ step: 'walk', status: 'FAIL', issues: [{ sev: 'high', what: String(e.message).slice(0, 300) }] }); console.log('FAIL walk', w.email, e.message); }
    }
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
  } finally { await browser.close(); writeIndex(); }
}
