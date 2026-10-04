// THE QUARTERLY REFRESH RE-CHECKS EVERY SEAT KNOWLEDGE ENTRY (5 Oct 2026, it_engineer; backlog T4).
//
// The cause: it_engineer.knowledge_refresh re-researched only each seat's FIVE stalest items a quarter; 282 entries
// with no source and every entry past its date went unflagged. This fails if that returns.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the re-check loop over fn_seat_knowledge_items gains a LIMIT, or stops flagging one of the three
//     reasons, or stops recording the stale status / marking agent_knowledge stale / filing in the seat's own queue
//     / writing the per-quarter result; the verify stops requiring the stale entries; the file carries both (or
//     neither of) a pending note and a MANIFEST line;
//   * production, in ONE aborted transaction (the file replayed while pending; nothing commits): the probe file
//     must print PROBE OK.
//
//   node --test scripts/checks/the_quarterly_refresh_rechecks_every_seat_knowledge_entry.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/the_quarterly_refresh_rechecks_every_seat_knowledge_entry_against_its_source.sql';
const PROBE_FILE = FILE.replace(/\.sql$/, '_probe.sql');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

test('static: every entry is re-checked, flagged, marked and filed', () => {
  const src = read(FILE);
  const fn = src.slice(src.indexOf('create or replace function public.fn_it_engineer_knowledge_refresh()'));
  const loop = fn.match(/for k in select \* from public\.fn_seat_knowledge_items\(s\) x([^\n]*) loop/);
  assert.ok(loop, 'the re-check loop over fn_seat_knowledge_items is gone');
  assert.doesNotMatch(loop[1], /\blimit\b/i, 'the re-check must read EVERY entry, not a sample');
  for (const r of ['no_source', 'review_overdue', 'source_old']) assert.match(fn, new RegExp(`then '${r}' end`), `reason ${r} is no longer flagged`);
  assert.match(fn, /insert into public\.seat_knowledge_stale/, 'the stale status is not recorded');
  assert.match(fn, /update public\.agent_knowledge set validation_status = 'stale'/, 'agent_knowledge is not marked stale (the prompt tag would not show)');
  assert.match(fn, /fn_reason_hold\(s, s \|\| '\.knowledge_refresh'[\s\S]{0,700}'krecheck:'/, 'stale entries are not filed in the seat\'s own queue');
  assert.match(fn, /set recheck = jsonb_build_object\('checked'/, 'the per-quarter result is not written');
  assert.match(fn, /recheck is not null[\s\S]{0,300}seat_knowledge_stale st where[\s\S]{0,120}resolved_at is null/, 'verify no longer waits on the stale entries');
  assert.match(src, /update public\.seat_knowledge_stale set resolved_at = now\(\)/, 'reasoning the question does not resolve the stale row');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(FILE) !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: the probe prints PROBE OK', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = pending(FILE) ? read(FILE) : '';
  let verdict;
  try { await sql(replay + '\n' + read(PROBE_FILE), { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    verdict = m[1];
  }
  assert.ok(verdict, 'the probe did not raise its verdict (did something commit?)');
  assert.match(verdict, /^PROBE OK/, verdict.slice(0, 1500));
});
