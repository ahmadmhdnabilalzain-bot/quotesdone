// THE COOKIE NOTICE NEVER COVERS THE FIRST BUTTON (12 Nov 2026, customer_support; founder ruling 1645). Found on production with a
// fresh browser profile, iPhone 13 emulation (390 wide, 664 visible): /portal?join=1 opened on "Register as a supplier" and the
// cookie notice, fixed at the bottom and 157 px tall, covered the lower half of "Create my account". Every earlier walk had a
// cookie choice stored, which is why none saw it. Measured on a local production build of main the same day: the bar covered
// "Create my account" at 360x640, 375x667 and 390x664, and "Open the supplier portal" on /supplier at the same three sizes.
// Since then (src/components/CookieConsent.tsx): on a phone the notice is one row in the page flow at the top, laid out in the
// first paint (html[data-qd-cookie="ask"], set by the layout's inline script before any content), so it covers nothing and
// nothing moves; from sm up it is the bar fixed at the bottom with its height kept free below the page.
//
// Two parts. The SOURCE part always runs. The BROWSER part opens a first visit (nothing stored) on a local production build and
// fails if the notice's box and the first primary button's box intersect on /portal?join=1 at 360x640 and 390x664, or if the page
// shifts (CLS >= 0.05). It uses QD_RENDER_BASE (e.g. http://localhost:3207, a `next start` you run) or, when .next/BUILD_ID exists
// (after `npm run build`, as the gate's next-build step leaves it), starts `next start` on a free port itself. Every request not to
// that local server is aborted, so it reaches nothing outside the machine. With neither, the browser part says so and is skipped.
//   node --test scripts/checks/the_cookie_notice_never_covers_the_first_button.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { spawn } from 'node:child_process';
import net from 'node:net';

const ROOT = new URL('../../', import.meta.url);
const R = (p) => readFileSync(new URL(p, ROOT), 'utf8');

