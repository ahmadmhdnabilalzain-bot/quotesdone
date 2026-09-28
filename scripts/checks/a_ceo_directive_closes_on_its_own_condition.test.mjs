// A CEO directive carries a done-condition, is closed only when that condition is true, and escalates once. Seat: ceo.
// 28 Sep 2026: ceo_seat_directive held 0 rows and every seat's daily priority read "Move improvement #N forward." --
// a pointer with no condition and no date. This reads the NEWEST definition of each routine (MANIFEST order, then
// files still pending apply) and fails if the daily priority goes back to the pointer, or the loop loses its
// predicate check or its escalate-once guard.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim())
  .filter((l) => l.endsWith('.sql') && !l.startsWith('#'));
const pending = readdirSync('scripts/sql/pending').filter((f) => f.endsWith('.txt') && !f.endsWith('_probe.txt'))
  .map((f) => `scripts/sql/${f.replace(/\.txt$/, '.sql')}`);
const files = [...manifest, ...pending].filter(existsSync);

function newest(fn) {
  const def = new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${fn}\\s*\\(`, 'i');
  const file = files.filter((f) => def.test(readFileSync(f, 'utf8'))).pop();
  assert.ok(file, `no file defines ${fn}`);
  return { file, body: readFileSync(file, 'utf8').split(def).pop().split(/\$(?:function|fn)\$;/)[0] };
}

test('the daily priority is the seat\'s directive, never a bare improvement pointer', () => {
  const { file, body } = newest('fn_ceo_daily_run');
  assert.doesNotMatch(body, /Move improvement #/, `${file}: the priority is a pointer again`);
  assert.match(body, /fn_ceo_directive_run\(/, `${file}: the daily run no longer issues and re-checks directives`);
  assert.match(body, /from public\.ceo_directive/, `${file}: the priority does not read the seat's open directive`);
});

test('the loop closes on the predicate and escalates exactly once', () => {
  const { file, body } = newest('fn_ceo_directive_run');
  assert.match(body, /execute\s+'select coalesce\(\(' \|\| d\.done_sql/, `${file}: a directive must close on its own done_sql`);
  assert.match(body, /d\.escalated_from is null/, `${file}: only a first-issue directive may be re-issued`);
  assert.match(body, /status = 'missed'/, `${file}: a late re-issue must close missed, not be re-issued again`);
  assert.match(body, /ceo_decision_log/, `${file}: an escalation must leave a CEO decision row`);
});
