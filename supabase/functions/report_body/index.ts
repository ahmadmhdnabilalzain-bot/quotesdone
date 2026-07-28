// report_body — returns the full text of a board/agent report for the OS reports viewer.
// Admin-only (JWT + admin_emails). report_registry.id maps 1:1 to board_reports.id.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    // FAIL-OPEN FIX 28 Jul 2026. The gate read `if (admins.length && !admins.includes(...))`, so it only
    // applied when admin_emails was readable and non-empty. With that row missing, renamed, or the read
    // returning nothing, admins was empty, the whole check was skipped and any authenticated user - every
    // supplier and customer holding a QuotesDone login - could read board_reports in full. A guard must
    // never be conditional on its own config being readable. It now falls closed to the founder and runs
    // unconditionally, the same shape canon_eval, content_revise, dept_plan, dept_learn, marketing_draft,
    // analytics_recommend and boost_recommend already use.
    const admins = (await sec('admin_emails') || 'management@quotesdone.com').toLowerCase().split(',').map((s) => s.trim()).filter(Boolean);
    if (!admins.includes(user.email.toLowerCase())) return J({ error: 'admin only' }, 403);
    const b = await req.json().catch(() => ({} as any));
    const id = Number(b.id);
    if (!id) return J({ error: 'id required' }, 400);
    const { data: rpt } = await admin.from('board_reports').select('id,title,report_type,week_start,body,kpis,created_at').eq('id', id).maybeSingle();
    if (!rpt) return J({ ok: true, found: false, note: 'No stored body for this report id.' });
    return J({ ok: true, found: true, report: rpt });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
