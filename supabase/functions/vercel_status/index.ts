import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
Deno.serve(async (req) => {
  try {
    const b = await req.json().catch(()=>({} as any));
    const __exp = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, b?.__secret, 'vercel_status');
    if (!__auth.ok) return J({ error:'forbidden' }, 403);
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