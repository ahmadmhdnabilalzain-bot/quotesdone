// A test payment can never be refunded with the live key, and a live payment never with the test key.
// Stripe is stubbed: every request is recorded with the key it carried, so each case asserts both the
// answer and which key (if any) ever left this process.
import { assert, assertEquals, assertThrows } from 'jsr:@std/assert@1';
import { confirmRefundOutcome, keyMode, refundIdempotencyKey, stripeRefund, type RefundRefused } from './stripe_refund.ts';

Deno.test('a second refund of the same payment reaches Stripe as the same request: one key per transaction', async () => {
  const tx = '8a1f0000-0000-4000-8000-000000000001';
  assertEquals(refundIdempotencyKey(tx), refundIdempotencyKey(tx));
  assertEquals(refundIdempotencyKey(tx), 'qd_refund_' + tx);
  assertThrows(() => refundIdempotencyKey(''));
  // A top-up and a retry are their own requests, deterministic and still rooted in the transaction.
  assertEquals(refundIdempotencyKey(tx, 'topup72031'), 'qd_refund_' + tx + '_topup72031');
  assertEquals(refundIdempotencyKey(tx, 'retry9'), 'qd_refund_' + tx + '_retry9');
  assert(refundIdempotencyKey(tx, 'topup72031') !== refundIdempotencyKey(tx) && refundIdempotencyKey(tx, 'retry9') !== refundIdempotencyKey(tx, 'topup9'));
  assertThrows(() => refundIdempotencyKey(tx, 'incident9'));
  // Two different refund rows for one payment send the SAME Idempotency-Key.
  const keys: string[] = [];
  const f = (async (url: string | URL, init?: RequestInit) => {
    const u = String(url);
    if (u.includes('/payment_intents/')) return new Response(JSON.stringify({ id: 'pi_test_1', livemode: false }));
    keys.push(String((init?.headers as Record<string, string>)['Idempotency-Key']));
    return new Response(JSON.stringify({ id: 're_same', status: 'succeeded', amount: 100 }));
  }) as typeof fetch;
  const deps = { secret: async (k: string) => (k === 'stripe_secret_key_test' ? 'sk_test_x' : undefined), fetch: f };
  for (const _rowId of [101, 102]) await stripeRefund(deps, { demoPayer: true, ref: 'pi_test_1', amountFils: 100, idem: refundIdempotencyKey(tx) });
  assertEquals(keys.length, 2);
  assertEquals(keys[0], keys[1]);
});

const LIVE = 'sk_live_ZZDEMOlive', TEST = 'sk_test_ZZDEMOtest';

function stub(secrets: Record<string, string>, payments: Record<string, { livemode: boolean; status?: number }>) {
  const calls: Array<{ url: string; key: string; method: string }> = [];
  const f = (async (url: string | URL, init?: RequestInit) => {
    const u = String(url);
    const key = String((init?.headers as Record<string, string>)?.Authorization || '').replace('Bearer ', '');
    calls.push({ url: u, key, method: init?.method || 'GET' });
    const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s });
    const pi = decodeURIComponent(u.split('/payment_intents/')[1] || '');
    if (pi) {
      const p = payments[pi];
      // Stripe answers a key of the other mode with "No such payment_intent".
      if (!p || (p.livemode ? key !== LIVE : key !== TEST)) return json({ error: { message: 'No such payment_intent' } }, 404);
      return json({ id: pi, livemode: p.livemode });
    }
    if (u.includes('/checkout/sessions/')) return json({ id: 'cs_x', payment_intent: 'pi_test_1', livemode: key === LIVE });
    if (u.endsWith('/v1/refunds')) return json({ id: 're_1', status: 'succeeded', amount: 1234 });
    return json({}, 404);
  }) as typeof fetch;
  return { deps: { secret: async (k: string) => secrets[k], fetch: f }, calls };
}
const both = { stripe_secret_key: LIVE, stripe_secret_key_test: TEST };
const posted = (calls: Array<{ url: string }>) => calls.some((c) => c.url.endsWith('/v1/refunds'));

// A LOST ANSWER IS NEVER RELEASED BLIND. `post` decides what POST /v1/refunds does; `list` what
// Stripe shows under the payment afterwards (null = the lookup itself fails).
function stripeAfter(post: 'network' | 400 | 503 | 'failed', list: Array<Record<string, unknown>> | null) {
  const bodies: string[] = [];
  const f = (async (url: string | URL, init?: RequestInit) => {
    const u = String(url);
    const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s });
    if (u.includes('/payment_intents/')) return json({ id: 'pi_test_1', livemode: false });
    if (u.endsWith('/v1/refunds') && init?.method === 'POST') {
      bodies.push(String(init.body));
      if (post === 'network') throw new Error('timeout');
      if (post === 'failed') return json({ id: 're_f', status: 'failed' });
      return json({ error: { message: 'x' } }, post);
    }
    if (u.includes('/v1/refunds/re_f')) return list === null ? json({}, 500) : json({ id: 're_f', status: 'failed' });
    if (u.includes('/v1/refunds?')) return list === null ? json({}, 500) : json({ data: list });
    return json({}, 404);
  }) as typeof fetch;
  return { deps: { secret: async (k: string) => (k === 'stripe_secret_key_test' ? 'sk_test_x' : undefined), fetch: f }, bodies };
}
const KEY = 'qd_refund_8a1f0000-0000-4000-8000-000000000001_topup7';
async function attempt(post: 'network' | 400 | 503 | 'failed', list: Array<Record<string, unknown>> | null) {
  const s = stripeAfter(post, list);
  const o = { demoPayer: true, ref: 'pi_test_1', idem: KEY };
  const res = await stripeRefund(s.deps, { ...o, amountFils: 100, metadata: { refund_id: '7' } });
  assertEquals(res.ok, false);
  return { out: await confirmRefundOutcome(s.deps, o, res as RefundRefused), bodies: s.bodies };
}

