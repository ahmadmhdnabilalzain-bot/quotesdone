// apply_missing_objects.mjs — close the gap between staging and production, without a full rebuild.
//
// A full baseline replay takes ~50 minutes and drops the public schema to do it. When staging is
// already 95% correct and simply missing the tables that postdate the last baseline capture, that
// is the wrong tool. This computes the difference from the two live catalogues - Supabase is the
// source of truth, so the catalogue is the authority, not the repo - and applies only the
// statements that mention a missing table.
//
// It refuses to run against production.
//
//   node scripts/staging/apply_missing_objects.mjs [--apply]
import { readFileSync } from 'node:fs';
import { splitStatements } from './sql_split.mjs';
import { mgmtRead, mgmtWrite, PROD_REF, assertNotProduction } from './qd_guard.mjs';

const SCHEMA_FILE = 'C:/Users/Opera/quotesdone/supabase/schema/full_schema.sql';
const REF = assertNotProduction(process.env.QD_STAGING_REF || 'pglpqrhvozwepymcuunn', 'apply missing');
const APPLY = process.argv.includes('--apply');

const q = "select table_name from information_schema.tables where table_schema='public' and table_type='BASE TABLE'";
const prod = new Set((await mgmtRead(PROD_REF, q)).map(r => r.table_name));
const stage = new Set((await mgmtRead(REF, q)).map(r => r.table_name));
const missing = [...prod].filter(t => !stage.has(t)).sort();

console.log(`production ${prod.size} tables, staging ${stage.size}, missing ${missing.length}`);
if (!missing.length) { console.log('nothing to do'); process.exit(0); }
console.log('missing: ' + missing.join(', '));

const raw = readFileSync(SCHEMA_FILE, 'utf8');
// The CRON JOBS section arms 151 schedules pointing at production. It is never applied to a branch.
const SEC = /^-- ===== (.+?) =====/gm;
const bounds = [];
for (let m; (m = SEC.exec(raw));) bounds.push({ name: m[1], start: m.index });
for (let i = 0; i < bounds.length; i++) bounds[i].end = bounds[i + 1]?.start ?? raw.length;
let body = '';
for (const b of bounds) if (b.name !== 'CRON JOBS') body += raw.slice(b.start, b.end);

const all = splitStatements(body);
// A statement is in scope when it names a missing table with a word boundary, so `quotes` does
// not drag in `quote_items`.
const wanted = all.filter(s =>
  !s.includes(PROD_REF) &&
  missing.some(t => new RegExp(`\\b${t}\\b`).test(s)));

console.log(`statements parsed ${all.length}, referencing a missing table: ${wanted.length}`);
if (!APPLY) { console.log('\nDRY RUN - nothing applied. Re-run with --apply.'); process.exit(0); }

let pending = wanted.slice();
for (let pass = 1; pass <= 5 && pending.length; pass++) {
  const failed = [];
  let ok = 0;
  for (const s of pending) {
    try { await mgmtWrite(REF, s, 'statement'); ok++; }
    catch (e) { failed.push({ sql: s, err: String(e.message).slice(0, 200) }); }
  }
  console.log(`pass ${pass}: applied ${ok}, failed ${failed.length}`);
  const noProgress = failed.length === pending.length;
  pending = failed.map(f => f.sql);
  if (!failed.length || noProgress) break;
}

const after = new Set((await mgmtRead(REF, q)).map(r => r.table_name));
const stillMissing = [...prod].filter(t => !after.has(t)).sort();
console.log(`\nstaging now ${after.size} tables; still missing ${stillMissing.length}` +
  (stillMissing.length ? ': ' + stillMissing.join(', ') : ''));
process.exitCode = stillMissing.length ? 1 : 0;
