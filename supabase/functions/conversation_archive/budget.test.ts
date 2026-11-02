// deno test supabase/functions/conversation_archive/budget.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { drawingMs, mayRenderNext, RENDER_BUDGET_MS } from './budget.ts';

Deno.test('the first render always starts, so the oldest message is never starved', () => {
  assert(mayRenderNext(0, 0));
});

Deno.test('KNOWN-BAD control: after one slow render the worker stops instead of drawing three more (1 Nov 546s)', () => {
  assert(!mayRenderNext(900, 900));
  assert(mayRenderNext(200, 150));
  // a run of short messages is drawn back to back until the budget is used
  let spent = 0, slowest = 0, drawn = 0;
  for (const ms of [180, 220, 190, 210, 200, 230]) { if (!mayRenderNext(spent, slowest)) break; spent += ms; slowest = Math.max(slowest, ms); drawn++; }
  assertEquals(drawn, 5);   // 180+220+190+210+200 = 1000 ms; a sixth would pass 1,200 with the slowest (220)
  assert(RENDER_BUDGET_MS < 2000, 'the budget sits under the edge CPU cap');
});

Deno.test('a cold asset fetch is not drawing time (review of #1797: a cold start cut a sweep to 1-2 PDFs)', () => {
  assertEquals(drawingMs(1500, 1300), 200);   // a 1.3 s font fetch on a fresh worker, 200 ms of drawing
  assertEquals(drawingMs(300, 0), 300);
  assertEquals(drawingMs(100, 400), 0);
  // four short messages behind a cold first render still all fit
  let spent = 0, slowest = 0, drawn = 0;
  for (const [wall, wait] of [[1500, 1300], [210, 0], [190, 0], [220, 0]]) {
    if (!mayRenderNext(spent, slowest)) break; const d = drawingMs(wall, wait); spent += d; slowest = Math.max(slowest, d); drawn++;
  }
  assertEquals(drawn, 4);
});

Deno.test('the sweep consults the budget before each render and times only the drawing', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assertMatch(src, /if \(!mayRenderNext\(renderMs, slowestMs\)\)/);
  assertMatch(src, /renderPdf\(conversationDocument\(m\), \{ fetchBytes: timedFetchBytes, identity \}\)/);
  assertMatch(src, /drawingMs\(performance\.now\(\) - t0, waitedMs - w0\)/);
});
