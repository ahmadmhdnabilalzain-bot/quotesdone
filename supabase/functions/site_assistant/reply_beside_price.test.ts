// prevented by: this test (sandbox run f4294be8 S13, 12 Oct 2026). The reply starts before the price reasoning ends;
// a question with no price block is composed ONCE; a price block is composed into the reply; nothing rejects.
import { assertEquals } from 'jsr:@std/assert';
import { replyBesidePrice } from './reply_beside_price.ts';

const later = <T>(v: T, ms: number) => new Promise<T>((ok) => setTimeout(() => ok(v), ms));

Deno.test('no price block: one composition, started before the price lookup finished', async () => {
  const calls: string[] = []; let priceDone = false; let startedBefore = false;
  const price = later('', 30).then((v) => { priceDone = true; return v; });
  const r = await replyBesidePrice(price, (p) => { calls.push(p); startedBefore = !priceDone; return later('reply:' + p, 10); });
  assertEquals(calls, ['']);
  assertEquals(startedBefore, true);
  assertEquals(r.reply, 'reply:');
});

Deno.test('a price block: the reply that goes out carries it', async () => {
  const calls: string[] = [];
  const r = await replyBesidePrice(later('BANDS', 20), (p) => { calls.push(p); return later('reply:' + p, 5); });
  assertEquals(r.reply, 'reply:BANDS');
  assertEquals(r.priceCtx, 'BANDS');
  assertEquals(calls, ['', 'BANDS'], 'the beside composition, then the one with the block (only on a trade-price question)');
});

Deno.test('a failed price lookup and a rejected first composition never throw', async () => {
  let n = 0;
  const r = await replyBesidePrice(Promise.reject(new Error('down')), () => (++n === 1 ? Promise.reject(new Error('x')) : Promise.resolve('ok')));
  assertEquals(r.reply, 'ok');
  assertEquals(r.priceCtx, '');
});
