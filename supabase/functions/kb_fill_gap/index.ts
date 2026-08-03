// kb_fill_gap — generate + ingest UAE trade knowledge for a category gap. Admin-JWT or __secret gated.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function isAdmin(email: string){ if(!email) return false; const em=email.toLowerCase(); try{const{data}=await admin.rpc('fn_role_of',{p_email:em}); if(['owner','admin'].includes(String(data||'').toLowerCase())) return true;}catch(_e){} try{const{data}=await admin.from('app_secrets').select('value').eq('key','admin_emails').maybeSingle(); const list=String((data as any)?.value||'').toLowerCase().split(/[,;\s]+/).filter(Boolean); if(list.includes(em)) return true;}catch(_e){} return false; }

function parseSections(raw: string): any[] {
  let txt = String(raw || '').replace(/```json/gi, '').replace(/```/g, '').trim();
  try { const m = txt.match(/\{[\s\S]*\}/); const o = JSON.parse(m ? m[0] : txt); if (Array.isArray(o?.sections)) return o.sections; } catch (_e) {}
  try { const am = txt.match(/"sections"\s*:\s*(\[[\s\S]*\])/); if (am) { const arr = JSON.parse(am[1]); if (Array.isArray(arr)) return arr; } } catch (_e) {}
  return [];
}
async function genOnce(key: string, label: string, category: string): Promise<any[]> {
  const prompt = `You are QuotesDone's trade knowledge curator for the UAE B2B services market. Produce authoritative, factual reference knowledge for the service category "${label}" (slug: ${category}).\nReturn STRICT JSON ONLY (no markdown, no prose): {\"sections\":[{\"title\":\"...\",\"content\":\"...\"}]} with 4-6 sections covering: (1) Scope & typical deliverables, (2) UAE regulations/standards & required approvals — name the authority (SIRA, Dubai Municipality, Civil Defence, DEWA, ADDC, ESMA, TDRA, etc.), (3) Key materials/brands/equipment, (4) Pricing drivers & typical cost ranges in AED, (5) Common quality red flags & how to vet suppliers, (6) Typical project timeline. Be specific to the UAE.`;
  const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: key, fn: 'kb_fill_gap', sys: '', input: prompt, temperature: 0.2 }) });
  const jd = await r.json().catch(() => ({} as any));
  return parseSections(jd?.content || '');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return J({ ok: true });
  try {
    const body = await req.json().catch(() => ({} as any));
    let ok = false;
    if (body?.__secret && (await requireInternal(admin, body.__secret, 'kb_fill_gap')).ok) ok = true;
    else { const tok = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim(); if (tok) { const { data: u } = await admin.auth.getUser(tok); const em = u?.user?.email || ''; if (em && await isAdmin(em)) ok = true; } }
    if (!ok) return J({ error: 'unauthorized' }, 401);

    const category = String(body?.category || '').trim(); const label = String(body?.label || category).trim();
    if (!category) return J({ error: 'category_required' }, 400);
    const key = await sec('cred_fn_ai'); if (!key) return J({ error: 'no_llm_key' }, 500);

    let sections = await genOnce(key, label, category);
    if (!sections.length) sections = await genOnce(key, label, category); // one retry
    if (!sections.length) return J({ error: 'generation_failed' }, 502);

    const rows = sections.slice(0, 8).filter((s: any) => s && (s.content || s.title)).map((s: any) => ({ source_kind: 'generated', category, title: String(s.title || 'Knowledge'), content: String(s.content || ''), citation: `QuotesDone trade knowledge: ${category} / ${String(s.title || '')}`, effective_date: new Date().toISOString().slice(0, 10) }));
    if (!rows.length) return J({ error: 'empty_sections' }, 502);
    const { data: ins, error } = await admin.from('kb_chunks').insert(rows).select('id');
    if (error) return J({ error: error.message }, 500);
    try { await admin.from('agent_actions').insert({ agent: 'knowledge_curator', status: 'done', title: `Filled knowledge gap: ${label}`, risk: 'low', recommendation: `Generated ${rows.length} chunks for ${category}` }); } catch (_e) {}
    return J({ ok: true, inserted: (ins?.length || rows.length), category });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
