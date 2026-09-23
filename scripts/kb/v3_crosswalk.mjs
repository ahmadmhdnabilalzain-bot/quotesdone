// Stage 2 — reconcile the 96 packaged role identities against the runtime roster.
// Reads the live org_agents/org_departments tables and the packaged canonical roster,
// and writes docs/knowledge/V3_RUNTIME_ROLE_CROSSWALK.csv.
//
// Usage: node scripts/kb/v3_crosswalk.mjs <extracted-root> [--ref=<project>]
import fs from 'node:fs';
import path from 'node:path';
import { mgmtRead, PROD_REF } from '../lib/qd_guard.mjs';
import { walk } from './v3_package.mjs';

const root = process.argv[2];
const refArg = process.argv.find((a) => a.startsWith('--ref='));
const REF = refArg ? refArg.slice(6) : PROD_REF;
if (!root) { console.error('usage: v3_crosswalk.mjs <extracted-root> [--ref=]'); process.exit(2); }

// ---- packaged roster -------------------------------------------------------
const rosterCsv = walk(root).find((f) => f.endsWith('CANONICAL_96_ROLE_ROSTER.csv'));
if (!rosterCsv) { console.error('CANONICAL_96_ROLE_ROSTER.csv not found under ' + root); process.exit(1); }
const lines = fs.readFileSync(rosterCsv, 'utf8').trim().split(/\r?\n/);
const head = splitCsv(lines[0]);
const packaged = lines.slice(1).map((l) => Object.fromEntries(splitCsv(l).map((v, i) => [head[i], v])));

function splitCsv(line) {
  const out = []; let cur = '', q = false;
  for (const ch of line) {
    if (ch === '"') q = !q;
    else if (ch === ',' && !q) { out.push(cur); cur = ''; }
    else cur += ch;
  }
  out.push(cur); return out;
}

// packaged departments come from the role ids' department column
const pkgDepts = [...new Set(packaged.map((r) => r.department))].sort();

// packaged categories from the category_specialist directories
const catDirs = [...new Set(walk(root)
  .map((f) => f.replace(/\\/g, '/'))
  .filter((f) => f.includes('/category_specialists/'))
  .map((f) => {
    const after = f.split('/category_specialists/')[1].split('/').filter((s) => s !== 'routes');
    return /^\d{3}_/.test(after[0]) ? after[0] : null;
  })
  .filter(Boolean))].sort();

// ---- runtime ---------------------------------------------------------------
const agents = await mgmtRead(REF, `select agent_key, department, role, kind, active, title, manager_key, seniority,
  coalesce(routing_tier,'') routing_tier, max_open_tasks from org_agents order by department, agent_key`);
const depts = await mgmtRead(REF, `select dept_key, name, active, lead_agent, brain_agent from org_departments order by dept_key`);
const routes = await mgmtRead(REF, `select catalog_num, route_key, catalog_name, coverage_status from kb_operational_route order by catalog_num`);
const taskCounts = await mgmtRead(REF, `select assigned_agent agent_key, count(*) n from org_tasks where assigned_agent is not null group by 1`);
const runCounts = await mgmtRead(REF, `select agent, count(*) n, max(started_at) last_run from agent_runs group by 1`);
const execs = await mgmtRead(REF, `select target, action_class, kind from org_action_executor where active`);
const knowledgeCounts = await mgmtRead(REF, `select agent_key, count(*) n from agent_knowledge group by 1`);

const byKey = new Map(agents.map((a) => [a.agent_key, a]));
const tasksBy = new Map(taskCounts.map((r) => [r.agent_key, Number(r.n)]));
const runsBy = new Map(runCounts.map((r) => [r.agent, { n: Number(r.n), last: r.last_run }]));
const knowBy = new Map(knowledgeCounts.map((r) => [r.agent_key, Number(r.n)]));
const execBy = new Map();
for (const e of execs) {
  if (!execBy.has(e.target)) execBy.set(e.target, []);
  execBy.get(e.target).push(e.action_class);
}

