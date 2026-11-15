// A DRAWING IS CHECKED INSIDE THE REQUEST THAT CARRIES IT, OR HELD FOR TIME AND SAID (round 4 of the drawings fix,
// 15 Nov 2026, sales_engineer; third review ANONYMITY F3 DRAWINGS 3, fix 2; _shared/drawing_deadline.ts).
// READ before: an A1 page is about 21 model calls (4 at a time) plus a crop worker each; the pages ran one by one inside
// analyze_drawing's 150 s edge wall with no deadline, so a 3-4 page A1 set passed the wall, the worker was killed, no held
// row was written and nothing was shared. Offline; every model is a stub. The SLOW stub answers each call in 8 s of a
// virtual clock, four at a time as the gate's pool runs them; the same set on a real clock is in the hand-back.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/drawing_redact/a_drawing_is_checked_inside_its_request.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { DRAWING_DEADLINE, TIME_HELD, callTimeoutMs, deadlinesFrom, eachPageInTime } from '../_shared/drawing_deadline.ts';
import { pageSizeFromMediaBox, pixelBudget, pixelGate, planTiles, type Tile } from '../_shared/drawing_pixel_gate.ts';

const A1 = pageSizeFromMediaBox(841 / (25.4 / 72), 594 / (25.4 / 72));

/** A virtual clock: sleep(ms) waits on it, and run() moves it to the next timer once every waiting call has registered. */
function virtualClock(t0 = 0) {
  let t = t0; const timers: { at: number; go: () => void }[] = [];
  const sleep = (ms: number) => new Promise<void>((go) => timers.push({ at: t + ms, go }));
  async function run<T>(p: Promise<T>): Promise<T> {
    let done = false, val: T | undefined, err: unknown = null;
    p.then((v) => { done = true; val = v; }, (e) => { done = true; err = e; });
    while (!done) {
      await new Promise((r) => setTimeout(r, 0));
      if (done || !timers.length) continue;
      const at = Math.min(...timers.map((x) => x.at)); t = at;
      for (const x of timers.filter((y) => y.at === at)) { timers.splice(timers.indexOf(x), 1); x.go(); }
    }
    if (err) throw err;
    return val as T;
  }
  return { now: () => t, sleep, run };
}

/** One A1 page through the gate: every model call takes `callMs` of the clock; four run at once (the gate's pool). */
function slowGate(clock: ReturnType<typeof virtualClock>, callMs: number, stopAt: number) {
  const crop = async (_b: string, _t: Tile, mark: string) => mark;          // the "view" is its mark: the stub copies it
  const ask = async (shown: string) => { await clock.sleep(callMs); return JSON.stringify({ mark: shown, clean: true, addressed: false, regions: [] }); };
  return pixelGate('page', ask, async (b) => b, pixelBudget(), { plan: planTiles(A1), crop, stopAt, now: clock.now });
}

Deno.test('the deadlines: 100 s to start a page, 125 s to abandon one; a caller may bring them earlier, never later', () => {
  const t0 = 1_000_000;
  assertEquals(deadlinesFrom({}, t0), { startBy: t0 + 100_000, stopAt: t0 + 125_000 });
  assertEquals(deadlinesFrom({ deadline_at: t0 + 50_000, stop_at: t0 + 80_000 }, t0), { startBy: t0 + 50_000, stopAt: t0 + 80_000 });
  assertEquals(deadlinesFrom({ deadline_at: t0 + 900_000, stop_at: 'never' }, t0), { startBy: t0 + 100_000, stopAt: t0 + 125_000 }, 'a later value is ignored');
  assertEquals(deadlinesFrom({ stop_at: t0 + 60_000 }, t0).startBy, t0 + 60_000, 'no page starts after the stop');
  assert(DRAWING_DEADLINE.stopAtMs + 8_000 < 140_000, 'one more 8 s call still lands inside analyze_drawing\'s 140 s answer budget');
});

Deno.test('SLOW stub (8 s a call) on a 4-page A1 set: pages 1-2 checked, page 3 abandoned at 125 s, page 4 never started; all four accounted for', async () => {
  const clock = virtualClock(), d = deadlinesFrom({}, 0);
  assertEquals(planTiles(A1).calls, 21);
  const ran = await clock.run(eachPageInTime(4, (_i) => slowGate(clock, 8_000, d.stopAt), d.startBy, clock.now));
  const outcome = ran.done.map((x) => x.out.ok ? 'checked' : x.out.held);
  // 21 calls, 4 at a time, 8 s each: six rounds, 48 s a page. Page 1 ends at 48 s, page 2 at 96 s; page 3 starts before
  // 100 s, its fifth round would start at 128 s, past the stop, so it is cut; page 4 is never started.
  assertEquals(outcome, ['checked', 'checked', TIME_HELD]);
  assertEquals(ran.notReached, [3]);
  assertEquals(clock.now(), 128_000, 'the last call ended at 128 s, inside analyze_drawing\'s 140 s answer budget');
  const cut = ran.done[2].out;
  assert(!cut.ok && cut.held === TIME_HELD && Number(cut.detail.not_asked) > 0, 'views not asked are named, not answered');
  assert(!cut.ok && cut.calls < 21, 'what was never asked is not counted as spent');
  assertEquals(ran.done.length + ran.notReached.length, 4, 'no page is lost: each is checked, held for time, or not started');
});

Deno.test('a page whose views all answered before the stop is not held for time; a stop before the first view holds at once', async () => {
  const c1 = virtualClock();
  const fast = await c1.run(slowGate(c1, 100, 125_000));
  assert(fast.ok);
  const c2 = virtualClock(200_000);
  const late = await c2.run(slowGate(c2, 100, 125_000));
  assert(!late.ok && late.held === TIME_HELD && late.calls === 0);
});

