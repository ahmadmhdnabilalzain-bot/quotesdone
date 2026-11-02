// THE CANONICAL ROUTINE MANIFEST — one file per routine, chosen by an explicit sequence.
//
// WHAT THIS REPLACES, and why.
//   scripts/checks/sql_files_match_live.test.mjs resolves a routine to its newest file by GIT COMMIT
//   TIME, and for a tie inside one commit it accepts live if it matches ANY candidate. The final
//   Phase C audit (17 Aug 2026) found that mechanism certifying the wrong body:
//
//     operations_assistance_company_reports.sql  and  operations_company_remaining_lists.sql
//     were added in the SAME commit (deff052) and BOTH define public.fn_ws_operations and
//     public.fn_ws_company, with different bodies. Live matched the second. The check reported
//     0 drift, and a later session editing and applying the FIRST file would have silently reverted
//     both workspace readers with the check still printing 0.
//
//   A commit timestamp is not an apply order. This check never consults one.
//
// THE SEQUENCE, entirely explicit:
//
//     tier 1  supabase/migrations_history/<version>_*.sql   seq = 1 | <version>
//     tier 2  supabase/migrations/<version>_*.sql           seq = 2 | <version>
//     tier 3  ai-organization/db-functions/*.sql            seq = 3 | <filename>
//     tier 4  scripts/sql/*.sql                             seq = 4 | <line position in MANIFEST.txt>
//
//   The HIGHEST sequence that defines a routine is CANONICAL. Everything earlier is SUPERSEDED and
//   is named as such. Historical migrations are preserved and readable; they simply cannot be
//   current. Two files can only collide if they share a sequence key, and a shared key is itself a
//   failure — see AMBIGUOUS below — so there is never a tie left to break with a heuristic.
//
// SOURCES THAT MAY NEVER BE CANONICAL, recorded rather than silently ignored:
//     scripts/sql/rollback/**                          ROLLBACK
//     supabase/rollback/**                             ROLLBACK
//     supabase/migrations-superseded-consolidated/**   SUPERSEDED_CONSOLIDATED
//     supabase/seeds/**                                SEED
//     holdout_v2_eval/**                               EVAL_FIXTURE
//     vendor/**                                        THIRD_PARTY
//
// EXPLICIT SUPERSESSION: scripts/sql/SUPERSEDED.txt records (file :: routine :: superseded_by ::
//   reason) for a definition that must never win even though its file is still on disk. It is how a
//   competing definition is retired without editing an append-only record of a change that happened.
//
// WHAT FAILS (any non-zero count exits 1):
//   CONFLICTING  two files at the SAME sequence key both define one routine
//   AMBIGUOUS    a routine whose canonical file cannot be determined uniquely
//   REPO->PROD   the canonical body is not what is deployed
//   PROD->REPO   a live application routine no canonical file defines
//   MANIFEST GAP a scripts/sql file on disk that MANIFEST.txt does not list, or the reverse
//
// OWNERSHIP is decided by evidence, never by a name pattern, so an application routine cannot hide
// inside a "managed" exclusion: EXTENSION_MANAGED means pg_depend deptype='e'; SUPABASE_MANAGED
// means a Supabase-owned schema or role owns it; everything else in public is APPLICATION.
//
//   node scripts/checks/canonical_routine_manifest.mjs           check
//   node scripts/checks/canonical_routine_manifest.mjs --emit    check and write the CSV
//
// READ-ONLY against production. Every statement it sends is a SELECT.
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { readdirSync, readFileSync, existsSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname } from 'node:path';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { SCHEMA_MIRROR, readSchemaMirror } from '../lib/schema_mirror.mjs';

const ROOT = process.cwd().replace(/\\/g, '/');
const PROD = 'htdblwldjkcgjvmqkbeh';
const MANIFEST = 'scripts/sql/MANIFEST.txt';
const SUPERSEDED = 'scripts/sql/SUPERSEDED.txt';
// 9 Sep 2026: the emit target moved to docs/. It used to sit inside one of the nine Phase A-D
// documentation trees, and those were deleted on the founder's instruction. The check itself is
// unchanged — it measures production, and this CSV is a --emit side output nothing asserts against.
const CSV_OUT = 'docs/CANONICAL_ROUTINE_MANIFEST.csv';
const EMIT = process.argv.includes('--emit');
const ALL = process.argv.includes('--all');   // print every finding instead of the first 25

const sha = s => createHash('sha256').update(String(s), 'utf8').digest('hex');
// Compare on TOKENS: indentation is not a finding, a changed identifier or literal is.
const tokens = s => (String(s).match(/[A-Za-z_$][\w$]*|\d+(?:\.\d+)?|'(?:[^']|'')*'|[^\sA-Za-z0-9_$]/g) || [])
  .join(' ').toLowerCase();
