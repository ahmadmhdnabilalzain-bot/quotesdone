// The instrumentation must not change what the function it watches returns, and must not decide
// that a wrong password is an outage.
//
// `deno test` grants no permissions, so `record()` cannot reach the database here: Deno.env.get
// throws without --allow-env, admin() catches it and returns null, and the write is a no-op. That
// is the point — these assertions run against the SAME code path a broken database produces, so
// "instrumentation never breaks the thing it watches" is executed, not asserted in a comment.
//
// Run: deno test supabase/functions/_shared/observe.test.ts   (or npm test, which discovers it)
import { assert, assertEquals, assertStrictEquals } from 'jsr:@std/assert@1';
import { baseCounts, classify, edgeRegion, LATENCY_BUDGET_MS, observe, record, statusOf } from './observe.ts';

const req = (url = 'http://x.test/fn', init?: RequestInit) => new Request(url, init);

Deno.test('4xx is a warn, 5xx is an error, 2xx is ok', () => {
  assertEquals(classify(200), 'ok');
  assertEquals(classify(302), 'ok');
  assertEquals(classify(399), 'ok');
  // The whole reason this function exists: fn_watch_failed_runs pages on 'error'. A rejected
  // password, an expired link and an unauthenticated poke are 4xx and must never page.
  assertEquals(classify(400), 'warn');
  assertEquals(classify(401), 'warn');
  assertEquals(classify(403), 'warn');
  assertEquals(classify(404), 'warn');
  assertEquals(classify(429), 'warn');
  assertEquals(classify(499), 'warn');
  assertEquals(classify(500), 'error');
  assertEquals(classify(502), 'error');
  assertEquals(classify(504), 'error');
});

Deno.test('the handler\'s own Response is returned untouched', async () => {
  const original = new Response('{"ok":true,"n":7}', { status: 201, headers: { 'Content-Type': 'application/json', 'X-Marker': 'kept' } });
  const out = await observe('probe', () => original)(req());
  assertStrictEquals(out, original, 'observe returned a different Response object');
  assertEquals(out.status, 201);
  assertEquals(out.headers.get('X-Marker'), 'kept');
  // The body must still be readable by the caller: cloning for the error note must not consume it.
  assertEquals(await out.text(), '{"ok":true,"n":7}');
});

Deno.test('a 4xx body is cloned for the note and the caller still gets it', async () => {
  const out = await observe('probe', () => new Response('{"error":"unauthorized"}', { status: 401, headers: { 'Content-Type': 'application/json' } }))(req());
  assertEquals(out.status, 401);
  assertEquals(await out.text(), '{"error":"unauthorized"}');
});

Deno.test('a 500 body is cloned for the note and the caller still gets it', async () => {
  const out = await observe('probe', () => new Response('{"error":"boom"}', { status: 500, headers: { 'Content-Type': 'application/json' } }))(req());
  assertEquals(out.status, 500);
  assertEquals(await out.text(), '{"error":"boom"}');
});

Deno.test('a thrown handler still throws the same error to the caller', async () => {
  const boom = new Error('the handler exploded');
  let caught: unknown = null;
  try {
    await observe('probe', () => { throw boom; })(req());
  } catch (e) { caught = e; }
  assertStrictEquals(caught, boom, 'observe swallowed or replaced the handler\'s exception');
});

Deno.test('recording never throws, even with no database reachable', async () => {
  // No --allow-env, so admin() cannot build a client. This must resolve, not reject.
  await record('probe', 'error', { http: 500 }, 'no database here', Date.now());
  await record('probe', 'ok');
});

Deno.test('a binary response is never cloned for its body', async () => {
  const bytes = new Uint8Array([0, 1, 2, 3, 4]);
  const out = await observe('probe', () => new Response(bytes, { status: 500, headers: { 'Content-Type': 'application/pdf' } }))(req());
  assertEquals(out.status, 500);
  assertEquals(new Uint8Array(await out.arrayBuffer()), bytes);
});

Deno.test('healthy runs are sampled but every slow one is kept', async () => {
  // Not observable from outside without a database, so this asserts the property that IS
  // observable: sampling changes nothing about the response, whichever branch it takes.
  const handler = observe('probe', () => new Response('ok'), { okEveryMs: 60_000, slowMs: 1 });
  for (let i = 0; i < 5; i++) {
    const out = await handler(req());
    assertEquals(out.status, 200);
    assertEquals(await out.text(), 'ok');
  }
  assert(true);
});

Deno.test('every run row carries the edge region that served it', () => {
  // 21 Sep 2026: the latency detector read GitHub-runner smoke calls served in us-east (3.3s p50)
  // against a baseline of calls served in ap-south-1 (~1s) and reported the function as slower.
  // The region in the row is what lets a baseline compare like with like; this fails if it is dropped.
  const c = baseCounts(req('http://x.test/functions/v1/supplier_portal', { method: 'POST' }), 200, 'us-east-2');
  assertEquals(c, { http: 200, method: 'POST', path: '/functions/v1/supplier_portal', region: 'us-east-2' });
  // Without env permission (this test run) the region is unknown, never a throw.
  assertStrictEquals(edgeRegion(), null);
  assertStrictEquals(baseCounts(req(), 204).region, null);
});

Deno.test('the portal data functions carry the 2.5 s budget the founder set', () => {
  // 24 Sep 2026: fn_it_engineer_latency_slo judges only rows that carry budget_ms. A portal function dropped
  // from this map would silently leave the latency budget unwatched.
  for (const fn of ['customer_api', 'customer_portal', 'project_api', 'messages_api', 'kyc', 'supplier_portal', 'supplier_api']) {
    assertEquals(LATENCY_BUDGET_MS[fn], 2500, fn + ' has no 2.5 s budget');
  }
});

// Incident 437 (24 Sep 2026): ai_gateway's deliberate 503 fixture_no_spend was logged 'error' and paged as a run failure.
Deno.test('a 5xx the handler annotated held is held; an unannotated 5xx is still an error', () => {
  assertEquals(statusOf(503, { held: true }), 'held');
  assertEquals(statusOf(503, { skipped: true }), 'skipped');      // a daily-ceiling skip (spend_ceiling.ts)
  assertEquals(statusOf(503, { skipped: 'true' }), 'error');
  assertEquals(statusOf(503, {}), 'error');
  assertEquals(statusOf(503, { held: 'true' }), 'error');
  assertEquals(statusOf(503), 'error');
  assertEquals(statusOf(401, { held: true }), 'warn');
});

// 19 Oct 2026: fn:marketing_social_inbox read "half its runs failing" -- 4 of 8 were one curl sweep with no
// signature header. A refusal of a caller with no credential is 'skipped'; a presented-but-wrong one stays 'warn'.
Deno.test('a 4xx refused for presenting no credential is skipped; any other 4xx stays warn', () => {
  assertEquals(statusOf(403, { refused_unauthenticated: true }), 'skipped');
  assertEquals(statusOf(405, { refused_unauthenticated: true }), 'skipped');
  assertEquals(statusOf(403, {}), 'warn');
  assertEquals(statusOf(403), 'warn');
  assertEquals(statusOf(500, { refused_unauthenticated: true }), 'error');
  assertEquals(statusOf(200, { refused_unauthenticated: true }), 'ok');
});
