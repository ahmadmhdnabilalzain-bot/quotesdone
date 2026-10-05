// 4 Oct 2026 (seats ceo and it_engineer). The founder's IT digest listed handoffs "answered but never closed"
// that were either not due (a month directive the CEO closes at month end) or not answered at all (a review
// step held by the model hold), and every fault line claimed engineers were changing code when nobody was.
// These assert, on the canonical definitions (a pending file wins over MANIFEST):
//   1. the SLA duty times a handoff by its contract's due_at and never calls a held review step unclosed;
//   2. the originator closes every answered originator_closes handoff (fn_originators_reverify_handoffs §4);
//   3. the digest carries only founder decisions and never the false "work is under way" sentence.
// The behaviour itself is proved by the probe in the SQL file (answer -> closed in one tick; 0 founder lines
// for the current findings; 1 for a seeded founder decision).
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
// The body only, so a header comment describing the old sentence cannot match.
const body = (name) => {
  const re = new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\s*\\(`, 'i');
  const file = newest(re);
  assert.ok(file, `no file defines ${name}`);
  const src = readFileSync(file, 'utf8');
  const start = src.search(re);
  const end = src.indexOf('$function$', src.indexOf('$function$', start) + 10);
  return { file, text: src.slice(start, end) };
};

test('an answered handoff is late by its contract: due_at first, and a held review step is not answered', () => {
  const { file, text } = body('fn_it_handoff_sla_items');
  assert.match(text, /coalesce\(\(a\.detail->>'due_at'\)::timestamptz, a\.created_at\) due/, `${file}: the SLA duty must time a handoff from its due_at`);
  assert.match(text, /'\{step,action\}', ''\) = 'held' held/, `${file}: the SLA duty must recognise a step held by the model hold`);
  assert.match(text, /h\.t <> 'it\.finding' and not h\.held and now\(\) > h\.due \+ h\.w/, `${file}: the unclosed rule must use due and skip held`);
});

test('every originator_closes handoff that was answered has a closer', () => {
  const { file, text } = body('fn_originators_reverify_handoffs');
  assert.match(text, /join public\.seat_handoff_kind sk on [\s\S]*?sk\.originator_closes/, `${file}: section 4 must cover every originator_closes kind`);
  assert.match(text, /'verdict', 'answered within the contract of '/, `${file}: section 4 must close an answered handoff with its verdict`);
  assert.match(text, /perform public\.fn_seat_handoff_act\(h\.id\)/, `${file}: a reply that fails its contract is sent back and handled again (ruling 1059)`);
});

test('the IT digest carries only founder decisions and never claims a fix is under way', () => {
  const { file, text } = body('fn_customer_support_sends_the_it_digest');
  assert.doesNotMatch(text, /engineers are making/i, `${file}: the digest claims engineers are making a change`);
  assert.doesNotMatch(text, /open more than a day/i, `${file}: the digest still reports faults to the founder`);
  // An item reaches v_items only after the founder-decision class matched (to_founder = true).
  assert.match(text, /if found and not v_his then[\s\S]*?if not found then[\s\S]*?'digest', 'internal'[\s\S]*?continue;\s*end if;\s*v_items := v_items/,
    `${file}: an item without a founder-decision class must be kept internal before anything is added to the email`);
});
