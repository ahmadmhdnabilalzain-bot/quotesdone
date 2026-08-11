// scripts/sql IS APPEND-ONLY, AND THIS IS THE CHECK THAT MAKES THAT MEAN SOMETHING.
//
// THE POLICY, written down because it has only ever been folklore:
//
//   1. A file in scripts/sql is a RECORD OF A CHANGE THAT WAS APPLIED. Once it is committed it is
//      never edited. To change a routine again, add a NEW file. The old file stays as the record of
//      what was true then, and its header comment stays as the reasoning that was true then.
//   2. The file name says what changed and why, in words: the_employee_context_died_on_an_8s_wall.sql,
//      not fix_context_v3.sql. Grep is the index.
//   3. Every file is applied with `node scripts/apply_sql.mjs <file> --promote [--ddl]`, which posts
//      the definition read back FROM STAGING to production, never the file text a second time.
//   4. Therefore: for any routine, the NEWEST file that defines it should match what is live. If it
//      does not, one of two things happened, and both are worth knowing about:
//         * a file was written and never applied, or applied to staging only, or
//         * the routine was changed somewhere else — a migration, the dashboard, another session —
//           and scripts/sql no longer records the truth.
//
// This check reads every `create or replace function` in scripts/sql, takes the NEWEST file per
// routine by git commit time, and compares its body against the live `prosrc` on PRODUCTION, on
// TOKENS rather than bytes so that indentation is not a finding.
//
// A RATCHET, not a cliff: BASELINE below is the number of routines already drifted on 11 Aug 2026.
// The check fails when that number GROWS. Lower it when you reconcile one; never raise it.
//
//   node scripts/checks/sql_files_match_live.test.mjs
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { join } from 'node:path';

const BASELINE_DRIFTED = 0;    // RECONCILED 12 Aug 2026: 190 routines across 316 files — 190 identical,
                               // 0 missing from production, 0 drifted. The ratchet is now at the
                               // floor, so ANY drift fails this check.
                               //
                               // The 8 that were outstanding were reconciled TOWARD PRODUCTION, after
                               // checking the direction rather than assuming it. fn_term_matches live
                               // handles multi-word Arabic patterns and English plurals; the file in
                               // scripts/sql/stage_b6_rollback_completion.sql has neither, so applying
                               // that file would have broken Arabic term matching on a UAE marketplace.
                               // The files were stale; the database was right. Captured verbatim from
                               // pg_get_functiondef in scripts/sql/the_files_were_stale_not_the_database.sql.
                               //
                               // Raising this number is not how you fix a failure here. A routine that
                               // drifts means something changed production without leaving a file, and
                               // the file is what the next session would apply.
const DIR = 'scripts/sql';
const PROD = 'htdblwldjkcgjvmqkbeh';
// This check has to READ PRODUCTION, so it cannot run where there is no management token — and CI
// is exactly that place. Skipping loudly beats failing the build for a missing credential, which is
// what the first run of this file did: ENOENT on the local token path, exit 1, red merge.
// It is not weakened, it is scoped: the drift it looks for is created by a human applying (or not
// applying) a file, and it is caught the next time a session runs the sweep.
const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
if (!token) {
  console.log('SKIPPED: no SUPABASE_ACCESS_TOKEN and no local access token, so production cannot be '
    + 'read. This check compares scripts/sql against LIVE routine bodies; run it from a session that '
    + 'has the management token. It is not asserting anything here.');
  process.exit(0);
}

const tokens = (s) => (String(s).match(/[A-Za-z_$][\w$]*|\d+(?:\.\d+)?|'(?:[^']|'')*'|[^\sA-Za-z0-9_$]/g) || [])
  .join(' ').toLowerCase();

// Newest-first commit order for the files, so "the newest file that defines this routine" is a fact
// about history and not about the filesystem.
let order = [];
try {
  order = execSync(`git log --name-only --pretty=format: -- ${DIR}`, { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 })
    .split('\n').map(s => s.trim()).filter(s => s.startsWith(DIR));
} catch (_e) { /* not a git checkout; fall back to readdir order */ }
const rank = new Map();
order.forEach((f, i) => { if (!rank.has(f)) rank.set(f, i); });   // first appearance = newest commit

const files = readdirSync(DIR).filter(f => f.endsWith('.sql'))
  .map(f => `${DIR}/${f}`.replace(/\\/g, '/'))
  .sort((a, b) => (rank.has(a) ? rank.get(a) : 1e9) - (rank.has(b) ? rank.get(b) : 1e9));

// routine name -> { file, body } from the NEWEST file that defines it
const newest = new Map();
for (const f of files) {
  if (!existsSync(f)) continue;
  const src = readFileSync(f, 'utf8');
  const re = /create\s+or\s+replace\s+function\s+(?:public\.)?([a-z0-9_]+)\s*\(/gi;
  let m;
  while ((m = re.exec(src))) {
    const name = m[1].toLowerCase();
    if (newest.has(name)) continue;                     // an older file; the newest already won
    // body between the first $tag$ after the header and its closing twin
    const rest = src.slice(m.index);
    const tag = rest.match(/as\s+(\$[a-z_]*\$)/i);
    if (!tag) continue;
    const start = rest.indexOf(tag[1], rest.indexOf(tag[0])) + tag[1].length;
    const end = rest.indexOf(tag[1], start);
    if (end < 0) continue;
    newest.set(name, { file: f, body: rest.slice(start, end) });
  }
}

const names = [...newest.keys()];
if (!names.length) { console.log('no routines defined in scripts/sql'); process.exit(0); }

const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
  method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query:
    `select p.proname n, p.prosrc s from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.proname in (${names.map(n => `'${n}'`).join(',')})` }),
});
if (!r.ok) { console.error('could not read production:', r.status, (await r.text()).slice(0, 200)); process.exit(1); }
const live = await r.json();
const byName = new Map();
for (const row of live) {                               // overloads: keep every body, match any
  if (!byName.has(row.n)) byName.set(row.n, []);
  byName.get(row.n).push(tokens(row.s));
}

const missing = [], drifted = [], ok = [];
for (const [name, { file, body }] of newest) {
  const bodies = byName.get(name);
  if (!bodies) { missing.push({ name, file }); continue; }
  if (bodies.includes(tokens(body))) ok.push(name); else drifted.push({ name, file });
}

console.log(`scripts/sql defines ${newest.size} routine(s) across ${files.length} file(s)`);
console.log(`  live and identical to the newest file : ${ok.length}`);
console.log(`  NOT PRESENT on production             : ${missing.length}`);
for (const m of missing) console.log(`     ${m.name.padEnd(38)} newest file ${m.file}`);
console.log(`  present but DRIFTED from the newest file: ${drifted.length}`);
for (const d of drifted) console.log(`     ${d.name.padEnd(38)} newest file ${d.file}`);

if (missing.length) {
  console.error('\nA routine recorded in scripts/sql does not exist on production. Either the file was '
    + 'never applied, or the routine was dropped and the file was left behind as a false record.');
  process.exit(1);
}
const bad = drifted.length;
if (bad > BASELINE_DRIFTED) {
  console.error(`\n${bad} drifted against a baseline of ${BASELINE_DRIFTED}. Something changed a routine `
    + 'outside scripts/sql, or a new file was written and never applied.');
  process.exit(1);
}
console.log(`\ndrift ${bad} <= baseline ${BASELINE_DRIFTED}. NOT the same as "no drift" — lower the baseline as you reconcile.`);
