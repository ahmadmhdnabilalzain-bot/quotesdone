#!/usr/bin/env node
// THIS PULL REQUEST'S NEW MANIFEST LINES, REHEARSED THE WAY THE MERGE WILL APPLY THEM (it_engineer, 3 Nov 2026).
// scripts/lib/applies_at_merge.mjs says why. In MANIFEST order, for each file k:
//   1. What files 1..k-1 leave behind, from their text in statement order: a routine created in CODE (comments,
//      strings and bodies masked) is credited; a `drop function|procedure` ANYWHERE in the text, a string or comment
//      included, takes the credit away and marks the routine GONE. File k FAILS when it calls a gone routine that it
//      does not define itself: at merge it would run after the drop, whatever production holds today.
//   2. apply_sql.mjs's own pre-write guards, as a DRY RUN (refused statements, a foreign project ref, a callee the
//      database does not have), with the credited routines handed to it as comments, which apply_sql reads as defined.
//   3. When k's CODE (comments stripped, apply_sql.mjs's rule) carries PROBE OK or PROBE FAILED, it has promised an
//      INLINE verdict: files 1..k are replayed with nothing appended and the rows of k's last statement are judged by
//      apply_sql's rule (a cell starting PROBE OK, none starting PROBE FAILED). A last statement that is not a query,
//      or returns no verdict, FAILS: at merge apply_sql exits 3 on exactly that (fourth review of #1825).
//   4. When k has a _probe.sql (as well, or instead): files 1..k replayed with the probe, which must answer PROBE OK.
// Then ONE replay of all the files together, reading back from inside the rolled-back transaction every routine they
// define or call, and every relation a call might name: that read-back is what production will hold once the merge
// has applied them, and it is the rehearsal of every file without a probe. A file FAILS when something it calls
// (apply_sql's callee pattern, less what it defines) is neither a routine nor a relation in that read-back.
// Every replay starts with a lock and statement timeout, so a rehearsal that would hold production's locks fails
// instead, and the finding counts. Nothing commits: safe_replay refuses transaction control and fingerprints the
// routines before and after.
//
// KNOWN LIMIT (review of #1825): a routine an earlier file removes in a form the drop pattern cannot see, and that a
// file AFTER k recreates, passes here and stops the merge at k. Unseen forms: the second and later names of
// `drop function a(), b()`; a quoted-name drop; `drop routine`; `alter function|procedure|routine ... rename`; and a
// drop built at run time, e.g. `execute format('drop function %s', ...)`. The dry run asks production as it is now,
// and the read-back sees the state after every file, so neither notices the gap between.
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
const { maskSql } = await import('../lib/sql_text.mjs');
// A rehearsal that waits on a lock is one holding production up; it fails, and the finding counts (review of #1825).
const LIMITS = "set local lock_timeout = '5s';\nset local statement_timeout = '90s';\n";
const texts = files.map((f) => readFileSync(f, 'utf8'));
const upTo = (k) => LIMITS + texts.slice(0, k + 1).join('\n;\n');
const bare = (n) => n.replace(/"/g, '').toLowerCase().replace(/^public\./, '');

// apply_sql.mjs's own patterns: what a file defines, what it calls, and the drops that are not calls.
const DEFINES = /create\s+or\s+replace\s+function\s+(?:public\.)?([a-z0-9_]+)\s*\(/gi;
const CALLEE = /public\.((?:fn|trg|qd|run)_[a-z0-9_]+)\s*\(/g;
const DROPPED_HERE = /drop\s+(?:function|procedure)\s+(?:if\s+exists\s+)?public\.[a-z0-9_]+\s*\(/gi;
const callsOf = (t) => {
  const own = new Set([...t.matchAll(DEFINES)].map((m) => m[1].toLowerCase()));
  return [...new Set([...t.replace(DROPPED_HERE, '').matchAll(CALLEE)].map((m) => m[1].toLowerCase()))].filter((c) => !own.has(c));
};
const calls = texts.map(callsOf);

// Statement order inside each earlier file. maskSql keeps every offset, so masked creates and raw drops share one axis.
const CREATES = /\bcreate\s+(?:or\s+replace\s+)?(?:function|procedure)\s+([a-z0-9_."]+)\s*\(/gi;
const DROPS = /\bdrop\s+(?:function|procedure)\s+(?:if\s+exists\s+)?([a-z0-9_."]+)/gi;
const credited = [], gone = [];
{
  const left = new Set(), dropped = new Set();
  for (const [k, t] of texts.entries()) {
    credited[k] = [...left]; gone[k] = [...dropped];
    const events = [
      ...[...maskSql(t).matchAll(CREATES)].map((m) => ({ at: m.index, name: m[1], create: true })),
      ...[...t.matchAll(DROPS)].map((m) => ({ at: m.index, name: m[1], create: false })),
    ].filter((e) => !e.name.includes('.') || /^"?public"?\./i.test(e.name)).sort((a, b) => a.at - b.at);
    for (const e of events) {
      const n = bare(e.name);
      if (e.create) { left.add(n); dropped.delete(n); } else { left.delete(n); dropped.add(n); }
    }
  }
}

// apply_sql.mjs's rule for a file's own verdict: CODE (comments stripped) naming a marker has promised one, and the
// rows of its last statement must carry a cell starting PROBE OK and none starting PROBE FAILED.
const promisesAVerdict = (t) => {
  const code = t.replace(/\/\*[\s\S]*?\*\//g, ' ').split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
  return code.includes('PROBE OK') || code.includes('PROBE FAILED');
};
const inlineVerdict = async (k) => {
  let rows;
  try {
    rows = await replaySql(upTo(k), { label: `${files[k]} (its own verdict, on top of ${k} earlier file(s) of this PR)`, rows: true });
  } catch (e) {
    throw new Error(`it promises a verdict (PROBE OK / PROBE FAILED in its code) and the replay returned none: ${String(e?.message ?? e).slice(0, 1200)}`);
  }
  const cells = (Array.isArray(rows) ? rows : []).flatMap((r) => Object.values(r || {})).filter((c) => typeof c === 'string').map((c) => c.trim());
  const bad = cells.find((c) => c.startsWith('PROBE FAILED'));
  if (bad) throw new Error(`its own verdict: ${bad.slice(0, 600)}`);
  if (!cells.some((c) => c.startsWith('PROBE OK'))) throw new Error('it promises a verdict (PROBE OK / PROBE FAILED in its code) and its last statement returned none; apply_sql exits 3 on that');
  return 'PROBE OK';
};
const scratch = mkdtempSync(join(tmpdir(), 'qd-rehearse-'));
const guards = (k) => {
  const after = calls[k].filter((c) => gone[k].includes(c));
  if (after.length) throw new Error(`it calls ${after.join(', ')}, which an earlier file of this PR drops; at merge it runs after that drop`);
  const file = join(scratch, files[k].split('/').pop());
  writeFileSync(file, texts[k] + '\n' + credited[k].map((n) => `-- applied by an earlier file of this PR: create or replace function public.${n}(\n`).join(''));
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
    if (promisesAVerdict(texts[k])) {
      console.log(`${await inlineVerdict(k)}, rolled back: ${file} (its own verdict)`);
    }
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
  // Every name a `create function` in these files mentions (canonical_routine_manifest's pattern), and every callee.
  const callees = [...new Set(calls.flat())];
  const names = [...new Set([...texts.join('\n;\n').matchAll(/create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?([a-z0-9_]+)"?\s*\(/gi)]
    .map((m) => m[1].toLowerCase()).concat(callees))];
  const arr = (xs) => `array[${xs.map((n) => `'${n}'`).join(',') || "''"}]::text[]`;
  const unprobed = results.files.filter((r) => !r.probe);
  try {
    const rows = await replaySql(`${upTo(files.length - 1)}\n;\nselect 'routine' as kind, p.proname as name, p.prosrc
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = any(${arr(names)})
      union all
      select 'relation', c.relname, null from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind in ('r','p','v','m','f') and c.relname = any(${arr(callees)})`,
    { label: 'this PR\'s files, read back', rows: true });
    const routines = {}, relations = new Set();
    for (const r of rows) if (r.kind === 'relation') relations.add(r.name); else (routines[r.name] ??= []).push(r.prosrc);
    results.post_state = { ok: true, routines };
    for (const r of unprobed) r.verdict = 'REHEARSED';
    // Something a file calls that the merged state does not hold: the merge's own dry run of it would refuse it,
    // or it throws the first time it runs. Fails closed whether the name was credited or live today.
    for (const [k, r] of results.files.entries()) {
      const absent = calls[k].filter((c) => !routines[c] && !relations.has(c));
      if (absent.length) r.verdict = `FAILED: it calls ${absent.join(', ')}, and the read-back after every file of this PR holds no such routine or relation`;
    }
    console.log(`read back ${rows.length} routine/relation row(s) for ${names.length} name(s) after all ${files.length} file(s), rolled back`);
  } catch (e) {
    results.post_state = { ok: false, error: String(e?.message ?? e).slice(0, 2000) };
    for (const r of unprobed) r.verdict = `FAILED: the replay of every file failed: ${results.post_state.error.slice(0, 300)}`;
    console.log(`::warning::the read-back after this PR's files failed: ${results.post_state.error.slice(0, 600)}`);
  }
} else {
  for (const r of results.files) if (!r.verdict) r.verdict = 'NOT REHEARSED: a file of this PR failed before the replay of every file';
}
save();
