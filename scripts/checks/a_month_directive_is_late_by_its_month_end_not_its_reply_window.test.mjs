// 7 Oct 2026 (wiring audit #1278, item 3): fn_ceo_seat_audit and fn_ceo_directive_run timed every pending handoff
// from created_at + reply_within, so the five October ceo.month_directive handoffs -- answered in the same second,
// closed by the CEO at their due_at (month end) -- read "late" from 2 Oct. Both now ask fn_handoff_is_late, which
// honours an answered handoff's due_at. This fails if either monitor goes back to the raw reply-window clock, or
// if the predicate stops reading due_at. Reads the canonical file per routine (a pending file wins over MANIFEST).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const newest = (re) => {
  const defines = (f) => existsSync(f) && re.test(readFileSync(f, 'utf8'));
  const pending = readdirSync('scripts/sql/pending').map((n) => `scripts/sql/${n.replace(/\.txt$/, '.sql')}`).filter(defines);
  const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim())
    .filter((l) => l.endsWith('.sql')).filter(defines);
  return pending.at(-1) ?? manifest.at(-1);
};
const body = (file, name) => {
  const src = readFileSync(file, 'utf8');
  const at = src.search(new RegExp(String.raw`create\s+or\s+replace\s+function\s+public\.${name}\s*\(`, 'i'));
  return src.slice(at, src.indexOf('$fn$;', at));
};

test('the late-handoff predicate honours an answered handoff\'s due_at', () => {
  const file = newest(/function\s+public\.fn_handoff_is_late\s*\(/i);
  assert.ok(file, 'no canonical file defines fn_handoff_is_late');
  assert.match(body(file, 'fn_handoff_is_late'), /replied_at[\s\S]*due_at/, `${file}: fn_handoff_is_late must read due_at once replied`);
});

for (const fn of ['fn_ceo_seat_audit', 'fn_ceo_directive_run']) {
  test(`${fn} counts late handoffs through fn_handoff_is_late`, () => {
    const file = newest(new RegExp(String.raw`function\s+public\.${fn}\s*\(`, 'i'));
    const b = body(file, fn);
    assert.match(b, /fn_handoff_is_late\(/, `${file}: ${fn} must ask fn_handoff_is_late`);
    assert.doesNotMatch(b, /a\.created_at\s*<\s*(now\(\)|p_at)\s*-\s*k\.reply_within/,
      `${file}: ${fn} times a handoff from its reply window again; a month directive reads late on day 2`);
  });
}
