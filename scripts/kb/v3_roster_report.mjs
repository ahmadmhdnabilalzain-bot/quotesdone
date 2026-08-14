// The company roster: every department, every AI employee, and the packaged role identity
// each one holds. Generated from the live tables, never hand-maintained.
//
//   node scripts/kb/v3_roster_report.mjs [--ref=<project>]
import fs from 'node:fs';
import path from 'node:path';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';

const refArg = process.argv.find((a) => a.startsWith('--ref='));
const REF = refArg ? refArg.slice(6) : PROD_REF;

const depts = await mgmtRead(REF, `select dept_key, name, charter, north_star, lead_agent, active,
  (select count(*) from org_agents a where a.department = d.dept_key and a.active) n_active,
  (select count(*) from org_agents a where a.department = d.dept_key and not a.active) n_inactive
  from org_departments d order by n_active desc, dept_key`);

const agents = await mgmtRead(REF, `select a.agent_key, a.department, a.title, a.role, a.seniority,
  a.manager_key, a.active, a.max_open_tasks,
  (select string_agg(distinct i.archetype, ', ' order by i.archetype) from org_role_identity i where i.agent_key = a.agent_key) archetypes,
  (select min(i.packaged_department) from org_role_identity i where i.agent_key = a.agent_key) pkg_dept,
  (select string_agg(distinct i.mapping_type, ', ') from org_role_identity i where i.agent_key = a.agent_key) mapping,
  (select string_agg(distinct i.readiness, ', ') from org_role_identity i where i.agent_key = a.agent_key) readiness,
  (select count(*) from agent_runs r where r.agent = a.agent_key) runs,
  (select count(*) from org_tasks t where t.assigned_agent = a.agent_key) tasks
  from org_agents a order by a.department, a.agent_key`);

const cats = await mgmtRead(REF, `select c.category_key, c.catalog_num, c.route_key, r.catalog_name, c.readiness
  from org_category_identity c join kb_operational_route r on r.catalog_num = c.catalog_num
  order by c.catalog_num`);

const byDept = new Map();
for (const a of agents) {
  if (!byDept.has(a.department)) byDept.set(a.department, []);
  byDept.get(a.department).push(a);
}

const ARCH_ORDER = { director: 0, 'analyst-controller': 1, 'reviewer-auditor': 2, 'operations-specialist': 3 };
const firstArch = (a) => String(a.archetypes || '').split(',')[0].trim();

let md = `# QuotesDone — the company roster\n\n`;
md += `Generated ${new Date().toISOString().slice(0, 10)} from \`${REF}\` by \`scripts/kb/v3_roster_report.mjs\`.\n`;
md += `Never hand-maintained: re-run it and it tells you what is actually there.\n\n`;
md += `**${agents.filter((a) => a.active).length} active AI employees** across **${depts.filter((d) => d.active).length} departments**, `;
md += `plus **${cats.length} on-demand category specialists** that are overlays on the route catalogue rather than standing agents.\n\n`;
md += `An agent can hold more than one packaged role identity: where a department has no separate\n`;
md += `analyst or reviewer, its director carries that archetype as a second hat. That is why the\n`;
md += `archetype column sometimes lists two or three.\n\n`;

for (const d of depts) {
  const list = (byDept.get(d.dept_key) || []).sort((x, y) =>
    (ARCH_ORDER[firstArch(x)] ?? 9) - (ARCH_ORDER[firstArch(y)] ?? 9) || x.agent_key.localeCompare(y.agent_key));
  if (!list.length) continue;
  md += `## ${d.name}\n\n`;
  md += `\`${d.dept_key}\` — packaged as \`${list[0].pkg_dept || '—'}\` · ${d.n_active} active`;
  md += d.n_inactive ? ` (${d.n_inactive} inactive)\n\n` : `\n\n`;
  if (d.charter) md += `> ${String(d.charter).replace(/\s+/g, ' ').trim()}\n\n`;
  md += `| agent | role | archetype | manager | runs | tasks | readiness |\n|---|---|---|---|---|---|---|\n`;
  for (const a of list) {
    md += `| \`${a.agent_key}\`${a.active ? '' : ' *(inactive)*'} | ${a.title || a.role || ''} | ${a.archetypes || '—'} `;
    md += `| ${a.manager_key || '—'} | ${a.runs} | ${a.tasks} | ${a.readiness || '—'} |\n`;
  }
  md += `\n`;
}

md += `## On-demand category specialists\n\n`;
md += `These are the 86 packaged category identities. They are not standing agents — the company\n`;
md += `does not run 182 employees. Each is an overlay retrieved at inquiry time by\n`;
md += `\`fn_category_checklist\`, and each owns its own question bank, mandatory-field list and\n`;
md += `never-infer list.\n\n`;
md += `| # | route | category identity | readiness |\n|---|---|---|---|\n`;
for (const c of cats) md += `| ${c.catalog_num} | \`${c.route_key}\` | ${c.catalog_name} | ${c.readiness} |\n`;

const outDir = path.join(process.cwd(), 'docs', 'knowledge');
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'COMPANY_ROSTER.md'), md);

console.log(`docs/knowledge/COMPANY_ROSTER.md — ${agents.filter((a) => a.active).length} active agents, ` +
  `${depts.filter((d) => d.active).length} departments, ${cats.length} category identities`);
for (const d of depts) {
  const list = byDept.get(d.dept_key) || [];
  if (!list.length) continue;
  console.log(`  ${String(d.n_active).padStart(2)}  ${d.dept_key.padEnd(20)} ${d.name}`);
}
