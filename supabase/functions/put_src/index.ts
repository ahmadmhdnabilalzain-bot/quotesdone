import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// SECURITY FIX 27 Jul 2026 -----------------------------------------------------------------------
// WHAT WAS WRONG: this writer was gated on inbound_secret - the single shared secret that 134 of the
// 187 edge functions accept. It takes ANY path and ANY string and upserts it into qd_deploy_src, and
// deploy_next_preview publishes that whole table to Vercel. So inbound_secret was never "an API key
// with some reach": one leak of it meant arbitrary code on quotesdone.com. Blast radius = the site.
// WHY THIS FIX: deploy authority now needs its OWN key - app_secrets key 'deploy_secret', sent as
// body.__deploy_secret. Until that row exists we still honour inbound_secret so publishing does not
// break before the founder creates it, but every fallback authorisation is written to agent_runs with
// status 'error' so the gap is loud, not silent. Delete the fallback once deploy_secret is live.
async function deployAuth(b:any, fn:string){
  const dep = await sec('deploy_secret');
  if (dep) return b.__deploy_secret === dep;
  const inbound = await sec('inbound_secret');
  const ok = !!inbound && (b.__deploy_secret === inbound || b.__secret === inbound);
  if (ok) { const t = new Date().toISOString(); try { await admin.from('agent_runs').insert({ agent:'deploy_authority', started_at:t, finished_at:t, status:'error', counts:{ fallback_auth:1, fn }, note:'DEPLOY SECRET NOT SET YET: '+fn+' authorised a deploy-capable call using inbound_secret because app_secrets has no deploy_secret row. inbound_secret is accepted by 134 of 187 functions, so until deploy_secret exists anything holding it can write source and publish it to quotesdone.com. Create app_secrets key deploy_secret and have callers send __deploy_secret.' }); } catch(_e){ /* never block the deploy path on a log write */ } }
  return ok;
}
Deno.serve(async (req)=>{
  try{
    const b = await req.json().catch(()=>({}));
    if(!(await deployAuth(b,'put_src'))) return new Response(JSON.stringify({error:'forbidden'}),{status:403,headers:{'Content-Type':'application/json'}});
    if(!b.path || typeof b.data!=='string') return new Response(JSON.stringify({error:'bad_request'}),{status:400,headers:{'Content-Type':'application/json'}});
    const { error } = await admin.from('qd_deploy_src').upsert({ path:b.path, data:b.data });
    if(error) return new Response(JSON.stringify({error:error.message}),{status:500,headers:{'Content-Type':'application/json'}});
    return new Response(JSON.stringify({ ok:true, bytes:b.data.length }),{headers:{'Content-Type':'application/json'}});
  }catch(e){ return new Response(JSON.stringify({error:String((e as Error)?.message||e)}),{status:500,headers:{'Content-Type':'application/json'}}); }
});
