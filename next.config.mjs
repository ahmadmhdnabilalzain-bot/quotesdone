import createNextIntlPlugin from 'next-intl/plugin';
const withNextIntl = createNextIntlPlugin('./src/i18n/request.ts');

// Legacy site (old HTML system) still owns everything not yet migrated.
const LEGACY = 'https://qd-site.vercel.app';

// Top-level paths still served by the legacy site. As each is migrated to
// Next.js, delete it from this list and the proxy stops.
const LEGACY_SEGMENTS = [
  'preview', 'workspace', 'setup-stripe',
];
const LEGACY_FILES = ['robots.txt', 'llms.txt', 'favicon.ico'];

function legacyRewrites() {
  const r = [];
  for (const s of LEGACY_SEGMENTS) {
    r.push({ source: `/${s}`, destination: `${LEGACY}/${s}` });
    r.push({ source: `/${s}/:path*`, destination: `${LEGACY}/${s}/:path*` });
  }
  for (const f of LEGACY_FILES) {
    r.push({ source: `/${f}`, destination: `${LEGACY}/${f}` });
  }
  r.push({ source: '/ar/app', destination: `${LEGACY}/ar/app` });
  r.push({ source: '/ar/app/:path*', destination: `${LEGACY}/ar/app/:path*` });
  return r;
}

/** @type {import('next').NextConfig} */
const nextConfig = {
  async redirects() {
    return [
      { source: '/app', destination: '/me', permanent: false },
      { source: '/app/:path*', destination: '/me', permanent: false },
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
  async rewrites() {
    return {
      beforeFiles: legacyRewrites(),
      fallback: [{ source: '/:path*', destination: `${LEGACY}/:path*` }],
    };
  },
};

export default withNextIntl(nextConfig);
