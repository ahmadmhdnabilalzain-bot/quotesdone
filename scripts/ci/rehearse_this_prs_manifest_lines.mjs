#!/usr/bin/env node
// THIS PULL REQUEST'S NEW MANIFEST LINES, REHEARSED THE WAY THE MERGE WILL APPLY THEM (it_engineer, 3 Nov 2026).
// scripts/lib/applies_at_merge.mjs says why. In MANIFEST order, for each file k:
//   1. apply_sql.mjs's own pre-write guards, as a DRY RUN (refused statements, a foreign project ref, a callee the
//      database does not have). A routine an earlier file of this PR defines counts as present, because the merge
//      applies that file first: its name is handed to the dry run as a comment, which apply_sql reads as defined.
//   2. Only when k has a _probe.sql: files 1..k replayed with the probe, which must answer PROBE OK.
// Then ONE replay of all the files together, reading back every routine they define from inside the rolled-back
// transaction: that read-back is what production will hold once the merge has applied them, and it is the
// rehearsal of every file without a probe. Every replay starts with a lock and statement timeout, so a rehearsal
// that would hold production's locks fails instead, and the finding counts. Nothing commits: safe_replay refuses
// transaction control and fingerprints the routines before and after.
//
// What the merge does that this does not: the release guard (it passes on main by construction) and the seat (the
// merge always names one). The rehearsal runs against production as it is NOW; the merge runs minutes or days later.
//   node scripts/ci/rehearse_this_prs_manifest_lines.mjs <base-sha> <results.json>
// Writes the results and exits 0 whatever they say: canonical_routine_manifest decides what they excuse. A PR that
// adds no MANIFEST line touches nothing on production. Exits 1 only when the results cannot be written.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { prAddedFiles, probeOf, sha256 } from '../lib/applies_at_merge.mjs';

const [base, out] = process.argv.slice(2);
if (!out) { console.error('usage: rehearse_this_prs_manifest_lines.mjs <base-sha> <results.json>'); process.exit(2); }
const { files, error } = prAddedFiles(base);
const results = { base, error, files: [], post_state: null };
const save = () => writeFileSync(out, JSON.stringify(results, null, 1));
if (error || !files.length) {
  console.log(error ? `nothing rehearsed: ${error}` : 'this pull request adds no MANIFEST line; nothing to rehearse');
  save(); process.exit(0);
}

const { rehearse } = await import('./rehearse_sql.mjs');
const { replaySql } = await import('../lib/safe_replay.mjs');
// A rehearsal that waits on a lock is one holding production up; it fails, and the finding counts (review of #1825).
const LIMITS = "set local lock_timeout = '5s';\nset local statement_timeout = '90s';\n";
const texts = files.map((f) => readFileSync(f, 'utf8'));
const upTo = (k) => LIMITS + texts.slice(0, k + 1).join('\n;\n');
// apply_sql.mjs's own pattern for "this file defines a routine".
const DEFINES = /create\s+or\s+replace\s+function\s+(?:public\.)?([a-z0-9_]+)\s*\(/gi;
const scratch = mkdtempSync(join(tmpdir(), 'qd-rehearse-'));
const guards = (k) => {
  const earlier = [...new Set(texts.slice(0, k).flatMap((t) => [...t.matchAll(DEFINES)].map((m) => m[1].toLowerCase())))];
  const file = join(scratch, files[k].split('/').pop());
  writeFileSync(file, texts[k] + '\n' + earlier.map((n) => `-- applied by an earlier file of this PR: create or replace function public.${n}(\n`).join(''));
  try {
    execFileSync(process.execPath, ['scripts/apply_sql.mjs', file, '--ddl', '--seat', 'it_engineer'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) {
    throw new Error(`apply_sql.mjs refused it (exit ${e.status}): ${String(e.stderr || e.stdout).trim().slice(0, 1500)}`);
  }
};

let failed = false;
for (const [k, file] of files.entries()) {
  const probe = existsSync(probeOf(file)) ? probeOf(file) : null;
  const probeText = probe ? readFileSync(probe, 'utf8') : null;
  const row = { file, sha256: sha256(texts[k]), probe, probe_sha256: probe ? sha256(probeText) : null, verdict: '' };
  results.files.push(row);
  if (failed) { row.verdict = 'NOT REHEARSED: an earlier file of this PR failed, and the merge would stop there'; continue; }
  try {
    guards(k);
    if (probe) {
      row.verdict = await rehearse(upTo(k), probeText, `${file} (on top of ${k} earlier file(s) of this PR)`);
      console.log(`${row.verdict}, rolled back: ${file}`);
    }
  } catch (e) {
    failed = true;
    row.verdict = `FAILED: ${e.message}`;
    console.log(`::warning::${file} did not rehearse; the merge would stop at it. ${e.message.slice(0, 600)}`);
  }
}
rmSync(scratch, { recursive: true, force: true });

if (!failed) {
  // Every name a `create function` in these files mentions, the same pattern canonical_routine_manifest reads.
  const names = [...new Set([...texts.join('\n;\n').matchAll(/create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?([a-z0-9_]+)"?\s*\(/gi)]
    .map((m) => m[1].toLowerCase()))];
  const unprobed = results.files.filter((r) => !r.probe);
  try {
    const list = names.map((n) => `'${n}'`).join(',') || "''";
    const rows = await replaySql(`${upTo(files.length - 1)}\n;\nselect p.proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = any(array[${list}]::text[])`, { label: 'this PR\'s files, read back', rows: true });
    const routines = {};
    for (const r of rows) (routines[r.proname] ??= []).push(r.prosrc);
    results.post_state = { ok: true, routines };
    for (const r of unprobed) r.verdict = 'REHEARSED';
    console.log(`read back ${rows.length} routine body(ies) of ${names.length} name(s) after all ${files.length} file(s), rolled back`);
  } catch (e) {
    results.post_state = { ok: false, error: String(e?.message ?? e).slice(0, 2000) };
    for (const r of unprobed) r.verdict = `FAILED: the replay of every file failed: ${results.post_state.error.slice(0, 300)}`;
    console.log(`::warning::the read-back after this PR's files failed: ${results.post_state.error.slice(0, 600)}`);
  }
} else {
  for (const r of results.files) if (!r.verdict) r.verdict = 'NOT REHEARSED: a file of this PR failed before the replay of every file';
}
save();
