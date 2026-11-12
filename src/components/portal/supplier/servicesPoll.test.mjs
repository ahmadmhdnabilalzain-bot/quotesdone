// node --test src/components/portal/supplier/servicesPoll.test.mjs
// THE LIST IS SHOWN THE MOMENT IT IS STORED (12 Nov 2026, sales_engineer; built by it_engineer). Certification J9 after #1973: stored at
// 117.1 s, on his screen at 130.3 s. Each case fails if the finished reading costs a second services_state, if the 2 s cadence runs
// before step A has landed (extra load for nothing) or not after it, if the poll outlives its 10 minutes, or if the Services tab
// draws the finished reading through `load` again.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { answerOrder, POLL_FAST_MS, POLL_FOR_MS, POLL_SLOW_MS, profileReading, sameProgress, startReadingPoll, stepALanded } from './servicesPoll.ts';

const doc = (status) => ({ kind: 'profile', status });
const READING = { ok: true, capability: { source_docs: { docs: [doc('reading')] } } };
const STEP_A = { ...READING, reading_progress: { stage: 'mapping', summary: 'ZZ DEMO interiors.', claims: [{ words: 'interior decoration', basis: 'stated' }] } };
const DONE = { ok: true, capability: { source_docs: { docs: [doc('read')] } }, proposed_services: [{ key: 'interior_fitout.decoration' }] };

// a fake clock: timers run only when the test advances them, and every armed delay is recorded
function clock() {
  let t = 0, seq = 0; const timers = new Map(); const delays = [];
  return {
    delays, now: () => t,
    setTimer: (fn, ms) => { const id = ++seq; delays.push(ms); timers.set(id, { at: t + ms, fn }); return id; },
    clearTimer: (id) => timers.delete(id),
    pending: () => timers.size,
    advance: async (ms) => { t += ms; },
    async next() { const [id, x] = [...timers.entries()].sort((a, b) => a[1].at - b[1].at)[0] || []; if (!id) return false; timers.delete(id); t = x.at; await x.fn(); return true; },
  };
}
function run(answers, { onScreen = () => false } = {}) {
  const c = clock(); const log = { fetches: 0, finished: [], progress: [] };
  let i = 0; let shown = false;
  const stop = startReadingPoll({
    fetchState: async () => { log.fetches++; const a = answers[Math.min(i++, answers.length - 1)]; if (a instanceof Error) throw a; return a; },
    mappingOnly: () => shown || onScreen(),
    onProgress: (p) => { shown = true; log.progress.push(p); },
    onFinished: (j) => log.finished.push(j),
    setTimer: c.setTimer, clearTimer: c.clearTimer, now: c.now,
  });
  return { c, log, stop };
}

test('the answer that says the reading finished is the one drawn: one request, never a second full load', async () => {
  const { c, log } = run([STEP_A, STEP_A, DONE]);
  while (await c.next());
  assert.equal(log.fetches, 3, 'two polls while reading, the third finds the list: no fourth request');
  assert.equal(log.finished.length, 1);
  assert.equal(log.finished[0], DONE, 'onFinished is handed the poll\'s own answer');
  assert.equal(c.pending(), 0, 'nothing is armed after the reading finished');
});

test('every 5 s while step A reads, every 2 s once its summary is stored (only the mapping left)', async () => {
  const { c, log } = run([READING, READING, STEP_A, STEP_A, STEP_A, DONE]);
  while (await c.next());
  assert.deepEqual(c.delays, [POLL_SLOW_MS, POLL_SLOW_MS, POLL_SLOW_MS, POLL_FAST_MS, POLL_FAST_MS, POLL_FAST_MS]);
  assert.equal(POLL_SLOW_MS, 5000); assert.equal(POLL_FAST_MS, 2000);
  assert.equal(log.progress.length, 3);
});

test('a tab that opens on a reading already past step A asks at 2 s from the first poll', async () => {
  const { c } = run([STEP_A, DONE], { onScreen: () => true });
  while (await c.next());
  assert.deepEqual(c.delays, [POLL_FAST_MS, POLL_FAST_MS]);
});

