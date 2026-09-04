// THE APPLICATION SOURCE-OF-TRUTH GATE.
//
// WHY THIS EXISTS AND WHY IT IS NOT canonical_routines.test.mjs.
//   canonical_routines.test.mjs measures the WHOLE live catalogue against the manifest and gets a
//   true number nobody can act on: 483 live routines no manifest file defines. The received
//   reading of that number was "most of it is Supabase- and extension-managed code". MEASURED,
//   THAT IS FALSE — the check already excludes extension-owned routines by pg_depend, and every
//   remaining routine in `public` on this project is owned by `postgres`. The 483 is application
//   code, all of it, and lumping it with the managed estate made a real problem look like noise.
//
//   So this check separates the two estates MECHANICALLY, by the rules kernel_s0 encodes, and then
//   gates ONLY the estate QuotesDone actually owns as source: QUOTESDONE_APPLICATION.
//
// THE ONE RULE THAT DECIDES CANON: position in scripts/sql/MANIFEST.txt. The LAST manifest file
// that defines a routine is its ONE current source file. Git commit time is never consulted.
// A commit-time tie is exactly what let the phase_c_39 correction sit in the repository and not on
// production for a day while every instrument read 0 drift.
//
// EVERY LINE CARRIES ITS DENOMINATOR. A bare count cannot tell a clean estate from an empty one,
// and this repository has been burned by pct(got, 0) = 100 before.
//
// READ-ONLY. Every statement it sends is a SELECT.
//
//   node scripts/checks/application_source_of_truth.test.mjs
import { readFileSync, existsSync } from 'node:fs';
import { execSync, spawnSync } from 'node:child_process';
import { newDdlRecord, eatDdl, uncommittedDdl, LIVE_DDL_SQL } from './_ddl_from_sql.mjs';

const DIR = 'scripts/sql';
const MANIFEST = `${DIR}/MANIFEST.txt`;
const SCHEMA_MIRROR = 'supabase/schema/full_schema.sql';
const PROD = 'htdblwldjkcgjvmqkbeh';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
if (!token) {
  console.log('SKIPPED: no SUPABASE_ACCESS_TOKEN and no local access token, so production cannot be '
    + 'read. This gate compares the QuotesDone application estate against the LIVE catalogue; run it '
    + 'from a session that has the management token. It is not asserting anything here.');
  process.exit(0);
}

async function q(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if (!r.ok) { console.error('could not read production:', r.status, (await r.text()).slice(0, 300)); process.exit(1); }
  return r.json();
}

// Same normaliser as canonical_routines.test.mjs and sql_files_match_live.test.mjs: compare on
// TOKENS, so indentation is not a finding but a changed identifier or literal is.
const tokens = (s) => (String(s).match(/[A-Za-z_$][\w$]*|\d+(?:\.\d+)?|'(?:[^']|'')*'|[^\sA-Za-z0-9_$]/g) || [])
  .join(' ').toLowerCase();

