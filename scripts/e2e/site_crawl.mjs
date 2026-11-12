// Read-only browser crawl of the public site (ledger 1464: "every link smooth, quick, no glitches;
// browser proof required"). Visits every sitemap URL plus every internal link found from / and /ar,
// in English and Arabic, at desktop 1440 and mobile 390, on quotesdone.com (full) and quotesdone.ae
// (desktop, full list), and walks the redirect matrix of both domains. Only GETs and clicks on menus,
// the language switch, FAQ rows, the chat widget and the cookie banner: nothing is submitted or created.
// Usage: node scripts/e2e/site_crawl.mjs   (env: QD_CRAWL_OUT=out dir, QD_CRAWL_LIMIT=n pages for a trial)
import { chromium } from 'playwright';
import fs from 'node:fs';

const OUT = process.env.QD_CRAWL_OUT || 'crawl-out';
const LIMIT = Number(process.env.QD_CRAWL_LIMIT || 0);
const COM = 'https://quotesdone.com';
const AE = 'https://quotesdone.ae';
const VIEWS = { desktop: { width: 1440, height: 900 }, mobile: { width: 390, height: 844 } };
const LCP_MAX_MS = 4000;
const SKIP = /^\/(api|_next|_vercel|u)(\/|$)|\.(pdf|png|jpe?g|svg|ico|xml|txt|webp|zip)$/i;
fs.mkdirSync(OUT, { recursive: true });

const pool = async (items, n, fn) => {
  const q = [...items]; const out = [];
  await Promise.all(Array.from({ length: n }, async () => { for (let it; (it = q.shift());) out.push(await fn(it)); }));
  return out;
};

// ---- URL list -------------------------------------------------------------------------------
async function sitemapPaths() {
  const xml = await (await fetch(COM + '/sitemap.xml')).text();
  return [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => new URL(m[1]).pathname);
}
async function linkedPaths(browser, seeds) {
  const found = new Set(); const ctx = await browser.newContext(); const page = await ctx.newPage();
  for (const s of seeds) {
    await page.goto(COM + s, { waitUntil: 'load', timeout: 45000 }).catch(() => {});
    const hrefs = await page.$$eval('a[href]', (as) => as.map((a) => a.getAttribute('href')));
    for (const h of hrefs) {
      try { const u = new URL(h, COM + s); if (u.origin === COM || u.origin === AE) found.add(u.pathname.replace(/(.)\/$/, '$1')); } catch {}
    }
  }
  await ctx.close(); return found;
}

