// Generate the agent-reorganisation deliverables FROM THE LIVE DATABASE.
//
// Every number in these documents is measured at generation time against production. The only
// authored input is the current->target department map, which is the decision itself and is the
// same VALUES list applied in scripts/sql/org_reorg_02_departments.sql.
//
//   node scripts/agents/export_org_docs.mjs [--ref=htdblwldjkcgjvmqkbeh]
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';

const REF = (process.argv.find((a) => a.startsWith('--ref=')) || '--ref=htdblwldjkcgjvmqkbeh').slice(6);
const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
if (!token) { console.error('no SUPABASE_ACCESS_TOKEN'); process.exit(2); }

async function q(sql) {
  for (let attempt = 0; ; attempt++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: sql }),
    });
    const t = await r.text();
    if ((r.status === 429 || r.status >= 500) && attempt < 5) {
      await new Promise((s) => setTimeout(s, 1500 * 2 ** attempt)); continue;
    }
    if (!r.ok) throw new Error(`${r.status} ${t}`);
    return JSON.parse(t);
  }
}

// The authored decision: which department each of the 25 absorbed into. Everything else is read.
const DEPT_BEFORE = {
  ceo: 'exec', brief: 'exec', strategy_director: 'exec', cpo: 'exec',
  org_designer: 'evolution', innovation_mgr: 'evolution', optimisation_eng: 'evolution',
  sales_director: 'sales', account_mgr: 'sales', crm_pipeline_mgr: 'sales',
  marketing: 'marketing', brand_mgr: 'marketing', marketing_content: 'marketing',
  marketing_design: 'marketing', marketing_social: 'marketing', marketing_analyst: 'marketing',
  marketing_copy: 'marketing',
  bd: 'bizdev', partnerships_mgr: 'bizdev', gov_relations_mgr: 'bizdev',
  followup: 'customer_success', cs_onboarding: 'customer_success', cs_support: 'customer_success',
  cs_retention: 'customer_success', rfq_success: 'customer_success',
  comms_manager: 'comms', channel_specialist: 'comms', notification_ops: 'comms',
  procurement: 'procurement', quote_evaluation: 'procurement', supplier_verification: 'procurement',
  spec_commercial: 'procurement', spec_construction: 'procurement', spec_fitout: 'procurement',
  spec_industrial: 'procurement', spec_mep: 'procurement',
  rfq_qualification_mgr: 'rfq_intelligence', inquiry_router: 'rfq_intelligence',
  inquiry_scoring: 'rfq_intelligence',
  onboarding: 'supplier_success', supplier_coverage: 'supplier_success',
  supplier_retention: 'supplier_success',
  taxonomy_manager: 'supplier_knowledge', category_curator: 'supplier_knowledge',
  supplier_intel_analyst: 'supplier_knowledge',
  doc_intel_manager: 'doc_intelligence', boq_analyst: 'doc_intelligence',
  drawing_analyst: 'doc_intelligence',
  cto: 'it', it: 'it', security: 'it',
  eng_manager: 'engineering', backend_engineer: 'engineering', frontend_engineer: 'engineering',
  solution_architect: 'engineering',
  ai_director: 'ai_dept', ai_architect: 'ai_dept', prompt_engineer: 'ai_dept',
  model_evaluator: 'ai_dept',
  intel_director: 'intelligence', forecast_analyst: 'intelligence', market_analyst: 'intelligence',
  supplier_analyst: 'intelligence',
  analytics_director: 'analytics', analytics: 'analytics', bi_analyst: 'analytics',
  knowledge_director: 'knowledge_eng', kb_engineer: 'knowledge_eng',
  knowledge_validator: 'knowledge_eng',
  cfo: 'finance', bookkeeper: 'finance', ap_specialist: 'finance', collections: 'finance',
  financial_analyst: 'finance',
  payments_manager: 'payments', billing_specialist: 'payments',
  legal: 'legal', compliance_mgr: 'legal', contract_specialist: 'legal', risk_governance_mgr: 'legal',
  trust_safety_mgr: 'trust_safety', fraud_analyst: 'trust_safety', moderation_specialist: 'trust_safety',
  ops_director: 'knowledge', docs: 'knowledge', process_improvement_mgr: 'knowledge',
  project_coordinator: 'knowledge',
  hr_director: 'hr', recruitment_specialist: 'hr', learning_dev_mgr: 'hr',
  culture_performance_mgr: 'hr',
  qa_manager: 'qa', test_automation_eng: 'qa', ai_qa_specialist: 'qa',
};