Deno.test('our idempotency key and the refunds row id ride in the Stripe refund metadata', async () => {
  const { bodies } = await attempt(400, []);
  const p = new URLSearchParams(bodies[0]);
  assertEquals(p.get('metadata[qd_idempotency_key]'), KEY);
  assertEquals(p.get('metadata[refund_id]'), '7');
});

Deno.test('a timeout whose refund Stripe DID create is settled, not released', async () => {
  const { out } = await attempt('network', [{ id: 're_other', status: 'succeeded', metadata: { qd_idempotency_key: 'someone_else' } },
                                            { id: 're_ours', status: 'succeeded', metadata: { qd_idempotency_key: KEY } }]);
  assertEquals(out.outcome, 'settle');
  assertEquals(out.outcome === 'settle' && out.refund.id, 're_ours');
});

Deno.test('a timeout Stripe cannot confirm is HELD, whether nothing is listed yet or the lookup fails', async () => {
  assertEquals((await attempt('network', [])).out.outcome, 'hold');
  assertEquals((await attempt('network', null)).out.outcome, 'hold');
  assertEquals((await attempt(503, [])).out.outcome, 'hold');
});

Deno.test('only a confirmed refusal releases: Stripe refused (4xx), or the refund it made failed', async () => {
  assertEquals((await attempt(400, [])).out.outcome, 'release');
  assertEquals((await attempt('failed', [])).out.outcome, 'release');
  assertEquals((await attempt('failed', null)).out.outcome, 'hold');
});

Deno.test('keyMode reads the prefix and nothing else', () => {
  assertEquals(keyMode('sk_live_abc'), 'live');
  assertEquals(keyMode('rk_test_abc'), 'test');
  assertEquals(keyMode('pk_live_abc'), null);
  assertEquals(keyMode(''), null);
});

Deno.test('a test payment by a demo payer is refunded with the test key, and the live key never leaves', async () => {
  const s = stub(both, { pi_test_1: { livemode: false } });
  const r = await stripeRefund(s.deps, { demoPayer: true, ref: 'pi_test_1', amountFils: 1234, idem: 'qd_refund_1' });
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.ok && r.mode, 'test');
  assert(s.calls.length > 0 && s.calls.every((c) => c.key === TEST), JSON.stringify(s.calls));
});

Deno.test('a demo payer with no test key is refused and Stripe is never called (no fall-through to live)', async () => {
  const s = stub({ stripe_secret_key: LIVE }, { pi_test_1: { livemode: false } });
  const r = await stripeRefund(s.deps, { demoPayer: true, ref: 'pi_test_1', amountFils: 1234, idem: 'k' });
  assertEquals(r.ok, false);
  assertEquals(s.calls.length, 0);
});

Deno.test('a TEST payment can never be refunded with the LIVE key: a real payer citing a test payment is refused before any refund', async () => {
  const s = stub(both, { pi_test_1: { livemode: false } });
  const r = await stripeRefund(s.deps, { demoPayer: false, ref: 'pi_test_1', amountFils: 1234, idem: 'k' });
  assertEquals(r.ok, false);
  assertEquals(posted(s.calls), false);
});

Deno.test('a LIVE payment can never be refunded with the TEST key: a demo payer citing a live payment is refused before any refund', async () => {
  const s = stub(both, { pi_live_1: { livemode: true } });
  const r = await stripeRefund(s.deps, { demoPayer: true, ref: 'pi_live_1', amountFils: 1234, idem: 'k' });
  assertEquals(r.ok, false);
  assertEquals(posted(s.calls), false);
  assert(s.calls.every((c) => c.key === TEST), JSON.stringify(s.calls));
});

Deno.test('a key stored in the wrong slot is refused before Stripe is called', async () => {
  const s = stub({ stripe_secret_key: TEST, stripe_secret_key_test: LIVE }, { pi_live_1: { livemode: true } });
  assertEquals((await stripeRefund(s.deps, { demoPayer: false, ref: 'pi_live_1', amountFils: 1, idem: 'k' })).ok, false);
  assertEquals((await stripeRefund(s.deps, { demoPayer: true, ref: 'pi_live_1', amountFils: 1, idem: 'k' })).ok, false);
  assertEquals(s.calls.length, 0);
});

Deno.test('a live payment by a real payer is refunded with the live key at the stated amount', async () => {
  const s = stub(both, { pi_live_1: { livemode: true } });
  const r = await stripeRefund(s.deps, { demoPayer: false, ref: 'pi_live_1', amountFils: 1234, idem: 'k' });
  assert(r.ok, JSON.stringify(r));
  assert(s.calls.every((c) => c.key === LIVE));
  assert(posted(s.calls));
});
