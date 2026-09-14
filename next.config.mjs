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

// ── SECURITY HEADERS (website audit 14 Sep 2026) ──────────────────────────────────────────────────
// Measured before this change: `curl -I https://quotesdone.com/` returned Strict-Transport-Security
// (Vercel's default) and nothing else — no CSP, nosniff, frame-ancestors, Referrer-Policy or
// Permissions-Policy. Every origin below is one the site loads TODAY, found by grepping src/:
//   · Supabase (REST, edge functions, storage signed URLs, realtime websocket) — src/lib/supaEnv.ts.
//     Same env var and same production fallback, so a preview pointed at another project is allowed.
//   · cdnjs.cloudflare.com — pdf.js script + its worker, CustomerPortal.tsx:279 and
//     SupplierPortal.tsx:93. Being replaced by a self-hosted build; drop it here when that lands.
//   · cdn.jsdelivr.net — drei <Text> with no `font` prop makes troika-three-text fetch glyph data
//     from jsdelivr (unicode-font-resolver@v1.0.1). Used by SupplierEnvironment.tsx:107.
//   (The founder photo on /about is self-hosted at public/brand/founder.jpg, so no photo host is listed.)
//   · blob: workers — troika builds its worker from a blob URL; three.js loaders do the same.
//   · blob:/data: media and images — voice recordings (MediaRecorder) and canvas previews.
// NOT allowed, on purpose: www.gstatic.com/draco (drei's default decoder host). The one model we
// ship, public/models/supplier-warehouse.gltf, has 0 KHR_draco/EXT_meshopt extensions, so the decoder
// is never requested. A compressed model must ship its decoder in /public, not pull it from Google.
// Stripe Checkout is a top-level navigation to the URL stripe_checkout returns, which CSP does not
// govern, so no Stripe origin is needed. No Vercel Analytics / Speed Insights package is installed.
//
// script-src keeps 'unsafe-inline' because Next's App Router inlines its flight data as <script>
// tags; removing it needs a per-request nonce, which forces every page dynamic and loses the static
// HTML the marketing pages are served from. The CSP still earns its keep through frame-ancestors,
// object-src, base-uri, form-action and a closed connect-src list.
//
// IN-BROWSER OCR (14 Sep 2026, src/components/me/ocrClient.ts). Paid vision is on hold and an Edge
// function has ~2 s of CPU, so photos and scanned BOQs are read by tesseract.js on the customer's
// machine. Its worker is a blob: URL (already allowed in worker-src) that importScripts() the pinned
// worker and core from cdn.jsdelivr.net, and importScripts inside a worker is governed by script-src:
//   · script-src  https://cdn.jsdelivr.net — tesseract.js@7.0.0/dist/worker.min.js and
//                 tesseract.js-core@7.0.0/*.wasm.js. Exact versions are pinned in ocrClient.ts.
//   · script-src  'wasm-unsafe-eval' — lets the core compile its WebAssembly. It permits wasm
//                 compilation only, not eval() of JavaScript.
//   · connect-src https://cdn.jsdelivr.net — already present (troika); the eng/ara traineddata
//                 (@tesseract.js-data/<lang>/4.0.0_best_int, 2.95 MB + 1.66 MB gzipped) is fetched.
//   · worker-src  https://cdn.jsdelivr.net — only if a browser refuses the blob: bootstrap and
//                 loads the worker URL directly.
const SUPA = new URL(process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://htdblwldjkcgjvmqkbeh.supabase.co').host;
const isDev = process.env.NODE_ENV !== 'production';
// Vercel injects its feedback toolbar on preview deployments only.
const vercelLive = process.env.VERCEL_ENV === 'preview' ? ' https://vercel.live' : '';

const CSP = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'${isDev ? " 'unsafe-eval'" : ''} https://cdnjs.cloudflare.com https://cdn.jsdelivr.net${vercelLive}`,
  "style-src 'self' 'unsafe-inline'",
  `img-src 'self' data: blob: https://${SUPA}`,
  "font-src 'self' data:",
  `connect-src 'self' https://${SUPA} wss://${SUPA} https://cdn.jsdelivr.net${vercelLive}${isDev ? ' ws:' : ''}`,
  `media-src 'self' blob: data: https://${SUPA}`,
  "worker-src 'self' blob: https://cdnjs.cloudflare.com https://cdn.jsdelivr.net",
  `frame-src 'self'${vercelLive}`,
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  ...(isDev ? [] : ['upgrade-insecure-requests']),
].join('; ');

const SECURITY_HEADERS = [
  { key: 'Content-Security-Policy', value: CSP },
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
