// customer_api job_problem — "A problem with this job" on a revealed supplier (customer_support, 16 Nov 2026, agent AFTER_REVEAL;
// holes CUSTOMER.md items 3 and 4). The portal's only door on a revealed job was request_refund, which always files "the supplier did
// not respond", so "he raised the price", "he never came back", "the waterproofing leaks" were judged on the wrong question and
// declined, and the dispute machine (fn_customer_support_dispute_consider / _open) had no caller at all.
//
// This is the portal's side of the ONE door every channel shares (public.fn_customer_after_reveal_message; WhatsApp and the widget
// call the same routine). Code here checks only what must be exact: the quote is his, the sale is revealed, the message is words of
// a sane length. WHAT he wrote is read by the model in the dispute intake, beside the revealed quotation the supplier is bound by
// (price, scope, warranty): the supplier contacted him, did not (the refund door), a dispute that needs a case, or nothing for a case.
// prevented by: ./job_problem.test.ts
export const MIN_WORDS_CHARS = 10;
export const MAX_CHARS = 4000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type JobProblemIO = {
  /** The sale behind a quote: its id and whose it is (transactions, by quote_id). */
  saleOfQuote: (quoteId: string) => Promise<{ id: string; customer_id: string; revealed_at: string | null } | null>;
  /** public.fn_customer_after_reveal_message, the one door. */
  door: (args: { p_customer: string; p_message: string; p_channel: 'portal'; p_transaction: string }) =>
    Promise<{ data: Record<string, unknown> | null; error: { message: string } | null }>;
};

export type JobProblemAnswer = { status: number; body: Record<string, unknown> };

export async function jobProblem(io: JobProblemIO, customerId: string, body: Record<string, unknown>): Promise<JobProblemAnswer> {
  const quoteId = String(body?.quote_id ?? '').trim();
  if (!UUID.test(quoteId)) return { status: 400, body: { ok: false, code: 'quote_id_required' } };
  const message = String(body?.message ?? '').trim().slice(0, MAX_CHARS);
  if (message.length < MIN_WORDS_CHARS) return { status: 400, body: { ok: false, code: 'message_too_short', min: MIN_WORDS_CHARS } };
  const sale = await io.saleOfQuote(quoteId);
  if (!sale || sale.customer_id !== customerId) return { status: 404, body: { ok: false, code: 'not_your_revealed_job' } };
  if (!sale.revealed_at) return { status: 400, body: { ok: false, code: 'not_revealed' } };
  const { data, error } = await io.door({ p_customer: customerId, p_message: message, p_channel: 'portal', p_transaction: sale.id });
  if (error || !data) return { status: 500, body: { ok: false, code: 'job_problem_failed', detail: error?.message ?? 'no answer' } };
  const msg = data.locale === 'ar' ? (data.message_ar ?? data.message_en) : data.message_en;
  if (data.ok !== true) return { status: 400, body: { ok: false, code: data.code ?? 'not_opened', message: msg } };
  return { status: 200, body: { ok: true, rfq_no: data.rfq_no ?? null, open_case: data.open_dispute ?? data.open_refund ?? null, message: msg } };
}
