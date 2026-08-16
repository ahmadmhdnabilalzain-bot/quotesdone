// THE MANIFEST IS THE SOURCE OF TRUTH, AND THIS IS THE CHECK THAT MAKES THAT MEAN SOMETHING.
//
// THE DEFECT THIS EXISTS TO CATCH, observed on 16 Aug 2026:
//   scripts/sql/phase_c_31_autonomous_entry_creates_work.sql and
//   scripts/sql/phase_c_39_consumer_must_not_reemit.sql BOTH define public.fn_phase_c_event_ingress,
//   and both were committed in the SAME commit (8eebbec). sql_files_match_live.test.mjs resolves a
//   routine to the newest file by GIT COMMIT TIME. A tie gives it no third fact, so it accepted
//   production matching EITHER candidate, matched the UNFIXED phase_c_31 body, and printed
//   "439 routines, 0 not present, 0 drifted". The phase_c_39 correction was in the repository and
//   NOT on production, and no instrument in this repo could see it.
//
// THE FIX IS AN ORDER, NOT A HEURISTIC: scripts/sql/MANIFEST.txt lists the apply order explicitly.
// The LAST file listed that defines a routine is CANONICAL. There is no tie to break, so there is
// nothing left to guess wrong.
//
// FIVE THINGS ARE COUNTED, and any non-zero count fails:
//   a. CONFLICTING DEFINITIONS  — a routine defined in more than one manifest file. Informational on
//                                 its own; it FAILS only when live disagrees with the canonical file,
//                                 which is exactly the state that hid on 16 Aug.
//   b. REPO -> LIVE DRIFT       — the canonical file body is not what is live. FAIL.
//   c. LIVE -> REPO DRIFT       — a live routine no manifest file defines. NO EXISTING CHECK MEASURES
//                                 THIS DIRECTION: sql_files_match_live starts from the files, so a
//                                 routine created by a migration, the dashboard or another session is
//                                 invisible to it forever. FAIL.
//   d. UNCOMMITTED PRODUCTION DDL — a live table/column/constraint/index in neither the manifest files
//                                 nor supabase/schema/full_schema.sql. FAIL.
//   e. MANIFEST GAPS            — a .sql file on disk that is not in the manifest, or a manifest line
//                                 whose file is gone. A manifest with a hole is not an order. FAIL.
//
// READ-ONLY. Every statement it sends is a SELECT.
//
//   node scripts/checks/canonical_routines.test.mjs
import { readdirSync, readFileSync, existsSync } from 'node:fs';

const DIR = 'scripts/sql';
const MANIFEST = `${DIR}/MANIFEST.txt`;
const SCHEMA_MIRROR = 'supabase/schema/full_schema.sql';
const PROD = 'htdblwldjkcgjvmqkbeh';

// Same credential path and the same loud skip as sql_files_match_live.test.mjs: this check must READ
// PRODUCTION, and CI has no management token. Failing a build for a missing credential teaches people
// to ignore the check; saying plainly that it asserted nothing does not.
const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
if (!token) {
  console.log('SKIPPED: no SUPABASE_ACCESS_TOKEN and no local access token, so production cannot be '
    + 'read. This check compares scripts/sql/MANIFEST.txt against the LIVE catalogue; run it from a '
    + 'session that has the management token. It is not asserting anything here.');
  process.exit(0);
}

// Identical normaliser to sql_files_match_live.test.mjs — compare on TOKENS, so indentation is not a
// finding but a changed identifier or literal is.
const tokens = (s) => (String(s).match(/[A-Za-z_$][\w$]*|\d+(?:\.\d+)?|'(?:[^']|'')*'|[^\sA-Za-z0-9_$]/g) || [])
  .join(' ').toLowerCase();

async function q(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if (!r.ok) { console.error('could not read production:', r.status, (await r.text()).slice(0, 300)); process.exit(1); }
  return r.json();
}

