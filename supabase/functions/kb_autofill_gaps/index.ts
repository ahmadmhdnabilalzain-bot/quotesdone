// kb_autofill_gaps — autonomously fill the worst knowledge gaps. __secret gated (cron). Notifies founder only if all fills fail.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'kb_autofill_gaps', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    const secret = await sec('cred_fn_kb_autofill_gaps');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'kb_autofill_gaps');
    if (!__auth.ok) { await logRun('error', { filled: 0 }, 'call rejected: wrong or missing inbound secret; no knowledge gaps were filled'); return J({ error: 'unauthorized' }, 401); }
    const limit = Math.min(Math.max(Number(body?.limit) || 2, 1), 5);

    // pick service categories with zero knowledge chunks
    const { data: specs } = await admin.from('category_specs').select('category,label');
    const gaps: { category: string; label: string }[] = [];
    for (const s of (specs || [])) {
      const { count } = await admin.from('kb_chunks').select('id', { count: 'exact', head: true }).eq('category', (s as any).category);
      if (!count) gaps.push({ category: (s as any).category, label: (s as any).label || (s as any).category });
      if (gaps.length >= limit) break;
    }
    if (!gaps.length) { await logRun('ok', { gaps: 0, filled: 0, chunks_inserted: 0 }, 'no category had zero knowledge chunks; nothing needed filling this run'); return J({ ok: true, filled: [], note: 'no gaps' }); }

    const results: any[] = [];
    for (const g of gaps) {
      try {
        const r = await fetch(`${BASE}/kb_fill_gap`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, category: g.category, label: g.label }) });
        const jd = await r.json().catch(() => ({} as any));
        results.push({ category: g.category, ok: !!jd?.ok, held: jd?.held === true, inserted: jd?.inserted || 0, error: jd?.error, http: r.status });
      } catch (e) { results.push({ category: g.category, ok: false, error: String((e as Error)?.message || e) }); }
    }
    const anyOk = results.some((r) => r.ok);
    // 4 SEP 2026: every gap answered 'held' is the founder's paid-provider hold, not a failure of this
    // job: record it as skipped, page nobody, and let the next run try again once the hold lifts. The
    // old path logged status=error 27 times in one morning and posted a founder warning each time.
    if (!anyOk && results.length && results.every((r) => r.held)) {
      await logRun('skipped', { gaps: gaps.length, attempted: results.length, filled: 0, failed: 0, held: results.length, chunks_inserted: 0 },
        'paid provider held by the founder: ' + results.length + ' knowledge gap(s) [' + results.map((r) => r.category).join(', ') + '] left unfilled; nothing was generated, charged or paged');
      return J({ ok: true, skipped: 'provider_held', filled: [] });
    }
    if (!anyOk) { // exception-only alert
      try { await fetch(`${BASE}/alert_founder`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, level: 'warn', subject: 'Knowledge auto-fill failed', body: 'The weekly knowledge gap auto-fill produced no new knowledge. Details: ' + JSON.stringify(results).slice(0, 400) }) }); } catch (_e) {}
    }
    const okCount = results.filter((r) => r.ok).length;
    const failed = results.filter((r) => !r.ok);
    const inserted = results.reduce((a: number, r: any) => a + (Number(r.inserted) || 0), 0);
    let note: string;
    if (!anyOk) { note = 'NO knowledge generated this run: all ' + results.length + ' kb_fill_gap calls failed, so categories [' + results.map((r) => r.category).join(', ') + '] still have zero knowledge chunks and the assistant cannot answer questions about them'; }
    else if (failed.length) { note = 'partial run: filled ' + okCount + ' of ' + results.length + ' knowledge gaps (' + inserted + ' chunks); still empty: ' + failed.map((r) => r.category).join(', '); }
    else { note = 'filled all ' + okCount + ' knowledge gaps this run (' + inserted + ' chunks inserted)'; }
    if (inserted === 0 && anyOk) { note += ' | WARNING: kb_fill_gap reported success but inserted 0 chunks — those categories are still effectively empty'; }
    if (failed.length) { note += ' | first error: ' + String(failed[0]?.error || 'unknown'); }
    await logRun((!anyOk || (inserted === 0)) ? 'error' : 'ok', { gaps: gaps.length, attempted: results.length, filled: okCount, failed: failed.length, chunks_inserted: inserted }, note);
    return J({ ok: true, filled: results });
  } catch (e) { await logRun('error', { filled: 0 }, 'kb_autofill_gaps crashed before completing; no knowledge gaps filled this run: ' + String((e as Error)?.message || e)); return J({ error: String((e as Error)?.message || e) }, 500); }
});
