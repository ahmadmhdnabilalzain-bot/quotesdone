// THE HARNESS HOLDS ITS CONNECTIONS THE WAY A BROWSER DOES (16 Nov 2026, it_engineer; paid certification 9a97074e / 5c5ef298).
//
// A paid run sends the page's function calls through Node (supplier_registration_certification.mjs VIA_NODE, because this container
// cuts a browser connection at ~30 s). Node's fetch keeps an idle connection for 4 s only (undici's keepAliveTimeout default; Supabase
// sends no Keep-Alive header to lengthen it). The sign-in code takes 15-25 s to arrive by e-mail, so "Verify" always opened a NEW
// connection: a CONNECT through the session proxy and a TLS handshake. Measured from this container through the proxy, 16 Nov 2026
// (GET https://<project>.supabase.co/auth/v1/health, answered 401 by the gateway, no function and no database reached):
//   default dispatcher     after 6 s idle 362 ms, after 20 s idle 626 ms   (a new connection each time)
//   keepAliveTimeout 60 s  after 6 s idle  40 ms, after 20 s idle  25 ms   (the same connection)
// Run 1 J1 desktop "the code verifies and the registration form opens" was 3,140 ms against 3,000: login_otp verify 1,557 ms in the
// browser for 971 ms at the edge (function_edge_logs 15:00:57.363Z). A supplier's browser keeps its HTTP/2 connection to Supabase open
// for minutes, so the cost was the harness's, not his. The bar is unchanged; the harness stops adding a handshake to his step.
//
// Node installs its global dispatcher (an EnvHttpProxyAgent under NODE_USE_ENV_PROXY=1, an Agent otherwise) on the first fetch and keeps
// it at this symbol; the same class is built again with the longer idle time, so the proxy settings are read exactly as before.
// Prevented by: scripts/e2e/node_keepalive.test.mjs
const KEY = Symbol.for('undici.globalDispatcher.1');
export const KEEP_ALIVE_MS = 60_000, KEEP_ALIVE_MAX_MS = 600_000;

/** Replace Node's global fetch dispatcher with the same class holding idle connections for KEEP_ALIVE_MS. Idempotent. */
export async function holdConnectionsLikeABrowser() {
  if (!globalThis[KEY]) await fetch('http://127.0.0.1:9/').catch(() => {});   // makes Node install its dispatcher; nothing listens there
  const d = globalThis[KEY];
  if (!d || d.__qdHeld) return d || null;
  const held = new d.constructor({ keepAliveTimeout: KEEP_ALIVE_MS, keepAliveMaxTimeout: KEEP_ALIVE_MAX_MS });
  Object.defineProperty(held, '__qdHeld', { value: true });
  globalThis[KEY] = held;
  await d.close?.().catch?.(() => {});
  return held;
}
