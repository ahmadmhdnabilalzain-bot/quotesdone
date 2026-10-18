// THE CONTENT-SECURITY-POLICY, ONE BUILDER FOR BOTH PLACES THAT SEND IT (it_engineer, 19 Oct 2026).
//
// script-src carries NO 'unsafe-inline'. Pages get a per-request nonce from src/middleware.ts: Next
// reads the nonce out of the request's CSP header and stamps it on its own flight-data scripts, and
// the one inline script we write ourselves (BootPrefetch on /me) reads it with headers().
// Responses the middleware does not see (route handlers, the global not-found page Next prerenders
// for unmatched paths) get the policy from next.config.mjs with NO nonce, and there 'unsafe-inline'
// stays: the prerendered not-found page carries Next's inline flight scripts, which no per-request
// nonce can reach. Every [locale] page gets the nonced policy, where 'unsafe-inline' is absent.
// No 'strict-dynamic' (review of #1482): every chunk is 'self', pdf.js is the listed cdnjs host, and
// strict-dynamic would make browsers ignore that host list, blocking the vercel.live toolbar script
// on preview deployments.
// JSON-LD (<script type="application/ld+json">) is data, not script, and CSP does not govern it.
//
// Origins, all measured by grepping src/ (14 Sep 2026, kept as they were):
//   · Supabase (REST, edge functions, storage signed URLs, realtime websocket) — src/lib/supaEnv.ts.
//   · cdnjs.cloudflare.com — pdf.js script + its worker (CustomerPortal.tsx, SupplierPortal.tsx).
//   · blob: workers — three.js loaders; blob:/data: media and images — voice recordings, previews.
//   · 'wasm-unsafe-eval' — the self-hosted tesseract.js OCR core compiles WebAssembly (ocrClient.ts);
//     it permits wasm compilation only, never eval() of JavaScript.
// Stripe Checkout is a top-level navigation to the URL stripe_checkout returns, which CSP does not
// govern. No analytics script is loaded (CookieConsent.tsx: no analytics cookie is set).
//
// style-src KEEPS 'unsafe-inline': React `style={…}` props render as style attributes, which a nonce
// cannot cover (CSP nonces apply to <style>/<script> elements only), and the portals, chat widget and
// charts use them throughout. Removing it would break the layout; an inline style cannot run script.
const SUPA = new URL(process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://htdblwldjkcgjvmqkbeh.supabase.co').host;
const isDev = process.env.NODE_ENV !== 'production';
// Vercel injects its feedback toolbar on preview deployments only.
const vercelLive = process.env.VERCEL_ENV === 'preview' ? ' https://vercel.live' : '';

/** @param {string} [nonce] */
export function buildCsp(nonce) {
  const scriptNonce = nonce ? ` 'nonce-${nonce}'` : " 'unsafe-inline'";
  return [
    "default-src 'self'",
    `script-src 'self'${scriptNonce} 'wasm-unsafe-eval'${isDev ? " 'unsafe-eval'" : ''} https://cdnjs.cloudflare.com${vercelLive}`,
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' data: blob: https://${SUPA}`,
    "font-src 'self' data:",
    `connect-src 'self' https://${SUPA} wss://${SUPA}${vercelLive}${isDev ? ' ws:' : ''}`,
    `media-src 'self' blob: data: https://${SUPA}`,
    "worker-src 'self' blob: https://cdnjs.cloudflare.com",
    `frame-src 'self'${vercelLive}`,
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    ...(isDev ? [] : ['upgrade-insecure-requests']),
  ].join('; ');
}
