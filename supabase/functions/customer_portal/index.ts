// customer_portal — advanced customer dashboard API. Customer-authed (own customers row).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user) return J({ error: 'unauthorized' }, 401);
    const email = (user.email || '').toLowerCase();
    let { data: cust } = await admin.from('customers').select('id,full_name,email').eq('id', user.id).maybeSingle();
    if (!cust && email) { const r = await admin.from('customers').select('id,full_name,email').eq('email', email).maybeSingle(); cust = r.data; }
    if (!cust) return J({ error: 'no_customer', hint: 'no customer profile for this account' }, 400);
    const b = await req.json().catch(() => ({} as any));
    const action = b.action;
    const ar = String(b.lang || 'en') === 'ar';

    if (action === 'overview') {
      const { data: stats, error } = await admin.rpc('fn_customer_stats', { p_customer: cust.id });
      if (error) return J({ error: error.message }, 500);
      const inqs = (stats && stats.inquiries) || [];
      const alerts: any[] = [];
      const editable = inqs.filter((x: any) => x.editable);
      for (const e of editable) {
        const cat = e.category || (ar ? 'طلبك' : 'your request');
        alerts.push({ kind: 'edit_window', severity: 'medium',
          title: ar ? ('ما زال بإمكانك تعديل «' + cat + '»') : ('You can still edit “' + cat + '”'),
          detail: ar ? ('قابل للتعديل لمدة ' + e.edit_minutes_left + ' دقيقة أخرى، بعدها تُقفل التعديلات ويستمر المورّدون في التسعير على النطاق الأصلي.') : ('Editable for another ' + e.edit_minutes_left + ' minutes. After that, edits are locked and suppliers keep quoting the original scope.'),
          inquiry_id: e.id });
      }
      const toReview = inqs.filter((x: any) => (x.quotes_count || 0) > 0 && !['completed', 'closed', 'cancelled'].includes(String(x.status)));
      for (const t of toReview) {
        const cat = t.category || (ar ? 'طلبك' : 'your request');
        const n = t.quotes_count;
        alerts.push({ kind: 'quotes_ready', severity: 'low',
          title: ar ? (n + ' عرض للمراجعة على «' + cat + '»') : (n + ' quote' + (n > 1 ? 's' : '') + ' to review on “' + cat + '”'),
          detail: ar ? ('قارن العروض جنبًا إلى جنب واكشف عن المورّد الذي تريد.') : ('Compare quotes side by side and reveal the supplier you want.'),
          inquiry_id: t.id });
      }
      return J({ ok: true, customer: { id: cust.id, name: cust.full_name }, stats, alerts, alerts_count: alerts.length });
    }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
