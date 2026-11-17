// Run: deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/unsubscribe/token.test.ts
// The unsubscribe token is checked in constant time (security audit 17 Nov 2026, finding 5). No value below is real.
import { assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { unsubscribeToken, unsubscribeTokenMatches } from './token.ts';

const KEY = 'zz-demo-unsubscribe-key', LEGACY = 'zz-demo-legacy-key';
const E = 'zz.demo@example.invalid';

Deno.test('a link signed with the current or the legacy key opens; any other token does not', async () => {
  const t = await unsubscribeToken(E, KEY), old = await unsubscribeToken(E, LEGACY);
  assertEquals(t.length, 20);
  assertEquals(await unsubscribeTokenMatches(E, t, [KEY, LEGACY]), true);
  assertEquals(await unsubscribeTokenMatches(E, old, [KEY, LEGACY]), true);
  assertEquals(await unsubscribeTokenMatches(E.toUpperCase(), t, [KEY, LEGACY]), true, 'the address is case-folded as send_outbox signs it');
  assertEquals(await unsubscribeTokenMatches(E, t.slice(0, 19), [KEY, LEGACY]), false, 'a prefix is not the token');
  assertEquals(await unsubscribeTokenMatches(E, t + '0', [KEY, LEGACY]), false);
  assertEquals(await unsubscribeTokenMatches('other@example.invalid', t, [KEY, LEGACY]), false);
  assertEquals(await unsubscribeTokenMatches(E, old, [KEY, undefined]), false, 'an unset legacy key verifies nothing');
  assertEquals(await unsubscribeTokenMatches(E, '', [KEY]), false);
  assertEquals(await unsubscribeTokenMatches('', t, [KEY]), false);
});

Deno.test('the unsubscribe handler compares its token only through the constant-time check', async () => {
  const src = await Deno.readTextFile('supabase/functions/unsubscribe/index.ts');
  assertMatch(src, /await unsubscribeTokenMatches\(e, t, \[signKey, legacyKey\]\)/);
  assertEquals(/t === \(await tok\(/.test(src), false, 'the token is compared with === again');
  assertEquals(/async function tok\(/.test(src), false, 'a second copy of the token derivation is back in the handler');
});
