// The release train's decisions, offline (it_engineer, 29 Sep 2026). Each case is a way a PR could
// be merged that must not be: unreviewed, held, red, blocked by an unmerged dependency, a major bump.
import test from 'node:test';
import assert from 'node:assert/strict';
import { REQUIRED_CHECKS, dependsOn, isDependabotMinorPatch, checksGreen, inCampaignHours, refusal, applyOrder, driftFiles, isProbeNote }
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
  const red = [{ name: 'a', conclusion: 'FAILURE' }];
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
