// sync_executor_classification.mjs — copy org_action_executor's CLASSIFICATION columns from
// production to staging. Row data only; no DDL, no new rows, no deletes.
//
// WHY. Measured 2026-08-10: staging holds all 55 executor rows and all 39 edge ones, but every
// row reads risk_tier='high', reversible=false, and 31 of 55 advisory_safe=false. Production
// carries the real classification (27 low/advisory_safe/reversible, 8 medium, 3 high) plus
// idempotency_strategy, timeout_seconds, max_attempts, backoff, required_authority and
// compensation_action_class. The columns were populated on production and never backfilled on
// staging, so staging fails closed on everything — which looks safe and means the HTTP invoker
// cannot be rehearsed there at all. Same class of divergence as compliance_sources = 0 on
// staging while production held 17 (session 6).
//
// Refuses production as a destination outright, like sync_ops_projections.mjs.
import { readFileSync } from 'node:fs';

const SRC = 'htdblwldjkcgjvmqkbeh';   // production, read-only here
const DST = 'pglpqrhvozwepymcuunn';   // staging
if (process.argv.includes('--dst=htdblwldjkcgjvmqkbeh')) throw new Error('production is never a destination for this script');

const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

async function q(ref, sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(120000) });
  const t = await r.text();
  if (!r.ok) throw new Error(`${ref} ${r.status}: ${t.slice(0, 300)}`);
  return JSON.parse(t);
}
const lit = (v) => v === null || v === undefined ? 'null' : (typeof v === 'boolean' ? String(v)
  : typeof v === 'number' ? String(v) : `'${String(v).replace(/'/g, "''")}'`);

const COLS = ['advisory_safe', 'risk_tier', 'reversible', 'idempotency_strategy', 'timeout_seconds',
  'max_attempts', 'backoff', 'required_authority', 'compensation_action_class', 'owner_os', 'department'];

const src = await q(SRC, `select action_class, ${COLS.join(', ')} from org_action_executor order by action_class`);
console.log(`production: ${src.length} executor rows`);

const before = await q(DST, `select count(*) filter (where risk_tier='low' and advisory_safe and reversible) n, count(*) tot from org_action_executor`);
console.log('staging before:', JSON.stringify(before[0]));

const values = src.map(r => `(${lit(r.action_class)}, ${COLS.map(c => lit(r[c])).join(', ')})`).join(',\n');
const casts = 'action_class text, advisory_safe boolean, risk_tier text, reversible boolean, idempotency_strategy text, timeout_seconds int, max_attempts int, backoff text, required_authority text, compensation_action_class text, owner_os text, department text';
const sql = `
with src(${['action_class', ...COLS].join(', ')}) as (
  select * from (values\n${values}\n) v(${casts.split(',').map(s => s.trim().split(' ')[0]).join(', ')})
)
update org_action_executor e set
  advisory_safe = s.advisory_safe::boolean, risk_tier = s.risk_tier::text,
  reversible = s.reversible::boolean, idempotency_strategy = s.idempotency_strategy::text,
  timeout_seconds = s.timeout_seconds::int, max_attempts = s.max_attempts::int,
  backoff = s.backoff::text, required_authority = s.required_authority::text,
  compensation_action_class = s.compensation_action_class::text,
  owner_os = s.owner_os::text, department = s.department::text
from src s where s.action_class = e.action_class
returning e.action_class;`;
const updated = await q(DST, sql);
console.log(`staging updated: ${updated.length} rows`);

const after = await q(DST, `select count(*) filter (where risk_tier='low' and advisory_safe and reversible) low_safe, count(*) filter (where kind='edge') edge, count(*) tot from org_action_executor`);
console.log('staging after :', JSON.stringify(after[0]));
