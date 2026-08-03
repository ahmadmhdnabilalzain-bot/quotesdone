// dept_plan — THE DEPARTMENT OPERATING LOOP (self-planning half of the autonomy engine).
// On a cadence, each department acts as its own head: it reads the company vision + its charter +
// north star + its recent work AND whether it worked + its live numbers + what's already open, then
// GENERATES ITS OWN next objectives/tasks. The existing cos_execute engine carries them out; their
// outcomes feed the next cycle. No founder-fed tasks. This is what keeps the company growing unattended.
//
// Founder gates stay narrow: a task is only sent for founder approval (status='proposed') when it
// spends money or publishes public content; everything safe runs autonomously (status='assigned').
// Auth: __secret (cron / self fan-out) OR admin JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SELF = Deno.env.get('SUPABASE_URL')! + '/functions/v1/dept_plan';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const llm = makeLlm(SONNET_FIRST, { max: 1200, temperature: 0.35 });

// Work that runs WITHOUT the founder (safe, reversible, non-spending, non-publishing).
// Anything not in this set, or anything the department head marks needs_founder, waits for approval.
const AUTONOMOUS_SAFE = new Set(['content_draft', 'knowledge_fill', 'recommend', 'invite', 'analysis', 'research', 'seo', 'monitor', 'reconcile', 'outreach_draft']);
const OPEN_TASK_CAP = 5;     // don't let a department pile up unstarted work
const MAX_NEW = 3;           // per cycle

async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function authed(req: Request, body: any): Promise<boolean> {
  if ((await requireInternal(admin, body?.__secret, 'dept_plan')).ok) return true;
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return false;
  const { data: { user } } = await admin.auth.getUser(jwt);
  const allow = (await sec('admin_emails') || 'management@quotesdone.com').split(',').map((s) => s.trim().toLowerCase());
  return !!(user?.email && allow.includes(user.email.toLowerCase()));
}