// ---- one page visit -------------------------------------------------------------------------
const LATIN_RUN = /(?:[A-Za-z][A-Za-z'’-]+\s+){2,}[A-Za-z][A-Za-z'’-]+/g; // 3+ consecutive English words
async function visit(browser, origin, path, viewName) {
  const ctx = await browser.newContext({ viewport: VIEWS[viewName], locale: path.startsWith('/ar') ? 'ar-AE' : 'en-US' });
  await ctx.addInitScript(() => {
    window.__lcp = 0;
    try { new PerformanceObserver((l) => { for (const e of l.getEntries()) window.__lcp = e.startTime; }).observe({ type: 'largest-contentful-paint', buffered: true }); } catch {}
  });
  const page = await ctx.newPage();
  const r = { origin, path, view: viewName, defects: [] };
  const bad = (k, d) => r.defects.push({ kind: k, detail: d });
  const consoleErrors = [], failed = [], http = [];
  page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 300)); });
  page.on('pageerror', (e) => consoleErrors.push('pageerror: ' + String(e.message).slice(0, 300)));
  page.on('requestfailed', (q) => { const e = q.failure()?.errorText || ''; if (!/ERR_ABORTED/.test(e)) failed.push(`${q.method()} ${q.url().slice(0, 160)} ${e}`); });
  page.on('response', (s) => { if (s.status() >= 400) http.push(`${s.status()} ${s.url().slice(0, 160)}`); });
  const t0 = Date.now();
  let resp = null;
  try { resp = await page.goto(origin + path, { waitUntil: 'load', timeout: 45000 }); }
  catch (e) { bad('navigation', String(e.message).split('\n')[0]); }
  r.status = resp?.status() ?? null;
  r.finalUrl = page.url();
  let hops = 0; for (let q = resp?.request().redirectedFrom(); q; q = q.redirectedFrom()) hops++;
  r.redirects = hops; if (hops > 3) bad('redirect-chain', `${hops} hops`);
  if (resp && r.status >= 400) bad('status', String(r.status));
  if (resp) {
    await page.waitForTimeout(1500);
    // scroll so lazy images load, then measure
    await page.evaluate(async () => { for (let y = 0; y < document.body.scrollHeight; y += 600) { window.scrollTo(0, y); await new Promise((r) => setTimeout(r, 60)); } window.scrollTo(0, 0); });
    await page.waitForTimeout(800);
    const m = await page.evaluate(() => {
      const n = performance.getEntriesByType('navigation')[0];
      const imgs = [...document.images].filter((i) => i.complete && i.naturalWidth === 0 && i.currentSrc).map((i) => i.currentSrc.slice(0, 140));
      const vis = (el) => { const s = getComputedStyle(el); return s.display !== 'none' && s.visibility !== 'hidden' && el.getClientRects().length > 0; };
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      const texts = []; for (let t; (t = walker.nextNode());) {
        const p = t.parentElement; if (!p || /^(SCRIPT|STYLE|NOSCRIPT|CODE|PRE)$/.test(p.tagName) || p.closest('[lang="en"],[translate="no"]') || !vis(p)) continue;
        const s = t.nodeValue.trim(); if (s.length > 12) texts.push(s);
      }
      return {
        load: n ? Math.round(n.loadEventEnd) : null, lcp: Math.round(window.__lcp),
        overflow: document.documentElement.scrollWidth - window.innerWidth,
        textLen: document.body.innerText.trim().length, brokenImgs: imgs,
        lang: document.documentElement.lang, dir: document.documentElement.dir, texts, title: document.title,
      };
    });
    r.load = m.load; r.lcp = m.lcp; r.overflow = m.overflow; r.title = m.title;
    if (m.textLen < 80) bad('blank', `text length ${m.textLen}`);
    if (m.overflow > 1) bad('horizontal-overflow', `${m.overflow}px wider than viewport`);
    if (m.brokenImgs.length) bad('broken-images', m.brokenImgs.join(' | '));
    if (m.lcp > LCP_MAX_MS) bad('slow-lcp', `${m.lcp} ms`);
    if (!m.title) bad('no-title', '');
    if (path.startsWith('/ar')) {
      if (m.lang !== 'ar' || m.dir !== 'rtl') bad('ar-lang-dir', `lang=${m.lang} dir=${m.dir}`);
      const eng = []; for (const t of m.texts) for (const hit of t.match(LATIN_RUN) || []) eng.push(hit.slice(0, 90));
      r.arEnglish = [...new Set(eng)].slice(0, 6);
      if (eng.length) bad('untranslated-arabic', `${eng.length} English runs, e.g. "${r.arEnglish[0]}"`);
    }
  }
  r.wallMs = Date.now() - t0;
  r.consoleErrors = [...new Set(consoleErrors)]; r.failedRequests = [...new Set(failed)]; r.httpErrors = [...new Set(http)];
  if (r.consoleErrors.length) bad('console-error', r.consoleErrors[0]);
  if (r.failedRequests.length) bad('failed-request', r.failedRequests[0]);
  if (r.httpErrors.length && !r.defects.some((d) => d.kind === 'status')) bad('subresource-http', r.httpErrors[0]);
  await ctx.close(); return r;
}

