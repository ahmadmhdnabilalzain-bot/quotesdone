import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const SYS = `You are a professional English→Arabic translator for a UAE B2B quotation marketplace called QuotesDone.
Translate the VISIBLE TEXT of the given HTML fragment into natural, fluent Modern Standard Arabic (فصحى) appropriate for UAE business users.
HARD RULES:
1. Preserve ALL HTML tags, attributes, class names, ids, hrefs and overall structure EXACTLY as-is. Do not add, remove, or reorder tags.
2. Do NOT translate: the brand name "QuotesDone", any URL/href/src, email addresses, numbers, dates, currency codes (AED), or code.
3. Translate human-readable text between tags, and the VALUE of placeholder/title/aria-label/alt attributes when present.
4. Keep it accurate and professional. For legal text, translate faithfully and precisely.
5. Output ONLY the translated HTML fragment — no explanations, no markdown fences.`;
Deno.serve(async (req) => {
  try {
    const b = await req.json().catch(()=>({} as any));
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || b.__secret !== __exp) return J({ error:'forbidden' }, 403);
    const key = await sec('openrouter_api_key'); if(!key) return J({ error:'no_key' }, 500);
    const html = String(b.html||''); if(!html) return J({ error:'no_html' }, 400);
    // Primary model + automatic fallbacks (retired slugs like claude-3.5-sonnet 404 on this account).
    const model = b.model || 'anthropic/claude-sonnet-5';
    const models = [model, 'openai/gpt-4o', 'openai/gpt-4o-mini'].filter((v,i,a)=>a.indexOf(v)===i);
    const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method:'POST', headers:{ 'Authorization':'Bearer '+key, 'Content-Type':'application/json' }, body: JSON.stringify({ models, temperature:0.2, max_tokens:8000, messages:[{role:'system',content:SYS},{role:'user',content:html}] }) });
    const jd = await r.json();
    if(!r.ok) return J({ error:'llm_failed', status:r.status, detail: JSON.stringify(jd).slice(0,400) }, 200);
    let out = jd?.choices?.[0]?.message?.content || '';
    out = out.replace(/^```[a-z]*\n?/i,'').replace(/```\s*$/,'').trim();
    return J({ ok:true, ar: out, model: jd?.model || model, usage: jd?.usage||null });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});