// node --test src/lib/stillWorking.test.mjs
// src/lib/stillWorking.ts: a web chat shows "still working" when the answer is slow (founder ruling 1636, it_engineer 11 Nov 2026).
// Known-bad controls: a late line that ignores `answering` covers the first sentence of the answer (test 2 fails); one that is
// not idempotent is shown again on every keep-alive (test 3 counts it twice).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { STILL_WORKING_MS, stillWorking } from './stillWorking.ts';

function fake() {
  const pending = new Map(); let n = 0;
  return { timers: { set: (f) => { pending.set(++n, f); return n; }, clear: (h) => pending.delete(h) }, fire: () => { for (const f of [...pending.values()]) f(); }, pending };
}

test('no answer after STILL_WORKING_MS: the late line replaces the server status', () => {
  const shown = []; const c = fake();
  const s = stillWorking((t) => shown.push(t), 'Still working on your answer…', STILL_WORKING_MS, c.timers);
  s.status('Writing your answer…');
  c.fire();
  assert.deepEqual(shown, ['Writing your answer…', 'Still working on your answer…']);
  assert.equal(STILL_WORKING_MS, 8000);
});

test('a fast answer: the first sentence clears the status and the late line never shows', () => {
  const shown = []; const c = fake();
  const s = stillWorking((t) => shown.push(t), 'late', STILL_WORKING_MS, c.timers);
  s.status('Writing your answer…'); s.status('');   // a delta arrived
  c.fire(); s.working(); s.stop();
  assert.deepEqual(shown, ['Writing your answer…', '']);
  assert.equal(c.pending.size, 0, 'stop clears the timer');
});

test('the server keep-alive shows the late line once; a later server status does not cover it', () => {
  const shown = []; const c = fake();
  const s = stillWorking((t) => shown.push(t), 'late', STILL_WORKING_MS, c.timers);
  s.working(); s.working(); c.fire(); s.status('Writing your answer…');
  assert.deepEqual(shown, ['late']);
});

test('every web chat uses it: the widget and the portal assistant, and the request chat waits the same 8 s', async () => {
  const { readFileSync } = await import('node:fs');
  const widget = readFileSync(new URL('../components/ChatWidget.tsx', import.meta.url), 'utf8');
  assert.match(widget, /stillWorking\(setStatus, t\.late\)/);
  assert.match(widget, /working: sw\.working/);
  const panel = readFileSync(new URL('../components/me/shell/AssistantPanel.tsx', import.meta.url), 'utf8');
  assert.match(panel, /stillWorking\(setStatus, t\('asst_still'\)\)/);
  const helpers = readFileSync(new URL('../components/me/newRequest/helpers.ts', import.meta.url), 'utf8');
  assert.match(helpers, /SLOW_TURN_MS = STILL_WORKING_MS/);
  const reader = readFileSync(new URL('./portalReply.ts', import.meta.url), 'utf8');
  assert.match(reader, /e\.t === 'working'\) on\.working\?\.\(\)/);
});