test('a failed or refused poll changes nothing and asks again at the same cadence', async () => {
  const { c, log } = run([new Error('network'), { ok: false, code: 'x' }, DONE]);
  while (await c.next());
  assert.deepEqual(c.delays, [POLL_SLOW_MS, POLL_SLOW_MS, POLL_SLOW_MS]);
  assert.equal(log.finished.length, 1); assert.equal(log.progress.length, 0);
});

test('it stops asking after 10 minutes, as the 120 polls of 5 s did', async () => {
  const { c, log } = run([STEP_A]);
  while (await c.next());
  assert.ok(c.now() <= POLL_FOR_MS + POLL_FAST_MS, `last ask at ${c.now()} ms`);
  assert.ok(log.fetches > 290 && log.fetches <= POLL_FOR_MS / POLL_FAST_MS, `${log.fetches} polls`);
  assert.equal(c.pending(), 0);
});

test('a slow answer is not followed by a further full wait: the cadence runs from the start of the ask, one ask at a time', async () => {
  const c = clock(); const asked = []; let k = 0;
  const answers = [STEP_A, STEP_A, DONE];
  startReadingPoll({
    // each answer takes 3.5 s (a cold start): the clock moves while the ask is in flight
    fetchState: async () => { asked.push(c.now()); const a = answers[k++]; await c.advance(3500); return a; },
    mappingOnly: () => true, onProgress: () => {}, onFinished: () => {}, setTimer: c.setTimer, clearTimer: c.clearTimer, now: c.now,
  });
  while (await c.next());
  assert.deepEqual(asked, [2000, 5500, 9000], 'the next ask follows a 3.5 s answer at once, never 2 s after it');
  for (let i = 1; i < asked.length; i++) assert.ok(asked[i] - asked[i - 1] >= POLL_FAST_MS, 'never more often than every 2 s');
});

test('stopped (the tab left, or the reading finished elsewhere): a late answer draws nothing', async () => {
  const c = clock(); const finished = []; let release;
  const stop = startReadingPoll({ fetchState: () => new Promise((r) => { release = r; }), mappingOnly: () => false, onProgress: () => {}, onFinished: (j) => finished.push(j), setTimer: c.setTimer, clearTimer: c.clearTimer, now: c.now });
  const p = c.next(); stop(); release(DONE); await p;
  assert.equal(finished.length, 0); assert.equal(c.pending(), 0);
});

test('the reading flags and the progress comparison', () => {
  assert.equal(profileReading(READING), true); assert.equal(profileReading(DONE), false); assert.equal(profileReading(null), false);
  assert.equal(stepALanded(STEP_A), true); assert.equal(stepALanded(READING), false);
  assert.equal(sameProgress(STEP_A.reading_progress, JSON.parse(JSON.stringify(STEP_A.reading_progress))), true);
  assert.equal(sameProgress(undefined, null), true); assert.equal(sameProgress(null, STEP_A.reading_progress), false);
});

