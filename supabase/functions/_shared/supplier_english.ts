// SUPPLIERS READ ENGLISH ONLY (founder, 28 Sep 2026; ledger 993); CUSTOMERS WRITE IN THEIR OWN LANGUAGE.
// Seat: sales_engineer. founder_instruction 1026 (the anonymised Q&A every bidder reads) and the release review of #1195.
//
// What a customer writes that every matched supplier reads - an answer to a supplier's clarification question
// (messages_api clarify_answer) and a note added to a live request (customer_api rfq_note) - is stored on
// public.rfq_clarification. Measured 5 Oct 2026: both paths stored the text as typed and e-mailed it verbatim, so an
// Arabic answer reached suppliers in Arabic (send_outbox's Arabic hold reads the row's lang, not its body).
//
// NOW. An Arabic text is accepted and kept AS WRITTEN (answer_as_written). The supplier copy (answer) is HELD
// (english_held_at) and its English is filed in the sales_engineer's reasoning queue (fn_reason_hold, surface
// sales_engineer.supplier_english). A request path never waits on a model: the replay (resilience_ping ->
// replayHeld) translates it the moment the founder's model hold allows, and reasoned_delivery hands the English to
// finishEnglish below, which stores it and e-mails every matched supplier. While the hold is on, the copy stays held.
// The customer is told, in their language, that the message will be passed on shortly (HELD_NOTICE).
// Every supplier e-mail on these paths goes through toSuppliers(), which drops any row carrying Arabic script.
import { requestDelivery } from './deliver.ts';

const ARABIC = /[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]/; // U+FEFF (a pasted BOM) is not Arabic

export const hasArabic = (s: unknown): boolean => ARABIC.test(String(s ?? ''));

export const ENGLISH_SURFACE = 'sales_engineer.supplier_english';

/** What the customer sees when the supplier copy is held for its English. */
export const HELD_NOTICE = {
  en: 'Thank you. We have your message and will pass it on to the suppliers in English shortly.',
  ar: 'شكرًا لكم. استلمنا رسالتكم، وسنُرسلها إلى المورّدين باللغة الإنجليزية خلال وقت قصير.',
};

export function englishQuestion(text: string): string {
  return 'Translate this message from a customer into clear, professional English for the suppliers quoting the job, '
    + 'as a UAE sales engineer would write it. Keep every measurement, quantity, brand, model and grade code exactly as written. '
    + 'Add nothing and leave nothing out. Put ONLY the English text in "answer".\n\n' + text;
}

/** The reasoned answer as a supplier copy: non-empty English with no Arabic script left in it, or null. Pure. */
export function englishAnswer(answer: unknown): string | null {
  const s = String(answer ?? '').trim().replace(/^"(.*)"$/s, '$1').trim().slice(0, 1500);
  return s && !hasArabic(s) ? s : null;
}

/** Every supplier-bound row passes here: a row whose subject or body carries Arabic script is dropped, never sent. */
export function toSuppliers<T extends { subject?: unknown; body?: unknown }>(rows: T[]): T[] {
  return rows.filter((r) => !hasArabic(r.subject) && !hasArabic(r.body));
}

// deno-lint-ignore no-explicit-any
type Admin = any;

/** File the English of clarification `id` for the replay. Throws when the filing fails, so the caller never tells
 *  the customer it will be passed on when nothing will pass it on. */
export async function holdForEnglish(admin: Admin, id: number, text: string): Promise<void> {
  const req = {
    seat: 'sales_engineer', surface: ENGLISH_SURFACE, question: englishQuestion(text),
    // 'supplier', not 'internal' (founder ruling 1338, 27 Oct 2026): the text this writes is e-mailed to every matched
    // supplier, so it is reasoned with the public brief and retrieval's outside-audience branch, never seats.md or an
    // internal knowledge row. A translation needs neither.
    context: { audience: 'supplier', language: 'en' }, research: false,
    subject: { clarification_id: id }, dedupeKey: 'supplier_english:' + id,
  };
  const { error } = await admin.rpc('fn_reason_hold', { p_seat: req.seat, p_surface: req.surface, p_question: req.question.slice(0, 8000),
    p_request: req, p_plan: {}, p_subject: req.subject, p_reason: 'filed_from_a_request_path', p_dedupe_key: req.dedupeKey });
  if (error) throw new Error('fn_reason_hold: ' + error.message);
}