test('source: the notice is in the first paint, in the flow on a phone, and hidden once a choice is stored', () => {
  const layout = R('src/app/[locale]/layout.tsx');
  const comp = R('src/components/CookieConsent.tsx');
  const ask = R('src/lib/cookieAsk.ts');
  const css = R('src/app/globals.css');
  assert.match(layout, /<script dangerouslySetInnerHTML=\{\{ __html: COOKIE_ASK \}\} \/>/, 'the layout no longer marks a first visit before the content');
  assert.ok(layout.indexOf('__html: COOKIE_ASK') < layout.indexOf('<CookieConsent />'), 'the mark must come before the notice');
  // 19 Nov 2026: #2072 mounted <OfflineBanner> ahead of the notice. It is fixed and renders nothing while online, so the
  // notice is still the first thing in the flow; it is allowed there only while it stays out of the flow.
  assert.match(layout, /<NextIntlClientProvider messages=\{messages\}>(?:<OfflineBanner [^>]*\/>)?<CookieConsent \/>\{children\}/, 'on a phone the notice must come before the page, in its flow');
  if (layout.includes('<OfflineBanner ')) {
    const offline = R('src/components/OfflineBanner.tsx');
    assert.match(offline, /if \(online\) return null;/, 'the offline banner ahead of the notice must render nothing while online');
    assert.match(offline, /className="fixed /, 'the offline banner ahead of the notice must be fixed, out of the page flow');
  }
  assert.match(ask, /setAttribute\('data-qd-cookie','ask'\)/);
  assert.match(layout, /import \{ COOKIE_ASK \} from '@\/lib\/cookieAsk';/, 'the server layout must take the mark from the plain module, not the client component');
  assert.match(layout, /<html lang=\{locale\} dir=\{[^}]*\} suppressHydrationWarning>/);
  assert.match(comp, /className="relative [^"]*sm:fixed sm:inset-x-0 sm:bottom-0 sm:z-60/, 'below sm the notice must not be fixed over the page');
  assert.doesNotMatch(comp, /className="relative z-60/, 'on a phone the notice must not sit above overlays near the top of the page (review item 2)');
  assert.match(comp, /-my-\[13px\] inline-block whitespace-nowrap py-\[13px\] [^"]*">\{t\('policy'\)\}/, 'the Cookie Policy link lost its 44 px tap height');
  assert.match(css, /html:not\(\[data-qd-cookie='ask'\]\) \[data-qd-cookie-notice\] \{\s*display: none;/);
  assert.match(css, /html\[data-qd-cookie='ask'\] body \{\s*padding-bottom: var\(--qd-cookie-h, 0px\);/);
  assert.match(comp, /<span className="hidden sm:inline">\{t\('text'\)\}/, 'on a phone the notice is one row: the long sentence is for sm up');
});

const freePort = () => new Promise((ok) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); }); });
async function server() {
  if (process.env.QD_RENDER_BASE) return { base: process.env.QD_RENDER_BASE.replace(/\/$/, ''), stop: () => {} };
  if (!existsSync(new URL('.next/BUILD_ID', ROOT))) return null;
  const port = await freePort();
  const child = spawn(process.execPath, [new URL('node_modules/next/dist/bin/next', ROOT).pathname, 'start', '-p', String(port)], { cwd: new URL('.', ROOT).pathname, stdio: process.env.QD_RENDER_DEBUG ? 'inherit' : 'ignore',
    // .next may be a link to tmpfs (the-gate-tree-is-not-the-lockfile): the server then finds its runtime only through NODE_PATH
    env: { ...process.env, NODE_PATH: new URL('node_modules', ROOT).pathname, NEXT_TELEMETRY_DISABLED: '1' } });
  const base = `http://localhost:${port}`;
  for (let i = 0; i < 120; i++) { try { const r = await fetch(base + '/portal'); if (r.ok) break; } catch { /* starting */ } await new Promise((r) => setTimeout(r, 500)); }
  return { base, stop: () => child.kill('SIGTERM') };
}

test('browser: on a first visit the notice never covers "Create my account" on /portal?join=1, and nothing shifts', async (t) => {
  const srv = await server();
  if (!srv) { t.skip('no local production build: run `npm run build` (or set QD_RENDER_BASE to a running `next start`)'); return; }
  const { chromium, devices } = await import('playwright');
  const browser = await chromium.launch({ headless: true, args: ['--no-proxy-server'] });
  try {
    for (const [w, h] of [[360, 640], [390, 664]]) {
      const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: true, hasTouch: true, userAgent: devices['iPhone 13'].userAgent });
      await ctx.addInitScript(() => { window.__cls = 0; try { new PerformanceObserver((l) => { for (const e of l.getEntries()) if (!e.hadRecentInput) window.__cls += e.value; }).observe({ type: 'layout-shift', buffered: true }); } catch {} });
      const host = new URL(srv.base).host;
      await ctx.route((u) => u.host !== host, (r) => r.abort());
      const page = await ctx.newPage();
      await page.goto(srv.base + '/portal?join=1', { waitUntil: 'load' });
      await page.waitForSelector('#qd-supplier-signin input', { state: 'attached', timeout: 30000 });
      await page.waitForTimeout(1500);
      const m = await page.evaluate(() => {
        const box = (e) => { if (!e) return null; const r = e.getBoundingClientRect(); return r.width && r.height ? { top: r.top, bottom: r.bottom, left: r.left, right: r.right } : null; };
        const notice = box(document.querySelector('[data-qd-cookie-notice]'));
        const btn = box([...document.querySelectorAll('#qd-supplier-signin button')].find((b) => /Create my account/.test(b.innerText)));
        return { notice, btn, cls: window.__cls, ask: document.documentElement.getAttribute('data-qd-cookie') };
      });
      await ctx.close();
      assert.equal(m.ask, 'ask', `${w}x${h}: a first visit was not marked (nothing stored, the notice must show)`);
      assert.ok(m.notice && m.btn, `${w}x${h}: the notice or "Create my account" was not found: ${JSON.stringify(m)}`);
      const meet = m.notice.top < m.btn.bottom && m.btn.top < m.notice.bottom && m.notice.left < m.btn.right && m.btn.left < m.notice.right;
      assert.ok(!meet, `${w}x${h}: the cookie notice covers "Create my account": ${JSON.stringify(m)}`);
      assert.ok(m.cls < 0.05, `${w}x${h}: the page shifted on a first visit, CLS ${m.cls}`);
    }
  } finally { await browser.close(); srv.stop(); }
});

