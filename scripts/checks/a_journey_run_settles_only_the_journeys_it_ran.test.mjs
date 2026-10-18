// A harness run is complete once it attempted every journey it asked for, and it settles only the
// journeys it ran to their end (coordinator ruling, 19 Oct 2026). The harness also opens its rehearsal
// window with the models on (rulings 1244/1247), the way document_intake_accuracy.mjs does.
// Fails if: completeness goes back to "every journey in ORDER", a crashed or skipped journey counts as
// attempted, the ingests stop carrying the journeys a run did not finish, or the window opens models-off.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runIsComplete } from '../e2e/run_scope.mjs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

test('a run is complete once every journey it asked for was attempted', () => {
  const only = ['a', 'f'];
  assert.equal(runIsComplete({ truncated: false, harnessDead: null, only, attempted: new Set(['a', 'f']) }), true);
  assert.equal(runIsComplete({ truncated: false, harnessDead: null, only, attempted: new Set(['a']) }), false);
  assert.equal(runIsComplete({ truncated: true, harnessDead: null, only, attempted: new Set(only) }), false);
  assert.equal(runIsComplete({ truncated: false, harnessDead: 'signed out', only, attempted: new Set(only) }), false);
  assert.equal(runIsComplete({ truncated: false, harnessDead: null, only: [], attempted: new Set() }), false);
});

test('run.mjs reports the journeys that finished and judges completeness through run_scope', () => {
  const run = read('scripts/e2e/run.mjs');
  assert.match(run, /runIsComplete\(\{ truncated: state\.truncated, harnessDead, only, attempted \}\)/);
  assert.match(run, /await JOURNEYS\[k\]\(ctx\); finished\.add\(k\);/);
  assert.match(run, /journeys: RAN/);
  assert.doesNotMatch(run, /ORDER\.every\(\(k\) => only\.includes\(k\)\)/);
  assert.match(read('scripts/e2e/report_to_it_engineer.mjs'), /journeys: run\.journeys/);
});

test('both ingests carry the journeys a complete run did not finish (the canonical file)', () => {
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((s) => s.replace(/"/g, '').trim()).filter((s) => s && !s.startsWith('#'));
  const pending = (() => { try { return read('scripts/sql/pending/a_journey_run_settles_only_the_journeys_it_ran.txt'); } catch { return null; } })();
  assert.ok(pending !== null || manifest.includes('scripts/sql/a_journey_run_settles_only_the_journeys_it_ran.sql'),
    'the scoping file is neither applied (MANIFEST) nor pending');
  const sql = read('scripts/sql/a_journey_run_settles_only_the_journeys_it_ran.sql');
  assert.match(sql, /fn_it_duty_settle\('journey', v_items \|\| public\.fn_it_journey_scope_carried\('journey', p_report\)\)/);
  assert.match(sql, /fn_it_duty_settle\('smoke', v_items \|\| public\.fn_it_journey_scope_carried\('smoke', p_report\)\)/);
  assert.match(sql, /'carried', true/);
});

test('the harness window opens with the models on', () => {
  const fx = read('scripts/e2e/fixtures.mjs');
  const open = fx.slice(fx.indexOf('export async function openRun'), fx.indexOf('export async function openRun') + 1500);
  assert.match(open, /models_allowed, cap_usd, expires_at\)/);
  assert.match(open, /true, 15, now\(\) \+ interval '2 hours'/);
});
