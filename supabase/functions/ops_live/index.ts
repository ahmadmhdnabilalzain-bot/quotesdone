// ops_live — admin-authed live operations dashboard data for the /crm Ops tab.
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
    const { data, error } = await admin.rpc('fn_ops_dashboard');
    if (error) return J({ error: error.message }, 500);
    return J({ ok: true, dashboard: data });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
