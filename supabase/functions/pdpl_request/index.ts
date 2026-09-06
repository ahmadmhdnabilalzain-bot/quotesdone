// pdpl_request - public endpoint for UAE PDPL data export/delete requests. CORS-enabled. Rate-limited per email/day.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin':'*', 'Access-Control-Allow-Headers':'content-type', 'Access-Control-Allow-Methods':'POST, OPTIONS', 'Content-Type':'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined) || undefined; }
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(()=>({} as any));
    const kind = String(body.kind||'').toLowerCase();
    const email = String(body.email||'').trim().toLowerCase();
    if (!['export','delete'].includes(kind)) return J({ error:'kind must be export or delete' }, 400);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return J({ error:'valid email required' }, 400);
    // rate limit: max 3 open requests per email
    const { count } = await admin.from('pdpl_requests').select('id',{count:'exact',head:true}).eq('email',email).gt('created_at', new Date(Date.now()-86400000).toISOString());
    if ((count||0) >= 3) return J({ error:'too many requests today' }, 429);
    const role = ['customer','supplier'].includes(String(body.role)) ? String(body.role) : null;
    const details = String(body.details||'').slice(0,1000);
    const { data, error } = await admin.from('pdpl_requests').insert({ kind, email, role, details }).select('id').maybeSingle();
    if (error) return J({ error: error.message }, 500);
    // notify founder
    const inbound = await sec('cred_fn_pdpl_request');
    fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/alert_founder`, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ __secret: inbound, event:'PDPL '+kind+' request', detail: email, level:'action', kind: 'pdpl_request' }) }).catch(()=>{});
    return J({ ok:true, id: data?.id, message: kind==='delete' ? 'Your deletion request has been received. We will process it within 30 days.' : 'Your data export request has been received. We will email it within 30 days.' });
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
});
