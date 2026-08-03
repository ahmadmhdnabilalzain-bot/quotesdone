// cos_execute (v4) — the Chief of Staff's EXECUTION ENGINE. Runs hourly. Turns the objective/task
// ledger from a plan into work actually getting done. For each ready task:
//   - if its action_class is wired to a real executor (org_action_executor registry), it RUNS that
//     executor (real side effect, within the executor's own guards) and records mode:'executed';
//   - otherwise it dispatches to the owning department's specialist (agent_brain), which reasons +
//     produces the deliverable within its delegated authority (mode:'prepared'/'delivered').
// Either way it records to the ledger + organizational memory, advances the task by its authority tier,
// and rolls each objective up to done.
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
const llm = makeLlm(SONNET_FIRST, { max: 500, temperature: 0.2, timeoutMs: 75000 });

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
// A deliverable-complete class is one where the work product IS the completion (advice/analysis/plan/
// draft/knowledge). Others are 'prepared' — the department's own autonomous machinery (invite ramp,
// kb autofill, approval lane, etc.) performs the real side effect on its schedule.
const DELIVERED_CLASSES = /recommend|review|analy|forecast|report|research|draft|knowledge|plan|strategy|audit|assess/i;

// Ask the owning department's specialist to produce the ACTUAL deliverable for this task.
async function dispatch(deptName: string, brainKey: string, objective: string, t: any): Promise<string> {
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
  if (brainKey && (await validBrains()).has(brainKey)) {
    try {
      // 29 Jul 2026: was 50000, which was 5s TIGHTER than ai_gateway's own 55s budget - so this
      // caller walked away while the model was still generating and still being billed, and the
      // task recorded "could not reach the AI service". The inner call must outlast the layer it
      // depends on, never the reverse.
      const r = await fetch(FN + '/agent_brain', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: await sec('cred_fn_cos_execute'), agent: brainKey, message: instruction }), signal: AbortSignal.timeout(75000) });
      const j = await r.json().catch(() => ({} as any));
      if (j?.reply && String(j.reply).length > 40) return String(j.reply);
    } catch (_e) { /* fall through to generic */ }
  }
  // Generic department-head fallback (analytics, procurement, or brain unreachable).
  const out = await llm('You are the head of the ' + deptName + ' department at QuotesDone, a UAE B2B anonymous quotation marketplace. You are a seasoned professional. Produce concrete, practical deliverables. Never invent numbers.', instruction, 1200);
  return out || '';
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

    const { data: depts } = await admin.from('org_departments').select('dept_key,name,brain_agent,lead_agent');
    const deptMap = new Map((depts || []).map((d: any) => [d.dept_key, d]));
    // Action-executor registry: action_classes wired to a REAL side-effect executor.
    const { data: execs } = await admin.from('org_action_executor').select('action_class,kind,target,params,active,advisory_safe').eq('active', true);
    const execMap = new Map((execs || []).map((e: any) => [e.action_class, e]));

    // Ready set: freshly assigned + any in_progress a prior run may have left orphaned (stale).
    const staleCut = new Date(Date.now() - STALE_MIN * 60000).toISOString();
    const { data: assigned } = await admin.from('org_tasks').select('id,objective_id,dept_key,title,detail,action_class,tier,attempts,status').eq('status', 'assigned').order('id').limit(MAX_TASKS);
    let batch = assigned || [];
    if (batch.length < MAX_TASKS) {
      const { data: stale } = await admin.from('org_tasks').select('id,objective_id,dept_key,title,detail,action_class,tier,attempts,status').eq('status', 'in_progress').lt('last_run_at', staleCut).order('id').limit(MAX_TASKS - batch.length);
      batch = batch.concat(stale || []);
    }

    const touchedObjectives = new Set<number>();
    const summary: any[] = []; let done = 0, escalated = 0, working = 0;

    for (const t of batch) {
      if (Date.now() - started > TIME_BUDGET_MS) break; // leave the rest for the next hourly run
      touchedObjectives.add(t.objective_id);
      const dept: any = deptMap.get(t.dept_key) || { name: t.dept_key, brain_agent: null, lead_agent: null };
      const attempts = (t.attempts || 0) + 1;
      await admin.from('org_tasks').update({ status: 'in_progress', attempts, last_run_at: nowIso(), updated_at: nowIso() }).eq('id', t.id);

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
          await admin.from('agent_runs').insert({ agent: 'cos_execute', status: 'error',
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
      const ex: any = execMap.get(t.action_class);
      if (ex && grantedTier === 'autonomous' && (t.tier !== 'advisory' || ex.advisory_safe)) {
        let execResult: any;
        try {
          if (ex.kind === 'rpc') { const { data, error } = await admin.rpc(ex.target, ex.params || {}); execResult = error ? { error: error.message } : data; }
          else { const r = await fetch(FN + '/' + ex.target, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_cos_execute'), objective_id: t.objective_id, task_id: t.id, ...(ex.params || {}) }), signal: AbortSignal.timeout(50000) }); execResult = await r.json().catch(() => ({ error: 'bad_json' })); }
        } catch (e) { execResult = { error: String((e as Error)?.message || e) }; }
        const okExec = execResult && !execResult.error;
        const oneLine = (okExec ? String(execResult.note || JSON.stringify(execResult)) : 'executor error: ' + String(execResult?.error || 'unknown')).slice(0, 300);
        const newStatus = okExec ? 'done' : (attempts >= MAX_ATTEMPTS ? 'escalated' : 'in_progress');
        if (newStatus === 'done') done++; else if (newStatus === 'escalated') escalated++; else working++;
        const review_pending = newStatus === 'done' && t.tier === 'supervised';
        await admin.from('org_tasks').update({ status: newStatus, decided_by: 'cos', updated_at: nowIso(),
          result: { mode: 'executed', executor: ex.target, executed: execResult, summary: oneLine, review_pending, at: nowIso() } }).eq('id', t.id);
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
      const deliverable = (await dispatch(dept.name, dept.brain_agent || dept.lead_agent, obj?.objective || '', t)).trim();
      const oneLine = resultLine(deliverable);
      const delivered = DELIVERED_CLASSES.test(t.action_class || '') || t.tier === 'advisory';
      const mode = delivered ? 'delivered' : 'prepared'; // 'prepared' → dept's autonomous machinery executes the side effect
      const hasWork = deliverable.length > 60 && !NOT_WORK.test(deliverable.slice(0, 400));

      if (hasWork) {
        try { await admin.from('org_memory').insert({ scope: t.dept_key, kind: 'deliverable', content: (t.title + ' — ' + oneLine).slice(0, 500) + '\n\n' + deliverable.slice(0, 2500), source: 'cos' }); } catch (_e) {}
      }

      // Disposition by tier — the permission model already decided what's allowed.
      let newStatus: string;
      if (!hasWork) {
        newStatus = attempts >= MAX_ATTEMPTS ? 'escalated' : 'in_progress'; // couldn't produce work → retry, then hand up
      } else {
        newStatus = 'done';
      }
      if (newStatus === 'done') done++; else if (newStatus === 'escalated') escalated++; else working++;

      const review_pending = newStatus === 'done' && t.tier === 'supervised';
      await admin.from('org_tasks').update({
        status: newStatus, decided_by: 'cos', updated_at: nowIso(),
        result: { deliverable: deliverable.slice(0, 6000), summary: oneLine, mode, review_pending, brain: dept.brain_agent || dept.lead_agent || 'dept_head', at: nowIso() },
      }).eq('id', t.id);

      if (newStatus === 'escalated') {
        try {
          await admin.from('agent_actions').insert({
            agent: t.dept_key, kind: 'objective_step', status: 'pending', risk: 'low',
            title: ('Objective step needs you — ' + t.title).slice(0, 200),
            recommendation: ('The ' + dept.name + ' department could not complete this autonomously after ' + attempts + ' tries. Review and advise.').slice(0, 400),
            detail: { objective_id: t.objective_id, task_id: t.id, dept: t.dept_key, action_class: t.action_class, tier: t.tier },
          });
        } catch (_e) {}
      }
      summary.push({ task_id: t.id, dept: t.dept_key, tier: t.tier, status: newStatus, mode, summary: oneLine });
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

    try { await admin.from('agent_runs').insert({ agent: 'chief_of_staff', status: 'ok', finished_at: nowIso(), counts: { processed: batch.length, done, escalated, working, objectives_closed: rolled.length, ms: Date.now() - started } }); } catch (_e) {}
    return J({ ok: true, processed: batch.length, done, escalated, working, objectives_rolled: rolled, tasks: summary });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
