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

// A RUN THAT IS ENDED EARLY STILL LEAVES NOTHING (it_engineer, 27 Oct 2026). Measured that day: 10 withRun runs since
// 26 Oct 19:47Z (the holds probe, probe 857.2) and two e2e runs left a ZZ DEMO lead or customer, every window closed
// only by the expiry sweep, i.e. by no process. The exit handlers closed the window and never tore the run down, and
// withRun never swept runs that were over. This fails if either comes back.
const FACTORY = readFileSync(join(ROOT, 'scripts/lib/demo_factory.mjs'), 'utf8');
const withRunSrc = FACTORY.slice(FACTORY.indexOf('export async function withRun'), FACTORY.indexOf('// ---- auth'));

test('withRun sweeps runs that are over before its own run starts, a few per start', () => {
  const sweep = withRunSrc.indexOf('sweepStaleRuns({ limit: ');
  assert.ok(sweep > 0, 'withRun does not sweep runs that are over (scripts/e2e/fixtures.mjs sweepStaleRuns)');
  assert.ok(sweep < withRunSrc.indexOf('return await fn(run)'), 'withRun must sweep before it runs its own fixtures');
  assert.match(FIX.slice(FIX.indexOf('export async function sweepStaleRuns')), /for \(const tag of \(await staleRunTags\(opts\)\)\.slice\(0, opts\.limit \?\? Infinity\)\)/,
    'sweepStaleRuns must take only the stale tags staleRunTags returns (NEVER_SWEPT already filtered out)');
});

test('a terminated run is torn down by its exit handler, not only its window closed', () => {
  const handler = withRunSrc.slice(withRunSrc.indexOf('closeOnExit('), withRunSrc.indexOf('return await fn(run)'));
  assert.match(handler, /if \(!run\.keep\) await teardown\(run\)/, "withRun's exit handler does not tear the run down");
  assert.match(handler, /finally \{ await closeRehearsalWindow\(run\.tag\); \}/, "withRun's exit handler must still close the window when teardown throws");
  assert.match(RUN, /const disarm = closeOnExit\(\(\) => closeRun\(run, \{ keep: KEEP \}\)\);/, "run.mjs's exit handler does not tear the run down (closeRun)");
});
