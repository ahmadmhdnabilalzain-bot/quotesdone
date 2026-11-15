// supplier_api — the accept rule, the quality hold and acceptLive, and telling the customer of a new quote.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { SUPPLIER_LOCALE } from '../../_shared/registered_locale.ts';
import type { MissingItem } from '../../_shared/line_specs/assess.ts';
import { requestDelivery } from '../../_shared/deliver.ts';
import { SUPA_URL, admin, secretVal, tellItSeat } from '../context.ts';
import { writeRecorded } from '../../_shared/recorded_write.ts';
import { maskContact } from '../../_shared/observe.ts';
import { requestOf, reviewNotes } from '../../_shared/quote_review_notes.ts';

export async function notify(rows: Record<string, unknown>[]) { try { if (rows.length) await requestDelivery(admin, rows); } catch (_e) { /* */ } }

// THE COMMERCIAL ACCEPT RULE, read from the stored quote (14 Sep 2026). It lived inline in
// submit_quote; approving a regenerated quotation must clear the same bar, so both call this.
// 5 Aug 2026: completeness is a property of the QUOTE, not of the screen it arrived through — an
// uploaded quotation with priced lines, validity, warranty and lead time is as complete as a typed one.
export async function acceptRule(qid: string) {
  const { data: q } = await admin.from('quotes').select('lead_time,validity,warranty').eq('id', qid).maybeSingle();
  const { data: qi } = await admin.from('quote_items').select('unit_price,amount').eq('quote_id', qid);
  // deno-lint-ignore no-explicit-any
  let score: any = null; try { const { data } = await admin.rpc('fn_quote_structured_score', { p_quote: qid }); score = data; } catch (_e) { /* */ }
  const submittable = !!(score && score.submittable);
  try { await admin.from('quotes').update({ submittable }).eq('id', qid); } catch (_e) { /* */ }
  const requireStructured = (await secretVal('require_structured_quotes')) === 'true';
  const priced = (qi || []).filter((r: { unit_price: number | null; amount: number | null }) => (Number(r.unit_price) || 0) > 0 || (Number(r.amount) || 0) > 0).length;
  const formComplete = priced >= 1 && !!q?.validity && !!q?.warranty && !!q?.lead_time;
  return { accept: submittable || formComplete || !requireStructured, submittable, formComplete, requireStructured, priced, score };
}
// THE NOTES ARE STORED WITH THE QUOTE (founder ledger 1588, 10 Nov 2026). When a quote goes live the sales engineer's
// review of it against the request is written beside it — the record of what the customer was told. The surfaces that
// show it (my_inquiries, quote_compare, the quotation PDF) recompute it from the same rows, so an edit to the request
// is reflected at once; this is the record, never the only copy. The column is added by
// scripts/sql/a_quote_carries_the_sales_engineers_review_notes.sql (pending): until it is applied the update is
// refused and nothing else changes — the quote is live either way.
export async function storeReviewNotes(qid: string, inquiryId: string): Promise<number | null> {
  try {
    const [{ data: inq }, { data: q }, { data: lines }] = await Promise.all([
      admin.from('inquiries').select('summary,spec,boq').eq('id', inquiryId).maybeSingle(),
      admin.from('quotes').select('supplier_id,lead_time,warranty,scope,exclusions,conditions,notes,terms_spec').eq('id', qid).maybeSingle(),
      admin.from('quote_items').select('line_no,description,brand,model,specification,qty,unit,unit_price,amount,country_of_origin,notes,spec').eq('quote_id', qid).order('line_no', { ascending: true }).limit(80),
    ]);
    if (!inq || !q) return null;
    const { data: l } = q.supplier_id != null ? await admin.from('leads').select('company_name').eq('id', q.supplier_id).maybeSingle() : { data: null };
    const notes = reviewNotes({ request: requestOf(inq), quote: q, lines: lines || [], supplierNames: l?.company_name ? [String(l.company_name)] : [] });
    const { error } = await admin.from('quotes').update({ review_notes: notes, review_notes_at: new Date().toISOString() }).eq('id', qid);
    return error ? null : notes.length;
  } catch (_e) { return null; }
}
// THE NOTICE NAMES ITS QUOTE (final audit 12 Nov 2026, M8 / integration finding 4; ruling 1631). Every new_quote notice on
// a request has the same subject and body, so the outbox duplicate guard, keyed on the text alone, would have cancelled
// a second supplier's notice inside its 10-minute window (6 of 8 in the audit's run). The row now carries quote_id (the
// WhatsApp twin copies it), and the guard compares it: two quotes are two events; the same quote told twice is one.
export async function notifyNewQuote(inquiryId: string, quoteId: string | null = null) {
  try {
    const { data: inq } = await admin.from('inquiries').select('customer_id,summary').eq('id', inquiryId).maybeSingle();
    if (!inq?.customer_id) return;
    const { data: c } = await admin.from('customers').select('email').eq('id', inq.customer_id).maybeSingle();
    if (c?.email) await notify([{ type: 'new_quote', to_email: c.email, to_role: 'customer', inquiry_id: inquiryId, quote_id: quoteId, subject: 'You have a new quote on QuotesDone', body: 'A supplier submitted a quote for your request' + (inq.summary ? ': ' + inq.summary : '') + '. Log in to view the full quotation and compare.' }]);
  } catch (_e) { /* */ }
}
// "WE NOTIFY DIRECTLY" (founder, 14 Sep 2026). The sales engineer's notices are delivery requests
// customer_support sends (#614). Queued rows would otherwise wait for the next outbox tick; this asks
// both of support's dispatchers to send now. Best-effort: the scheduled flush still sends if it fails.
export async function kickDelivery() {
  const secret = await secretVal('cred_fn_supplier_api'); if (!secret) return;
  await Promise.allSettled(['send_outbox', 'send_whatsapp'].map((fn) => fetch(`${SUPA_URL}/functions/v1/${fn}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret }) })));
}
/** The supplier as the hold desk addresses them: every channel on file, in their language. */
// deno-lint-ignore no-explicit-any
export const supplierOf = (sup: any, email: string) => ({ id: Number(sup.id), email: email || null, phone: sup.whatsapp || sup.phone || null, locale: SUPPLIER_LOCALE });
/**
 * The quality hold on this quote, if the gate just opened (or kept) one: the fixes as MissingItem rows (the shape every
 * hold surface renders) and the message. Null when the quote went out. Suppliers are written in English only, so
 * label_ar carries the English sentence too. Before the SQL is applied the table is absent and this answers null.
 */
async function qualityHold(qid: string): Promise<{ missing: MissingItem[]; message: string } | null> {
  const { data: q } = await admin.from('quotes').select('status').eq('id', qid).maybeSingle();
  if (!q || String(q.status) !== 'draft') return null;
  const { data: h, error } = await admin.from('quote_quality_hold').select('fixes_en,release_due,released_at,superseded_at').eq('quote_id', qid).maybeSingle();
  if (error || !h || h.released_at || h.superseded_at) return null;
  const missing: MissingItem[] = String(h.fixes_en || '').split('\n').map((l) => l.replace(/^\d+\.\s*/, '').trim()).filter(Boolean)
    .map((l, i) => ({ scope: 'quote', line_no: null, description: null, attr: 'quality_fix_' + (i + 1), label_en: l, label_ar: l, type: 'text' }));
  const due = h.release_due ? new Date(h.release_due).toLocaleString('en-GB', { timeZone: 'Asia/Dubai', day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : null;
  return { missing, message: 'Your quotation is on hold: our quality check found the points listed. Correct them and send it again.'
    + (due ? ' If they are not corrected by ' + due + ' (Dubai time), it is shown to the customer as it stands, with the points beside it.' : '')
    + ' We are also e-mailing you this list.' };
}
/**
 * A SUBMISSION THE DOOR DID NOT ACCEPT ENDS THE QUALITY HOLD (review of #1108, 29 Sep 2026). The hold remembers the
 * version acceptLive accepted; the duty only ever releases that exact content. A later submission that the exact-specs
 * gate, the review's rules 1-7 or the accept rule refuses leaves a draft the wait must never publish, so its hold is
 * superseded here and closed without a release. A later accepted submission opens a fresh hold through the gate.
 */
export async function supersedeQualityHold(qid: string) {
  try { await admin.from('quote_quality_hold').update({ superseded_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq('quote_id', qid).is('released_at', null).is('superseded_at', null); } catch (_e) { /* absent before the SQL is applied */ }
}
/** What the supplier reads when the write that sends his quotation did not land (item A): plain, retryable, and true. The portal's
 *  copy for the code is src/components/portal/supplier/serverCopy.ts `quote_not_sent`. */
export const QUOTE_NOT_SENT = {
  code: 'quote_not_sent', retryable: true,
  message: 'Your quotation was saved but NOT sent to the customer: our system could not complete the last step just now. Nothing is lost. Please press Send again in a moment.',
} as const;
/** What the supplier reads when his quotation's lines could not be saved (item B). Portal copy: serverCopy.ts `quote_not_saved`. */
export const QUOTE_NOT_SAVED = {
  code: 'quote_not_saved', retryable: true,
  message: 'Your quotation was NOT sent: our system could not save its lines just now. Nothing is lost. Please press Send again in a moment.',
} as const;
/**
 * A QUOTATION'S LINES, WRITTEN OR SAID NOT TO BE (15 Nov 2026, review 2 of the certificate branch, item B). The old lines are deleted
 * and the new ones inserted, and BOTH answers are read: supabase-js answers { error }, it never throws, so the try/catch this
 * replaced let a lock or a timeout leave the quotation with its old lines or none while the submission answered ok. A blip retries
 * the PAIR (delete, then insert): a retry after an insert whose answer was lost deletes what landed first, so no line is doubled.
 */
export const writeQuoteLines = (qid: string, rows: Record<string, unknown>[], sleep?: (ms: number) => Promise<void>) =>
  writeRecorded(async () => {
    const d = await admin.from('quote_items').delete().eq('quote_id', qid);
    if (d.error) return { data: null, error: d.error };
    if (!rows.length) return { data: [{ quote_id: qid }], error: null };
    const i = await admin.from('quote_items').insert(rows);
    return { data: i.error ? null : rows, error: i.error };
  }, [800], sleep, { budgetMs: 10_000 });
/** Offer a quote that has cleared the hold gate to the accept rule; on pass it goes to the customer. */
export async function acceptLive(qid: string, inquiryId: string, notifyCustomer: boolean) {
  // Quote quality is scored by structure in trg_quote_quality; the category aspects are no longer read by the
  // model (24 Sep 2026, it_engineer, quote_quality_trade_keys_and_repeat_requests_are_code_not_the_model.sql).
  const r = await acceptRule(qid);
  // deno-lint-ignore no-explicit-any
  let coaching: any = null;
  if (r.accept) {
    // THE QUOTATION IS SENT ONLY IF THE WRITE THAT SENDS IT LANDED (15 Nov 2026, review 2 of the certificate branch, item A). This
    // write sat in a try/catch, which supabase-js never enters (it answers { error }, it does not throw): on 13 Nov a lock on quotes
    // cancelled writes like it, so the quote stayed a draft, qualityHold below found no hold, and the supplier was told "accepted"
    // while the customer was told of a quote he could not see. Now a blip is tried again (the same value; within a page's wait), and
    // a write that did not land answers the supplier that the quotation was NOT sent, tells nobody else, and tells the IT seat.
    const sent = await writeRecorded(async () => {
      const { error } = await admin.from('quotes').update({ status: 'submitted' }).eq('id', qid);
      return { data: error ? null : [{ id: qid }], error };
    }, [800], undefined, { budgetMs: 10_000 });
    if (!sent.ok) {
      tellItSeat('quote_not_sent:submitted_write', "supplier_api could not set a supplier's accepted quotation to submitted, so it did not reach the customer",
        'edge function supplier_api, acceptLive (submit_quote / spec_approve)', { quote_id: qid, inquiry_id: inquiryId, attempts: sent.attempts,
          reason: maskContact(sent.reason).slice(0, 300), told: 'the supplier was told the quotation was not sent and to press Send again; the customer was not told' });
      return { accepted: false, submittable: r.submittable, score: r.score, coaching, held: false, not_sent: true, ...QUOTE_NOT_SENT };
    }
    // THE QUALITY CHECK (founder ledger 1018, 29 Sep 2026; scripts/sql/a_quote_is_checked_for_specs_prices_and_terms_
    // before_the_customer_sees_it.sql). z40_quote_quality_gate keeps a quote with missing checklist specs, a price outside
    // the UAE range or no validity / delivery time / VAT basis a draft for up to 24 h. The status is read back: a held
    // quote is answered as held, with the exact fixes, and the customer is not told of a quote they cannot see.
    const qh = await qualityHold(qid);
    if (qh) return { accepted: false, submittable: r.submittable, score: r.score, coaching, held: true, code: 'quality_hold', missing: qh.missing, message: qh.message };
    // THE REQUEST'S STATUS FOLLOWS (item C): the quotation itself stands (it is submitted and the customer reads quotes by their own
    // status), so a failed write here is not said to the supplier; it is told to the IT seat, because the request's lists read it.
    const { error: inqErr } = await admin.from('inquiries').update({ status: 'quoted' }).eq('id', inquiryId).in('status', ['sent', 'quoted']);
    if (inqErr) tellItSeat('inquiry_not_marked_quoted', "supplier_api could not mark a request 'quoted' after a quotation went to the customer",
      'edge function supplier_api, acceptLive', { quote_id: qid, inquiry_id: inquiryId, reason: maskContact(String(inqErr.message ?? inqErr.code ?? '')).slice(0, 300),
        note: 'the quotation is submitted and stands; only inquiries.status was left as it was' });
    if (notifyCustomer) await notifyNewQuote(inquiryId, qid);
    // A QUOTE THAT WENT LIVE IS NEVER COACHED (final audit 12 Nov 2026, B3; ledger 1642). fn_quote_coach was called here
    // whenever the score said "not submittable", and told 8 of 8 suppliers "your quote needs a few more details before
    // we can send it" in the same second the customer received it. Only a refused draft is coached (below), and
    // fn_quote_coach itself refuses a quote that is not a draft (scripts/sql/a_quote_that_went_to_the_customer_is_never_coached.sql).
    return { accepted: true, submittable: r.submittable, score: r.score, coaching };
  }
  try { await admin.from('quotes').update({ status: 'draft' }).eq('id', qid); } catch (_e) { /* */ }
  await supersedeQualityHold(qid);
  try { const { data } = await admin.rpc('fn_quote_coach', { p_quote: qid }); coaching = data; } catch (_e) { /* */ }
  return { accepted: false, submittable: false, score: r.score, coaching };
}
