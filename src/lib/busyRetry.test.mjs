// node --test src/lib/busyRetry.test.mjs
// src/lib/busyRetry.ts: the widget asks again after a busy answer, a few times, with jitter (it_engineer, 11 Nov 2026).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { BUSY_TRIES, busyRetryDelay } from './busyRetry.ts';

test('a busy answer is asked again after its delay, growing, with jitter; anything else is not', () => {
  const busy = { reply: '', busy: true, retry_after_ms: 2000 };
  assert.equal(busyRetryDelay(busy, 0, () => 0), 2000);
  assert.equal(busyRetryDelay(busy, 1, () => 0), 3000);
  assert.equal(busyRetryDelay(busy, 2, () => 0), 4000);
  assert.equal(busyRetryDelay(busy, 4, () => 0), 4000, 'the growth is capped at 2x');
  // the whole window on average (base 3 s, mean jitter 0.75 s): longer than the ~20 s ramp of 11 Nov 04:33, under a minute at worst
  const total = (rnd, base) => Array.from({ length: BUSY_TRIES - 1 }, (_, a) => busyRetryDelay({ busy: true, retry_after_ms: base }, a, rnd)).reduce((x, y) => x + y, 0);
  assert.ok(total(() => 0.5, 3000) >= 25_000, 'mean window ' + total(() => 0.5, 3000));
  assert.ok(total(() => 1, 4500) <= 60_000, 'worst window ' + total(() => 1, 4500));
  assert.equal(BUSY_TRIES, 6);
  assert.equal(busyRetryDelay(busy, 0, () => 1), 3500, 'up to 1.5 s of jitter');
  assert.equal(busyRetryDelay(busy, BUSY_TRIES - 1, () => 0), null, 'the tries are used up');
  assert.equal(busyRetryDelay({ reply: 'hello' }, 0), null);
  assert.equal(busyRetryDelay({ error: 'no_answer', reply: '' }, 0), null);
  assert.equal(busyRetryDelay(null, 0), null);
  assert.equal(busyRetryDelay({ busy: true, retry_after_ms: 999999 }, 0, () => 0), 10000, 'a silly delay is capped');
  assert.equal(busyRetryDelay({ busy: true }, 0, () => 0), 3000, 'no delay given: 3 s');
});

test('the widget sends the message again on busy and does not wait 45 s for a stored answer that cannot exist', () => {
  const src = readFileSync(new URL('../components/ChatWidget.tsx', import.meta.url), 'utf8');
  assert.match(src, /const wait = busyRetryDelay\(j\.done, attempt\);\s*if \(wait === null\) break;\s*setStatus\(t\.late\);/);
  assert.match(src, /noVerdict\(j\) && j\.done\?\.busy !== true && conv\.current/);
});

test('a request the deadline cut: a stored answer is used, else the message is sent once more, never twice', async () => {
  const { CLIENT_TURN_MS, afterNoAnswer } = await import('./busyRetry.ts');
  assert.equal(afterNoAnswer({ timedOut: true, resent: false, stored: '' }), 'resend');
  assert.equal(afterNoAnswer({ timedOut: true, resent: true, stored: '' }), 'stop');
  assert.equal(afterNoAnswer({ timedOut: true, resent: false, stored: 'the answer' }), 'use_stored');
  assert.equal(afterNoAnswer({ timedOut: false, resent: false, stored: '' }), 'stop');
  // the deadline is past the turn's own clock (site_assistant/turn_outcome.ts SITE_TURN_MS), so it never cuts a running turn
  const clock = readFileSync(new URL('../../supabase/functions/site_assistant/turn_outcome.ts', import.meta.url), 'utf8');
  const siteTurn = Number(clock.match(/export const SITE_TURN_MS = ([\d_]+);/)[1].replace(/_/g, ''));
  assert.ok(CLIENT_TURN_MS >= siteTurn + 10_000, CLIENT_TURN_MS + ' vs ' + siteTurn);
  const src = readFileSync(new URL('../components/ChatWidget.tsx', import.meta.url), 'utf8');
  assert.match(src, /signal: AbortSignal\.timeout\(CLIENT_TURN_MS\)/, 'the widget request has no deadline');
  assert.match(src, /if \(then === 'resend'\) \{ resent = true; continue; \}/);
});