// ---------------------------------------------------------------- e. MANIFEST COMPLETENESS (first,
// because every other category reads the manifest and a manifest with a hole measures the wrong set)
if (!existsSync(MANIFEST)) {
  console.error(`${MANIFEST} does not exist. The apply order IS the source of truth; without it this `
    + 'check would be back to guessing from git timestamps, which is the defect it exists to catch.');
  process.exit(1);
}
const manifestLines = readFileSync(MANIFEST, 'utf8').split('\n')
  .map(l => l.replace(/#.*$/, '').trim()).filter(Boolean);
const seen = new Set();
const manifestFiles = [];
const duplicated = [];
for (const l of manifestLines) {
  const p = l.replace(/\\/g, '/');
  if (seen.has(p)) { duplicated.push(p); continue; }
  seen.add(p); manifestFiles.push(p);
}
const onDisk = readdirSync(DIR).filter(f => f.endsWith('.sql')).map(f => `${DIR}/${f}`);
const notInManifest = onDisk.filter(f => !seen.has(f)).sort();
const notOnDisk = manifestFiles.filter(f => !existsSync(f));
const manifestGaps = notInManifest.length + notOnDisk.length + duplicated.length;

// ---------------------------------------------------------------- parse the manifest files, IN ORDER
// name -> [{ file, body, pos }] in manifest order. The LAST entry is canonical, full stop.
const defs = new Map();
const declared = new Set();                              // every routine any manifest file defines
for (let pos = 0; pos < manifestFiles.length; pos++) {
  const f = manifestFiles[pos];
  if (!existsSync(f)) continue;
  const src = readFileSync(f, 'utf8');
  const re = /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z0-9_]+)\s*\(/gi;
  let m;
  while ((m = re.exec(src))) {
    const name = m[1].toLowerCase();
    declared.add(name);
    const rest = src.slice(m.index);
    const tag = rest.match(/as\s+(\$[a-z_]*\$)/i);
    if (!tag) continue;                                  // e.g. `language sql return ...`; nothing to diff
    const start = rest.indexOf(tag[1], rest.indexOf(tag[0])) + tag[1].length;
    const end = rest.indexOf(tag[1], start);
    if (end < 0) continue;
    if (!defs.has(name)) defs.set(name, []);
    defs.get(name).push({ file: f, body: rest.slice(start, end), pos });
  }
}

// ---------------------------------------------------------------- live routines
const liveRoutines = await q(
  `select p.proname n, p.prosrc s,
          exists(select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e') ext
     from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.prokind in ('f','p')`);
const liveBodies = new Map();                            // name -> [normalised body]  (overloads: any may match)
const liveOwn = new Set();                               // names not owned by an extension
const liveExt = new Set();
for (const row of liveRoutines) {
  if (row.ext) { liveExt.add(row.n); continue; }
  liveOwn.add(row.n);
  if (!liveBodies.has(row.n)) liveBodies.set(row.n, []);
  liveBodies.get(row.n).push(tokens(row.s));
}

// ---------------------------------------------------------------- a. CONFLICTING DEFINITIONS
const conflicts = [];
for (const [name, list] of defs) {
  const files = [...new Set(list.map(d => d.file))];
  if (files.length < 2) continue;
  const canonical = list[list.length - 1];
  const bodies = liveBodies.get(name) || [];
  const liveMatchesCanonical = bodies.includes(tokens(canonical.body));
  // A file EARLIER in the order matching live, while the canonical one does not, is the exact 16 Aug
  // shape: production is running a superseded definition and the newest correction never landed.
  const liveMatchesSuperseded = !liveMatchesCanonical
    && list.slice(0, -1).some(d => bodies.includes(tokens(d.body)));
  conflicts.push({ name, files, canonical: canonical.file, liveMatchesCanonical, liveMatchesSuperseded });
}

// ---------------------------------------------------------------- b. REPO -> LIVE DRIFT
const repoToLive = [];
for (const [name, list] of defs) {
  const canonical = list[list.length - 1];
  const bodies = liveBodies.get(name);
  if (!bodies) { repoToLive.push({ name, file: canonical.file, why: 'NOT PRESENT on production' }); continue; }
  if (bodies.includes(tokens(canonical.body))) continue;
  const supersededMatch = list.slice(0, -1).find(d => bodies.includes(tokens(d.body)));
  repoToLive.push({ name, file: canonical.file,
    why: supersededMatch ? `live matches the SUPERSEDED ${supersededMatch.file}` : 'body differs from live' });
}

// ---------------------------------------------------------------- c. LIVE -> REPO DRIFT
const liveToRepo = [...liveOwn].filter(n => !declared.has(n)).sort();
// A live routine the manifest does not define is still a finding, but "nowhere in the repository"
// and "in the pre-manifest migration history" are different problems and want different fixes, so
// the check says which. It does NOT excuse either: migrations_history has no apply order, so a
// routine recorded only there has no canonical file and nothing can tell you if it drifted.
const ELSEWHERE = ['supabase/migrations', 'supabase/migrations_history', 'supabase/migrations-superseded-consolidated'];
const elsewhereText = ELSEWHERE.filter(existsSync)
  .flatMap(d => readdirSync(d).filter(f => f.endsWith('.sql')).map(f => readFileSync(`${d}/${f}`, 'utf8')))
  .join('\n').toLowerCase();
const recordedElsewhere = liveToRepo.filter(n =>
  new RegExp(`create\\s+(or\\s+replace\\s+)?function\\s+(public\\.)?${n}\\s*\\(`).test(elsewhereText));

// ---------------------------------------------------------------- d. UNCOMMITTED PRODUCTION DDL
// The repository's record of DDL is the manifest files plus the schema mirror. Anything live that
// neither one mentions was created somewhere that left no record a future session could replay.
const repoTables = new Set(), repoCols = new Set(), repoIdx = new Set(), repoCons = new Set();
const eatDdl = (src) => {
  for (const m of src.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z0-9_]+)"?\s*\(/gi)) {
    const t = m[1].toLowerCase();
    repoTables.add(t);
    // Column list: from the opening paren to the line that closes it. Good enough for a dump and for
    // the hand-written create-tables in scripts/sql; anything it misses shows up as a finding, which
    // is the safe direction for a check to be wrong in.
    const block = src.slice(m.index + m[0].length);
    const close = block.search(/^\s*\)\s*;/m);
    for (const line of block.slice(0, close < 0 ? 4000 : close).split('\n')) {
      const c = line.trim().match(/^"?([a-z0-9_]+)"?\s+[a-z]/i);
      if (c && !/^(constraint|primary|unique|foreign|check|exclude|like)$/i.test(c[1])) {
        repoCols.add(`${t}.${c[1].toLowerCase()}`);
      }
      const inline = line.match(/\bconstraint\s+"?([a-z0-9_]+)"?/i);
      if (inline) repoCons.add(inline[1].toLowerCase());
    }
  }
  for (const m of src.matchAll(/alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?"?([a-z0-9_]+)"?[\s\S]{0,80}?add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z0-9_]+)"?/gi)) {
    repoCols.add(`${m[1].toLowerCase()}.${m[2].toLowerCase()}`);
  }
  for (const m of src.matchAll(/create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?"?([a-z0-9_]+)"?/gi)) {
    repoIdx.add(m[1].toLowerCase());
  }
  for (const m of src.matchAll(/add\s+constraint\s+"?([a-z0-9_]+)"?/gi)) repoCons.add(m[1].toLowerCase());
};
for (const f of manifestFiles) if (existsSync(f)) eatDdl(readFileSync(f, 'utf8'));
if (existsSync(SCHEMA_MIRROR)) eatDdl(readFileSync(SCHEMA_MIRROR, 'utf8'));
else console.log(`NOTE: ${SCHEMA_MIRROR} is missing, so category (d) is measuring against the manifest alone.`);

