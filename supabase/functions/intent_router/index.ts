// intent_router — the Chief of Staff's planning brain. Turns a founder OBJECTIVE (plain language)
// into a tracked plan: decomposes it into department-owned tasks, stamps each with the control tier
// the org's permission model allows (fn_dept_authority, with constitutional hard-caps), writes the
// objective + tasks to the ledger, and returns the plan. Departments then execute their tasks; the
// CoS tracks the objective to done. Auth: __secret (inbound) OR admin-email JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const llm = makeLlm(SONNET_FIRST, { max: 1400, temperature: 0 });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function authed(req: Request, body: any): Promise<boolean> {
  if (body?.__secret && (await requireInternal(admin, body.__secret, 'intent_router')).ok) return true;
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

    // status/read path: return an objective + its tasks
    if (body.action === 'status') {
      const id = Number(body.objective_id);
      const { data: obj } = await admin.from('org_objectives').select('*').eq('id', id).maybeSingle();
      if (!obj) return J({ error: 'not_found' }, 404);
      const { data: tasks } = await admin.from('org_tasks').select('id,dept_key,title,status,tier,needs_founder,updated_at').eq('objective_id', id).order('id');
      return J({ ok: true, objective: obj, tasks: tasks || [] });
    }

    const objective = String(body.objective || '').trim();
    if (!objective) return J({ error: 'objective required' }, 400);

    // Load the department roster + their authority classes so the planner routes correctly.
    const { data: depts } = await admin.from('org_departments').select('dept_key,name,charter,lead_agent').eq('active', true).order('sort');
    const { data: auth } = await admin.from('org_authority').select('dept_key,action_class,max_tier');
    const roster = (depts || []).filter((d: any) => d.dept_key !== 'exec')
      .map((d: any) => '- ' + d.dept_key + ' (' + d.name + '): ' + d.charter + '  [actions: ' + (auth || []).filter((a: any) => a.dept_key === d.dept_key).map((a: any) => a.action_class).join(', ') + ']').join('\n');

    const sys = 'You are the planning brain of the Chief of Staff at QuotesDone, an AI-native company run as DEPARTMENTS. Decompose the founder\'s objective into concrete tasks, each OWNED BY EXACTLY ONE department from the roster. For each task give: dept_key (exactly one roster key), title (short imperative), detail (what to do and why, 1-2 sentences), action_class (choose the closest of that department\'s listed actions; if none fits use a short verb_noun). Create only tasks that genuinely move the objective forward — usually 2 to 6. Never invent a department. Return STRICT minified JSON: {"summary":"...","tasks":[{"dept_key":"...","title":"...","detail":"...","action_class":"..."}]}.\n\nDEPARTMENT ROSTER:\n' + roster;
    const raw = await llm(sys, 'Founder objective: ' + objective + '\n\nReturn the JSON plan.');
    if (!raw) return J({ error: 'planner_unavailable' }, 502);
    let plan: any; try { plan = JSON.parse(raw.replace(/^```(json)?/i, '').replace(/```$/, '').trim()); } catch (_e) { const m = raw.match(/\{[\s\S]*\}/); plan = m ? JSON.parse(m[0]) : null; }
    if (!plan || !Array.isArray(plan.tasks)) return J({ error: 'plan_parse_failed', raw: raw.slice(0, 300) }, 502);

    const validKeys = new Set((depts || []).map((d: any) => d.dept_key));
    const { data: objRow } = await admin.from('org_objectives').insert({ objective, raw_input: String(body.raw || objective).slice(0, 4000), created_by: 'founder', status: 'in_progress' }).select('id').single();
    const objectiveId = objRow!.id;

    const out: any[] = [];
    for (const t of plan.tasks.slice(0, 8)) {
      const dept = String(t?.dept_key || '').trim();
      if (!validKeys.has(dept) || dept === 'exec') continue;
      const actionClass = String(t?.action_class || 'general').trim().slice(0, 60);
      // authority model decides the tier (with constitutional hard caps)
      const { data: authz } = await admin.rpc('fn_dept_authority', { p_dept: dept, p_action_class: actionClass });
      const tier = (authz?.tier as string) || 'gated';
      const needsFounder = tier === 'gated';
      const { data: taskRow } = await admin.from('org_tasks').insert({
        objective_id: objectiveId, dept_key: dept, title: String(t?.title || 'task').slice(0, 200),
        detail: String(t?.detail || '').slice(0, 1000), action_class: actionClass, tier, needs_founder: needsFounder,
        status: needsFounder ? 'proposed' : 'assigned'
      } as any).select('id').single();
      out.push({ id: taskRow?.id, dept, title: String(t?.title || '').slice(0, 200), action_class: actionClass, tier, needs_founder: needsFounder });
    }

    if (out.length === 0) { await admin.from('org_objectives').update({ status: 'blocked', outcome: 'No routable department tasks were produced.' }).eq('id', objectiveId); return J({ ok: true, objective_id: objectiveId, summary: plan.summary || '', tasks: [], note: 'no routable tasks' }); }
    return J({ ok: true, objective_id: objectiveId, summary: plan.summary || '', tasks: out,
      needs_founder: out.filter((t) => t.needs_founder).length, autonomous: out.filter((t) => !t.needs_founder).length });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
