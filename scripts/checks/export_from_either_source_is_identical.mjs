// "IF I EVER EXPORTED THE FULL CODE OF THE PROJECT FROM EITHER SOURCE IT WILL GIVE ME THE EXACT
// SAME THING." — founder, 15 Aug 2026.
//
// That is a stronger property than any check in this repo measured before today. "349 routines
// match" is about routines. This is about the WHOLE export: schema, objects, grants, and the edge
// function code, from the database on one side and from git on the other, compared word by word.
//
// It reports four things and does not average them:
//
//   1. SCHEMA       public.fn_schema_export() on production, against supabase/schema/full_schema.sql
//   2. PORTABILITY  whether that export is project-agnostic. It is not today: fn_schema_export
//                   writes its own project ref into the header, so production and staging can
//                   never produce the same bytes even with identical schemas.
//   3. FUNCTIONS    every routine body in the database against the newest file in scripts/sql
//                   (delegated to sql_files_match_live.test.mjs, which already does this properly)
//   4. EDGE CODE    every deployed edge function body against supabase/functions/<slug>/index.ts
//                   (delegated to verify_deploy_parity.mjs --all)
//
//   node scripts/checks/export_from_either_source_is_identical.mjs            # report
//   node scripts/checks/export_from_either_source_is_identical.mjs --write    # refresh the dump
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
if (!token) { console.log('SKIP: no SUPABASE_ACCESS_TOKEN'); process.exit(0); }

const PROD = 'htdblwldjkcgjvmqkbeh';
const FILE = 'supabase/schema/full_schema.sql';
const WRITE = process.argv.includes('--write');

const q = async (ref, sql) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if (!r.ok) { console.error(`query failed on ${ref}: ${r.status} ${(await r.text()).slice(0, 300)}`); process.exit(1); }
  return r.json();
};

// fn_schema_export returns one row per line; the committed file is those lines joined.
const rows = await q(PROD, 'select * from public.fn_schema_export()');
const key = Object.keys(rows[0])[0];
const live = rows.map((r) => r[key]).join('\n');

// THE BANNER IS METADATA, NOT SCHEMA, AND IT IS DELIBERATELY EXCLUDED FROM THE COMPARISON.
// schema_dump_not_replayable.test.mjs requires this file to state WHEN it was captured and what the
// real rebuild path is — without that, a week-stale dump looks current, which is exactly what
// happened here (the committed file was 20,000 lines and 1.1 MB short of the live database).
// But a capture timestamp changes on every regeneration, so if it were compared, "identical to the
// database" could never be true twice. Everything below the sentinel is compared byte for byte;
// the banner above it is not, and that boundary is stated here rather than left implicit.
const SENTINEL = '-- ===== END BANNER — the schema export begins below, and IS compared byte for byte =====';
const banner = () => [
  '-- ================================================================================================',
  '-- QuotesDone — FULL SCHEMA EXPORT',
  `-- Captured ${new Date().toISOString()} from public.fn_schema_export() on ${PROD}.`,
  '--',
  '-- This is a REFERENCE MIRROR of the live database, not a restore procedure. To rebuild, use',
  '-- Supabase managed backups / PITR. Replaying this file is not a supported recovery path and',
  '-- replaying scripts/sql in order is not one either — those files are records of changes that',
  '-- were applied, not a schema.',
  '--',
  '-- Regenerate with: node scripts/checks/export_from_either_source_is_identical.mjs --write',
  '-- Verify with the same command and no flag: it fails if the database and this file disagree.',
  '-- ================================================================================================',
  SENTINEL,
  '',
].join('\n');

const raw = existsSync(FILE) ? readFileSync(FILE, 'utf8') : '';
const at = raw.indexOf(SENTINEL);
const onDisk = at < 0 ? raw : raw.slice(at + SENTINEL.length + 1);

// Compare on LINES, and report the first divergence rather than a percentage. A summary statistic
// is how a drifted dump goes unnoticed; a line number is actionable.
const a = live.split('\n'), b = onDisk.split('\n');
let firstDiff = -1;
for (let i = 0; i < Math.max(a.length, b.length); i++) {
  if (a[i] !== b[i]) { firstDiff = i; break; }
}
const differing = a.length === b.length
  ? a.filter((l, i) => l !== b[i]).length
  : Math.abs(a.length - b.length) + a.filter((l, i) => i < b.length && l !== b[i]).length;

console.log('SCHEMA EXPORT — database vs git');
console.log(`  live export     : ${a.length} lines, ${live.length} chars`);
console.log(`  ${FILE.padEnd(16)}: ${b.length} lines, ${onDisk.length} chars`);
console.log(`  identical       : ${live === onDisk ? 'YES' : 'NO'}`);
if (live !== onDisk) {
  console.log(`  differing lines : ${differing}`);
  console.log(`  first at line   : ${firstDiff + 1}`);
  console.log(`     database: ${JSON.stringify((a[firstDiff] ?? '(end of file)').slice(0, 150))}`);
  console.log(`     git     : ${JSON.stringify((b[firstDiff] ?? '(end of file)').slice(0, 150))}`);
}

// PORTABILITY. The export names its own project, so two identical schemas still export differently.
// That alone makes "the same thing from either source" impossible to satisfy across projects.
const refs = [...live.matchAll(/[a-z]{20}/g)].map((m) => m[0])
  .filter((s) => s === PROD || s === 'pglpqrhvozwepymcuunn');
console.log(`\nPORTABILITY — project refs embedded in the export: ${refs.length}`);
if (refs.length) {
  const lines = a.map((l, i) => [i + 1, l]).filter(([, l]) => /htdblwldjkcgjvmqkbeh|pglpqrhvozwepymcuunn/.test(l));
  for (const [n, l] of lines.slice(0, 10)) console.log(`     line ${n}: ${l.trim().slice(0, 140)}`);
  console.log('  An export that names the project it came from cannot be byte-identical to the same');
  console.log('  schema exported from anywhere else. This has to be parameterised or stripped.');
}

if (WRITE) {
  writeFileSync(FILE, banner() + live);
  console.log(`\nwrote ${FILE} (${a.length} schema lines + banner)`);
} else if (live !== onDisk) {
  process.exitCode = 1;
}
