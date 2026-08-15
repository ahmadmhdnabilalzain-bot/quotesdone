// PHASE A — the organization fingerprint, on its own so the same code produces the pre-change,
// post-rehearsal and post-deployment values. A fingerprint computed two different ways proves
// nothing.
//
//   node scripts/phase_a/fingerprint.mjs                 # print it
//   node scripts/phase_a/fingerprint.mjs --compare <file> # compare against a saved one
//   node scripts/phase_a/fingerprint.mjs --save <file>
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';

const sha = (s) => createHash('sha256').update(String(s)).digest('hex');
const argv = process.argv.slice(2);
const arg = (k) => { const i = argv.indexOf(`--${k}`); return i < 0 ? null : argv[i + 1]; };

const live = {};
live.depts = await mgmtRead(PROD_REF, `select dept_key, name, active, lead_agent from org_departments order by dept_key`);
live.roles = await mgmtRead(PROD_REF, `select role_id, display_name, primary_department_id, manager_role_id,
    runtime_mode, runtime_agent_key, status, evaluation_suite,
    coalesce(array_length(owned_decisions,1),0) n_owned,
    coalesce(array_length(forbidden_decisions,1),0) n_forbidden
  from org_role order by role_id`);
live.cats = await mgmtRead(PROD_REF, `select category_key from org_category_identity order by 1`);
live.flows = await mgmtRead(PROD_REF, `select workflow_key, step_no, step, actor_role from workflow_step order by workflow_key, step_no`);
live.reserved = await mgmtRead(PROD_REF, `select decision_key from founder_reserved_decision order by 1`);
live.agents = await mgmtRead(PROD_REF, `select agent_key, department, active, manager_key from org_agents order by agent_key`);

const src = {
  departments: live.depts.map(d => `${d.dept_key}|${d.name}|${d.active}|${d.lead_agent ?? ''}`),
  roles: live.roles.map(r => `${r.role_id}|${r.display_name}|${r.primary_department_id}|${r.manager_role_id ?? ''}`
    + `|${r.runtime_mode}|${r.runtime_agent_key ?? ''}|${r.status}|${r.evaluation_suite ?? ''}|${r.n_owned}|${r.n_forbidden}`),
  categories: live.cats.map(c => c.category_key),
  workflow_steps: live.flows.map(f => `${f.workflow_key}|${f.step_no}|${f.step}|${f.actor_role ?? ''}`),
  reserved: live.reserved.map(r => r.decision_key),
  agents: live.agents.map(a => `${a.agent_key}|${a.department}|${a.active}|${a.manager_key ?? ''}`),
};
const fp = {};
for (const [k, v] of Object.entries(src)) fp[k] = { rows: v.length, sha256: sha(v.join('\n')) };
fp.ORGANIZATION = { rows: Object.values(src).reduce((n, v) => n + v.length, 0),
  sha256: sha(Object.entries(src).map(([k, v]) => `${k}\n${v.join('\n')}`).join('\n--\n')) };

for (const [k, v] of Object.entries(fp)) console.log(`${k.padEnd(16)} rows=${String(v.rows).padStart(4)}  ${v.sha256}`);

const save = arg('save');
if (save) { writeFileSync(save, JSON.stringify({ fingerprint: fp }, null, 2) + '\n'); console.log(`\nsaved ${save}`); }

const cmp = arg('compare');
if (cmp) {
  const was = JSON.parse(readFileSync(cmp, 'utf8')).fingerprint;
  const changed = Object.keys(fp).filter(k => !was[k] || was[k].sha256 !== fp[k].sha256);
  console.log('');
  if (!changed.length) { console.log(`UNCHANGED against ${cmp} — every subject digest matches.`); process.exitCode = 0; }
  else {
    console.log(`CHANGED against ${cmp}:`);
    for (const k of changed) console.log(`  ${k}: ${was[k]?.rows ?? '-'} rows ${was[k]?.sha256 ?? '(absent)'}\n${' '.repeat(2 + k.length + 2)}-> ${fp[k].rows} rows ${fp[k].sha256}`);
    process.exitCode = 1;
  }
}
