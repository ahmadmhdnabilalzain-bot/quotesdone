// deno test supabase/functions/reveal_invoice/attach.test.ts
// 3 Nov 2026 (customer_support): "Your invoice is ready" carries the QuotesDone invoice on email (the PDF) and WhatsApp
// (the same PDF reference, signed by send_whatsapp as it sends).
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { attachInvoice, emailInvoiceLine, invoiceFilename, type AttachDeps, type NoticeRow } from './attach.ts';

const QID = '0b9b1c7e-0000-4000-8000-0000000000aa';
const PATH = 'reveal_invoice/0b9b1c7e/1730000000000_invoice-ZZDEMO-0001-en-t2.pdf';
const REF = [{ bucket: 'agent-docs', path: PATH, filename: 'QuotesDone-invoice-ZZDEMO-0001.pdf' }];

function store(rows: NoticeRow[], over: Partial<AttachDeps> = {}) {
  const patches: Record<number, Record<string, unknown>> = {};
  const deps: AttachDeps = {
    notices: async () => rows,
    render: async () => ({ bucket: 'agent-docs', path: PATH, invoice_no: 'ZZDEMO-0001', ref: 'ZZDEMO-0001' }),
    update: async (id, p) => { patches[id] = p; return null; },
    ...over,
  };
  return { deps, patches };
}
const email = (o: Partial<NoticeRow> = {}): NoticeRow => ({ id: 1, channel: null, lang: 'en', body: 'The invoice for the reveal fee you paid is now in your QuotesDone account.', attachments: null, ...o });
const wa = (o: Partial<NoticeRow> = {}): NoticeRow => ({ id: 2, channel: 'whatsapp', lang: 'en', body: 'The invoice for the reveal fee you paid is now in your QuotesDone account.', attachments: null, ...o });

Deno.test('the invoice is attached to the email and named on its body, referenced on WhatsApp, and both are released', async () => {
  const { deps, patches } = store([email(), wa()]);
  const out = await attachInvoice(deps, QID);
  assertEquals(out.outcome, 'attached');
  assertEquals(patches[1].attachments, REF);
  assertMatch(String(patches[1].body), /in your QuotesDone account\.\n\nYour QuotesDone invoice ZZDEMO-0001 for this payment is attached/);
  assertEquals(patches[1].not_before, null);
  // the twin carries the reference, never a link in its body
  assertEquals(patches[2], { attachments: REF, not_before: null });
});

Deno.test('an Arabic notice gets the Arabic invoice and the Arabic line', async () => {
  let asked = '';
  const { deps, patches } = store([email({ lang: 'ar', body: 'أصبحت فاتورة رسوم الكشف متاحة في حسابكم.' })],
    { render: async (l) => { asked = l; return { bucket: 'agent-docs', path: PATH, invoice_no: null, ref: 'pi_zzdemo' }; } });
  await attachInvoice(deps, QID);
  assertEquals(asked, 'ar');
  assert(String(patches[1].body).endsWith(emailInvoiceLine('ar', null)));
});

Deno.test('KNOWN-BAD control: a failed render claims nothing and leaves the rows to go at the end of their hold', async () => {
  const { deps, patches } = store([email(), wa()], { render: async () => ({ error: 'pdf_failed' }) });
  const out = await attachInvoice(deps, QID);
  assertEquals(out.ok, false);
  assertMatch(out.outcome, /^render_failed/);
  assertEquals(Object.keys(patches).length, 0);
});

Deno.test('KNOWN-BAD control: a row that left the queue is a failure, not "attached"', async () => {
  const gone = store([email(), wa()], { update: async (id) => (id === 1 ? 'row_no_longer_waiting' : null) });
  assertEquals((await attachInvoice(gone.deps, QID)).outcome, 'email_not_updated: row_no_longer_waiting');
  const twinGone = store([email(), wa()], { update: async (id) => (id === 2 ? 'row_no_longer_waiting' : null) });
  const out = await attachInvoice(twinGone.deps, QID);
  assertEquals(out.ok, false);
  assertMatch(out.outcome, /^whatsapp_not_updated: 2: row_no_longer_waiting/);
});

Deno.test('KNOWN-BAD control: a second call attaches nothing twice', async () => {
  const { deps, patches } = store([email({ attachments: REF }), wa()]);
  const out = await attachInvoice(deps, QID);
  assertEquals(out.outcome, 'already_attached');
  assertEquals(Object.keys(patches).length, 0);
});

Deno.test('nothing waiting, an unreadable queue or a bad id answer a reason', async () => {
  assertEquals((await attachInvoice(store([wa()]).deps, QID)).outcome, 'no_notice_waiting');
  assertMatch((await attachInvoice(store([], { notices: async () => ({ error: 'down' }) }).deps, QID)).outcome, /^notices_unreadable/);
  assertEquals((await attachInvoice(store([email()]).deps, "x' or 1=1")).outcome, 'bad_quote_id');
  assertEquals((await attachInvoice(store([email()]).deps, '0b9b1c7e-0000-4000-8000-0000000000aa-')).outcome, 'bad_quote_id');
});

Deno.test('the file name passes send_outbox and the attachment policy', () => {
  for (const ref of ['ZZDEMO-0001', 'pi_3QzZ/../x', '', 'in_1 2 3']) assertMatch(invoiceFilename(ref), /^[A-Za-z0-9 ._-]{1,120}$/);
  assertEquals(invoiceFilename('pi_3QzZ/../x'), 'QuotesDone-invoice-pi_3QzZ-x.pdf');
});
