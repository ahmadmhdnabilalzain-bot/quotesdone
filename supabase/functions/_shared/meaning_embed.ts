// THE LINES MEANING READS, EMBEDDED OUTSIDE THE CALLER'S WORKER. Seat: sales_engineer. 29 Sep 2026.
//
// Decision point 93 (b): meaning is the only way a line not written as a service's name names one, so it has to read
// a whole catalogue (the ZZ DEMO one has 26 candidate lines) and it has to read Arabic. Both costs used to fall on
// the caller: one gte-small run per line inside supplier_api / sales_engineer, whose CPU cap no deadline bounds (16
// lines was the ceiling), and no multilingual model at all (it cannot load in a request worker: ml_embed.ts).
// Now every line is embedded by the embed_ml function over HTTP — 'gte' for an English line (Supabase.ai gte-small,
// the same model the stored vectors come from), 'query' for an Arabic line (the multilingual e5) — at most
// CONCURRENCY at a time. Each call is its own worker; the caller only waits. MEASURED 29 Sep 2026: see
// service_meaning.ts MEANING_MAX_LINES. The credential is cred_fn_ai (fn.ai, scope includes embed_ml), the one
// ml_embed_client.ts uses; `fn` names the caller in the audit. Free and in-region: never OpenRouter.
//
// FAIL SOFT: a line that could not be embedded comes back with vec null, and every reader reports it
// (meaning.state, complete=false) instead of reading it as naming nothing.
import { meaningSpace, type MeaningLine, type Space } from './service_meaning.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
export type Embedder = (text: string, space: Space) => Promise<number[] | null>;

export const CONCURRENCY = 8;
export const CALL_TIMEOUT_MS = 12_000;   // an e5 cold start is 1.2-2.6 s (ml_embed.ts); a warm call well under 1 s

let cred: { v: string; at: number } | null = null;
/** The embedder a request path uses: embed_ml over HTTP, one line per call. */
export function remoteEmbedder(admin: Admin, caller: string): Embedder {
  return async (text, space) => {
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
        body: JSON.stringify({ __secret: cred.v, fn: caller, action: space === 'ml' ? 'query' : 'gte', text: t.slice(0, 1200) }),
        signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
      });
      if (!r.ok) return null;
      const j = await r.json();
      const v = typeof j?.embedding === 'string' ? JSON.parse(j.embedding) : null;
      return Array.isArray(v) && v.length === 384 && j.space === space ? v as number[] : null;
    } catch (_e) { return null; }
  };
}

/** Every text embedded in its own space, CONCURRENCY at a time, in order. */
export async function embedLines(texts: string[], embed: Embedder): Promise<MeaningLine[]> {
  const out: MeaningLine[] = texts.map((text) => ({ text, vec: null, space: meaningSpace(text) }));
  let next = 0;
  const worker = async () => {
    while (next < out.length) {
      const i = next++;
      out[i].vec = await embed(out[i].text, out[i].space!).catch(() => null);
    }
  };
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, out.length) }, worker));
  return out;
}