// ---- normalisation ---------------------------------------------------------
const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
const ARCHETYPE = ['director', 'operations-specialist', 'analyst-controller', 'reviewer-auditor'];

function archetypeOf(roleId) {
  for (const a of ARCHETYPE) if (roleId.endsWith('-' + a)) return a;
  return 'other';
}

// The packaged department vocabulary and the runtime one are two names for the
// same 24 departments — decided by reading each runtime charter, not by string
// similarity. `knowledge` is process/coordination/document control (admin_operations);
// `knowledge_eng` owns the KB, retrieval and the exam loop (knowledge_learning);
// `procurement` runs intake->match->quote->reveal (marketplace_operations).
export const DEPT_ALIAS = {
  executive_office: 'exec', strategy_evolution: 'evolution', supplier_success: 'supplier_success',
  customer_success: 'customer_success', rfq_intelligence: 'rfq_intelligence',
  marketplace_operations: 'procurement', sales_crm: 'sales', marketing: 'marketing',
  finance: 'finance', legal_compliance: 'legal', hr_people: 'hr', admin_operations: 'knowledge',
  engineering: 'engineering', ai_model_ops: 'ai_dept', it_cybersecurity: 'it',
  data_analytics: 'analytics', qa_testing: 'qa', business_development: 'bizdev',
  supplier_knowledge: 'supplier_knowledge', document_intelligence: 'doc_intelligence',
  communications: 'comms', payments_revenue: 'payments', trust_safety: 'trust_safety',
  knowledge_learning: 'knowledge_eng',
};
// `intelligence` (market/competitive/supplier/customer intelligence + forecasting) is a
// runtime department the package does not model separately; it shares the data_analytics
// professional corpus. One packaged department therefore covers two runtime departments.
const SECOND_HOME = { data_analytics: 'intelligence' };

// Which of the four packaged archetypes does a runtime agent actually perform?
// Read from what the agent is, not from its department's shape.
const RE_ANALYST = /(analyst|analytics|bi_|forecast|bookkeep|financial|scoring|evaluation|coverage|intel|process_improvement|optimisation)/;
const RE_REVIEWER = /(valid|verif|qa|test|moderat|fraud|risk|complian|security|review|audit|trust)/;

// Exactly one director per runtime department — the department's own lead agent,
// or failing that the most senior. Calling every `*_mgr` a director would leave a
// department with three directors and no specialist, which is not what it does.
const SENIORITY_RANK = { executive: 6, chief: 5, director: 4, lead: 3, senior: 2, manager: 2, specialist: 1 };
const directorOf = new Map();

function runtimeArchetype(a) {
  if (directorOf.get(a.department) === a.agent_key) return 'director';
  if (RE_REVIEWER.test(a.agent_key)) return 'reviewer-auditor';
  if (RE_ANALYST.test(a.agent_key)) return 'analyst-controller';
  return 'operations-specialist';
}

// runtime agent index by runtime department key
const runtimeByDept = new Map();
for (const a of agents) {
  if (!runtimeByDept.has(a.department)) runtimeByDept.set(a.department, []);
  runtimeByDept.get(a.department).push(a);
}
for (const [dept, list] of runtimeByDept) {
  const lead = depts.find((d) => d.dept_key === dept);
  const byLead = list.find((a) => a.agent_key === (lead && lead.lead_agent));
  const best = byLead || [...list].sort((x, y) =>
    (SENIORITY_RANK[y.seniority] || 0) - (SENIORITY_RANK[x.seniority] || 0))[0];
  if (best) directorOf.set(dept, best.agent_key);
}

const rows = [];
const claimed = new Map();   // runtime agent_key -> [packaged role ids]
const identity = [];         // rows for the org_role_identity table