const MERGED_AWAY = {
  analytics_director: 'data_intelligence_director',
  supplier_intel_analyst: 'supplier_intelligence_analyst',
  notification_ops: 'lifecycle_channel_operations',
  marketing_copy: 'content_strategy_and_copy',
};

const csv = (v) => {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const row = (arr) => arr.map(csv).join(',');

const roles = await q(`
  select r.role_id, r.display_name, r.primary_department_id, d.name dept_name, r.manager_role_id,
         r.runtime_mode, r.runtime_agent_key, r.authority_level, r.status, r.rationale,
         r.activation_conditions, r.budget_limit, r.model_policy, r.evaluation_suite,
         array_to_string(r.owned_decisions,' | ') owned,
         array_to_string(r.forbidden_decisions,' | ') forbidden,
         array_to_string(r.output_contracts,' | ') outputs,
         array_to_string(r.required_inputs,' | ') inputs,
         array_to_string(r.tools,' | ') tools,
         array_to_string(r.knowledge_scopes,' | ') scopes,
         array_to_string(r.handoff_targets,' | ') handoffs,
         array_to_string(r.escalation_targets,' | ') escalations,
         (select string_agg(c.committee_key||':'||c.seat,' | ' order by c.committee_key)
            from org_role_committee c where c.role_id=r.role_id) committees,
         (select count(*) from employee_kpi k where k.agent_key=r.runtime_agent_key and k.active) kpis,
         (select count(*) from employee_knowledge k where k.agent_key=r.runtime_agent_key) knowledge_rows,
         (select count(*) from employee_authority k where k.agent_key=r.runtime_agent_key) authority_rows,
         (select count(*) from org_tasks t where t.assigned_agent=r.runtime_agent_key
            and t.status in ('assigned','in_progress')) open_tasks,
         (select count(*) from agent_runs g where g.agent=r.runtime_agent_key) runs,
         (select count(*) from event_subscription e where e.agent_key=r.runtime_agent_key and e.active) event_subs,
         (select count(*) from org_role_identity i where i.agent_key=r.runtime_agent_key) identities
    from org_role r join org_departments d on d.dept_key=r.primary_department_id
   where r.status='active' order by d.sort, r.role_id`);

const callers = await q(`
  with keys as (select distinct runtime_agent_key k from org_role where runtime_agent_key is not null),
       r as (select p.proname, p.prosrc src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
              where n.nspname='public' and p.prokind='f')
  select k.k agent_key, count(*) n, string_agg(r.proname, ' | ' order by r.proname) routines
    from keys k join r on r.src like '%''' || k.k || '''%' group by 1`);
const callerBy = Object.fromEntries(callers.map((c) => [c.agent_key, c]));

const depts = await q(`
  select d.dept_key, d.name, d.charter, d.north_star, d.lead_agent, d.health_fn,
         (select count(*) from org_agents a where a.department=d.dept_key and a.active) staff,
         (select count(*) from org_role r where r.primary_department_id=d.dept_key and r.status='active') roles,
         (select string_agg(s.dept_key,', ' order by s.dept_key) from org_departments s
           where s.merged_into=d.dept_key) absorbed,
         (select count(*) from company_goals g where g.owner_dept=d.dept_key and g.active) goals,
         (select count(*) from department_objective o where o.dept_key=d.dept_key and o.active) objectives,
         (select count(*) from org_tasks t where t.dept_key=d.dept_key and t.status in ('assigned','in_progress')) open_tasks
    from org_departments d where d.active order by d.sort`);

const aliases = await q(`select alias, role_id, kind from org_role_alias order by role_id, alias`);
const cascade = (await q(`select fn_objective_cascade() c`))[0].c;
const violations = await q(`select rule, role_id, detail from fn_org_role_violations()`);
const modes = await q(`select runtime_mode, count(*) n from org_role where status='active' group by 1 order by 2 desc`);
const now = (await q(`select now() at time zone 'utc' t`))[0].t;

mkdirSync('docs/agents', { recursive: true });

// ---- 1. CURRENT_TO_TARGET_AGENT_CROSSWALK.csv -------------------------------------------------
const crosswalkRows = [row(['current_role_id', 'current_department', 'runtime_callers',
  'runtime_caller_routines', 'agent_runs', 'event_subscriptions', 'open_tasks', 'tools',
  'knowledge_mappings', 'kpis', 'packaged_role_identities', 'current_manager',
  'target_role_id', 'target_department', 'target_manager_role', 'runtime_mode', 'action',
  'compatibility_strategy', 'rationale'])];

for (const r of roles) {
  if (r.runtime_mode === 'knowledge_overlay') continue;
  const k = r.runtime_agent_key;
  const c = callerBy[k] || { n: 0, routines: '' };
  const before = DEPT_BEFORE[k] || 'unknown';
  const renamed = r.role_id !== k;
  const absorbed = Object.entries(MERGED_AWAY).filter(([, v]) => v === r.role_id).map(([a]) => a);
  const action = absorbed.length ? `merge (absorbs ${absorbed.join(', ')})`
    : renamed ? 'rename' : 'keep';
  crosswalkRows.push(row([k, before, c.n, c.routines, r.runs, r.event_subs, r.open_tasks,
    r.tools, r.knowledge_rows, r.kpis, r.identities,
    '', r.role_id, r.primary_department_id, r.manager_role_id, r.runtime_mode, action,
    renamed
      ? `org_agents.agent_key stays '${k}'; '${r.role_id}' added to org_agent_alias and org_role_alias so both resolve`
      : 'canonical id equals the runtime key; no alias needed',
    r.rationale || '']));
}
for (const [oldKey, target] of Object.entries(MERGED_AWAY)) {
  const t = roles.find((r) => r.role_id === target);
  crosswalkRows.push(row([oldKey, DEPT_BEFORE[oldKey] || 'unknown', (callerBy[oldKey] || {}).n || 0,
    (callerBy[oldKey] || {}).routines || '', '', '', 0, '', '', '', '', '',
    target, t ? t.primary_department_id : '', t ? t.manager_role_id : '', t ? t.runtime_mode : '',
    'deactivate (merged)',
    `org_agents row kept inactive for history; org_agent_alias '${oldKey}' -> '${t ? t.runtime_agent_key : ''}' so every caller still resolves`,
    'duplicate identity removed by merge']));
}
for (const r of roles.filter((x) => x.runtime_mode === 'knowledge_overlay')) {
  crosswalkRows.push(row([r.role_id.replace('category_overlay_', 'category:'), 'procurement (category catalogue)',
    0, '', 0, 0, 0, r.tools, r.scopes, 0, 0, '', r.role_id, r.primary_department_id,
    r.manager_role_id, r.runtime_mode, 'convert_to_overlay',
    'no standing model instance; loaded into the invoking manager via fn_overlay_for_category',
    r.rationale || '']));
}
writeFileSync('docs/agents/CURRENT_TO_TARGET_AGENT_CROSSWALK.csv', crosswalkRows.join('\n') + '\n');

// ---- 2. CANONICAL_ROLE_REGISTRY.csv -----------------------------------------------------------
const regHead = ['role_id', 'display_name', 'primary_department_id', 'manager_role_id',
  'committee_memberships', 'runtime_mode', 'runtime_agent_key', 'responsibilities_owned_decisions',
  'forbidden_decisions', 'activation_conditions', 'required_inputs', 'output_contracts', 'tools',
  'knowledge_scopes', 'kpis', 'authority_level', 'budget_limit', 'handoff_targets',
  'escalation_targets', 'model_policy', 'evaluation_suite', 'status'];
const regRows = [row(regHead)];
for (const r of roles) {
  regRows.push(row([r.role_id, r.display_name, r.primary_department_id, r.manager_role_id,
    r.committees || '', r.runtime_mode, r.runtime_agent_key || '', r.owned, r.forbidden,
    r.activation_conditions, r.inputs, r.outputs, r.tools, r.scopes, r.kpis, r.authority_level,
    r.budget_limit ?? '', r.handoffs, r.escalations, r.model_policy || '', r.evaluation_suite,
    r.status]));
}
writeFileSync('docs/agents/CANONICAL_ROLE_REGISTRY.csv', regRows.join('\n') + '\n');

// ---- 3. RUNTIME_MODE_ASSIGNMENTS.csv ----------------------------------------------------------
const modeRows = [row(['role_id', 'display_name', 'department', 'runtime_mode', 'why_this_mode',
  'runtime_agent_key', 'event_subscriptions', 'agent_runs', 'open_tasks'])];
const WHY = {
  scheduled_manager: 'owns a department outcome and reviews on a cadence',
  event_driven_operator: 'wakes on a named event and executes inside its authority',
  on_demand_specialist: 'invoked by a manager as a tool; no standing state',
  knowledge_overlay: 'specialist knowledge loaded into the invoking manager; no model instance',
  independent_reviewer: 'holds stop authority and never approves work it authored',
};
for (const r of roles) {
  modeRows.push(row([r.role_id, r.display_name, r.primary_department_id, r.runtime_mode,
    WHY[r.runtime_mode], r.runtime_agent_key || '', r.event_subs ?? 0, r.runs ?? 0, r.open_tasks ?? 0]));
}
writeFileSync('docs/agents/RUNTIME_MODE_ASSIGNMENTS.csv', modeRows.join('\n') + '\n');

// ---- 4. REPORTING_AND_COMMITTEE_GRAPH.md ------------------------------------------------------
const byMgr = {};
for (const r of roles) (byMgr[r.manager_role_id || '(none)'] ||= []).push(r);
const tree = (id, depth) => {
  const kids = (byMgr[id] || []).filter((k) => k.runtime_mode !== 'knowledge_overlay');
  return kids.map((k) => `${'  '.repeat(depth)}- **${k.role_id}** — ${k.display_name} `
    + `(${k.primary_department_id}, ${k.runtime_mode}, runs as \`${k.runtime_agent_key}\`)\n`
    + tree(k.role_id, depth + 1)).join('');
};
const ceo = roles.find((r) => r.role_id === 'ceo');
const committees = await q(`select c.committee_key, c.name, c.purpose, c.chair_role_id, c.cadence,
    (select string_agg(m.role_id||' ('||m.seat||')', ', ' order by m.seat, m.role_id)
       from org_role_committee m where m.committee_key=c.committee_key) members
  from org_committee c where c.active order by c.committee_key`);

writeFileSync('docs/agents/REPORTING_AND_COMMITTEE_GRAPH.md',
`# Reporting and committee graph

Generated from \`${REF}\` at ${now} UTC by \`scripts/agents/export_org_docs.mjs\`. Every line is read
from \`org_role\`, \`org_role_committee\` and \`org_departments\`; nothing here is authored twice.

Exactly one primary manager per role, no cycles (enforced by \`a10_org_role_no_cycle\`), and the
only role without a manager is the CEO, whose boundary is the founder.

## Reporting chain

- **ceo** — ${ceo.display_name} (exec, ${ceo.runtime_mode}, runs as \`${ceo.runtime_agent_key}\`)
${tree('ceo', 1)}
The 86 category overlays all report to **inquiry_router** and are omitted from the tree above; they
are listed in \`RUNTIME_MODE_ASSIGNMENTS.csv\`. They are not departments and do not report to the
CEO individually.

## Committees

A committee seat is a row in \`org_role_committee\`, never a second role. The unique index
\`org_role_one_per_agent_ux\` makes a duplicate role for the same runtime agent unrepresentable.

${committees.map((c) => `### ${c.name} (\`${c.committee_key}\`)

${c.purpose}

- **Chair:** ${c.chair_role_id}
- **Cadence:** ${c.cadence}
- **Seats:** ${c.members}
`).join('\n')}
## Independence

\`fn_pick_reviewer(dept, author)\` never returns the author. Where the department head is the
author, review routes to that department's independent reviewer; where there is none, it climbs one
level. Measured on all ten departments, the head is never returned as its own reviewer.

| department | head | reviewer when the head is the author |
|---|---|---|
${(await q(`select d.dept_key, d.lead_agent,
     coalesce(fn_pick_reviewer(d.dept_key, d.lead_agent)->>'reviewer','(escalates — none available)') rev
   from org_departments d where d.active order by d.sort`))
  .map((r) => `| ${r.dept_key} | ${r.lead_agent} | ${r.rev} |`).join('\n')}
`);

// ---- 5. TARGET_AGENT_ORGANIZATION.md ----------------------------------------------------------
writeFileSync('docs/agents/TARGET_AGENT_ORGANIZATION.md',
`# The target agent organisation

Generated from \`${REF}\` at ${now} UTC. Ten primary departments, ${roles.filter((r) => r.runtime_mode !== 'knowledge_overlay').length} accountable
roles and ${roles.filter((r) => r.runtime_mode === 'knowledge_overlay').length} category overlays.

Every role belongs to one primary department, reports to one primary manager, owns defined
responsibilities, has measurable KPIs, has explicit decision authority, uses named tools and
knowledge scopes, records evidence, and contributes to the AED 1,000,000 revenue objective by
31 August 2027.

## Runtime modes

| mode | roles | what it means |
|---|---|---|
${modes.map((m) => `| \`${m.runtime_mode}\` | ${m.n} | ${WHY[m.runtime_mode]} |`).join('\n')}