/** The one supplier e-mail for a customer's text on a request (the answer to a question, or a note). Pure. */
export function supplierMail(kind: string, inq: { category?: string | null; emirate?: string | null }, question: string | null, english: string) {
  const job = (inq.category || 'request') + (inq.emirate ? ' job in ' + inq.emirate : ' job');
  return kind === 'question'
    ? { type: 'clarification_answered', subject: 'The customer answered a question on a request you were invited to quote',
        body: 'On the ' + job + ' you were invited to quote, a supplier asked:\n\n"' + String(question || '') + '"\n\nThe customer answered:\n\n"' + english + '"\n\nThis answer is now part of the request. Log in to your QuotesDone supplier portal to see the full request and quote.' }
    : { type: 'rfq_addendum', subject: 'The customer added detail to a request you were invited to quote',
        body: 'The customer added this to the ' + job + ' you were invited to quote:\n\n"' + english + '"\n\nIt is now part of the request. Log in to your QuotesDone supplier portal to see the full request and quote.' };
}

/** One queued e-mail per matched, unbanned supplier; returns how many were queued. */
export async function mailMatched(admin: Admin, inquiry_id: string, mail: { type: string; subject: string; body: string }): Promise<number> {
  const { data: ms } = await admin.from('inquiry_matches').select('supplier_id').eq('inquiry_id', inquiry_id);
  const ids = [...new Set((ms || []).map((m: { supplier_id: number }) => Number(m.supplier_id)).filter(Boolean))];
  if (!ids.length) return 0;
  const { data: ls } = await admin.from('leads').select('id,email,claimed_by,banned').in('id', ids);
  const rows = toSuppliers((ls || []).filter((l: { banned?: boolean }) => l.banned !== true)
    .map((l: { id: number; email?: string; claimed_by?: string }) => ({ id: l.id, to: String(l.claimed_by || l.email || '') })).filter((l: { to: string }) => /@/.test(l.to))
    .map((l: { id: number; to: string }) => ({ ...mail, to_email: l.to, to_role: 'supplier', lead_id: l.id, inquiry_id, channel: 'email', status: 'queued' })));
  if (!rows.length) return 0;
  try { const { error } = await requestDelivery(admin, rows); return error ? 0 : rows.length; } catch (_e) { return 0; }
}

/** The replay's delivery: store the reasoned English as the supplier copy and tell every matched supplier. */
export async function finishEnglish(admin: Admin, id: number, answer: unknown): Promise<{ ok: boolean; err?: string; notified?: number }> {
  const english = englishAnswer(answer);
  if (!english) return { ok: false, err: 'the reasoned answer is not English; the supplier copy stays held' };
  const { data: row } = await admin.from('rfq_clarification').select('id,inquiry_id,kind,question,english_held_at').eq('id', id).maybeSingle();
  if (!row) return { ok: false, err: 'no clarification ' + id };
  if (!row.english_held_at) return { ok: true, notified: 0 };   // already finished: never mailed twice
  const { data: upd, error } = await admin.from('rfq_clarification').update({ answer: english, english_held_at: null })
    .eq('id', id).not('english_held_at', 'is', null).select('id');
  if (error) return { ok: false, err: error.message };
  if (!upd?.length) return { ok: true, notified: 0 };
  const { data: inq } = await admin.from('inquiries').select('category,emirate').eq('id', row.inquiry_id).maybeSingle();
  const notified = await mailMatched(admin, String(row.inquiry_id), supplierMail(row.kind, inq || {}, row.question, english));
  return { ok: true, notified };
}
