// catalogue_ingest — turns a supplier's big catalogue / company profile into agent-readable capability
// text. Vision-reads sampled pages (sent by the portal), extracts the real products/brands/materials/
// services, and MERGES a factual capability profile into leads.capability_summary (the matching fuel).
// The heavy original file stays in storage for the record; agents read this distilled version.
// __secret-gated (invoked server-side by supplier_api).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function parseJson(t: string){ try { const m = String(t||'').match(/\{[\s\S]*\}/); return m ? JSON.parse(m[0]) : null; } catch { return null; } }

async function callModel(system: string, parts: any[], max: number): Promise<string> {
  const key = await sec('openrouter_api_key'); if (!key) return '';
  const MODELS = ['anthropic/claude-sonnet-5','anthropic/claude-opus-4.8'];
  for (const model of MODELS) {
    try {
      const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method:'POST', headers:{ 'Authorization':'Bearer '+key, 'Content-Type':'application/json' }, body: JSON.stringify({ model, max_tokens: max, temperature: 0, messages:[{role:'system',content:system},{role:'user',content:parts}] }) });
      const j = await r.json(); const c = j?.choices?.[0]?.message?.content; if (c) return c;
    } catch (_e) { /* next */ }
  }
  return '';
}

const EXTRACT_SYS = 'You are reading pages from a UAE supplier\'s product catalogue or company profile. Extract ONLY what is factually shown: the products and product ranges they supply, brands they carry or represent, materials, the services they perform, and the sectors/clients they serve. Ignore decorative pages, cover art, and pure contact pages. Do NOT invent anything not visible. Output ONLY minified JSON: {"found": boolean, "capabilities": string (concise factual bullet text, <= 220 words), "brands": string[], "low_confidence": boolean}.';
const MERGE_SYS = 'You maintain a UAE supplier\'s capability profile used by an AI to match them to jobs. Merge the EXISTING profile with NEW findings from their catalogue into one concise, factual, de-duplicated capability_summary (80-180 words, plain declarative sentences, no marketing fluff, no first person). Keep only what is supported; do not invent. Output ONLY minified JSON: {"capability_summary": string}.';

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) return J({ error:'forbidden' }, 403);
    const leadId = Number(body.lead_id); if (!leadId) return J({ error:'lead_id_required' }, 400);
    const images: any[] = Array.isArray(body.images) ? body.images.slice(0, 12).filter((im:any)=>im?.data && im?.mime) : [];
    if (!images.length) return J({ error:'no_images' }, 400);

    // 1) vision-extract capability content from the sampled pages
    const parts: any[] = [{ type:'text', text:'Extract this supplier\'s real capabilities from these catalogue/profile pages.' }];
    for (const im of images) parts.push({ type:'image_url', image_url:{ url:`data:${im.mime};base64,${im.data}` } });
    const ext = parseJson(await callModel(EXTRACT_SYS, parts, 1200));
    if (!ext || !ext.found || !ext.capabilities) return J({ ok:true, updated:false, note:'no_extractable_capabilities' });

    // 2) merge with the existing profile
    const { data: lead } = await admin.from('leads').select('company_name,categories,services,products,capability_summary').eq('id', leadId).maybeSingle();
    if (!lead) return J({ error:'lead_not_found' }, 404);
    const existing = [ lead.company_name && ('Company: '+lead.company_name), lead.categories && ('Categories: '+lead.categories), lead.services && ('Services: '+lead.services), lead.products && ('Products: '+lead.products), lead.capability_summary && ('Current summary: '+lead.capability_summary) ].filter(Boolean).join('\n');
    const mergeUser = [{ type:'text', text:'EXISTING PROFILE:\n'+(existing||'(none)')+'\n\nNEW CATALOGUE FINDINGS:\n'+String(ext.capabilities)+(Array.isArray(ext.brands)&&ext.brands.length?('\nBrands: '+ext.brands.join(', ')):'') }];
    const merged = parseJson(await callModel(MERGE_SYS, mergeUser, 700));
    const summary = merged?.capability_summary ? String(merged.capability_summary).slice(0, 1600) : String(ext.capabilities).slice(0,1600);
    if (!summary) return J({ ok:true, updated:false });

    await admin.from('leads').update({ capability_summary: summary, capability_enriched_at: new Date().toISOString() }).eq('id', leadId);
    return J({ ok:true, updated:true, pages_read: images.length, brands: ext.brands || [], low_confidence: ext.low_confidence === true });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
