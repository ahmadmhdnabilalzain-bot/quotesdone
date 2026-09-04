// cos_execute (v4) — the Chief of Staff's EXECUTION ENGINE. Runs hourly. Turns the objective/task
// ledger from a plan into work actually getting done. For each ready task:
//   - if its action_class is wired to a real executor REGISTERED TO ITS OWN DEPARTMENT
//     (org_action_executor, keyed on action_class AND department), it RUNS that executor (real side
//     effect, within the executor's own guards) and records mode:'executed';
//   - otherwise it dispatches to the owning department's specialist (agent_brain), which reasons +
//     produces the deliverable within its delegated authority (mode:'prepared'/'delivered').
// Either way it records to the ledger + organizational memory, advances the task by its authority tier,
// and rolls each objective up to done.
//
// EVERY DELIVERABLE IS REVIEWED BEFORE IT COUNTS AS DONE (6 Aug 2026). fn_task_review runs the
// department head (fn_pick_reviewer, honouring delegation_rule and seniority), then the Chief of
// Staff, against the org_task quality standard, then the cross-department challenge from
// collaboration_rule. A rejection returns the task for revision with its reason; the attempt
// counter below is the loop guard. Before this, the entire gate was `deliverable.length > 60`.
//
// SAFETY (Tier-0 discipline, permanent gates) — the tier IS the gate:
//   - Only works tasks the permission model already cleared: status='assigned' (advisory/supervised/
//     autonomous), plus stale 'in_progress' reclaimed from a killed run. GATED tasks are status='proposed'
//     and are NEVER touched here — they wait for the founder. fn_dept_authority already forced every
//     money/auth/security/destructive/legal-judgment class to 'gated', so nothing dangerous can be 'assigned'.
//   - agent_brain is advisory: it prepares work and hands off; it never moves money, approves suppliers,
//     publishes, or sends. So those side effects cannot happen here even in principle.
//   - supervised tasks complete but are flagged review_pending (the founder audits them in the daily brief).
//   - FREEZE SWITCH: app_secrets.cos_frozen='true' (or ai_kill_switch='true') halts everything instantly.
// Auth: __secret (cron) OR admin-email JWT (founder "run now").
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
// 29 Jul 2026: this waited 25s (makeLlm's default) while ai_gateway allows a two-model ladder up to
// 55s. Six analyses today finished at 50-60s, were billed, and were thrown away by this caller,
// then escalated to the founder as empty. This function's own budget is 110s, so waiting is free.
// THE SEVENTH TOKEN CEILING, AND IT WAS TOTAL. Measured on production 6 Aug 2026: of the 45
// cos_execute model calls ever made, **45 returned output_tokens EXACTLY 1200** — min 1200, max
// 1200, mean 1200. Not a distribution with a tail on the ceiling: every single deliverable this
// company has produced through the Chief of Staff was cut off mid-sentence. It shows up in the
// stored work — "…**Closing this item** with reason: *New standalone incident — `day_conduct" —
// and it is why 61 of 95 completed deliverables carry no RESULT: line: the line the work order
// asks for is the LAST thing written, so truncation removes it first.
//
// The ceiling was set TWICE, the documented shape: makeLlm({max:500}) here AND llm(sys,user,1200)
// at the dispatch call site, whose per-call third argument overrides this one. Raising only one
// changes nothing. Deleting it outright is worse — llm.ts falls back to `def.max ?? 700` and always
// sends a number — so both are set DELIBERATELY ABOVE model_policy.agent_reasoning so that
// ai_gateway's min(caller, policy) always yields the policy. Same fix as dept_plan's 1200.
//
// This SAVES money. A truncated deliverable now fails the review and is retried up to three times,
// so the old ceiling bought a cut-off answer and then paid for it twice more.
//
// AND THE STORAGE SLICE IS A CEILING TOO. `result.deliverable` was cut at 6,000 characters, which
// is roughly 1,500 tokens — under the old ceiling, so it never bit, and it would have become the
// next one the moment the model ceiling was lifted. Raised to 20,000 in the same change; jsonb has
// no width limit, so the only reason for a bound here is sanity, not schema.
const llm = makeLlm(SONNET_FIRST, { max: 8000, temperature: 0.2, timeoutMs: 75000 });

