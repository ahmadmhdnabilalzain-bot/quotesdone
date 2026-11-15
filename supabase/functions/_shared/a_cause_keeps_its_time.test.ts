// A TIME IS NOT A PHONE NUMBER (15 Nov 2026, review 2 of the certificate branch, item 10). maskContact (observe.ts) wrote
// "2026-11-13 08:47" as "<phone>:47" in a cause on agent_runs; the moment a write failed is what a seat reads it for.
// The contact it exists to hide is still hidden, next to a time or not.
//   deno test --no-lock --node-modules-dir=none supabase/functions/_shared/a_cause_keeps_its_time.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { maskContact } from './observe.ts';

Deno.test('maskContact keeps a date and a date-time as they are', () => {
  for (const t of ['2026-11-13 08', '2026-11-13 08:47', '2026-11-13T08:47:10.123Z', '2026-11-13 08:47:10+04:00', '2026-11-13', 'at 1999-12-31 23:59:59 UTC']) {
    assertEquals(maskContact('statement timeout at ' + t), 'statement timeout at ' + t, t);
  }
  assertEquals(maskContact('from 2026-11-13 08:00 to 2026-11-13 09:00, 3 tries'), 'from 2026-11-13 08:00 to 2026-11-13 09:00, 3 tries');
});

Deno.test('maskContact still masks a phone and an e-mail next to a time, and a number shaped like a date with a + or a 05 start', () => {
  const out = maskContact('2026-11-13 08:47 Key (phone)=(+971 50 123 4567) and zz-demo@example.invalid already exist');
  assert(out.startsWith('2026-11-13 08:47 '), out);
  assert(!out.includes('123 4567') && !out.includes('@example.invalid'), out);
  assert(out.includes('<phone>') && out.includes('<email>'), out);
  for (const p of ['0501234567', '+2010-12-1234', '971501234567', '0501-12-12 345']) assert(!maskContact('call ' + p).includes(p), p);
  assertEquals(maskContact(''), '');
  assertEquals(maskContact(undefined as unknown as string), '');
});
