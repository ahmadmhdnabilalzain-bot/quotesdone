import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string)||''; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const J=(o:unknown,s=200)=>new Response(JSON.stringify(o),{status:s,headers:{'Content-Type':'application/json'}});
Deno.serve(async (req)=>{
  try{
    const body=await req.json().catch(()=>({}as any));
    const __exp = await sec('inbound_secret');
    if(!secretOk(__exp) || body.__secret!==__exp) return J({error:'forbidden'},403);
    const topic=String(body.topic||'MDF moisture resistant grade selection for joinery');
    const key=await sec('openrouter_api_key'); if(!key) return J({error:'no key'},500);
    const r=await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',headers:{'Authorization':'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({
      model:'anthropic/claude-sonnet-5',
      plugins:[{id:'web',max_results:5}],
      max_tokens:900,
      messages:[{role:'system',content:'You are a UAE construction/materials researcher. Research the topic from authoritative sources and write a short grounded factual brief. Cite specifics.'},{role:'user',content:'Research for the UAE (Dubai) market: '+topic}]
    })});
    const j=await r.json();
    const msg=j?.choices?.[0]?.message||{};
    const ann=(msg.annotations||[]).map((a:any)=>a?.url_citation?.url||a?.url||null).filter(Boolean);
    return J({ok:true,status:r.status,has_content:!!msg.content,content_preview:String(msg.content||'').slice(0,400),source_count:ann.length,sources:ann,raw_error:j?.error||null});
  }catch(e){ return J({error:String((e as Error)?.message||e)},500); }
});
