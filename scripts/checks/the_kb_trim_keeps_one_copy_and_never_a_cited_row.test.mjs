// THE kb_chunks TRIM KEEPS ONE COPY OF EVERY TEXT AND NEVER A CITED ROW (5 Oct 2026, it_engineer; ledger 1085 stage 4).
// Fails if a duplicate is matched on content alone or the keeper can be an unverified copy, if a cited id can be
// planned, if the apply reads the whole table again, if the batch guards the 21 Sep outage taught go (size cap,
// advisory lock, pkey walk, lock_timeout), if a batch re-walks done ids, if the driver pins an export day, or if it
// can run a table rewrite or by day.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const x = readFileSync('scripts/sql/the_unverified_bulk_and_the_duplicates_leave_kb_chunks_in_pages.sql', 'utf8');
const drv = readFileSync('scripts/kb/trim_kb_chunks.mjs', 'utf8');
const book = readFileSync('docs/runbooks/kb_chunks_rewrite.md', 'utf8');
const code = (s) => s.split('\n').filter((l) => !/^\s*(--|\/\/)/.test(l)).join('\n');
const fn = (name) => x.slice(x.indexOf(`create or replace function public.${name}`), x.indexOf('end $fn$;', x.indexOf(`function public.${name}`)));

test('a duplicate is the same content, title and category, and the keeper is the verified copy', () => {
  assert.match(fn('fn_kb_trim_hash_page'), /md5\(k\.content\) \|\| md5\(coalesce\(k\.title, ''\) \|\| chr\(31\) \|\| coalesce\(k\.category, ''\)\)/);
  assert.match(fn('fn_kb_trim_hash_page'), /when k\.source_kind = 'qd_kb_pack' then 2 when coalesce\(k\.citation, ''\) = '' then 1 else 0/);
  const b = fn('fn_kb_trim_plan_build');
  assert.match(b, /window w as \(partition by h\.k order by h\.pref, h\.id\)/);
  assert.match(b, /when is_cited then null/);
  assert.match(b, /when id <> keeper and not keeper_qd then 7/);
  assert.match(x, /3,478 rows beyond the keeper/);
});

test('the apply hashes nothing beyond its 200-row probe', () => {
  const top = code(x.slice(0, x.indexOf('create or replace function'))).replace(/--.*$/gm, '');
  assert.ok(!/md5\(/.test(top), 'a hash outside the paged routine');
  const probe = x.slice(x.indexOf('do $$'));
  assert.match(probe, /fn_kb_trim_hash_page\([^;]*, 200\)/);
  assert.match(probe, /raise exception 'qd_probe_rollback'/);
  assert.ok(!/fn_kb_trim_census|^\s*(begin|commit)\s*;/im.test(code(x).replace(/drop function if exists public\.fn_kb_trim_census\(\);/, '')));
});

test('a batch is small, never overlaps, walks the pkey, gives up on a lock and leaves the plan as it goes', () => {
  const b = fn('fn_kb_trim_batch');
  assert.match(b, /p_limit > 5000/);
  assert.match(b, /pg_try_advisory_xact_lock\(hashtext\('public\.fn_kb_purge_batch'\)\)/);
  assert.match(b, /set enable_seqscan to 'off'/);
  assert.match(b, /set lock_timeout to '2s'/);
  assert.match(b, /no census in kb_purge_ledger/);
  assert.match(b, /delete from public\.kb_trim_plan p using pick/);
});

test('the driver resolves the newest full export, runs at night under the load guard, proves the keepers, never rewrites', () => {
  assert.match(drv, /where r\.kind = 'full' and r\.status = 'done' order by r\.stamp desc limit 1/);
  assert.match(drv, /is older than the newest kb_chunks row/);
  assert.ok(!/EXPORT_DAY\s*=\s*'20/.test(drv), 'a pinned export day');
  assert.match(drv, /inNightWindow\(\)/);
  assert.match(drv, /loadVerdict\(load, await diskFree\(\)\)/);
  assert.match(drv, /k\.id = h\.keeper_id/);
  assert.match(drv, /duplicate texts with no surviving copy/);
  assert.ok(!/vacuum\s*\(\s*full|vacuum full|pg_repack/i.test(code(drv) + code(x)), 'a table rewrite outside the runbook');
});

test('the runbook budgets the lock it measures', () => {
  assert.match(book, /set statement_timeout = '5min'/);
  assert.match(book, /set lock_timeout = '5s'/);
  assert.match(book, /02:00-05:00 Asia\/Dubai/);
  assert.match(book, /## Restore path/);
});
