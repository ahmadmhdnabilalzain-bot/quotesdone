// 7 Oct 2026 (wiring audit #1278, item 2): support.human_requested handoff 58191 sat pending 15 days. The 23-hour
// tick only looked at held requests (the founder's own number is never held), never closed what it followed up,
// and nothing escalated past the founder. This fails if the canonical tick filters on held again, stops reporting
// to the CEO at the reply clock, or stops closing the loop; or if the founder's own number opens a handoff again.
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
const body = (name) => {
  const file = newest(new RegExp(String.raw`create\s+or\s+replace\s+function\s+public\.${name}\s*\(`, 'i'));
  const src = readFileSync(file, 'utf8');
  const at = src.search(new RegExp(String.raw`create\s+or\s+replace\s+function\s+public\.${name}\s*\(`, 'i'));
  return [file, src.slice(at, src.indexOf('$fn$;', at))];
};

test('the human-request tick follows up every request, reports it to the CEO at the reply clock, and closes the loop', () => {
  const [file, b] = body('fn_wa_human_request_tick');
  const select = b.slice(b.indexOf('for r in select'), b.indexOf('loop', b.indexOf('for r in select')));
  assert.doesNotMatch(select, /'held'/, `${file}: the 23-hour selection filters on held again; an unheld request is never followed up`);
  assert.match(b, /fn_support_report_to_ceo\(\s*'wa_human:'/, `${file}: no CEO report at the reply clock`);
  assert.match(b, /reply_within/, `${file}: the escalation must use seat_handoff_kind.reply_within`);
  assert.match(b, /fn_seat_handoff_complete\(/, `${file}: the tick never closes a request`);
});

test('the founder\'s own number opens no handoff', () => {
  const [file, b] = body('fn_wa_human_request');
  assert.match(b, /audience'\s*,\s*''\)\s*=\s*'founder'/, `${file}: fn_wa_human_request must recognise the founder's own number`);
  assert.match(b, /if v_h is null and not v_founder/, `${file}: the founder's own number must not open a handoff`);
});