// ---- public-page interactions (no submits) ---------------------------------------------------
const stepper = (out, origin, path, view) => async (name, fn) => {
  try { const d = await fn(); out.push({ origin, path, view, name, ok: d === true || d === undefined, detail: d === true ? '' : String(d ?? '') }); }
  catch (e) { out.push({ origin, path, view, name, ok: false, detail: String(e.message).split('\n')[0] }); }
};
async function interactions(browser, origin, path, view) {
  const ctx = await browser.newContext({ viewport: VIEWS[view], locale: path.startsWith('/ar') ? 'ar-AE' : 'en-US' });
  const page = await ctx.newPage(); const out = []; const step = stepper(out, origin, path, view);
  await page.goto(origin + path, { waitUntil: 'load', timeout: 45000 });
  await page.waitForTimeout(1500);
  const ar = path.startsWith('/ar');
  await step('cookie banner shows with an enabled choice', async () => {
    const d = page.locator('[data-qd-cookie-notice] button').first();
    await d.waitFor({ state: 'visible', timeout: 6000 }); return (await d.isEnabled()) || 'disabled';
  });
  const burger = page.locator('button[aria-controls][aria-expanded]:visible').first();
  if (view === 'desktop') {
    await step('Services mega-menu opens, has links, Escape closes', async () => {
      const b = page.locator('nav button[aria-expanded]').first(); await b.click();
      const panel = page.locator('#' + (await b.getAttribute('aria-controls')));
      await panel.waitFor({ state: 'visible', timeout: 4000 });
      const n = await panel.locator('a[href]').count(); if (n < 5) return `only ${n} links`;
      await page.keyboard.press('Escape'); await page.waitForTimeout(300);
      return (await b.getAttribute('aria-expanded')) === 'false' || 'Escape did not close';
    });
  } else {
    await step('mobile menu opens, lists links, closes', async () => {
      await burger.click();
      const panel = page.locator('#' + (await burger.getAttribute('aria-controls'))); await panel.waitFor({ state: 'visible', timeout: 4000 });
      const n = await panel.locator('a[href]').count(); if (n < 4) return `only ${n} links`;
      await burger.click(); await page.waitForTimeout(400);
      return (await panel.count()) === 0 || !(await panel.isVisible()) || 'did not close';
    });
  }
  await step('language switch changes language', async () => {
    const find = () => page.locator('button:visible:has-text("العربية"), button:visible:has-text("English")').first();
    let sw = find();
    if (!(await sw.isVisible().catch(() => false)) && view === 'mobile') { await burger.click(); sw = find(); }
    await sw.click({ timeout: 4000 });
    await page.waitForURL((u) => u.pathname.startsWith('/ar') !== ar, { timeout: 8000 });
    return true;
  });
  await ctx.close(); return out;
}
async function faqAndWidget(browser, origin, path, view) {
  const ctx = await browser.newContext({ viewport: VIEWS[view], locale: path.startsWith('/ar') ? 'ar-AE' : 'en-US' });
  const page = await ctx.newPage(); const out = []; const step = stepper(out, origin, path, view);
  await page.goto(origin + path, { waitUntil: 'load', timeout: 45000 }); await page.waitForTimeout(1500);
  if (/\/faq$/.test(path)) await step('FAQ row opens', async () => {
    const row = page.locator('details.qa > summary').first(); await row.scrollIntoViewIfNeeded();
    const state = () => row.evaluate((e) => e.tagName === 'SUMMARY' ? e.parentElement.open : e.getAttribute('aria-expanded') === 'true');
    const a = await state(); await row.click(); await page.waitForTimeout(300);
    return a !== (await state()) || 'FAQ row did not toggle';
  });
  await step('chat widget opens and closes (nothing sent)', async () => {
    // the consent bar (z-60 from sm up) sits over the launcher (z-50) until a choice is made; "essential" only writes localStorage
    // (12 Nov 2026: the notice is [data-qd-cookie-notice], role=region, since the cookie-notice fix; it was role=dialog)
    const consent = page.locator('[data-qd-cookie-notice] button').first();
    if (await consent.isVisible().catch(() => false)) await consent.click();
    const launcher = page.locator('button[aria-label]:visible').last();
    await launcher.waitFor({ state: 'visible', timeout: 8000 });
    await launcher.click({ timeout: 5000 });
    const dlg = page.locator('div[role=dialog][aria-label]:not([aria-live])').first();
    await dlg.waitFor({ state: 'visible', timeout: 5000 });
    await dlg.locator('button').first().click(); await page.waitForTimeout(300);
    return !(await dlg.isVisible()) || 'did not close';
  });
  await ctx.close(); return out;
}

