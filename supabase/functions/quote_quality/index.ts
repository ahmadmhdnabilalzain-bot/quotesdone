// quote_quality — returns the completeness gate result for the customer's own quotes (badge in /app).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user?.email) return J({ error: 'Not signed in' }, 401);
    const { data: cust } = await admin.from('customers').select('id').eq('email', user.email.toLowerCase()).maybeSingle();
    if (!cust) return J({ error: 'unauthorized' }, 401);
    const body = await req.json().catch(() => ({} as any));
    const ids = Array.isArray(body.quote_ids) ? body.quote_ids.map((x: any) => String(x)).slice(0, 60) : [];
    if (!ids.length) return J({ ok: true, quality: {} });
    const { data: qs } = await admin.from('quotes').select('id,quality,inquiry_id').in('id', ids);
    const inqIds = [...new Set((qs || []).map((q: any) => q.inquiry_id))];
    const { data: inqs } = await admin.from('inquiries').select('id').eq('customer_id', cust.id).in('id', inqIds);
    const owned = new Set((inqs || []).map((i: any) => i.id));
    const out: Record<string, any> = {};
    for (const q of (qs || [])) {
      if (!owned.has(q.inquiry_id)) continue;
      const ql = q.quality || {};
      const miss = Array.isArray(ql.missing) ? ql.missing.filter((m: any) => m && m.mandatory).length : null;
      out[String(q.id)] = { score: ql.score ?? null, pass: ql.pass ?? null, missing_mandatory: miss };
    }
    return J({ ok: true, quality: out });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
