// The harness's call() asks again only when no worker served the request (stage 2 run 4506ead8, 3 Nov 2026: a relay 502 at a
// five-minute mark cost S07 seven assertions). Same rule as the product's _shared/not_reached.ts.
//   node --test scripts/lib/demo_factory_call.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { askAgainIfNotReached, RELAY_RETRY_MS } from './demo_factory.mjs';
import { platformRefused } from '../../supabase/functions/_shared/not_reached.ts';

const seq = (...answers) => { let i = 0; const once = async () => answers[Math.min(i++, answers.length - 1)]; once.calls = () => i; return once; };
const noSleep = async () => {};
const relay502 = { status: 502, text: '<html>Bad gateway</html>', notReached: platformRefused(502, null) };
const ok = { status: 200, json: { ok: true }, notReached: false };

test('a relay 502 no worker served is asked again and the answer that follows is returned', async () => {
  const once = seq(relay502, ok);
  const r = await askAgainIfNotReached(once, noSleep);
  assert.equal(r.status, 200);
  assert.equal(once.calls(), 2);
  assert.equal('notReached' in r, false, 'the flag never leaves the harness');
});

test('anything a worker answered is returned at once, a 502 from the runtime and a 504 included', async () => {
  for (const a of [{ status: 502, notReached: platformRefused(502, 'supabase-edge-runtime') }, { status: 504, notReached: platformRefused(504, null) }, { status: 401, notReached: false }]) {
    const once = seq(a, ok);
    const r = await askAgainIfNotReached(once, noSleep);
    assert.equal(r.status, a.status);
    assert.equal(once.calls(), 1);
  }
});

test('a relay that keeps refusing stops after the bounded retries and returns the refusal', async () => {
  const once = seq(relay502);
  const r = await askAgainIfNotReached(once, noSleep);
  assert.equal(r.status, 502);
  assert.equal(once.calls(), RELAY_RETRY_MS.length + 1);
});
