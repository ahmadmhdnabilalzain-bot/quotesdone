import createMiddleware from 'next-intl/middleware';
import { routing } from './i18n/routing';
export default createMiddleware(routing);
export const config = {
  // Only the surfaces already migrated to Next.js run through locale routing.
  // Everything else (legacy /app, /suppliers, /services/*, /blog/*, /about,
  // /contact, legal, sitemap, etc.) bypasses middleware and falls through to
  // the legacy site via the catch-all rewrite in next.config.mjs.
  matcher: [
    '/', '/(ar|en)',
    '/(ar|en)/os', '/os', '/(ar|en)/console', '/console', '/(ar|en)/portal', '/portal', '/(ar|en)/me', '/me', '/(ar|en)/customer', '/customer', '/(ar|en)/supplier', '/supplier',
    '/terms', '/(ar|en)/terms', '/privacy', '/(ar|en)/privacy', '/cookie-policy', '/(ar|en)/cookie-policy', '/refund-policy', '/(ar|en)/refund-policy', '/supplier-agreement', '/(ar|en)/supplier-agreement', '/acceptable-use', '/(ar|en)/acceptable-use', '/disclaimer', '/(ar|en)/disclaimer', '/complaints', '/(ar|en)/complaints',
    '/about', '/(ar|en)/about', '/contact', '/(ar|en)/contact', '/faq', '/(ar|en)/faq', '/services', '/(ar|en)/services', '/blog', '/(ar|en)/blog',
    '/services/:path*', '/(ar|en)/services/:path*'
  ]
};
