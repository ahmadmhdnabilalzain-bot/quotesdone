// A PULL REQUEST IS NOT RED FOR WHAT ITS OWN MERGE APPLIES (it_engineer, 3 Nov 2026).
//
// Since #1797 a merged MANIFEST line applies itself (scripts/ci/apply_new_manifest_lines.mjs). So on a pull request
// the routines in the PR's own new lines are, by definition, not on production yet, and canonical_routine_manifest
// reported them as REPOSITORY -> PRODUCTION drift: red on every database PR, ~10 human overrides on 3 Nov alone.
//
// This decides the one narrow case that drift may be set aside, and only on a pull_request run:
//   1. THE SET comes from git, never from a file the run is handed: MANIFEST lines in this tree that MANIFEST at the
//      event's base sha (and origin/main, when present) does not list. Probes are never applied, so never in it.
//   2. THE PROOF is the same run's rehearsal (scripts/ci/rehearse_this_prs_manifest_lines.mjs): every file, in
//      MANIFEST order, replayed on production on top of the ones before it and rolled back, with its _probe.sql
//      answering PROBE OK when it has one; then all of them together, with the routines they define read back from
//      inside the rolled-back transaction. The results are bound to the base sha and to each file's sha256.
// canonical_routine_manifest then sets a finding aside only when its canonical file is in the set, every file
// rehearsed, and the read-back body equals the canonical body - "production will match after the merge applies",
// measured, not assumed. Anything short of that counts exactly as before.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';

export const MANIFEST = 'scripts/sql/MANIFEST.txt';
const path = (l) => l.replace(/^﻿/, '').trim().replace(/^["']+|["']+$/g, '').trim();
const sqlLines = (text) => text.split(/\r?\n/).map(path).filter((p) => /^scripts\/sql\/[^/]+\.sql$/.test(p));
export const sha256 = (text) => createHash('sha256').update(text, 'utf8').digest('hex');
export const probeOf = (file) => file.replace(/\.sql$/, '_probe.sql');

/** { files, error }: MANIFEST lines in this tree that main does not list yet, in MANIFEST order. */
export function prAddedFiles(base, { cwd = process.cwd() } = {}) {
  if (!/^[0-9a-f]{7,40}$/.test(String(base || ''))) return { files: [], error: 'no base sha for this pull request' };
  const git = (...a) => execFileSync('git', a, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  const onMain = new Set();
  try { sqlLines(git('show', `${base}:${MANIFEST}`)).forEach((l) => onMain.add(l)); } catch {
    return { files: [], error: `MANIFEST at base ${base} could not be read` };
  }
  try { sqlLines(git('show', `origin/main:${MANIFEST}`)).forEach((l) => onMain.add(l)); } catch { /* no remote ref: base alone */ }
  const here = sqlLines(readFileSync(`${cwd}/${MANIFEST}`, 'utf8'));
  return { files: [...new Set(here)].filter((f) => !onMain.has(f) && !f.endsWith('_probe.sql')), error: '' };
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