// A department that cannot reach its specialist returns a courteous sentence, not a deliverable.
// Those sentences are 60-90 characters, which sailed past a bare length check and marked the task
// DONE with an apology stored as the work product. A false success is worse than an escalation:
// an escalation gets looked at, a false success never does.
const NOT_WORK = /(could not reach|couldn't reach|unable to reach|not reachable|ai_unreachable|ai (service|is) (unavailable|unreachable)|try again in a moment|no ai key|ai not reachable|service unavailable)/i;
const MAX_TASKS = 2;            // per run; hourly cadence drains the rest (bounded runtime)
                                // 29 Jul 2026: 3 -> 2. A department-brain call can now take up to
                                // 75s and TIME_BUDGET_MS is 110s, so three per run could not fit and
                                // the third was always abandoned mid-flight.
const MAX_ATTEMPTS = 3;        // no deliverable after this many hourly tries → escalate to founder
const TIME_BUDGET_MS = 110000; // stop starting new specialist calls before the edge wall limit
const STALE_MIN = 15;          // reclaim an in_progress task a prior (possibly killed) run left behind

const nowIso = () => new Date().toISOString();
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function authed(req: Request, body: any): Promise<boolean> {
  if ((await requireInternal(admin, body?.__secret, 'cos_execute')).ok) return true;
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return false;
  const { data: { user } } = await admin.auth.getUser(jwt);
  const allow = (await sec('admin_emails') || 'management@quotesdone.com').split(',').map((s) => s.trim().toLowerCase());
  return !!(user?.email && allow.includes(user.email.toLowerCase()));
}

// 29 Jul 2026: this was a hardcoded list of 12 brain keys. Evolution (cpo), Intelligence
// (intel_director) and Knowledge Engineering (knowledge_director) were added later, were not in it,
// and so never reached their own specialist - every task they were given fell through to a generic
// stand-in. A department's brain is now validated against the real agent registry (org_agents), so
// adding a department can no longer silently disable its specialist. Cached per request; a failed
// lookup falls back to the original twelve rather than blocking all dispatch.
const LEGACY_BRAINS = ['legal', 'collections', 'cfo', 'bookkeeper', 'security', 'it', 'onboarding', 'docs', 'followup', 'bd', 'marketing', 'brief'];
let _brains: Set<string> | null = null;
async function validBrains(): Promise<Set<string>> {
  if (_brains) return _brains;
  try {
    const { data } = await admin.from('org_agents').select('agent_key');
    const keys = (data || []).map((r: any) => String(r.agent_key)).filter(Boolean);
    _brains = new Set(keys.length ? keys : LEGACY_BRAINS);
  } catch (_e) { _brains = new Set(LEGACY_BRAINS); }
  return _brains;
}
// WHO IN THE DEPARTMENT ACTUALLY DOES IT (11 Aug 2026).
// Every task went to `dept.brain_agent || dept.lead_agent` — ONE agent per department. Measured on
// production the same day: of 93 active employees, 64 had never appeared in agent_runs, agent_chats,
// agent_actions, decision_log or agent_memory at all. They were not idle; they were unreachable.
// The spec is explicit that a department is a TEAM and that specialists perform while managers
// review, and an org chart whose staff cannot be given work is an org chart, not a company.
//
// employee_authority already holds 285 per-employee (agent_key, action_class, max_tier) grants
// across 67 employees and had no reader on this path. It IS the answer to "who in this department
// is allowed to do this?", so the work order goes to the person the authority model already names.
//
// Ordering: the highest tier for that class first, then the LEAST senior person who holds it —
// specialists do the work, managers review it. The department's brain remains the fallback, so a
// class nobody personally holds behaves exactly as it did before.
async function assignee(deptKey: string, actionClass: string, fallback: string): Promise<string> {
  if (!actionClass) return fallback;
  try {
    const { data } = await admin.from('employee_authority')
      .select('agent_key,max_tier,org_agents!inner(agent_key,department,active,seniority)')
      .eq('action_class', actionClass)
      .eq('org_agents.department', deptKey)
      .eq('org_agents.active', true);
    const RANK: Record<string, number> = { advisory: 0, gated: 1, supervised: 2, autonomous: 3 };
    const SEN: Record<string, number> = { specialist: 0, senior: 1, lead: 2, manager: 3, director: 4, chief: 5, executive: 6 };
    const rows = (data || []) as any[];
    if (!rows.length) return fallback;
    rows.sort((a, b) =>
      (RANK[b.max_tier] ?? 0) - (RANK[a.max_tier] ?? 0) ||
      (SEN[a.org_agents?.seniority] ?? 9) - (SEN[b.org_agents?.seniority] ?? 9) ||
      String(a.agent_key).localeCompare(String(b.agent_key)));
    const pick = String(rows[0].agent_key || '');
    return (pick && (await validBrains()).has(pick)) ? pick : fallback;
  } catch (_e) { return fallback; }   // routing is an improvement; it must never block dispatch
}

// A deliverable-complete class is one where the work product IS the completion (advice/analysis/plan/
// draft/knowledge). Others are 'prepared' — the department's own autonomous machinery (invite ramp,
// kb autofill, approval lane, etc.) performs the real side effect on its schedule.
const DELIVERED_CLASSES = /recommend|review|analy|forecast|report|research|draft|knowledge|plan|strategy|audit|assess/i;

// Ask the owning department's specialist to produce the ACTUAL deliverable for this task.
// Returns the deliverable AND whether the paid model produced it: the org_task result carries used_llm so
// the employee_task run that mirrors this task (fn_workflow_run_follow_task) can say how it was worked.
async function dispatch(deptName: string, brainKey: string, objective: string, t: any): Promise<{ text: string; usedLlm: boolean }> {
  const instruction =
    'DEPARTMENT WORK ORDER from the Chief of Staff.\n' +
    'Company objective: ' + objective + '\n' +
    'Your department: ' + deptName + '\n' +
    'Task: ' + t.title + '\n' +
    'Detail: ' + (t.detail || '') + '\n' +
    'Action class: ' + t.action_class + '  |  Authority tier: ' + t.tier + '\n\n' +
    'Do the work now, to the fullest extent of your authority and knowledge. Produce the ACTUAL deliverable ' +
    '(the real draft / analysis / recommendation / plan / checklist / findings), not a description of what you would do. ' +
    'Be concrete and specific to QuotesDone and the UAE market. End with a one-line "RESULT:" summarising what you produced.';

  // DETERMINISTIC-FIRST (founder doctrine: internal work is ~95% code + knowledge, no model). Produce
  // the deliverable by APPLYING the nearest company playbook/rule to the task BY MEANING — no model
  // call. Only a task with no confident match falls through to the specialist model path below.
  try {
    // deno-lint-ignore no-explicit-any
    const emb = await (new (globalThis as any).Supabase.ai.Session('gte-small'))
      .run(((t.title || '') + ' — ' + (t.detail || '')).slice(0, 1200), { mean_pool: true, normalize: true }) as number[];
    // Cosine alone cannot tell a determination from noise (random in-scope pairs: median 0.837, measured
    // 4 Sep 2026), so fn_apply_playbook also demands keyword corroboration from the task's own text and an
    // ACTIONABLE record kind. See scripts/sql/apply_playbook_needs_corroboration.sql.
    const { data: det } = await admin.rpc('fn_apply_playbook',
      { p_agent_key: brainKey || deptName, p_query_embedding: '[' + emb.join(',') + ']',
        p_query_text: String(t.title || '') + ' ' + String(t.detail || '').slice(0, 800),
        p_min_similarity: 0.85, p_k: 20 });
    // deno-lint-ignore no-explicit-any
    const d = det as any;
    if (d && d.matched === true && typeof d.determination === 'string' && d.determination.length > 60) {
      return { text: String(d.determination) + '\nRESULT: ' + String(d.outcome || d.title || 'applied the company playbook').slice(0, 280), usedLlm: false };
    }
  } catch (_e) { /* deterministic path optional; fall through to the specialist model */ }

  if (brainKey && (await validBrains()).has(brainKey)) {
    try {
      // 29 Jul 2026: was 50000, which was 5s TIGHTER than ai_gateway's own 55s budget - so this
      // caller walked away while the model was still generating and still being billed, and the
      // task recorded "could not reach the AI service". The inner call must outlast the layer it
      // depends on, never the reverse.
      const r = await fetch(FN + '/agent_brain', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: await sec('cred_fn_cos_execute'), agent: brainKey, message: instruction }), signal: AbortSignal.timeout(75000) });
      const j = await r.json().catch(() => ({} as any));
      // agent_brain answers the held model with a courteous apology, not with model output: that is
      // NOT_WORK, and it is not a model call either.
      if (j?.reply && String(j.reply).length > 40) return { text: String(j.reply), usedLlm: j?.used_llm !== false && !NOT_WORK.test(String(j.reply).slice(0, 400)) };
    } catch (_e) { /* fall through to generic */ }
  }
  // Generic department-head fallback (analytics, procurement, or brain unreachable).
  // 8000 is above model_policy.agent_reasoning on purpose — see the ceiling note on `llm` above.
  // This is "let the task class decide", expressed through a signature that will not accept undefined.
  const out = await llm('You are the head of the ' + deptName + ' department at QuotesDone, a UAE B2B anonymous quotation marketplace. You are a seasoned professional. Produce concrete, practical deliverables. Never invent numbers.', instruction, 8000);
  return { text: out || '', usedLlm: !!out };
}
function resultLine(deliverable: string): string {
  const m = deliverable.match(/RESULT:\s*(.+)\s*$/i);
  return (m ? m[1] : deliverable.slice(0, 160)).replace(/\s+/g, ' ').slice(0, 300);
}

