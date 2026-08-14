// dept_plan — THE DEPARTMENT OPERATING LOOP (self-planning half of the autonomy engine).
// On a cadence, each department acts as its own head: it reads the company vision + its charter +
// north star + its recent work AND whether it worked + its live numbers + what's already open, then
// GENERATES ITS OWN next objectives/tasks. The existing cos_execute engine carries them out; their
// outcomes feed the next cycle. No founder-fed tasks. This is what keeps the company growing unattended.
//
// Founder gates are decided by the AUTHORITY MODEL (fn_dept_authority), not by this file: a task is
// created gated (status='proposed') whenever the model does not grant the owning department
// unsupervised power over that action class. Everything the model does clear runs (status='assigned').
// Auth: __secret (cron / self fan-out) OR admin JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SELF = Deno.env.get('SUPABASE_URL')! + '/functions/v1/dept_plan';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
// THE CEILING WAS 1200 AGAINST A POLICY OF 2000, AND IT WAS SET TWICE.
// ai_gateway computes min(body.max, route.max_tokens), so a caller ceiling can only ever LOWER
// model_policy.chief_of_staff_decision's 2000. Measured in production 6 Aug 2026: 40 of the 61
// dept_plan calls ever made returned output_tokens EXACTLY 1200. An output that lands precisely on
// the ceiling is truncation, not a coincidence — the JSON plan was cut mid-string, the function
// reported `output_did_not_parse` (§5's laundered string), and it fell through to the opus fallback
// at roughly twice the cost. legal and customer_success failed outright on 6 Aug at 01:00.
//
// It is set here and NOT at the call site, because llm(sys, input, max) takes a per-call third
// argument that overrides this one — dept_plan passed 1200 there too, so removing only this had no
// effect at all (measured: still exactly 1200). And `makeLlm`'s own fallback is `def.max ?? 700`,
// so deleting the ceiling outright makes it WORSE, not absent — llm.ts always sends a number.
//
// 8000 is DELIBERATELY ABOVE THE POLICY so that min(caller, policy) always yields the policy: this
// is "let the task class decide" expressed through a signature that will not accept undefined.
// model_policy.chief_of_staff_decision was raised 2000 -> 4000 on both projects at the same time,
// because the first fixed production run measured 1,725 output tokens — 86% of 2000, which is the
// same mid-distribution position that made license_extract (74-78%) worth fixing before it failed.
// THE WALL WAS 27 SECONDS AND THE WORK TAKES UP TO 44 (14 Aug 2026).
//
// No timeoutMs here meant makeLlm's 25s default. _shared/llm.ts declares client_timeout_ms as
// dTo + 5000 and ai_gateway sets its wall to declared - 3000, so this function ran against a
// 27,000 ms wall. Measured on production over 14 days, chief_of_staff_decision on sonnet-5:
//
//   ok=true   49 calls   9,329-43,732 ms   avg 6,986 in / 1,597 out tokens
//   ok=false  16 calls  27,036-55,052 ms   prompt_tokens 0, output_tokens 0, EVERY ONE
//
// Zero tokens in both directions on all sixteen: the model never produced anything. The minimum,
// 27,036 ms, is that 27-second wall to the millisecond. These are our own aborts, not the model
// answering badly — while legitimate successes run to 43.7s.
//
// IT WAS NOT A FREE FAILURE. fn_model_autoswitch read those sixteen as model failure, scored the
// class at 75.4% against its 85% floor, and promoted chief_of_staff_decision to opus-4.8 at 04:35
// on 14 Aug — roughly 2.3x the cost per call. Opus is SLOWER, so a timeout is answered by a model
// more likely to time out. 60s gives the 43.7s worst observed success comfortable room.
const llm = makeLlm(SONNET_FIRST, { max: 8000, temperature: 0.35, timeoutMs: 60000 });