for (const p of packaged) {
  const roleId = p.agent_key;
  const dept = p.department;
  const arche = archetypeOf(roleId);
  const runtimeDepts = [DEPT_ALIAS[dept], SECOND_HOME[dept]].filter(Boolean);
  let cands = runtimeDepts.flatMap((d) => runtimeByDept.get(d) || []);

  // agents of this department that perform this archetype
  let matches = cands.filter((c) => runtimeArchetype(c) === arche);

  // No agent performs the archetype: the department director carries it as a
  // second hat rather than the company hiring a 4th agent for a 3-agent department.
  let mappingType;
  if (matches.length === 0) {
    const dirs = cands.filter((c) => runtimeArchetype(c) === 'director');
    matches = dirs.length ? [dirs[0]] : cands.slice(0, 1);
    mappingType = matches.length ? 'runtime_composite' : 'missing_runtime_agent';
  } else if (matches.length === 1) {
    mappingType = runtimeDepts.length > 1 ? 'package_composite' : 'one_to_one';
  } else {
    mappingType = 'package_composite';   // one packaged role, several runtime agents
  }

  for (const m of matches) {
    if (!claimed.has(m.agent_key)) claimed.set(m.agent_key, []);
    claimed.get(m.agent_key).push(roleId);
    identity.push({ agent_key: m.agent_key, packaged_role_id: roleId, packaged_department: dept, archetype: arche, mapping_type: mappingType });
  }

  const m = matches[0] || null;
  rows.push({
    packaged_department: dept,
    packaged_role_id: roleId,
    runtime_agent_id: matches.map((x) => x.agent_key).join('|'),
    agent_name: m ? (m.title || m.role || '') : '',
    department: m ? m.department : '',
    manager: m ? (m.manager_key || '') : (p.manager || ''),
    runtime_entry_point: m ? entryPoint(m) : '',
    tools_available: m ? (execBy.get(m.agent_key) || []).join('|') : '',
    tasks_received: matches.reduce((s, x) => s + (tasksBy.get(x.agent_key) || 0), 0),
    runs: matches.reduce((s, x) => s + (runsBy.get(x.agent_key)?.n || 0), 0),
    current_kpis: m ? (m.seniority || '') : '',
    current_knowledge_records: matches.reduce((s, x) => s + (knowBy.get(x.agent_key) || 0), 0),
    mapping_type: mappingType,
    implementation_action: mappingType === 'runtime_composite'
      ? 'director carries this archetype as a second identity; no new agent'
      : mappingType === 'package_composite'
        ? 'one packaged role identity shared by several runtime agents'
        : mappingType === 'missing_runtime_agent'
          ? 'no runtime agent in this department performs this archetype'
          : 'direct identity',
  });
}

// A runtime agent that no packaged role claimed still has to have an identity —
// give it its department archetype so no active agent runs without one.
const unmatchedRuntime = new Set(agents.filter((a) => !claimed.has(a.agent_key)).map((a) => a.agent_key));

function entryPoint(a) {
  // Every runtime agent is dispatched by exec_agents (cron fan-out) or dept_plan
  // (department planning); brain agents additionally answer through agent_brain.
  const parts = ['exec_agents'];
  if (depts.some((d) => d.brain_agent === a.agent_key)) parts.push('agent_brain');
  if (depts.some((d) => d.lead_agent === a.agent_key)) parts.push('dept_plan');
  return parts.join('|');
}

