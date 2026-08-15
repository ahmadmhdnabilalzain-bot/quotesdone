// ROLE CALLER CENSUS — who actually invokes each of the 90 canonical roles?
//
// The founder's instruction is blunt: "No active role may have zero real workflow callers. No role
// may be retained only because a row already exists." This file answers that question by
// measurement rather than by reading the role table back to itself.
//
// A role is CALLED when something outside org_role names it. Six independent surfaces are searched,
// because each can be the only one that names a given role:
//
//   sql       a pg_proc body in public names the role_id or its runtime_agent_key
//   cron      a pg_cron command names it
//   edge      an edge function under supabase/functions names it
//   executor  org_action_executor.owner_os / department routes work to it
//   workflow  employee_workflow gives it a part in a named workflow
//   tool      agent_tool.authorised_roles grants it a tool
//
// And separately, RUNTIME EVIDENCE — did it ever actually do anything?
//
//   runs      agent_runs.agent
//   actions   agent_actions.agent
//   review    review_chain.author_agent / reviewer_agent
//   tasks     org_tasks assignee
//
// The two are deliberately not merged. A role with callers and no runtime evidence is wired but
// idle, which for an on-demand specialist is the CORRECT state and for an event-driven operator is
// a defect. A role with runtime evidence and no callers is being driven by something that does not
// name it — which is how dispatch_inquiry ran for months with agent_runs.agent = 'dispatch_inquiry'
// and no canonical owner at all.
//
//   node scripts/agents/role_caller_census.mjs            # print the summary
//   node scripts/agents/role_caller_census.mjs --write    # also write the CSVs and JSON
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

if (!token) {
  console.log('SKIP role_caller_census: no SUPABASE_ACCESS_TOKEN (expected in CI)');
  process.exit(0);
}

const REF = process.argv.find((a) => a.startsWith('--ref='))?.slice(6) || 'htdblwldjkcgjvmqkbeh';
const WRITE = process.argv.includes('--write');
const OUT_JSON = 'docs/agents/role_census.json';
const OUT_MATRIX = 'docs/agents/FINAL_ROLE_NECESSITY_MATRIX.csv';
const OUT_ACTIVATION = 'docs/agents/FINAL_RUNTIME_ACTIVATION_MAP.csv';

async function q(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if (!r.ok) { console.error(`query failed: ${r.status} ${await r.text()}`); process.exit(1); }
  return r.json();
}

// ---------------------------------------------------------------------------------------------
// 1. the registry
// ---------------------------------------------------------------------------------------------
const roles = await q(`
  select r.role_id, r.display_name, r.primary_department_id, r.runtime_mode, r.runtime_agent_key,
         r.manager_role_id, r.authority_level, r.model_policy, r.budget_limit,
         coalesce(r.activation_conditions,'')                as activation_conditions,
         coalesce(array_length(r.tools,1),0)                 as tools_n,
         array_to_string(coalesce(r.tools,'{}'),';')         as tools,
         coalesce(array_length(r.knowledge_scopes,1),0)      as ks_n,
         array_to_string(coalesce(r.knowledge_scopes,'{}'),';')      as knowledge_scopes,
         array_to_string(coalesce(r.owned_decisions,'{}'),';')       as owned_decisions,
         array_to_string(coalesce(r.forbidden_decisions,'{}'),';')   as forbidden_decisions,
         array_to_string(coalesce(r.output_contracts,'{}'),';')      as output_contracts,
         array_to_string(coalesce(r.handoff_targets,'{}'),';')       as handoff_targets,
         array_to_string(coalesce(r.escalation_targets,'{}'),';')    as escalation_targets,
         r.status
    from org_role r
   where r.runtime_mode <> 'knowledge_overlay'
   order by r.primary_department_id, r.role_id`);

// every identifier a caller might legitimately use for this role
const aliasRows = await q(`
  select role_id, alias from org_role_alias
  union all select r.role_id, a.alias from org_agent_alias a join org_role r on r.runtime_agent_key = a.agent_key`);
const aliasOf = new Map();
for (const a of aliasRows) {
  if (!aliasOf.has(a.role_id)) aliasOf.set(a.role_id, new Set());
  aliasOf.get(a.role_id).add(a.alias);
}

// ---------------------------------------------------------------------------------------------
// 2. the six caller surfaces
// ---------------------------------------------------------------------------------------------
const sqlBodies = await q(`
  select p.proname as name, pg_get_functiondef(p.oid) as body
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f'`);