async function planDept(deptKey: string) {
  const { data: d } = await admin.from('org_departments').select('dept_key,name,charter,north_star,health_fn,lead_agent,active').eq('dept_key', deptKey).maybeSingle();
  if (!d || !d.active) return { dept: deptKey, skipped: 'unknown or inactive' };

  // Guard: already enough open work → don't pile up.
  const { count: openCount } = await admin.from('org_tasks').select('id', { count: 'exact', head: true }).eq('dept_key', deptKey).in('status', ['assigned', 'proposed', 'in_progress']);
  if ((openCount || 0) >= OPEN_TASK_CAP) return { dept: deptKey, skipped: 'has ' + openCount + ' open tasks' };

  const { data: vis } = await admin.from('company_vision').select('vision,mission').eq('id', 1).maybeSingle();
  // Company-level strategic targets every department plans against (company_goals).
  // Distinct from org_objectives, which is this loop's own work-item table.
  const { data: goals } = await admin.from('company_goals')
    .select('goal,metric,target_value,unit,period,owner_dept')
    .eq('active', true).order('sort');
  const goalsTxt = (goals || []).map((g: any) =>
    '- ' + g.goal + ' (' + g.metric + (g.target_value != null ? ('; target ' + g.target_value + ' ' + (g.unit || '')) : '')
    + '; ' + (g.period || 'annual') + (g.owner_dept ? ('; owned by ' + g.owner_dept) : '') + ')'
  ).join('\n');
  // SENSE: recent work and whether it worked
  const { data: recent } = await admin.from('org_tasks').select('title,status,result,action_class,updated_at').eq('dept_key', deptKey).order('updated_at', { ascending: false }).limit(8);
  const { data: mem } = await admin.from('org_memory').select('kind,content,created_at').eq('scope', deptKey).order('created_at', { ascending: false }).limit(6);
  const { data: openItems } = await admin.from('org_tasks').select('title,status').eq('dept_key', deptKey).in('status', ['assigned', 'proposed', 'in_progress']).limit(10);
  // Live KPIs from the department's own health function, if it has one.
  let kpi = '';
  if (d.health_fn) { try { const { data: h } = await admin.rpc(d.health_fn); if (h) kpi = JSON.stringify(h).slice(0, 1200); } catch (_e) { /* health fn optional */ } }
  // Capabilities the department can actually execute.
  const { data: caps } = await admin.from('org_action_executor').select('action_class,note,advisory_safe').eq('department', deptKey).eq('active', true);
  const capList = (caps || []).map((c: any) => c.action_class + (c.note ? (' — ' + c.note) : '')).join('; ') || '(no wired executors yet — use action_class "analysis" to prepare a deliverable)';
  // The department head plans WITH its management discipline (_global) + its own domain expertise
  // (the lead agent's knowledge): reversibility, ruthless prioritization, and role-specific know-how.
  let expertise = '';
  try { const { data } = await admin.rpc('fn_agent_context', { p_agent_key: d.lead_agent || null, p_max_chars: 5000 }); expertise = data ? String(data).slice(0, 4500) : ''; } catch (_e) { /* optional */ }

  const recentTxt = (recent || []).map((r: any) => '- [' + r.status + '] ' + (r.title || '') + (r.result ? (' → ' + (typeof r.result === 'string' ? r.result : JSON.stringify(r.result)).slice(0, 200)) : '')).join('\n') || '(no recent work)';
  const memTxt = (mem || []).map((m: any) => '- ' + (m.content || '').slice(0, 200)).join('\n') || '(no notes)';
  const openTxt = (openItems || []).map((o: any) => '- [' + o.status + '] ' + o.title).join('\n') || '(none)';

  const sys = 'You are the HEAD of the ' + (d.name || deptKey) + ' department at QuotesDone, a UAE B2B anonymous quotation marketplace. '
    + 'Company vision: ' + (vis?.vision || 'Become the smartest marketplace engine in the world.') + ' '
    + (goalsTxt ? ('COMPANY GOALS every department is working toward — your plan must move at least one of these, and you must say which one and how:\n' + goalsTxt + '\n') : '')
    + 'Your charter: ' + (d.charter || '') + ' Your north-star metric: ' + (d.north_star || '') + '. '
    + 'You run a CONTINUOUS LOOP as an autonomous expert: review what you recently did and whether it worked, look at your live numbers, and decide the highest-leverage NEXT actions that move your north star toward the vision. You never wait for instructions. '
    + 'Propose only real, concrete, doable actions — no vague goals. For each, pick an action_class from YOUR CAPABILITIES: ' + capList + '. If none fits, use "analysis" to prepare a research/analysis deliverable. '
    + 'Set needs_founder=true ONLY when the action spends money or publishes public content; otherwise it runs autonomously. '
    + 'Do NOT duplicate anything already open. Return STRICT minified JSON only: {"plan_rationale":"<2-3 sentences: what you learned from recent outcomes and why these are the next best moves>","tasks":[{"title":"<short>","detail":"<exactly what to do and the outcome you expect>","action_class":"<one of the above>","needs_founder":false}]}. At most ' + MAX_NEW + ' tasks; fewer if that is genuinely the right call.'
    + (expertise ? ('\n\nHOW YOU THINK (management discipline + your domain expertise — plan by this):\n' + expertise) : '');
  const user = 'RECENT WORK & OUTCOMES:\n' + recentTxt + '\n\nLEARNED NOTES:\n' + memTxt + '\n\nLIVE NUMBERS:\n' + (kpi || '(no KPI feed)') + '\n\nALREADY OPEN (do not duplicate):\n' + openTxt + '\n\nDecide your next moves and return the JSON.';

  const raw = (await llm(sys, user, 1200) || '').trim();
  if (!raw) return { dept: deptKey, error: 'llm_unavailable' };
  let parsed: any = null;
  try { parsed = JSON.parse(raw.replace(/^```(json)?/i, '').replace(/```$/, '').trim()); } catch (_e) { const m = raw.match(/\{[\s\S]*\}/); if (m) { try { parsed = JSON.parse(m[0]); } catch (_e2) { /* noop */ } } }
  const tasks = Array.isArray(parsed?.tasks) ? parsed.tasks.slice(0, MAX_NEW) : [];
  if (!tasks.length) return { dept: deptKey, planned: 0, note: 'no new tasks proposed' };

  // One objective per planning cycle, owned by the department.
  const { data: obj } = await admin.from('org_objectives').insert({
    objective: (parsed?.plan_rationale || ('Self-directed plan for ' + (d.name || deptKey))).slice(0, 500),
    raw_input: 'dept_plan self-planning cycle', created_by: deptKey, status: 'active', priority: 3,
  }).select('id').maybeSingle();

  const rows = tasks.map((t: any) => {
    const ac = String(t?.action_class || 'analysis').toLowerCase().trim();
    const gated = t?.needs_founder === true || !AUTONOMOUS_SAFE.has(ac);
    return {
      objective_id: obj?.id || null, dept_key: deptKey,
      title: String(t?.title || 'Untitled').slice(0, 200), detail: String(t?.detail || '').slice(0, 2000),
      action_class: ac, status: gated ? 'proposed' : 'assigned',
      tier: gated ? 'gated' : 'autonomous', needs_founder: gated, decided_by: 'dept_plan',
    };
  });
  const { data: ins } = await admin.from('org_tasks').insert(rows).select('id,status');
  const assigned = (ins || []).filter((r: any) => r.status === 'assigned').length;
  const proposed = (ins || []).filter((r: any) => r.status === 'proposed').length;

  await admin.from('org_memory').insert({ scope: deptKey, kind: 'plan', content: 'Self-planned ' + rows.length + ' task(s) (' + assigned + ' autonomous, ' + proposed + ' for founder). Rationale: ' + String(parsed?.plan_rationale || '').slice(0, 400), source: 'dept_plan' });
  return { dept: deptKey, planned: rows.length, autonomous: assigned, needs_founder: proposed, rationale: String(parsed?.plan_rationale || '').slice(0, 240) };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await authed(req, body))) return J({ error: 'forbidden' }, 403);

    // Single department (real work).
    if (body.dept_key) return J({ ok: true, result: await planDept(String(body.dept_key)) });

    // Fan-out: trigger every active department's own planning invocation (fire-and-forget so no edge timeout).
    if (body.all) {
      const { data: depts } = await admin.from('org_departments').select('dept_key').eq('active', true);
      const secret = await sec('cred_fn_dept_plan');
      const keys = (depts || []).map((d: any) => d.dept_key);
      await Promise.all(keys.map((k: string) => fetch(SELF, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, dept_key: k }), signal: AbortSignal.timeout(2500) }).catch(() => {})));
      return J({ ok: true, fanned_out: keys.length, departments: keys });
    }
    return J({ error: 'provide dept_key or all:true' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