Deno.test('drawing_redact starts no page after the clock and passes stopAt to every gate; customer_api sends its own clock and says the hold', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assertMatch(src, /const clock = deadlinesFrom\(body, startedAt\);/);
  assertEquals((src.match(/if \(Date\.now\(\) >= clock\.startBy\) \{ skipped\+\+; timePages\.push\(i\);/g) ?? []).length, 2, 'both the manual and the model loop check the clock before each page');
  assertEquals((src.match(/await gatePage\([^\n]*clock\.stopAt(?:, vocabularyVet\(pp, (?:\[\]|seeds)\))?\);/g) ?? []).length, 6, 'every gate call carries the stop');
  assertMatch(src, /time_held: timePages\.length, time_held_pages: timePages, redaction_complete: recorded && paths\.length === imgs\.length \}\);/);
  const api = Deno.readTextFileSync(new URL('../customer_api/actions/documents.ts', import.meta.url));
  assertMatch(api, /deadline_at: redStartBy, stop_at: redStopAt/);
  assertMatch(api, /const ran = await eachPageInTime\(batches, async \(b\) => \{/);
  assertMatch(api, /redIn \+= notReached\.length; timeHeld \+= notReached\.length;/);
  assertMatch(api, /\.\.\.timeNote\(timeHeld, \[\.\.\.abandoned, \.\.\.notReached\]\)/);
  assertMatch(api, /const reason = timeHeld \? 'time' :/);
});

// Round 5 (fourth review, fix 3): a view under way at the stop was not cut (the model call had no signal: the gateway's 55 s;
// a crop 60 s, a repaint 90 s twice), so it outlived customer_api's 140 s abort and the page was lost as redactor_died.
Deno.test('SLOW stub: a model call started at 124 s is cut by 135 s and the page is held for time; every call carries the stop', async () => {
  assertEquals(callTimeoutMs(125_000, 55_000, () => 124_000), 11_000, 'started at 124 s: cut at 135 s');
  assertEquals(callTimeoutMs(125_000, 55_000, () => 10_000), 55_000, 'early: its own cap');
  assertEquals(callTimeoutMs(125_000, 60_000, () => 200_000), 1_000, 'past the stop: one second, never zero');
  assertEquals(callTimeoutMs(undefined, 90_000), 90_000);
  // The gate on a virtual clock: one view, a model that would take 30 s, honouring the timeout it is given.
  const clock = virtualClock(124_000), stopAt = 125_000;
  const ask = async (shown: string) => {
    const ms = callTimeoutMs(stopAt, 55_000, clock.now);
    await clock.sleep(Math.min(30_000, ms));
    return ms < 30_000 ? null : JSON.stringify({ mark: shown, clean: true, addressed: false, regions: [] });   // aborted: no answer
  };
  const one = { tiles: [{ x: 0, y: 0, w: 1, h: 1, outW: 100, outH: 70 }], whole: null, cols: 1, rows: 1, textPx: 12, calls: 1, usd: 0, page: A1 };
  const g = await clock.run(pixelGate('page', ask, async (b) => b, pixelBudget(), { plan: one, crop: async (_b, _t, m) => m, stopAt, now: clock.now }));
  assert(!g.ok && g.held === TIME_HELD, 'an answer the stop cut is held for time, not unverified');
  assert(clock.now() <= 140_000, `the call ended at ${clock.now() / 1000} s, before customer_api's 140 s abort`);
  assertEquals(clock.now(), 135_000);
  // A repaint the clock cut is time too.
  const c2 = virtualClock(120_000);
  const g2 = await c2.run(pixelGate('page', async (shown) => JSON.stringify({ mark: shown, clean: false, addressed: false, regions: [{ x: 0.1, y: 0.1, w: 0.1, h: 0.1 }] }),
    async () => { await c2.sleep(callTimeoutMs(125_000, 90_000, c2.now)); throw new Error('repaint_failed'); }, pixelBudget(), { plan: one, crop: async (_b, _t, m) => m, stopAt: 125_000, now: c2.now }));
  assert(!g2.ok && g2.held === TIME_HELD && c2.now() === 135_000);
  // drawing_redact: the model, crop and repaint calls all take their timeout from the stop.
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assertMatch(src, /const ms = callTimeoutMs\(stopAt, 55_000\);\n\s*const r = await fetch\(GW, \{[^\n]*signal: AbortSignal\.timeout\(ms\),\n[^\n]*client_timeout_ms: ms,/);
  assertMatch(src, /mode: 'repaint', verify: false[^\n]*signal: AbortSignal\.timeout\(callTimeoutMs\(stopAt, 90_000\)\)/);
  assertMatch(src, /mode: 'tile', jpg_b64: jpgB64, tile, mark \}\), signal: AbortSignal\.timeout\(callTimeoutMs\(stopAt, 60_000\)\)/);
  assertMatch(src, /askPixels\(key, authors, b, stopAt\), \(b, regions\) => paintElsewhere\(secret, b, regions, stopAt\)[^\n]*cropElsewhere\(secret, b, t, m, stopAt\)/);
  // customer_api: a batch the clock cut is time (the time message), not a dead redactor; abandoned pages are recorded.
  const api = Deno.readTextFileSync(new URL('../customer_api/actions/documents.ts', import.meta.url));
  assertMatch(api, /if \(cutByClock\(e, Date\.now\(\), redStopAt\)\) \{ timeHeld \+= slice\.length; abandoned\.push\(/);
  assertMatch(api, /const cut = pagesHeldForTime\(rj, i, slice\.length\); timeHeld \+= cut\.length; abandoned\.push\(\.\.\.cut\);/);
  assertMatch(api, /pages_abandoned: abandoned, pages_not_started: notReached/);
});
