// Every setting send_outbox reads on its main path is in the one bulk read (OUTBOX_KEYS), and is read
// through setting(). A new setting('...') outside the list, or a direct sec('...') call that skips the
// bulk read, silently brings back one round trip per key, the 8.4 s idle poll of 28 Sep 2026.
import { assert } from 'jsr:@std/assert@1';

Deno.test('every setting() key in send_outbox is read in the one bulk read, and nothing calls sec() directly', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const list = src.match(/OUTBOX_KEYS = \[([\s\S]*?)\];/)?.[1] ?? '';
  const listed = new Set([...list.matchAll(/'([a-z0-9_]+)'/g)].map((m) => m[1]));
  const used = new Set([...src.matchAll(/\bsetting\('([a-z0-9_]+)'\)/g)].map((m) => m[1]));
  const missing = [...used].filter((k) => !listed.has(k));
  const direct = [...src.matchAll(/\bsec\('([a-z0-9_]+)'\)/g)].map((m) => m[1]);
  assert(listed.size > 0, 'OUTBOX_KEYS not found');
  assert(used.size > 0, 'no setting() reads found');
  assert(missing.length === 0, 'read one at a time: ' + missing.join(', '));
  assert(direct.length === 0, 'sec() called directly, skipping the bulk read: ' + direct.join(', '));
  assert(/await warmSecrets\(\);/.test(src), 'the handler no longer warms the settings');
});
