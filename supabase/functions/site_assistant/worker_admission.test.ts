// site_assistant/worker_admission.ts: a worker runs at most `cap` turns at once; one more is answered busy at once and
// costs nothing (it_engineer, 11 Nov 2026, load test round 2; the module header carries the measurement).
//   DENO_NO_PACKAGE_JSON=1 deno test --no-lock --allow-read=. supabase/functions/site_assistant/worker_admission.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { BUSY_RETRY_MS, WORKER_TURNS_DEFAULT, busyBody, workerGate } from './worker_admission.ts';

Deno.test('the 18 turns the router stacked on worker 8872b574: eight run, ten are told to ask again, none is lost', () => {
  const g = workerGate(() => WORKER_TURNS_DEFAULT);
  const slots = Array.from({ length: 18 }, () => g.enter());
  assertEquals(slots.filter(Boolean).length, 8);
  assertEquals(g.inflight(), 8);
  assertEquals(g.shed(), 10);
  assertEquals(g.shed(), 0, 'the shed count is read and reset by the next observe row');
  slots[0]!(); slots[0]!();   // a release that runs twice frees one slot, not two
  assertEquals(g.inflight(), 7);
  assert(g.enter(), 'a freed slot takes the next turn');
  assertEquals(g.enter(), null);
});

Deno.test('the limit is read on every entry (retuned in app_secrets without a deploy); a missing one is the default', () => {
  let cap = 2; const g = workerGate(() => cap);
  const a = g.enter(), b = g.enter();
  assert(a && b); assertEquals(g.enter(), null);
  cap = 3; assert(g.enter(), 'a raised limit applies to the next turn');
  const zero = workerGate(() => 0);
  assertEquals(Array.from({ length: 10 }, () => zero.enter()).filter(Boolean).length, WORKER_TURNS_DEFAULT, 'a zero or missing limit is the default');
  const half = workerGate(() => 0.5); assert(half.enter(), 'never below one'); assertEquals(half.enter(), null);
});

Deno.test('the busy answer carries no text and asks for a spread delay', () => {
  const lo = busyBody(() => 0), hi = busyBody(() => 1);
  assertEquals(lo, { reply: '', busy: true, retry_after_ms: BUSY_RETRY_MS[0] });
  assertEquals(hi.retry_after_ms, BUSY_RETRY_MS[1]);
});

Deno.test('index.ts admits before anything else and releases on every path', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const serve = src.slice(src.indexOf('Deno.serve(async (req) => {'), src.indexOf('async function handle('));
  const enter = serve.indexOf('const release = gate.enter();');
  assert(enter > 0, 'Deno.serve no longer passes the gate');
  assert(enter < serve.indexOf('await req.text()'), 'the body is read before admission');
  assert(/if \(!release\) return J\(busyBody\(\)\);/.test(serve), 'a full worker does not answer busy');
  assert(/return plain\(req\)\.finally\(release\);/.test(serve), 'the plain turn does not release its slot');
  assert(/\.finally\(release\); \}\),/.test(serve), 'the streamed turn does not release its slot');
  assert(/catch \(e\) \{ release\(\); throw e; \}/.test(serve), 'a throw before the stream keeps the slot');
});
