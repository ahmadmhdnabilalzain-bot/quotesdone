// Incident 484 (24 Sep 2026): the delivery duty timed a digest-held request from the HANDOFF's created_at while
// the IT digest ages the same item by its FINDING's started_at, which restarts when the finding re-opens. The duty
// called handoff 80605 late at 29 hours; the digest was correctly holding it and delivered it the next day.
// This asserts that the canonical fn_it_duties (a pending file wins over MANIFEST) holds a digest item until the
// later of the two clocks, and that the digest still ages by the finding: if either side changes, both must.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const newest = (re) => {
  const defines = (f) => existsSync(f) && re.test(readFileSync(f, 'utf8'));
  // A probe is never applied (its note says so), so a stand-in it defines inside its rolled-back transaction is never the
  // canonical routine (12 Nov 2026: the hourly-duties probe replaces fn_it_duties with a stand-in to stay inside the API's time).
  const pending = readdirSync('scripts/sql/pending').filter((n) => !n.endsWith('_probe.txt'))
    .map((n) => `scripts/sql/${n.replace(/\.txt$/, '.sql')}`).filter(defines);
  const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim())
    .filter((l) => l.endsWith('.sql')).filter(defines);
  return pending.at(-1) ?? manifest.at(-1);
};

test('the delivery duty holds a digest item by the later of the handoff and its finding', () => {
  const file = newest(/function\s+public\.fn_it_duties\s*\(/i);
  const src = readFileSync(file, 'utf8');
  assert.match(src, /fn_it_digest_hold_ends\(greatest\(a\.created_at,\s*coalesce\(\s*\(select f\.started_at from public\.it_engineer_finding f/,
    `${file}: section 4 must time a held digest item from greatest(handoff created_at, open finding started_at)`);
});

// 4 Oct 2026: the digest stopped carrying faults, and with them its 24-hour young rule; every item is now
// decided at the first 19:00 tick. The duty's allowance above is therefore an upper bound and stays correct.
// If a young rule comes back, re-align fn_it_duties section 4 with it.
test('the digest holds no item past its next 19:00 tick', () => {
  const file = newest(/create\s+or\s+replace\s+function\s+public\.fn_customer_support_sends_the_it_digest\s*\(/i);
  assert.ok(file, 'no file defines fn_customer_support_sends_the_it_digest');
  assert.doesNotMatch(readFileSync(file, 'utf8'), /f\.started_at > p_now - interval/,
    `${file}: the digest ages items again; re-align fn_it_duties section 4 with it`);
});
