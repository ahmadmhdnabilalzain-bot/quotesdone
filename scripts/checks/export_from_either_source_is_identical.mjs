// "IF I EVER EXPORTED THE FULL CODE OF THE PROJECT FROM EITHER SOURCE IT WILL GIVE ME THE EXACT
// SAME THING." — founder, 15 Aug 2026.
//
// That is a stronger property than any check in this repo measured before today. "349 routines
// match" is about routines. This is about the WHOLE export: schema, objects, grants, and the edge
// function code, from the database on one side and from git on the other, compared word by word.
//
// It reports four things and does not average them:
//
//   1. SCHEMA       public.fn_schema_export() on production, against the mirror in
//                   supabase/schema/full_schema/ (eleven parts read as one, scripts/lib/schema_mirror.mjs)
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
import { readFileSync, existsSync } from 'node:fs';
// The repository's SQL reader, with the one retry policy this endpoint has. It adds no dependency
// (node:fs and fetch only), and the token probe below stays because db.mjs THROWS when there is no
// token while this check must SKIP — a check with no credential has measured nothing, and saying so
// is not the same as failing.
import { sql } from '../lib/db.mjs';
import { SCHEMA_MIRROR, readSchemaMirror, writeSchemaMirror } from '../lib/schema_mirror.mjs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
if (!token) { console.log('SKIP: no SUPABASE_ACCESS_TOKEN'); process.exit(0); }

const PROD = 'htdblwldjkcgjvmqkbeh';
const FILE = SCHEMA_MIRROR;
const WRITE = process.argv.includes('--write');

// A TIMEOUT IS NOT DRIFT, AND THIS CHECK USED TO PRINT THEM THE SAME COLOUR.
//
// Until 18 Sep 2026 the single fetch below had no retry: one `57014 canceling statement due to
// statement timeout` and the check exited 1, the same exit a genuine repository-versus-production
// difference produces. MEASURED that day: 11 failures in 29 runs over 2.5 hours — 38%, including on
// the head of main — and not one of them was drift. fn_schema_export deparses every object in
// `public`, deparsing takes an ACCESS SHARE lock, and any other session mid-apply holds ACCESS
// EXCLUSIVE; the export then waits out the whole 2-minute statement_timeout. Proven with an
// aborted-transaction probe: a 12s lock on ONE table turned a ~900 ms export into 12,374 ms.
// (scripts/sql/the_export_gate_was_red_because_another_session_held_a_lock.sql carries the numbers
// and sets lock_timeout=15s on the routine so a blocked export gives up in seconds, as 55P03,
// instead of burning two minutes before anything can be retried.)
//
// A gate that is red 38% of the time for a reason unrelated to its subject teaches everyone to
// merge past it, and then the day it is right about real drift nobody looks. So there are now THREE
// outcomes, never two, and the exit code says which:
//
//     0  the export was measured and matches the committed mirror
//     1  the export was measured and DIFFERS — drift. Unchanged, still loud, still fails the merge.
//     2  THE EXPORT COULD NOT BE MEASURED. Not a drift finding, not an OK. Also fails the merge,
//        because a gate that cannot reach its subject must never report a green over nothing.
//
// The retry is the repository's ONE retry policy — scripts/lib/db.mjs — not a second copy written
// here. `retryableBody` is the option added there for this: the management API answers a statement
// timeout and a lock timeout with HTTP 400, the same status as a syntax error, so the pattern to
// retry has to be named. db.mjs allows 7 attempts and backs off 2s doubling to a 60s cap with
// jitter (~3 minutes of patience), which outlasts an ordinary apply by another session.
//
// WHAT COULD NOT BE MEASURED, honestly: the 429s seen on 18 Sep 2026 are account-wide throttling,
// and 20 consecutive full 3.5 MB exports issued back to back in a quiet window all returned 201.
// The limiter is therefore shared with whatever else is running, so no fixed throttle window was
// measurable from this side and the budget above is a budget, not a derivation.
//
// This is a pure READ, which is why retrying it is safe. db.mjs's own header records the opposite
// case — re-POSTing DDL while the first copy still ran server-side deadlocked for 18 minutes. The
// distinguishing fact is not "only one statement": it is that fn_schema_export requests only
// ACCESS SHARE, so two copies of it queue behind a writer harmlessly and can never deadlock each
// other. A check that retries something which takes an exclusive lock does NOT inherit that.
const RETRYABLE_BODY = /57014|55P03|40P01|canceling statement|lock_not_available|deadlock detected/i;

/** Exit 2 with the reason. The wording is deliberate: it says what was not measured. */
const couldNotMeasure = (why) => {
  console.log('SCHEMA EXPORT — database vs git');
  console.log('  THE EXPORT COULD NOT BE MEASURED.');
  console.log(`  ${why}`);
  console.log('  This is NOT a drift finding: the database was never compared to the committed');
  console.log('  mirror, so nothing is known either way about whether production matches this');
  console.log('  repository. Re-run once the session that is applying SQL has finished.');
  process.exit(2);
};

// fn_schema_export returns one row per line; the committed file is those lines joined.
let rows;
try {
  rows = await sql('select * from public.fn_schema_export()', { ref: PROD, retryableBody: RETRYABLE_BODY });
} catch (err) {
  const msg = String(err?.message || err).replace(/\s+/g, ' ').slice(0, 400);
  const infra = RETRYABLE_BODY.test(msg) || /HTTP (?:429|5\d\d)/.test(msg) || !/^HTTP /.test(msg);
  couldNotMeasure(infra
    ? `the export did not complete within db.mjs's retry budget. Last: ${msg}`
    : `the query was refused and asking again will not help: ${msg}`);
}
if (!Array.isArray(rows) || !rows.length) couldNotMeasure('public.fn_schema_export() returned no rows.');
const key = Object.keys(rows[0])[0];
const live = rows.map((r) => r[key]).join('\n');
if (!live.trim()) couldNotMeasure('public.fn_schema_export() returned an empty export.');

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

// A mirror that cannot be read (a part missing or unlisted) compares as empty: drift, loudly.
let raw = '';
try { raw = readSchemaMirror(); } catch (err) { console.log(`  ${err.message}`); }
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
console.log(`  committed mirror: ${b.length} lines, ${onDisk.length} chars (${FILE}/)`);
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
  const parts = writeSchemaMirror(banner() + live);
  console.log(`\nwrote ${FILE}/ (${a.length} schema lines + banner) as ${parts.length} parts:`);
  for (const p of parts) console.log(`  ${String(p.bytes).padStart(9)}  ${p.file}`);
} else if (live !== onDisk) {
  process.exitCode = 1;
}
