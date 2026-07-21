// kb_embed — populate kb_chunks.embedding_gte via the free in-region gte-small. Single small pass per call
// (avoids the edge compute limit); a frequent cron backfills over time. New chunks get embedded incrementally.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
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
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) { await logThrottled('forbidden', 60, 'error', { stage: 'auth' }, 'kb_embed rejected a caller presenting a bad or missing inbound secret. If this is the scheduled backfill, no knowledge-base chunks are being embedded and semantic search silently degrades to whatever was already indexed.'); return J({ error: 'forbidden' }, 403); }
    const lim = Math.min(Math.max(Number(body.limit) || 10, 1), 40);
    // library chunks first (newest, most relevant), then the rest
    let q = admin.from('kb_chunks').select('id, title, content').is('embedding_gte', null);
    if (body.scope !== 'all') q = q.eq('source_kind', 'library');
    let { data, error: qerr } = await q.limit(lim);
    let qerr2: any = null;
    if ((!data || data.length === 0) && body.scope !== 'all') {
      const r = await admin.from('kb_chunks').select('id, title, content').is('embedding_gte', null).limit(lim);
      data = r.data; qerr2 = r.error;
    }
    if (!data || data.length === 0) {
      if (qerr || qerr2) await logThrottled('query_failed', 60, 'error', { stage: 'select' }, 'kb_embed could not read kb_chunks, so it reported "done" while unembedded chunks may still exist; the embedding backfill has silently stalled and new knowledge-base content will not appear in semantic search. ' + String((qerr || qerr2)?.message || (qerr || qerr2)).slice(0, 160));
      return J({ ok: true, done: true, embedded: 0 });
    }
    // deno-lint-ignore no-explicit-any
    const model = new (globalThis as any).Supabase.ai.Session('gte-small');
    let n = 0;
    let writeFailed = 0; let lastWriteErr = '';
    for (const r of data as any[]) {
      const text = (String(r.title || '') + '\n' + String(r.content || '')).slice(0, 1200);
      const emb = await model.run(text, { mean_pool: true, normalize: true }) as number[];
      const { error: uerr } = await admin.from('kb_chunks').update({ embedding_gte: '[' + emb.join(',') + ']' }).eq('id', r.id);
      if (uerr) { writeFailed++; lastWriteErr = String(uerr?.message || uerr).slice(0, 160); }
      n++;
    }
    const { count: remaining } = await admin.from('kb_chunks').select('id', { count: 'exact', head: true }).is('embedding_gte', null);
    if (writeFailed > 0) {
      await logThrottled('embedding_write_failed', 60, 'error', { attempted: n, write_failed: writeFailed, remaining }, 'kb_embed computed embeddings but failed to write ' + writeFailed + ' of ' + n + ' back to kb_chunks. Those chunks stay unembedded and are re-picked on every run, so the backfill loops forever without progressing and that content never becomes searchable. ' + lastWriteErr);
    } else {
      await logThrottled('progress', 60, 'ok', { embedded: n, remaining }, 'kb_embed backfill is progressing: embedded ' + n + ' chunk(s) this run, ' + String(remaining ?? '?') + ' still unembedded.');
    }
    return J({ ok: true, embedded: n, remaining });
  } catch (e) { await logThrottled('embed_failed', 60, 'error', { stage: 'fatal' }, 'kb_embed crashed during the embedding pass (model session or database failure); the embedding backfill has stopped making progress and newly added knowledge-base chunks are not searchable. ' + String((e as Error)?.message || e).slice(0, 200)); return J({ error: String((e as Error)?.message || e) }, 500); }
});
