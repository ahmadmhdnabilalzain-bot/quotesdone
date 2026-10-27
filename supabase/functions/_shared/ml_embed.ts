// THE MULTILINGUAL EMBEDDER — Arabic and English in one space. Seat: it_engineer (shared platform). 23-24 Sep 2026.
//
// Supabase.ai.Session runs one embedding model, gte-small, and it is English-only (measured: an Arabic question
// reached its own Arabic knowledge row 0-8% of the time). This runs the trimmed multilingual-e5-small
// (ml_embed_recipe.ts) with transformers.js, in ONE small function of its own (embed_ml), never in ai_gateway.
//
// WHY THIS IMPORT AND THESE OPTIONS (measured 24 Sep 2026 on production, zz_test_ml_embed, deleted after):
//   npm:@huggingface/transformers   the deploy fails, 500 "internal error", in a function of its own as in ai_gateway
//   jsDelivr +esm, no device        "Unsupported device: wasm": the web build defaults to wasm, which the edge
//                                   runtime does not offer; it exposes its native ONNX under Symbol.for('onnxruntime')
//   device 'auto'                   uses that native session; the full 118 MB model then dies at 298 MB (Memory)
//   + the trimmed 45.5 MB model     loads in 1.2-2.6 s cold, a question embeds in ~35 ms, 20 questions in 190 ms,
//                                   8 rows of 1,200 chars in 1.3 s; 16 rows exceed the worker's resources
// The model files come from Storage (in-region, free); nothing here is OpenRouter.
//
// FAIL SOFT, NEVER WRONG. Anything that goes wrong returns null and the caller uses the gte-small path with
// the gte routines. A vector is never returned for the wrong space. The pipeline is built once per worker
// (module scope): building it per request is what killed kb_embed with WORKER_RESOURCE_LIMIT on 28 Jul.
//
// THE TYPES COME FROM NPM, THE CODE FROM JSDELIVR (27 Oct 2026, it_engineer). The local gate runs behind an egress
// proxy that refuses cdn.jsdelivr.net, so `deno check` of every function failed on fetching this URL. `deno check`
// builds a types-only graph: with @ts-types it reads the .d.ts of the SAME version from npm and never fetches the
// +esm (measured: deno-all passes with jsDelivr refused). The edge bundler (supabase/edge-runtime, deno_facade ->
// create_graph_and_maybe_check) builds with TypeCheckMode::None, a code-only graph, which does not follow @ts-types,
// so the deployed bundle still holds only the jsDelivr +esm above: the 24 Sep measurements stand unchanged.
// @ts-types="npm:@huggingface/transformers@3.8.1"
import * as TJS from 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1/+esm';
import { ML_MODEL, ML_MODEL_PATH, mlQueryText, mlRowText, rowText } from './ml_embed_recipe.ts';
import { embedLine } from './gte_embed.ts';

export const ML_EMBED_MS = 20_000;   // a cold start downloads the model (1.2-2.6 s measured); a warm embed is tens of ms
// Rows per tick: 8 rows took 1.3 s of the worker's CPU and 16 were refused, so a tick embeds 4.
export const ML_TICK_MAX = 4;
// deno-lint-ignore no-explicit-any
let pipe: Promise<any> | null = null;

// deno-lint-ignore no-explicit-any
async function extractor(): Promise<any> {
  if (!pipe) {
    pipe = (async () => {
      // deno-lint-ignore no-explicit-any
      const { pipeline, env } = TJS as any;
      env.allowLocalModels = false;
      env.useBrowserCache = false;
      env.remoteHost = Deno.env.get('SUPABASE_URL') + ML_MODEL_PATH;
      env.remotePathTemplate = '{model}/';
      return await pipeline('feature-extraction', ML_MODEL, { dtype: 'q8', device: 'auto' });
    })();
    pipe.catch(() => { pipe = null; });   // a failed load is retried by the next call, not cached forever
  }
  return await pipe;
}

/** Embed texts exactly as given (the caller has applied the prefix). null on any failure or timeout. */
export async function embedRaw(texts: string[], timeoutMs = ML_EMBED_MS): Promise<number[][] | null> {
  if (!texts.length) return [];
  try {
    const run = (async () => {
      const f = await extractor();
      const out = await f(texts, { pooling: 'mean', normalize: true });
      const v = out.tolist() as number[][];
      return Array.isArray(v) && v.length === texts.length && v.every((x) => Array.isArray(x) && x.length === 384) ? v : null;
    })();
    return await Promise.race([run, new Promise<null>((r) => setTimeout(() => r(null), timeoutMs))]);
  } catch (e) {
    console.error('ml_embed: failed:', String((e as Error)?.message || e).slice(0, 300));
    return null;
  }
}

/** A question, or a case situation (a case is compared with a case: both sides are queries). */
export async function embedQueryMl(text: string, timeoutMs = ML_EMBED_MS): Promise<number[] | null> {
  const t = String(text ?? '').trim();
  if (!t) return null;
  const v = await embedRaw([mlQueryText(t)], timeoutMs);
  return v ? v[0] : null;
}

/** The text a source row becomes: a case is a query-side text, knowledge is a passage. */
export function textForRow(src: string, title: string | null, body: string | null): string {
  return mlRowText(src, title, body);
}
// The two tables that had no gte-small column (support_knowledge, ceo_knowledge: 916 rows) get their gte
// vector from the same pass, so the fused retrieval reads them in both spaces like every other source.
export const GTE_ALSO = new Set(['support_knowledge', 'ceo_knowledge']);

// deno-lint-ignore no-explicit-any
type Rpc = { rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: any; error: { message: string } | null }> };

// ── the embed queue: claim, embed, write ────────────────────────────────────────────────────────
type Claimed = { src: string; row_id: string; title: string | null; body: string | null; hash: string };
/** One pass of the queue (fn_ml_embed_claim -> embed -> fn_ml_embed_write). Used by embed_ml's tick (resilience_ping's clock). */
export async function embedQueueOnce(admin: Rpc, limit: number): Promise<Record<string, unknown>> {
  const { data, error } = await admin.rpc('fn_ml_embed_claim', { p_limit: limit });
  if (error) return { ok: false, error: error.message };
  const rows = (Array.isArray(data?.rows) ? data.rows : []) as Claimed[];
  let embedded = 0, failed = 0, stale = 0;
  // One batch through the model (rows x ~30 ms warm), then one small write per row.
  const v = await embedRaw(rows.map((r) => textForRow(r.src, r.title, r.body)));
  for (const [i, r] of rows.entries()) {
    if (!v) { failed++; continue; }
    const g = GTE_ALSO.has(r.src) ? await embedLine(rowText(r.title, r.body)) : null;
    if (GTE_ALSO.has(r.src) && !g) { failed++; continue; }
    const w = await admin.rpc('fn_ml_embed_write', { p_src: r.src, p_row_id: r.row_id, p_hash: r.hash,
      p_embedding: '[' + v[i].join(',') + ']', p_embedding_gte: g ? '[' + g.join(',') + ']' : null });
    if (w.error) failed++; else if (w.data === true) embedded++; else stale++;
  }
  // A claim that embedded nothing is a failure, never a quiet zero.
  return { ok: failed === 0 || embedded > 0, claimed: rows.length, embedded, stale, failed, reason: data?.reason ?? null, today: data?.today ?? null, cap: data?.cap ?? null };
}
