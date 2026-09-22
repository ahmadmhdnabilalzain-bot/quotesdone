// The nightly removes other runs' leftovers only when those runs are over, never the founder's demo (22 Sep 2026, it_engineer).
//
// WHY THIS EXISTS. At 00:32Z on 22 Sep the nightly's request was routed to three ZZ DEMO aluminium
// suppliers left by runs 7e3a1c99 and 12ddadff (windows closed hours earlier); the per-trade cap is 3,
// so none of the run's own suppliers was invited and "routing invited the demo suppliers" failed.
// run.mjs now sweeps runs that are over (scripts/e2e/fixtures.mjs staleRunTags / sweepStaleRuns) by
// their exact tags. This fails if the sweep could reach the persistent founder demo accounts
// (instruction 571: leave demo records alone) or a run whose window is still open.
// Source only: importing fixtures.mjs reads the management token.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const FIX = readFileSync(join(ROOT, 'scripts/e2e/fixtures.mjs'), 'utf8');
const TOUR = readFileSync(join(ROOT, 'scripts/e2e/founder_demo_tour.mjs'), 'utf8');
const RUN = readFileSync(join(ROOT, 'scripts/e2e/run.mjs'), 'utf8');

test("the founder demo tour's tag is never swept", () => {
  const tag = TOUR.match(/export const TAG = '([a-z0-9]+)'/)?.[1];
  assert.ok(tag, 'founder_demo_tour.mjs no longer exports its TAG');
  const never = FIX.match(/const NEVER_SWEPT = new Set\(\[([^\]]*)\]\)/)?.[1] || '';
  assert.ok(never.includes(`'${tag}'`), `NEVER_SWEPT must hold '${tag}'`);
  assert.ok(FIX.includes('&& !NEVER_SWEPT.has(t))'), 'staleRunTags must filter NEVER_SWEPT out');
});

test('only runs whose every window has ended, past the grace, are stale', () => {
  const fn = FIX.slice(FIX.indexOf('export async function staleRunTags'), FIX.indexOf('export async function sweepStaleRuns'));
  assert.match(fn, /and exists \(select 1 from public\.rehearsal_window w where w\.run_tag = 'qd_run:' \|\| t\.tag\)/, 'a tag with no window is not ours to judge');
  assert.match(fn, /w\.ended_at is null or w\.ended_at > now\(\) - make_interval/, 'an open or just-closed window protects its run');
  assert.match(FIX.slice(FIX.indexOf('export async function sweepStaleRuns')), /teardown\(newRun\(\{ tag, quiet: true \}\)\)/, 'removal is the harness teardown by exact tag');
});

test('run.mjs sweeps before it creates its own fixtures', () => {
  assert.ok(RUN.indexOf('await sweepStaleRuns()') > 0 && RUN.indexOf('await sweepStaleRuns()') < RUN.indexOf('await makeDemoCustomer(run'));
});
