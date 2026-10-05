// THE kb_chunks TRIM KEEPS ONE COPY OF EVERY TEXT AND NEVER A CITED ROW (5 Oct 2026, it_engineer; ledger 1085 stage 4).
// Fails if the plan deletes a duplicate's last copy, plans a cited id, drops the batch guards the 21 Sep outage taught
// (size cap, advisory lock, pkey walk, lock_timeout), or if the driver can run a table rewrite or by day.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const x = readFileSync('scripts/sql/the_unverified_bulk_and_the_duplicates_leave_kb_chunks_in_pages.sql', 'utf8');
const drv = readFileSync('scripts/kb/trim_kb_chunks.mjs', 'utf8');
const code = (s) => s.split('\n').filter((l) => !/^\s*(--|\/\/)/.test(l)).join('\n');

test('a duplicate group keeps its lowest id that is not itself trimmed, and cited ids are never planned', () => {
  assert.match(x, /keep as \(select c, min\(id\) id from h where not goes6 group by c\)/);
  assert.match(x, /where not h\.goes6 and h\.id <> keep\.id and h\.id not in \(select id from cited\)/);
  assert.match(x, /k\.source_kind = 'qd_kb_pack' and k\.id not in \(select id from cited\)/);
});

test('a batch is small, never overlaps, walks the pkey and gives up on a lock', () => {
  const b = x.slice(x.indexOf('create or replace function public.fn_kb_trim_batch'));
  assert.match(b, /p_limit > 5000/);
  assert.match(b, /pg_try_advisory_xact_lock\(hashtext\('public\.fn_kb_purge_batch'\)\)/);
  assert.match(b, /set enable_seqscan to 'off'/);
  assert.match(b, /set lock_timeout to '2s'/);
  assert.match(b, /no census in kb_purge_ledger/);
});

test('the driver runs at night under the load guard, proves a surviving copy, and never rewrites the table', () => {
  assert.match(drv, /inNightWindow\(\)/);
  assert.match(drv, /loadVerdict\(load, await diskFree\(\)\)/);
  assert.match(drv, /duplicate texts with no surviving copy/);
  assert.ok(!/vacuum\s*\(\s*full|vacuum full|pg_repack/i.test(code(drv) + code(x)), 'a table rewrite outside the runbook');
});
