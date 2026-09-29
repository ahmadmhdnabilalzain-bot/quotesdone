// RETRY A BLIP, NEVER A REAL FAILURE — one place for the rule, tested in retry.test.mjs.
//
// 21 Sep 2026. Two gates went red on the network rather than on the subject they measure, and every
// red run emails the founder:
//   - scripts/checks/edge_requests_show_no_attack_pattern.mjs read the edge logs with ONE request, so
//     one transient miss reported the log "unreadable" (exit 2).
//   - scripts/deploy_functions.mjs, main run 35619142770: 62/63 deployed; email_cron failed with
//     "Failed to bundle the function (reason: JSR package manifest for '@supabase/supabase-js'
//     failed to load. Fetch 'https://jsr.io/@supabase/supabase-js/meta.json' timed out after 10s".
//     The code was fine; jsr.io was slow for ten seconds.
//
// Both retry now. What is NOT retried is the point: a type error or a real bundle error in our own
// code fails at once, and a subject that stays unreadable after the last attempt still fails.

/** Run fn up to `attempts` times, sleeping baseMs, 2*baseMs, ... between tries; rethrow the last error. */
export async function withRetry(fn, attempts = 3, baseMs = 2000,
  sleep = (ms) => new Promise((s) => setTimeout(s, ms))) {
  let last;
  for (let i = 0; i < attempts; i++) {
    try { return await fn(); } catch (e) {
      last = e;
      if (i < attempts - 1) {
        console.error(`${String(e?.message || e).slice(0, 300)} (attempt ${i + 1}/${attempts}, retrying)`);
        await sleep(baseMs * 2 ** i);
      }
    }
  }
  throw last;
}

// A deploy failure is TRANSIENT only when its text names the network: a timeout, a reset, a gateway
// 502/503/504, or a module registry (jsr.io / esm.sh / deno.land) that failed to load. Anything else
// — a TS error, a missing import in our code, a 400 about our bundle — is real and fails at once.
// 28 Sep 2026, main run 36463025632: email_triage, role_guard, site_assistant and stripe_confirm each
// got `unexpected deploy status 500: {"message":"Function deploy failed due to an internal error"}` and
// were not retried. The next push diffs against ITS own parent, so those four stayed undeployed.
// Supabase's own "internal error" 500 names no bundle problem of ours, so it is a blip.
const NETWORK = /failed due to an internal error|timed out|ETIMEDOUT|ECONNRESET|ECONNREFUSED|EAI_AGAIN|socket hang up|\b50[234]\b|Bad Gateway|Service Unavailable|Gateway Time-?out/i;
const REGISTRY_LOAD = /(failed to load|error sending request|could not fetch|failed to fetch)[^\n]*(jsr\.io|esm\.sh|deno\.land)|(jsr\.io|esm\.sh|deno\.land)[^\n]*(failed to load|timed out)/i;
// A real error in our own source can mention a registry URL too (a bad import specifier), so these
// win over the network patterns: "Module not found" or a type error is never retried.
const REAL = /\bTS\d{3,5}\b|error: Module not found|Relative import path|is not exported|Unexpected token|Expected .* got|SyntaxError|Type error/i;

export function isTransientDeployFailure(text) {
  const t = String(text || '');
  if (!t.trim() || REAL.test(t)) return false;
  return NETWORK.test(t) || REGISTRY_LOAD.test(t);
}
