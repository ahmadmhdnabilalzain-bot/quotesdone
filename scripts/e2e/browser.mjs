// scripts/e2e/browser.mjs — a signed-in portal page without an OTP, and the measurements a journey needs.
//
// SESSION INJECTION. Both portals are single-page apps that decide "signed in" from localStorage
// (src/components/me/CustomerPortal.tsx, src/components/portal/SupplierPortal.tsx):
//   customer  qd-cust-token + qd-cust-refresh, and supabase-js's own session under storageKey qd-cust-auth
//   supplier  qd-sup-token  + qd-sup-refresh,  and supabase-js's own session under storageKey qd-portal-auth
// All THREE keys are written. Writing only the two tokens is the trap recorded in quotesdone-session §7:
// the mount effect calls SB.auth.getSession() and would restore whichever session qd-*-auth held.
import { chromium } from 'playwright';
import { holdConnectionsLikeABrowser, fetchLikeABrowser } from './node_keepalive.mjs';

export const SITE = process.env.QD_SITE || 'https://quotesdone.com';
export const VIEWPORTS = { desktop: { width: 1440, height: 900 }, mobile: { width: 375, height: 812 }, tablet: { width: 768, height: 1024 } };

const KEYS = {
  customer: { token: 'qd-cust-token', refresh: 'qd-cust-refresh', auth: 'qd-cust-auth', path: '/me' },
  supplier: { token: 'qd-sup-token', refresh: 'qd-sup-refresh', auth: 'qd-portal-auth', path: '/portal' },
};

export const portalUrl = (kind, lang, query = '') => `${SITE}${lang === 'ar' ? '/ar' : ''}${KEYS[kind].path}${query}`;