// THE OPEN MENU NEVER HIDES ITS OWN CLOSE BUTTON (review of this change, blocker 1, 12 Nov 2026): on a first visit the notice pushes
// the header down 61 px and the sheet, fixed at 68 px, covered the header; a tap where the close button was opened "How it works".
// And (already on main, review note 12) a menu opened on a scrolled page put the close button at y -146. Here, on a first visit, in
// English and Arabic, at the top and scrolled: open the menu, the close button is on screen and is what a tap there hits, and the
// tap closes it.
test('browser: on a first visit the open menu keeps its close button reachable, at the top and scrolled, in English and Arabic', async (t) => {
  const srv = await server();
  if (!srv) { t.skip('no local production build: run `npm run build` (or set QD_RENDER_BASE to a running `next start`)'); return; }
  const { chromium, devices } = await import('playwright');
  const browser = await chromium.launch({ headless: true, args: ['--no-proxy-server'] });
  const fails = [];
  try {
    for (const [w, h] of [[360, 640], [390, 664]]) for (const path of ['/', '/ar']) for (const scroll of [0, 600]) {
      const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: true, hasTouch: true, userAgent: devices['iPhone 13'].userAgent });
      const host = new URL(srv.base).host;
      await ctx.route((u) => u.host !== host, (r) => r.abort());
      const page = await ctx.newPage();
      await page.goto(srv.base + path, { waitUntil: 'load' });
      await page.waitForTimeout(1200);
      if (scroll) { await page.evaluate((y) => window.scrollTo(0, y), scroll); await page.waitForTimeout(400); }
      // the phone menu's button (MobileNav): the visible one; the desktop dropdowns share the attributes but are hidden here
      const btn = page.locator('header .xl\\:hidden > button[aria-controls][aria-expanded]').first();
      await btn.tap();
      await page.waitForTimeout(500);
      const m = await page.evaluate(() => {
        const b = document.querySelector('header .xl\\:hidden > button[aria-controls][aria-expanded]');
        const r = b.getBoundingClientRect(); const x = r.left + r.width / 2, y = r.top + r.height / 2;
        const hit = document.elementFromPoint(x, y);
        return { expanded: b.getAttribute('aria-expanded'), top: Math.round(r.top), bottom: Math.round(r.bottom), on_screen: r.top >= 0 && r.bottom <= innerHeight, hits_itself: !!hit && (hit === b || b.contains(hit)), notice: document.documentElement.getAttribute('data-qd-cookie') };
      });
      const label = `${w}x${h} ${path} scroll ${scroll}`;
      if (m.notice !== 'ask') fails.push(`${label}: not a first visit`);
      if (m.expanded !== 'true') fails.push(`${label}: the menu did not open`);
      if (!m.on_screen || !m.hits_itself) fails.push(`${label}: the close button is hidden or covered: ${JSON.stringify(m)}`);
      else {
        await btn.tap(); await page.waitForTimeout(400);
        if ((await btn.getAttribute('aria-expanded')) !== 'false') fails.push(`${label}: tapping the close button did not close the menu`);
      }
      await ctx.close();
    }
  } finally { await browser.close(); srv.stop(); }
  assert.deepEqual(fails, []);
});
