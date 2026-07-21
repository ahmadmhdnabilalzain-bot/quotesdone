// exec_board — admin-authed read of the Executive Intelligence reports for the /crm Board tab.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function isAdmin(req: Request, body: any): Promise<boolean> {
  if (body && body.__secret && body.__secret === (await sec('inbound_secret'))) return true;
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return false;
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user?.email) return false;
  const admins = String((await sec('admin_emails')) || 'management@quotesdone.com').toLowerCase().split(',').map((s) => s.trim());
  return admins.includes(user.email.toLowerCase());
}
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await isAdmin(req, body))) return J({ error: 'forbidden' }, 403);
    const action = String(body.action || 'latest');
    if (action === 'history') {
      const officer = String(body.officer || '');
      const { data } = await admin.from('exec_reports').select('*').eq('officer', officer).order('created_at', { ascending: false }).limit(12);
      return J({ ok: true, reports: data || [] });
    }
    // latest: newest report per officer + headline quote-quality
    const { data: all } = await admin.from('exec_reports').select('*').order('created_at', { ascending: false }).limit(60);
    const seen = new Set<string>(); const latest: any[] = [];
    for (const r of (all || [])) { if (seen.has(r.officer)) continue; seen.add(r.officer); latest.push(r); }
    const order = ['strategy','operations','procurement_quality','data_science','product_ux','competitive'];
    latest.sort((a, b) => order.indexOf(a.officer) - order.indexOf(b.officer));
    const { data: qq } = await admin.from('quotes').select('quality');
    const scored = (qq || []).filter((x: any) => x.quality && x.quality.score != null);
    const avg = scored.length ? Math.round(scored.reduce((s: number, x: any) => s + Number(x.quality.score), 0) / scored.length) : null;
    const low = scored.filter((x: any) => Number(x.quality.score) < 50).length;
    return J({ ok: true, reports: latest, quote_quality: { avg_completeness: avg, low_quality: low, total_scored: scored.length } });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
