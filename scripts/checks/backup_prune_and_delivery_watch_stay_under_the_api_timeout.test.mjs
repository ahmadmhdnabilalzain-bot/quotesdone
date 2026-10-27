// THE BACKUP PRUNE AND THE DELIVERY WATCH STAY UNDER THE 8 s API TIMEOUT (19 Oct 2026, it_engineer).
//
// resilience_ping calls these over PostgREST (authenticator statement_timeout = 8 s). fn_backup_prune_plan measured
// 6,362 ms and fn_backup_prune_tick over 8 s because doc_backups was matched to a day by a LIKE on a concatenated
// pattern (no index can serve it); fn_customer_support_delivery_watch(null) walked ~409 rows with no LIMIT.
// Fix: scripts/sql/the_backup_prune_and_the_delivery_watch_finish_under_the_api_timeout.sql.
//
// The canonical body of each routine is the LAST file in MANIFEST.txt that defines it; a file with a note in
// scripts/sql/pending/ is committed-but-unapplied and counts as later than every MANIFEST file.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const root = new URL('../../', import.meta.url);
const read = (p) => readFileSync(new URL(p, root), 'utf8');
const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
const pending = readdirSync(new URL('scripts/sql/pending/', root)).filter((f) => f.endsWith('.txt'))
  .map((f) => `scripts/sql/${f.slice(0, -4)}.sql`).filter((p) => existsSync(new URL(p, root)));

function body(name) {
  const re = new RegExp(String.raw`create or replace function public\.${name}\(([\s\S]*?)\$fn\$([\s\S]*?)\$fn\$`, 'gi');
  let last = null;
  for (const f of [...manifest, ...pending]) {
    if (!existsSync(new URL(f, root))) continue;
    for (const m of read(f).matchAll(re)) last = { file: f, text: m[0] };
  }
  assert.ok(last, `${name}: no defining file found`);
  return last;
}

test('no backup prune routine matches doc_backups to a day with a non-sargable LIKE', () => {
  for (const fn of ['fn_backup_prune_plan', 'fn_backup_prune_tick', 'fn_backup_prune_cancel']) {
    const { file, text } = body(fn);
    assert.ok(!/dedupe_key\s+like\s+'EXPORT:'\s*\|\|/i.test(text), `${fn} (${file}) matches the day by LIKE; use left(dedupe_key, 18) =`);
  }
});

test('the storage.objects day match is a COLLATE "C" range the bucket/name index can serve', () => {
  for (const fn of ['fn_backup_prune_plan', 'fn_backup_prune_storage_next']) {
    const { file, text } = body(fn);
    assert.ok(/name collate "C" >= /i.test(text) && /name collate "C" < /i.test(text), `${fn} (${file}) lost the name range`);
  }
});

test('the delivery watch loop is bounded', () => {
  const { file, text } = body('fn_customer_support_delivery_watch');
  const loop = text.slice(text.indexOf('for q in'), text.indexOf('loop', text.indexOf('for q in')));
  assert.ok(/\blimit\b/i.test(loop), `fn_customer_support_delivery_watch (${file}) loops with no LIMIT`);
});

// 27 Oct 2026: LIMIT 50 alone stopped bounding the TIME. A result came to cost ~300 ms, so the 50-row walk took
// 15,464 ms, every resilience_ping ladder tick was cancelled at 8 s and rolled back, and no delivery.result committed
// from 19 Oct (the_delivery_watch_returns_results_within_a_time_budget_so_the_ladder_tick_commits.sql). A row count
// bounds work only while each row is cheap; the walk must stop on a clock.
test('the delivery watch walk stops on a clock budget, not only a row count', () => {
  const { file, text } = body('fn_customer_support_delivery_watch');
  assert.match(text, /v_until timestamptz := clock_timestamp\(\) \+ interval '\d+ seconds?'/, `fn_customer_support_delivery_watch (${file}) has no clock budget`);
  assert.match(text, /if p_request_id is null and clock_timestamp\(\) > v_until then/, `fn_customer_support_delivery_watch (${file}) never checks its budget in the walk`);
  assert.match(text, /'left_for_next_tick', v_left/, `fn_customer_support_delivery_watch (${file}) does not report what it left for the next tick`);
});
