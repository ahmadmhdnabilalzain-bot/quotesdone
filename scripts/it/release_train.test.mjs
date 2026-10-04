// The release train's decisions, offline (it_engineer, 29 Sep 2026). Each case is a way a PR could
// be merged that must not be: unreviewed, held, red, blocked by an unmerged dependency, a major bump.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { REQUIRED_CHECKS, dependsOn, isDependabotMinorPatch, checksGreen, inCampaignHours, refusal, mergeOrFlag, applyOrder, driftFiles, isProbeNote }
  from './release_train.mjs';

const green = [...REQUIRED_CHECKS.map((name) => ({ name, conclusion: 'SUCCESS' })), { name: 'a', conclusion: 'SUCCESS' }, { context: 'Vercel', state: 'SUCCESS' }];
const pr = (o = {}) => ({ number: 9, title: 'x', author: { login: 'someone' }, labels: [{ name: 'review-approved' }],
  mergeable: 'MERGEABLE', statusCheckRollup: green, body: '', baseRefName: 'main', ...o });

test('Depends-on lines are read, several numbers per line, case-insensitive', () => {
  assert.deepEqual(dependsOn('text\nDepends-on: #1040 and #1041\ndepends-on: #7\n#99 not a dep'), [1040, 1041, 7]);
  assert.deepEqual(dependsOn('mentions #5 only'), []);
});

test('only a Dependabot minor or patch bump skips the review label', () => {
  const d = (title) => ({ author: { login: 'app/dependabot' }, title });
  assert.equal(isDependabotMinorPatch(d('build(deps): bump the npm-minor-and-patch group with 23 updates')), true);
  assert.equal(isDependabotMinorPatch(d('bump x from 1.2.3 to 1.4.0')), true);
  assert.equal(isDependabotMinorPatch(d('bump x from 1.2.3 to 2.0.0')), false);
  assert.equal(isDependabotMinorPatch(d('bump x from 0.2.3 to 0.3.0')), false);
  assert.equal(isDependabotMinorPatch({ author: { login: 'someone' }, title: 'bump x from 1.2.3 to 1.2.4' }), false);
});

test('checks: none, pending or failed is not green', () => {
  assert.equal(checksGreen(green), true);
  assert.equal(checksGreen([]), false);
  // #998/#992, 29 Sep: a fresh head carrying only Vercel's statuses is not green - Actions had not started
  assert.equal(checksGreen([{ context: 'Vercel', state: 'SUCCESS' }, { context: 'Vercel Preview Comments', state: 'SUCCESS' }]), false);
  assert.equal(checksGreen(green.filter((c) => c.name !== 'the database is running what this repository says')), false);
  assert.equal(checksGreen([...green, { name: 'b' }]), false);
  assert.equal(checksGreen([...green, { name: 'b', conclusion: 'FAILURE' }]), false);
});