test('the Services tab draws the finished reading from the poll\'s answer, never through a second load, and tells only a changed status', () => {
  const src = readFileSync(new URL('./ServicesTab.tsx', import.meta.url), 'utf8');
  const poll = src.slice(src.indexOf('return startReadingPoll({'), src.indexOf('}, [readingNow, token]);'));
  assert.ok(poll.length > 0, 'the tab polls through startReadingPoll');
  assert.match(poll, /onFinished: \(j\) => \(mounted\.current && order\.draw\(n\) \? \(show\(j as State, \{ keepText: true \}\), true\) : false\),/, 'the finished answer is drawn with show(), keeping his edits, and says whether it was');
  assert.doesNotMatch(poll, /\bload\(/, 'no second full services_state when the reading finishes');
  assert.doesNotMatch(src, /window\.setTimeout\(async \(\) => \{\s*polls\.current/, 'the old 5 s timer is gone');
  assert.match(src, /if \(!was \|\| was\.confirmed !== next\.confirmed[^)]*\) onStatus\(next\)/, 'the dashboard is told a status only when it changed');
});

// AN OLDER ANSWER NEVER REDRAWS THE SCREEN (12 Nov 2026, review of #1975, item 1), both ways round.
test('race: a poll asked before a Confirm that lands after the Confirm\'s reload is not drawn', () => {
  const o = answerOrder();
  const poll = o.ask();          // the poll asks (the old state: screen 1's rows)
  const reload = o.ask();        // he confirms; the reload asks
  assert.equal(o.draw(reload), true, 'the reload lands first and is drawn');
  assert.equal(o.newer(poll), false, 'the older poll moves no progress');
  assert.equal(o.draw(poll), false, 'the older poll lands after it and is not drawn');
});
test('race: a load asked before a poll that lands after the poll\'s answer is not drawn, and the poll\'s is', () => {
  const o = answerOrder();
  const load = o.ask(); const poll = o.ask();
  assert.equal(o.draw(poll), true);
  assert.equal(o.draw(load), false, 'the older load does not put the earlier state back');
  assert.equal(o.latest(load), false, 'an older failed load says nothing either');
});
test('in order, every answer is drawn; progress of the poll in flight moves while nothing later is on screen', () => {
  const o = answerOrder();
  const a = o.ask(); assert.equal(o.draw(a), true);
  const b = o.ask(); assert.equal(o.newer(b), true); assert.equal(o.draw(b), true); assert.equal(o.latest(b), true);
});
test('the tab numbers every services_state it asks for, the load and the poll, and draws only by that order', () => {
  const src = readFileSync(new URL('./ServicesTab.tsx', import.meta.url), 'utf8');
  assert.match(src, /const n = order\.ask\(\);\n\s*const j = await call\('supplier_api', \{ action: 'services_state' \}, token\)/, 'load numbers its ask');
  assert.match(src, /if \(j && j\.ok && order\.draw\(n\)\) show\(j as State, o\);/);
  assert.match(src, /fetchState: \(\) => \{ n = order\.ask\(\); return call\('supplier_api', \{ action: 'services_state' \}, token\); \}/);
  assert.match(src, /onFinished: \(j\) => \(mounted\.current && order\.draw\(n\) \? \(show\(j as State, \{ keepText: true \}\), true\) : false\),/);
  assert.match(src, /onProgress: \(p\) => \{ if \(mounted\.current && order\.newer\(n\)\)/);
  assert.equal((src.match(/action: 'services_state'/g) || []).length, 2, 'no third, unnumbered services_state');
});

// THE POLL STOPS ONLY WHEN THE FINISHED ANSWER WAS DRAWN (review of #1976, item 1). On 01dc2d2d1 the poll stopped before the tab
// decided; a refused draw (a later-asked load, which said a new reading had started, was on screen) left it dead with the tab saying
// "reading" until a reload.
test('a finished answer the tab refuses to draw does not stop the poll: it asks again', async () => {
  const c = clock(); let asks = 0; const offered = [];
  startReadingPoll({ fetchState: async () => { asks++; return asks === 1 ? DONE : asks === 2 ? STEP_A : DONE; }, mappingOnly: () => false, onProgress: () => {},
    onFinished: (j) => { offered.push(j); return offered.length > 1; },   // the first is refused, the second drawn
    setTimer: c.setTimer, clearTimer: c.clearTimer, now: c.now });
  while (await c.next());
  assert.equal(asks, 3, 'refused at the 1st ask, still reading at the 2nd, drawn at the 3rd: then it stops');
  assert.equal(offered.length, 2); assert.equal(c.pending(), 0);
});
test('a finished answer that is drawn stops the poll at once', async () => {
  const c = clock(); let asks = 0;
  startReadingPoll({ fetchState: async () => { asks++; return DONE; }, mappingOnly: () => false, onProgress: () => {}, onFinished: () => true,
    setTimer: c.setTimer, clearTimer: c.clearTimer, now: c.now });
  while (await c.next());
  assert.equal(asks, 1); assert.equal(c.pending(), 0);
});
test('a tab that is gone (the effect cleanup ran) re-arms nothing, even if its answer would be refused', async () => {
  const c = clock(); let release; let offered = 0;
  const stop = startReadingPoll({ fetchState: () => new Promise((r) => { release = r; }), mappingOnly: () => false, onProgress: () => {},
    onFinished: () => { offered++; return false; }, setTimer: c.setTimer, clearTimer: c.clearTimer, now: c.now });
  const p = c.next(); stop(); release(DONE); await p;
  assert.equal(offered, 0); assert.equal(c.pending(), 0, 'no poll is armed on a dead component');
});
