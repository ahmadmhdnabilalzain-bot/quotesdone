// deno test supabase/functions/customer_api/lib/quotation_for_backup.test.ts
// The Dropbox backup's quotation (ruling 1680): the portal's own renderer, into backups/generated/, only for a live quote.
import { assertEquals } from 'jsr:@std/assert@1';
import { quotationForBackup, type BackupQuoteDeps } from './quotation_for_backup.ts';

const ID = '7ca86d2e-5f34-401b-a42c-6b2d219721ce';
function deps(status: string, j: Record<string, unknown> = { ok: true, bucket: 'backups', path: 'generated/1_QD-151767-A-v2.3-quotation-en.pdf' }) {
  const seen: unknown[] = [];
  const d: BackupQuoteDeps = {
    load: () => Promise.resolve({ q: { id: ID, status }, inq: { id: 'i', rfq_no: 151767 } }),
    build: (_q, _i, lang, target) => { seen.push([lang, target]); return Promise.resolve({ j, ref: 'QD-151767-A' }); },
  };
  return { d, seen };
}

Deno.test('a live quote is rendered by the portal renderer into backups/generated/', async () => {
  const { d, seen } = deps('submitted');
  const r = await quotationForBackup(ID, 'en', d);
  assertEquals(r, { status: 200, body: { ok: true, bucket: 'backups', path: 'generated/1_QD-151767-A-v2.3-quotation-en.pdf', ref: 'QD-151767-A' } });
  assertEquals(seen, [['en', { bucket: 'backups', folder: 'generated' }]]);
});

Deno.test('a draft or a withdrawn quote is not the customer\'s: no document', async () => {
  for (const s of ['draft', 'withdrawn']) {
    const { d, seen } = deps(s);
    assertEquals((await quotationForBackup(ID, 'en', d)).status, 409);
    assertEquals(seen.length, 0);
  }
});

Deno.test('a renderer that held or failed gives no file and a retryable answer', async () => {
  const { d } = deps('submitted', { ok: false, error: 'reveal_rate_unread' });
  assertEquals(await quotationForBackup(ID, 'en', d), { status: 503, body: { error: 'reveal_rate_unread' } });
});

Deno.test('a malformed id is refused before anything is read', async () => {
  const { d } = deps('submitted');
  assertEquals((await quotationForBackup('x; drop', 'en', d)).status, 400);
});