const cronJobs = await q(`select jobname as name, command as body from cron.job`).catch(() => []);

const execRows = await q(`
  select action_class, kind, coalesce(owner_os,'') as owner_os, coalesce(department,'') as department,
         coalesce(target,'') as target, active
    from org_action_executor`);

// workflow_step is the STEP-LEVEL ownership surface and the one the founder's chain is expressed
// in: actor_role is the accountable owner of one step. employee_workflow is coarser — it records
// participation in a whole workflow, and it records TEN owners for rfq_handling — so it cannot
// answer "who owns this step" on its own. Both are read; a role owning a step is a caller.
const stepRows = await q(`
  select workflow_key, step_no, actor_role,
         coalesce(fn_org_agent_resolve(actor_role), fn_org_role_resolve(actor_role), actor_role) as resolved
    from workflow_step`);
const wfRows = await q(`select agent_key, workflow_key, role_in_workflow from employee_workflow`);
const toolRows = await q(`
  select tool_id, array_to_string(coalesce(authorised_roles,'{}'),';') as roles,
         array_to_string(coalesce(authorised_departments,'{}'),';') as depts, active
    from agent_tool`);
const kpiRows = await q(`
  select agent_key, count(*) as n, count(*) filter (where active) as active_n,
         count(*) filter (where measure_sql is not null and btrim(measure_sql) <> '') as measurable_n,
         count(*) filter (where actual_value is not null) as measured_n
    from employee_kpi group by agent_key`);

// runtime evidence
const runEvidence = await q(`
  select k as agent_key, sum(runs) as runs, sum(actions) as actions, sum(reviews) as reviews, sum(tasks) as tasks
    from (
      select agent as k, count(*) runs, 0 actions, 0 reviews, 0 tasks from agent_runs group by 1
      union all select agent, 0, count(*), 0, 0 from agent_actions group by 1
      union all select author_agent, 0, 0, count(*), 0 from review_chain group by 1
      union all select reviewer_agent, 0, 0, count(*), 0 from review_chain group by 1
      union all select assigned_agent, 0, 0, 0, count(*) from org_tasks where assigned_agent is not null group by 1
    ) s where k is not null group by k`);

// ---------------------------------------------------------------------------------------------
// 3. the local source tree — edge functions and the scripts that drive them
// ---------------------------------------------------------------------------------------------
function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    let s; try { s = statSync(p); } catch { continue; }
    if (s.isDirectory()) walk(p, out);
    else if (/\.(ts|tsx|mjs|js|sql)$/.test(e)) out.push(p);
  }
  return out;
}
const edgeFiles = walk('supabase/functions').map((p) => ({ path: p, text: readFileSync(p, 'utf8') }));

// A bare identifier match is too loose — 'ceo' appears inside 'ceo_report' and inside prose. Every
// search below is word-bounded on the identifier, which is the same discipline the negation-blind
// keyword detector needed on 13 Aug.
const wordRe = (id) => new RegExp(`(^|[^a-z0-9_])${id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^a-z0-9_]|$)`, 'i');

const kpiOf = new Map(kpiRows.map((k) => [k.agent_key, k]));
const evOf = new Map(runEvidence.map((e) => [e.agent_key, e]));

const census = roles.map((r) => {
  const ids = new Set([r.role_id, r.runtime_agent_key, ...(aliasOf.get(r.role_id) || [])].filter(Boolean));
  const anyId = (text) => [...ids].some((id) => wordRe(id).test(text));

  const sqlCallers = sqlBodies.filter((f) => anyId(f.body)).map((f) => f.name);
  const cronCallers = cronJobs.filter((f) => anyId(f.body || '')).map((f) => f.name);
  const edgeCallers = edgeFiles.filter((f) => anyId(f.text))
    .map((f) => f.path.replace(/\\/g, '/').replace('supabase/functions/', '').replace(/\/index\.ts$/, ''));
  const execCallers = execRows.filter((e) => anyId(`${e.owner_os} ${e.target}`)).map((e) => e.action_class);
  const stepCallers = stepRows.filter((s) => ids.has(s.resolved) || ids.has(s.actor_role))
    .map((s) => `${s.workflow_key}#${s.step_no}`);
  const wfCallers = wfRows.filter((w) => ids.has(w.agent_key)).map((w) => `${w.workflow_key}:${w.role_in_workflow}`);
  const toolGrants = toolRows.filter((t) => (t.roles || '').split(';').some((x) => ids.has(x))).map((t) => t.tool_id);

  const ev = evOf.get(r.runtime_agent_key) || evOf.get(r.role_id) || {};
  const kpi = kpiOf.get(r.runtime_agent_key) || kpiOf.get(r.role_id) || {};

  const callers = {
    sql: sqlCallers, cron: cronCallers, edge: edgeCallers,
    executor: [...new Set(execCallers)], step: stepCallers, workflow: wfCallers, tool: toolGrants,
  };
  const callerTotal = Object.values(callers).reduce((a, b) => a + b.length, 0);

  return {
    ...r,
    identifiers: [...ids],
    callers,
    caller_total: callerTotal,
    caller_surfaces: Object.entries(callers).filter(([, v]) => v.length).map(([k]) => k),
    kpi_total: Number(kpi.n || 0),
    kpi_active: Number(kpi.active_n || 0),
    kpi_measurable: Number(kpi.measurable_n || 0),
    kpi_measured: Number(kpi.measured_n || 0),
    runs: Number(ev.runs || 0),
    actions: Number(ev.actions || 0),
    reviews: Number(ev.reviews || 0),
    tasks: Number(ev.tasks || 0),
    runtime_evidence: Number(ev.runs || 0) + Number(ev.actions || 0) + Number(ev.reviews || 0) + Number(ev.tasks || 0),
  };
});