// The schema mirror is a directory of parts read as one (scripts/lib/schema_mirror.mjs); a missing part THROWS
// there rather than reading as null, so the mirror can never silently look empty to this check.
const read = p => { if (p === SCHEMA_MIRROR) return readSchemaMirror(); try { return readFileSync(`${ROOT}/${p}`, 'utf8'); } catch { return null; } };
const lsSql = d => { try { return readdirSync(`${ROOT}/${d}`).filter(f => f.endsWith('.sql')).map(f => `${d}/${f}`); } catch { return []; } };

// ---------------------------------------------------------------- the sequence
// A MANIFEST line is a PATH, and a path that arrived quoted, BOM-prefixed or tab-padded is the same
// path. Both prefix tests below used to run on a merely-trimmed line, so a quoted entry would have
// been SKIPPED — not reported, skipped, which is the failure mode that matters: a file listed but
// invisible to the order check reads exactly like a file that was never listed at all.
// `grep -c '^"' scripts/sql/MANIFEST.txt` returns 0 over all 1,524 lines today, so the blind spot
// has never been hit. It is closed here in mechanism rather than left closed in fact.
const manifestPath = (l) => l.replace(/^﻿/, '').trim().replace(/^["']+|["']+$/g, '').trim();
const manifestLines = (read(MANIFEST) || '').split(/\r?\n/);
const manifestPos = new Map();
manifestLines.forEach((l, i) => {
  const p = manifestPath(l);
  if (p.startsWith('scripts/sql/') && p.endsWith('.sql') && !manifestPos.has(p)) manifestPos.set(p, i + 1);
});

const NON_CANONICAL = [
  [/^scripts\/sql\/rollback\//, 'ROLLBACK'],
  [/^supabase\/rollback\//, 'ROLLBACK'],
  [/^supabase\/migrations-superseded-consolidated\//, 'SUPERSEDED_CONSOLIDATED'],
  [/^supabase\/seeds\//, 'SEED'],
  [/^holdout_v2_eval\//, 'EVAL_FIXTURE'],
  [/^vendor\//, 'THIRD_PARTY'],
];

/** The explicit sequence key for a file, or null when the file may never be canonical. */
function sequenceOf(file) {
  for (const [re, why] of NON_CANONICAL) if (re.test(file)) return { key: null, why };
  let m = file.match(/^supabase\/migrations_history\/(\d+)_/);
  if (m) return { key: `1|${m[1].padStart(20, '0')}`, version: m[1], tier: 1 };
  m = file.match(/^supabase\/migrations\/(\d+)_/);
  if (m) return { key: `2|${m[1].padStart(20, '0')}`, version: m[1], tier: 2 };
  if (/^ai-organization\/db-functions\//.test(file)) {
    return { key: `3|${file.split('/').pop()}`, version: file.split('/').pop(), tier: 3 };
  }
  if (/^scripts\/sql\/[^/]+\.sql$/.test(file)) {
    const pos = manifestPos.get(file);
    if (!pos) return { key: null, why: 'NOT_IN_MANIFEST' };
    return { key: `4|${String(pos).padStart(6, '0')}`, version: `MANIFEST:${pos}`, tier: 4 };
  }
  return { key: null, why: 'UNCLASSIFIED_LOCATION' };
}

// ---------------------------------------------------------------- explicit supersession
const superseded = new Set();   // `${file}::${routine}`
const supersededBy = new Map();
for (const line of (read(SUPERSEDED) || '').split(/\r?\n/)) {
  const l = line.trim();
  if (!l || l.startsWith('#')) continue;
  const [file, routine, by, ...rest] = l.split('::').map(s => s.trim());
  if (!file || !routine) continue;
  superseded.add(`${file}::${routine.toLowerCase()}`);
  supersededBy.set(`${file}::${routine.toLowerCase()}`, { by, reason: rest.join('::') });
}

// ---------------------------------------------------------------- every definition in the repo
/** Every CREATE FUNCTION in a file: name, declared arg text, dollar-quoted body. */
function definitionsIn(file) {
  const t = read(file);
  if (t === null) return [];
  const out = [];
  const re = /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?([a-z0-9_]+)"?\s*\(/gi;
  let m;
  while ((m = re.exec(t))) {
    const from = m.index;
    const rest = t.slice(from);
    // declared arguments: from the opening paren to its match, shallow but sufficient to record
    const open = rest.indexOf('(');
    let depth = 0, close = -1;
    for (let i = open; i < rest.length && i < open + 4000; i++) {
      if (rest[i] === '(') depth++;
      else if (rest[i] === ')') { depth--; if (depth === 0) { close = i; break; } }
    }
    const args = close > open ? rest.slice(open + 1, close).replace(/\s+/g, ' ').trim() : '';
    // The body opener is the dollar quote that follows `as`. Anchoring on `as` keeps a positional
    // parameter like $1 in a default out of it, and the tag may carry digits — $k34$, $w14$ — which
    // an [A-Za-z_] class silently skipped, losing every kernel routine from the manifest.
    const dq = rest.match(/\bas\s*(\$[A-Za-z0-9_]*\$)/i);
    let body = null;
    if (dq) {
      const tag = dq[1];
      const s = rest.indexOf(tag, dq.index) + tag.length;
      const e = rest.indexOf(tag, s);
      if (e > s) body = rest.slice(s, e);
    }
    out.push({ name: m[1].toLowerCase(), args, body });
  }
  // Within ONE file the later statement wins deterministically, so a redefinition is not a conflict.
  // Distinct argument lists are overloads and both survive. Key on (name, normalised args).
  const last = new Map();
  for (const d of out) last.set(`${d.name}(${tokens(d.args)})`, d);
  return [...last.values()];
}

// FILES COMMITTED AND DELIBERATELY NOT APPLIED have one note each, scripts/sql/pending/<name>.txt
// (scripts/lib/pending_sql.mjs), and are excluded from the canonical scan below. A file that has not
// run is not the canonical definition of anything — including it would report repository -> production
// drift for a change nobody has made yet, which is exactly what a pending founder decision looks like
// from here. An empty note excludes nothing; it is reported below.
const NOTES = pendingNotes();
const PENDING = new Map([...NOTES].filter(([, why]) => why));

const FILES = [
  ...lsSql('supabase/migrations_history'),
  ...lsSql('supabase/migrations'),
  ...lsSql('ai-organization/db-functions'),
  ...lsSql('scripts/sql'),
  ...lsSql('scripts/sql/rollback'),
  ...lsSql('supabase/migrations-superseded-consolidated'),
  ...lsSql('supabase/rollback'),
].filter((f) => !PENDING.has(f));

// name -> [{file, seqKey, tier, version, args, body, canonicalEligible, whyNot}]
const byRoutine = new Map();
for (const file of FILES) {
  const seq = sequenceOf(file);
  for (const d of definitionsIn(file)) {
    if (!byRoutine.has(d.name)) byRoutine.set(d.name, []);
    const explicitlySuperseded = superseded.has(`${file}::${d.name}`);
    byRoutine.get(d.name).push({
      file, ...d,
      seqKey: seq.key, tier: seq.tier ?? null, version: seq.version ?? '',
      eligible: Boolean(seq.key) && !explicitlySuperseded && d.body !== null,
      whyNot: !seq.key ? (seq.why || 'NO_SEQUENCE') : explicitlySuperseded ? 'EXPLICITLY_SUPERSEDED'
        : d.body === null ? 'NO_PARSEABLE_BODY' : '',
    });
  }
}

// ---------------------------------------------------------------- pick the canonical file
const CONFLICTING = [], AMBIGUOUS = [];
const canonical = new Map();     // name -> chosen entry
for (const [name, defs] of byRoutine) {
  const eligible = defs.filter(d => d.eligible);
  if (!eligible.length) continue;
  const top = eligible.reduce((a, b) => (b.seqKey > a.seqKey ? b : a));
  const tied = eligible.filter(d => d.seqKey === top.seqKey);
  const tiedFiles = [...new Set(tied.map(d => d.file))];
  if (tiedFiles.length > 1) {
    // TWO FILES at ONE sequence key. The order cannot decide, so nothing may.
    const bodies = new Set(tied.map(d => tokens(d.body)));
    CONFLICTING.push({ name, seqKey: top.seqKey, files: tiedFiles, distinctBodies: bodies.size });
    AMBIGUOUS.push({ name, files: tiedFiles });
    continue;
  }
  // One file, possibly carrying several overloads of this name. All of them are canonical.
  canonical.set(name, {
    ...top,
    bodies: tied.map(d => ({ args: d.args, body: d.body })),
    superseded: [...new Set(defs.filter(d => d.file !== top.file).map(d => d.file))],
  });
}

// ---------------------------------------------------------------- manifest integrity
const diskScripts = new Set(lsSql('scripts/sql'));
const GAPS = [];

// A FILE COMMITTED AND DELIBERATELY NOT APPLIED IS A STATED FACT, NOT A GAP.
//
// PCCR-006 is the case this exists for: a security correction to a FROZEN Phase C contract that may
// not be applied until the founder approves it in a verified session. Committing it is required —
// the approval names a digest of something that must already exist — and applying it from a
// migration would be the exact defect it closes. Before this, such a file read as "ON DISK, NOT IN
// MANIFEST", which is the same words this check uses for a file somebody forgot.
//
// scripts/sql/pending/<name>.txt carries the REASON for scripts/sql/<name>.sql. A file with a note AND
// a MANIFEST line is refused: it cannot be both applied and pending, and letting that pass would be a
// way to hide an apply. AN EMPTY NOTE IS AN EXCLUSION NOBODY EXPLAINED, and it would be a way to hide a
// file from the canonical scan. The PENDING map above skips such a note; this reports it.
// The retired shared list must not come back through a branch cut before 22 Sep 2026: its entries would
// be read by nothing.
if (existsSync('scripts/sql/PENDING.txt')) GAPS.push('RETIRED LIST REAPPEARED     scripts/sql/PENDING.txt — convert each entry to scripts/sql/pending/<name>.txt');
for (const [f, why] of NOTES) if (!why) GAPS.push(`PENDING ENTRY WITH NO REASON  ${f} (its note in scripts/sql/pending/ is empty)`);
for (const [f, why] of PENDING) {
  if (manifestPos.has(f)) GAPS.push(`PENDING AND ALSO IN MANIFEST  ${f} — a file cannot be both applied and pending`);
  else if (!diskScripts.has(f)) GAPS.push(`PENDING, NOT ON DISK  ${f}`);
  else console.log(`   PENDING (committed, deliberately not applied)  ${f}\n      ${why.replace(/\r?\n/g, '\n      ')}`);
}

// A PENDING NOTE IS NOT A PLACE TO LIVE (it_engineer, outcome audit 30 Sep 2026). #1007 merged 28 Sep with
// its routines in a pending/ note and never got applied; this check read 0 drift for two days because a
// pending file is excluded from the scan above. A non-probe note older than 24 h on the branch is now a
// finding naming the file and the PR that added it. Age comes from git, so a shallow clone cannot measure
// it - that is a finding too, never a silent pass (the parity job checks out with fetch-depth: 0).
{
  const { execFileSync } = await import('node:child_process');
  const git = (...a) => execFileSync('git', a, { encoding: 'utf8' }).trim();
  // A shallow clone shows every file as added by its boundary commit, dated at the tip: that would read
  // as young and pass. A note whose adding commit IS a shallow boundary cannot be dated, and says so.
  let boundary = null;
  try {
    const p = git('rev-parse', '--git-path', 'shallow');
    boundary = new Set(existsSync(p) ? readFileSync(p, 'utf8').split(/\s+/).filter(Boolean) : []);
  } catch { /* no git at all: every note below is unmeasurable */ }
  // Age is measured ON MAIN: the date the note's adding commit reached origin/main (HEAD when there is no
  // origin/main). A note only on this branch is an open PR's own "apply at merge" note, not a stale one.
  // On a pull_request run a stale note on main is PRINTED, not counted: like production drift, a finding
  // already on main must not red every unrelated PR (code review of this change). Push-to-main and the
  // daily run fail on it, and that is where it belongs.
  let ref = 'HEAD';
  try { git('rev-parse', '--verify', '--quiet', 'origin/main'); ref = 'origin/main'; } catch { /* no remote ref */ }
  const onPr = process.env.GITHUB_EVENT_NAME === 'pull_request';
  const stale = [...PENDING].filter(([f, why]) => !f.endsWith('_probe.sql') && !/^\s*A PROBE\b/.test(why));
  for (const [f] of stale) {
    const note = `scripts/sql/pending/${f.slice('scripts/sql/'.length, -4)}.txt`;
    const [hash, when, subject = ''] = boundary
      ? git('log', '-1', '--diff-filter=A', '--format=%H%x09%cI%x09%s', ref, '--', note).split('\t') : [];
    if (boundary && !hash) continue;   // not on main yet: this branch adds it
    if (!boundary || boundary.has(hash)) {
      // The parity job checks out full history and sets QD_REQUIRE_GIT_HISTORY=1, so there this is a finding.
      // Elsewhere (the shallow static checks job, a local shallow clone) it is said out loud, not counted.
      const line = `PENDING AGE UNMEASURABLE  ${f} — no full git history to date its note (fetch-depth: 0, or git fetch --unshallow)`;
      if (process.env.QD_REQUIRE_GIT_HISTORY === '1') GAPS.push(line); else console.log(`   ${line}  (not counted here)`);
      continue;
    }
    if ((Date.now() - Date.parse(when)) / 36e5 <= 24) continue;
    const pr = (subject.match(/\(#(\d+)\)/) || [])[1];
    const line = `PENDING OVER 24 H ON MAIN  ${f} — note reached main ${when} by ${pr ? `PR #${pr}` : `"${subject.slice(0, 80)}"`}; apply it with its MANIFEST line or delete it`;
    if (onPr) console.log(`   ${line}  (reported, not counted, on a pull request)`); else GAPS.push(line);
  }
}

for (const f of diskScripts) if (!manifestPos.has(f) && !PENDING.has(f)) GAPS.push(`ON DISK, NOT IN MANIFEST  ${f}`);
for (const f of manifestPos.keys()) if (!diskScripts.has(f)) GAPS.push(`IN MANIFEST, NOT ON DISK  ${f}`);
{
  const seen = new Set();
  for (const l of manifestLines) {
    const p = manifestPath(l);
    if (!p.startsWith('scripts/sql/') || !p.endsWith('.sql')) continue;
    if (seen.has(p)) GAPS.push(`LISTED TWICE              ${p}`);
    seen.add(p);
  }
}

// ---------------------------------------------------------------- production
const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

async function q(text) {
  for (let a = 0; ; a++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: text }),
    });
    const body = await r.text();
    if ((r.status === 429 || r.status >= 500) && a < 6) { await new Promise(z => setTimeout(z, 2000 * 2 ** a)); continue; }
    if (!r.ok) throw new Error(`HTTP ${r.status}: ${body.slice(0, 500)}`);
    return JSON.parse(body);
  }
}

const REPO_ONLY = !token;
let live = [];
if (!REPO_ONLY) {
  live = await q(`
    select p.proname,
           pg_get_function_identity_arguments(p.oid) as sig_args,
           p.prosrc,
           n.nspname,
           pg_get_userbyid(p.proowner) as owner,
           (select count(*) from pg_depend d where d.objid = p.oid and d.deptype = 'e') as ext
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
     order by p.proname`);
}

const SUPABASE_ROLES = new Set(['supabase_admin', 'supabase_auth_admin', 'supabase_storage_admin',
  'supabase_realtime_admin', 'supabase_functions_admin', 'pgbouncer', 'supabase_read_only_user']);
const ownership = r => Number(r.ext) > 0 ? 'EXTENSION_MANAGED'
  : SUPABASE_ROLES.has(r.owner) ? 'SUPABASE_MANAGED' : 'APPLICATION';

const liveByName = new Map();
for (const r of live) {
  if (!liveByName.has(r.proname)) liveByName.set(r.proname, []);
  liveByName.get(r.proname).push(r);
}

const REPO_TO_PROD = [], PROD_TO_REPO = [], RECORDED_ABSENCES = [];
if (!REPO_ONLY) {
  // A routine that is GONE on purpose and a routine that FAILED TO DEPLOY must not share a counter.
  // scripts/sql/DROPPED.txt records the measured absence; it asserts nothing about why.
  const droppedReg = new Map();
  for (const line of (read('scripts/sql/DROPPED.txt') || '').split(/\r?\n/)) {
    const l = line.trim();
    if (!l || l.startsWith('#')) continue;
    const [n, ...rest] = l.split('::').map(s => s.trim());
    if (n) droppedReg.set(n.toLowerCase(), rest.join(' :: '));
  }
  for (const [name, c] of canonical) {
    const rows = liveByName.get(name);
    if (!rows) {
      if (droppedReg.has(name)) { RECORDED_ABSENCES.push({ name, file: c.file, note: droppedReg.get(name) }); continue; }
      REPO_TO_PROD.push({ name, file: c.file, why: 'NOT PRESENT on production' });
      continue;
    }
    // Every canonical body must be live, and every live overload must be a canonical body. One
    // direction alone lets an extra deployed overload, or an unapplied one, pass unseen.
    const src = new Set(c.bodies.map(b => tokens(b.body)));
    const dep = new Set(rows.map(r => tokens(r.prosrc)));
    const missing = [...src].filter(b => !dep.has(b)).length;
    const extra = [...dep].filter(b => !src.has(b)).length;
    if (missing || extra) {
      REPO_TO_PROD.push({
        name, file: c.file,
        why: `DRIFTED — ${missing} canonical body(ies) not deployed, ${extra} deployed body(ies) not in the canonical file (${rows.length} live overload(s), ${src.size} canonical)`,
      });
    }
  }
  // The schema mirror is an ATTESTATION of the deployed shape, not a change in the apply order, so
  // it never becomes canonical. It answers one narrower question: is this routine committed to main
  // at all? A routine in neither a change file nor the mirror is genuinely absent from the repository.
  const mirror = new Set(definitionsIn(SCHEMA_MIRROR).map(d => d.name));
  for (const r of live) {
    if (ownership(r) !== 'APPLICATION') continue;
    if (canonical.has(r.proname)) continue;
    PROD_TO_REPO.push({
      name: r.proname, args: r.sig_args, owner: r.owner,
      mirror: mirror.has(r.proname) ? 'in the schema mirror only, with no change file' : 'in NO repository file',
    });
  }
}

// ---------------------------------------------------------------- uncommitted application DDL
// The repository's record of DDL is every canonical-tier file plus the schema mirror. Anything live
// that neither mentions was created somewhere that left no record a future session could replay.
//
// TWO MATCHER DEFECTS ARE FIXED HERE, both of which reported COMMITTED ddl as uncommitted:
//   * `alter table t add column a, add column b, add column c` was read as ONE column. Three
//     columns of phase_c_historical_repair, all committed in kernel_k23, were reported missing.
//   * a constraint declared INLINE — `signal_id bigserial primary key` — is auto-named by Postgres
//     (`<table>_pkey`, `<table>_<col>_key`, `<table>_<col>_fkey`) and that name appears in no file.
//     Eleven kernel constraints, every one of them committed, were reported missing.
const UNCOMMITTED_DDL = [];
// DATED ROLLBACK OBJECTS (7 Oct 2026, it_engineer). The kb_chunks copy-and-swap (#1220, docs/runbooks/kb_chunks_rewrite.md)
// keeps the pre-swap table as kb_chunks_old: the rollback, by design in no canonical file. It is named here by TABLE
// with a hard expiry, never by pattern: on or after the date the exemption ends and every object of that table counts
// again, so a rollback copy that outlives its runbook step 8 drop turns this check red. Measured 6 Oct 22:01 UTC: 27
// objects (table, columns, constraints, indexes); with the date set in the past the check reported all 27 (exit 1).
// The drop waits for sales_engineer Arabic recall back at its 0.55 floor (0.548 on 7 Oct).
const ROLLBACK_OBJECTS = { kb_chunks_old: '2026-10-13' };   // table -> expiry (UTC date); runbook step 8 drops it
const rollbackExempt = t => Object.hasOwn(ROLLBACK_OBJECTS, t) && new Date().toISOString().slice(0, 10) < ROLLBACK_OBJECTS[t];
if (!REPO_ONLY) {
  const repoTables = new Set(), repoCols = new Set(), repoIdx = new Set(), repoCons = new Set();
  const eatDdl = src => {
    for (const m of src.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z0-9_]+)"?\s*\(/gi)) {
      const t = m[1].toLowerCase();
      repoTables.add(t);
      const block = src.slice(m.index + m[0].length);
      const close = block.search(/^\s*\)\s*;/m);
      const body = block.slice(0, close < 0 ? 8000 : close);
      for (const line of body.split('\n')) {
        const c = line.trim().match(/^"?([a-z0-9_]+)"?\s+[a-z]/i);
        if (c && !/^(constraint|primary|unique|foreign|check|exclude|like)$/i.test(c[1])) {
          const col = c[1].toLowerCase();
          repoCols.add(`${t}.${col}`);
          // auto-generated names for constraints declared on the column itself
          if (/\bunique\b/i.test(line)) repoCons.add(`${t}_${col}_key`);
          if (/\breferences\b/i.test(line)) repoCons.add(`${t}_${col}_fkey`);
          if (/\bprimary\s+key\b/i.test(line)) repoCons.add(`${t}_pkey`);
          if (/\bcheck\s*\(/i.test(line)) repoCons.add(`${t}_${col}_check`);
        }
        const named = line.match(/\bconstraint\s+"?([a-z0-9_]+)"?/i);
        if (named) repoCons.add(named[1].toLowerCase());
        if (/^\s*primary\s+key\s*\(/i.test(line)) repoCons.add(`${t}_pkey`);
        if (/^\s*unique\s*\(/i.test(line)) {
          const cols = (line.match(/\(([^)]*)\)/) || [, ''])[1].split(',').map(s => s.trim().replace(/"/g, ''));
          repoCons.add(`${t}_${cols.join('_')}_key`);
        }
        if (/^\s*foreign\s+key\s*\(/i.test(line)) {
          const cols = (line.match(/\(([^)]*)\)/) || [, ''])[1].split(',').map(s => s.trim().replace(/"/g, ''));
          repoCons.add(`${t}_${cols.join('_')}_fkey`);
        }
      }
    }
    // EVERY `add column` in the statement, not just the first one after `alter table`.
    for (const m of src.matchAll(/alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?"?([a-z0-9_]+)"?([\s\S]*?);/gi)) {
      const t = m[1].toLowerCase();
      for (const c of m[2].matchAll(/add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z0-9_]+)"?/gi)) {
        repoCols.add(`${t}.${c[1].toLowerCase()}`);
      }
    }
    for (const m of src.matchAll(/create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?"?([a-z0-9_]+)"?/gi)) repoIdx.add(m[1].toLowerCase());
    for (const m of src.matchAll(/add\s+constraint\s+"?([a-z0-9_]+)"?/gi)) repoCons.add(m[1].toLowerCase());
  };
  for (const f of [...FILES, SCHEMA_MIRROR]) { const s = read(f); if (s) eatDdl(s); }

  const liveDdl = await q(`
    select 'table' kind, c.relname obj, ''::text detail
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relkind in ('r','p')
       and not exists (select 1 from pg_depend d where d.objid=c.oid and d.deptype='e')
    union all
    select 'column', c.relname, a.attname
      from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relkind in ('r','p') and a.attnum>0 and not a.attisdropped
       and not exists (select 1 from pg_depend d where d.objid=c.oid and d.deptype='e')
    union all
    select 'constraint', c.relname, con.conname
      from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and con.contype in ('p','u','f','c','x')
       and not exists (select 1 from pg_depend d where d.objid=con.oid and d.deptype='e')
    union all
    select 'index', c.relname, i.relname
      from pg_index x join pg_class i on i.oid=x.indexrelid join pg_class c on c.oid=x.indrelid
      join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public'
       and not exists (select 1 from pg_constraint k where k.conindid=x.indexrelid)
       and not exists (select 1 from pg_depend d where d.objid=i.oid and d.deptype='e')`);
  for (const row of liveDdl) {
    const t = row.obj.toLowerCase(), d = (row.detail || '').toLowerCase();
    if (rollbackExempt(t)) continue;
    if (row.kind === 'table' && !repoTables.has(t)) UNCOMMITTED_DDL.push(`table       ${t}`);
    else if (row.kind === 'column' && !repoCols.has(`${t}.${d}`)) UNCOMMITTED_DDL.push(`column      ${t}.${d}`);
    else if (row.kind === 'constraint' && !repoCons.has(d)) UNCOMMITTED_DDL.push(`constraint  ${d}  on ${t}`);
    else if (row.kind === 'index' && !repoIdx.has(d)) UNCOMMITTED_DDL.push(`index       ${d}  on ${t}`);
  }
  UNCOMMITTED_DDL.sort();
}

// ---------------------------------------------------------------- the CSV
if (EMIT) {
  const esc = v => { const s = v == null ? '' : String(v).replace(/\s+/g, ' ').trim(); return /[",]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
  const rows = [];
  const names = new Set([...canonical.keys(), ...liveByName.keys()]);
  for (const name of [...names].sort()) {
    const c = canonical.get(name);
    // DETERMINISTIC OVERLOAD ORDER. `lv` arrives in whatever order the catalogue query returned it,
    // and for a multi-overload name — pgvector's array_to_vector, cosine_distance, l2_norm,
    // l2_normalize, inner_product, vector_dims — that order moves between runs. Both
    // routine_signature and deployed_sha256 are built from it, so the committed CSV churned on
    // every regeneration: measured 18 Aug 2026, eleven rows differed with identical content, and a
    // real change (fn_kernel_truncate_protection_state, and trg_contact_message_to_kernel moving to
    // its current canonical file) sat in the middle of that noise. An artefact whose diff cannot be
    // read is an artefact nobody checks. Sorted by signature so a diff means a change.
    const lv = (liveByName.get(name) || [])
      .slice()
      .sort((a, b) => String(a.sig_args).localeCompare(String(b.sig_args)));
    const cls = lv.length ? [...new Set(lv.map(ownership))].join('+') : (c ? 'APPLICATION (not deployed)' : 'UNKNOWN');
    const srcHashes = c ? c.bodies.map(b => sha(tokens(b.body))) : [];
    const depHashes = lv.map(r => sha(tokens(r.prosrc)));
    const matched = c && srcHashes.length === depHashes.length
      && srcHashes.every(h => depHashes.includes(h)) && depHashes.every(h => srcHashes.includes(h));
    rows.push({
      routine_signature: lv.length ? lv.map(r => `public.${name}(${r.sig_args})`).join(' | ')
        : (c ? c.bodies.map(b => `public.${name}(${b.args})`).join(' | ') : `public.${name}()`),
      canonical_current_sql_file: c ? c.file : '',
      migration_sequence_version: c ? `${c.seqKey}  (${c.version})` : '',
      source_sha256: srcHashes.join(' | '),
      deployed_sha256: depHashes.join(' | '),
      source_matches_deployed: c ? String(Boolean(matched)) : '',
      superseded_source_files: c ? c.superseded.join(' ; ') : (byRoutine.get(name) || []).map(d => d.file).join(' ; '),
      ownership_classification: cls,
      live_overloads: String(lv.length),
    });
  }
  const cols = Object.keys(rows[0]);
  mkdirSync(`${ROOT}/${dirname(CSV_OUT)}`, { recursive: true });
  writeFileSync(`${ROOT}/${CSV_OUT}`, [cols.join(','), ...rows.map(r => cols.map(c => esc(r[c])).join(','))].join('\n') + '\n');
  console.log(`wrote ${CSV_OUT}  (${rows.length} rows)`);
}

// ---------------------------------------------------------------- report
const show = (title, list, fmt) => {
  console.log(`\n${title}: ${list.length}`);
  const cap = ALL ? list.length : 25;
  for (const x of list.slice(0, cap)) console.log(`   ${fmt(x)}`);
  if (list.length > cap) console.log(`   ... and ${list.length - cap} more`);
};
console.log(`files scanned ${FILES.length}   routine names with a repo definition ${byRoutine.size}   canonical ${canonical.size}`);
show('CONFLICTING current definitions (two files at one sequence key)', CONFLICTING,
  x => `${x.name}  seq ${x.seqKey}  ${x.files.join('  ')}  distinct bodies ${x.distinctBodies}`);
show('AMBIGUOUS routine winners', AMBIGUOUS, x => `${x.name}  ${x.files.join('  ')}`);
show('MANIFEST GAPS', GAPS, x => x);
if (REPO_ONLY) {
  console.log('\nPRODUCTION COMPARISON SKIPPED: no SUPABASE_ACCESS_TOKEN. The repository-side counts '
    + 'above are asserted; repo->prod and prod->repo are NOT. Run from a session holding the '
    + 'management token to assert them.');
} else {
  show('REPOSITORY -> PRODUCTION drift (canonical body not deployed)', REPO_TO_PROD, x => `${x.name}  ${x.why}  [${x.file}]`);
  show('PRODUCTION -> REPOSITORY drift (live application routine with no canonical file)', PROD_TO_REPO,
    x => `${x.name}(${x.args})  owner ${x.owner}  — ${x.mirror}`);
  // A FINDING THAT IS COUNTED AND NEVER NAMED CANNOT BE ACTED ON. UNCOMMITTED_DDL was summed into
  // the exit code and printed only as a number; every other finding class here shows its rows.
  // Measured 24 Aug 2026: the summary said 2 and nothing in the output said which 2.
  show('UNCOMMITTED APPLICATION DDL (live, and in no canonical file or the schema mirror)',
       UNCOMMITTED_DDL, x => x);
  console.log(`\nownership of live public routines: `
    + Object.entries(live.reduce((a, r) => { const k = ownership(r); a[k] = (a[k] || 0) + 1; return a; }, {}))
      .map(([k, v]) => `${k} ${v}`).join('   '));
}

const findings = CONFLICTING.length + AMBIGUOUS.length + GAPS.length + REPO_TO_PROD.length + PROD_TO_REPO.length + UNCOMMITTED_DDL.length;
console.log(`\n---------------------------------------------------------------- SUMMARY`);
console.log(`  conflicting current definitions  ${CONFLICTING.length}`);
console.log(`  ambiguous routine winners        ${AMBIGUOUS.length}`);
console.log(`  manifest gaps                    ${GAPS.length}`);
console.log(`  repository -> production drift   ${REPO_ONLY ? 'not asserted' : REPO_TO_PROD.length}`);
console.log(`  production -> repository drift   ${REPO_ONLY ? 'not asserted' : PROD_TO_REPO.length}`);
console.log(`  uncommitted application DDL      ${REPO_ONLY ? 'not asserted' : UNCOMMITTED_DDL.length}`);
console.log(`  ------------------------------------`);
console.log(`  countable findings               ${findings}  -> exit ${findings ? 1 : 0}`);

// A FINDING HERE IS NOT NECESSARILY THE BRANCH'S (23 Sep 2026).
//
// The three production counters above read the LIVE database, not the diff. So this check can go
// red on a branch that changed nothing, and on a commit of main that was green an hour earlier -
// production moved underneath it. Measured that day: main's own run 35794274321 (head 26b914a)
// was green at 22:48 UTC and failed on a re-run at 23:30 with 15 findings, none of them from any
// diff, and every open PR went red at once. The cause was two PRs applied to production and not
// yet merged - the normal window between an apply and its merge. It cleared when they landed.
//
// A session that reads the finding off a PR and starts fixing the PR loses an hour proving that,
// so the check says it out loud and says how to attribute the finding.
if (findings && !REPO_ONLY) {
  console.log();
  console.log("  THE THREE PRODUCTION COUNTERS READ THE LIVE DATABASE, NOT THIS DIFF.");
  console.log("  A finding is only this branch's if the same check is red on main at the same moment:");
  console.log("      git fetch origin && git checkout --detach origin/main && node scripts/checks/canonical_routine_manifest.mjs");
  console.log("  Red on main too: production and main disagree - apply, or correct the file, on main.");
  console.log("  Green on main:   the finding is this branch's - its SQL is unapplied, or its file is stale.");
  console.log("  Red on both while another PR is mid-apply: that is the apply-then-merge window; re-read after it merges.");
}
// THE EXIT CODE IS SET, NOT FORCED (sales_engineer, 3 Nov 2026). This line was process.exit(), and on
// Linux a child's stdout pipe is asynchronous: whatever the kernel buffer has not yet taken is queued in
// the process, and process.exit() throws the queue away. Once the PENDING notes above grew to ~75 KB of
// separate writes, CI lost the whole tail — main's own run 41529498335 (6987460e) and #1796's run
// 41524780655 both had canonical_routines.test.mjs read "exit 0, countable findings ?" and "reported
// nothing" for every counter, while f6dcbe7d, one commit earlier, read 0. Windows pipes are synchronous,
// so it never reproduced locally. exitCode lets Node flush stdout first; the code itself is unchanged.
process.exitCode = findings ? 1 : 0;
