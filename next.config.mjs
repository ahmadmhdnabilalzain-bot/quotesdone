import createNextIntlPlugin from 'next-intl/plugin';
const withNextIntl = createNextIntlPlugin('./src/i18n/request.ts');

/**
 * The legacy HTML host (qd-site) has been retired. Everything it used to serve
 * is now native:
 *   /blog/:slug   -> src/app/[locale]/blog/[slug]        (from src/content/blog.json)
 *   /robots.txt   -> src/app/robots.txt/route.ts
 *   /ar/app       -> redirect to /ar/me
 * The old catch-all rewrite is gone; unmatched paths now return a normal 404
 * instead of proxying to a host that no longer exists.
 *
 * Still parked in the database and NOT served: /preview, /workspace,
 * /setup-stripe, /llms.txt. Nothing on the site links to them.
 */

import { buildCsp } from './src/lib/csp.mjs';

// ── SECURITY HEADERS (website audit 14 Sep 2026) ──────────────────────────────────────────────────
// The CSP and every origin in it are documented in src/lib/csp.mjs. This copy carries no nonce and
// covers requests the middleware does not see (route handlers, static files); src/middleware.ts
// replaces it with the nonced policy on every [locale] page.
const SUPA = new URL(process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://htdblwldjkcgjvmqkbeh.supabase.co').host;
const CSP = buildCsp();

const SECURITY_HEADERS = [
  { key: 'Content-Security-Policy', value: CSP },
  // HSTS WITH includeSubDomains (pre-launch security pass, 6 Oct 2026, L8). Vercel's default header was
  // max-age=63072000 alone, so a subdomain could still be reached over plain HTTP first. Measured on DNS
  // the same day: every name that serves the web (apex and www on .com and .ae) is HTTPS on Vercel; hello.,
  // mail., send., send.hello. and send.mail.quotesdone.com are MX/TXT only (no A record, no web), so HSTS
  // does not touch them; mail.quotesdone.ae has an A record to Vercel and no site or certificate behind
  // it, so nothing that works today is lost. `preload` is deliberately NOT sent: the preload list is
  // hard to leave, and a future plain-HTTP subdomain would be unreachable for months.
  { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains' },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'X-Frame-Options', value: 'DENY' }, // frame-ancestors for browsers that predate CSP2
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  // microphone=(self): the customer portal records voice briefs (getUserMedia, CustomerPortal.tsx).
  // Nothing on the site uses the camera stream, location, USB or payment-request APIs.
  { key: 'Permissions-Policy', value: 'microphone=(self), camera=(), geolocation=(), usb=(), payment=(), browsing-topics=()' },
];

// Signed-in app shells are not pages a search engine should index. The header works whatever the
// page files export; src/lib/seo.ts appShellMeta() gives them the matching <meta name=robots>.
const NOINDEX = [{ key: 'X-Robots-Tag', value: 'noindex, nofollow' }];
// /supplier is the public supplier sales page (indexable, its own canonical); only the signed-in
// shells are noindexed.
const APP_SHELLS = ['/me', '/portal'];

/** @type {import('next').NextConfig} */
const nextConfig = {
  // OUR MAIL LINKS TO OUR OWN DOMAIN (22 Sep 2026, customer_support; founder instructions 633/635).
  // mail-tester.com scored the supplier invitation 9.6/10; the only point lost was SpamAssassin
  // URI_NOVOWEL (-0.5), fired by the project host "htdblwldjkcgjvmqkbeh.supabase.co" in the unsubscribe
  // link and the logo URL. These two proxies let the mail name quotesdone.com instead. The query string
  // and the method pass through, so the RFC 8058 one-click POST still reaches the unsubscribe function,
  // and its relative form action ("?e=…") resolves against /u/unsubscribe.
  async rewrites() {
    const origin = `https://${SUPA}`;
    return [
      // /u/unsubscribe is a route handler (src/app/u/unsubscribe/route.ts) since 24 Sep 2026: a rewrite
      // passed Supabase's forced text/plain through, and the page showed as raw HTML source.
      { source: '/m/brand/:path*', destination: `${origin}/storage/v1/object/public/brand/:path*` },
    ];
  },
  async headers() {
    return [
      { source: '/:path*', headers: SECURITY_HEADERS },
      ...APP_SHELLS.flatMap((p) => [
        { source: p, headers: NOINDEX },
        { source: `${p}/:path*`, headers: NOINDEX },
        { source: `/:locale(en|ar)${p}`, headers: NOINDEX },
        { source: `/:locale(en|ar)${p}/:path*`, headers: NOINDEX },
      ]),
      // Self-hosted brand fonts are preloaded by URL from the locale layout (not through next/font,
      // which gave every page all 11 files). 30 days rather than immutable: fetch_fonts.mjs keeps
      // the file names across a version bump, so an immutable year would pin browsers to old glyphs.
      { source: '/fonts/:file*', headers: [{ key: 'Cache-Control', value: 'public, max-age=2592000, stale-while-revalidate=86400' }] },
    ];
  },
  async redirects() {
    return [
      // Audit 14 Sep: Supplier Agreement §16 linked /legal?doc=privacy, a 404. The text is fixed,
      // but copies accepted before the fix still carry the old link, so the old URL resolves too.
      { source: '/legal', has: [{ type: 'query', key: 'doc', value: 'privacy' }], destination: '/privacy', permanent: true },
      { source: '/ar/legal', has: [{ type: 'query', key: 'doc', value: 'privacy' }], destination: '/ar/privacy', permanent: true },
      { source: '/app', destination: '/me', permanent: false },
      { source: '/app/:path*', destination: '/me', permanent: false },
      { source: '/ar/app', destination: '/ar/me', permanent: false },
      { source: '/ar/app/:path*', destination: '/ar/me', permanent: false },
      // /customer was a second route rendering the identical CustomerPortal — a
      // pure duplicate. The route file is gone; /me is the single canonical URL.
      { source: '/customer', destination: '/me', permanent: false },
      { source: '/customer/:path*', destination: '/me', permanent: false },
      { source: '/ar/customer', destination: '/ar/me', permanent: false },
      { source: '/ar/customer/:path*', destination: '/ar/me', permanent: false },
      { source: '/suppliers', destination: '/portal', permanent: false },
      { source: '/suppliers/:path*', destination: '/portal', permanent: false },
    ];
  },
};

export default withNextIntl(nextConfig);
