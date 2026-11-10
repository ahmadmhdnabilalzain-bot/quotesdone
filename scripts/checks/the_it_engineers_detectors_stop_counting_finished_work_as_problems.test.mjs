// THE IT ENGINEER'S DETECTORS STOP COUNTING FINISHED WORK AS PROBLEMS (it_engineer, 10 Nov 2026).
//
// Four detectors kept a finding open for work that was finished or recovered, so the founder brief's "N open technical
// problems" read 500 to 833: delivery (handoffs done as record_removed), latency_slo (a 30-day average that could not
// clear), reveal_reconcile (one test payment rewritten 139 times) and credential rotation (a cap of 3 a day for 45
// credentials due together). scripts/sql/the_it_engineers_detectors_stop_counting_finished_work_as_problems.sql fixed them.
//
// This fails if any of the four reverts. It reads the schema mirror (what production runs) followed by the
// MANIFEST-listed SQL (what merges apply), code only, and judges the LAST definition of each routine.
//
//   node --test scripts/checks/the_it_engineers_detectors_stop_counting_finished_work_as_problems.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const ROOT = join(import.meta.dirname, '..', '..');
const manifest = readFileSync(join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8').split('\n').map((l) => l.trim())
  .filter((l) => l && !l.startsWith('#')).map((l) => (l.startsWith('scripts/') ? l : `scripts/sql/${l}`));
const applied = manifest.filter((f) => existsSync(join(ROOT, f))).map((f) => readFileSync(join(ROOT, f), 'utf8')).join('\n');
// Code only: a comment that quotes the rule must not satisfy the check (apply-discipline, section 7).
const code = (readSchemaMirror() + '\n' + applied).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

const lastDefinition = (name) => {
  const re = new RegExp(`create or replace function public\\.${name}\\([^]*?\\n\\$(fn|function)\\$;?`, 'gi');
  const all = [...code.matchAll(re)];
  return all.length ? all[all.length - 1][0] : null;
};
const norm = (s) => s.replace(/\s+/g, ' ');

test('delivery: a handoff already done with a non-failure result is not a late delivery', () => {
  const duties = lastDefinition('fn_it_duties');
  assert.ok(duties, 'fn_it_duties is not defined');
  const delivery = norm(duties.slice(duties.indexOf("a.detail->>'type' = 'delivery.request'")));
  assert.match(delivery, /and not \(a\.status = 'done' and a\.detail->>'result' is not null and a\.detail->>'result' not in \('not_sent', 'no_response_confirmation', 'sent_unconfirmed'\)\)/,
    'a done delivery.request with a result must be excluded, and failure results must still be raised');
});

test('latency_slo: the 30-day term needs the 24-hour burn above 1 as well', () => {
  const judge = lastDefinition('fn_it_slo_judge');
  assert.ok(judge, 'fn_it_slo_judge is not defined');
  assert.match(norm(judge), /coalesce\(p_runs_30d, 0\) >= 5 and coalesce\(p_runs_24h, 0\) > 0 then p_bad_30d::numeric \/ p_runs_30d > 0\.001 and p_bad_24h::numeric \/ p_runs_24h \/ 0\.001 > 1/,
    'the 30-day bad-rate term must be ANDed with the 24-hour burn rate above 1');
});

test('reveal_reconcile: an item is not rewritten after 10 attempts, but a resolution still is', () => {
  const rec = lastDefinition('fn_accountant_reveal_reconcile_record');
  assert.ok(rec, 'fn_accountant_reveal_reconcile_record is not defined');
  assert.match(norm(rec), /where not \(it\.resolved_at is null and it\.attempts >= 10 and it\.outcome in \('failed', 'test_mode_not_demo', 'refunded_unrecorded'\) and excluded\.outcome in \('failed', 'test_mode_not_demo', 'refunded_unrecorded', 'deferred'\)\)/,
    'the upsert must stop rewriting an open failed/test_mode_not_demo/refunded_unrecorded item after 10 attempts');
  assert.doesNotMatch(norm(rec).match(/where not \(it\.resolved_at[^;]*?\)\);/)?.[0] ?? '', /recovered|refunded'|second_payment/,
    'recovered, refunded and second_payment must stay writable');
});

test('credential rotation: the per-run cap is 15 and the overlap window that makes that safe is still there', () => {
  const caps = [...code.matchAll(/update public\.it_threshold\s+set value = (\d+)[^;]*where key = 'credential_rotations_per_run'/gi)];
  assert.ok(caps.length, 'no file raises credential_rotations_per_run');
  assert.ok(Number(caps[caps.length - 1][1]) >= 15, 'credential_rotations_per_run must be at least 15 so 45 credentials clear in 3 days');
  const rotate = lastDefinition('fn_it_credential_rotate');
  assert.ok(rotate, 'fn_it_credential_rotate is not defined');
  assert.match(rotate, /update public\.app_secrets set value = v_secret/, 'the new secret must reach every caller through app_secrets');
  assert.match(rotate, /expires_at = now\(\) \+ v_overlap \+ 2 \* v_cadence where id = c\.id/, 'the old credential must stay valid through the overlap window');
  const reverify = lastDefinition('fn_it_credential_reverify');
  assert.ok(reverify, 'fn_it_credential_reverify is not defined');
  assert.match(reverify, /status = 'held'/, 'a rotation whose old credential is still presented must be held, not retired');
});