Deno.serve(async (req) => {
  const started = Date.now();
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await authed(req, body))) return J({ error: 'forbidden' }, 403);

    // FREEZE / kill switch — halt instantly.
    if ((await sec('cos_frozen')) === 'true' || (await sec('ai_kill_switch')) === 'true') return J({ ok: true, frozen: true, note: 'CoS execution is frozen; no tasks worked.' });

    // SIXTY PERCENT OF THE BILL WAS THE COMPANY THINKING ABOUT ITSELF (12 Aug 2026).
    //
    // Measured on production: 290 of the 316 agent_brain Anthropic calls in seven days fire at
    // minute 50-51 — this cron — for 71.27 of 77.02 AED. On 6 August a queue of self-analysis tasks
    // appeared (346 of the 385 open tasks are action_class='analysis') and the daily AI bill went
    // from ~1 AED to 11-15 AED and has stayed there every day since, on days with a session and days
    // without. Demand on the same date: 0 customers, 0 inquiries, 0 quotes, 0 transactions.
    //
    // The gate is on the WORK, not on the model. Revenue-path tasks are never capped. Self-analysis
    // gets decision_policy.cos_reflection_tasks_per_day. It opens by itself: the gate asks whether
    // THIS task is on the revenue path, never whether the company is busy yet, so the first inquiry
    // that arrives is worked uncapped without anyone changing a setting.
    //
    // A failure to read the gate does NOT halt the loop — this is a cost control, not a safety gate,
    // and the safety gates are the freeze switch above and the authority tier below. Failing open
    // costs money; failing closed would stop the company on a transient PostgREST error.
    let gate: any = {};
    try {
      const { data: g } = await admin.rpc('fn_cos_work_gate');
      gate = (g || {}) as any;
    } catch (_e) { gate = {}; }
    if (gate.gated === true) return J({ ok: true, gated: true, gate, worked: 0, note: gate.reason });

    const { data: depts } = await admin.from('org_departments').select('dept_key,name,brain_agent,lead_agent');
    const deptMap = new Map((depts || []).map((d: any) => [d.dept_key, d]));
    // Action-executor registry: action_classes wired to a REAL side-effect executor.
    //
    // AUDIT (4 Aug 2026). KEYED ON (action_class, department), NOT action_class ALONE.
    // org_action_executor carries a `department` column and every active row sets it, but the lookup
    // ignored it, so one department's task ran another department's executor. org_tasks#20
    // (supplier_success/invite) did exactly that on 25 Jul 2026 and enqueued 10 real supplier invites
    // through procurement's fn_org_exec_invite — for a department org_authority has no row for.
    // A declared constraint that is not enforced is worse than no constraint. A task whose owning
    // department does not own the executor now falls through to the advisory deliverable path, which
    // prepares work and moves nothing.
    const { data: execs } = await admin.from('org_action_executor').select('action_class,department,kind,target,params,active,advisory_safe').eq('active', true);
    // '::' cannot occur in an action_class or a dept_key, so the composite key cannot collide.
    const execKey = (ac: string, dept: string) => String(ac || '') + '::' + String(dept || '');
    const execMap = new Map((execs || []).map((e: any) => [execKey(e.action_class, e.department), e]));
    // Same registry keyed by class alone — used ONLY to name the refusal, never to run anything.
    const execAnyDept = new Map((execs || []).map((e: any) => [e.action_class, e]));

    // Ready set: freshly assigned + any in_progress a prior run may have left orphaned (stale).
    //
    // ONE RESERVED SLOT SO NEITHER QUEUE CLASS CAN BE LOCKED OUT (6 Aug 2026).
    // THIS IS A FAIRNESS FIX FOR A STARVED QUEUE CLASS. It is NOT an attempt to move
    // contract-consolidation: it closes no delivery, writes no result, invents nothing, and the
    // ratio that check measures may still not reach 50%. All it changes is that a whole class of
    // work stops waiting behind a queue it can never reach.
    //
    // MEASURED ON PRODUCTION, 6 Aug 2026 15:00 UTC: 499 tasks sat in 'assigned'. 94 of them were
    // queued by approval_path/dept_plan and sat AHEAD of the oldest event-derived task (#382),
    // with 394 more event-derived tasks behind it. `order by id limit 2` at one run an hour would
    // not have LOOKED at event-derived work for ~47 hours, and the bus adds more every 15 minutes.
    // Structural starvation of a class is a scheduling defect on its own merits.
    //
    // AND IT DOES NOT MIRROR THE DEFECT. Letting event-derived work always win starves the other
    // side by exactly the same mechanism. Slot 1 stays pure FIFO by id, unchanged. Only the LAST
    // slot is reallocated, only when the FIFO head is entirely ONE class, and only to the OLDEST
    // task of whichever class is missing — so whichever class owns the head of the queue, the
    // other one still gets a slot. With MAX_TASKS=2 that is one each whenever both have work.
    //
    // The class marker is decided_by, i.e. who QUEUED the row. fn_event_dispatch stamps the rows
    // the event bus raises (395 of the 499 pending) and this function overwrites it with 'cos' only
    // once the task is finished, so on pending work it is exactly a provenance flag. Written as
    // is-null OR neq so a row with no writer counts as the non-bus class rather than vanishing.
    const BUS = 'fn_event_dispatch';
    const TASK_COLS = 'id,objective_id,dept_key,title,detail,action_class,tier,attempts,status,decided_by';
    const staleCut = new Date(Date.now() - STALE_MIN * 60000).toISOString();
    // REVENUE-PATH WORK FIRST, AND UNCAPPED. This was one `order by id limit 2` over the whole
    // assigned queue, which is FIFO across 346 self-analysis rows and 2 invites — so a task on the
    // revenue path queued today would not be LOOKED at for a week, by exactly the structural
    // starvation the fairness block below already fixed once for the event bus. Taking demand first
    // costs nothing when there is none (the list is empty and this select is skipped) and is the
    // only reason the ceiling below is safe to impose.
    const demandClasses: string[] = Array.isArray(gate.demand_classes) ? gate.demand_classes : [];
    let batch: any[] = [];
    if (demandClasses.length) {
      const { data: dem } = await admin.from('org_tasks').select(TASK_COLS)
        .eq('status', 'assigned').in('action_class', demandClasses).order('id').limit(MAX_TASKS);
      batch = dem || [];
    }
    // Reflection fills what the revenue path left, and only while today's ceiling holds.
    const reflectionSlots = gate.reflection_allowed === false ? 0 : MAX_TASKS - batch.length;
    const { data: assigned } = reflectionSlots > 0
      ? await admin.from('org_tasks').select(TASK_COLS).eq('status', 'assigned').order('id').limit(reflectionSlots)
      : { data: [] as any[] };
    for (const x of (assigned || [])) if (!batch.some((b: any) => b.id === x.id)) batch.push(x);
    if (batch.length === MAX_TASKS) {
      const busInHead = batch.some((x: any) => x.decided_by === BUS);
      if (busInHead !== batch.some((x: any) => x.decided_by !== BUS)) { // head is all one class
        const q = admin.from('org_tasks').select(TASK_COLS).eq('status', 'assigned').order('id').limit(1);
        const { data: fair } = await (busInHead ? q.or('decided_by.is.null,decided_by.neq.' + BUS) : q.eq('decided_by', BUS));
        if (fair && fair.length) batch = batch.slice(0, MAX_TASKS - 1).concat(fair[0]);
      }
    }
    // THE RECLAIM COULD ONLY RUN WHEN THE QUEUE WAS EMPTY, AND THE QUEUE IS NEVER EMPTY
    // (12 Aug 2026). This was `if (batch.length < MAX_TASKS)`, i.e. stale work was picked up only
    // with the slots the ASSIGNED queue had left over. There are 340 tasks in 'assigned', so the
    // FIFO head fills both slots on every single run and the condition has never once been true.
    //
    // MEASURED: 48 tasks sit in 'in_progress', the oldest last touched on 2026-08-06 - six days -
    // and NONE is at MAX_ATTEMPTS, so none was abandoned deliberately. They are simply in a state
    // whose only exit was a branch that cannot execute. A recovery path that runs only when nothing
    // needs recovering is the same defect as the workflow steps parked on an executor that could
    // never pick them up.
    //
    // Reserving a slot rather than taking the leftovers, which is the pattern the fairness block
    // directly above already uses for exactly this reason: whichever class owns the head of the
    // queue, the other one still gets in. Oldest-first by last_run_at, so the six-day-old task goes
    // first rather than the lowest id. attempts still increments and MAX_ATTEMPTS still escalates to
    // the founder, so a task that genuinely cannot be worked leaves this loop instead of cycling.
    //
    // It costs the assigned queue one slot per run WHILE stale work exists, and nothing once it is
    // cleared - self-limiting, and cheaper than 48 tasks aging indefinitely.
    //
    // 12 Aug 2026: the reclaim honours the reflection ceiling, because a stale task is worked by the
    // same 25,000-token model call as a fresh one and 46 of the 48 in_progress rows are self-analysis.
    // A stale task on the REVENUE path is still reclaimed while the ceiling is spent — the ceiling
    // exists to stop the company thinking about itself, not to strand a customer.
    let staleQ = admin.from('org_tasks').select(TASK_COLS)
      .eq('status', 'in_progress').lt('last_run_at', staleCut).order('last_run_at').limit(1);
    if (gate.reflection_allowed === false) {
      if (!demandClasses.length) staleQ = null as any;
      else staleQ = staleQ.in('action_class', demandClasses);
    }
    const { data: stale } = staleQ ? await staleQ : { data: [] as any[] };
    if (stale && stale.length) batch = batch.slice(0, MAX_TASKS - 1).concat(stale[0]);

    const touchedObjectives = new Set<number>();
    const summary: any[] = []; let done = 0, escalated = 0, working = 0;
    const startRefused: any[] = [];

    for (const t of batch) {
      if (Date.now() - started > TIME_BUDGET_MS) break; // leave the rest for the next hourly run
      touchedObjectives.add(t.objective_id);
      const dept: any = deptMap.get(t.dept_key) || { name: t.dept_key, brain_agent: null, lead_agent: null };
      const attempts = (t.attempts || 0) + 1;
      // THE BRAKE REFUSES THE MARKER, NOT THE WORK — AND THIS WRITE WAS UNCHECKED (6 Aug 2026).
      // trg_org_task_autonomy_brake raises on any move INTO 'in_progress' by a non-advisory task
      // while WI-001 broad autonomy is blocked, which it is today (fn_autonomy_status().allowed is
      // false: three open spec_backlog rows plus agent_autonomy_enabled='false'). All 395 pending
      // event-derived tasks carry tier='autonomous', so all 395 hit it. Proven on production by an
      // aborted probe: updating #382 to in_progress raises check_violation.
      //
      // Nothing read the error, so the refusal was invisible AND it took the attempt counter down
      // with it — the trigger raises before the row is written, so `attempts` never persisted. That
      // is why the five event-derived tasks that finished today (#377-#381) are stored with
      // attempts=0 despite having been worked. `attempts` is MAX_ATTEMPTS' loop guard; with it dead
      // a task that never clears review is retried every hour forever and never escalates, and
      // giving that class a guaranteed slot above would have multiplied it.
      //
      // The brake is HONOURED, not weakened: when it refuses, the task does not claim 'in_progress'.
      // Only the counters are written, which leaves status exactly as the brake left it and is
      // bookkeeping the brake never gated. A run that could not start a task also cannot use
      // 'in_progress' as that task's retry state, so retryStatus falls back to its current status.
      const { error: startErr } = await admin.from('org_tasks').update({ status: 'in_progress', attempts, last_run_at: nowIso(), updated_at: nowIso() }).eq('id', t.id);
      if (startErr) {
        startRefused.push({ task_id: t.id, dept: t.dept_key, tier: t.tier, reason: String(startErr.message || startErr).slice(0, 200) });
        await admin.from('org_tasks').update({ attempts, last_run_at: nowIso(), updated_at: nowIso() }).eq('id', t.id);
      }
      const retryStatus = startErr ? t.status : 'in_progress';

      // AUDIT 7.3 (4 Aug 2026). RE-CHECK THE AUTHORITY, DO NOT INHERIT IT.
      //
      // This used to gate execution on org_tasks.tier alone - a column written by whoever created the
      // row. Three things write tasks and only intent_router consulted the authority model, so
      // fn_event_dispatch granted itself 'autonomous' on every task it made and this function
      // executed them without ever asking. A permission carried in the payload is not a permission,
      // it is a claim by the caller.
      //
      // The tier is now resolved HERE, from fn_dept_authority, at the moment of execution. The stored
      // tier is used only to detect the disagreement, which is itself the signal worth having: a row
      // claiming more authority than the model grants means something upstream is minting authority.
      const authRow: any = (await admin.rpc('fn_dept_authority', { p_dept: t.dept_key, p_action_class: t.action_class })).data;
      const grantedTier = String(authRow?.tier || 'gated');
      if (t.tier === 'autonomous' && grantedTier !== 'autonomous') {
        try {
          // 4 SEP 2026: a refusal is not a failed run. The guard did its job (the row claimed more
          // than the authority model grants and was not executed); recording it as 'error' put a
          // correct refusal on the founder's failure ledger, the same shape the department-mismatch
          // refusal below had until 3 Sep. The signal stays on the row so the minting writer is found.
          await admin.from('agent_runs').insert({ agent: 'cos_execute', status: 'skipped',
            counts: { signal: 'tier_claim_exceeds_grant', task_id: t.id, dept: t.dept_key,
                      action_class: t.action_class, claimed: t.tier, granted: grantedTier },
            note: ('org_tasks#' + t.id + ' was written with tier=autonomous but the authority model grants only "'
              + grantedTier + '" for ' + t.dept_key + '/' + t.action_class + '. Whatever created this row is '
              + 'minting authority it does not have. Reason: ' + String(authRow?.reason || '-')).slice(0, 500),
            started_at: nowIso(), finished_at: nowIso() });
        } catch (_e) { /* never let the alert block the refusal */ }
      }

      // EXECUTOR PATH — if this action_class is wired to a real executor, run it (real side effect)
      // instead of only preparing a deliverable. Anything the model does not grant autonomously falls
      // through to the advisory path below, which prepares a deliverable and moves nothing.
      const ex: any = execMap.get(execKey(t.action_class, t.dept_key));
      if (!ex && grantedTier === 'autonomous') {
        // An executor for this class exists, but it belongs to another department. Refuse it and say
        // so — this is the signal that either the task is misfiled or the registry row is.
        const foreign: any = execAnyDept.get(t.action_class);
        if (foreign) {
          try {
            // 3 SEP 2026: a refusal by policy that ROUTES the task to the advisory path is an outcome,
            // not a failed run. Logged as 'error' it paged the founder the first time a re-enabled
            // measurement cron filed a task under a department whose executor lives elsewhere.
            await admin.from('agent_runs').insert({ agent: 'cos_execute', status: 'skipped',
              counts: { signal: 'executor_department_mismatch', task_id: t.id, dept: t.dept_key,
                        action_class: t.action_class, executor: foreign.target, executor_dept: foreign.department },
              note: ('org_tasks#' + t.id + ' is owned by ' + t.dept_key + ' but the only executor for '
                + t.action_class + ' (' + foreign.target + ') belongs to ' + String(foreign.department || '(none)')
                + '. Refused; routed to the advisory deliverable path instead.').slice(0, 500),
              started_at: nowIso(), finished_at: nowIso() });
          } catch (_e) { /* never let the alert block the refusal */ }
        }
      }
      if (ex && grantedTier === 'autonomous' && (t.tier !== 'advisory' || ex.advisory_safe)) {
        let execResult: any;
        try {
          if (ex.kind === 'rpc') { const { data, error } = await admin.rpc(ex.target, ex.params || {}); execResult = error ? { error: error.message } : data; }
          else { const r = await fetch(FN + '/' + ex.target, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_cos_execute'), objective_id: t.objective_id, task_id: t.id, ...(ex.params || {}) }), signal: AbortSignal.timeout(50000) }); execResult = await r.json().catch(() => ({ error: 'bad_json' })); }
        } catch (e) { execResult = { error: String((e as Error)?.message || e) }; }
        const okExec = execResult && !execResult.error;
        const oneLine = (okExec ? String(execResult.note || JSON.stringify(execResult)) : 'executor error: ' + String(execResult?.error || 'unknown')).slice(0, 300);
        const newStatus = okExec ? 'done' : (attempts >= MAX_ATTEMPTS ? 'escalated' : retryStatus);
        if (newStatus === 'done') done++; else if (newStatus === 'escalated') escalated++; else working++;
        const review_pending = newStatus === 'done' && t.tier === 'supervised';
        await admin.from('org_tasks').update({ status: newStatus, decided_by: 'cos', updated_at: nowIso(),
          result: { mode: 'executed', executor: ex.target, executed: execResult, summary: oneLine, review_pending, used_llm: execResult?.used_llm === true, at: nowIso() } }).eq('id', t.id);
        try { await admin.from('org_memory').insert({ scope: t.dept_key, kind: 'action', content: (t.title + ' — ' + oneLine).slice(0, 500), source: 'cos' }); } catch (_e) {}
        if (newStatus === 'escalated') {
          try { await admin.from('agent_actions').insert({ agent: t.dept_key, kind: 'objective_step', status: 'pending', risk: 'low',
            title: ('Objective step needs you — ' + t.title).slice(0, 200),
            recommendation: ('Automated executor for ' + t.action_class + ' failed after ' + attempts + ' tries: ' + oneLine).slice(0, 400),
            detail: { objective_id: t.objective_id, task_id: t.id, dept: t.dept_key, action_class: t.action_class, tier: t.tier } }); } catch (_e) {}
        }
        summary.push({ task_id: t.id, dept: t.dept_key, tier: t.tier, status: newStatus, mode: 'executed', summary: oneLine });
        continue; // executed — skip the advisory deliverable path
      }

      const { data: obj } = await admin.from('org_objectives').select('objective').eq('id', t.objective_id).maybeSingle();
      const worker = await assignee(t.dept_key, t.action_class, dept.brain_agent || dept.lead_agent);
      const disp = await dispatch(dept.name, worker, obj?.objective || '', t);
      const deliverable = disp.text.trim();
      const usedLlm = disp.usedLlm;
      const oneLine = resultLine(deliverable);
      const delivered = DELIVERED_CLASSES.test(t.action_class || '') || t.tier === 'advisory';
      const mode = delivered ? 'delivered' : 'prepared'; // 'prepared' → dept's autonomous machinery executes the side effect
      const hasWork = deliverable.length > 60 && !NOT_WORK.test(deliverable.slice(0, 400));

      if (hasWork) {
        try { await admin.from('org_memory').insert({ scope: t.dept_key, kind: 'deliverable', content: (t.title + ' — ' + oneLine).slice(0, 500) + '\n\n' + deliverable.slice(0, 2500), source: 'cos' }); } catch (_e) {}
      }

      // THE REVIEW CHAIN. Until 6 Aug 2026 the whole quality gate was the line above —
      // `deliverable.length > 60` — and the department head, the Chief of Staff, the challenge
      // heuristics and the ten collaboration rules were all built, populated, and called by NOTHING.
      // Spec file #1 devotes two sections to this: "Every Task Has a Review Process" and "Employees
      // Challenge Each Other". fn_task_review runs fn_review_submit (department head resolved live
      // through fn_pick_reviewer + delegation_rule, then Chief of Staff, against the org_task
      // quality standard) and then the cross-department challenge, which is deterministic SQL and
      // therefore free on every task rather than rationed.
      //
      // fn_task_review reads the deliverable OFF THE ROW, so the result has to be stored before the
      // review runs, not after.
      let review: any = null;
      if (hasWork) {
        await admin.from('org_tasks').update({
          updated_at: nowIso(),
          result: { deliverable: deliverable.slice(0, 20000), summary: oneLine, mode, used_llm: usedLlm, brain: dept.brain_agent || dept.lead_agent || 'dept_head', at: nowIso() },
        }).eq('id', t.id);
        try {
          const { data, error } = await admin.rpc('fn_task_review', { p_task_id: t.id });
          review = error ? null : data;
        } catch (_e) { review = null; }
      }

      // Disposition. FAIL CLOSED, deliberately: a review that could not run is not an approval.
      // That is fn_review_submit's own rule for an uncheckable critical criterion, and applying a
      // weaker one here would restore the 60-character bar silently whenever the RPC is unreachable.
      // An escalation gets looked at; a false success never does.
      let newStatus: string;
      let reviewNote = '';
      if (!hasWork) {
        newStatus = attempts >= MAX_ATTEMPTS ? 'escalated' : retryStatus; // couldn't produce work → retry, then hand up
        reviewNote = 'no usable deliverable';
      } else if (review?.outcome === 'published') {
        newStatus = 'done';
        reviewNote = 'approved by ' + String(review.reviewer || 'the department head') + ' and the Chief of Staff'
          + ((review.dissents || []).length ? ' over ' + (review.dissents || []).length + ' recorded dissent(s)' : '');
      } else if (review?.outcome === 'reject' || review?.outcome === 'request_revision') {
        // Returned for revision. The existing attempt counter is the loop guard: three tries and it
        // goes to the founder rather than cycling forever.
        newStatus = attempts >= MAX_ATTEMPTS ? 'escalated' : retryStatus;
        reviewNote = String(review.outcome) + ' — '
          + ((review.violations || []).map((v: any) => v.rule + '/' + v.severity).join(', ')
             || (review.dissents || []).map((d: any) => d.by + ':' + d.stance).join(', ')
             || 'see review_chain');
      } else {
        newStatus = 'escalated';
        reviewNote = review ? ('review outcome ' + String(review.outcome)) : 'the review chain could not be reached';
      }
      if (newStatus === 'done') done++; else if (newStatus === 'escalated') escalated++; else working++;

      const review_pending = newStatus === 'done' && t.tier === 'supervised';
      await admin.from('org_tasks').update({
        status: newStatus, decided_by: 'cos', updated_at: nowIso(),
        result: { deliverable: deliverable.slice(0, 20000), summary: oneLine, mode, review_pending, used_llm: usedLlm, brain: dept.brain_agent || dept.lead_agent || 'dept_head', at: nowIso(),
                  review: review ? { outcome: review.outcome, reviewer: review.reviewer, delegated_from: review.delegated_from,
                                     violations: review.violations, dissents: review.dissents, rules_applied: review.rules_applied,
                                     blocked: review.blocked } : { outcome: 'unavailable' },
                  review_note: reviewNote },
      }).eq('id', t.id);

      if (newStatus === 'escalated') {
        try {
          await admin.from('agent_actions').insert({
            agent: t.dept_key, kind: 'objective_step', status: 'pending', risk: 'low',
            title: ('Objective step needs you — ' + t.title).slice(0, 200),
            recommendation: ('The ' + dept.name + ' department could not clear this after ' + attempts + ' tries: ' + reviewNote + '. Review and advise.').slice(0, 400),
            detail: { objective_id: t.objective_id, task_id: t.id, dept: t.dept_key, action_class: t.action_class, tier: t.tier, review: reviewNote },
          });
        } catch (_e) {}
      }
      // `worker` is recorded, not just used: which EMPLOYEE did the work is the thing the org chart
      // could not previously answer, and a routing change nobody can audit is a routing change
      // nobody can disprove.
      summary.push({ task_id: t.id, dept: t.dept_key, tier: t.tier, status: newStatus, mode, worker, summary: oneLine, review: reviewNote });
    }

    // Roll up each touched objective. Open = anything still needing work or the founder (incl. gated 'proposed').
    const rolled: any[] = [];
    for (const oid of touchedObjectives) {
      const { data: all } = await admin.from('org_tasks').select('status,tier,title,result').eq('objective_id', oid);
      const open = (all || []).filter((x: any) => ['proposed', 'assigned', 'in_progress', 'escalated'].includes(x.status));
      if (open.length === 0 && (all || []).length > 0) {
        const lines = (all || []).map((x: any) => '- [' + x.status + '] ' + x.title + ': ' + String(x.result?.summary || '').slice(0, 160)).join('\n');
        const { data: o } = await admin.from('org_objectives').select('objective').eq('id', oid).maybeSingle();
        const outcome = await llm('You are the Chief of Staff at QuotesDone. In 2-3 sentences, summarize for the founder what the organization accomplished on this objective across its departments. Concrete and honest.', 'OBJECTIVE: ' + (o?.objective || '') + '\n\nTASK RESULTS:\n' + lines, 400);
        const anyFailed = (all || []).some((x: any) => x.status === 'failed');
        await admin.from('org_objectives').update({ status: anyFailed ? 'blocked' : 'done', outcome: (outcome || 'Completed.').slice(0, 2000), closed_at: nowIso(), updated_at: nowIso() }).eq('id', oid);
        rolled.push({ objective_id: oid, status: anyFailed ? 'blocked' : 'done' });
      }
    }

    // ONE row per run, not one per task: this fires on every non-advisory task while WI-001 is open,
    // and an alert that arrives 24 times a day identically is an alert nobody reads.
    //
    // status IS 'ok', AND THAT IS THE GATE. Measured on production the first time this shipped,
    // 6 Aug 2026 15:10 UTC: writing this row with status:'error' fired fn_emit_test_failed_ins,
    // which raised company_event #734 `test.failed / scheduled_run / cos_execute` — and test.failed
    // has two active subscribers (ops_director, qa_manager), so fn_event_dispatch would have turned
    // this function's own refusal into two fresh org_tasks for this function to work, every day,
    // forever, since WI-001 stays open and the refusal therefore never stops. The emitter
    // de-duplicates per agent per calendar day so the ceiling was 2 tasks/day rather than a burst,
    // but a closed loop with no terminating condition is a closed loop at any rate.
    // It was also simply FALSE: the run did not fail. It completed 2 of 2 tasks and published both.
    // A scheduled run that finished its work must not report itself as a failed scheduled run.
    // The condition stays fully visible — counts.signal, the note, start_refused in the response and
    // in the chief_of_staff row below — without manufacturing work about itself.
    if (startRefused.length) {
      try {
        await admin.from('agent_runs').insert({ agent: 'cos_execute', status: 'ok',
          counts: { signal: 'task_start_refused', n: startRefused.length, tasks: startRefused },
          note: (startRefused.length + ' task(s) could not be moved to in_progress this run — the autonomy brake '
            + 'refuses the in-flight marker for non-advisory work while broad autonomy is blocked. The tasks were '
            + 'still worked on the advisory path and their attempt counters were persisted separately so the '
            + 'MAX_ATTEMPTS loop guard still applies. First: #' + startRefused[0].task_id + ' — ' + startRefused[0].reason).slice(0, 500),
          started_at: nowIso(), finished_at: nowIso() });
      } catch (_e) {}
    }
    try { await admin.from('agent_runs').insert({ agent: 'chief_of_staff', status: 'ok', finished_at: nowIso(), counts: { processed: batch.length, done, escalated, working, start_refused: startRefused.length, objectives_closed: rolled.length, ms: Date.now() - started } }); } catch (_e) {}
    return J({ ok: true, processed: batch.length, done, escalated, working, start_refused: startRefused, objectives_rolled: rolled, tasks: summary });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
