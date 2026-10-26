// The origins that serve the website, and the one way an edge function builds a URL that sends a
// browser back to it. Keep in step with src/lib/domains.ts (the Next app's copy of the same list).
//
// 14 Sep 2026. The founder wants UAE visitors on quotesdone.ae (TDRA). A customer who starts a
// Stripe checkout on .ae must come back to .ae, because that is where their login session lives.
//
// Links in emails, WhatsApp and PDFs stay on https://quotesdone.com on purpose: they are not tied
// to a browser session, and the .com host sends UAE visitors to .ae itself.
//
// CORS: every edge function answers Access-Control-Allow-Origin '*' (measured 14 Sep 2026), so
// no allow-list rejects the .ae site. If one is ever narrowed, build it from SITE_ORIGINS.

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
