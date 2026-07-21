import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
Deno.serve(async (req) => {
  try {
    const b = await req.json().catch(()=>({} as any));
    if (b.__secret !== (await sec('inbound_secret'))) return J({ error:'forbidden' }, 403);
    const token = await sec('vercel_token'); const team = await sec('vercel_team_id');
    const H = { Authorization: 'Bearer ' + token };
    if (b.action === 'logs') {
      const r = await fetch('https://api.vercel.com/v3/deployments/' + b.id + '/events?teamId=' + team + '&direction=backward&limit=200', { headers: H });
      const arr = await r.json();
      const lines = (Array.isArray(arr) ? arr : []).map((e:any)=> (e.text||e.payload?.text||'')).filter((x:string)=>x && /error|fail|Error|cannot|Cannot|Unexpected|Module|not found|Type|Syntax/.test(x)).slice(-40);
      return J({ ok:true, lines });
    }
    const r = await fetch('https://api.vercel.com/v13/deployments/' + b.id + '?teamId=' + team, { headers: H });
    const j = await r.json();
    return J({ ok:r.ok, readyState: j.readyState || j.status, aliasError: j.aliasError||null });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});