test('refusal names each blocker, and passes a clean PR', () => {
  assert.equal(refusal(pr()), null);
  assert.match(refusal(pr({ labels: [] })), /review-approved/);
  assert.match(refusal(pr({ labels: [{ name: 'review-approved' }, { name: 'hold' }] })), /hold/);
  assert.match(refusal(pr({ labels: [{ name: 'review-approved' }, { name: 'release-failed' }] })), /release-failed/);
  assert.match(refusal(pr({ mergeable: 'CONFLICTING' })), /mergeable/);
  assert.match(refusal(pr({ statusCheckRollup: [{ name: 'a', conclusion: 'FAILURE' }] })), /green/);
  assert.match(refusal(pr({ body: 'Depends-on: #1' }), { depState: () => 'OPEN' }), /#1/);
  assert.equal(refusal(pr({ body: 'Depends-on: #1' }), { depState: () => 'MERGED' }), null);
  assert.match(refusal(pr(), { campaign: true, offHoursFiles: ['scripts/sql/a.sql'] }), /campaign/);
  assert.equal(refusal(pr(), { campaign: false, offHoursFiles: ['scripts/sql/a.sql'] }), null);
  assert.match(refusal(pr({ isDraft: true })), /draft/);
});

test('campaign hours are read in Dubai time', () => {
  assert.equal(inCampaignHours(new Date('2026-09-29T06:00:00Z'), '08-20'), true);   // 10:00 Dubai
  assert.equal(inCampaignHours(new Date('2026-09-29T17:00:00Z'), '08-20'), false);  // 21:00 Dubai
  assert.equal(inCampaignHours(new Date('2026-09-29T20:00:00Z'), '22-06'), true);   // 00:00 Dubai, wrapped
});

test('a note that names another file of the PR runs after it', () => {
  const order = applyOrder([
    { sql: 'scripts/sql/a.sql', note: 'apply after b.sql is live' },
    { sql: 'scripts/sql/b.sql', note: 'first' },
    { sql: 'scripts/sql/c.sql', note: 'independent' },
  ]).map((x) => x.sql);
  assert.deepEqual(order, ['scripts/sql/b.sql', 'scripts/sql/a.sql', 'scripts/sql/c.sql']);
});

test('a note that says it runs BEFORE another file goes first (#1070)', () => {
  const order = applyOrder([
    { sql: 'scripts/sql/marketing_plans.sql', note: 'It must be\napplied BEFORE the_invitation_queue.sql (sales_engineer), which reads its table' },
    { sql: 'scripts/sql/the_invitation_queue.sql', note: 'sales engineer file' },
  ]).map((x) => x.sql);
  assert.deepEqual(order, ['scripts/sql/marketing_plans.sql', 'scripts/sql/the_invitation_queue.sql']);
});

test('an explicit apply-order line wins over file references and names', () => {
  const order = applyOrder([
    { sql: 'scripts/sql/a.sql', note: 'apply-order: 2\nafter b.sql' },
    { sql: 'scripts/sql/b.sql', note: 'apply-order: 3' },
    { sql: 'scripts/sql/c.sql', note: 'no order line' },
    { sql: 'scripts/sql/z.sql', note: 'Apply-Order: 1' },
  ]).map((x) => x.sql);
  assert.deepEqual(order, ['scripts/sql/z.sql', 'scripts/sql/a.sql', 'scripts/sql/b.sql', 'scripts/sql/c.sql']);
});

test('drift files are read from the repository-to-production section only', () => {
  const report = 'MANIFEST GAPS (1)\n  [scripts/sql/gap.sql]\nREPOSITORY -> PRODUCTION drift (canonical body not deployed) (2)\n'
    + '  fn_a  NOT PRESENT on production  [scripts/sql/a.sql]\n  fn_b  body differs  [scripts/sql/a.sql]\n'
    + 'PRODUCTION -> REPOSITORY drift (x) (0)\n';
  assert.deepEqual(driftFiles(report), ['scripts/sql/a.sql']);
  assert.deepEqual(driftFiles('nothing'), []);
});

test('a probe note is recognised', () => {
  assert.equal(isProbeNote('A PROBE, so it is never applied'), true);
  assert.equal(isProbeNote('Waits for the campaign to end'), false);
});

test('the one stale PR: oldest reviewed PR whose only blocker is finished, failing checks on a branch behind main', async () => {
  const { staleCandidate, checksRunning } = await import('./release_train.mjs');
  const red = [...green.filter((c) => c.name !== 'the database is running what this repository says'), { name: 'the database is running what this repository says', conclusion: 'FAILURE' }];
  const running = [{ name: 'a', conclusion: '', status: 'IN_PROGRESS' }];
  assert.equal(checksRunning(running), true);
  assert.equal(checksRunning(red), false);
  assert.equal(checksRunning([{ context: 'Vercel', state: 'PENDING' }]), true);
  const prs = [
    pr({ number: 1, labels: [] , statusCheckRollup: red }),            // not reviewed
    pr({ number: 2, statusCheckRollup: running }),                     // still running
    pr({ number: 3, statusCheckRollup: red }),                         // up to date with main
    pr({ number: 4, statusCheckRollup: red }),                         // the one
    pr({ number: 5, statusCheckRollup: red }),
  ];
  const isBehind = (p) => p.number !== 3;
  assert.equal(staleCandidate(prs, { isBehind })?.number, 4);
  assert.equal(staleCandidate(prs.slice(0, 3), { isBehind }), null);
  // up to date with main, but its CI never started (a GITHUB_TOKEN push): chosen, to start CI
  const vercelOnly = [{ context: 'Vercel', state: 'SUCCESS' }];
  assert.equal(staleCandidate([pr({ number: 7, statusCheckRollup: vercelOnly })], { isBehind: () => false })?.number, 7);
  assert.equal(staleCandidate([pr({ number: 6, statusCheckRollup: red, body: 'Depends-on: #9' })], { isBehind, depState: () => 'OPEN' }), null);
});

test('a check that ran twice counts once, by its latest run (#1095: CANCELLED then SUCCESS)', () => {
  const db = 'the database is running what this repository says';
  const rollup = [...green.filter((c) => c.name !== db),
    { name: db, conclusion: 'CANCELLED', startedAt: '2026-09-29T04:15:43Z', completedAt: '2026-09-29T04:15:44Z' },
    { name: db, conclusion: 'SUCCESS', startedAt: '2026-09-29T04:15:47Z', completedAt: '2026-09-29T04:16:49Z' }];
  assert.equal(checksGreen(rollup), true);
  const rerunRed = [...rollup, { name: db, conclusion: 'FAILURE', startedAt: '2026-09-29T05:00:00Z', completedAt: '2026-09-29T05:01:00Z' }];
  assert.equal(checksGreen(rerunRed), false);
  const running = [...rollup, { name: db, conclusion: '', status: 'IN_PROGRESS', startedAt: '2026-09-29T05:00:00Z', completedAt: '0001-01-01T00:00:00Z' }];
  assert.equal(checksGreen(running), false);
});

test('only a PR failing the live-database checks is refreshed; one failing its own code is left alone', async () => {
  const { staleCandidate, onlyStaleFailures } = await import('./release_train.mjs');
  const withFail = (name) => [...green.filter((c) => c.name !== name), { name, conclusion: 'FAILURE' }];
  const dbRed = withFail('the database is running what this repository says');
  const unitRed = withFail('classification, pricing and refund checks');
  assert.equal(onlyStaleFailures(dbRed), true);
  assert.equal(onlyStaleFailures(unitRed), false);
  const prs = [pr({ number: 1, statusCheckRollup: unitRed }), pr({ number: 2, statusCheckRollup: dbRed })];
  assert.equal(staleCandidate(prs, { isBehind: () => true })?.number, 2);
});

test('a failed apply is never followed by a deploy (#1050, 29 Sep)', () => {
  const src = readFileSync(new URL('./release_train.mjs', import.meta.url), 'utf8');
  const i = src.indexOf("scripts/deploy_functions.mjs");
  assert.ok(i > 0);
  assert.match(src.slice(Math.max(0, i - 400), i), /if \(failed\)[\s\S]*else \{/, 'the deploy must sit in the else of if (failed)');
});

test('a lock error is retried only when safe; any other error stops at once', async () => {
  const { applyWithRetry, isOneTransaction } = await import('./release_train.mjs');
  const deadlock = { code: 1, out: 'ERROR:  40P01: deadlock detected' };
  const ok = { code: 0, out: 'APPLIED' };
  const run = async (results, opts = {}) => {
    const seq = [...results]; const slept = [];
    const r = await applyWithRetry({ apply: () => seq.shift(), sqlText: opts.sql ?? 'create or replace function public.f() returns int language sql as $$select 1$$;',
      snapshot: opts.snapshot ?? (() => 'same'), windowOpen: opts.windowOpen, sleep: async (ms) => { slept.push(ms); }, jitter: () => 1 });
    return { ...r, slept };
  };
  // 40P01 then success: applied, so the release goes on to deploy
  let r = await run([deadlock, ok]);
  assert.equal(r.ok, true); assert.equal(r.attempts, 2); assert.deepEqual(r.slept, [5000]);
  // 40P01 three times: failed after 3 attempts (release-failed, no deploy)
  r = await run([deadlock, deadlock, deadlock]);
  assert.equal(r.ok, false); assert.equal(r.attempts, 3); assert.deepEqual(r.slept, [5000, 15000]);
  // 42P01 (undefined table): never retried
  r = await run([{ code: 1, out: 'ERROR:  42P01: relation "x" does not exist' }, ok]);
  assert.equal(r.ok, false); assert.equal(r.attempts, 1);
  // a lock error in a file with its own COMMIT is not provably rolled back: no retry
  r = await run([deadlock, ok], { sql: 'begin;\ncreate table x();\ncommit;' });
  assert.equal(r.ok, false); assert.equal(r.attempts, 1);
  // the routines moved (a partial apply): no retry
  let n = 0; r = await run([deadlock, ok], { snapshot: () => (n++ ? 'changed' : 'before') });
  assert.equal(r.ok, false); assert.equal(r.attempts, 1);
  // the off-hours window closed: stop, the next tick retries
  r = await run([deadlock, ok], { windowOpen: () => false });
  assert.equal(r.ok, false); assert.equal(r.attempts, 1);
  // 55P03 is a lock error too
  r = await run([{ code: 1, out: 'ERROR:  55P03: lock not available' }, ok]);
  assert.equal(r.ok, true);
  assert.equal(isOneTransaction('-- commit; in a comment\ncreate table y();'), true);
});

test('no retry for a file with a statement that cannot run inside a transaction', async () => {
  const { isOneTransaction } = await import('./release_train.mjs');
  assert.equal(isOneTransaction('create index concurrently i on t(a);'), false);
  assert.equal(isOneTransaction('vacuum analyze t;'), false);
  assert.equal(isOneTransaction("alter system set work_mem = '64MB';"), false);
  assert.equal(isOneTransaction("alter type public.k add value 'x';"), false);
  assert.equal(isOneTransaction('create or replace function public.f() returns int language sql as $$select 1$$;\ncreate index i on t(a);'), true);
  assert.equal(isOneTransaction('-- create index concurrently in a comment\ncreate table y();'), true);
});

test('no retry once the database accepted the file, and routinesIn reads unprefixed names', async () => {
  const { applyWithRetry, routinesIn } = await import('./release_train.mjs');
  const accepted = { code: 1, out: 'applied scripts/sql/x.sql to htdblwldjkcgjvmqkbeh\nDIFFERS ... 40P01 in a later read' };
  const seq = [accepted, { code: 0, out: '' }];
  const r = await applyWithRetry({ apply: () => seq.shift(), sqlText: 'create table t();', snapshot: () => 's', sleep: async () => {}, jitter: () => 1 });
  assert.equal(r.ok, false); assert.equal(r.attempts, 1);
  assert.deepEqual(routinesIn('create or replace function fn_x() returns int language sql as $$select 1$$;\ncreate or replace function public.fn_y() returns int language sql as $$select 1$$;'), ['fn_x', 'fn_y']);
});

test('#1141: a refused merge is flagged and labelled, and does not crash the run', () => {
  const calls = [];
  const ok = mergeOrFlag(pr(), {
    merge: () => { const e = new Error('Command failed: gh pr merge'); e.stderr = 'GraphQL: refusing to allow a GitHub App to create or update workflow without workflows permission'; throw e; },
    finding: (p, file, out) => calls.push(['finding', p.number, file, out]),
    label: (p) => calls.push(['label', p.number]),
  });
  assert.equal(ok, false);
  assert.equal(calls[0][2], 'merge');
  assert.match(calls[0][3], /workflows permission/);
  assert.deepEqual(calls[1], ['label', 9]);
  assert.equal(mergeOrFlag(pr(), { merge: () => 'ok', finding: () => assert.fail(), label: () => assert.fail() }), true);
});

test('a PR touching .github/workflows/ needs a human merge', () => {
  assert.match(refusal(pr({ files: [{ path: '.github/workflows/release-train.yml' }] })), /needs a human merge: workflow files/);
  assert.equal(refusal(pr({ files: [{ path: 'scripts/it/x.mjs' }] })), null);
});
