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
    // idcol/orderby let a target key on something other than `id`/`created_at`. ops_knowledge is keyed
    // on record_id (text) and has no created_at, so a strict FIFO orders on record_id. The agents'
    // OWN operating knowledge (authority, policy, playbooks, department library) is embedded here with
    // the same free in-region gte-small, so fn_ops_knowledge_match can retrieve it by meaning.
    const TARGETS: Record<string, { table: string; cols: string; idcol: string; orderby: string; text: (r: Record<string, unknown>) => string }> = {
      kb_chunks:   { table: 'kb_chunks',   cols: 'id, title, content', idcol: 'id', orderby: 'created_at',
                     text: (r) => String(r.title || '') + '\n' + String(r.content || '') },
      company_faq: { table: 'company_faq', cols: 'id, question, answer', idcol: 'id', orderby: 'created_at',
                     text: (r) => String(r.question || '') + '\n' + String(r.answer || '') },
      ops_knowledge: { table: 'ops_knowledge', cols: 'record_id, title, content', idcol: 'record_id', orderby: 'record_id',
                     text: (r) => String(r.title || '') + '\n' + String(r.content || '') },
    };
    const tgt = TARGETS[String(body.target ?? 'kb_chunks')] ?? TARGETS.kb_chunks;

    // QUERY MODE (4 Sep 2026). gte-small runs only in the Edge runtime — Postgres cannot embed a
    // sentence — so a probe that wants to prove fn_ops_knowledge_match / fn_apply_playbook return a
    // playbook by MEANING had no free way to obtain the query vector outside agent_brain (which sits
    // behind the paid-model hold). Same credential gate, same model, no write: returns the 384-dim
    // vector for one sentence. scripts/kb/probe_ops_knowledge_match.mjs is the caller.
    if (typeof body.query === 'string' && body.query.trim()) {
      const emb = await embedder().run(body.query.trim().slice(0, 1200), { mean_pool: true, normalize: true }) as number[];
      return J({ ok: true, dims: emb.length, embedding: emb });
    }

    // OLDEST-FIRST IS FAIR AND IT PUT THE MOST AUTHORITATIVE KNOWLEDGE LAST (11 Aug 2026).
    // Measured on production: kb_chunks is 42.6% embedded and rising ~1,240/hour, but `trade`
    // (1,993 rows) and `regulation` (45) are at 0% and `material` (3) at 0% — they arrived AFTER
    // the 115,148-row pack import, so a strict FIFO leaves UAE regulations and trade knowledge
    // roughly 56 hours behind a queue of pack chunks. Those are exactly the rows an employee is
    // most likely to be wrong about without.
    //
    // An optional source_kinds filter, not a hard-coded priority: the default is unchanged, so the
    // every-minute backfill cron keeps its fair FIFO, and a second caller can drain a named,
    // FINITE set first. A permanent priority ordering would starve the pack corpus, which is the
    // defect the comment above this one records.
    const kinds = Array.isArray(body.source_kinds)
      ? body.source_kinds.map((s: unknown) => String(s)).filter(Boolean).slice(0, 8) : null;
    // Optional category allowlist (mirrors source_kinds): lets a driver drain a FINITE, named set of
    // categories first — e.g. the professional-cert functional fields, whose chunks are the NEWEST in
    // the table and would otherwise sit behind millions of older rows under the default oldest-first
    // FIFO. Bounded to 20 and only applied to kb_chunks; default is unchanged so the fair FIFO cron is
    // untouched. `newest` flips to newest-first for the same prioritisation without naming categories.
    const cats = Array.isArray(body.categories)
      ? body.categories.map((s: unknown) => String(s)).filter(Boolean).slice(0, 20) : null;
    const newest = body.newest === true;
    let sel = admin.from(tgt.table).select(tgt.cols).is('embedding_gte', null);
    if (kinds && kinds.length && tgt.table === 'kb_chunks') sel = sel.in('source_kind', kinds);
    if (cats && cats.length && tgt.table === 'kb_chunks') sel = sel.in('category', cats);
    const { data, error: qerr } = await sel
      .order(tgt.orderby, { ascending: !newest })
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
      const { error: uerr } = await admin.from(tgt.table).update({ embedding_gte: '[' + emb.join(',') + ']' }).eq(tgt.idcol, (r as any)[tgt.idcol]);
      if (uerr) { writeFailed++; lastWriteErr = String(uerr?.message || uerr).slice(0, 160); }
      n++;
    }
    // BOUNDED, NOT COUNTED (6 Sep 2026). This was `count: 'exact'` over `embedding_gte is null` on
    // kb_chunks - 2.65M rows, ~2.54M of them null - and it hit the 8 s statement wall on every run:
    // 28 error rows in 7 days saying "could not read its target table, so it reported done", written
    // by a function that had just embedded five chunks. fn_kb_embed_backlog() is planner statistics
    // (reltuples x null_frac, dated by the analyze that produced them) plus one index-bounded
    // min(created_at) - the frontier the oldest-first picker is at - and never a scan. The two small
    // targets keep the exact count: company_faq is 484 rows and ops_knowledge ~9k.
    let remaining: number | null = null;
    let backlog: Record<string, unknown> | null = null;
    if (tgt.table === 'kb_chunks') {
      const { data: bl } = await admin.rpc('fn_kb_embed_backlog');
      backlog = (bl && typeof bl === 'object') ? bl as Record<string, unknown> : null;
      remaining = backlog && typeof backlog.estimated_unembedded === 'number' ? backlog.estimated_unembedded : null;
    } else {
      const { count } = await admin.from(tgt.table).select(tgt.idcol, { count: 'exact', head: true }).is('embedding_gte', null);
      remaining = count ?? null;
    }
    if (writeFailed > 0) {
      await logThrottled('embedding_write_failed', 60, 'error', { attempted: n, write_failed: writeFailed, remaining }, 'kb_embed computed embeddings but failed to write ' + writeFailed + ' of ' + n + ' back to kb_chunks. Those chunks stay unembedded and are re-picked on every run, so the backfill loops forever without progressing and that content never becomes searchable. ' + lastWriteErr);
    } else {
      await logThrottled('progress', 60, 'ok', { embedded: n, remaining, budget_hit: budgetHit, frontier: backlog?.frontier_created_at ?? null, stats_as_of: backlog?.stats_as_of ?? null }, 'kb_embed backfill is progressing: embedded ' + n + ' chunk(s) this run, ~' + String(remaining ?? '?') + ' still unembedded (planner estimate' + (backlog?.frontier_created_at ? '; oldest unembedded chunk created ' + String(backlog.frontier_created_at) : '') + ').');
    }
    return J({ ok: true, embedded: n, remaining, backlog, budget_hit: budgetHit });
  } catch (e) { await logThrottled('embed_failed', 60, 'error', { stage: 'fatal' }, 'kb_embed crashed during the embedding pass (model session or database failure); the embedding backfill has stopped making progress and newly added knowledge-base chunks are not searchable. ' + String((e as Error)?.message || e).slice(0, 200)); return J({ error: String((e as Error)?.message || e) }, 500); }
});