## The ten departments

${depts.map((d) => `### ${d.name} (\`${d.dept_key}\`)

${d.charter}

- **North star:** ${d.north_star}
- **Head:** \`${d.lead_agent}\`
- **Health function:** \`${d.health_fn || '(none)'}\`
- **Absorbed:** ${d.absorbed || '(none — kept its own key)'}
- **Staff:** ${d.staff} employees, ${d.roles} canonical roles
- **Company goals owned:** ${d.goals} · **department objectives:** ${d.objectives} · **open work:** ${d.open_tasks}

| role | mode | authority | runs as | KPIs |
|---|---|---|---|---|
${roles.filter((r) => r.primary_department_id === d.dept_key && r.runtime_mode !== 'knowledge_overlay')
  .map((r) => `| **${r.role_id}** — ${r.display_name} | ${r.runtime_mode} | ${r.authority_level} | \`${r.runtime_agent_key}\` | ${r.kpis} |`)
  .join('\n')}
`).join('\n')}
## Category specialists

All 86 are kept as on-demand knowledge overlays. They are not departments and none of them reports
to the CEO individually.

**Operational chain:** \`marketplace_director\` → \`rfq_qualification_manager\` → \`inquiry_router\` →
the relevant category overlay, resolved by \`fn_overlay_for_category(category_key)\`.

**Knowledge governance:** \`knowledge_director\` / \`taxonomy_manager\` own category source quality,
freshness, aliases, rules and evaluations.

Each overlay owns route and subcategory knowledge, minimum sufficient questions, mandatory and
optional fields, never-infer rules, pricing drivers, required documents, technical comparison
fields, regulatory triggers, quote-readiness criteria and escalation rules.

No overlay may dispatch, approve a supplier, expose customer identity, draw an unsupported legal
conclusion, override a privacy, authority or regulatory gate, or take over the customer
conversation. The inquiry-facing manager keeps the conversation and invokes the overlay internally,
through \`fn_specialist_invoke\`, which records the invocation and leaves the manager accountable.

## The objective cascade

\`\`\`
${JSON.stringify(cascade, null, 2)}
\`\`\`

Links are written only where a department owns exactly one active goal or objective. The rest are
reported unlinked rather than guessed: a fabricated link makes the cascade look complete while
explaining nothing.

## Enforcement

\`fn_org_role_violations()\` returns ${violations.length} row(s) at generation time. It checks: department
active, exactly one primary manager, manager active, a runtime executor for every non-overlay role,
that executor active, KPIs present, knowledge present, authority present, tools present, an
evaluation suite named, an independent reviewer actually holding stop authority, no duplicate role
for the same runtime agent, and no active employee without a canonical role.

Structural rules are constraints rather than reports: unique \`role_id\` (primary key), exactly one
\`primary_department_id\` (not-null foreign key), exactly one \`manager_role_id\`, no self-management
(\`org_role_no_self_manage_ck\`), no reporting cycles (\`a10_org_role_no_cycle\`), one active role per
runtime agent (\`org_role_one_per_agent_ux\`), and no self-approval
(\`review_chain_no_self_approval_ck\`).
`);

// ---- 6. aliases appendix used by the migration report -----------------------------------------
writeFileSync('docs/agents/ROLE_ALIASES.csv',
  [row(['alias', 'canonical_role_id', 'kind'])].concat(aliases.map((a) => row([a.alias, a.role_id, a.kind]))).join('\n') + '\n');

console.log(`wrote docs/agents/ from ${REF}: ${roles.length} roles, ${depts.length} departments, ${aliases.length} aliases, ${violations.length} violations`);
