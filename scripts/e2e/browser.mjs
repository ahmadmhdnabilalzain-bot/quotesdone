// scripts/e2e/browser.mjs — a signed-in portal page without an OTP, and the measurements a journey needs.
//
// SESSION INJECTION. Both portals are single-page apps that decide "signed in" from localStorage
// (src/components/me/CustomerPortal.tsx, src/components/portal/SupplierPortal.tsx):
//   customer  qd-cust-token + qd-cust-refresh, and supabase-js's own session under storageKey qd-cust-auth
//   supplier  qd-sup-token  + qd-sup-refresh,  and supabase-js's own session under storageKey qd-portal-auth
// All THREE keys are written. Writing only the two tokens is the trap recorded in quotesdone-session §7:
// the mount effect calls SB.auth.getSession() and would restore whichever session qd-*-auth held.
import { chromium } from 'playwright';

export const SITE = process.env.QD_SITE || 'https://quotesdone.com';
export const VIEWPORTS = { desktop: { width: 1440, height: 900 }, mobile: { width: 375, height: 812 } };

const KEYS = {
  customer: { token: 'qd-cust-token', refresh: 'qd-cust-refresh', auth: 'qd-cust-auth', path: '/me' },
  supplier: { token: 'qd-sup-token', refresh: 'qd-sup-refresh', auth: 'qd-portal-auth', path: '/portal' },
};

export const portalUrl = (kind, lang, query = '') => `${SITE}${lang === 'ar' ? '/ar' : ''}${KEYS[kind].path}${query}`;

export async function launch() {
  const headless = process.env.QD_HEADED !== '1';
  try {
    return await chromium.launch({ headless });
  } catch (e) {
    // `playwright install chromium` on this machine fetched the full build but not the headless shell
    // (measured 14 Sep 2026: ms-playwright held chromium-1148 only). Fall back to the full build.
    if (!/Executable doesn't exist/.test(String(e.message))) throw e;
    // Then the Chrome or Edge already installed on the machine - no download needed.
    for (const channel of ['chrome', 'msedge']) {
      try { return await chromium.launch({ headless, channel }); } catch { /* try the next one */ }
    }
    throw e;
  }
}

/**
 * A browser context signed in as `who` (a fixture from fixtures.mjs), in `lang` at `viewport`.
 * Returns { ctx, page, consoleErrors, calls } where calls records every edge-function round trip.
 */
export async function signedInPage(browser, who, { lang = 'en', viewport = 'desktop' } = {}) {
  const k = KEYS[who.kind];
  const vp = VIEWPORTS[viewport];
  const ctx = await browser.newContext({
    viewport: vp, locale: lang === 'ar' ? 'ar-AE' : 'en-GB',
    ...(viewport === 'mobile' ? { isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : {}),
  });
  const s = who.session;
  await ctx.addInitScript(([k, s, lang]) => {
    try {
      localStorage.setItem(k.token, s.access_token);
      localStorage.setItem(k.refresh, s.refresh_token);
      localStorage.setItem(k.auth, JSON.stringify({
        access_token: s.access_token, refresh_token: s.refresh_token, expires_in: s.expires_in,
        expires_at: s.expires_at, token_type: s.token_type || 'bearer', user: s.user,
      }));
      localStorage.setItem('qd-lang', lang);
      localStorage.setItem('qd-cookie-consent', JSON.stringify({ necessary: true, analytics: false, marketing: false, ts: Date.now() }));
    } catch { /* storage blocked: the page will show sign-in, and the journey reports it */ }
  }, [k, s, lang]);
  // QD_KYC_URL: the kyc edge function served from THIS checkout (deno, against the same project), so a
  // kyc change is driven through the real screens before it is deployed. Only kyc is rerouted; the
  // round trip is made from Node, so an https page can reach a local http server.
  if (process.env.QD_KYC_URL) {
    await ctx.route(/\/functions\/v1\/kyc(\?|$)/, async (route) => {
      const req = route.request();
      const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, content-type, apikey, x-client-info', 'access-control-allow-methods': 'POST, OPTIONS' };
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 200, headers: cors, body: 'ok' });
      const res = await fetch(process.env.QD_KYC_URL, { method: req.method(), headers: { authorization: req.headers()['authorization'] || '', 'content-type': 'application/json' }, body: req.postData() });
      return route.fulfill({ status: res.status, headers: { ...cors, 'content-type': 'application/json' }, body: await res.text() });
    });
  }
  const page = await ctx.newPage();
  const consoleErrors = [];
  page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 300)); });
  page.on('pageerror', (e) => consoleErrors.push('pageerror: ' + String(e.message).slice(0, 300)));
  const calls = [];
  page.on('requestfinished', async (req) => {
    const u = req.url();
    if (!u.includes('/functions/v1/')) return;
    // timing().startTime is epoch ms; responseEnd is ms after it. Both are kept so a report can say
    // which call started when and how long it took - "6 calls, 3.7 s" alone could not tell serial
    // from slow (smoke run 34888342875, 14 Sep 2026).
    const t = req.timing();
    let action = null;
    try { action = JSON.parse(req.postData() || '{}').action ?? null; } catch { /* not JSON */ }
    const res = await req.response().catch(() => null);
    const ms = Math.round(t.responseEnd >= 0 ? t.responseEnd : 0);
    calls.push({ fn: u.split('/functions/v1/')[1].split('?')[0], action, status: res?.status() ?? 0,
      ms, startAt: Math.round(t.startTime), at: Date.now() });
  });
  page.on('requestfailed', (req) => {
    const u = req.url();
    if (u.includes('/functions/v1/')) calls.push({ fn: u.split('/functions/v1/')[1].split('?')[0], action: null, status: 0, ms: 0, failed: req.failure()?.errorText });
  });
  return { ctx, page, consoleErrors, calls };
}

