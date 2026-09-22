// A FRESH DEPLOY IS COLD, SO THE DEPLOY WARMS IT (22 Sep 2026, customer_support + it_engineer).
//
// MEASURED. After merge 4fb90cd the post-deploy smoke failed "[a customer] overview data under 2.5 s"
// (en-desktop 4,947 ms, ar-desktop 3,412 ms). All six overview functions had been redeployed at
// 04:31-04:32Z (the change touched _shared, which widens the deploy to every importer) and the smoke
// measured at 04:38Z. function_edge_logs put the time inside the platform, not the code: in en-desktop
// all six calls took 3.2-3.6 s server-side at once; in ar-desktop only the two calls that landed on a
// second worker (my_inquiries, threads) did. Reproduced at 06:40Z with a ZZ DEMO customer after
// customer_api alone was redeployed (06:35Z): its first two calls took 3,051 and 2,860 ms server-side
// and every later one 408-562 ms, while the five functions not redeployed answered in 220-1,096 ms from
// the first call. In function_logs each slow request's worker logged "booted (time: 47-67ms)" about
// 2.8 s AFTER the request arrived: the wait is the new bundle reaching a worker, before boot is timed.
// Nothing in any function changed; the first customer after every deploy paid it.
//
// SO: after a verified deploy, every deployed function that answers the keep-warm header
// (`x-qd-warm: 1`, checked first thing in the handler, 204 with no auth and no database) is called a few
// times in parallel in the database region, the region the portal pins (src/lib/supaEnv.ts FN_REGION).
// A function that does not answer the header is never called: a bare request to it would run its real
// handler. Best-effort: a warm call that fails is printed and never fails the deploy.
//
// Checked by scripts/checks/a_fresh_deploy_is_warmed_before_a_customer_reaches_it.test.mjs.

export const WARM_REGION = 'ap-southeast-1';

/** The deployed slugs whose handler answers the keep-warm header. `source(slug)` returns index.ts. */
export function warmable(slugs, source) {
  return slugs.filter((s) => {
    let src = '';
    try { src = source(s); } catch { return false; }
    // The code, not a comment: a comment mentioning the header must not make a function "warmable".
    const code = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1');
    return /req\.headers\.get\('x-qd-warm'\) === '1'\) return new Response\(null, \{ status: 204 \}\)/.test(code);
  });
}

/**
 * `rounds` rounds of `fanout` parallel keep-warm calls per slug, `gapMs` apart. Returns, per slug, the
 * slowest call of each round and how many answered 204, so the log shows the cold round and the warm
 * one side by side rather than claiming "warmed".
 */
export async function warmFunctions({ url, anon, slugs, rounds = 3, fanout = 4, gapMs = 1500, timeoutMs = 15000, fetchImpl = fetch }) {
  const out = {};
  for (const s of slugs) out[s] = { slowest_ms: [], ok: 0, calls: 0 };
  for (let r = 0; r < rounds; r++) {
    if (r) await new Promise((ok) => setTimeout(ok, gapMs));
    await Promise.all(slugs.map(async (s) => {
      const ms = await Promise.all(Array.from({ length: fanout }, async () => {
        const t0 = Date.now();
        try {
          const res = await fetchImpl(`${url}/functions/v1/${s}?forceFunctionRegion=${WARM_REGION}`, {
            method: 'GET', headers: { 'x-qd-warm': '1', apikey: anon, Authorization: 'Bearer ' + anon },
            signal: AbortSignal.timeout(timeoutMs) });
          await res.body?.cancel?.().catch(() => {});
          if (res.status === 204) out[s].ok++;
        } catch { /* counted as not ok */ }
        out[s].calls++;
        return Date.now() - t0;
      }));
      out[s].slowest_ms.push(Math.max(...ms));
    }));
  }
  return out;
}