export async function launch() {
  const headless = process.env.QD_HEADED !== '1';
  // QD_CHROMIUM_ARGS: extra Chromium switches for a diagnostic run, e.g. "--disable-http2" (27 Oct 2026: separating a
  // cloud container's egress proxy from production when a long request failed at 30 s with net::ERR_FAILED).
  const args = (process.env.QD_CHROMIUM_ARGS || '').split(/\s+/).filter(Boolean);
  try {
    return await chromium.launch({ headless, ...(args.length ? { args } : {}) });
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

/** Thrown when the HARNESS's own session is dead. Never a portal defect — see harnessSession(). */
export class HarnessSignedOut extends Error {
  constructor(msg) { super(HARNESS_SIGNED_OUT + ': ' + msg); this.name = 'HarnessSignedOut'; }
}

/**
 * The words every harness-session failure is announced with — in the thrown message and in the step
 * name run.mjs records — so one phrase is searchable across a report, a log and a workflow run.
 *
 * WHY IT MATTERS DOWNSTREAM. fn_it_journey_ingest assigns an owner from the JOURNEY LETTER alone
 * (a/b/c/f -> sales_engineer, d/e -> accountant), so a FAIL step raised on journey f becomes a
 * finding addressed to the sales_engineer. A harness failure delivered to a seat as their product
 * defect is the same mislabelling this change exists to remove, one layer downstream, which is why
 * report_to_it_engineer.mjs keeps that step out of the per-seat ingest — it identifies it by
 * run.json's own harness_signed_out value rather than importing this constant, because that file's
 * only other dependency is the database client and this module pulls in playwright.
 */
export const HARNESS_SIGNED_OUT = 'THE HARNESS IS SIGNED OUT';

/**
 * A SESSION OF THIS CONTEXT'S OWN — not a second copy of the first one.
 *
 * WHY. Every context used to be injected with the SAME session object the fixture minted once. The
 * project runs jwt_exp 3600 with refresh-token ROTATION on and a 10 s reuse interval, so the first
 * context to cross its refresh threshold rotates the pair and REVOKES the refresh token every other
 * context is still holding. The next context to try to refresh is signed out — measured as journey f
 * meeting a signed-out portal ~17 minutes into a run ("FAIL … offered: (empty)", "FAIL … 401"), and
 * reported as a portal defect because a signed-out portal renders no navigation at all.
 *
 * Rejected alternatives. `autoRefreshToken: false` on the injected client is not ours to set — the
 * PAGE constructs its own supabase-js client (src/lib/supaClient.ts) and a harness that reached in to
 * disable refresh would stop exercising the refresh path real users depend on. A single shared session
 * with refresh suppressed has the same problem one layer down.
 *
 * Minting per context is the fix: each password grant opens an INDEPENDENT refresh-token family, so
 * one context rotating its own pair cannot revoke another's. A fixture made before this (or one that
 * deliberately holds a fixed session) has no `newSession` and keeps the old behaviour.
 */
async function harnessSession(who) {
  // NO SILENT FALLBACK TO `who.session`. Falling back to the shared session when `newSession` is
  // absent would reopen this exact bug for the next fixture factory written from an older example,
  // and it would do it the same way it happened the first time: no exception, no log, just a run
  // whose evidence is wrong 17 minutes later. Every factory in fixtures.mjs attaches `newSession`;
  // a `who` that does not is a harness mistake and says so here, at the point of use.
  if (typeof who.newSession !== 'function') {
    throw new HarnessSignedOut(`fixture ${who.email || '(unnamed)'} (${who.kind}) carries no newSession(), so every context would share one ` +
      'refresh-token family and revoke it for the others. Add newSession to the factory in scripts/e2e/fixtures.mjs.');
  }
  // RETRIED, BECAUSE MINTING PER CONTEXT ASKS AUTH ~8x MORE OFTEN THAN HOLDING ONE SESSION DID.
  // Measured on the 18 Sep production run of journey f: the password grant came back as
  // "upstream request timeout" (not even JSON) on one of the eight contexts and took the whole
  // journey with it. A gateway blip is not a signed-out session, and answering it as one would be
  // the same mislabelling in the opposite direction. Three tries over ~3 s; if all three fail,
  // something is genuinely wrong with the session and it says so.
  let last;
  for (let i = 0; i < 3; i++) {
    try { return await who.newSession(); } catch (e) { last = e; await new Promise((r) => setTimeout(r, 500 + i * 1000)); }
  }
  throw new HarnessSignedOut(`could not mint a session for ${who.email} (${who.kind}) in 3 tries — ${String(last?.message).slice(0, 200)}`);
}

/** Only a call to THIS project's edge functions may carry the run tag and its credential. */
export function carriesRunTag(url, base) {
  try {
    const u = new URL(String(url)), b = new URL(String(base));
    return u.protocol === 'https:' && u.hostname === b.hostname && u.pathname.startsWith('/functions/v1/');
  } catch { return false; }
}

/**
 * A browser context signed in as `who` (a fixture from fixtures.mjs), in `lang` at `viewport`.
 * Returns { ctx, page, consoleErrors, calls } where calls records every edge-function round trip.
 */
export async function signedInPage(browser, who, { lang = 'en', viewport = 'desktop' } = {}) {
  const k = KEYS[who.kind];
  // A named viewport, or an explicit { width, height } (inquiry_box_visible.mjs walks five sizes).
  const vp = typeof viewport === 'object' ? viewport : VIEWPORTS[viewport];
  const ctx = await browser.newContext({
    viewport: vp, locale: lang === 'ar' ? 'ar-AE' : 'en-GB',
    ...(vp.width < 768 ? { isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : {}),
  });
  // AI ON IN THE BROWSER TOO (ruling 1260). A fixture's model call is let through only for a proven run tag
  // in an open window (think.ts fixtureInOpenWindow); the API harness sends it, the browser did not, so every
  // portal action a walk drove ran with the models held. The tag and its credential ride ONLY on calls to the
  // Supabase edge functions, never to the site, Stripe or anything else.
  if (process.env.QD_E2E_RUN_TAG) {
    const { internalCred, BASE } = await import('../lib/demo_factory.mjs');
    const extra = { 'x-qd-e2e-run': process.env.QD_E2E_RUN_TAG, 'x-qd-e2e-secret': await internalCred() };
    // The predicate parses the URL: exact project host and path prefix, so no other host, page path or query
    // string that merely contains "/functions/v1/" can receive the credential (#1558 review).
    await ctx.route((u) => carriesRunTag(u, BASE), (route) => route.request().method() === 'OPTIONS' ? route.continue() : route.continue({ headers: { ...route.request().headers(), ...extra } }));
  }
  const s = await harnessSession(who);
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
  // A VERCEL PREVIEW HAS NO SUPABASE TARGET (src/lib/supaEnv.ts, 3 Sep 2026): with
  // NEXT_PUBLIC_SUPABASE_URL unset, a preview build calls `/functions/v1/...` on its OWN origin, which
  // 404s, so no signed-in portal can load there — deliberately, so a preview never writes production by
  // accident. This harness targets the one project on purpose and only with demo fixtures, so it forwards
  // exactly those same-origin calls to the project's functions. A production or main build calls Supabase
  // directly and never makes such a request, so on quotesdone.com this rule never fires.
  // (Measured 15 Sep 2026: journey g on preview 7dv2getlj crashed on "Couldn't load your account" —
  // kyc state -> 404 text/html from the preview itself.)
  await ctx.route(`${new URL(SITE).origin}/functions/v1/**`, async (route) => {
    const req = route.request();
    const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, content-type, apikey, x-client-info', 'access-control-allow-methods': 'POST, GET, OPTIONS' };
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 200, headers: cors, body: 'ok' });
    const { BASE } = await import('../lib/demo_factory.mjs');
    const target = BASE + '/functions/v1/' + req.url().split('/functions/v1/')[1];
    const h = req.headers();
    const res = await fetchLikeABrowser(target, { method: req.method(), headers: { authorization: h['authorization'] || '', 'content-type': h['content-type'] || 'application/json' }, body: req.method() === 'GET' ? undefined : req.postData() }).catch(() => null);
    if (!res) return route.abort('connectionreset');   // a second failure reaches the page as a network error, never an unhandled rejection
    return route.fulfill({ status: res.status, headers: { ...cors, 'content-type': res.headers.get('content-type') || 'application/json' }, body: Buffer.from(await res.arrayBuffer()) });
  });
  // THIS CONTAINER CUTS A BROWSER CONNECTION AT ABOUT 30 s (measured 27 Oct and again 10 Nov 2026). supplier_full_walk
  // c: extract_quote answered HTTP 200 at 30,974 ms in the edge log while the page got nothing ("blocked by CORS
  // policy: No 'Access-Control-Allow-Origin' header" on production, a 300 s waitForResponse timeout locally); Node
  // and curl get the same 200. QD_ROUTE_FUNCTIONS_VIA_NODE=1 sends the page's calls to the project's functions
  // through Node, so a run here judges the product and not the container. Off by default: the nightly and a real
  // browser go direct. The run-tag headers are forwarded, so a model call stays inside the run's capped window.
  if (process.env.QD_ROUTE_FUNCTIONS_VIA_NODE === '1') {
    const { BASE, internalCred } = await import('../lib/demo_factory.mjs');
    await holdConnectionsLikeABrowser();   // a browser keeps its connection across a wait; Node's fetch drops it after 4 s (node_keepalive.mjs)
    // Registered after the run-tag route, so it runs first (Playwright: last registered, first matched) and that
    // route's continue() never adds the tag: it is added here, on the same exact-host calls only.
    const tagged = process.env.QD_E2E_RUN_TAG ? { 'x-qd-e2e-run': process.env.QD_E2E_RUN_TAG, 'x-qd-e2e-secret': await internalCred() } : {};
    await ctx.route((u) => carriesRunTag(u, BASE), async (route) => {
      const req = route.request();
      const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, content-type, apikey, x-client-info, x-qd-e2e-run, x-qd-e2e-secret', 'access-control-allow-methods': 'POST, GET, OPTIONS' };
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 200, headers: cors, body: 'ok' });
      const h = req.headers();
      const fwd = { ...Object.fromEntries(['authorization', 'content-type', 'apikey', 'x-client-info'].filter((k) => h[k]).map((k) => [k, h[k]])), ...tagged };
      const res = await fetchLikeABrowser(req.url(), { method: req.method(), headers: fwd, body: req.method() === 'GET' ? undefined : req.postData() }).catch(() => null);
      if (!res) return route.abort('connectionreset');   // node_keepalive.mjs: retried once like a browser; a second failure is the page's
      return route.fulfill({ status: res.status, headers: { ...cors, 'content-type': res.headers.get('content-type') || 'application/json' }, body: Buffer.from(await res.arrayBuffer()) });
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

/**
 * THE HARNESS SAYS SO ITSELF RATHER THAN LETTING A JOURNEY MISREAD IT.
 *
 * A 401 on a portal's own edge call, made with a session this harness minted moments ago, can only
 * mean the harness's session died — and a signed-out portal renders no navigation, so every
 * assertion after that point fails and reads like a product defect. That mislabelling is the
 * expensive part: a whole run's evidence is silently WRONG, not merely missing. The portals answer
 * their own refusals {ok:false} at HTTP 200 (src/components/portal/supplier/api.ts) and every
 * function reserves 401 for a missing or invalid JWT, so 401 here is unambiguous.
 *
 * Exported because two journey-g steps navigate with page.goto instead of openPortal (they load a
 * portal mid-sign-up, where the nav openPortal waits for does not exist yet) and must not be the
 * one place a dead session can still be reported as a product assertion failure.
 */
export function assertHarnessSignedIn(calls, since, where) {
  const dead = calls.filter((c) => c.at >= since && c.status === 401);
  if (!dead.length) return;
  throw new HarnessSignedOut(`${where} answered 401 on ${[...new Set(dead.map((c) => c.fn + (c.action ? ':' + c.action : '')))].join(', ')}` +
    ' — the injected session is no longer valid. This is the harness, NOT a portal defect.');
}

export async function openPortal(page, url, calls, navSelector = PORTAL_READY) {
  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  const navUp = await page.locator(navSelector).first().waitFor({ state: 'visible', timeout: 30000 }).then(() => true).catch(() => false);
  const shellMs = Date.now() - t0;
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  const mine = calls.filter((c) => c.at >= t0);
  assertHarnessSignedIn(calls, t0, url);
  // A DEAD SESSION THAT NEVER GETS AS FAR AS A 401. supabase-js can decide on its own that the
  // stored session is unusable and put the portal back on its sign-in screen without ever calling a
  // function, so the 401 test above would see nothing. A portal that reached neither its navigation
  // NOR a single edge call in 30 s has not loaded signed in, and saying "no navigation" about it is
  // the same mislabelling one layer down. The two conditions together are what makes this safe: a
  // portal that is merely slow still makes its calls, and one that is merely quiet still has a nav.
  if (!navUp && !mine.length) {
    throw new HarnessSignedOut(`${url} showed no portal navigation and made no edge-function call in ${shellMs} ms` +
      ' — the page never loaded signed in. This is the harness, NOT a portal defect.');
  }
  const dataMs = mine.length ? Math.max(...mine.map((c) => c.at)) - t0 : shellMs;
  // Each call as "<fn>:<action> @<start after navigation> +<duration>", in start order, so a slow
  // call and a call that waited for another are told apart in the report.
  const breakdown = mine.slice().sort((a, b) => (a.startAt || 0) - (b.startAt || 0))
    .map((c) => `${c.fn}${c.action ? ':' + c.action : ''} @${c.startAt ? c.startAt - t0 : '?'} +${c.ms}`);
  return { shellMs, dataMs, calls: mine.length, breakdown };
}

/**
 * A full-page capture TAKEN FROM THE TOP OF THE DOCUMENT.
 *
 * WHY THE SCROLL. `page.screenshot({ fullPage: true })` paints `position: sticky` / `position:
 * fixed` chrome where it is STUCK at the moment of capture, then stitches that into an image of the
 * whole document — so a bar that a user only ever sees at the top of the window lands in the middle
 * of the picture, on top of whatever the document has at that offset. Measured 18 Sep 2026 on
 * https://quotesdone.com/portal: the supplier top bar's getBoundingClientRect().top is 0 at every
 * scroll offset (0 / 400 / 900, EN + AR, 1440x900 and 375x812), yet the same page captured with
 * fullPage while scrolled 275px put the bar across a paragraph. The founder read two of the merged
 * #725 captures (en_desktop_04 at y=158, en_desktop_07 at y=681) as a bar "moving up and down when
 * you scroll" and covering a job card. Nothing was wrong with the page; the capture was wrong.
 *
 * Scrolling to 0 first costs nothing — fullPage already captures the whole document — and makes the
 * picture agree with what a supplier sees.
 */
export async function fullPageShot(page, file) {
  await page.evaluate(() => window.scrollTo(0, 0)).catch(() => {});
  await page.waitForTimeout(150);
  await page.screenshot({ path: file, fullPage: true }).catch(() => {});
  return file;
}

export async function shot(page, dir, name, { fullPage = false } = {}) {
  const file = `${dir}/${name.replace(/[^a-z0-9_.-]+/gi, '_')}.png`;
  // The same reason fullPageShot scrolls first (#735): a capture taken part-way down the page shows
  // a sticky bar where a person never sees it. The crawl presses buttons that scroll, so its own
  // captures were as exposed to this as the ones the founder read. One line, every journey.
  if (fullPage) return fullPageShot(page, file);
  await page.evaluate(() => window.scrollTo(0, 0)).catch(() => {});
  await page.waitForTimeout(150);
  await page.screenshot({ path: file, fullPage: false }).catch(() => {});
  return file;
}

/** The customer's inquiry box, measured as a person sees it (scripts/e2e/inquiry_box_visible.mjs). Runs in the page. Returns the facts and the reasons the box is not usable (empty = usable). */
export function measureInquiryBox() {
  const el = document.getElementById('qd-intake-input');
  if (!el) return { problems: ['#qd-intake-input is not in the page'] };
  const r = el.getBoundingClientRect();
  const cs = getComputedStyle(el);
  const line = parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.4;
  const pad = parseFloat(cs.paddingTop) + parseFloat(cs.paddingBottom);
  // The part of the box an ancestor's overflow lets through, intersected with the window.
  let vis = { top: Math.max(r.top, 0), left: Math.max(r.left, 0), bottom: Math.min(r.bottom, innerHeight), right: Math.min(r.right, innerWidth) };
  const chain = [];
  for (let a = el.parentElement; a && a !== document.documentElement; a = a.parentElement) {
    const s = getComputedStyle(a); const ar = a.getBoundingClientRect();
    chain.push({ tag: a.tagName.toLowerCase(), id: a.id || undefined, cls: String(a.className).slice(0, 90), display: s.display, position: s.position,
      overflow: `${s.overflowX}/${s.overflowY}`, height: Math.round(ar.height), minH: s.minHeight, maxH: s.maxHeight, top: Math.round(ar.top), bottom: Math.round(ar.bottom) });
    if (s.overflowX !== 'visible' || s.overflowY !== 'visible') {
      vis = { top: Math.max(vis.top, ar.top), left: Math.max(vis.left, ar.left), bottom: Math.min(vis.bottom, ar.bottom), right: Math.min(vis.right, ar.right) };
    }
  }
  const visH = Math.max(0, vis.bottom - vis.top), visW = Math.max(0, vis.right - vis.left);
  const problems = [];
  if (r.height < 2 * line + pad - 1) problems.push(`box is ${Math.round(r.height)}px tall, under two lines (${Math.round(2 * line + pad)}px)`);
  if (visH < r.height - 1 || visW < r.width - 1) problems.push(`only ${Math.round(visW)}x${Math.round(visH)} of the ${Math.round(r.width)}x${Math.round(r.height)} box can be seen (clipped by an overflow ancestor or the window)`);
  if (r.width < 120) problems.push(`box is only ${Math.round(r.width)}px wide`);
  const covered = [];
  if (visH > 4 && visW > 4) {
    // Corner probes sit inside the rounded corner (a point in the cut-away corner hits the parent, not the box).
    const k = Math.max(4, parseFloat(cs.borderTopLeftRadius) || 0);
    const pts = [[(vis.left + vis.right) / 2, (vis.top + vis.bottom) / 2], [vis.left + k, vis.top + k], [vis.right - k, vis.top + k], [vis.left + k, vis.bottom - k], [vis.right - k, vis.bottom - k]];
    for (const [x, y] of pts) {
      const hit = document.elementFromPoint(x, y);
      if (hit !== el && !el.contains(hit)) covered.push(`${Math.round(x)},${Math.round(y)} -> ${hit ? hit.tagName.toLowerCase() + (hit.id ? '#' + hit.id : '') + '.' + String(hit.className).slice(0, 60) : 'nothing'}`);
    }
  }
  if (covered.length) problems.push('something lies on top of the box: ' + covered.join('; '));
  return { rect: { top: Math.round(r.top), left: Math.round(r.left), width: Math.round(r.width), height: Math.round(r.height) }, visible: { w: Math.round(visW), h: Math.round(visH) },
    textarea: { display: cs.display, visibility: cs.visibility, opacity: cs.opacity, height: cs.height, minH: cs.minHeight, lineHeight: cs.lineHeight, zIndex: cs.zIndex },
    window: { w: innerWidth, h: innerHeight, scrollY }, chain, problems };
}

