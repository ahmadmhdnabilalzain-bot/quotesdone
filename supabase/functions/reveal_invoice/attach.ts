// THE INVOICE TRAVELS WITH THE RECEIPT (customer_support, 3 Nov 2026). Founder, 3 Nov 2026: after a customer pays the reveal
// fee "an invoice from our app is shared on email and whatsapp with the customer".
//
// Measured on production before this: the reveal receipt (fn_sales_engineer_acts_on_handoff, reveal.paid) carried no
// attachment and no link, and its WhatsApp twin used customer_supplier_unlocked, whose {{2}} is the account page. The
// QuotesDone invoice existed only when the customer pressed "Invoice" in the portal (this function, signed-in path).
//
// Now a08_reveal_receipt_waits_for_its_invoice holds both receipt rows for ten minutes and z30_reveal_receipt_asks_for_its_invoice
// asks this function (action 'attach') to render the invoice in the receipt's language. attachInvoice() then attaches the
// PDF to the email row, says so in its body, puts the signed link on each WhatsApp twin and releases them. If anything
// fails, nothing is claimed: the rows go at the end of the hold as the plain receipt, and the failure is logged.
// prevented by: reveal_invoice/attach.test.ts
export type Lang = 'en' | 'ar';
export type ReceiptRow = { id: number; channel: string | null; lang: string | null; body: string | null; attachments: unknown };
export type Rendered = { bucket: string; path: string; invoice_no: string | null; ref: string };
export type AttachDeps = {
  /** reveal_receipt rows to the customer for this quote that are still queued (email and WhatsApp). */
  receipts: (quoteId: string) => Promise<ReceiptRow[] | { error: string }>;
  render: (lang: Lang) => Promise<Rendered | { error: string }>;
  signedUrl: (bucket: string, path: string) => Promise<string | null>;
  /** Updates one row only while it is still queued; returns an error message, or null. */
  update: (id: number, patch: Record<string, unknown>) => Promise<string | null>;
};
export type AttachResult = { ok: boolean; outcome: string; email_id?: number; whatsapp_ids?: number[] };

const SIGNED_MARK = '/storage/v1/object/sign/';
export const isEmail = (r: ReceiptRow) => !r.channel || (r.channel !== 'whatsapp' && r.channel !== 'sms');
const attached = (a: unknown) => Array.isArray(a) && a.length > 0;

/** send_outbox and a20_notifications_attachment_policy accept only letters, digits, space, dot, underscore and hyphen. */
export function invoiceFilename(ref: string): string {
  const safe = String(ref || '').replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 80);
  return 'QuotesDone-invoice' + (safe ? '-' + safe : '') + '.pdf';
}
export function emailInvoiceLine(lang: Lang, invoiceNo: string | null): string {
  const no = invoiceNo ? ' ' + invoiceNo : '';
  return lang === 'ar'
    ? 'أرفقنا بهذه الرسالة فاتورة QuotesDone' + (no ? ' رقم' + no : '') + ' عن هذه الدفعة، ويمكنكم تنزيلها في أي وقت من صفحة الطلب في حسابكم.'
    : 'Your QuotesDone invoice' + no + ' for this payment is attached to this e-mail. You can also download it at any time from the request in your account.';
}
export function waInvoiceLine(lang: Lang, url: string): string {
  return (lang === 'ar' ? 'فاتورتكم: ' : 'Your invoice: ') + url;
}

export async function attachInvoice(deps: AttachDeps, quoteId: string): Promise<AttachResult> {
  if (!/^[0-9a-f-]{36}$/i.test(String(quoteId || ''))) return { ok: false, outcome: 'bad_quote_id' };
  const rows = await deps.receipts(quoteId);
  if (!Array.isArray(rows)) return { ok: false, outcome: 'receipts_unreadable: ' + rows.error };
  const email = rows.find(isEmail);
  if (!email) return { ok: false, outcome: 'no_receipt_waiting' };
  if (attached(email.attachments)) return { ok: true, outcome: 'already_attached', email_id: email.id };
  const lang: Lang = email.lang === 'ar' ? 'ar' : 'en';
  const doc = await deps.render(lang);
  if ('error' in doc) return { ok: false, outcome: 'render_failed: ' + doc.error, email_id: email.id };
  const err = await deps.update(email.id, {
    attachments: [{ bucket: doc.bucket, path: doc.path, filename: invoiceFilename(doc.ref) }],
    body: String(email.body || '').trimEnd() + '\n\n' + emailInvoiceLine(lang, doc.invoice_no),
    not_before: null,
  });
  if (err) return { ok: false, outcome: 'email_not_updated: ' + err, email_id: email.id };
  const url = await deps.signedUrl(doc.bucket, doc.path);
  const wa: number[] = [];
  for (const r of rows.filter((x) => x.channel === 'whatsapp')) {
    const has = String(r.body || '').includes(SIGNED_MARK);
    const patch: Record<string, unknown> = { not_before: null };
    if (url && !has) patch.body = String(r.body || '').trimEnd() + '\n\n' + waInvoiceLine(r.lang === 'ar' ? 'ar' : 'en', url);
    if (!(await deps.update(r.id, patch))) wa.push(r.id);
  }
  return { ok: true, outcome: url ? 'attached' : 'attached_without_link', email_id: email.id, whatsapp_ids: wa };
}
