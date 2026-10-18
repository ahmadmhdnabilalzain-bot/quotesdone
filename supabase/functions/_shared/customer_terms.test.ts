// Run: deno test supabase/functions/_shared/customer_terms.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { needsReacceptance, customerTermsRecord } from './customer_terms.ts';

const secOf = (m: Record<string, string>) => async (k: string) => m[k] ?? null;

Deno.test('an older accepted version needs re-acceptance; the current one, none, or no current do not', () => {
  assertEquals(needsReacceptance({ tos_accepted_at: '2026-09-01', tos_version: 'v8' }, 'v9'), true);
  assertEquals(needsReacceptance({ tos_accepted_at: '2026-09-01', tos_version: 'v9' }, 'v9'), false);
  assertEquals(needsReacceptance({ tos_accepted_at: null, tos_version: null }, 'v9'), false); // sign-up handles it
  assertEquals(needsReacceptance({ tos_accepted_at: '2026-09-01', tos_version: 'v8' }, null), false);
});

Deno.test('the record carries the SHA only when the pin is for the version accepted', async () => {
  const r1 = await customerTermsRecord(secOf({ customer_terms_version: 'v9', terms_sha256_customer_version: 'v9', terms_sha256_customer: 'abc' }), '1.2.3.4');
  assertEquals([r1?.tos_version, r1?.tos_sha256, r1?.tos_ip], ['v9', 'abc', '1.2.3.4']);
  const r2 = await customerTermsRecord(secOf({ customer_terms_version: 'v10', terms_sha256_customer_version: 'v9', terms_sha256_customer: 'abc' }), '1.2.3.4');
  assertEquals([r2?.tos_version, r2?.tos_sha256], ['v10', null]);
  assertEquals(await customerTermsRecord(secOf({}), 'x'), null);
});
