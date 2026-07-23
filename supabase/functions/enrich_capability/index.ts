// enrich_capability — synthesizes a rich, factual capability_summary for a seller from their own
// profile (categories, services, products, sector, licence trade). This is the FUEL the matching
// adjudicator (route_inquiry) reads to judge who can genuinely quote a job. Never invents scope it
// cannot infer; thin inputs -> conservative summary + low_confidence flag. Single (lead_id) or batch.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const _llm = makeLlm(SONNET_FIRST, { max: 700, temperature: 0 });
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'enrich_capability', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const LLM_STATE = { keyMissing: false, failures: [] as string[] };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function parseJson(s: string){ try { const m=String(s||'').match(/\{[\s\S]*\}/); return m?JSON.parse(m[0]):null; } catch { return null; } }

async function llm(sys: string, user: string, max = 700): Promise<string> {
  const key = await sec('openrouter_api_key'); if (!key) { LLM_STATE.keyMissing = true; return ''; }
  return (await _llm(sys, user, max)) || '';
}

const SYS = `You write a concise, FACTUAL capability profile for a UAE B2B supplier/contractor, used by an AI to decide which customer jobs this supplier can genuinely quote. Base it ONLY on the supplier's own profile data given. Do NOT invent trades, brands, certifications or scale that are not supported by the input. If the input is thin, write a short conservative summary and set low_confidence true. Capture: the exact products/materials they supply and/or services they perform, the trades they cover, typical project types/sectors, and any clear specialisation. 60-140 words, plain declarative sentences (no marketing fluff, no first person). Output ONLY minified JSON: {"capability_summary": string, "low_confidence": boolean}.`;

async function enrichOne(lead: any): Promise<{ id: number; ok: boolean; low?: boolean; reason?: string }> {
  const profile = [
    lead.company_name && ('Company: '+lead.company_name),
    lead.sector && ('Sector: '+lead.sector),
    lead.categories && ('Categories: '+lead.categories),
    lead.services && ('Services: '+lead.services),
    lead.products && ('Products: '+lead.products),
    lead.capability_summary && ('Existing notes: '+lead.capability_summary)
  ].filter(Boolean).join('\n');
  if (!profile.trim()) return { id: lead.id, ok: false, reason: 'no_profile_data' };
  const out = parseJson(await llm(SYS, profile, 700));
  const summary = out?.capability_summary ? String(out.capability_summary).slice(0, 1200) : '';
  if (!summary) return { id: lead.id, ok: false, reason: LLM_STATE.keyMissing ? 'llm_key_missing' : 'llm_no_summary' };
  const { error } = await admin.from('leads').update({ capability_summary: summary, capability_enriched_at: new Date().toISOString() }).eq('id', lead.id);
  return { id: lead.id, ok: !error, low: out?.low_confidence === true, reason: error ? ('db_update_failed:'+String(error.message)) : undefined };
}

const COLS = 'id,company_name,sector,categories,services,products,capability_summary';

Deno.serve(async (req) => {
  LLM_STATE.keyMissing = false; LLM_STATE.failures.length = 0;
  try {
    const body = await req.json().catch(()=>({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) { await logRun('error', { stage:'auth', rejected:1 }, 'Rejected a call with a wrong or missing __secret; no supplier capability profiles were written, so suppliers awaiting enrichment stay without a capability_summary and the matching adjudicator cannot judge them for any RFQ'); return J({ error:'forbidden' }, 403); }

    if (body.lead_id) {
      const { data: lead, error: leadErr } = await admin.from('leads').select(COLS).eq('id', Number(body.lead_id)).maybeSingle();
      if (!lead) { await logRun('error', { stage:'single', lead_id: Number(body.lead_id), found: 0 }, 'Lead '+String(body.lead_id)+' could not be loaded for enrichment'+(leadErr ? (': '+String(leadErr.message)) : ' (not found)')+'; this supplier keeps no capability_summary and cannot be matched to any RFQ'); return J({ error:'lead_not_found' }, 404); }
      const r = await enrichOne(lead);
      await logRun(r.ok ? 'ok' : 'error', { stage:'single', lead_id: r.id, enriched: r.ok ? 1 : 0, low_confidence: r.low === true, reason: r.reason, llm_key_missing: LLM_STATE.keyMissing, llm_failures: LLM_STATE.failures }, r.ok ? ('Supplier '+r.id+' enriched'+(r.low ? ' with low_confidence (thin profile, so the adjudicator may under-match this supplier)' : '')) : ('Supplier '+r.id+' was NOT enriched ('+String(r.reason)+(LLM_STATE.failures.length ? ('; llm: '+LLM_STATE.failures.join(' | ')) : '')+'); it is left without a capability_summary and cannot be matched to any RFQ'));
      return J({ ok: true, ...r });
    }

    // batch backfill: approved, matchable, not yet enriched
    const limit = Math.min(Number(body.limit) || 10, 25);
    const { data: leads, error: batchErr } = await admin.from('leads').select(COLS + ',capability_enriched_at,approval_status,registration_submitted_at,source,banned,matching_blocked')
      .eq('approval_status','approved').is('capability_enriched_at', null).limit(limit);
    if (batchErr) { await logRun('error', { stage:'batch_select', limit }, 'Could not read the backlog of approved suppliers awaiting enrichment: '+String(batchErr.message)+'; the whole backlog stays without capability_summary and none of those suppliers can be matched to any RFQ'); }
    const cands = (leads || []).filter((l:any)=> (l.registration_submitted_at || l.source==='self_registered') && !l.banned && !l.matching_blocked);
    const results = []; let done = 0;
    for (const l of cands) { const r = await enrichOne(l); if (r.ok) done++; results.push(r); }
    const failed = results.filter((r:any)=> !r.ok);
    const lowN = results.filter((r:any)=> r.low === true).length;
    const notes: string[] = [];
    if (batchErr) notes.push('backlog query failed: '+String(batchErr.message));
    if (LLM_STATE.keyMissing) notes.push('openrouter_api_key is missing from app_secrets, so NO supplier can be enriched at all: every approved supplier awaiting enrichment stays without a capability_summary and is unmatchable to every RFQ until the key is restored');
    if (failed.length) notes.push(failed.length+' of '+cands.length+' suppliers were not enriched (ids '+failed.map((r:any)=>r.id).join(',')+'; reasons '+[...new Set(failed.map((r:any)=>String(r.reason)))].join(',')+'); they are left without a capability_summary, so the adjudicator cannot judge them and they will never be matched to any RFQ');
    if (LLM_STATE.failures.length) notes.push('llm errors: '+LLM_STATE.failures.join(' | '));
    if (lowN) notes.push(lowN+' summaries were low_confidence (thin supplier profiles), which typically means those suppliers get under-matched');
    if (!notes.length) notes.push(cands.length ? ('Enriched '+done+' of '+cands.length+' suppliers; all now have a capability_summary and are matchable') : 'No approved suppliers were awaiting enrichment');
    await logRun((batchErr || failed.length || LLM_STATE.keyMissing) ? 'error' : 'ok', { stage:'batch', limit, candidates: cands.length, enriched: done, failed: failed.length, low_confidence: lowN, llm_key_missing: LLM_STATE.keyMissing, batch_select_failed: batchErr ? 1 : 0 }, notes.join(' | '));
    return J({ ok: true, processed: cands.length, enriched: done, results });
  } catch (e) { await logRun('error', { stage:'run' }, 'enrich_capability crashed: '+String((e as Error)?.message || e)+'; the suppliers in this batch keep no capability_summary and cannot be matched to any RFQ'); return J({ error: String((e as Error)?.message || e) }, 500); }
});