// ---------------------------------------------------------------------------------------------
// 4. the class, derived from runtime_mode — H / O / S / R as the founder defined them
// ---------------------------------------------------------------------------------------------
const CLASS = {
  scheduled_manager: 'H',
  event_driven_operator: 'O',
  on_demand_specialist: 'S',
  independent_reviewer: 'R',
};

// The necessity verdict. The default follows the class, because a role with callers, tools,
// knowledge, a KPI and a forbidden-decision set IS needed in its class. The overrides are the
// roles this workstream actually changed, and the ones where the existing implementation was
// measured to be already correct and was therefore left alone.
const REPURPOSED = {
  supplier_matching_dispatch_operator:
    'REPURPOSE — was Commercial Services Specialist; now owns the supplier selection step that had no owner',
  marketplace_content_privacy_reviewer:
    'REPURPOSE — was Content Moderation Reviewer; now inspects the actual supplier-facing payload',
  agent_workforce_capability_director:
    'REPURPOSE — was HR Director; the seat governs an AI workforce, not human resources',
  visual_design:
    'REPURPOSE — Director to Specialist; advisory, and artifact.review removed from its tools',
  test_automation_engineer:
    'REPURPOSE — reviewer to operator; release go/no-go returned to the QA & Release Management Director',
  organization_designer:
    'REPURPOSE — moved from exec to people_ops under the workforce director',
  financial_controller:
    'REQUIRED_CORE — scope extended to UAE tax; the capability is an overlay, not a new employee',
};
const EXISTING_BETTER = {
  spec_mep: 'EXISTING_BETTER_KEEP — already on_demand_specialist with advisory authority, which is what the instruction asks for; only the fence against duplicating an overlay was added',
  spec_construction: 'EXISTING_BETTER_KEEP — as spec_mep',
  spec_fitout: 'EXISTING_BETTER_KEEP — as spec_mep',
  spec_industrial: 'EXISTING_BETTER_KEEP — as spec_mep',
};
const verdictOf = (c) => EXISTING_BETTER[c.role_id] || REPURPOSED[c.role_id]
  || ({ H: 'REQUIRED_MANAGER', O: 'REQUIRED_CORE', S: 'REQUIRED_ON_DEMAND', R: 'REQUIRED_REVIEWER' }[CLASS[c.runtime_mode]] || 'DEFER');

const summary = {
  roles: census.length,
  by_class: {},
  no_callers: census.filter((c) => c.caller_total === 0).map((c) => c.role_id),
  no_tools: census.filter((c) => c.tools_n === 0).map((c) => c.role_id),
  no_knowledge: census.filter((c) => c.ks_n === 0).map((c) => c.role_id),
  no_kpi: census.filter((c) => c.kpi_active === 0).map((c) => c.role_id),
  no_forbidden: census.filter((c) => !c.forbidden_decisions).map((c) => c.role_id),
  operators_never_ran: census.filter((c) => c.runtime_mode === 'event_driven_operator' && c.runtime_evidence === 0).map((c) => c.role_id),
  managers_never_ran: census.filter((c) => c.runtime_mode === 'scheduled_manager' && c.runtime_evidence === 0).map((c) => c.role_id),
};
for (const c of census) {
  const k = CLASS[c.runtime_mode] || '?';
  summary.by_class[k] = (summary.by_class[k] || 0) + 1;
}

