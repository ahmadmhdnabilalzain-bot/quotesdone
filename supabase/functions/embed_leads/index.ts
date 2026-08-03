// embed_leads - populate leads.embedding_gte (vector 384) via free in-region gte-small.
// Secret-guarded. Default scope ('new'): REAL suppliers first (registered / self-registered / approved) so a
// supplier is matchable via semantic search within a day of registering, THEN the cold apify-scraped backlog.
// This closes the launch trap where a self-registered supplier (source='self_registered') was never embedded
// by the old 'new' scope (which only touched enrich_source='apify_maps_contacts') and stayed invisible to
// vector matching. scope='all' embeds everything missing embedding_gte, unprioritised.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'embed_leads', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

Deno.serve(async (req) => {
  let embedded = 0; let updFails = 0; const failIds: unknown[] = [];
  try {
    const body = await req.json().catch(()=>({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'embed_leads');
    if (!__auth.ok) { await logRun('error', { stage:'auth', rejected:1 }, 'Rejected a call with a wrong or missing __secret; no supplier embeddings were generated this run, so any suppliers still lacking embedding_gte remain unmatchable to every RFQ'); return J({ error: 'forbidden' }, 403); }
    const scope = body.scope === 'all' ? 'all' : 'new';
    // deno-lint-ignore no-explicit-any
    const model = new (globalThis as any).Supabase.ai.Session('gte-small');
    const t0 = Date.now(); let total = 0;
    while (Date.now() - t0 < 44000) {
      let data: any[] | null = null; let error: any = null;
      if (scope === 'all') {
        ({ data, error } = await admin.from('leads').select('id, capability_summary, company_name').is('embedding_gte', null).limit(100));
      } else {
        // PRIORITY 1: real suppliers (registered / self-registered / approved) missing an embedding.
        ({ data, error } = await admin.from('leads').select('id, capability_summary, company_name')
          .is('embedding_gte', null)
          .or('registration_submitted_at.not.is.null,source.eq.self_registered,approval_status.eq.approved')
          .limit(100));
        // PRIORITY 2: only once no real supplier is waiting, chew through the cold apify-scraped backlog.
        if (!error && (!data || data.length === 0)) {
          ({ data, error } = await admin.from('leads').select('id, capability_summary, company_name')
            .is('embedding_gte', null).eq('enrich_source', 'apify_maps_contacts').limit(100));
        }
      }
      if (error) { await logRun('error', { stage:'select', scope, embedded, update_failures: updFails }, 'Could not read the backlog of un-embedded suppliers: '+String(error.message)+'; every supplier still missing embedding_gte stays invisible to semantic matching and cannot be matched to any RFQ'); return J({ error: error.message, total }, 500); }
      if (!data || data.length === 0) { await logRun(updFails ? 'error' : 'ok', { stage:'done', scope, embedded, update_failures: updFails, failed_ids: failIds }, updFails ? (updFails+' supplier embedding writes failed (ids '+failIds.join(',')+'); those suppliers are left without embeddings, cannot be matched to any RFQ, and will be re-selected on every future run because embedding_gte stays null') : ('Backlog cleared: '+embedded+' suppliers embedded; no suppliers are left unmatchable for scope '+scope)); return J({ ok: true, done: true, total }); }
      for (const r of data as any[]) {
        const text = String(r.capability_summary || r.company_name || '').slice(0, 800);
        const emb = await model.run(text, { mean_pool: true, normalize: true }) as number[];
        const { error: updErr } = await admin.from('leads').update({ embedding_gte: '[' + emb.join(',') + ']' }).eq('id', r.id);
        if (updErr) { updFails++; if (failIds.length < 20) failIds.push(r.id); }
        total++;
        embedded++;
      }
    }
    await logRun(updFails ? 'error' : 'ok', { stage:'partial', scope, embedded, update_failures: updFails, failed_ids: failIds }, updFails ? (updFails+' of '+embedded+' supplier embedding writes failed (ids '+failIds.join(',')+'); those suppliers are left without embeddings and cannot be matched to any RFQ. Time budget also expired, so an un-embedded backlog remains') : ('Time budget expired after embedding '+embedded+' suppliers; an un-embedded backlog remains and those suppliers cannot be matched to any RFQ until a later run reaches them'));
    return J({ ok:true, partial:true, total });
  } catch (e) { await logRun('error', { stage:'embed', embedded, update_failures: updFails }, 'embed_leads aborted: '+String((e as Error)?.message || e)+'; the embedding model or a write failed mid-batch, so the remaining suppliers keep a null embedding_gte and cannot be matched to any RFQ'); return J({ error: String((e as Error)?.message || e) }, 500); }
});
