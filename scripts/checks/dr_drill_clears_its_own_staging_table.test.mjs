// THE DRILL COULD NOT CLEAR ITS OWN STAGING TABLE, AND REPORTED THE BACKUPS AS UNPROVEN.
//
// 12 Aug 2026, 20:31. dr_drill opened with a single conditional DELETE over public.dr_restore and
// got back "canceling statement due to statement timeout". It then counted the leftovers as
// restored rows:
//
//   kb_chunks      95,983 expected   287,949 restored   exactly 3x
//   dept_library    1,456 expected     4,368 restored   exactly 3x
//   ops_knowledge   3,735 expected    11,205 restored   exactly 3x
//
// and declared 7 of 11 tables "not proven restorable". The backups were fine — the runs at 20:35
// and 20:40, once the table happened to be small enough to clear, both came back 11/11 with 0
// failed. The failure mode is the dangerous one: not "your backup is bad" but "the verdict on your
// backup cannot be trusted", on the one drill that exists to tell you a real outage is survivable.
//
// TRUNCATE is not the fix and this check says so. The predicate is load-bearing: rows another
// chain is mid-way through must survive, and the 180-second concurrency guard above it is a
// check-then-act that a table-wide wipe would race.
//
//   node --test scripts/checks/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SRC = readFileSync('supabase/functions/dr_drill/index.ts', 'utf8');

const clear = (() => {
  const at = SRC.indexOf('let wiped = 0');
  assert.ok(at > 0, 'dr_drill no longer has the batched clear this check reads');
  return SRC.slice(at, at + 1600);
})();

// 4 SEP 2026: the pass moved server-side. PostgREST capped every select at 1,000 rows, so 40 passes
// reached 40,000 while one drill leaves ~234,000 rows; fn_dr_restore_clear deletes up to 20,000 rows
// chosen by ctid in ONE statement (1.4s measured against the 8s budget) and the loop here stays.
const CLEAR_SQL = readFileSync('scripts/sql/fn_dr_restore_clear_one_bounded_delete_per_pass.sql', 'utf8');

test('the staging clear is bounded, so no single statement can time out', () => {
  assert.match(clear, /sb\.rpc\('fn_dr_restore_clear', \{ p_before: cutoff \}\)/,
    'the pre-clear no longer runs through fn_dr_restore_clear with the age cutoff');
  assert.match(CLEAR_SQL, /limit greatest\(1, least\(coalesce\(p_limit, 20000\), 50000\)\)/,
    'fn_dr_restore_clear no longer bounds one pass — one statement over a six-figure dr_restore is '
    + 'what timed out on 12 Aug and made the drill count three runs as one');
  assert.match(clear, /for \(; wipePasses < 40; wipePasses\+\+\)/,
    'the clear is not a bounded loop; an unbounded one turns a stuck table into a hanging drill');
});

test('the age predicate survives — a concurrent chain is not wiped', () => {
  assert.match(CLEAR_SQL, /r\.drill_at < p_before/,
    'fn_dr_restore_clear no longer filters on drill_at, so it can delete rows a concurrently running '
    + 'drill chain is still writing');
  assert.match(CLEAR_SQL, /p_before is null and p_run_id is null[\s\S]*raise exception/,
    'fn_dr_restore_clear must refuse a call with neither an age cutoff nor a run id — that is the '
    + 'table-wide wipe the 180-second guard cannot survive');
  assert.match(clear, /\.lt\('drill_at', cutoff\)/,
    'the leftover count after the pass budget no longer filters on drill_at');
  // Executable truncates only — the comment above the clear says the word, on purpose, to explain
  // why it is not used. Asserting on the bare word would fail on its own explanation.
  const code = SRC.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');
  assert.doesNotMatch(code, /truncate\s+table|rpc\(\s*['"][^'"]*truncate/i,
    'dr_drill must not TRUNCATE dr_restore: the 180-second guard above the clear is a check-then-act '
    + 'and a table-wide wipe would race a running chain');
});

test('a clear that does not finish is reported, not carried into the counts', () => {
  // The whole point. Leftovers silently inflating `restored` is how "not proven restorable" got
  // said about seven healthy backups.
  assert.match(clear, /wipePasses >= 40/,
    'exhausting the pass budget must be detected');
  assert.match(clear, /still remain/,
    'a clear that ran out of passes must produce a failure note — leaving it silent puts leftover '
    + 'rows straight into the restored-row comparison, which is the original defect');
});