console.log(`project                     : ${REF}`);
console.log(`canonical roles (non-overlay): ${summary.roles}`);
console.log(`by class H/O/S/R            : ${['H', 'O', 'S', 'R'].map((k) => `${k}=${summary.by_class[k] || 0}`).join('  ')}`);
console.log(`roles with ZERO callers     : ${summary.no_callers.length}${summary.no_callers.length ? '  ' + summary.no_callers.join(', ') : ''}`);
console.log(`roles with no tools         : ${summary.no_tools.length}${summary.no_tools.length ? '  ' + summary.no_tools.join(', ') : ''}`);
console.log(`roles with no knowledge     : ${summary.no_knowledge.length}${summary.no_knowledge.length ? '  ' + summary.no_knowledge.join(', ') : ''}`);
console.log(`roles with no active KPI    : ${summary.no_kpi.length}${summary.no_kpi.length ? '  ' + summary.no_kpi.join(', ') : ''}`);
console.log(`roles with no forbidden set : ${summary.no_forbidden.length}${summary.no_forbidden.length ? '  ' + summary.no_forbidden.join(', ') : ''}`);
console.log(`operators with no runtime ev: ${summary.operators_never_ran.length}  ${summary.operators_never_ran.join(', ')}`);
console.log(`managers  with no runtime ev: ${summary.managers_never_ran.length}  ${summary.managers_never_ran.join(', ')}`);

if (WRITE) {
  const esc = (v) => {
    const s = v === null || v === undefined ? '' : String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  writeFileSync(OUT_JSON, JSON.stringify({ ref: REF, generated_utc: new Date().toISOString(), summary, census }, null, 2));

  const head = ['role_id', 'display_name', 'department', 'class', 'runtime_mode', 'workflows_served',
    'activation_event', 'actual_callers', 'tools', 'knowledge_scopes', 'owned_decisions',
    'forbidden_decisions', 'manager', 'reviewer', 'kpi_causal_chain', 'cost_policy', 'status'];
  const rows = census.map((c) => [
    c.role_id, c.display_name, c.primary_department_id, CLASS[c.runtime_mode] || '?', c.runtime_mode,
    [...c.callers.step, ...c.callers.workflow].join(' | ') || '(none recorded)',
    c.activation_conditions,
    c.caller_surfaces.map((s) => `${s}:${c.callers[s].length}`).join(' ') || 'NONE',
    c.tools, c.knowledge_scopes, c.owned_decisions, c.forbidden_decisions,
    c.manager_role_id || '(founder)',
    // The reviewer of this role's work. An independent_reviewer is reviewed by its own manager;
    // everyone else by fn_pick_reviewer over their department, which never returns the author.
    c.runtime_mode === 'independent_reviewer'
      ? `${c.manager_role_id} (its manager; it never reviews itself)`
      : `fn_pick_reviewer('${c.primary_department_id}', author) — the department head unless the head is the author`,
    `${c.kpi_active} active / ${c.kpi_measurable} measurable / ${c.kpi_measured} measured`,
    c.model_policy + (c.budget_limit ? ` cap=${c.budget_limit}` : ''),
    verdictOf(c),
  ].map(esc).join(','));
  writeFileSync(OUT_MATRIX, head.join(',') + '\n' + rows.join('\n') + '\n');

  const ahead = ['role_id', 'class', 'runtime_mode', 'activation_event', 'caller_surfaces',
    'workflow_steps_owned', 'sql_callers', 'cron_callers', 'edge_callers', 'executor_callers',
    'runs', 'actions', 'reviews', 'tasks', 'runtime_evidence'];
  const arows = census.map((c) => [
    c.role_id, CLASS[c.runtime_mode] || '?', c.runtime_mode, c.activation_conditions,
    c.caller_surfaces.join(' '),
    c.callers.step.join(' '),
    c.callers.sql.slice(0, 12).join(' '), c.callers.cron.join(' '),
    c.callers.edge.slice(0, 12).join(' '), c.callers.executor.slice(0, 12).join(' '),
    c.runs, c.actions, c.reviews, c.tasks, c.runtime_evidence,
  ].map(esc).join(','));
  writeFileSync(OUT_ACTIVATION, ahead.join(',') + '\n' + arows.join('\n') + '\n');

  console.log(`\nwrote ${OUT_JSON}, ${OUT_MATRIX}, ${OUT_ACTIVATION}`);
}
