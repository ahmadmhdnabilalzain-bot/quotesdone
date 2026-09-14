import createMiddleware from 'next-intl/middleware';
import { routing } from './i18n/routing';
export default createMiddleware(routing);
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
    '/terms', '/(ar|en)/terms', '/privacy', '/(ar|en)/privacy', '/cookie-policy', '/(ar|en)/cookie-policy', '/refund-policy', '/(ar|en)/refund-policy', '/supplier-agreement', '/(ar|en)/supplier-agreement', '/acceptable-use', '/(ar|en)/acceptable-use', '/disclaimer', '/(ar|en)/disclaimer', '/complaints', '/(ar|en)/complaints',
    '/about', '/(ar|en)/about', '/contact', '/(ar|en)/contact', '/faq', '/(ar|en)/faq', '/services', '/(ar|en)/services', '/blog', '/(ar|en)/blog',
    '/how-it-works', '/(ar|en)/how-it-works',
    '/services/:path*', '/(ar|en)/services/:path*',
    '/blog/:path*', '/(ar|en)/blog/:path*'
  ]
};
