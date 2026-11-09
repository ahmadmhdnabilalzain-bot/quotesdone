// @ts-nocheck
import { supaClient } from '@/lib/supaClient';
// The customer portal is the page a paying customer uses. Its Supabase target was an inline
// fallback to the production ref, so an unconfigured preview signed real customers in against the
// LIVE database. supaEnv resolves it once and warns on fallback; see the note there.
import { SUPA_ANON as ANON, fnUrl } from '@/lib/supaEnv';
import { retryRead, isReadAction } from '@/lib/fetchRetry';
// The five reads the dashboard makes on its first render, started beside the kyc gate rather than
// behind it — see prefetch.ts for the measurement. Keys are what Dashboard and DecisionSupport take.
import { warm } from './prefetch';

const SB = () => supaClient('qd-cust-auth');
// A TOKEN READ FROM localStorage IS NOT A TOKEN THAT STILL WORKS. It is restored synchronously on
// mount while the Supabase client refreshes asynchronously, so for the first moment after a page
// has been left open past the 60-minute expiry the portal holds a JWT that every endpoint will
// answer 401 to. The retry-then-refresh path recovers and the customer sees nothing, but it spends
// a round trip and prints a red error on a healthy page - and a console with routine errors in it
// is one where a real error is easy to miss. Cheaper to read the `exp` we already have.
// Sixty seconds of slack so a token about to die mid-flight is treated as already dead.
const tokenAlive = (t) => {
  if (!t) return false;
  try { return (JSON.parse(atob(String(t).split('.')[1])).exp || 0) > (Date.now() / 1000) + 60; }
  catch (_e) { return true; } // unparseable: let the endpoint be the judge, do not lock anyone out
};
const CALL_TIMEOUT_MS = 30000; // longer than any endpoint's own budget; this is the hang, not the slow answer
// The comparison report is the one call whose own budget is longer: quote_compare can take ~56 s on its own and the
// Arabic build may then reason until 90 s (customer_api ARABIC_COMPARE_BUDGET_MS), inside the 150 s edge wall. Cut
// at 30 s, the customer saw "timed out" instead of the 202 that says the Arabic report will be sent (PR #1574).
const COMPARE_PDF_TIMEOUT_MS = 150000;
async function call(path, body, token, timeoutMs = CALL_TIMEOUT_MS) {
  const ac = typeof AbortController === 'function' ? new AbortController() : null;
  const timer = ac ? setTimeout(() => ac.abort(), timeoutMs) : null;
  let r;
  try {
    r = await retryRead(async () => await fetch(fnUrl(path), { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) }, body: JSON.stringify(body), signal: ac ? ac.signal : undefined }), isReadAction(body), 2, () => !!(ac && ac.signal.aborted));
  } catch (e) {
    return { ok: false, error: (e && e.name === 'AbortError') ? 'qd_timeout' : 'qd_network' };
  } finally { if (timer) clearTimeout(timer); }
  const text = await r.text().catch(() => '');
  try { return JSON.parse(text); } catch (_e) { return { ok: false, error: 'qd_bad_response', status: r.status }; }
}
const warmDashboard = (tk, lang) => {
  // 'kyc' joins the warmed set so Authed.load() can take the promise BootPrefetch.tsx already
  // started at HTML-parse time. take() deletes on read, so load(retried) still asks fresh.
  warm(tk, 'kyc', () => call('kyc', { action: 'state' }, tk));
  warm(tk, 'inq', () => call('customer_api', { action: 'my_inquiries' }, tk));
  warm(tk, 'ov', () => call('customer_portal', { action: 'overview', lang }, tk));
  warm(tk, 'pd', () => call('project_api', { action: 'dashboard' }, tk));
  warm(tk, 'threads', () => call('messages_api', { action: 'threads' }, tk));
  warm(tk, 'decision_support', () => call('customer_portal', { action: 'decision_support', lang }, tk));
};
export { SB, tokenAlive, COMPARE_PDF_TIMEOUT_MS, call, warmDashboard };
