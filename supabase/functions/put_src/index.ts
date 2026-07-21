import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
Deno.serve(async (req)=>{
  try{
    const b = await req.json().catch(()=>({}));
    if(b.__secret !== (await sec('inbound_secret'))) return new Response(JSON.stringify({error:'forbidden'}),{status:403,headers:{'Content-Type':'application/json'}});
    if(!b.path || typeof b.data!=='string') return new Response(JSON.stringify({error:'bad_request'}),{status:400,headers:{'Content-Type':'application/json'}});
    const { error } = await admin.from('qd_deploy_src').upsert({ path:b.path, data:b.data });
    if(error) return new Response(JSON.stringify({error:error.message}),{status:500,headers:{'Content-Type':'application/json'}});
    return new Response(JSON.stringify({ ok:true, bytes:b.data.length }),{headers:{'Content-Type':'application/json'}});
  }catch(e){ return new Response(JSON.stringify({error:String((e as Error)?.message||e)}),{status:500,headers:{'Content-Type':'application/json'}}); }
});
