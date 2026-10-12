// customer_support, 12 Oct 2026 (sandbox run f4294be8 S13). The widget's price reasoning is two model calls (7-15 s
// measured) and the reply is four more; run one after the other, a visitor waited 37-44 s for "How much does it
// cost to reveal a supplier?". The reply is composed while the price is reasoned. Only when a price block comes
// back (a real trade-price question) is it composed again with that block, because the block changes the facts.
// For every other question there is one composition and the wait is the longer of the two, not their sum.
// Never throws: a failed price lookup or a rejected first composition is treated as "nothing came back".
export async function replyBesidePrice<R>(price: Promise<string>, compose: (priceCtx: string) => Promise<R>): Promise<{ priceCtx: string; reply: R }> {
  const first = compose('').then((r) => ({ r }), () => null);
  const priceCtx = await price.catch(() => '');
  if (priceCtx) return { priceCtx, reply: await compose(priceCtx) };
  const done = await first;
  return { priceCtx, reply: done ? done.r : await compose('') };
}
