// K15 — make fn_phase_b_invariants read its expected counts from the founder-approved baseline
// instead of from literals typed into the function body.
//
// Built from the LIVE definition, replacing only the fifteen literals in the counts CTE with
// scalar subqueries. The `values` list already contains scalar subqueries in its `actual` column,
// so no restructuring is needed: the shape of the function does not change at all.
import { readFileSync, writeFileSync } from 'node:fs';
import { sql } from './lib/db.mjs';

const [{ prosrc }] = await sql(
  `select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='fn_phase_b_invariants'`);

const KEYS = {
  'count.workflows': 'workflows', 'count.steps': 'steps', 'count.handoffs': 'handoffs',
  'count.business_objects': 'business_objects', 'count.business_rules': 'business_rules',
  'count.exceptions': 'exceptions', 'count.sla_policies': 'sla_policies', 'count.gates': 'gates',
  'count.events': 'events', 'count.workflow_states': 'workflow_states',
  'count.workflow_transitions': 'workflow_transitions', 'count.step_states': 'step_states',
  'count.step_transitions': 'step_transitions', 'count.founder_boundaries': 'founder_boundaries',
  'count.cross_department_handoffs': 'cross_department_handoffs',
};
const approved = k =>
  `(select (b.counts->>'${k}')::text from public.org_phase_baseline b where b.phase = 'B')`;

let body = prosrc;
for (const [check, key] of Object.entries(KEYS)) {
  const re = new RegExp(`(\\('${check.replace('.', '\\.')}',\\s*)'\\d+'`);
  if (!re.test(body)) { console.error(`no literal for ${check} — refusing to emit`); process.exit(1); }
  body = body.replace(re, `$1${approved(key)}`);
}
const survivor = body.split('\n').filter(l => /\('count\./.test(l) && /'\d+'/.test(l));
if (survivor.length) { console.error('a count literal survived:\n' + survivor.join('\n')); process.exit(1); }

writeFileSync('scripts/sql/kernel_k15_invariants_read_the_baseline.sql',
  readFileSync('scripts/sql/kernel_k15_header.txt', 'utf8') +
  `\nbegin;\n\ncreate or replace function public.fn_phase_b_invariants()\n` +
  `returns table (check_name text, expected text, actual text, ok boolean)\n` +
  `language sql\nstable\nsecurity definer\nset search_path to 'public', 'pg_temp'\n` +
  `as $k15_inv$${body}$k15_inv$;\n\n` +
  `comment on function public.fn_phase_b_invariants() is\n` +
  `  'Phase B invariants. K15: the expected COUNTS are read from the founder-approved baseline row '\n` +
  `  'in org_phase_baseline, not from literals in this body, so a founder-approved amendment moves '\n` +
  `  'the expectation and the measurement together while an unapproved registry change still fails. '\n` +
  `  'If no Phase B baseline is recorded, expected is NULL and every count check FAILS.';\n\ncommit;\n`);
console.log(`emitted, ${Object.keys(KEYS).length} literals replaced.`);
