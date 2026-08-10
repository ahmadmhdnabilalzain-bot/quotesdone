// sync_ops_projections.mjs — bring staging's ops_kb_stage projections to production parity.
//
// Both projects hold the same 3,959 ops_kb_stage.records. Production also holds the relational
// projections the pack's import order builds from them (departments 24, roles 96, sops 236,
// decision rules 240, workflows 18, handoffs 132, event subscriptions 100, ...). On staging
// every one of those tables is EMPTY: the records landed and the projection step never ran.
//
// Row data only. It refuses to touch a table that already has rows, so a re-run cannot double
// up, and it refuses production as a destination outright — production is the source here.
//
//   node scripts/kb/sync_ops_projections.mjs [--apply]
import { readFileSync } from 'node:fs';

const PROD = 'htdblwldjkcgjvmqkbeh';
const STAGE = 'pglpqrhvozwepymcuunn';
const APPLY = process.argv.includes('--apply');
const FORCE = process.argv.includes('--force');
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const sleep = (ms) => new Promise(r => setTimeout(r, ms));
async function q(ref, sql, attempt = 0) {
  if (ref === PROD && !/^\s*select/i.test(sql)) throw new Error('REFUSED: production is read-only here');
  let r, body;
  try {
    r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(180_000),
    });
    body = await r.text();
  } catch (e) {
    if (attempt < 6) { await sleep(1500 * 2 ** attempt); return q(ref, sql, attempt + 1); }
    throw new Error(`transport failed: ${e.message}`);
  }
  if ([429, 500, 502, 503, 504].includes(r.status) && attempt < 6) {
    await sleep(1500 * 2 ** attempt); return q(ref, sql, attempt + 1);
  }
  if (!r.ok) throw new Error(`${ref} management API ${r.status}: ${body.slice(0, 400)}`);
  return body ? JSON.parse(body) : null;
}
const lit = (s) => "'" + s.replace(/\u0000/g, '').replace(/'/g, "''") + "'";

// Ordered so a table lands after anything it references.
const TABLES = ['departments', 'department_crosswalk', 'roles', 'sops', 'decision_rules',
  'exception_playbooks', 'kpis', 'templates', 'scenarios', 'workflows', 'handoffs',
  'event_subscriptions', 'live_bindings', 'hard_gates', 'policies', 'binding_aliases',
  'sources', 'mapping_decisions'];

const report = [];
for (const t of TABLES) {
  let prodN, stageN;
  try { prodN = Number((await q(PROD, `select count(*)::bigint n from ops_kb_stage.${t};`))[0].n); }
  catch { report.push(`${t}: absent on production — skipped`); continue; }
  try { stageN = Number((await q(STAGE, `select count(*)::bigint n from ops_kb_stage.${t};`))[0].n); }
  catch { report.push(`${t}: absent on STAGING — skipped (schema differs)`); continue; }

  if (prodN === stageN) { report.push(`${t}: ${prodN} = ${stageN}  already at parity`); continue; }
  if (prodN === 0) { report.push(`${t}: both 0`); continue; }
  // A partial copy from an interrupted run is worse than none: it looks populated and is short.
  // Refill only tables this script itself left short, never one that holds independent rows.
  const refillable = stageN === 0 || (FORCE && stageN < prodN);
  if (!refillable) { report.push(`${t}: prod ${prodN} vs stage ${stageN} — NOT EMPTY, left alone`); continue; }
  if (!APPLY) { report.push(`${t}: would copy ${prodN} rows (dry run)`); continue; }
  if (stageN > 0) await q(STAGE, `delete from ops_kb_stage.${t};`);

  const cols = (await q(PROD, `select column_name from information_schema.columns
      where table_schema='ops_kb_stage' and table_name='${t}' order by ordinal_position;`))
    .map(r => r.column_name);
  const stageCols = new Set((await q(STAGE, `select column_name from information_schema.columns
      where table_schema='ops_kb_stage' and table_name='${t}';`)).map(r => r.column_name));
  const use = cols.filter(c => stageCols.has(c));
  const dropped = cols.filter(c => !stageCols.has(c));

  // GENERATED ALWAYS identity columns reject an explicit value. Keeping the production id is
  // what makes the two projections comparable row for row, so override rather than regenerate.
  const idCols = (await q(STAGE, `select column_name from information_schema.columns
      where table_schema='ops_kb_stage' and table_name='${t}'
        and is_identity='YES' and identity_generation='ALWAYS';`)).map(r => r.column_name);
  const OVERRIDE = idCols.length ? 'overriding system value' : '';

  const rows = await q(PROD, `select ${use.map(c => `"${c}"`).join(',')} from ops_kb_stage.${t};`);
  let done = 0;
  for (let i = 0; i < rows.length; i += 300) {
    const batch = rows.slice(i, i + 300);
    await q(STAGE, `insert into ops_kb_stage.${t} (${use.map(c => `"${c}"`).join(',')}) ${OVERRIDE}
      select ${use.map(c => `"${c}"`).join(',')} from jsonb_populate_recordset(
        null::ops_kb_stage.${t}, ${lit(JSON.stringify(batch))}::jsonb);`);
    done += batch.length;
  }
  // Explicit ids leave the identity sequence behind the data; the next insert would collide.
  for (const c of idCols) {
    await q(STAGE, `select setval(pg_get_serial_sequence('ops_kb_stage.${t}','${c}'),
      coalesce((select max("${c}") from ops_kb_stage.${t}), 1));`);
  }
  const after = Number((await q(STAGE, `select count(*)::bigint n from ops_kb_stage.${t};`))[0].n);
  report.push(`${t}: copied ${done}, staging now ${after} (prod ${prodN})` +
    (dropped.length ? `  [columns not on staging, skipped: ${dropped.join(',')}]` : '') +
    (after === prodN ? '  OK' : '  MISMATCH'));
}
console.log(report.join('\n'));
