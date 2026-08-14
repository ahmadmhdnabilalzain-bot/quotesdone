// Load the reconciled roster into the runtime: department alias, role identity, category
// identity. Reads docs/knowledge/V3_ROLE_IDENTITY.json, which v3_crosswalk.mjs produced.
//
//   node scripts/kb/v3_identity_load.mjs --ref=<project>
import fs from 'node:fs';
import { mgmtRead, mgmtWriteData, PROD_REF } from '../staging/qd_guard.mjs';

const refArg = process.argv.find((a) => a.startsWith('--ref='));
const REF = refArg ? refArg.slice(6) : PROD_REF;
const IS_PROD = REF === PROD_REF;
const TOKEN = (process.env.SUPABASE_ACCESS_TOKEN
  || fs.readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

async function prodPost(sql) {
  for (let attempt = 0; ; attempt++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: sql }),
    });
    const body = await r.text();
    if (r.ok) return body ? JSON.parse(body) : null;
    if (r.status === 429 && attempt < 8) { await new Promise((s) => setTimeout(s, Math.min(30000, 2000 * 2 ** attempt))); continue; }
    throw new Error(`production query failed ${r.status}: ${body.slice(0, 300)}`);
  }
}
const write = (sql, where) => (IS_PROD ? prodPost(sql) : mgmtWriteData(REF, sql, where));
const q = (v) => (v === null || v === undefined) ? 'null' : `'${String(v).replace(/'/g, "''")}'`;

const j = JSON.parse(fs.readFileSync('docs/knowledge/V3_ROLE_IDENTITY.json', 'utf8'));

// department alias
const aliasRows = [];
for (const [pkg, dept] of Object.entries(j.department_alias)) aliasRows.push([pkg, dept, false]);
for (const [pkg, dept] of Object.entries(j.second_home || {})) aliasRows.push([pkg, dept, true]);
await write(`insert into org_department_alias (packaged_department, dept_key, is_second_home)
  values ${aliasRows.map((r) => `(${q(r[0])},${q(r[1])},${r[2]})`).join(',')}
  on conflict (packaged_department, dept_key) do update set is_second_home = excluded.is_second_home`,
  'department alias');

// role identity — one row per (agent, packaged role)
const seen = new Set();
const idRows = j.identity.filter((r) => {
  const k = `${r.agent_key}|${r.packaged_role_id}`;
  if (seen.has(k)) return false; seen.add(k); return true;
});
for (let i = 0; i < idRows.length; i += 100) {
  const part = idRows.slice(i, i + 100);
  await write(`insert into org_role_identity
      (agent_key, packaged_role_id, packaged_department, archetype, mapping_type, readiness, package_version)
    values ${part.map((r) => `(${q(r.agent_key)},${q(r.packaged_role_id)},${q(r.packaged_department)},${q(r.archetype)},${q(r.mapping_type)},'knowledge_imported','2026.08.14')`).join(',')}
    on conflict (agent_key, packaged_role_id) do update set
      packaged_department = excluded.packaged_department,
      archetype = excluded.archetype,
      mapping_type = excluded.mapping_type,
      updated_at = now()`, 'role identity');
}

// category identity — the 86 packaged specialists bound to the existing route catalogue
const routes = await mgmtRead(REF, 'select catalog_num, route_key from kb_operational_route');
const byNum = new Map(routes.map((r) => [Number(r.catalog_num), r.route_key]));
const catRows = j.categories.map((c) => ({ key: c, num: Number(c.slice(0, 3)) }))
  .filter((c) => byNum.has(c.num));
await write(`insert into org_category_identity (category_key, catalog_num, route_key, owner_agent, readiness)
  values ${catRows.map((c) => `(${q(c.key)},${c.num},${q(byNum.get(c.num))},null,'knowledge_imported')`).join(',')}
  on conflict (category_key) do update set catalog_num = excluded.catalog_num,
    route_key = excluded.route_key, updated_at = now()`, 'category identity');

const counts = await mgmtRead(REF, `select
  (select count(*) from org_department_alias) alias,
  (select count(*) from org_role_identity) identity,
  (select count(distinct agent_key) from org_role_identity) agents,
  (select count(distinct packaged_role_id) from org_role_identity) roles,
  (select count(*) from org_category_identity) categories,
  (select count(*) from org_agents a where a.active
     and not exists (select 1 from org_role_identity i where i.agent_key = a.agent_key)) active_without_identity`);
console.log(JSON.stringify({ ref: REF, ...counts[0] }, null, 2));
