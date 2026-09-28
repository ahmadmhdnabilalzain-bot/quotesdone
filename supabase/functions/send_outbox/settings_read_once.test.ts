// Every setting send_outbox reads on its main path is in the one bulk read (OUTBOX_KEYS). A new
// sec('...') outside the list silently brings back one round trip per key, the 8.4 s idle poll of 28 Sep 2026.
import { assert } from 'jsr:@std/assert@1';

Deno.test('every sec() key in send_outbox is read in the one bulk read', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const list = src.match(/OUTBOX_KEYS = \[([\s\S]*?)\];/)?.[1] ?? '';
  const listed = new Set([...list.matchAll(/'([a-z0-9_]+)'/g)].map((m) => m[1]));
  const used = new Set([...src.matchAll(/\bsec\('([a-z0-9_]+)'\)/g)].map((m) => m[1]));
  const missing = [...used].filter((k) => !listed.has(k));
  assert(listed.size > 0, 'OUTBOX_KEYS not found');
  assert(missing.length === 0, 'read one at a time: ' + missing.join(', '));
  assert(/await warmSecrets\(\);/.test(src), 'the handler no longer warms the settings');
});
