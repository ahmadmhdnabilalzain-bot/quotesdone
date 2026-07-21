import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const { data: cust } = await admin.from('customers').select('id').eq('email', user.email.toLowerCase()).maybeSingle();
    if (!cust) return J({ duplicate: false });
    const body = await req.json().catch(() => ({}));
    const summary = String(body.summary || body.text || '').slice(0, 500);
    const hours = Math.min(Math.max(Number(body.hours) || 72, 1), 720);
    if (summary.length < 13) return J({ duplicate: false });
    const { data: dupId } = await admin.rpc('recent_duplicate_inquiry', { p_customer: cust.id, p_summary: summary, p_window: hours + ' hours' });
    if (!dupId) return J({ duplicate: false });
    const { data: inq } = await admin.from('inquiries').select('id,summary,category,emirate,created_at,status').eq('id', dupId).maybeSingle();
    return J({ duplicate: true, inquiry: inq || { id: dupId } });
  } catch (e) { return J({ duplicate: false, error: String((e as Error)?.message || e) }); }
});
