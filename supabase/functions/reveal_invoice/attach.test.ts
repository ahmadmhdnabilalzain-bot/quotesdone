// deno test supabase/functions/reveal_invoice/attach.test.ts
// 3 Nov 2026 (customer_support): the reveal receipt carries the QuotesDone invoice on email (the PDF) and WhatsApp (its link).
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { attachInvoice, emailInvoiceLine, invoiceFilename, type AttachDeps, type ReceiptRow } from './attach.ts';

const QID = '0b9b1c7e-0000-4000-8000-0000000000aa';
const URL_ = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/sign/agent-docs/reveal_invoice/aa/1_invoice.pdf?token=zz';

function store(rows: ReceiptRow[], over: Partial<AttachDeps> = {}) {
  const patches: Record<number, Record<string, unknown>> = {};
  const deps: AttachDeps = {
    receipts: async () => rows,
    render: async () => ({ bucket: 'agent-docs', path: 'reveal_invoice/aa/1_invoice.pdf', invoice_no: 'ZZDEMO-0001', ref: 'ZZDEMO-0001' }),
    signedUrl: async () => URL_,
    update: async (id, p) => { patches[id] = p; return null; },
    ...over,
  };
  return { deps, patches };
}
const email = (o: Partial<ReceiptRow> = {}): ReceiptRow => ({ id: 1, channel: 'email', lang: 'en', body: 'You have unlocked ZZ DEMO Works.', attachments: null, ...o });
const wa = (o: Partial<ReceiptRow> = {}): ReceiptRow => ({ id: 2, channel: 'whatsapp', lang: 'en', body: 'You have unlocked ZZ DEMO Works.', attachments: null, ...o });

Deno.test('the invoice is attached to the email, named on its body, linked on WhatsApp, and both are released', async () => {
  const { deps, patches } = store([email(), wa()]);
  const out = await attachInvoice(deps, QID);
  assertEquals(out.outcome, 'attached');
  assertEquals(patches[1].attachments, [{ bucket: 'agent-docs', path: 'reveal_invoice/aa/1_invoice.pdf', filename: 'QuotesDone-invoice-ZZDEMO-0001.pdf' }]);
  assertMatch(String(patches[1].body), /You have unlocked ZZ DEMO Works\.\n\nYour QuotesDone invoice ZZDEMO-0001 for this payment is attached/);
  assertEquals(patches[1].not_before, null);
  assertEquals(patches[2].body, 'You have unlocked ZZ DEMO Works.\n\nYour invoice: ' + URL_);
  assertEquals(patches[2].not_before, null);
});

Deno.test('an Arabic receipt gets the Arabic invoice and Arabic lines', async () => {
  let asked = '';
  const { deps, patches } = store([email({ lang: 'ar', body: 'أصبحت بيانات التواصل متاحة.' }), wa({ lang: 'ar', body: 'أصبحت بيانات التواصل متاحة.' })],
    { render: async (l) => { asked = l; return { bucket: 'agent-docs', path: 'p.pdf', invoice_no: null, ref: 'pi_zzdemo' }; } });
  await attachInvoice(deps, QID);
  assertEquals(asked, 'ar');
  assert(String(patches[1].body).endsWith(emailInvoiceLine('ar', null)));
  assertMatch(String(patches[2].body), /فاتورتكم: https:/);
});

Deno.test('KNOWN-BAD control: a failed render claims nothing and leaves the rows to go at the end of their hold', async () => {
  const { deps, patches } = store([email(), wa()], { render: async () => ({ error: 'pdf_failed' }) });
  const out = await attachInvoice(deps, QID);
  assertEquals(out.ok, false);
  assertMatch(out.outcome, /^render_failed/);
  assertEquals(Object.keys(patches).length, 0);
});

Deno.test('KNOWN-BAD control: a second call attaches nothing twice', async () => {
  const { deps, patches } = store([email({ attachments: [{ bucket: 'agent-docs', path: 'p', filename: 'f.pdf' }] }), wa()]);
  const out = await attachInvoice(deps, QID);
  assertEquals(out.outcome, 'already_attached');
  assertEquals(Object.keys(patches).length, 0);
});

Deno.test('no link, no WhatsApp line: the twin is only released', async () => {
  const { deps, patches } = store([email(), wa()], { signedUrl: async () => null });
  const out = await attachInvoice(deps, QID);
  assertEquals(out.outcome, 'attached_without_link');
  assertEquals(patches[2], { not_before: null });
});

Deno.test('nothing waiting, an unreadable queue or a bad id answer a reason', async () => {
  assertEquals((await attachInvoice(store([wa()]).deps, QID)).outcome, 'no_receipt_waiting');
  assertMatch((await attachInvoice(store([], { receipts: async () => ({ error: 'down' }) }).deps, QID)).outcome, /^receipts_unreadable/);
  assertEquals((await attachInvoice(store([email()]).deps, "x' or 1=1")).outcome, 'bad_quote_id');
});

Deno.test('the file name passes send_outbox and the attachment policy', () => {
  for (const ref of ['ZZDEMO-0001', 'pi_3QzZ/../x', '', 'in_1 2 3']) assertMatch(invoiceFilename(ref), /^[A-Za-z0-9 ._-]{1,120}$/);
  assertEquals(invoiceFilename('pi_3QzZ/../x'), 'QuotesDone-invoice-pi_3QzZ-..-x.pdf');
});
