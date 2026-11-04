// THE MULTILINGUAL EMBEDDER, ASKED FROM A REQUEST PATH. Seat: it_engineer (shared platform). 23 Sep 2026.
//
// The model (45.5 MB, ml_embed.ts) runs in ONE place: the embed_ml function. A seat answering a customer
// (think.ts, case_recall.ts) asks it over HTTP instead of loading the model in its own worker, so a worker that
// runs out of memory loading it is embed_ml's, and here it is only a failed fetch: this returns null and the
// caller takes the gte-small path. (Review of #907, finding 1: an in-process load on wa_inbound or customer_api
// could kill the isolate mid-reply, which no try/catch can recover.)
// The credential is cred_fn_ai, the fn.ai context whose scope includes embed_ml; 'fn' names the caller in the audit.
import { errorText } from './error_text.ts';
import { notReached } from './not_reached.ts';
// deno-lint-ignore no-explicit-any
type Admin = any;

// ── which space the seats read ──────────────────────────────────────────────────────────────────
export type Space = 'ml' | 'gte';
let spaceCache: { v: Space; at: number } | null = null;
/** fn_ml_read_space, cached for a minute per worker. Any failure answers 'gte', the path that exists today. */
export async function readSpace(admin: Admin): Promise<Space> {
  if (spaceCache && Date.now() - spaceCache.at < 60_000) return spaceCache.v;
  try {
    const { data, error } = await admin.rpc('fn_ml_read_space', {});
    const v: Space = !error && data === 'ml' ? 'ml' : 'gte';
    spaceCache = { v, at: Date.now() };
    return v;
  } catch (_e) { return 'gte'; }
}


let cred: { v: string; at: number } | null = null;

// EMBED_ML DOWN COSTS ONE TIMEOUT, NOT ONE PER TEXT (it_engineer, 27 Oct 2026). Review of #1687: the learning tick
// embeds up to 8 lessons in a row, each with an ~8 s timeout, so an embed_ml that is down could add ~64 s and push
// resilience_ping's main tick past its 95 s deadline; the held replay's steps embed one after another the same way.
// When embed_ml does not answer at all (a timeout, a throw, a 5xx with no JSON body - the platform's, not embed_ml's),
// every call in this worker for the next EMBED_COOL_MS returns null at once with reason 'embed_ml_cooling_off', and
// each caller takes the path it already takes for a null. A per-text refusal (503 embed_failed, a bad vector) is
// embed_ml answering, and opens nothing. prevented by: _shared/embed_failure_reason.test.ts
export const EMBED_COOL_MS = 30_000;
/** The clock every seat gives embed_ml (think.ts, the learning tick, the gateway's embed action). Only a timeout at
 *  this length or longer is evidence that embed_ml is down. */
export const EMBED_FULL_TIMEOUT_MS = 8_000;
let downUntil = 0;
let downWhy = '';

/** `why`, when given, is told the reason a call returned null (27 Oct 2026: a bare null hid three different failures). */
export type EmbedWhy = (reason: string) => void;
export function embedQueryMlRemote(admin: Admin, text: string, caller: string, timeoutMs: number, why?: EmbedWhy): Promise<number[] | null> {
  return embedRemote(admin, text, caller, timeoutMs, 'ml', why);
}
/**
 * gte-small ASKED FROM OUTSIDE THE EDGE RUNTIME (ceo, ledger 1003 stage 2, 19 Oct 2026). gte_embed.embedLine needs
 * Supabase.ai, which only an edge worker has; a run of think() from Deno on a machine (the seat exam) got null for
 * every gte vector, so fn_reason_retrieve_ml ranked by the multilingual space alone, where 268 of 268 marketing pack
 * rows (and 4,910 of 6,102 sales rows) had no vector yet. Measured: marketing-exam-04's entry ranked 1st fused, absent
 * ml-only. The SAME model answers here (embed_ml action 'gte', Supabase's own gte-small), so the space never mixes.
 */
export function embedGteRemote(admin: Admin, text: string, caller: string, timeoutMs: number, why?: EmbedWhy): Promise<number[] | null> {
  return embedRemote(admin, text, caller, timeoutMs, 'gte', why);
}
async function embedRemote(admin: Admin, text: string, caller: string, timeoutMs: number, space: Space, why?: EmbedWhy): Promise<number[] | null> {
  const t = String(text ?? '').trim();
  const fail = (reason: string) => { try { why?.(reason); } catch (_e) { /* a reporter never breaks the call */ } return null; };
  if (!t) return fail('empty_text');
  if (Date.now() < downUntil) return fail('embed_ml_cooling_off (' + downWhy + ')');
  const down = (reason: string) => { downUntil = Date.now() + EMBED_COOL_MS; downWhy = reason; return fail(reason); };
  try {
    if (!cred || Date.now() - cred.at > 10 * 60_000) {
      const { data } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle();
      if (!data?.value) return fail('no_credential');
      cred = { v: String(data.value), at: Date.now() };
    }
    const signal = AbortSignal.timeout(timeoutMs);
    const ask = () => fetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/embed_ml', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: cred!.v, fn: caller, action: space === 'ml' ? 'query' : 'gte', text: t }),
      signal: signal,
    });
    // A relay 502/503 no worker served (2 Nov 2026: 8 on embed_ml, all at a five-minute mark) is asked once more
    // inside the same timeout rather than opening the 30 s cool-off for every embed in this worker.
    let r = await ask();
    if (notReached(r)) { await r.body?.cancel(); await new Promise((ok) => setTimeout(ok, 400)); r = await ask(); }
    if (!r.ok) {
      const j = await r.json().catch(() => null);
      const reason = 'embed_ml_http_' + r.status + (j?.error ? ':' + errorText(j.error, 80) : j ? '' : ':no_json_body');
      return r.status >= 500 && !j ? down(reason) : fail(reason);
    }
    const j = await r.json();
    const v = typeof j?.embedding === 'string' ? JSON.parse(j.embedding) : null;
    return Array.isArray(v) && v.length === 384 && j.space === space ? v as number[] : fail('embed_ml_bad_vector');
  } catch (e) {
    const n = (e as Error)?.name;
    // A caller that chose a SHORTER clock than the full one (ai_gateway's semantic cache waits 3 s) has said it would
    // rather go without than wait; that is not embed_ml being down, so it opens no cool-off for every other caller in
    // the worker (review of #1797: the embed action and the FAQ match would have lost their vectors for 30 s).
    if (n === 'TimeoutError' || n === 'AbortError') {
      const why = 'embed_ml_timeout_' + timeoutMs + 'ms';
      return timeoutMs >= EMBED_FULL_TIMEOUT_MS ? down(why) : fail(why);
    }
    return down('embed_ml_error: ' + errorText(e));
  }
}
/** For tests: forget the cached credential so the next call reads app_secrets again. */
export function _resetEmbedClientForTest(): void { cred = null; spaceCache = null; downUntil = 0; downWhy = ''; }
