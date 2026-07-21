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

/** @type {import('next').NextConfig} */
const nextConfig = {
  async redirects() {
    return [
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
      { source: '/os2', destination: '/os', permanent: false },
      { source: '/os2/:path*', destination: '/os', permanent: false },
      { source: '/os3', destination: '/os', permanent: false },
      { source: '/os3/:path*', destination: '/os', permanent: false },
      { source: '/crm', destination: '/os', permanent: false },
      { source: '/crm/:path*', destination: '/os', permanent: false },
      { source: '/admin', destination: '/os', permanent: false },
      { source: '/admin/:path*', destination: '/os', permanent: false },
    ];
  },
};

export default withNextIntl(nextConfig);
