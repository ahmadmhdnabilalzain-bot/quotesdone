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
