#!/usr/bin/env node
// THIS PULL REQUEST'S NEW MANIFEST LINES, REHEARSED THE WAY THE MERGE WILL APPLY THEM (it_engineer, 3 Nov 2026).
// scripts/lib/applies_at_merge.mjs says why. In MANIFEST order, file k is replayed on top of files 1..k-1 (the merge
// applies them one after another, so k may need what an earlier one creates) with its _probe.sql when it has one, and
// rolled back. Then all of them together, reading back every routine they define from inside the rolled-back
// transaction: that read-back is what production will hold once the merge has applied them. Nothing commits;
// safe_replay refuses transaction control and fingerprints the routines before and after.
//   node scripts/ci/rehearse_this_prs_manifest_lines.mjs <base-sha> <results.json>
// Writes the results and exits 0 whatever they say: canonical_routine_manifest decides what they excuse. A PR that
// adds no MANIFEST line touches nothing on production. Exits 1 only when the results cannot be written.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
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
const texts = files.map((f) => readFileSync(f, 'utf8'));
const upTo = (k) => texts.slice(0, k + 1).join('\n;\n');
let failed = false;
for (const [k, file] of files.entries()) {
  const probe = existsSync(probeOf(file)) ? probeOf(file) : null;
  const probeText = probe ? readFileSync(probe, 'utf8') : null;
  const row = { file, sha256: sha256(texts[k]), probe, probe_sha256: probe ? sha256(probeText) : null, verdict: '' };
  results.files.push(row);
  if (failed) { row.verdict = 'NOT REHEARSED: an earlier file of this PR failed, and the merge would stop there'; continue; }
  try {
    row.verdict = await rehearse(upTo(k), probeText, `${file} (on top of ${k} earlier file(s) of this PR)`);
    console.log(`${row.verdict}, rolled back: ${file}`);
  } catch (e) {
    failed = true;
    row.verdict = `FAILED: ${e.message}`;
    console.log(`::warning::${file} did not rehearse; the merge would stop at it. ${e.message.slice(0, 600)}`);
  }
}

if (!failed) {
  // Every name a `create function` in these files mentions, the same pattern canonical_routine_manifest reads.
  const names = [...new Set([...upTo(files.length - 1).matchAll(/create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?([a-z0-9_]+)"?\s*\(/gi)]
    .map((m) => m[1].toLowerCase()))];
  try {
    const list = names.map((n) => `'${n}'`).join(',') || "''";
    const rows = await replaySql(`${upTo(files.length - 1)}\n;\nselect p.proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = any(array[${list}]::text[])`, { label: 'this PR\'s files, read back', rows: true });
    const routines = {};
    for (const r of rows) (routines[r.proname] ??= []).push(r.prosrc);
    results.post_state = { ok: true, routines };
    console.log(`read back ${rows.length} routine body(ies) of ${names.length} name(s) after all ${files.length} file(s), rolled back`);
  } catch (e) {
    results.post_state = { ok: false, error: String(e?.message ?? e).slice(0, 2000) };
    console.log(`::warning::the read-back after this PR's files failed: ${results.post_state.error.slice(0, 600)}`);
  }
}
save();