const liveDdl = await q(
  `select 'table' kind, c.relname obj, ''::text detail
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r','p')
      and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
   union all
   select 'column', c.relname, a.attname
     from pg_attribute a join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r','p') and a.attnum > 0 and not a.attisdropped
      and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
   union all
   select 'constraint', c.relname, con.conname
     from pg_constraint con join pg_class c on c.oid = con.conrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and con.contype in ('p','u','f','c','x')
      and not exists (select 1 from pg_depend d where d.objid = con.oid and d.deptype = 'e')
   union all
   select 'index', c.relname, i.relname
     from pg_index x join pg_class i on i.oid = x.indexrelid
     join pg_class c on c.oid = x.indrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and not exists (select 1 from pg_constraint k where k.conindid = x.indexrelid)
      and not exists (select 1 from pg_depend d where d.objid = i.oid and d.deptype = 'e')`);

const uncommittedDdl = [];
for (const row of liveDdl) {
  const t = row.obj.toLowerCase(), d = (row.detail || '').toLowerCase();
  if (row.kind === 'table' && !repoTables.has(t)) uncommittedDdl.push(`table       ${t}`);
  else if (row.kind === 'column' && !repoCols.has(`${t}.${d}`)) uncommittedDdl.push(`column      ${t}.${d}`);
  else if (row.kind === 'constraint' && !repoCons.has(d)) uncommittedDdl.push(`constraint  ${d}  on ${t}`);
  else if (row.kind === 'index' && !repoIdx.has(d)) uncommittedDdl.push(`index       ${d}  on ${t}`);
}
uncommittedDdl.sort();

