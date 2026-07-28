import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
Deno.serve(async (req)=>{
  let b:any={}; try{ b=await req.json(); }catch(_){}
  const __exp = await sec('inbound_secret');
  if(!secretOk(__exp) || b.__secret!==__exp) return new Response(JSON.stringify({error:'forbidden'}),{status:403,headers:{'Content-Type':'application/json'}});
  const items=Array.isArray(b.items)?b.items:[]; let n=0; const errs:string[]=[];
  for(const it of items){
    const slug=String(it.slug||'').trim(); const title=String(it.title||'').trim();
    const category=(String(it.category||'public').trim()==='internal')?'internal':'public';
    const body=String(it.body_html||''); const summary=String(it.summary||'').slice(0,600);
    if(!slug||!title||body.length<40){ errs.push((slug||'?')+': skipped'); continue; }
    try{ await admin.from('legal_documents').upsert({slug,title,category,summary,body_html:body.slice(0,60000),version:String(it.version||'1.0'),effective_date:new Date().toISOString().slice(0,10),updated_at:new Date().toISOString()},{onConflict:'slug'}); n++; }catch(e){ errs.push(slug+': '+String((e as Error)?.message||e)); }
  }
  return new Response(JSON.stringify({ok:true,upserted:n,errors:errs.slice(0,20),received:items.length}),{headers:{'Content-Type':'application/json'}});
});