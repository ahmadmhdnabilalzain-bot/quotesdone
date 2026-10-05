// The origins that serve the website, and the one way an edge function builds a URL that sends a
// browser back to it. Keep in step with src/lib/domains.ts (the Next app's copy of the same list).
//
// 14 Sep 2026. The founder wants UAE visitors on quotesdone.ae (TDRA). A customer who starts a
// Stripe checkout on .ae must come back to .ae, because that is where their login session lives.
//
// Links in emails, WhatsApp and PDFs stay on https://quotesdone.com on purpose: they are not tied
// to a browser session, and the .com host sends UAE visitors to .ae itself.
//
// CORS: since 6 Oct 2026 the endpoints that return personal data answer only these origins (siteCors
// below); everything else still answers '*'. The .ae origins are in the list, so .ae is never refused.

export const CANONICAL_ORIGIN = 'https://quotesdone.com';

/**
 * The host the company trades under in the UAE. TDRA NOL-26-100000665 is issued for
 * www.quotesdone.ae and the founder's rule of 14 Sep is that a UAE visitor is served there.
 * Same constant as AE_ORIGIN in src/lib/domains.ts; the printed documents use the bare host
 * (_shared/doc_template.ts `web`). Use it where the AUDIENCE is known to be in the UAE and no
 * browser session is involved — a phone call, a printed page. A link in mail or WhatsApp still
 * goes to CANONICAL_ORIGIN, which redirects UAE visitors here itself.
 */
export const AE_ORIGIN = 'https://quotesdone.ae';

export const SITE_ORIGINS: readonly string[] = [
  'https://quotesdone.com',
  'https://www.quotesdone.com',
  'https://quotesdone.ae',
  'https://www.quotesdone.ae',
];

/**
 * The portal deep link a document prints: /me?request=<id>&quote=<id> (/ar/me for Arabic), on the
 * canonical origin. Ids only — never a supplier name. Same format as src/lib/portalLink.ts.
 */
export function portalLink(lang: string, requestId?: string, quoteId?: string): string {
  const base = CANONICAL_ORIGIN + (lang === 'ar' ? '/ar/me' : '/me');
  if (!requestId) return base;
  const qs = new URLSearchParams({ request: String(requestId) });
  if (quoteId) qs.set('quote', String(quoteId));
  return base + '?' + qs.toString();
}

const SITE_HOSTS = new Set(SITE_ORIGINS.map((o) => new URL(o).hostname));

/** An https URL on one of the site hosts, or on a Vercel preview. Anything else is refused. */
function allowed(raw: unknown): URL | null {
  try {
    const u = new URL(String(raw));
    if (u.protocol !== 'https:') return null;
    const h = u.hostname.toLowerCase();
    return SITE_HOSTS.has(h) || h.endsWith('.vercel.app') ? u : null;
  } catch { return null; }
}

/**
 * The base a browser should be returned to (origin + path, no trailing slash).
 *
 * 1. the body's return_url, when it is on an allowed host (keeps the /ar or /me path it carries);
 * 2. else the request's Origin header, when it is one of the site origins;
 * 3. else the canonical .com site.
 *
 * Step 1's host check is the open-redirect guard: a crafted return_url cannot send a paying
 * customer, with the Checkout Session id in the query string, to another domain.
 */
export function siteReturnBase(req: Request, returnUrl?: unknown): string {
  const u = returnUrl ? allowed(returnUrl) : null;
  if (u) return (u.origin + u.pathname).replace(/\/+$/, '');
  const origin = req.headers.get('origin') || '';
  if (SITE_ORIGINS.includes(origin)) return origin;
  return CANONICAL_ORIGIN;
}

// CORS FOR ENDPOINTS THAT RETURN PERSONAL DATA (pre-launch security pass, 6 Oct 2026, L6).
// Measured: 44 edge functions answered Access-Control-Allow-Origin '*'. They take a Bearer token,
// not a cookie, so '*' did not hand a session to another site, but it let any page that held a token
// (an injected script, a phishing copy of the portal) read the answer cross-origin. A browser is only
// allowed to read these answers from the four site origins and a localhost dev server; a request with
// no Origin header (curl, a server, a webhook) is untouched because CORS never applies to it.
// Vercel preview hosts are deliberately NOT allowed: a preview is not where a customer signs in.
const DEV_ORIGIN = /^http:\/\/(localhost|127\.0\.0\.1)(:\d{1,5})?$/;
export function corsOriginAllowed(origin: string | null): boolean {
  return !!origin && (SITE_ORIGINS.includes(origin) || DEV_ORIGIN.test(origin));
}
/**
 * Wraps a handler so its Access-Control-Allow-Origin names the caller's origin when that origin is a
 * site origin, and is ABSENT otherwise (the browser then refuses to hand the body to the page). The
 * handler keeps building its own CORS headers; this rewrites the one header after it answers, so a
 * function cannot forget it on one branch.
 */
export function siteCors(handler: (req: Request) => Response | Promise<Response>): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    const res = await handler(req);
    const origin = req.headers.get('origin');
    const headers = new Headers(res.headers);
    if (corsOriginAllowed(origin)) headers.set('Access-Control-Allow-Origin', origin!);
    else headers.delete('Access-Control-Allow-Origin');
    const vary = headers.get('Vary');
    if (!vary || !/\borigin\b/i.test(vary)) headers.set('Vary', vary ? vary + ', Origin' : 'Origin');
    return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
  };
}