// ---- redirects -------------------------------------------------------------------------------
async function redirectMatrix() {
  const starts = [];
  for (const h of ['quotesdone.com', 'www.quotesdone.com', 'quotesdone.ae', 'www.quotesdone.ae']) for (const p of ['http://', 'https://']) starts.push(p + h + '/');
  starts.push(COM + '/en', COM + '/ar/', COM + '/about/', AE + '/ar', AE + '/services', COM + '/no-such-page-qd-crawl');
  const rows = [];
  for (const s of starts) {
    let url = s; const chain = []; let status = null;
    for (let i = 0; i < 10; i++) {
      let res; try { res = await fetch(url, { redirect: 'manual', headers: { 'user-agent': 'Mozilla/5.0 qd-crawl' } }); } catch (e) { chain.push('ERR ' + e.message); break; }
      status = res.status; chain.push(`${status} ${url}`);
      const loc = res.headers.get('location'); if (status >= 300 && status < 400 && loc) url = new URL(loc, url).href; else break;
    }
    const urls = chain.map((c) => c.split(' ').slice(1).join(' '));
    const loop = new Set(urls).size < urls.length || chain.length >= 10;
    const expect404 = s.includes('no-such-page');
    const ok = !loop && (expect404 ? status === 404 : status === 200) && chain.length <= 4;
    rows.push({ start: s, chain, final: status, ok, loop });
  }
  return rows;
}

// ---- main ------------------------------------------------------------------------------------
const browser = await chromium.launch();
const sm = await sitemapPaths();
const linked = await linkedPaths(browser, ['/', '/ar']);
let paths = [...new Set([...sm, ...linked, '/', '/ar'])].filter((p) => !SKIP.test(p)).sort();
if (LIMIT) paths = paths.slice(0, LIMIT);
console.log(`sitemap ${sm.length}, linked ${linked.size}, crawling ${paths.length} paths`);

const jobs = [];
for (const p of paths) for (const v of ['desktop', 'mobile']) jobs.push([COM, p, v]);
for (const p of paths) jobs.push([AE, p, 'desktop']);
const pages = await pool(jobs, 4, async ([o, p, v]) => {
  let r = await visit(browser, o, p, v);
  if (r.defects.length) { const again = await visit(browser, o, p, v); r = { ...again, firstTry: r.defects.map((d) => d.kind) }; } // a flake must repeat to count
  return r;
});

const inter = [];
const keyPages = ['/', '/ar', '/faq', '/ar/faq', '/services', '/ar/services'];
for (const [o, v] of [[COM, 'desktop'], [COM, 'mobile'], [AE, 'desktop']]) for (const p of keyPages) {
  inter.push(...await interactions(browser, o, p, v));
  inter.push(...await faqAndWidget(browser, o, p, v));
}
const redirects = await redirectMatrix();
await browser.close();

// ---- report ----------------------------------------------------------------------------------
const defects = pages.flatMap((r) => r.defects.map((d) => ({ ...d, where: `${r.origin}${r.path} [${r.view}]` })));
const failedInter = inter.filter((i) => !i.ok);
const failedRedir = redirects.filter((r) => !r.ok);
const slow = pages.filter((r) => r.lcp != null).sort((a, b) => (b.lcp || 0) - (a.lcp || 0)).slice(0, 10);
fs.writeFileSync(`${OUT}/report.json`, JSON.stringify({ paths: paths.length, pages, inter, redirects }, null, 1));
const md = [
  `# Site crawl ${new Date().toISOString()}`,
  `Paths ${paths.length}; page visits ${pages.length}; interactions ${inter.length}; redirect probes ${redirects.length}`,
  `Defects ${defects.length}; failed interactions ${failedInter.length}; failed redirects ${failedRedir.length}`,
  '## Defects', ...defects.map((d) => `- ${d.kind}: ${d.where}: ${d.detail}`),
  '## Failed interactions', ...failedInter.map((i) => `- ${i.origin}${i.path} [${i.view}] ${i.name}: ${i.detail}`),
  '## Redirects', ...redirects.map((r) => `- ${r.ok ? 'ok' : 'BAD'} ${r.chain.join(' -> ')}`),
  '## Slowest by LCP (ms)', ...slow.map((r) => `- ${r.lcp} lcp, ${r.load} load: ${r.origin}${r.path} [${r.view}]`),
].join('\n');
fs.writeFileSync(`${OUT}/report.md`, md); console.log(md);
if (defects.length || failedInter.length || failedRedir.length) process.exitCode = 1;
