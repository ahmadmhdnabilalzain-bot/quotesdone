// The holding line's clock (holding_notice.ts, founder ruling 1636). Run: deno test supabase/functions/_shared/holding_notice.test.ts
// Known-bad controls: a timer that is not cleared on settle sends after a fast reply (the 'fast reply' test fails); a send
// with no fired-flag sends twice when the clock fires twice (the 'once' test fails).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { armHolding, HOLDING_AFTER_MS, HOLDING_LINE, holdingDelay, holdingLine, registerHolding, answeredHoldingFor, settleHoldingFor, type HoldingClock } from './holding_notice.ts';

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

// 12 Nov 2026 (final audit W2): 15 s, was 9 s. At 9 s the line preceded 29 of 29 replies; the reason is at HOLDING_AFTER_MS.
Deno.test('the delay is counted from the arrival: 15 s after it, 0 when that is already past', () => {
  assertEquals(HOLDING_AFTER_MS, 15_000);
  assertEquals(holdingDelay(1_000, 1_000), 15_000);
  assertEquals(holdingDelay(1_000, 5_000), 11_000);
  assertEquals(holdingDelay(1_000, 60_000), 0);
});

Deno.test('never on email: no function that sends or answers mail reaches the holding line', () => {
  const root = new URL('../', import.meta.url);
  const files: string[] = [];
  const walk = (dir: URL, rel: string) => {
    for (const e of Deno.readDirSync(dir)) {
      if (e.isDirectory) walk(new URL(e.name + '/', dir), rel + e.name + '/');
      else if (e.name.endsWith('.ts') && !e.name.endsWith('.test.ts')) files.push(rel + e.name);
    }
  };
  for (const fn of ['email_triage', 'send_outbox', 'resend_inbound', 'inbound_email']) walk(new URL(fn + '/', root), fn + '/');
  assert(files.length > 5, 'the mail functions were read');
  const reach = files.filter((f) => /holding_notice|wa_inbound\/holding|HOLDING_LINE|armHolding/.test(Deno.readTextFileSync(new URL(f, root))));
  assertEquals(reach, []);
});

Deno.test('the line: Arabic for an Arabic-writing customer, English for a supplier always, and no promise of a time', () => {
  assertEquals(holdingLine('ar', 'customer'), HOLDING_LINE.ar[0]);
  assertEquals(holdingLine('ar', 'supplier'), HOLDING_LINE.en[0]);
  assertEquals(holdingLine('en', 'visitor'), HOLDING_LINE.en[0]);
  // a wording the person was given recently is not given again while another is left (12 Nov 2026, W2)
  assertEquals(holdingLine('en', 'customer', [HOLDING_LINE.en[0]]), HOLDING_LINE.en[1]);
  assertEquals(holdingLine('ar', 'customer', [HOLDING_LINE.ar[1], HOLDING_LINE.ar[0]]), HOLDING_LINE.ar[2]);
  assertEquals(holdingLine('en', 'customer', [HOLDING_LINE.en[2], HOLDING_LINE.en[1], HOLDING_LINE.en[0]]), HOLDING_LINE.en[0], 'all used: the one given longest ago');
  assertEquals(HOLDING_LINE.en.length, HOLDING_LINE.ar.length);
  for (const l of [...HOLDING_LINE.en, ...HOLDING_LINE.ar]) {
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
  assertEquals(sent, 0);
  // review of 12 Nov 2026: leaving is not arriving. Only a delivered reply answers the line; a failed send leaves it unanswered
  assert(!h.answered, 'a reply that is only leaving does not count as answered');
  answeredHoldingFor('whatsapp:+971500000077');
  await h.settle();
  assert(h.answered, 'a delivered reply answers it');
});
