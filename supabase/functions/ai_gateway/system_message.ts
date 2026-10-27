// THE SYSTEM MESSAGE AND ITS CACHE BREAKPOINTS (sales_engineer, 13 Oct 2026; the coordinator's options a and c).
// Measured 13 Oct on five live widget replies: the English and the Arabic brief were two different ~120k-token cached
// prefixes, so an Arabic reply wrote 122,782 tokens to the cache (USD 0.31) whenever its 5-minute entry had gone cold.
//   shared  - the block every conversation reply carries in every language and channel (the knowledge brief): first,
//             with its own breakpoint, so it is read from the cache whatever follows it;
//   stable  - the caller's own byte-stable half (company block, price guide, FAQ, its facts): second breakpoint;
//   sys     - what changes per call (the rules, the language, the person's facts): never cached.
// ttl '1h' asks Anthropic for the 1-hour tier (2x write against 1.25x); only the chat callers ask for it.
// prevented by: ai_gateway/system_message.test.ts

// deno-lint-ignore no-explicit-any
export type Block = { type: 'text'; text: string; cache_control?: Record<string, any> };

/** OpenRouter (or the provider behind it) refused the request because of the cache ttl: a 400 that names it. */
export function ttlRejected(status: number, body: string): boolean {
  return status === 400 && /\bttl\b|cache_control/i.test(body || '');
}
/** The same messages with every cache_control back on the default tier (the ttl field dropped, the breakpoints kept). */
// deno-lint-ignore no-explicit-any
export function withoutTtl(messages: any[]): any[] {
  // deno-lint-ignore no-explicit-any
  return messages.map((m: any) => !Array.isArray(m?.content) ? m : { ...m, content: m.content.map((b: any) =>
    b?.cache_control?.ttl ? { ...b, cache_control: { type: b.cache_control.type ?? 'ephemeral' } } : b) });
}

export function systemMessage(o: { shared: string; stable: string; sys: string; useCache: boolean; ttl: '1h' | null }):
  { role: 'system'; content: string | Block[] } | null {
  const text = o.shared + o.stable + o.sys;
  if (!text) return null;
  if (!o.useCache) return { role: 'system', content: text };
  const cc = o.ttl ? { type: 'ephemeral', ttl: o.ttl } : { type: 'ephemeral' };
  if (!o.shared && !o.stable) return { role: 'system', content: [{ type: 'text', text: o.sys, cache_control: cc }] };
  return { role: 'system', content: [
    ...(o.shared ? [{ type: 'text' as const, text: o.shared, cache_control: cc }] : []),
    ...(o.stable ? [{ type: 'text' as const, text: o.stable, cache_control: cc }] : []),
    ...(o.sys ? [{ type: 'text' as const, text: o.sys }] : []),
  ] };
}

/** Send; if the 1-hour tier was asked for and the route refuses the ttl field, send once more without it. Any other
 *  failure is returned as it came, for the gateway's own ladder to handle. */
// deno-lint-ignore no-explicit-any
export async function sendWithTtlFallback(send: (messages: any[]) => Promise<Response>, messages: any[], ttl: '1h' | null): Promise<Response> {
  const r = await send(messages);
  if (r.ok || !ttl || r.status !== 400) return r;
  const body = await r.clone().text().catch(() => '');
  return ttlRejected(r.status, body) ? await send(withoutTtl(messages)) : r;
}

/** THE CONVERSATION SO FAR IS CACHED TOO (18 Oct 2026, founder ruling: no turn limit, the stable prefix cached). A caller
 *  that sends cache_history marks the message BEFORE the newest one as a third breakpoint (Anthropic allows four), so a
 *  long chat reads its earlier turns from the cache and pays full price only for the newest pair. Only applied where
 *  the route caches at all (Google refuses cache_control). Messages are returned new; the input is not mutated. */
// deno-lint-ignore no-explicit-any
export function withHistoryBreakpoint(messages: any[], ttl: '1h' | null): any[] {
  if (!Array.isArray(messages) || messages.length < 2) return messages;
  const cc = ttl ? { type: 'ephemeral', ttl } : { type: 'ephemeral' };
  const i = messages.length - 2;
  const m = messages[i];
  const content = typeof m?.content === 'string'
    ? (m.content ? [{ type: 'text', text: m.content, cache_control: cc }] : m.content)
    // deno-lint-ignore no-explicit-any
    : Array.isArray(m?.content) ? m.content.map((b: any, k: number, a: any[]) => k === a.length - 1 && b?.type === 'text' ? { ...b, cache_control: cc } : b) : m?.content;
  return [...messages.slice(0, i), { ...m, content }, messages[i + 1]];
}