// CEILING, NOT A GRANT. This set can only REFUSE autonomy; it can never confer it. The tier itself
// comes from fn_dept_authority (see planDept). Until 4 Aug 2026 this same set WAS the decision, and
// being department-blind it minted authority for 112 (department, action_class) pairs the model does
// not grant at all — see the block comment at the routing site. It is kept as an upper bound so that
// switching to the model could not, by itself, release the 14 pairs where the model grants MORE than
// this file used to. Removing it is a founder decision, not an edit.
const AUTONOMOUS_CEILING = new Set(['content_draft', 'knowledge_fill', 'recommend', 'invite', 'analysis', 'research', 'seo', 'monitor', 'reconcile', 'outreach_draft']);
// Mirrors public.fn_authority_rank exactly. Unknown ranks highest so that comparisons fail closed.
const TIER_RANK: Record<string, number> = { advisory: 0, gated: 1, supervised: 2, autonomous: 3 };
const rank = (t: string) => (t in TIER_RANK ? TIER_RANK[t] : 3);
const KNOWN_TIERS = new Set(['advisory', 'gated', 'supervised', 'autonomous']);
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
  // AUDIT (4 Aug 2026). This counted `proposed` too. `proposed` means "waiting on a founder
  // decision", and there is no approval path, so a proposed row can never clear. Counting it
  // turned a throughput guard into an off switch: eight of thirteen departments were permanently
  // barred from planning by a queue with no reader, and the count could only ever rise.
  // The cap now measures work that is actually MOVING. The founder backlog is still returned,
  // because it is a real number that ought to be falling — not one that should become invisible.
  const { count: openCount } = await admin.from('org_tasks').select('id', { count: 'exact', head: true }).eq('dept_key', deptKey).in('status', ['assigned', 'in_progress']);
  const { count: awaitingFounder } = await admin.from('org_tasks').select('id', { count: 'exact', head: true }).eq('dept_key', deptKey).eq('status', 'proposed');
  if ((openCount || 0) >= OPEN_TASK_CAP) return { dept: deptKey, skipped: 'has ' + openCount + ' open tasks', awaiting_founder: awaitingFounder || 0 };

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
  // THE DAILY PLANNER IS THE READER THAT MOST NEEDS ITS DEPARTMENT'S OWN RULES, and it was the one
  // that could not see them. fn_agent_context only emits LAYER 2b (dept_library) and LAYER 2c
  // (ops_knowledge — the department's SOPs, decision rules and exception playbooks) when the caller
  // supplies the question it is reasoning about; this passed none. And the 4,500-char slice cut the
  // context off inside layer 2 regardless, so even a query would have been thrown away.
  //
  // The query is the charter plus the north star plus what is actually open — which is precisely
  // what this function is about to plan against, so the retrieval is scoped to the real task rather
  // than to a keyword. The slice is raised to 11,000: measured 6 Aug 2026, the widest department
  // (legal) renders 34,191 chars with a query against 28,014 without, so 11,000 keeps identity,
  // layer 2 and the retrieved sections while still bounding what reaches the prompt.
  const planQuery = [d.charter, d.north_star, ...(openItems || []).map((o: any) => o.title)]
    .filter(Boolean).join(' ').slice(0, 600);
  try {
    const { data } = await admin.rpc('fn_agent_context', {
      p_agent_key: d.lead_agent || null, p_max_chars: 12000, p_query: planQuery,
    });
    expertise = data ? String(data).slice(0, 11000) : '';
  } catch (_e) { /* optional */ }

  const recentTxt = (recent || []).map((r: any) => '- [' + r.status + '] ' + (r.title || '') + (r.result ? (' → ' + (typeof r.result === 'string' ? r.result : JSON.stringify(r.result)).slice(0, 200)) : '')).join('\n') || '(no recent work)';
  const memTxt = (mem || []).map((m: any) => '- ' + (m.content || '').slice(0, 200)).join('\n') || '(no notes)';
  const openTxt = (openItems || []).map((o: any) => '- [' + o.status + '] ' + o.title).join('\n') || '(none)';

  const sys = 'You are the HEAD of the ' + (d.name || deptKey) + ' department at QuotesDone, a UAE B2B anonymous quotation marketplace. '
    + 'Company vision: ' + (vis?.vision || 'Become the smartest marketplace engine in the world.') + ' '
    + (goalsTxt ? ('COMPANY GOALS every department is working toward — your plan must move at least one of these, and you must say which one and how:\n' + goalsTxt + '\n') : '')
    + 'Your charter: ' + (d.charter || '') + ' Your north-star metric: ' + (d.north_star || '') + '. '
    + 'You run a CONTINUOUS LOOP as an autonomous expert: review what you recently did and whether it worked, look at your live numbers, and decide the highest-leverage NEXT actions that move your north star toward the vision. You never wait for instructions. '
    + 'Propose only real, concrete, doable actions — no vague goals. For each, pick an action_class from YOUR CAPABILITIES: ' + capList + '. If none fits, use "analysis" to prepare a research/analysis deliverable. '
    + 'Set needs_founder=true when the action spends money, publishes public content, or you judge it should not run unattended. '
    + 'needs_founder only TIGHTENS: the authority model decides what may run unattended, and it cannot be overridden from here. '
    + 'Do NOT duplicate anything already open. Return STRICT minified JSON only: {"plan_rationale":"<2-3 sentences: what you learned from recent outcomes and why these are the next best moves>","tasks":[{"title":"<short>","detail":"<exactly what to do and the outcome you expect>","action_class":"<one of the above>","needs_founder":false}]}. At most ' + MAX_NEW + ' tasks; fewer if that is genuinely the right call.'
    + (expertise ? ('\n\nHOW YOU THINK (management discipline + your domain expertise — plan by this):\n' + expertise) : '');
  const user = 'RECENT WORK & OUTCOMES:\n' + recentTxt + '\n\nLEARNED NOTES:\n' + memTxt + '\n\nLIVE NUMBERS:\n' + (kpi || '(no KPI feed)') + '\n\nALREADY OPEN (do not duplicate):\n' + openTxt + '\n\nDecide your next moves and return the JSON.';

  const raw = (await llm(sys, user) || '').trim();   // budget set once, on makeLlm above
  if (!raw) return { dept: deptKey, error: 'llm_unavailable' };
  let parsed: any = null;
  try { parsed = JSON.parse(raw.replace(/^```(json)?/i, '').replace(/```$/, '').trim()); } catch (_e) { const m = raw.match(/\{[\s\S]*\}/); if (m) { try { parsed = JSON.parse(m[0]); } catch (_e2) { /* noop */ } } }
  const tasks = Array.isArray(parsed?.tasks) ? parsed.tasks.slice(0, MAX_NEW) : [];
  if (!tasks.length) {
    // AUDIT (4 Aug 2026). Three different states used to return the same sentence, so a week of
    // "no new tasks proposed" was indistinguishable from a week of unparseable model output.
    // fn_edge_health_scan filed org_tasks#323 saying dept_plan had produced no effect, and the
    // note gave nobody a way to say why. A diagnosis you cannot make is a defect in the log.
    const why = parsed === null ? 'output_did_not_parse'
      : !Array.isArray((parsed as any)?.tasks) ? 'output_parsed_but_no_tasks_array'
      : 'proposed_nothing';
    if (why !== 'proposed_nothing') {
      try {
        await admin.from('agent_runs').insert({
          agent: 'dept_plan', status: 'error', started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
          counts: { signal: why, dept: deptKey, raw_len: raw.length },
          note: (deptKey + ': model output unusable (' + why + '). First 300 chars: ' + raw.slice(0, 300)).slice(0, 500),
        });
      } catch (_e) { /* never let the trail block planning */ }
    }
    return { dept: deptKey, planned: 0, reason: why, note: why === 'proposed_nothing' ? 'no new tasks proposed' : 'model output unusable: ' + why };
  }

  // One objective per planning cycle, owned by the department.
  const { data: obj } = await admin.from('org_objectives').insert({
    objective: (parsed?.plan_rationale || ('Self-directed plan for ' + (d.name || deptKey))).slice(0, 500),
    raw_input: 'dept_plan self-planning cycle', created_by: deptKey, status: 'active', priority: 3,
  }).select('id').maybeSingle();

  // AUDIT (4 Aug 2026). ROUTE ON THE AUTHORITY MODEL, NOT ON A CONSTANT IN THIS FILE.
  //
  // This block used to decide BOTH status and tier from AUTONOMOUS_SAFE — a hardcoded,
  // DEPARTMENT-BLIND set. Measured against fn_dept_authority across every active department and
  // every known action class, that constant granted tier='autonomous' to 112 (department,
  // action_class) pairs the model grants nothing for, and to one it grants only 'advisory'.
  // That is not theoretical: org_tasks#20, supplier_success/invite, was created 'autonomous' by
  // this path and executed on 25 Jul 2026, enqueueing 10 real supplier invites for a department
  // org_authority has no row for. It is the same defect audit 7.3 fixed in fn_event_dispatch and
  // cos_execute — "a permission carried in the payload is not a permission, it is a claim by the
  // caller" — and dept_plan was not included in that fix.
  //
  // The tier now comes from fn_dept_authority, the same source cos_execute re-checks against at
  // execution time, so the two can no longer disagree by construction.
  //
  // AUTONOMOUS_CEILING survives only as an UPPER BOUND. There are 14 pairs where the model grants
  // MORE than this file used to (e.g. procurement/supplier_approve_clean, sales/outreach_send).
  // Honouring those would be a real widening of what runs unattended, and that is a founder
  // decision — so the ceiling still clamps them to 'gated' and every clamp is recorded, making the
  // gap measurable instead of invisible. A restriction living in a file is safe; a grant is not.
  const rows: any[] = [];
  const clamped: string[] = [];
  const unknownClass: string[] = [];
  // The prompt tells the department head to pick an action_class from its OWN capabilities and to
  // fall back to 'analysis'. Nothing enforced it, so a hallucinated class went straight into
  // org_tasks.action_class and into the authority lookup. Classes the department cannot execute now
  // become the deliverable class the prompt already names.
  const ownClasses = new Set<string>((caps || []).map((c: any) => String(c.action_class)));
  for (const t of tasks) {
    let ac = String(t?.action_class || 'analysis').toLowerCase().trim();
    let detail = String(t?.detail || '').slice(0, 2000);
    if (ac !== 'analysis' && !ownClasses.has(ac)) {
      unknownClass.push(ac);
      // Keep the original ask ON THE ROW, not only in the run log. The row is what a human reads.
      detail = (detail + '\n\n[dept_plan: requested action_class "' + ac.slice(0, 60) + '" is not executable by '
        + deptKey + '; routed to analysis so it produces a deliverable instead of a row nothing can action.]').slice(0, 2000);
      ac = 'analysis';
    }
    let granted = 'gated';
    try {
      const { data: auth } = await admin.rpc('fn_dept_authority', { p_dept: deptKey, p_action_class: ac });
      const tv = String((auth as any)?.tier || '');
      granted = KNOWN_TIERS.has(tv) ? tv : 'gated';   // unreadable / unknown tier → gated, fail closed
    } catch (_e) { granted = 'gated'; }               // model unreachable → gated, fail closed
    const ceiling = AUTONOMOUS_CEILING.has(ac) ? 'autonomous' : 'gated';
    let tier = rank(granted) > rank(ceiling) ? ceiling : granted;
    if (tier !== granted) clamped.push(deptKey + '/' + ac + ' ' + granted + '→' + tier);
    // The department head may only TIGHTEN its own routing, never loosen it.
    if (t?.needs_founder === true && rank(tier) > rank('gated')) tier = 'gated';
    rows.push({
      objective_id: obj?.id || null, dept_key: deptKey,
      title: String(t?.title || 'Untitled').slice(0, 200), detail,
      action_class: ac, status: tier === 'gated' ? 'proposed' : 'assigned',
      tier, needs_founder: tier === 'gated', decided_by: 'dept_plan',
    });
  }
  if (clamped.length || unknownClass.length) {
    try {
      await admin.from('agent_runs').insert({
        agent: 'dept_plan', status: 'ok', started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
        counts: { signal: 'routing_clamped', dept: deptKey, clamped: clamped.length, unknown_class: unknownClass.length },
        note: ((clamped.length ? ('authority model grants more than AUTONOMOUS_CEILING allows: ' + clamped.join('; ')) : '')
          + (unknownClass.length ? ((clamped.length ? ' | ' : '') + 'action_class not executable by ' + deptKey
             + ', routed to analysis: ' + unknownClass.join(', ')) : '')).slice(0, 500),
      });
    } catch (_e) { /* never let the trail block planning */ }
  }
  const { data: ins } = await admin.from('org_tasks').insert(rows).select('id,status');
  const assigned = (ins || []).filter((r: any) => r.status === 'assigned').length;
  const proposed = (ins || []).filter((r: any) => r.status === 'proposed').length;

  await admin.from('org_memory').insert({ scope: deptKey, kind: 'plan', content: 'Self-planned ' + rows.length + ' task(s) (' + assigned + ' cleared by the authority model, ' + proposed + ' for founder). Rationale: ' + String(parsed?.plan_rationale || '').slice(0, 400), source: 'dept_plan' });
  return { dept: deptKey, planned: rows.length, assigned, needs_founder: proposed, tiers: rows.map((r: any) => r.action_class + ':' + r.tier), clamped, unknown_class: unknownClass, rationale: String(parsed?.plan_rationale || '').slice(0, 240) };
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

      // A RUN ROW ON EVERY FAN-OUT, INCLUDING THE ONE WHERE NOBODY PLANS.
      //
      // planDept writes to agent_runs only when it actually plans, and it returns early for any
      // department already holding OPEN_TASK_CAP open tasks. Measured on production 14 Aug 2026:
      // nine of the ten departments hold 18 to 115 open tasks, so the daily cron fires, every
      // department is skipped, and NOTHING is written. dept_plan then shows 7 runs across 3 active
      // days in 30 — and fn_runner_silence_watch, which re-derives cadence from agent_runs,
      // classifies it as on-demand and never alerts. A watcher that learns "is this running?" from
      // rows the runner only writes on success cannot ever see it stop.
      //
      // The skip picture is computed here rather than collected from the children, because the
      // fan-out is fire-and-forget with a 2.5s abort and has no results to collect.
      const skipped: string[] = []; const eligible: string[] = [];
      for (const k of keys) {
        const { count } = await admin.from('org_tasks').select('id', { count: 'exact', head: true })
          .eq('dept_key', k).in('status', ['assigned', 'in_progress']);
        ((count || 0) >= OPEN_TASK_CAP ? skipped : eligible).push(k + ':' + (count || 0));
      }
      await admin.from('agent_runs').insert({
        agent: 'dept_plan', started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
        status: eligible.length ? 'ok' : 'skipped',
        counts: { departments: keys.length, eligible: eligible.length, skipped: skipped.length, cap: OPEN_TASK_CAP },
        note: eligible.length
          ? `Fanned out to ${keys.length} department(s); ${eligible.length} under the ${OPEN_TASK_CAP}-open-task cap and planning (${eligible.join(', ')}); ${skipped.length} skipped for carrying unstarted work (${skipped.join(', ')}).`
          : `Fanned out to ${keys.length} department(s) and NONE planned: every one holds at least ${OPEN_TASK_CAP} open tasks (${skipped.join(', ')}). The company's planning loop is stopped until that backlog is owned or closed — this row exists so that is visible rather than silent.`,
      });
      return J({ ok: true, fanned_out: keys.length, departments: keys, eligible, skipped });
    }
    return J({ error: 'provide dept_key or all:true' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