/** Console noise that is not the product's: third-party trackers blocked by consent, extension chatter. */
export const IGNORABLE_CONSOLE = [/favicon/i, /Download the React DevTools/i, /googletagmanager|google-analytics|facebook\.net|clarity\.ms/i, /ERR_BLOCKED_BY_CLIENT/i];
export const realErrors = (errs) => errs.filter((e) => !IGNORABLE_CONSOLE.some((re) => re.test(e)));

/** Navigate and time it: ms until the portal nav is visible, and ms until its data calls settled. */
// Desktop: the sidebar <nav>. Phone (375px): the bottom bar's More button - the <nav> there is hidden,
// and waiting for it cost 30 s per page on the first phone run.
export const PORTAL_READY = 'nav:visible, button[aria-controls="qd-nav-more"]:visible';

export async function openPortal(page, url, calls, navSelector = PORTAL_READY) {
  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.locator(navSelector).first().waitFor({ state: 'visible', timeout: 30000 }).catch(() => {});
  const shellMs = Date.now() - t0;
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  const mine = calls.filter((c) => c.at >= t0);
  const dataMs = mine.length ? Math.max(...mine.map((c) => c.at)) - t0 : shellMs;
  // Each call as "<fn>:<action> @<start after navigation> +<duration>", in start order, so a slow
  // call and a call that waited for another are told apart in the report.
  const breakdown = mine.slice().sort((a, b) => (a.startAt || 0) - (b.startAt || 0))
    .map((c) => `${c.fn}${c.action ? ':' + c.action : ''} @${c.startAt ? c.startAt - t0 : '?'} +${c.ms}`);
  return { shellMs, dataMs, calls: mine.length, breakdown };
}

export async function shot(page, dir, name) {
  const file = `${dir}/${name.replace(/[^a-z0-9_.-]+/gi, '_')}.png`;
  await page.screenshot({ path: file, fullPage: false }).catch(() => {});
  return file;
}
