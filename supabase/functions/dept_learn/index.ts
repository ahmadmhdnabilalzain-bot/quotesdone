// dept_learn — THE LEARN STEP of the department loop (makes experience compound).
// After work runs, each department reflects on recently completed tasks + their outcomes + its live
// numbers, and extracts at most 2 DURABLE, reusable lessons (what worked, what failed, a pattern).
// Lessons are written to BOTH stores the org already reads: org_memory (scope=dept → the self-planner
// dept_plan reads it next cycle) and agent_memory (the lead agent → agent_brain reads it in chat).
// So the department is measurably smarter each cycle. Runs on a cadence just BEFORE dept_plan.
// Auth: __secret (cron / self fan-out) OR admin JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SELF = Deno.env.get('SUPABASE_URL')! + '/functions/v1/dept_learn';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const llm = makeLlm(SONNET_FIRST, { max: 700, temperature: 0.3 });

async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function authed(req: Request, body: any): Promise<boolean> {
  if ((await requireInternal(admin, body?.__secret, 'dept_learn')).ok) return true;
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return false;
  const { data: { user } } = await admin.auth.getUser(jwt);
  const allow = (await sec('admin_emails') || 'management@quotesdone.com').split(',').map((s) => s.trim().toLowerCase());
  return !!(user?.email && allow.includes(user.email.toLowerCase()));
}

async function learnDept(deptKey: string) {
  const { data: d } = await admin.from('org_departments').select('dept_key,name,north_star,lead_agent,active').eq('dept_key', deptKey).maybeSingle();
  if (!d || !d.active) return { dept: deptKey, skipped: 'unknown/inactive' };

  // Look at recently completed / failed work (last ~26h so a daily run covers one cycle, no double-counting).
  const since = new Date(Date.now() - 26 * 3600 * 1000).toISOString();
  const { data: done } = await admin.from('org_tasks').select('title,status,result,action_class,updated_at')
    .eq('dept_key', deptKey).in('status', ['done', 'failed', 'review_pending', 'escalated']).gte('updated_at', since).order('updated_at', { ascending: false }).limit(12);
  if (!done || !done.length) return { dept: deptKey, learned: 0, note: 'no completed work in window' };

  const { data: existing } = await admin.from('org_memory').select('content').eq('scope', deptKey).eq('kind', 'lesson').order('created_at', { ascending: false }).limit(20);
  const known = (existing || []).map((m: any) => '- ' + m.content).join('\n') || '(none yet)';
  const outcomes = done.map((t: any) => '- [' + t.status + '] ' + (t.title || '') + (t.result ? (' → ' + (typeof t.result === 'string' ? t.result : JSON.stringify(t.result)).slice(0, 260)) : '')).join('\n');

  const sys = 'You are the head of the ' + (d.name || deptKey) + ' department at QuotesDone (UAE B2B anonymous quotation marketplace). Your north star: ' + (d.north_star || '') + '. '
    + 'From the recently completed/failed work below, extract AT MOST 2 DURABLE, reusable lessons that will make this department better over time — what worked and should be repeated, what failed and should be avoided, or a pattern worth remembering. '
    + 'Only genuinely NEW lessons not already covered by EXISTING LESSONS. Each lesson must be a self-contained, actionable sentence (max 220 chars), not a one-off fact or a restatement of a task. If there is nothing durable to learn, return an empty list. '
    + 'Return STRICT minified JSON only: {"lessons":[{"lesson":"...","kind":"win|mistake|insight"}]}.';
  const user = 'EXISTING LESSONS:\n' + known + '\n\nRECENT WORK & OUTCOMES:\n' + outcomes + '\n\nExtract the new durable lessons and return the JSON.';

  const raw = (await llm(sys, user, 700) || '').trim();
  if (!raw) return { dept: deptKey, learned: 0, error: 'llm_unavailable' };
  let parsed: any = null;
  try { parsed = JSON.parse(raw.replace(/^```(json)?/i, '').replace(/```$/, '').trim()); } catch (_e) { const m = raw.match(/\{[\s\S]*\}/); if (m) { try { parsed = JSON.parse(m[0]); } catch (_e2) { /* noop */ } } }
  const lessons = Array.isArray(parsed?.lessons) ? parsed.lessons.slice(0, 2) : [];
  if (!lessons.length) return { dept: deptKey, learned: 0, note: 'nothing durable to learn' };

  let written = 0;
  for (const l of lessons) {
    const text = String(l?.lesson || '').trim(); if (text.length < 12) continue;
    const kind = ['win', 'mistake', 'insight'].includes(String(l?.kind)) ? String(l.kind) : 'insight';
    const tagged = '[' + kind + '] ' + text;
    await admin.from('org_memory').insert({ scope: deptKey, kind: 'lesson', content: tagged.slice(0, 400), source: 'dept_learn' });
    if (d.lead_agent) await admin.from('agent_memory').insert({ agent_key: d.lead_agent, kind: 'learned', content: tagged.slice(0, 360), source: 'dept_learn' });
    written++;
  }
  return { dept: deptKey, learned: written, from_tasks: done.length };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await authed(req, body))) return J({ error: 'forbidden' }, 403);
    if (body.dept_key) return J({ ok: true, result: await learnDept(String(body.dept_key)) });
    if (body.all) {
      const { data: depts } = await admin.from('org_departments').select('dept_key').eq('active', true);
      const secret = await sec('cred_fn_dept_learn');
      const keys = (depts || []).map((d: any) => d.dept_key);
      await Promise.all(keys.map((k: string) => fetch(SELF, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, dept_key: k }), signal: AbortSignal.timeout(2500) }).catch(() => {})));
      // dept_learn has written ZERO agent_runs rows in 30 days, so fn_runner_silence_watch cannot
      // watch it at all: it re-derives cadence from agent_runs, and a runner with no rows is not
      // among the 139 it knows about. The daily cron has fired every day regardless. One row per
      // fan-out makes the learning loop observable.
      await admin.from('agent_runs').insert({
        agent: 'dept_learn', started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
        status: 'ok', counts: { departments: keys.length },
        note: `Fanned out the daily learning pass to ${keys.length} active department(s): ${keys.join(', ')}.`,
      });
      return J({ ok: true, fanned_out: keys.length });
    }
    return J({ error: 'provide dept_key or all:true' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
