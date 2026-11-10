// A PULL REQUEST IS NOT RED FOR WHAT ITS OWN MERGE APPLIES (it_engineer, 3 Nov 2026).
//
// Since #1797 a merged MANIFEST line applies itself (scripts/ci/apply_new_manifest_lines.mjs). So on a pull request
// the routines in the PR's own new lines are, by definition, not on production yet, and canonical_routine_manifest
// reported them as REPOSITORY -> PRODUCTION drift: red on every database PR, ~10 human overrides on 3 Nov alone.
//
// This decides the one narrow case that drift may be set aside, and only on a pull_request run:
//   1. THE SET comes from git, never from a file the run is handed, and is the set the MERGE applies: the merge's own
//      addedFiles() over `git diff <base> HEAD -- MANIFEST`, which must equal the MANIFEST lines new to main (base
//      sha, and origin/main when present). When the two readings differ, nothing is set aside.
//   2. THE PROOF is the same run's rehearsal (scripts/ci/rehearse_this_prs_manifest_lines.mjs): every file passes
//      apply_sql.mjs's own pre-write guards (dry run), each file with a _probe.sql is replayed on top of the earlier
//      files with its probe answering PROBE OK, then all files together are replayed with the routines they define
//      read back from inside the rolled-back transaction. Results are bound to the base sha and each file's sha256.
// canonical_routine_manifest then sets a finding aside only when its canonical file is in the set, every file
// rehearsed, and the read-back body equals the canonical body - "production will match after the merge applies",
// measured, not assumed. Anything short of that counts exactly as before.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { addedFiles } from '../ci/apply_new_manifest_lines.mjs';

export const MANIFEST = 'scripts/sql/MANIFEST.txt';
const path = (l) => l.replace(/^﻿/, '').trim().replace(/^["']+|["']+$/g, '').trim();
const sqlLines = (text) => text.split(/\r?\n/).map(path).filter((p) => /^scripts\/sql\/[^/]+\.sql$/.test(p));
export const sha256 = (text) => createHash('sha256').update(text, 'utf8').digest('hex');
export const probeOf = (file) => file.replace(/\.sql$/, '_probe.sql');

/**
 * { files, error }: the files the merge will apply, in order. Two readings must AGREE or nothing is set aside:
 *   * the merge's own: addedFiles() over `git diff <base> HEAD -- MANIFEST` (raw `+` lines), exactly what
 *     apply-on-merge.yml will apply;
 *   * the meaning: MANIFEST lines here that MANIFEST at <base>, and at origin/main when present, does not list.
 * A quoted or indented new line (new by meaning, never applied by the merge) and a moved or re-spaced existing line
 * (re-applied by the merge, new to nobody) make them differ, and then every finding counts (review of #1825).
 */
export function prAddedFiles(base, { cwd = process.cwd() } = {}) {
  if (!/^[0-9a-f]{7,40}$/.test(String(base || ''))) return { files: [], error: 'no base sha for this pull request' };
  const git = (...a) => execFileSync('git', a, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  const onMain = new Set();
  let applies;
  try {
    sqlLines(git('show', `${base}:${MANIFEST}`)).forEach((l) => onMain.add(l));
    applies = addedFiles(git('diff', base, 'HEAD', '--', MANIFEST));
  } catch {
    return { files: [], error: `MANIFEST at base ${base} could not be read or diffed` };
  }
  try { sqlLines(git('show', `origin/main:${MANIFEST}`)).forEach((l) => onMain.add(l)); } catch { /* no remote ref: base alone */ }
  const here = sqlLines(readFileSync(`${cwd}/${MANIFEST}`, 'utf8'));
  const meant = [...new Set(here)].filter((f) => !onMain.has(f) && !f.endsWith('_probe.sql'));
  if (applies.join('\n') !== meant.join('\n')) {
    return { files: [], error: `the merge would apply [${applies.join(', ')}] but the MANIFEST lines new to main are [${meant.join(', ')}]` };
  }
  return { files: applies, error: '' };
}

/** '' when `results` proves every file in `files` rehearsed as committed; otherwise why it does not. */
export function rehearsalProblem(results, files, base, { cwd = process.cwd() } = {}) {
  if (!results) return 'no rehearsal results in this run';
  if (results.base !== base) return `the rehearsal was for base ${results.base}, this run's base is ${base}`;
  const got = (results.files || []).map((f) => f.file);
  if (got.join('\n') !== files.join('\n')) return `the rehearsal covered [${got.join(', ')}], this PR adds [${files.join(', ')}]`;
  for (const r of results.files) {
    if (r.sha256 !== sha256(readFileSync(`${cwd}/${r.file}`, 'utf8'))) return `${r.file} changed after it was rehearsed`;
    const probe = probeOf(r.file);
    if (existsSync(`${cwd}/${probe}`)) {
      if (r.probe !== probe || r.probe_sha256 !== sha256(readFileSync(`${cwd}/${probe}`, 'utf8'))) return `${r.file} was not rehearsed with ${probe} as committed`;
      if (r.verdict !== 'PROBE OK') return `${r.file}: ${String(r.verdict).slice(0, 300)}`;
    } else if (r.probe || r.verdict !== 'REHEARSED') return `${r.file}: ${String(r.verdict).slice(0, 300)}`;
  }
  if (!results.post_state?.ok) return `the read-back after every file failed: ${String(results.post_state?.error).slice(0, 300)}`;
  return '';
}

/** This branch's own new MANIFEST files (prAddedFiles against its merge-base with origin/main), or [] on main, without a
 *  remote ref, or when the two readings disagree. For a check that replays pending files built on a file this PR applies at
 *  merge (it_engineer, 10 Nov 2026: a pending file naming a model only this PR's MANIFEST file registers). */
export function branchAddedFiles({ cwd = process.cwd() } = {}) {
  let base = '';
  try { base = execFileSync('git', ['merge-base', 'origin/main', 'HEAD'], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return []; }
  return prAddedFiles(base, { cwd }).files;
}
