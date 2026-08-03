// analytics_recommend — the Analytics & Intelligence department's data-grounded advisory executor.
// Pulls LIVE marketplace + funnel metrics (fn_query_platform), then has the analytics head synthesize
// a concrete, prioritized recommendation that CITES those numbers — instead of reasoning in the
// abstract. Records the recommendation as a shared org insight (org_memory). Read + recommend only:
// NO business side effects, which is why it is safe to run for advisory-tier tasks.
// Auth: __secret (cos_execute / cron) OR admin-email JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const llm = makeLlm(SONNET_FIRST, { max: 900, temperature: 0.2 });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function authed(req: Request, body: any): Promise<boolean> {
  if (body?.__secret && (await requireInternal(admin, body.__secret, 'analytics_recommend')).ok) return true;
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return false;
  const { data: { user } } = await admin.auth.getUser(jwt);
  const allow = (await sec('admin_emails') || 'management@quotesdone.com').split(',').map((s) => s.trim().toLowerCase());
  return !!(user?.email && allow.includes(user.email.toLowerCase()));
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await authed(req, body))) return J({ error: 'forbidden' }, 403);

    // Resolve the task (title/detail/objective) — cos_execute passes task_id.
    let title = String(body.title || '').trim(), detail = String(body.detail || '').trim(), objectiveText = '';
    if (body.task_id) {
      const { data: t } = await admin.from('org_tasks').select('title,detail,objective_id').eq('id', body.task_id).maybeSingle();
      if (t) { title = title || t.title || ''; detail = detail || t.detail || ''; if (t.objective_id) { const { data: o } = await admin.from('org_objectives').select('objective').eq('id', t.objective_id).maybeSingle(); objectiveText = o?.objective || ''; } }
    }
    if (!title) title = 'Produce an analytics recommendation on current marketplace performance';

    // Pull the LIVE data (same RPCs the OS dashboards use).
    const [{ data: analytics }, { data: funnel }, { data: company }] = await Promise.all([
      admin.rpc('fn_query_platform', { p_topic: 'analytics', p_args: {} }),
      admin.rpc('fn_query_platform', { p_topic: 'funnel', p_args: { days: 30 } }),
      admin.rpc('fn_query_platform', { p_topic: 'company', p_args: {} }),
    ]);

    const sys = 'You are the head of Analytics & Intelligence at QuotesDone, a UAE B2B anonymous quotation marketplace. Turn the live data into a DECISION. Ground every claim in the numbers provided and cite the specific figure in-line. Produce a concrete, prioritized recommendation of at most 3-4 points; for each, name the metric that justifies it and the department that should own the action. Be honest about pre-launch / low-volume data — flag when a number is too small to act on rather than over-reading noise. Never invent numbers not present in the data. End with a single line "RESULT:" summarizing the top recommendation in one sentence.';
    const user = 'ANALYTICS TASK: ' + title + (detail ? ('\n' + detail) : '') + (objectiveText ? ('\nParent objective: ' + objectiveText) : '') +
      '\n\nLIVE MARKETPLACE ANALYTICS:\n' + JSON.stringify(analytics || {}) +
      '\n\nCONVERSION FUNNEL (30d):\n' + JSON.stringify(funnel || {}) +
      '\n\nCOMPANY SNAPSHOT:\n' + JSON.stringify(company || {}) +
      '\n\nWrite the data-grounded recommendation now.';
    const rec = (await llm(sys, user, 900) || '').trim();
    if (!rec || rec.length < 40) return J({ error: 'analytics_llm_unavailable' }, 502);

    const m = rec.match(/RESULT:\s*(.+)\s*$/i);
    const oneLine = (m ? m[1] : rec.slice(0, 180)).replace(/\s+/g, ' ').slice(0, 300);

    // Record as a shared organizational insight (reusable by every department). No side effects.
    try { await admin.from('org_memory').insert({ scope: 'analytics', kind: 'insight', content: (title + ' — ' + oneLine).slice(0, 500) + '\n\n' + rec.slice(0, 3000), source: 'analytics_recommend' }); } catch (_e) {}

    return J({ ok: true, note: 'Produced a data-grounded recommendation citing live funnel/marketplace metrics; recorded as a shared org insight. ' + oneLine, recommendation: rec.slice(0, 4000) });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
