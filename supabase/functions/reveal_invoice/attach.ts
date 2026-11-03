// THE INVOICE TRAVELS WITH "YOUR INVOICE IS READY" (customer_support, 3 Nov 2026). Founder, 3 Nov 2026: after a customer
// pays the reveal fee "an invoice from our app is shared on email and whatsapp with the customer".
//
// Measured on production before this: a paid reveal sends reveal_receipt (the reveal.paid handoff) and, once
// stripe_webhook's captureInvoice files the Stripe invoice, invoice_ready (the invoice.issued handoff, "Your invoice is
// ready"). Neither carried the invoice; invoice_ready only said it was in the account, and its WhatsApp twin had no
// template mapping. The QuotesDone invoice existed only when the customer pressed "Invoice" in the portal.
//
// Now a08_invoice_ready_waits_for_its_invoice holds both invoice_ready rows for ten minutes and
// z30_invoice_ready_asks_for_its_invoice asks this function (action 'attach') to render the invoice in the notice's
// language. attachInvoice() attaches the PDF reference to the email row (send_outbox attaches the file), says so in its
// body, puts the same reference on each WhatsApp twin (send_whatsapp signs a short-lived link when it sends: no link is
// stored) and releases them. Each update must land on a row that is still waiting, or it counts as a failure. If anything
// fails, nothing is claimed: the rows go at the end of the hold as the plain notice, and the failure is logged.
// invoice_ready is the carrier, not reveal_receipt: it exists exactly when the Stripe invoice number is known.
// prevented by: reveal_invoice/attach.test.ts
export type Lang = 'en' | 'ar';
export type NoticeRow = { id: number; channel: string | null; lang: string | null; body: string | null; attachments: unknown };
export type Rendered = { bucket: string; path: string; invoice_no: string | null; ref: string };
export type AttachDeps = {
  /** invoice_ready rows to the customer for this quote that are still waiting (queued or pending; email and WhatsApp). */
  notices: (quoteId: string) => Promise<NoticeRow[] | { error: string }>;
  render: (lang: Lang) => Promise<Rendered | { error: string }>;
  /** Updates one row only while it is still waiting; returns an error message, or null when exactly that row changed. */
  update: (id: number, patch: Record<string, unknown>) => Promise<string | null>;
};
export type AttachResult = { ok: boolean; outcome: string; email_id?: number; whatsapp_ids?: number[] };

export const isEmail = (r: NoticeRow) => !r.channel || (r.channel !== 'whatsapp' && r.channel !== 'sms');
const attached = (a: unknown) => Array.isArray(a) && a.length > 0;

/** send_outbox and a20_notifications_attachment_policy accept only letters, digits, space, dot, underscore and hyphen. */
export function invoiceFilename(ref: string): string {
  const safe = String(ref || '').replace(/[^A-Za-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 80);
  return 'QuotesDone-invoice' + (safe ? '-' + safe : '') + '.pdf';
}
export function emailInvoiceLine(lang: Lang, invoiceNo: string | null): string {
  const no = invoiceNo ? ' ' + invoiceNo : '';
  return lang === 'ar'
    ? 'أرفقنا بهذه الرسالة فاتورة QuotesDone' + (no ? ' رقم' + no : '') + ' عن هذه الدفعة، ويمكنكم تنزيلها في أي وقت من صفحة الطلب في حسابكم.'
    : 'Your QuotesDone invoice' + no + ' for this payment is attached to this e-mail. You can also download it at any time from the request in your account.';
}

export async function attachInvoice(deps: AttachDeps, quoteId: string): Promise<AttachResult> {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(quoteId || ''))) return { ok: false, outcome: 'bad_quote_id' };
  const rows = await deps.notices(quoteId);
  if (!Array.isArray(rows)) return { ok: false, outcome: 'notices_unreadable: ' + rows.error };
  const email = rows.find(isEmail);
  if (!email) return { ok: false, outcome: 'no_notice_waiting' };
  if (attached(email.attachments)) return { ok: true, outcome: 'already_attached', email_id: email.id };
  const lang: Lang = email.lang === 'ar' ? 'ar' : 'en';
  const doc = await deps.render(lang);
  if ('error' in doc) return { ok: false, outcome: 'render_failed: ' + doc.error, email_id: email.id };
  const ref = [{ bucket: doc.bucket, path: doc.path, filename: invoiceFilename(doc.ref) }];
  const err = await deps.update(email.id, {
    attachments: ref,
    body: String(email.body || '').trimEnd() + '\n\n' + emailInvoiceLine(lang, doc.invoice_no),
    not_before: null,
  });
  if (err) return { ok: false, outcome: 'email_not_updated: ' + err, email_id: email.id };
  const wa: number[] = []; const missed: string[] = [];
  for (const r of rows.filter((x) => x.channel === 'whatsapp')) {
    const e = await deps.update(r.id, attached(r.attachments) ? { not_before: null } : { attachments: ref, not_before: null });
    if (e) missed.push(r.id + ': ' + e); else wa.push(r.id);
  }
  if (missed.length) return { ok: false, outcome: 'whatsapp_not_updated: ' + missed.join('; '), email_id: email.id, whatsapp_ids: wa };
  return { ok: true, outcome: 'attached', email_id: email.id, whatsapp_ids: wa };
}
