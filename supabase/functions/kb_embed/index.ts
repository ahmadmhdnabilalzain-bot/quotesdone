// kb_embed — populate kb_chunks.embedding_gte via the free in-region gte-small.
//
// 28 Jul 2026 — WORKER_RESOURCE_LIMIT fix. The gte-small Session was being constructed INSIDE the
// request handler, so every invocation loaded the model into a fresh allocation. Under any worker
// memory pressure the platform killed the worker with a 546 before the handler could log anything,
// which is why this failed every scheduled run for hours with zero signal in agent_runs. The session
// is now a module-scope lazy singleton, reused for the life of a warm worker.
//
// Two other defects fixed in the same pass:
//   * The chunk query had no ORDER BY, so rows could starve indefinitely. 32 'document' chunks from
//     26 Jul survived ~2,000 newer embeddings. Now strictly oldest-first.
//   * There was no wall-clock budget, so a slow run walked into the CPU ceiling instead of returning
//     the work it had already completed. Now stops cleanly and lets the next cron tick continue.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

// Module scope: created once per worker, reused across invocations. Do NOT move this inside Deno.serve.
// deno-lint-ignore no-explicit-any
let _model: any = null;
// deno-lint-ignore no-explicit-any
function embedder(): any {
  // deno-lint-ignore no-explicit-any
  if (_model === null) _model = new (globalThis as any).Supabase.ai.Session('gte-small');
  return _model;
}

const T0 = Date.now();
const BUDGET_MS = 7000; // return what we have well before the edge CPU ceiling

async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'kb_embed', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
async function logThrottled(signal: string, minutes: number, status: string, counts: Record<string, unknown>, note: string) {
  try {
    const since = new Date(Date.now() - minutes * 60000).toISOString();
    const { data } = await admin.from('agent_runs').select('id').eq('agent', 'kb_embed')
      .gte('started_at', since).eq('counts->>signal', signal).limit(1);
    if (data && data.length) return;
  } catch (_e) { /* if the check fails, fall through and log */ }
  await logRun(status, { ...counts, signal }, note);
}
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'kb_embed');
    if (!__auth.ok) { await logThrottled('forbidden', 60, 'error', { stage: 'auth' }, 'kb_embed rejected a caller presenting a bad or missing inbound secret. If this is the scheduled backfill, no knowledge-base chunks are being embedded and semantic search silently degrades to whatever was already indexed.'); return J({ error: 'forbidden' }, 403); }
    // 5 is the measured ceiling on this project's edge worker. Empirically on 28 Jul 2026:
    // limit 40 -> 546, limit 20 -> 546, limit 10 -> 546, limit 8 -> 546, limit 5 -> 200. The gte-small
    // session grows its allocation with each run() inside one invocation, so the batch has to stay
    // small and throughput comes from cron frequency (every minute = 7,200 chunks/day) instead.
    const lim = Math.min(Math.max(Number(body.limit) || 5, 1), 8);

    // Strict oldest-first. Without this, PostgREST returns an arbitrary slice and individual rows can
    // starve forever behind newer arrivals. The old library-first priority pass is gone for the same
    // reason: a steady stream of 'library' chunks starved every other source_kind indefinitely.
    // TARGET. company_faq.embedding_gte was null on all 484 rows, and fn_faq_answer takes an
    // embedding and a min-similarity: the SEMANTIC half of the level-0 FAQ path -- the one that
    // answers a customer with no model at all -- had never worked, so every question it could have
    // caught went to a model instead. Same free in-region gte-small, same batch ceiling, one more
    // table. Allowlisted rather than free-form: this runs as service_role and a caller-supplied
    // table name would be an update primitive for the whole schema. Default is unchanged, so the
    // kb_chunks backfill running on kb_embed_backfill_boost is not touched by this.
    const TARGETS: Record<string, { table: string; cols: string; text: (r: Record<string, unknown>) => string }> = {
      kb_chunks:   { table: 'kb_chunks',   cols: 'id, title, content',
                     text: (r) => String(r.title || '') + '\n' + String(r.content || '') },
      company_faq: { table: 'company_faq', cols: 'id, question, answer',
                     text: (r) => String(r.question || '') + '\n' + String(r.answer || '') },
    };
    const tgt = TARGETS[String(body.target ?? 'kb_chunks')] ?? TARGETS.kb_chunks;

    const { data, error: qerr } = await admin
      .from(tgt.table).select(tgt.cols)
      .is('embedding_gte', null)
      .order('created_at', { ascending: true })
      .limit(lim);

    if (!data || data.length === 0) {
      if (qerr) await logThrottled('query_failed', 60, 'error', { stage: 'select' }, 'kb_embed could not read its target table, so it reported "done" while unembedded chunks may still exist; the embedding backfill has silently stalled and new knowledge-base content will not appear in semantic search. ' + String(qerr?.message || qerr).slice(0, 160));
      return J({ ok: true, done: true, embedded: 0 });
    }

    const model = embedder();
    let n = 0;
    let writeFailed = 0; let lastWriteErr = '';
    let budgetHit = false;
    for (const r of data as any[]) {
      if (Date.now() - T0 > BUDGET_MS) { budgetHit = true; break; }
      const text = tgt.text(r).slice(0, 1200);
      const emb = await model.run(text, { mean_pool: true, normalize: true }) as number[];
      const { error: uerr } = await admin.from(tgt.table).update({ embedding_gte: '[' + emb.join(',') + ']' }).eq('id', r.id);
      if (uerr) { writeFailed++; lastWriteErr = String(uerr?.message || uerr).slice(0, 160); }
      n++;
    }
    const { count: remaining } = await admin.from(tgt.table).select('id', { count: 'exact', head: true }).is('embedding_gte', null);
    if (writeFailed > 0) {
      await logThrottled('embedding_write_failed', 60, 'error', { attempted: n, write_failed: writeFailed, remaining }, 'kb_embed computed embeddings but failed to write ' + writeFailed + ' of ' + n + ' back to kb_chunks. Those chunks stay unembedded and are re-picked on every run, so the backfill loops forever without progressing and that content never becomes searchable. ' + lastWriteErr);
    } else {
      await logThrottled('progress', 60, 'ok', { embedded: n, remaining, budget_hit: budgetHit }, 'kb_embed backfill is progressing: embedded ' + n + ' chunk(s) this run, ' + String(remaining ?? '?') + ' still unembedded.');
    }
    return J({ ok: true, embedded: n, remaining, budget_hit: budgetHit });
  } catch (e) { await logThrottled('embed_failed', 60, 'error', { stage: 'fatal' }, 'kb_embed crashed during the embedding pass (model session or database failure); the embedding backfill has stopped making progress and newly added knowledge-base chunks are not searchable. ' + String((e as Error)?.message || e).slice(0, 200)); return J({ error: String((e as Error)?.message || e) }, 500); }
});
