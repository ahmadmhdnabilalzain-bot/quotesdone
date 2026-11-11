// THE 10 NOV 2026 GLOCKAPPS VERDICT IS RECORDED FROM ITS FIXTURE, AND RECORDING IT MOVES NOTHING ELSE (it_engineer,
// founder ledger 1617, 10 Nov 2026: "run a new GlockApps inbox-placement test now, so supplier e-mail invitations keep
// running past 26 Nov").
//
// The verdict the invitation gate reads (fn_invite_placement_class_verdicts) is the latest deliverability_test row for
// supplier@. This test's row was written by scripts/sql/glockapps_10_nov_placement_verdict_is_recorded.sql, which inlines
// the connector's get_results answer. The check FAILS if:
//   * the inlined result drifts from scripts/checks/glockapps_10_nov_providers.fixture.json (the numbers in production
//     and the numbers in the repository must be the same measurement);
//   * the recorder no longer accepts that result (a provider row that does not add up, no providerRollup);
//   * the file stops being keyed on the test id (a re-apply would re-stamp recorded_at), or writes anything besides the
//     verdict: a campaign switch, the bar, the cap, a seat, or a notification (the seeds were sent once, by hand, and a
//     replayed file must never send them again);
//   * the file is not in MANIFEST exactly once, or also carries a pending note.
//
//   node --test scripts/checks/glockapps_10_nov_verdict_is_recorded_from_its_fixture.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const TEST_ID = '2026-11-10-21:29:37:367t';
const FILE = 'scripts/sql/glockapps_10_nov_placement_verdict_is_recorded.sql';
const FIXTURE = 'scripts/checks/glockapps_10_nov_providers.fixture.json';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('the file inlines exactly the fixture, and the recorder accepts it', async () => {
  const fx = JSON.parse(R(FIXTURE)); delete fx._source;
  assert.equal(fx.testId, TEST_ID);
  const lit = R(FILE).match(/\$glockapps\$(.*?)\$glockapps\$/s);
  assert.ok(lit, `${FILE} no longer inlines the GlockApps result`);
  assert.deepEqual(JSON.parse(lit[1]), fx, 'the recorded GlockApps numbers drifted from the fixture');
  const rec = await import('../record_inbox_placement_verdict.mjs');
  const p = rec.parseResult(R(FIXTURE));
  assert.equal(p.result.testId, TEST_ID);
  assert.ok(p.rollupSeeds > 0 && p.rollupSeeds <= fx.trackedSeeds, `rollup ${p.rollupSeeds} seeds, tracked ${fx.trackedSeeds}`);
});

test('the file records once, keyed on the test id, and writes nothing but the verdict', () => {
  const src = code(R(FILE));
  assert.match(src, /fn_record_inbox_placement_verdict\(\s*\$glockapps\$/, 'the verdict is not recorded through the routine');
  assert.ok(src.includes(`test_id = '${TEST_ID}'`) && /where\s+not\s+exists/i.test(src),
    'the record is not keyed on the test id, so a re-apply would re-stamp it');
  // Shapes, not spellings, so this comment cannot match: no write statement against any table.
  for (const [what, re] of [
    ['an UPDATE', /\bupdate\s+(public\.)?\w+\s+set\b/i], ['an INSERT', /\binsert\s+into\b/i], ['a DELETE', /\bdelete\s+from\b/i],
    ['DDL', /\b(create|alter|drop|grant|revoke|truncate)\s/i],
  ]) assert.doesNotMatch(src, re, `${FILE} carries ${what}; a verdict record writes only through the recorder`);
  assert.match(src, /'PROBE OK'/, 'the file does not end on a verdict row');
});

test('MANIFEST holds the file exactly once, with no pending note', () => {
  const lines = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.equal(lines.filter((l) => l === FILE).length, 1, `${FILE} must be in MANIFEST exactly once`);
  assert.ok(!existsSync(join(ROOT, 'scripts/sql/pending', FILE.split('/').pop().replace(/\.sql$/, '.txt'))),
    'an applied file keeps no pending note');
});