// Runtime agents no packaged role claimed: attach the department's archetype
// identity anyway, so every active agent maps to at least one approved role.
const REV_ALIAS = Object.fromEntries(Object.entries(DEPT_ALIAS).map(([k, v]) => [v, k]));
REV_ALIAS.intelligence = 'data_analytics';
for (const key of unmatchedRuntime) {
  const a = byKey.get(key);
  const pkgDept = REV_ALIAS[a.department] || '';
  const arche = runtimeArchetype(a);
  const roleId = pkgDept ? `${pkgDept.replace(/_/g, '-')}-${arche}` : '';
  const known = pkgDept && packaged.some((p) => p.agent_key === roleId);
  const type = !a.active ? 'obsolete_runtime_agent' : known ? 'package_composite' : 'duplicate_role';
  if (a.active && pkgDept) {
    identity.push({ agent_key: a.agent_key, packaged_role_id: known ? roleId : `${pkgDept}:${arche}`, packaged_department: pkgDept, archetype: arche, mapping_type: type });
  }
  rows.push({
    packaged_department: pkgDept, packaged_role_id: known ? roleId : '',
    runtime_agent_id: a.agent_key, agent_name: a.title || a.role || '',
    department: a.department, manager: a.manager_key || '',
    runtime_entry_point: entryPoint(a), tools_available: (execBy.get(a.agent_key) || []).join('|'),
    tasks_received: tasksBy.get(a.agent_key) || 0, runs: runsBy.get(a.agent_key)?.n || 0,
    current_kpis: a.seniority || '', current_knowledge_records: knowBy.get(a.agent_key) || 0,
    mapping_type: type,
    implementation_action: !a.active ? 'inactive; no identity assigned'
      : `shares the ${pkgDept} ${arche} identity`,
  });
}

// category specialists are on-demand identities, not standing agents
for (const c of catDirs) {
  const num = Number(c.slice(0, 3));
  const route = routes.find((r) => Number(r.catalog_num) === num);
  rows.push({
    packaged_department: 'marketplace_category_experts',
    packaged_role_id: c,
    runtime_agent_id: route ? `route:${route.route_key}` : '',
    agent_name: route ? route.catalog_name : '',
    department: 'marketplace', manager: 'category-intelligence-director',
    runtime_entry_point: route ? 'route_inquiry|kb_route_test_run' : '',
    tools_available: 'kb_match|kb_query', tasks_received: 0, runs: 0,
    current_kpis: route ? route.coverage_status : '',
    current_knowledge_records: 0,
    mapping_type: route ? 'on_demand_specialist' : 'missing_runtime_agent',
    implementation_action: '',
  });
}

const cols = ['packaged_department', 'packaged_role_id', 'runtime_agent_id', 'agent_name', 'department', 'manager',
  'runtime_entry_point', 'tools_available', 'tasks_received', 'runs', 'current_kpis',
  'current_knowledge_records', 'mapping_type', 'implementation_action'];
const csv = [cols.join(',')].concat(rows.map((r) => cols.map((c) => csvCell(r[c])).join(','))).join('\n');
function csvCell(v) { const s = String(v ?? ''); return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; }

const outDir = path.join(process.cwd(), 'docs', 'knowledge');
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'V3_RUNTIME_ROLE_CROSSWALK.csv'), csv + '\n');
fs.writeFileSync(path.join(outDir, 'V3_ROLE_IDENTITY.json'), JSON.stringify({
  generated_from_ref: REF, department_alias: DEPT_ALIAS, second_home: SECOND_HOME,
  categories: catDirs, identity,
}, null, 2));

const tally = {};
for (const r of rows) tally[r.mapping_type] = (tally[r.mapping_type] || 0) + 1;
console.log(JSON.stringify({
  ref: REF, packaged_roles: packaged.length, packaged_departments: pkgDepts.length,
  packaged_categories: catDirs.length,
  runtime_agents: agents.length, runtime_active: agents.filter((a) => a.active).length,
  runtime_departments: depts.length, runtime_routes: routes.length,
  mapping: tally,
  packaged_depts_unresolved: pkgDepts.filter((d) => !DEPT_ALIAS[d] || !runtimeByDept.has(DEPT_ALIAS[d])),
  runtime_depts_without_packaged_dept: depts.map((d) => d.dept_key)
    .filter((d) => !Object.values(DEPT_ALIAS).includes(d) && !Object.values(SECOND_HOME).includes(d)),
  agents_without_identity: agents.filter((a) => a.active && !identity.some((i) => i.agent_key === a.agent_key)).map((a) => a.agent_key),
}, null, 2));
