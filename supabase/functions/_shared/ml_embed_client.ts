// THE MULTILINGUAL EMBEDDER, ASKED FROM A REQUEST PATH. Seat: it_engineer (shared platform). 23 Sep 2026.
//
// The model (45.5 MB, ml_embed.ts) runs in ONE place: the embed_ml function. A seat answering a customer
// (think.ts, case_recall.ts) asks it over HTTP instead of loading the model in its own worker, so a worker that
// runs out of memory loading it is embed_ml's, and here it is only a failed fetch: this returns null and the
// caller takes the gte-small path. (Review of #907, finding 1: an in-process load on wa_inbound or customer_api
// could kill the isolate mid-reply, which no try/catch can recover.)
// The credential is cred_fn_ai, the fn.ai context whose scope includes embed_ml; 'fn' names the caller in the audit.
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

export async function embedQueryMlRemote(admin: Admin, text: string, caller: string, timeoutMs: number): Promise<number[] | null> {
  const t = String(text ?? '').trim();
  if (!t) return null;
  try {
    if (!cred || Date.now() - cred.at > 10 * 60_000) {
      const { data } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle();
      if (!data?.value) return null;
      cred = { v: String(data.value), at: Date.now() };
    }
    const r = await fetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/embed_ml', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: cred.v, fn: caller, action: 'query', text: t }),
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!r.ok) return null;
    const j = await r.json();
    const v = typeof j?.embedding === 'string' ? JSON.parse(j.embedding) : null;
    return Array.isArray(v) && v.length === 384 && j.space === 'ml' ? v as number[] : null;
  } catch (_e) { return null; }
}
