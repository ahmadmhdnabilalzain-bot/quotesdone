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

// 2 Nov 2026 (ceo; ledger 1482): v17 changed the contact line only, so a v16 acceptance stands and nobody signs again.
import { acceptanceStands, supplierAcceptanceStands, supplierTermsCarriedFrom } from './supplier_terms.ts';

Deno.test('a version the current text carries counts as accepted; any other older version does not', () => {
  assertEquals(acceptanceStands('v16', 'v17', ['v16']), true, 'v16 -> v17 is contact-only');
  assertEquals(acceptanceStands('v17', 'v17', ['v16']), true);
  assertEquals(acceptanceStands('v15', 'v17', ['v16']), false, 'v15 never saw the v16 changes: asked once');
  assertEquals(acceptanceStands('v16', 'v17', []), false, 'a material version publishes an empty list and everyone is asked');
  assertEquals(acceptanceStands(null, 'v17', ['v16']), false, 'nothing accepted is never accepted');
  assertEquals(acceptanceStands('v16', '', ['v16']), false);
});

Deno.test('the carried list is read from app_secrets, trimmed, and absent means empty', async () => {
  const s = (v: string | null) => (k: string) => Promise.resolve(k === 'supplier_terms_carries_from' ? v : k === 'supplier_terms_version' ? 'v17' : null);
  assertEquals(await supplierTermsCarriedFrom(s(' v16 , v15 ')), ['v16', 'v15']);
  assertEquals(await supplierTermsCarriedFrom(s(null)), []);
  assertEquals(await supplierAcceptanceStands(s('v16'), 'v16'), true);
  assertEquals(await supplierAcceptanceStands(s(null), 'v16'), false);
});
