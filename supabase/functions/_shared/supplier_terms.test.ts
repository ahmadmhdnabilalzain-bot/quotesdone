// deno test supabase/functions/_shared/supplier_terms.test.ts
// 24 Sep 2026: the acceptance row kept time, version, IP and hash but never the browser that accepted.
import { assertEquals } from 'jsr:@std/assert';
import { clientIp, supplierTermsRecord } from './supplier_terms.ts';
import { SUPPLIER_AGREEMENT_VERSION } from './supplier_agreement.ts';

const sec = (v: string | null) => (k: string) => Promise.resolve(k === 'supplier_terms_version' ? v : null);

Deno.test('the acceptance row records the user agent beside the IP, clipped to 500', async () => {
  const r = await supplierTermsRecord(sec(SUPPLIER_AGREEMENT_VERSION), '203.0.113.9', ' Mozilla/5.0 ' + 'x'.repeat(600));
  assertEquals(r?.accepted_terms_user_agent?.length, 500);
  assertEquals(r?.accepted_terms_user_agent?.startsWith('Mozilla/5.0 '), true);
  assertEquals(r?.accepted_terms_ip, '203.0.113.9');
  assertEquals(r?.accepted_terms_version, SUPPLIER_AGREEMENT_VERSION);
  assertEquals(r?.accepted_terms_sha256?.length, 64);
});

Deno.test('no User-Agent header records null, never an empty string', async () => {
  assertEquals((await supplierTermsRecord(sec(SUPPLIER_AGREEMENT_VERSION), '', ''))?.accepted_terms_user_agent, null);
});

Deno.test('the accepting address falls back past a missing x-forwarded-for (kyc once read only that header)', () => {
  const rq = (h: Record<string, string>) => new Request('https://x', { headers: h });
  assertEquals(clientIp(rq({ 'x-forwarded-for': '198.51.100.1, 10.0.0.1', 'cf-connecting-ip': '203.0.113.5' })), '198.51.100.1');
  assertEquals(clientIp(rq({ 'cf-connecting-ip': '203.0.113.5' })), '203.0.113.5');
  assertEquals(clientIp(rq({ 'x-real-ip': '192.0.2.7' })), '192.0.2.7');
  assertEquals(clientIp(rq({})), '');
});
