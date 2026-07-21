// supplier_me — returns the authenticated supplier's own digital twin + reputation.
// Auth: supplier Supabase JWT -> email -> leads.claimed_by (claimed=true).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

async function supplier(req: Request): Promise<number | null> {
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user?.email) return null;
  const { data: l } = await admin.from('leads').select('id').eq('claimed_by', user.email.toLowerCase()).eq('claimed', true).maybeSingle();
  return l ? Number(l.id) : null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const sid = await supplier(req);
    if (!sid) return J({ error: 'unauthorized' }, 401);
    const [{ data: twin }, { data: rep }, { data: lead }] = await Promise.all([
      admin.from('supplier_twin').select('*').eq('supplier_id', sid).maybeSingle(),
      admin.from('supplier_reputation').select('*').eq('supplier_id', sid).maybeSingle(),
      admin.from('leads').select('company_name,emirate,categories,approval_status,response_rate_pct').eq('id', sid).maybeSingle()
    ]);
    // recent RFQs in their categories, matched vs not (last 30d)
    let recent_30d = 0, matched = 0, not_matched = 0;
    try {
      const cats = (lead?.categories || []) as string[];
      if (cats.length) {
        const since = new Date(Date.now() - 30 * 864e5).toISOString();
        const { data: rfqs } = await admin.from('inquiries').select('id').in('category', cats).gte('created_at', since);
        const ids = (rfqs || []).map((r: any) => r.id);
        recent_30d = ids.length;
        if (ids.length) { const { data: m } = await admin.from('inquiry_matches').select('inquiry_id').eq('supplier_id', sid).in('inquiry_id', ids); matched = (m || []).length; not_matched = ids.length - matched; }
      }
    } catch (_e) { /* best effort */ }
    return J({ ok: true, supplier_id: sid, lead: lead || null, twin: twin || null, reputation: rep || null,
      exposure: { recent_rfqs_in_your_categories_30d: recent_30d, you_were_invited: matched, you_were_not_invited: not_matched } });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