// ---------------------------------------------------------------- report
const conflictFailures = conflicts.filter(c => !c.liveMatchesCanonical);
console.log(`MANIFEST ${MANIFEST}: ${manifestFiles.length} file(s), ${defs.size} routine(s) defined, `
  + `${liveOwn.size} live in public (+${liveExt.size} extension-owned).\n`);

console.log(`a. CONFLICTING DEFINITIONS (routine defined in more than one manifest file): ${conflicts.length}`);
for (const c of conflicts) {
  const verdict = c.liveMatchesCanonical ? 'live matches canonical — informational'
    : c.liveMatchesSuperseded ? '*** LIVE MATCHES A SUPERSEDED FILE — THE CORRECTION NEVER LANDED ***'
    : '*** live matches NEITHER definition ***';
  console.log(`   ${c.name}`);
  for (const f of c.files) console.log(`      defined in  ${f}${f === c.canonical ? '   <== CANONICAL (last in manifest)' : ''}`);
  console.log(`      ${verdict}`);
}

console.log(`\nb. REPO -> LIVE DRIFT (canonical file body != live prosrc): ${repoToLive.length}`);
for (const d of repoToLive) console.log(`   ${d.name.padEnd(42)} ${d.why}\n      canonical ${d.file}`);

console.log(`\nc. LIVE -> REPO DRIFT (live in public, defined by NO manifest file): ${liveToRepo.length}`);
for (const n of liveToRepo.slice(0, 60)) console.log(`   ${n}`);
if (liveToRepo.length > 60) console.log(`   ... and ${liveToRepo.length - 60} more`);
console.log(`   extension-owned functions excluded and reported separately: ${liveExt.size}`);
console.log(`   of the ${liveToRepo.length}: ${recordedElsewhere.length} are recorded in ${ELSEWHERE.join(' / ')} `
  + `(no apply order there, so still no canonical file), ${liveToRepo.length - recordedElsewhere.length} `
  + 'appear NOWHERE in the repository.');

console.log(`\nd. UNCOMMITTED PRODUCTION DDL (live, in neither the manifest nor ${SCHEMA_MIRROR}): ${uncommittedDdl.length}`);
for (const s of uncommittedDdl.slice(0, 20)) console.log(`   ${s}`);
if (uncommittedDdl.length > 20) console.log(`   ... and ${uncommittedDdl.length - 20} more`);

console.log(`\ne. MANIFEST GAPS: ${manifestGaps}`);
for (const f of notInManifest) console.log(`   ON DISK, NOT IN MANIFEST  ${f}   (append it at the bottom)`);
for (const f of notOnDisk) console.log(`   IN MANIFEST, NOT ON DISK  ${f}`);
for (const f of duplicated) console.log(`   LISTED TWICE              ${f}`);

const fail = conflictFailures.length + repoToLive.length + liveToRepo.length + uncommittedDdl.length + manifestGaps;
console.log('\n---------------------------------------------------------------- SUMMARY');
console.log(`  conflicting definitions      ${String(conflicts.length).padStart(5)}   (${conflictFailures.length} where live does not match canonical — those count)`);
console.log(`  repo -> live drift           ${String(repoToLive.length).padStart(5)}`);
console.log(`  live -> repo drift           ${String(liveToRepo.length).padStart(5)}`);
console.log(`  uncommitted production DDL   ${String(uncommittedDdl.length).padStart(5)}`);
console.log(`  manifest gaps                ${String(manifestGaps).padStart(5)}`);
console.log(`  ------------------------------------`);
console.log(`  countable findings           ${String(fail).padStart(5)}   -> exit ${fail ? 1 : 0}`);

if (fail) {
  console.error('\nFAIL. Every line above is a place where the repository and production disagree about '
    + 'what the code IS. Fix by making the canonical file and production agree — apply the file, or '
    + 'append a new file recording what production actually does. Raising no baseline here: the whole '
    + 'point of this check is that the last one had a number that could be right for the wrong reason.');
  process.exit(1);
}
console.log('\nPASS. The manifest, the files and production all say the same thing.');
