// THE HELD ARABIC COMPARISON REPORT REACHES THE CUSTOMER, ONCE (it_engineer, 27 Oct 2026; review of PR #1574).
//
// compare_pdf in Arabic answers 202 "held" when a line of the report has no Arabic yet: under the founder's model
// hold, or (PR #1574, run 0a717394 S09) when the request's 90 s budget is spent before every batch was reasoned.
// The missing lines are filed for the replay (fn_reason_hold, surface sales_engineer.document_arabic). Until this
// file, the replay stored their Arabic and NOTHING rendered the report or sent it: the customer had been told
// "it will be ready shortly" and had to come back and press the button again.
//
// Now the 202 also records a waiter (public.arabic_compare_waiter, keyed by the INQUIRY: the same lines may have been
// filed first by another document, and a held row keeps its first subject). When the replay stores Arabic,
// reasoned_delivery asks which waiters are complete (fn_arabic_compare_waiters_ready) and customer_api runs
// finishCompareArabic for each:
//   * render the report again. Every line is in the cache now, so no model is called; a line that is still missing
//     (the quote set changed since) is FILED, never reasoned here, and the waiter stays for the next replay;
//   * hand customer_support ONE delivery per channel (email; WhatsApp to the confirmed number), in Arabic, with the
//     report's link. The dedupe key is the waiter's own creation time, so a second run of the same waiter (two ticks,
//     a retry after a failed delete) returns the first request instead of sending again;
//   * delete the waiter. A customer who presses the button again and gets the report directly also clears it
//     (customer_api compare_pdf), so a report already in their hands is not sent to them a second time.
// A render that fails is counted; after MAX_ATTEMPTS the waiter stops being offered and the sales engineer is told.
//
// What this does NOT change: the English report (never held), and how a line is translated (reasoned_governance.ts).
// Prevented by: customer_api/compare_arabic.test.ts.

export const MAX_ATTEMPTS = 5;
// THE CLOCK (sales_engineer, 2 Nov 2026). A waiter whose lines never all got Arabic was never offered again, so the
// customer waited forever (3 waiters open, the oldest 16 h, 0 reports sent in 14 days). The replay now offers a
// waiter at least hourly from its first hour (fn_arabic_compare_waiters_ready): each render re-files what is still
// missing (deduplicated) for the sales engineer's reasoning queue, and a report still waiting at OVERDUE_HOURS is put in
// the sales engineer's queue ONCE with its hours. It is never sent half-translated (founder, 14 Sep: Arabic throughout).
export const OVERDUE_HOURS = 6;

export type Waiter = { inquiry_id: string; created_at: string; attempts: number };
export type CompareInquiry = { id: string; rfq_no?: string | null; customer_id: string };
export type Rendered = { held: true } | { url: string; ref: string } | { error: string };
export type Customer = { email: string | null };

export interface CompareFinishIO {
  waiter(inquiryId: string): Promise<Waiter | null>;
  inquiry(inquiryId: string): Promise<CompareInquiry | null>;
  customer(customerId: string): Promise<Customer | null>;
  /** Render the Arabic comparison report with what is cached; never reason a line (file it instead). */
  render(inq: CompareInquiry): Promise<Rendered>;
  deliver(rows: Record<string, unknown>[]): Promise<{ ok: boolean; err?: string }>;
  done(inquiryId: string): Promise<void>;
  tried(inquiryId: string, attempts: number): Promise<void>;
  tellSalesEngineer(inquiryId: string, last: unknown): Promise<void>;
  /** The report has waited OVERDUE_HOURS or more: one item in the sales engineer's queue (idempotent per inquiry). */
  overdue(inquiryId: string, hours: number): Promise<void>;
}

export type FinishResult =
  | { ok: true; ref: string; sent: number }
  | { ok: false; code: 'no_waiter' | 'not_found' | 'still_pending' | 'render_failed' | 'delivery_failed' | 'no_contact'; detail?: string };

/** The notice the customer gets, in Arabic: the report is ready, here it is, and where it lives in the portal. */
export function compareReadyNotice(ref: string, url: string): { subject: string; body: string } {
  return {
    subject: `تقرير مقارنة العروض جاهز باللغة العربية (${ref})`,
    body: [
      'تحية طيبة وبعد،',
      '',
      'أصبحت النسخة العربية من تقرير مقارنة العروض لطلبكم جاهزة.',
      `يمكنكم فتحها من هنا: ${url}`,
      '',
      'يبقى الرابط صالحًا لمدة سبعة أيام، والتقرير متاح دائمًا في بوابتكم من صفحة الطلب.',
      '',
      'مع أطيب التحيات،',
      'فريق QuotesDone',
    ].join('\n'),
  };
}

export async function finishCompareArabic(io: CompareFinishIO, inquiryId: string, now: number = Date.now()): Promise<FinishResult> {
  const w = await io.waiter(inquiryId);
  if (!w) return { ok: false, code: 'no_waiter' };          // already delivered, or already in the customer's hands
  const inq = await io.inquiry(inquiryId);
  if (!inq) { await io.done(inquiryId); return { ok: false, code: 'not_found' }; }
  const cust = await io.customer(inq.customer_id);
  if (!cust?.email) { await io.done(inquiryId); return { ok: false, code: 'no_contact' }; }

  let out: Rendered;
  try { out = await io.render(inq); } catch (e) { out = { error: String((e as Error)?.message || e).slice(0, 200) }; }
  if ('held' in out) {   // a line is still missing: it was filed again; wait, and past the clock the sales engineer owns it
    const hours = (now - Date.parse(w.created_at)) / 36e5;
    if (hours >= OVERDUE_HOURS) await io.overdue(inquiryId, Math.floor(hours));
    return { ok: false, code: 'still_pending' };
  }
  if ('error' in out) {
    const attempts = w.attempts + 1;
    await io.tried(inquiryId, attempts);
    if (attempts >= MAX_ATTEMPTS) await io.tellSalesEngineer(inquiryId, out);
    return { ok: false, code: 'render_failed', detail: out.error };
  }

  const n = compareReadyNotice(out.ref, out.url);
  const key = `compare_ar:${inquiryId}:${Date.parse(w.created_at) || w.created_at}`;
  const base = { type: 'compare_report_ar', kind: 'customer_support_compare_report_ar', to_role: 'customer', inquiry_id: inquiryId,
    subject: n.subject, body: n.body, status: 'queued', lang: 'ar', requested_by: 'customer_support', sender: 'customer_support' };
  // WhatsApp consent is the confirmed WhatsApp number, nothing else (#322): the row names the customer by email and the
  // a03 trigger addresses it to their confirmed number, or records why it was not sent.
  const rows = [
    { ...base, channel: 'email', to_email: cust.email, dedupe_key: key + ':email' },
    { ...base, channel: 'whatsapp', to_email: cust.email, dedupe_key: key + ':whatsapp' },
  ];
  const sent = await io.deliver(rows);
  if (!sent.ok) {
    const attempts = w.attempts + 1;
    await io.tried(inquiryId, attempts);
    if (attempts >= MAX_ATTEMPTS) await io.tellSalesEngineer(inquiryId, { delivery: sent.err });
    return { ok: false, code: 'delivery_failed', detail: sent.err };
  }
  await io.done(inquiryId);
  return { ok: true, ref: out.ref, sent: rows.length };
}
