// deno test supabase/functions/customer_api/lib/quotation_for_backup.test.ts
// The Dropbox backup's quotation (ruling 1680): the portal's own renderer, into backups/generated/, only for a live quote; the
// supplier's copy carries the request as the supplier inbox shows it before a reveal; the backup credential opens only this door.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { DOOR_SCOPES, quotationForBackup, scopeOpens, supplierSafeRequest, type BackupQuoteDeps } from './quotation_for_backup.ts';
import { quoteDocument } from '../../_shared/quote_documents.ts';

const ID = '7ca86d2e-5f34-401b-a42c-6b2d219721ce';
// A made-up customer: none of this is a real person, company, number or address.
const BUYER = { full_name: 'Khalid Zarooni', email: 'khalid.zarooni@marsaheights.example', phone: '+971501234567', project: 'Marsa Heights Villas' };
const SUMMARY = 'Hi, I am Khalid Zarooni of Zarooni Holdings LLC. Repaint 3 villas at Marsa Heights Villas, Dubai. Call me on 050 123 4567 or '
  + 'khalid.zarooni@marsaheights.example, or see www.zaroonigroup.example.';
const LEAKS = ['Khalid', 'Zarooni', '123 4567', '1234567', 'marsaheights', 'Marsa Heights', 'zaroonigroup'];
const INQ = { id: '11111111-2222-3333-4444-555555555555', rfq_no: 151767, category: 'painting', emirate: 'Dubai', summary: SUMMARY,
  spec: { site: 'Marsa Heights Villas, villa 7' }, boq: { boq: [{ description: 'Repaint villa 7 for Khalid Zarooni', qty: 3, unit: 'nos' }] } };

function deps(status: string, over: Partial<{ revealed: boolean; buyer: typeof BUYER | null }> = {}, j: Record<string, unknown> = { ok: true, bucket: 'backups', path: 'generated/1_QD-151767-A-v2.3-quotation-en.pdf' }) {
  // deno-lint-ignore no-explicit-any
  const seen: { inq: Record<string, any>; target: Record<string, unknown> }[] = [];
  const d: BackupQuoteDeps = {
    load: () => Promise.resolve({ q: { id: ID, status }, inq: INQ, buyer: over.buyer === undefined ? BUYER : over.buyer, revealed: !!over.revealed }),
    build: (_q, inq, _lang, target) => { seen.push({ inq, target }); return Promise.resolve({ j, ref: 'QD-151767-A' }); },
  };
  return { d, seen };
}

Deno.test('a live quote is rendered by the portal renderer into backups/generated/', async () => {
  const { d, seen } = deps('submitted');
  const r = await quotationForBackup(ID, 'en', d);
  assertEquals(r, { status: 200, body: { ok: true, bucket: 'backups', path: 'generated/1_QD-151767-A-v2.3-quotation-en.pdf', ref: 'QD-151767-A', side: 'supplier' } });
  assertEquals([seen[0].target.bucket, seen[0].target.folder], ['backups', 'generated']);
});

Deno.test('a draft or a withdrawn quote is not the customer\'s: no document', async () => {
  for (const s of ['draft', 'withdrawn']) {
    const { d, seen } = deps(s);
    assertEquals((await quotationForBackup(ID, 'en', d)).status, 409);
    assertEquals(seen.length, 0);
  }
});

Deno.test('a renderer that held or failed gives no file and a retryable answer', async () => {
  const { d } = deps('submitted', {}, { ok: false, error: 'reveal_rate_unread' });
  assertEquals(await quotationForBackup(ID, 'en', d), { status: 503, body: { error: 'reveal_rate_unread' } });
});

Deno.test('a malformed id is refused before anything is read', async () => {
  const { d } = deps('submitted');
  assertEquals((await quotationForBackup('x; drop', 'en', d)).status, 400);
});

Deno.test('ANONYMITY: the supplier\'s filed quotation carries none of the customer\'s name, phone, e-mail, web address or project', async () => {
  const { d, seen } = deps('submitted');
  await quotationForBackup(ID, 'en', d, 'supplier');
  const { inq, target } = seen[0];
  // the request text the renderer prints and checks against is the gated one, nothing read back from the table
  assertEquals(target.request, { summary: inq.summary, spec: inq.spec, boq: inq.boq });
  // the document itself, as pdf_native receives it (the PDF's text is drawn from exactly this body)
  const { body } = quoteDocument({ quote: { id: ID, quote_amount: 12000, status: 'submitted', scope: 'Repaint as requested' } as never, inquiry: inq as never,
    items: [{ desc: 'Painting works', qty: '3', unit: 'nos', price: 4000, amount: 12000 } as never], letter: 'A', lang: 'en', revealRate: 0.03 });
  const text = JSON.stringify(body);
  for (const leak of LEAKS) assert(!text.toLowerCase().includes(leak.toLowerCase()), `the supplier's copy carries "${leak}"`);
  // and the same document from the UNGATED request does carry them: the assertion above is not vacuous
  const raw = JSON.stringify(quoteDocument({ quote: { id: ID, quote_amount: 12000, status: 'submitted', scope: 'Repaint as requested' } as never, inquiry: INQ as never,
    items: [], letter: 'A', lang: 'en', revealRate: 0.03 }).body);
  // (measured: the customer's own page already hides his self-introduction and contacts, but prints the PROJECT name; the gate is what
  // takes it off the supplier's copy)
  assert(raw.includes('Marsa Heights'), 'the ungated page carries the project name');
});

Deno.test('the customer\'s own copy, and a revealed quote, keep his words; a buyer we could not read withholds them all', async () => {
  const c = deps('submitted'); await quotationForBackup(ID, 'en', c.d, 'customer');
  assertEquals([c.seen[0].inq.summary, c.seen[0].target.request], [SUMMARY, undefined]);
  const r = deps('revealed', { revealed: true }); await quotationForBackup(ID, 'en', r.d, 'supplier');
  assertEquals(r.seen[0].inq.summary, SUMMARY);
  const u = supplierSafeRequest(INQ, null);
  assertEquals([u.inq.summary, u.inq.spec, u.inq.boq, u.withheld.length], [null, null, null, 3]);
});

Deno.test('the backup credential opens the backup door and NEITHER of the other two internal doors', () => {
  const backup = ['pdf_native', 'customer_api.quotation_for_backup'];
  assert(scopeOpens(backup, 'quotation_for_backup'));
  assert(!scopeOpens(backup, 'compare_arabic_finish'), 'the backup credential must not send a customer his comparison report');
  assert(!scopeOpens(backup, 'rematch_waiting'), 'the backup credential must not e-mail suppliers');
  assertEquals(DOOR_SCOPES.compare_arabic_finish, 'customer_api');
});

Deno.test('the backup door checks its door-only scope, and the other two doors keep the function-wide one', async () => {
  const src = await Deno.readTextFile(new URL('../index.ts', import.meta.url));
  assert(/peek\.action === 'quotation_for_backup'\) \{\n\s+const ok = await requireInternal\(admin, String\(peek\.__secret\), DOOR_SCOPES\.quotation_for_backup\);/.test(src));
  for (const door of ['compare_arabic_finish', 'rematch_waiting']) {
    assert(new RegExp(`peek\\.action === '${door}'\\) \\{\\n\\s+const ok = await requireInternal\\(admin, String\\(peek\\.__secret\\), '${DOOR_SCOPES[door as 'rematch_waiting']}'\\);`).test(src), door);
  }
});
