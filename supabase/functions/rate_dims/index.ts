// rate_dims — persists the 6 reputation dimensions onto an existing review row.
// Called by /app right after rate_supplier. Customer Supabase JWT auth.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const DIMS = ['r_communication','r_quality','r_punctuality','r_documentation','r_after_sales','r_compliance'];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user?.email) return J({ error: 'Not signed in' }, 401);
    const { data: cust } = await admin.from('customers').select('id').eq('email', user.email.toLowerCase()).maybeSingle();
    if (!cust) return J({ error: 'unauthorized' }, 401);
    const body = await req.json().catch(() => ({} as any));
    const qid = String(body.quote_id || '');
    if (!qid) return J({ error: 'quote_id required' }, 400);
    const patch: Record<string, number> = {};
    for (const d of DIMS) { const v = Number((body as any)[d]); if (v >= 1 && v <= 5) patch[d] = Math.round(v); }
    if (!Object.keys(patch).length) return J({ ok: true, updated: 0, note: 'no dimensions supplied' });
    const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', qid).eq('customer_id', cust.id).maybeSingle();
    if (!tx) return J({ error: 'You can only rate a supplier you have dealt with.' }, 403);
    const { data: rev } = await admin.from('reviews').select('id').eq('transaction_id', tx.id).eq('customer_id', cust.id).maybeSingle();
    if (!rev) return J({ error: 'Submit the overall rating first.' }, 409);
    const { error } = await admin.from('reviews').update(patch).eq('id', rev.id);
    if (error) return J({ error: error.message }, 500);
    try { const { data: q } = await admin.from('quotes').select('supplier_id').eq('id', qid).maybeSingle(); if (q) await admin.rpc('recompute_supplier_rating', { p_supplier: q.supplier_id }); } catch (_e) {}
    return J({ ok: true, updated: Object.keys(patch).length });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
