// seo_gen - AI-writes intro/includes/faqs for seo_categories (concurrent batch). Secret-guarded.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
function parseJson(t: string){ try{return JSON.parse(t);}catch{ const m=t.match(/\{[\s\S]*\}/); if(m){try{return JSON.parse(m[0]);}catch{}} return null; } }
const SYS = `You write helpful, accurate SEO landing-page content for QuotesDone, a UAE home & building services marketplace where customers get multiple quotes from vetted suppliers. For the given service, return STRICT JSON ONLY: {"intro": string (~110-140 words, UK English, UAE context: what the service covers, who typically needs it, what affects cost/scope, and that customers can compare several quotes free; natural and useful, not keyword-stuffed), "includes": string[] (exactly 6 concrete scope items a customer might request), "faqs": [{"q":string,"a":string}] (exactly 3 real questions UAE customers ask — e.g. cost factors, timelines, what to check in a quote — with concise 1-2 sentence answers)}. Use AED and UAE emirates where natural. Never invent specific prices.`;
async function genOne(key: string, c: any){
  try {
    const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method:'POST', headers:{'Authorization':'Bearer '+key,'Content-Type':'application/json'}, body: JSON.stringify({ models:['anthropic/claude-sonnet-5','anthropic/claude-opus-4.8'], max_tokens:1200, temperature:0.4, messages:[{role:'system',content:SYS},{role:'user',content:'Service: '+c.name+' (search intent: '+(c.search_term||c.name)+'). Country: United Arab Emirates.'}] }) });
    const jd = await r.json(); const p = parseJson(jd?.choices?.[0]?.message?.content||'');
    if (p && p.intro) { await admin.from('seo_categories').update({ intro:String(p.intro).slice(0,2000), includes:Array.isArray(p.includes)?p.includes.slice(0,8):[], faqs:Array.isArray(p.faqs)?p.faqs.slice(0,5):[], generated:true, updated_at:new Date().toISOString() }).eq('slug', c.slug); return true; }
    return false;
  } catch(_e){ return false; }
}
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) return J({ error:'forbidden' }, 403);
    const key = await sec('openrouter_api_key'); if(!key) return J({ error:'no_ai' }, 200);
    const { data: rows } = await admin.from('seo_categories').select('slug,name,search_term').eq('generated', false).order('sort').limit(20);
    if (!rows || !rows.length) return J({ ok:true, finished:true, done:0 });
    const results = await Promise.all(rows.map((c)=>genOne(key, c)));
    const done = results.filter(Boolean).length;
    const { count: remaining } = await admin.from('seo_categories').select('slug',{count:'exact',head:true}).eq('generated', false);
    return J({ ok:true, done, remaining: remaining||0 });
  } catch(e){ return J({ error:String((e as Error)?.message||e) }, 500); }
});
