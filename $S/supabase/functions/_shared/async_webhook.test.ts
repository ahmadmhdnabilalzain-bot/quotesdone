import { assert, assertEquals } from 'jsr:@std/assert';
import { ackThenWork, detach } from './async_webhook.ts';

Deno.test('the webhook is acknowledged at once while reasoning takes 20 s — well inside Twilio\'s 15 s and Meta\'s 20 s', async () => {
  const held: Promise<unknown>[] = [];
  let done = false;
  let release!: () => void;
  // stands for a 20 s think(): it does not finish until released below, long after the ack
  const slow = () => new Promise<void>((ok) => { release = () => { done = true; ok(); }; });
  const t0 = performance.now();
  const res = ackThenWork(new Response('<Response></Response>'), slow, 't', (p) => held.push(p));
  const ms = performance.now() - t0;
  assertEquals(res.status, 200);
  assert(ms < 100, `acknowledged in ${ms} ms`);
  assertEquals(done, false, 'the work is still running after the ack');
  assertEquals(held.length, 1, 'the runtime is told to keep the worker alive for it');
  release(); await held[0];
  assertEquals(done, true);
});

Deno.test('a failure after the ack is logged, never thrown', async () => {
  const held: Promise<unknown>[] = [];
  const res = ackThenWork(new Response('ok'), () => Promise.reject(new Error('boom')), 't', (p) => held.push(p));
  assertEquals(await res.text(), 'ok');
  await held[0];
});

Deno.test('detach keeps url, headers and the whole form body readable after the original is gone', async () => {
  const orig = new Request('https://x.test/functions/v1/wa_inbound', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': 'sig' }, body: 'From=whatsapp%3A%2B971&Body=hi' });
  const copy = await detach(orig);
  assertEquals(copy.url, orig.url);
  assertEquals(copy.headers.get('x-twilio-signature'), 'sig');
  assertEquals(await copy.text(), 'From=whatsapp%3A%2B971&Body=hi');
});
