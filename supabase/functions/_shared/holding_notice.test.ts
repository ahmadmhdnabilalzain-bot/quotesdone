// The holding line's clock (holding_notice.ts, founder ruling 1636). Run: deno test supabase/functions/_shared/holding_notice.test.ts
// Known-bad controls: a timer that is not cleared on settle sends after a fast reply (the 'fast reply' test fails); a send
// with no fired-flag sends twice when the clock fires twice (the 'once' test fails).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { armHolding, HOLDING_AFTER_MS, HOLDING_LINE, holdingChannel, holdingDelay, holdingLine, registerHolding, settleHoldingFor, type HoldingClock } from './holding_notice.ts';

/** A clock the test drives: `fire()` runs every pending timer (twice, to prove a second firing does nothing). */
function fakeClock() {
  const timers = new Map<number, () => void>();
  let n = 0;
  const clock: HoldingClock = {
    setTimeout: (f) => { timers.set(++n, f); return n; },
    clearTimeout: (h) => { timers.delete(h as number); },
  };
  return { clock, pending: () => timers.size, fire: () => { for (const f of [...timers.values()]) { f(); f(); } } };
}

Deno.test('the timer fires once, never twice, and only when no reply was ready first', async () => {
  const c = fakeClock();
  let sent = 0;
  const h = armHolding({ delayMs: 9_000, send: async () => { sent++; }, clock: c.clock });
  c.fire(); c.fire();
  await h.settle();
  assertEquals(sent, 1);
  assert(h.fired);
});

Deno.test('a fast reply: settled before the clock, the holding line is never sent', async () => {
  const c = fakeClock();
  let sent = 0;
  const h = armHolding({ delayMs: 9_000, send: async () => { sent++; }, clock: c.clock });
  await h.settle();
  assertEquals(c.pending(), 0, 'the timer is cleared');
  c.fire();
  assertEquals(sent, 0);
  assert(!h.fired);
});

Deno.test('a send that is still reading when the reply leaves stands down (stillDue turns false)', async () => {
  const c = fakeClock();
  let release!: () => void;
  const gate = new Promise<void>((r) => { release = r; });
  let sentText = false;
  const h = armHolding({ delayMs: 0, clock: c.clock, send: async (stillDue) => { await gate; if (stillDue()) sentText = true; } });
  c.fire();
  const settled = h.settle();   // the reply is ready while the send reads the history
  release();
  await settled;
  assertEquals(sentText, false);
});

Deno.test('the delay is counted from the arrival: 9 s after it, 0 when that is already past', () => {
  assertEquals(HOLDING_AFTER_MS, 9_000);
  assertEquals(holdingDelay(1_000, 1_000), 9_000);
  assertEquals(holdingDelay(1_000, 5_000), 5_000);
  assertEquals(holdingDelay(1_000, 60_000), 0);
});

Deno.test('never on email; WhatsApp and the web chats only', () => {
  assertEquals(holdingChannel('email'), false);
  assertEquals(holdingChannel('sms'), false);
  for (const c of ['whatsapp', 'widget', 'portal', 'intake']) assert(holdingChannel(c), c);
});

Deno.test('the line: Arabic for an Arabic-writing customer, English for a supplier always, and no promise of a time', () => {
  assertEquals(holdingLine('ar', 'customer'), HOLDING_LINE.ar);
  assertEquals(holdingLine('ar', 'supplier'), HOLDING_LINE.en);
  assertEquals(holdingLine('en', 'visitor'), HOLDING_LINE.en);
  for (const l of Object.values(HOLDING_LINE)) {
    assert(!/\d|minute|second|دقيقة|ثانية|\bAI\b/i.test(l), 'promises a time or names AI: ' + l);
    assert(l.length < 120);
  }
});

Deno.test('a reply leaving for the person settles the line armed for them (any branch of the turn)', async () => {
  const c = fakeClock();
  let sent = 0;
  const h = registerHolding('whatsapp:+971500000077', armHolding({ delayMs: 9_000, send: async () => { sent++; }, clock: c.clock }));
  settleHoldingFor('+971 50 000 0077');   // the same person, written another way
  c.fire();
  await h.settle();
  assertEquals(sent, 0);
});
