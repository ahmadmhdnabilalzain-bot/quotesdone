// fn_it_detect's queue_not_draining arm must not raise a drain of zero while every pending row is younger
// than the hour the drain was counted over. Incidents 495 and 554 (25 Sep 2026): doc_backups filled in its
// daily batch at ~23:12 UTC, the arm fired at 23:16 with drained_last_hour 0, and the queue cleared by 23:31.
// Reads the newest fn_it_detect definition the same way refusal_rate_judges_a_surface_by_its_own_baseline does:
// a scripts/sql/pending note's file wins over MANIFEST, else the last MANIFEST file defining the routine.
// Then replays the raise condition on the two incidents and on a consumer that is really dead.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const defines = (f) => existsSync(f) && /function\s+public\.fn_it_detect\s*\(/i.test(readFileSync(f, 'utf8'));
const pending = readdirSync('scripts/sql/pending')
  .map((n) => `scripts/sql/${n.replace(/\.txt$/, '.sql')}`).filter(defines);
const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/)
  .map((l) => l.trim()).filter((l) => l.endsWith('.sql')).filter(defines);
const file = pending.at(-1) ?? manifest.at(-1);
const src = readFileSync(file, 'utf8');

// The condition that raises queue_not_draining, as SQL text -> a JS predicate.
const cond = src.match(/\n\s*if\s+(\(?v_hours is null[^\n]*?)\s+then\s*\n\s*v_state\s*:=\s*case when v_drain = 0/)[1];
const raises = new Function('v_hours', 'v_drain', 'v_age', 'return ' + cond
  .replace(/\bis null\b/g, '=== null').replace(/\bnot\b/g, '!').replace(/\band\b/g, '&&')
  .replace(/\bor\b/g, '||').replace(/([^<>!=])=([^=])/g, '$1===$2'));

test(`${file}: a queue filled minutes ago with nothing drained yet is not raised`, () => {
  assert.equal(raises(null, 0, 4), false, 'doc_backups 25 Sep: 527 rows, oldest 4 minutes old');
  assert.equal(raises(null, 0, 59), false, 'still inside the hour the drain was counted over');
});

test(`${file}: a dead consumer and a slow one are still raised`, () => {
  assert.equal(raises(null, 0, 61), true, 'nothing drained and the oldest row has waited a full hour');
  assert.equal(raises(30, 10, 5), true, 'draining, but 30 hours to clear');
  assert.equal(raises(2, 100, 5), false, 'draining inside the threshold');
});