// ---------------------------------------------------------------- the repository, in apply order
if (!existsSync(MANIFEST)) {
  console.error(`${MANIFEST} does not exist. Position in it IS the canon rule; without it this gate `
    + 'would be back to guessing from git timestamps, which is the defect it exists to catch.');
  process.exit(1);
}
const manifestFiles = readFileSync(MANIFEST, 'utf8').split('\n')
  .map(l => l.replace(/#.*$/, '').trim()).filter(Boolean).map(p => p.replace(/\\/g, '/'));
const manifestSet = new Set(manifestFiles);

// Schema-qualified on purpose: trg_archive_record_version() exists in BOTH kb_stage and
// ops_kb_stage with identical arguments, and a name-only key silently merges them.
const CREATE_RE = /create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+(?:([a-z0-9_]+)\.)?([a-z0-9_]+)\s*\(/gi;

function definitionsIn(src, file, pos) {
  const out = [];
  let m;
  const re = new RegExp(CREATE_RE.source, 'gi');
  while ((m = re.exec(src))) {
    const key = `${(m[1] || 'public').toLowerCase()}.${m[2].toLowerCase()}`;
    const rest = src.slice(m.index);
    // DIGITS ALLOWED IN THE TAG. canonical_routines.test.mjs and sql_files_match_live.test.mjs both
    // use /\$[a-z_]*\$/, which does not match $k11_reach$, $k11_state$, $k11_guard$ or this
    // increment's own $s0_derive$ — those definitions are silently skipped there, and a skipped
    // definition looks exactly like a clean one. Anything with a body gets compared here.
    const tag = rest.match(/as\s+(\$[a-z0-9_]*\$)/i);
    if (!tag) { out.push({ key, file, pos, body: null }); continue; }   // e.g. `language sql return ...`
    const s = rest.indexOf(tag[1], rest.indexOf(tag[0])) + tag[1].length;
    const e = rest.indexOf(tag[1], s);
    out.push({ key, file, pos, body: e < 0 ? null : rest.slice(s, e) });
  }
  return out;
}

const manifestDefs = new Map();                 // key -> [{file, pos, body}] in manifest order
manifestFiles.forEach((f, pos) => {
  if (!existsSync(f)) return;
  for (const d of definitionsIn(readFileSync(f, 'utf8'), f, pos)) {
    // A pg_temp routine is session-local by construction: it lives for one connection and can never
    // appear in the production catalogue. scripts/sql/b7_latency.sql declares one as a probe helper.
    // Counting it as "in the repository, missing from production" would be a finding that can never
    // be closed, which is worse than no finding at all.
    if (d.key.startsWith('pg_temp.')) continue;
    if (!manifestDefs.has(d.key)) manifestDefs.set(d.key, []);
    manifestDefs.get(d.key).push(d);
  }
});

// Every other tracked .sql in the repository. `git ls-files`, not a hand-kept directory list: a
// keep-list that misses a category is how the stand-down stopped the monitors it said it kept.
let trackedElsewhere = [];
try {
  trackedElsewhere = execSync('git ls-files "*.sql"', { encoding: 'utf8', maxBuffer: 1 << 26 })
    .split('\n').map(s => s.trim()).filter(Boolean).filter(f => !manifestSet.has(f));
} catch (e) {
  console.error('git ls-files failed, so "recorded elsewhere in the repository" cannot be measured '
    + 'and this gate would call tracked code untracked. Refusing to report a number.', e.message);
  process.exit(1);
}
const elsewhereDefs = new Map();                // key -> [file]
for (const f of trackedElsewhere) {
  if (!existsSync(f)) continue;
  for (const d of definitionsIn(readFileSync(f, 'utf8'), f, -1)) {
    if (!elsewhereDefs.has(d.key)) elsewhereDefs.set(d.key, []);
    if (elsewhereDefs.get(d.key).length < 3) elsewhereDefs.get(d.key).push(f);
  }
}

// ---------------------------------------------------------------- the live catalogue
const live = await q(`
select ns.nspname sch, p.proname nm, pg_get_function_identity_arguments(p.oid) args, p.prosrc src,
       pg_get_userbyid(p.proowner) owner,
       coalesce((select e.extname from pg_depend d join pg_extension e on e.oid = d.refobjid
                  where d.objid = p.oid and d.deptype = 'e' limit 1), '') ext
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname not in ('pg_catalog','information_schema','pg_toast') and p.prokind in ('f','p')`);

// ---------------------------------------------------------------- the derivation, re-run here
// Identical precedence to public.fn_kernel_routine_ownership. It is repeated in this file on
// purpose: a gate that asks the database to classify itself cannot catch the database being wrong.
const PLATFORM_ROLES = new Set(['supabase_admin', 'supabase_auth_admin', 'supabase_storage_admin',
  'supabase_functions_admin', 'supabase_realtime_admin', 'authenticator', 'pgbouncer', 'pgsodium_keyholder']);
const PLATFORM_SCHEMAS = new Set(['auth', 'storage', 'realtime', 'vault', 'graphql', 'graphql_public',
  'pgbouncer', 'net', 'cron', 'pgsodium', 'supabase_functions', 'supabase_migrations',
  '_realtime', '_analytics', '_supavisor']);

function classify(r) {
  const key = `${r.sch}.${r.nm}`;
  if (r.ext) return { cls: 'EXTENSION_MANAGED', rule: 'R1_PG_DEPEND_EXTENSION', key };
  if (PLATFORM_ROLES.has(r.owner) && PLATFORM_SCHEMAS.has(r.sch))
    return { cls: 'SUPABASE_MANAGED', rule: 'R2_PLATFORM_ROLE_IN_PLATFORM_SCHEMA', key };
  if (PLATFORM_ROLES.has(r.owner) && r.sch === 'extensions')
    return { cls: 'PLATFORM_INTERNAL', rule: 'R3_PLATFORM_ROLE_IN_EXTENSIONS_SCHEMA', key };
  if (PLATFORM_ROLES.has(r.owner))
    return { cls: 'SUPABASE_MANAGED', rule: 'R2B_PLATFORM_ROLE', key };
  if (manifestDefs.has(key)) return { cls: 'QUOTESDONE_APPLICATION', rule: 'R4_MANIFEST_DEFINES_IT', key };
  if (elsewhereDefs.has(key)) return { cls: 'HISTORICAL_APPLICATION', rule: 'R5_TRACKED_SQL_OUTSIDE_MANIFEST', key };
  return { cls: 'NO_SOURCE_IN_REPOSITORY', rule: 'R6_NO_PROVENANCE_FOUND', key };
}

const classified = live.map(r => ({ ...r, ...classify(r) }));
const classCount = {};
for (const r of classified) classCount[r.cls] = (classCount[r.cls] || 0) + 1;

const MANAGED = new Set(['EXTENSION_MANAGED', 'SUPABASE_MANAGED', 'PLATFORM_INTERNAL']);
const appLive = classified.filter(r => !MANAGED.has(r.cls));           // the application estate, live
const qdLive = classified.filter(r => r.cls === 'QUOTESDONE_APPLICATION');
const liveByKey = new Map();                                           // key -> [normalised prosrc]
for (const r of classified) {
  if (!liveByKey.has(r.key)) liveByKey.set(r.key, []);
  liveByKey.get(r.key).push(tokens(r.src));
}

// ---------------------------------------------------------------- the ownership ledger, if it is there
const ledgerRows = await q(`select to_regclass('public.kernel_routine_ownership') is not null as present`);
const ledgerPresent = !!ledgerRows[0]?.present;
let ledger = [];
if (ledgerPresent) {
  ledger = await q(`select schema_name, routine_name, identity_args, ownership_class,
                           classified_by_rule, source_kind, source_file, justification
                      from public.kernel_routine_ownership`);
}

// THE MANIFEST'S LAST WORD CAN BE A DROP (3 Sep 2026). A routine defined by an earlier manifest file
// and dropped by a later one (scripts/sql/retire_orphaned_phase_governance_routines.sql retired twelve
// governance routines that way, each measured unused and recorded in scripts/sql/DROPPED.txt) is
// EXPECTED to be absent from production. Counting it as "in repository, missing from production" made
// a deliberate, recorded retirement look like drift, and the only ways to clear it were to excise the
// definition from the historical file — rewriting the record of what was applied — or to bring the
// routine back. Neither is right. The apply order decides: the last manifest file that speaks about a
// routine wins, and if that word is DROP the routine belongs on the retired side of the ledger — and a
// retired routine still on production is the drift, reported as its own line.
const DROP_RE = /^\s*drop\s+function\s+(?:if\s+exists\s+)?(?:([a-z_][\w]*)\s*\.\s*)?([a-z_][\w]*)\s*\(/gim;
const manifestDrops = new Map();               // key -> last {file, pos} that drops it
manifestFiles.forEach((f, pos) => {
  if (!existsSync(f)) return;
  const src = readFileSync(f, 'utf8');
  let m;
  while ((m = DROP_RE.exec(src)) !== null) {
    const key = (m[1] || 'public') + '.' + m[2];
    manifestDrops.set(key, { file: f, pos });
  }
});
// TWO KEYS, NOT ONE. scripts/sql/phase_c_ROLLBACK.sql sits in the apply order and drops 33 routines
// that are alive and meant to be — it is a rollback recipe, not an applied change — and a drop by bare
// name cannot tell one overload from another. So a drop in the apply order is only a RETIREMENT when
// scripts/sql/DROPPED.txt, the ledger of routines measured absent on purpose, names the routine too.
// A drop that the ledger does not confirm is reported as a count, never a finding.
const droppedLedger = new Set();
try {
  for (const raw of readFileSync('scripts/sql/DROPPED.txt', 'utf8').split('\n')) {
    const l = raw.trim();
    if (!l || l.startsWith('#')) continue;
    const name = l.split('::')[0].trim().replace(/\(.*$/, '');
    if (name) droppedLedger.add(name.includes('.') ? name : 'public.' + name);
  }
} catch { /* no ledger: nothing is retired, every drop is just a count */ }
const droppedLaterButUnconfirmed = [];
const retiredByManifest = (key) => {
  const drop = manifestDrops.get(key);
  const defs = manifestDefs.get(key) || [];
  const later = !!drop && defs.length > 0 && drop.pos > defs[defs.length - 1].pos;
  if (later && !droppedLedger.has(key)) { if (!droppedLaterButUnconfirmed.includes(key)) droppedLaterButUnconfirmed.push(key); return false; }
  return later;
};

// ================================================================ 1. IN REPO, NOT ON PRODUCTION
const repoOnly = [];
const retiredAbsent = [];                       // dropped after their last definition, and absent: correct
const retiredStillLive = [];                    // dropped after their last definition, and STILL live: drift
for (const [key, list] of manifestDefs) {
  if (retiredByManifest(key)) {
    if (liveByKey.has(key)) retiredStillLive.push({ key, file: manifestDrops.get(key).file });
    else retiredAbsent.push({ key, file: manifestDrops.get(key).file });
    continue;
  }
  if (!liveByKey.has(key)) repoOnly.push({ key, file: list[list.length - 1].file });
}
repoOnly.sort((a, b) => a.key.localeCompare(b.key));
retiredStillLive.sort((a, b) => a.key.localeCompare(b.key));

// ================================================================ 2. ON PRODUCTION, NOT IN REPO
// Scoped to the application estate. An extension's or the platform's code being absent from this
// repository is not a finding; it was never ours to hold.
const justified = new Set(ledger
  .filter(r => r.ownership_class === 'INTENTIONALLY_UNTRACKED_WITH_JUSTIFICATION'
            && (r.justification || '').trim().length >= 60)
  .map(r => `${r.schema_name}.${r.routine_name}`));
const liveOnly = appLive
  .filter(r => r.cls === 'NO_SOURCE_IN_REPOSITORY' && !justified.has(r.key))
  .map(r => `${r.key}(${r.args})`).sort();

// ================================================================ 3. CONFLICTING CURRENT DEFINITIONS
// A routine in more than one manifest file is NOT itself a finding: the manifest order names the
// ONE current source file and the question is answered. It becomes a finding when production does
// not run that file — the shape that hid fn_phase_c_event_ingress for a day.
const multiFile = [];
const conflicts = [];
for (const [key, list] of manifestDefs) {
  const files = [...new Set(list.map(d => d.file))];
  if (files.length < 2) continue;
  if (retiredByManifest(key)) continue;          // retired on purpose: absence is the expected state, not a conflict
  multiFile.push(key);
  const canonical = list[list.length - 1];
  const bodies = liveByKey.get(key) || [];
  if (canonical.body && bodies.includes(tokens(canonical.body))) continue;    // live runs canon: fine
  const superseded = list.slice(0, -1).find(d => d.body && bodies.includes(tokens(d.body)));
  conflicts.push({ key, files, canonical: canonical.file,
    why: !bodies.length ? 'not present on production'
      : superseded ? `production runs the SUPERSEDED ${superseded.file}`
      : 'production runs neither definition' });
}

// ================================================================ 4. DRIFTED APPLICATION ROUTINES
// Comparable means the canonical definition has a dollar-quoted body to compare. A definition with
// no body to read is NOT a pass — it is counted and named separately, because a check whose input
// vanished scoring 100 is how a missing source file once scored a pack at perfect.
const drifted = [], notComparable = [];
let comparable = 0;
for (const r of qdLive) {
  const list = manifestDefs.get(r.key);
  const canonical = list[list.length - 1];
  if (!canonical.body) { notComparable.push(`${r.key}  (${canonical.file})`); continue; }
  comparable++;
  const bodies = liveByKey.get(r.key) || [];
  if (bodies.includes(tokens(canonical.body))) continue;
  const superseded = list.slice(0, -1).find(d => d.body && bodies.includes(tokens(d.body)));
  drifted.push({ key: r.key, file: canonical.file,
    why: superseded ? `production runs the SUPERSEDED ${superseded.file}` : 'body differs from live prosrc' });
}
const driftedKeys = [...new Set(drifted.map(d => d.key))];

// ================================================================ 5. UNCOMMITTED APPLICATION DDL
const ddl = newDdlRecord();
for (const f of manifestFiles) if (existsSync(f)) eatDdl(ddl, readFileSync(f, 'utf8'));
let mirrorRead = false;
if (existsSync(SCHEMA_MIRROR)) { eatDdl(ddl, readFileSync(SCHEMA_MIRROR, 'utf8')); mirrorRead = true; }
const liveDdl = await q(LIVE_DDL_SQL);
const uncommitted = uncommittedDdl(ddl, liveDdl);

// ================================================================ 6. LEDGER vs REPOSITORY
// The database guard closes the catalogue direction: it will not let managed code be filed as
// application source, or application source be hidden inside the managed exclusion. It cannot see
// a git tree, so this closes the other direction — every MANIFEST/TRACKED claim recorded on
// production is re-derived here from the repository, and a claim the repository does not support
// is a finding.
const ledgerBad = [];
// The DERIVED truth for every row the comparison rejects, so the repair can be generated from the
// same derivation that found the drift instead of retyped by hand. kernel_s0b repaired SEVEN rows
// with seven hand-written UPDATEs; there are ninety now, and ninety hand-typed literals is a rubber
// stamp, not a reconciliation. `--emit-ledger-sync` prints the statements.
const ledgerFix = [];
// 3 SEP 2026: a ledger row whose CLASS the repository denies is a finding. A row whose source_file
// merely lags the manifest (a routine gained a newer canonical file) is a stale pointer, not a
// claim the repository denies: the canonical engine (line 7) already decides which file is
// canonical from the manifest itself, so this column was a mirror of a mirror and it reddened this
// gate every time a routine was re-homed. It is now reported and repaired by --emit-ledger-sync,
// never counted.
const ledgerStale = [];
if (ledgerPresent) {
  const liveKeyArgs = new Set(classified.map(r => `${r.key}|${r.args}`));
  for (const row of ledger) {
    const key = `${row.schema_name}.${row.routine_name}`;
    const derived = classify(classified.find(r => r.key === key && r.args === row.identity_args)
      || { sch: row.schema_name, nm: row.routine_name, owner: 'postgres', ext: '' });
    if (!liveKeyArgs.has(`${key}|${row.identity_args}`)) {
      ledgerBad.push(`${key}(${row.identity_args})  recorded, but no such routine is live`);
      continue;
    }
    if (row.ownership_class === 'INTENTIONALLY_UNTRACKED_WITH_JUSTIFICATION') {
      if (derived.cls !== 'NO_SOURCE_IN_REPOSITORY') {
        ledgerBad.push(`${key}(${row.identity_args})  filed untracked, but the repository DOES define it (${derived.rule})`);
      }
      continue;
    }
    const mList = manifestDefs.get(key) || [];
    const mCanonical = mList.length ? mList[mList.length - 1].file : null;
    if (derived.cls !== row.ownership_class) {
      ledgerBad.push(`${key}(${row.identity_args})  recorded ${row.ownership_class}, repository derives ${derived.cls}`);
      ledgerFix.push({ ...row, cls: derived.cls, rule: derived.rule,
                       kind: mCanonical ? 'MANIFEST' : row.source_kind,
                       file: mCanonical ?? row.source_file,
                       why: `recorded ${row.ownership_class}, repository derives ${derived.cls}` });
      continue;
    }
    if (row.source_kind === 'MANIFEST') {
      if (mCanonical !== row.source_file) {
        ledgerStale.push(`${key}(${row.identity_args})  records source_file ${row.source_file}, `
          + `manifest order says ${mCanonical ?? '(none)'}`);
        ledgerFix.push({ ...row, cls: derived.cls, rule: derived.rule, kind: 'MANIFEST',
                         file: mCanonical ?? row.source_file,
                         why: `records source_file ${row.source_file}, manifest order says ${mCanonical ?? '(none)'}` });
      }
    }
  }
}
ledgerBad.sort();

// ================================================================ REPORT
const pad = (n) => String(n).padStart(5);
const line = (label, num, den, note) =>
  `  ${label.padEnd(46)} ${pad(num)} / ${String(den).padEnd(6)}${note ? '  ' + note : ''}`;

console.log(`MANIFEST ${MANIFEST}: ${manifestFiles.length} file(s) in apply order.`);
console.log(`LIVE CATALOGUE: ${live.length} routine(s) across every non-system schema.\n`);

console.log('THE ESTATE SPLIT (mechanical; the rules are in scripts/sql/kernel_s0_routine_ownership.sql)');
for (const [k, v] of Object.entries(classCount).sort((a, b) => b[1] - a[1])) {
  console.log(`  ${k.padEnd(30)} ${pad(v)}`);
}
console.log(`  ${'-'.repeat(36)}`);
console.log(`  MANAGED, EXCLUDED FROM THIS GATE ${pad(classified.length - appLive.length)}   `
  + 'extension-owned by pg_depend, or owned by a platform role');
console.log(`  APPLICATION ESTATE, LIVE         ${pad(appLive.length)}   every one owned by `
  + `postgres in a QuotesDone schema`);
console.log(`  OF WHICH GATED HERE              ${pad(qdLive.length)}   QUOTESDONE_APPLICATION only`);
console.log(`  HISTORICAL_APPLICATION           ${pad(classCount.HISTORICAL_APPLICATION || 0)}   in the `
  + 'repository but outside the apply order, so no file is canonical and drift is not defined for');
console.log('                                          them. Not gated. Bringing them under the manifest is a separate increment.\n');

console.log('THE GATE — QUOTESDONE_APPLICATION SCOPE. Any non-zero fails.');
console.log(line('1. in repository, missing from production', repoOnly.length, manifestDefs.size,
  'denominator: routines any manifest file defines'));
for (const r of repoOnly) console.log(`        ${r.key}   canonical ${r.file}`);
console.log(line('1b. retired by the manifest (dropped after their last definition), still on production', retiredStillLive.length, manifestDefs.size,
  'the apply order says DROP; production still has it'));
for (const r of retiredStillLive) console.log(`        ${r.key}   dropped by ${r.file}`);
console.log(`      retired by the manifest and absent, as the apply order says: ${retiredAbsent.length} (not a finding)`);
console.log(`      dropped by a later manifest file but NOT confirmed by scripts/sql/DROPPED.txt, so not treated as retired: ${droppedLaterButUnconfirmed.length} (a count, not a finding; phase_c_ROLLBACK.sql is a rollback recipe in the apply order)`);

console.log(line('2. on production, missing from repository', liveOnly.length, appLive.length,
  'denominator: the live application estate'));
for (const s of liveOnly) console.log(`        ${s}`);

console.log(line('3. conflicting current definitions', conflicts.length, multiFile.length,
  'denominator: routines defined in >1 manifest file'));
for (const c of conflicts) {
  console.log(`        ${c.key}  — ${c.why}`);
  for (const f of c.files) console.log(`             ${f}${f === c.canonical ? '   <== CANONICAL (last in manifest)' : ''}`);
}
if (!conflicts.length && multiFile.length) {
  console.log(`        all ${multiFile.length} are informational: production runs the last manifest file in every case,`);
  console.log('        so each already has exactly ONE current source file and nothing needs changing.');
}

console.log(line('4. drifted application routines', driftedKeys.length, comparable,
  'denominator: canonical definitions with a body to compare'));
for (const d of drifted) console.log(`        ${d.key}  — ${d.why}\n             canonical ${d.file}`);
console.log(`        ${notComparable.length} canonical definition(s) carry no dollar-quoted body and could not be `
  + 'compared at all;');
console.log('        they are NOT counted as passing. Named here so the silence is visible:');
for (const s of notComparable.slice(0, 10)) console.log(`             ${s}`);
if (notComparable.length > 10) console.log(`             ... and ${notComparable.length - 10} more`);

console.log(line('5. uncommitted application DDL', uncommitted.length, liveDdl.length,
  'denominator: live public DDL objects examined'));
if (!mirrorRead) console.log(`        NOTE: ${SCHEMA_MIRROR} is missing, so this line measured against the manifest alone.`);
for (const s of uncommitted.slice(0, 20)) console.log(`        ${s}`);
if (uncommitted.length > 20) console.log(`        ... and ${uncommitted.length - 20} more`);

console.log(line('6. ledger claims the repository denies', ledgerBad.length, ledger.length,
  'denominator: rows in public.kernel_routine_ownership'));
if (ledgerStale.length) {
  console.log(`        stale source_file pointers (informational, repaired by --emit-ledger-sync): ${ledgerStale.length}`);
  for (const s of ledgerStale.slice(0, 10)) console.log(`          ${s}`);
}
if (!ledgerPresent) {
  console.log('        THIS LINE ASSERTS NOTHING. public.kernel_routine_ownership does not exist on production');
  console.log('        yet — scripts/sql/kernel_s0_routine_ownership.sql has not been applied. 0 of 0 here is an');
  console.log('        idle instrument, not a clean one.');
}
for (const s of ledgerBad.slice(0, 25)) console.log(`        ${s}`);
if (ledgerBad.length > 25) console.log(`        ... and ${ledgerBad.length - 25} more`);

// `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync > file.sql`
// prints the repair for line 6 from the SAME derivation that produced line 6. The point is that
// nobody retypes a classification: if the emitted file and the check ever disagree, the check is
// the one that is right, because the file came out of it.
if (process.argv.includes('--emit-ledger-sync')) {
  const lit = s => `'${String(s ?? '').replace(/'/g, "''")}'`;
  console.log(`-- Generated by: node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync`);
  console.log(`-- ${ledgerFix.length} row(s) where public.kernel_routine_ownership disagreed with the repository.\n`);
  for (const f of ledgerFix) {
    console.log(`update public.kernel_routine_ownership set`);
    console.log(`       ownership_class = ${lit(f.cls)}, classified_by_rule = ${lit(f.rule)},`);
    console.log(`       source_kind = ${lit(f.kind)}, source_file = ${lit(f.file)},`);
    console.log(`       evidence = ${lit(f.why + ' — reconciled mechanically 17 Aug 2026 (kernel_s0c).')}`);
    console.log(` where schema_name = ${lit(f.schema_name)} and routine_name = ${lit(f.routine_name)}`);
    console.log(`   and coalesce(identity_args,'') = ${lit(f.identity_args ?? '')};\n`);
  }
  process.exit(0);
}

// ================================================================ 7. ONE AUTHORITY, ENFORCED
//
// THIS FILE IS NOT THE AUTHORITY ON ROUTINE CANONICALITY. canonical_routine_manifest.mjs is.
//
// The independent acceptance (17 Aug 2026) found the two of them measuring the same production at
// the same commit and disagreeing — the engine said 0 findings, this file said 105 — with nothing
// anywhere that would notice. Both are green now, but "both happen to be green today" is not the
// same claim as "there is one authority", and the difference between those two sentences is a day
// of fn_phase_c_event_ingress running an unfixed body under a green instrument.
//
// So the agreement is asserted rather than hoped for. This file keeps the two subjects the engine
// does not cover — DDL objects (line 5) and the ownership ledger (line 6) — and on the subject they
// share, the engine's answer is the one that counts: if it and this file ever resolve a routine to
// different files, or the engine reports anything at all, THIS CHECK FAILS and names the routine.
// D6. A CSV row reader that honours quoting. The emitter wraps any field containing a comma in
// double quotes and doubles an embedded quote; anything less than this drops multi-argument
// signatures on the floor.
function parseCsvRow(row) {
  const out = [];
  let cur = '';
  let inQ = false;
  for (let i = 0; i < row.length; i++) {
    const c = row[i];
    if (inQ) {
      if (c === '"') {
        if (row[i + 1] === '"') { cur += '"'; i++; } else { inQ = false; }
      } else cur += c;
    } else if (c === '"') inQ = true;
    else if (c === ',') { out.push(cur); cur = ''; }
    else cur += c;
  }
  out.push(cur);
  return out;
}

// The parser is exercised before it is trusted: a quoted multi-argument signature must come back
// whole, and an unquoted row must be unaffected. Without this the fix is an assertion about itself.
{
  const probe = parseCsvRow('"public.fn_phase_d_rule_check(text,jsonb)",scripts/sql/x.sql,3');
  if (probe[0] !== 'public.fn_phase_d_rule_check(text,jsonb)' || probe[1] !== 'scripts/sql/x.sql') {
    throw new Error('parseCsvRow does not read a quoted multi-argument signature: ' + JSON.stringify(probe));
  }
  const plain = parseCsvRow('public.fn_x(),scripts/sql/y.sql,1');
  if (plain[0] !== 'public.fn_x()' || plain[1] !== 'scripts/sql/y.sql') {
    throw new Error('parseCsvRow broke an unquoted row: ' + JSON.stringify(plain));
  }
}

const engineDisagreements = [];
{
  // D6. `--emit` REWROTE A COMMITTED ARTEFACT AS A SIDE EFFECT OF `npm test`. It rewrote
  // docs/phase-c-final-kernel/CANONICAL_ROUTINE_MANIFEST.csv microseconds before the loop below
  // reads it, so the comparison was the engine against itself, and every `npm test` left a dirty
  // tree. This spawn needs only the exit status and the `countable findings N` line.
  //
  // Dropping the flag alone would FREEZE the CSV, because this was its only call site anywhere in
  // the repository — CI runs the engine without it (.github/workflows/project-parity.yml). So
  // `npm run regen:canonical-manifest` now exists and is the deliberate way to rewrite it.
  const r = spawnSync(process.execPath, ['scripts/checks/canonical_routine_manifest.mjs', '--all'],
    { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const engineFindings = Number((r.stdout || '').match(/countable findings\s+(\d+)/)?.[1] ?? -1);
  if (r.status !== 0 || engineFindings !== 0) {
    engineDisagreements.push(`the canonical engine exits ${r.status} with ${engineFindings} finding(s) — `
      + `it owns this subject, so its answer stands and this file cannot report the estate clean`);
  }
  const csv = 'docs/phase-c-final-kernel/CANONICAL_ROUTINE_MANIFEST.csv';
  if (existsSync(csv)) {
    for (const row of readFileSync(csv, 'utf8').split('\n').slice(1)) {
      // D6. ANY MULTI-ARGUMENT SIGNATURE CONTAINS A COMMA, so the emitter quotes the field and a
      // split on ',' truncated it at the first argument — `"public.fn_phase_d_rule_check(text`.
      // The key then had no ')' to slice at, `manifestDefs.get()` missed, and the `continue` two
      // lines down swallowed it. Measured: 403 of 1195 data rows, 33.7%, were silently skipped,
      // including every multi-argument Phase D routine — fn_phase_d_rule_check(text,jsonb),
      // fn_phase_d_schema_validate(text,jsonb), fn_phase_d_rule_applies(text,text),
      // fn_phase_d_gate_applies, fn_phase_d_gate_evaluate, fn_phase_d_handoff_packet_valid,
      // fn_phase_d_fixture_value, fn_phase_d_fixture_for_column, fn_phase_d_fixture_context.
      // A disagreement check blind to a third of the estate reports agreement it never tested.
      const cells = parseCsvRow(row);
      const sig = cells[0];
      const file = cells[1];
      if (!sig || !file) continue;
      const paren = sig.indexOf('(');
      if (paren < 0) continue;
      const key = sig.slice(0, paren);                            // engine keys by signature, this file by name
      const list = manifestDefs.get(key);
      if (!list || !list.length) continue;                        // engine sees tiers this file does not; not a disagreement
      const mine = list[list.length - 1].file;
      if (mine !== file && list.length === 1) {
        engineDisagreements.push(`${sig}: the engine resolves ${file}, this file resolves ${mine}`);
      }
    }
  } else {
    engineDisagreements.push(`${csv} was not produced by the engine, so the two could not be compared`);
  }
}
console.log(line('7. this file disagreeing with the canonical engine', engineDisagreements.length,
  manifestDefs.size, 'denominator: routines any manifest file defines. The engine owns this subject.'));
for (const s of engineDisagreements.slice(0, 25)) console.log(`        ${s}`);

const fail = repoOnly.length + retiredStillLive.length + liveOnly.length + conflicts.length + driftedKeys.length
           + uncommitted.length + ledgerBad.length + engineDisagreements.length;
console.log('\n---------------------------------------------------------------- SUMMARY');
console.log(line('1. in repository, missing from production', repoOnly.length, manifestDefs.size));
console.log(line('2. on production, missing from repository', liveOnly.length, appLive.length));
console.log(line('3. conflicting current definitions', conflicts.length, multiFile.length));
console.log(line('4. drifted application routines', driftedKeys.length, comparable));
console.log(line('5. uncommitted application DDL', uncommitted.length, liveDdl.length));
console.log(line('6. ledger claims the repository denies', ledgerBad.length, ledger.length));
console.log(line('7. disagreeing with the canonical engine', engineDisagreements.length, manifestDefs.size));
console.log(`  ${'-'.repeat(60)}`);
console.log(`  countable findings                             ${pad(fail)}          -> exit ${fail ? 1 : 0}`);

if (fail) {
  console.error('\nFAIL. Each line above is a place where the repository and production disagree about what '
    + 'the QuotesDone application IS. Fix by making the canonical file and production agree — never by '
    + 'moving a routine into the managed exclusion, which is the one repair this gate exists to refuse.');
  process.exit(1);
}
console.log('\nPASS. For every routine QuotesDone owns as source, exactly one file is canonical, production '
  + 'runs it, and the ownership ledger agrees with the repository.');
