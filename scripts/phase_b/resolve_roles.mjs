// Measure: does every role token the Phase B package addresses resolve to a live,
// active canonical role?
//
// This is the question that decides whether Phase B touches frozen Phase A at all.
// The package addresses roles by descriptive name (`payments_billing_manager`);
// the frozen organization stores them under its own keys (`payments_and_billing_manager`).
// Resolution order is: exact role_id -> org_role_alias -> declared dynamic placeholder.
// Anything left over is a real gap and is printed as one.
import { loadPackage, collectRoleRefs, DECLARED_COUNTS } from './lib/package.mjs';
import { sql } from './lib/db.mjs';

const pkg = loadPackage();
for (const [k, want] of Object.entries(DECLARED_COUNTS)) {
  if (pkg[k].length !== want) {
    console.error(`COUNT MISMATCH ${k}: ${pkg[k].length} != ${want}`);
    process.exit(1);
  }
}

const refs = collectRoleRefs(pkg);
const tokens = [...refs.keys()].sort();

const roles = await sql(`select role_id, display_name, status, runtime_mode, primary_department_id
                         from public.org_role order by role_id`);
const aliases = await sql(`select alias, role_id, kind from public.org_role_alias`);

const byId = new Map(roles.map(r => [r.role_id, r]));
const byAlias = new Map();
for (const a of aliases) if (!byAlias.has(a.alias)) byAlias.set(a.alias, a);
const placeholders = new Set(pkg.placeholders.map(p => p.placeholder_id));

const out = { exact: [], alias: [], placeholder: [], unresolved: [], inactive: [], overlay: [] };
for (const t of tokens) {
  const src = [...refs.get(t)].sort().join(',');
  if (byId.has(t)) {
    const r = byId.get(t);
    if (r.status !== 'active') out.inactive.push({ token: t, status: r.status, src });
    else if (r.runtime_mode === 'knowledge_overlay') out.overlay.push({ token: t, src });
    else out.exact.push({ token: t, src });
  } else if (byAlias.has(t)) {
    const a = byAlias.get(t);
    const r = byId.get(a.role_id);
    if (!r) out.unresolved.push({ token: t, src, note: `alias -> missing role ${a.role_id}` });
    else if (r.status !== 'active') out.inactive.push({ token: t, status: r.status, src, via: a.role_id });
    else out.alias.push({ token: t, role_id: a.role_id, kind: a.kind, src });
  } else if (placeholders.has(t)) {
    out.placeholder.push({ token: t, src });
  } else {
    out.unresolved.push({ token: t, src });
  }
}

console.log(JSON.stringify({
  tokens: tokens.length,
  exact: out.exact.length,
  alias: out.alias.length,
  placeholder: out.placeholder.length,
  overlay: out.overlay.length,
  inactive: out.inactive.length,
  unresolved: out.unresolved.length,
}, null, 2));
console.log('\n-- UNRESOLVED --');
for (const u of out.unresolved) console.log(`${u.token}\t${u.src}${u.note ? '\t' + u.note : ''}`);
console.log('\n-- INACTIVE --');
for (const u of out.inactive) console.log(`${u.token}\t${u.status}\t${u.src}`);
console.log('\n-- RESOLVED VIA ALIAS --');
for (const u of out.alias) console.log(`${u.token}\t->\t${u.role_id}\t(${u.kind})`);
