import createMiddleware from 'next-intl/middleware';
import { NextResponse, type NextRequest } from 'next/server';
import { routing } from './i18n/routing';
import { AE_DOMAIN_SERVES_SITE, aeRedirectTarget } from './lib/domains';

const intl = createMiddleware(routing);

// UAE visitors on quotesdone.com go to quotesdone.ae (TDRA, founder 14 Sep 2026). Gated by
// AE_DOMAIN_SERVES_SITE in src/lib/domains.ts; every page lives under [locale], so the matcher
// below already covers every page the rule is meant for.
export default function middleware(req: NextRequest) {
  const to = aeRedirectTarget({
    enabled: AE_DOMAIN_SERVES_SITE,
    host: req.headers.get('host'),
    country: req.headers.get('x-vercel-ip-country'),
    pathname: req.nextUrl.pathname,
    search: req.nextUrl.search,
    userAgent: req.headers.get('user-agent'),
  });
  return to ? NextResponse.redirect(to, 308) : intl(req);
}

export const config = {
  // Only the surfaces migrated to Next.js run through locale routing.
  // NOTE: individual blog posts (/blog/:slug) are now native pages, so they
  // must be listed here. Without the :path* entry they bypass locale routing
  // and fall through to the legacy catch-all rewrite.
  matcher: [
    '/', '/(ar|en)',
    // /os and /console were the OS admin console. The founder ruled the OS irrelevant on 8 Sep 2026
    // and it is deleted — the routes, the shell, its client and its twelve edge functions. Matching a
    // path that no longer exists costs a middleware run on every request to a 404.
    '/(ar|en)/portal', '/portal', '/(ar|en)/me', '/me', '/(ar|en)/supplier', '/supplier',
    '/terms', '/(ar|en)/terms', '/privacy', '/(ar|en)/privacy', '/cookie-policy', '/(ar|en)/cookie-policy', '/refund-policy', '/(ar|en)/refund-policy', '/supplier-agreement', '/(ar|en)/supplier-agreement', '/acceptable-use', '/(ar|en)/acceptable-use', '/disclaimer', '/(ar|en)/disclaimer', '/complaints', '/(ar|en)/complaints', '/complaints/status', '/(ar|en)/complaints/status', '/how-we-verify', '/(ar|en)/how-we-verify',
    '/about', '/(ar|en)/about', '/contact', '/(ar|en)/contact', '/faq', '/(ar|en)/faq', '/services', '/(ar|en)/services', '/blog', '/(ar|en)/blog',
    '/how-it-works', '/(ar|en)/how-it-works',
    // the Sealed brand book (noindex), 14 Sep 2026
    '/brand', '/(ar|en)/brand',
    '/services/:path*', '/(ar|en)/services/:path*',
    '/blog/:path*', '/(ar|en)/blog/:path*'
  ]
};
