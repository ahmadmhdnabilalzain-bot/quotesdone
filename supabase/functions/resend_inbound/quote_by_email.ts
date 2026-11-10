// quote_by_email — A SUPPLIER'S QUOTATION SENT BY E-MAIL REACHES HIS REQUEST (customer_support, 10 Nov 2026; founder
// ruling 1608, supplier follow-up #1909 item 1).
//
// MEASURED on origin/main: steps/supplier_docs.ts treated every attachment from a matched supplier as a PROFILE document
// (licence, profile, catalogue). An e-mailed quotation was stored in supplier-docs, classified (or, under the model
// hold, not classified at all), and the supplier was answered "we received 1 document(s) and our team will add them
// to your profile". The quote never reached the request, and an .xlsx quotation was refused outright (that path takes
// only PDF and images).
//
// WHAT THIS DECIDES, before the profile path sees the mail:
//   WHO   — only a VERIFIED sender: the receiving server authenticated the From domain (suppression_policy.ts
//           senderAuthenticated, the same proof the licence write needs), and the address is the one the company signs
//           in with (leads.claimed_by), or its listed address proven by a code (fn_email_proven). Anyone else is told to
//           upload in the portal; nothing is accepted from them.
//   WHAT  — by CONTENT, with the existing quotation reader (supplier_api/quote_review_flow/reading.ts readQuotationFile:
//           doc_read + quote_from_document, the vision transcription where a model may be asked). A file it prices with
//           a stated total is a quotation; so is one with priced lines when the mail is tied to a request. A body that
//           prices the job is a quotation too. Anything else is left to the profile path, which classifies it as before.
//   WHICH — the request: the notice it replies to (In-Reply-To / References carry our qd-notif-<id> Message-ID, or the
//           provider id of the notice), else a request number in the subject or body that is one of HIS open requests,
//           else his only open request. Two or more candidates, or a number that is not one of his open requests: the
//           supplier is ASKED which request, never guessed for.
// The quotation then goes to supplier_api's internal door email_quote (supplier_api/email_quote.ts): the portal's own
// extract_quote and submit_quote, so the review and the hold desk's one evaluator decide, as for an upload. The supplier
// is told in English what was received and what, if anything, is still needed, with the portal link.
// prevented by: resend_inbound/quote_by_email.test.ts
import type { Proposal } from '../quote_extract/quote_from_document.ts';
import type { EmailQuoteInput, EmailQuoteResult } from '../supplier_api/email_quote.ts';
import { jobNoOf } from '../_shared/quote_documents/rows.ts';

export const PORTAL = 'https://quotesdone.com/portal';
export type OpenRequest = { id: string; rfq_no: number | string | null; category: string | null; emirate: string | null };
export type Lead = { id: number; company_name: string | null; claimed_by: string | null; email: string | null };
export type MailFile = { index: number; filename: string; mime: string; bytes: Uint8Array };
export type Reading = { proposal: (Proposal & { review_reason?: string | null }) | null; kind: string };

/** Request numbers the supplier wrote: "RFQ-151767", "QD-151767", "Request 151767", "Job No: 151767", "#151767". */
export function requestNumbersIn(...texts: (string | null | undefined)[]): string[] {
  const out = new Set<string>();
  const re = /(?:\b(?:rfq|qd|request|req|job|enquiry|inquiry)\s*(?:no\.?|number|ref\.?|#)?\s*[:#-]?\s*|#)(\d{3,9})\b/gi;
  for (const t of texts) for (const m of String(t ?? '').matchAll(re)) out.add(String(Number(m[1])));
  return [...out];
}

/** Our notices' ids in a reply's threading headers: send_outbox's Message-ID is <qd-notif-<id>.<ms>@quotesdone.com>. */
export function notificationIdsIn(...headers: (string | null | undefined)[]): number[] {
  const out = new Set<number>();
  for (const h of headers) for (const m of String(h ?? '').matchAll(/qd-notif-(\d{1,12})\./gi)) out.add(Number(m[1]));
  return [...out];
}
/** Every Message-ID token in the threading headers, bare (a Resend-lane notice is matched on its provider id). */
export function messageIdsIn(...headers: (string | null | undefined)[]): string[] {
  const out = new Set<string>();
  for (const h of headers) for (const m of String(h ?? '').matchAll(/<([^<>\s@]{4,200})@[^<>\s]+>/g)) out.add(m[1]);
  return [...out];
}

export type Choice =
  | { kind: 'one'; request: OpenRequest; by: 'thread' | 'reference' | 'only_open' }
  | { kind: 'ask'; candidates: OpenRequest[]; why: 'several_threaded' | 'several_named' | 'several_open' | 'named_not_open' }
  | { kind: 'none' };

/** Which of the supplier's open requests the mail answers. Never a guess: two candidates is a question. */
export function chooseRequest(open: OpenRequest[], threaded: string[], numbers: string[]): Choice {
  const t = open.filter((o) => threaded.includes(String(o.id)));
  if (t.length === 1) return { kind: 'one', request: t[0], by: 'thread' };
  if (t.length > 1) return { kind: 'ask', candidates: t, why: 'several_threaded' };
  const named = open.filter((o) => o.rfq_no != null && numbers.includes(String(Number(o.rfq_no))));
  if (named.length === 1) return { kind: 'one', request: named[0], by: 'reference' };
  if (named.length > 1) return { kind: 'ask', candidates: named, why: 'several_named' };
  if (numbers.length) return open.length ? { kind: 'ask', candidates: open, why: 'named_not_open' } : { kind: 'none' };
  if (open.length === 1) return { kind: 'one', request: open[0], by: 'only_open' };
  if (open.length > 1) return { kind: 'ask', candidates: open, why: 'several_open' };
  return { kind: 'none' };
}

/** A verified sender: the domain authenticated AND the company's sign-in address (or its listed address, proven). */
export function verifiedSender(lead: Lead | null, from: string, senderAuth: boolean, listedProven: boolean): boolean {
  const f = String(from || '').trim().toLowerCase();
  const claimed = String(lead?.claimed_by || '').trim().toLowerCase();
  if (!lead || !senderAuth || !claimed || !f) return false;
  if (f === claimed) return true;
  return f === String(lead.email || '').trim().toLowerCase() && listedProven;
}

/** By content: the quotation reader priced it with a total (or a total it held as ambiguous), or priced lines on a mail
 *  tied to a request. A price list with no total and no request is a catalogue, and stays on the profile path. */
export function isQuotation(r: Reading, tiedToRequest: boolean): boolean {
  const p = r.proposal;
  if (!p) return false;
  if (p.amount != null && p.amount > 0) return true;
  if (p.review_reason) return true;
  return tiedToRequest && (p.line_items || []).some((l) => l.amount != null && l.amount > 0);
}

const ref = (o: OpenRequest) => 'RFQ-' + jobNoOf(o);
const what = (o: OpenRequest) => ref(o) + ' (' + [o.category, o.emirate].filter(Boolean).join(', ') + ')';
const money = (n: number) => 'AED ' + n.toLocaleString('en-US', { maximumFractionDigits: 2 });
const hello = (lead: Lead) => 'Dear ' + (String(lead.company_name || '').trim() || 'supplier') + ',\n\n';
const sign = '\n\nQuotesDone supplier support';
// deno-lint-ignore no-explicit-any
const missingLines = (m: any[]) => m.map((x) => String(x?.label_en || x?.en || x?.attr || '').trim()).filter(Boolean).slice(0, 12).map((s, i) => (i + 1) + '. ' + s).join('\n');

export type Outcome =
  | { kind: 'unverified' }
  | { kind: 'ask'; choice: Extract<Choice, { kind: 'ask' }> }
  | { kind: 'none' }
  | { kind: 'submitted'; request: OpenRequest; file: string; result: EmailQuoteResult; extra: string[] };

/** What the supplier is told, in English (suppliers are always written in English). */
export function replyFor(lead: Lead, o: Outcome): { subject: string; body: string } {
  if (o.kind === 'unverified') return { subject: 'Please send your quotation through the supplier portal',
    body: hello(lead) + 'We received a quotation by e-mail, but we can only accept a quotation by e-mail from the address your company signs in with, and only when your mail server confirms it really came from you. Nothing has been sent to the customer.\n\nPlease sign in to the supplier portal and upload it on the request: ' + PORTAL + sign };
  if (o.kind === 'none') return { subject: 'We received a quotation, but you have no open request to quote',
    body: hello(lead) + 'We received a quotation from you by e-mail, but your company has no open request on QuotesDone that it could answer, so nothing has been sent to a customer. New requests matched to your company appear in the supplier portal: ' + PORTAL + sign };
  if (o.kind === 'ask') {
    const why = o.choice.why === 'named_not_open' ? 'the request number in your e-mail is not one of your open requests'
      : o.choice.why === 'several_named' ? 'your e-mail names more than one of your requests' : 'you have more than one open request';
    return { subject: 'Which request is your quotation for?',
      body: hello(lead) + 'We received a quotation from you by e-mail, but ' + why + ', so we have not sent it to any customer. Your open requests are:\n\n'
        + o.choice.candidates.slice(0, 10).map((c) => '- ' + what(c)).join('\n')
        + '\n\nPlease send it again with the request number (for example ' + ref(o.choice.candidates[0]) + ') in the subject, or upload it on the request in the supplier portal: ' + PORTAL + sign };
  }
  const r = o.result; const job = ref(o.request);
  const extra = o.extra.length ? '\n\nThis e-mail carried more than one quotation file. We used "' + o.file + '"; ' + o.extra.map((x) => '"' + x + '"').join(', ') + ' ' + (o.extra.length === 1 ? 'was' : 'were') + ' not used. If it is another option, add it as a new option on the request in the supplier portal.' : '';
  if (!r.ok) {
    const head = hello(lead) + 'We received your quotation "' + o.file + '" for request ' + job + ' by e-mail, but it has not been sent to the customer. ';
    const why = r.stage === 'extract'
      ? (r.code === 'quote_total_ambiguous' ? 'We read it but could not be sure of its total' + (r.review_reason ? ' (' + String(r.review_reason).replace(/_/g, ' ') + ')' : '') + '. Please open the request in the supplier portal and type the total.'
        : (r.message || 'We could not read it.') + ' You can also upload it on the request in the supplier portal.')
      : r.stage === 'job' ? 'This request is no longer open to your company.'
      : (r.message || 'It could not be submitted just now.');
    return { subject: 'Your quotation for ' + job + ' needs your attention', body: head + why + '\n\nSupplier portal: ' + PORTAL + extra + sign };
  }
  const read = (r.amount != null ? 'a total of ' + money(r.amount) + ' excluding VAT' : 'no total') + (r.lines ? ', ' + r.lines + ' priced line' + (r.lines === 1 ? '' : 's') : '');
  const head = hello(lead) + 'We received your quotation "' + o.file + '" for request ' + job + ' by e-mail and read it: ' + read + '. ';
  if (r.accepted && !r.held) return { subject: 'Your quotation for ' + job + ' has been sent to the customer',
    body: head + 'It has been sent to the customer. You can see it, and change it until the customer reveals a supplier, in the supplier portal: ' + PORTAL + extra + sign };
  if (r.held) {
    const list = missingLines(r.missing);
    return { subject: 'Your quotation for ' + job + ' is on hold: details needed',
      body: head + 'It is saved, but it is on hold and has not been sent to the customer until these details are stated:\n\n' + (list || (r.message || 'the details listed on the request')) + '\n\nPlease fill them in on the request in the supplier portal, or upload a revised quotation there: ' + PORTAL + extra + sign };
  }
  return { subject: 'Your quotation for ' + job + ' is saved as a draft',
    body: head + 'It is saved as a draft and has not been sent to the customer yet. ' + (r.message || 'Please add the missing details') + ' in the supplier portal: ' + PORTAL + extra + sign };
}

export type QuoteMailDeps = {
  openRequests: (leadId: number) => Promise<OpenRequest[]>;
  /** The requests of THIS supplier's notices that the reply's threading headers name. */
  threaded: (leadId: number, notificationIds: number[], messageIds: string[]) => Promise<string[]>;
  listedProven: (email: string) => Promise<boolean>;
  /** The quotation reader; `tied` = the mail answers one request (only then may a model transcribe a scan). */
  read: (f: MailFile, terms: string[], tied: boolean) => Promise<Reading>;
  submit: (input: EmailQuoteInput) => Promise<EmailQuoteResult>;
  reply: (lead: Lead, to: string, inquiryId: string | null, msg: { subject: string; body: string }) => Promise<void>;
};
export type Mail = { from: string; subject: string; text: string; inReplyTo: string | null; references: string | null; senderAuth: boolean };

const b64 = (u8: Uint8Array) => { let s = ''; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000)); return btoa(s); };

/** The quotation route. Answers which attachments it took (the profile path skips them) and what happened. */
export async function quoteByEmail(mail: Mail, lead: Lead | null, files: MailFile[], deps: QuoteMailDeps): Promise<{ taken: number[]; outcome: Outcome['kind'] | null; inquiry_id: string | null }> {
  const nothing = { taken: [] as number[], outcome: null, inquiry_id: null };
  if (!lead?.id || !String(lead.claimed_by || '').includes('@')) return nothing;   // an unclaimed listing cannot quote
  const open = await deps.openRequests(lead.id);
  const threaded = await deps.threaded(lead.id, notificationIdsIn(mail.inReplyTo, mail.references), messageIdsIn(mail.inReplyTo, mail.references));
  const choice = chooseRequest(open, threaded, requestNumbersIn(mail.subject, mail.text));
  const tied = choice.kind === 'one' || threaded.length > 0;
  const terms = [String(lead.company_name || '')].filter(Boolean);
  const quotes: MailFile[] = [];
  for (const f of files) if (isQuotation(await deps.read(f, terms, tied), tied)) quotes.push(f);
  // A priced body is a quotation too, when no file is one (the body is read as the text file it is).
  if (!quotes.length && String(mail.text || '').trim().length >= 20) {
    const body: MailFile = { index: -1, filename: 'quotation-email.txt', mime: 'text/plain', bytes: new TextEncoder().encode(mail.text) };
    if (isQuotation(await deps.read(body, terms, tied), tied)) quotes.push(body);
  }
  if (!quotes.length) return nothing;
  const taken = quotes.map((q) => q.index).filter((i) => i >= 0);
  const to = String(lead.claimed_by).trim().toLowerCase();
  const listed = String(lead.email || '').trim().toLowerCase();
  const proven = mail.from === listed && mail.from !== to ? await deps.listedProven(listed) : false;
  if (!verifiedSender(lead, mail.from, mail.senderAuth, proven)) {
    // Told at the address the company signs in with, never at an address we could not prove.
    await deps.reply(lead, to, null, replyFor(lead, { kind: 'unverified' }));
    return { taken, outcome: 'unverified', inquiry_id: null };
  }
  if (choice.kind !== 'one') {
    await deps.reply(lead, to, null, replyFor(lead, choice.kind === 'ask' ? { kind: 'ask', choice } : { kind: 'none' }));
    return { taken, outcome: choice.kind, inquiry_id: null };
  }
  const [first, ...rest] = quotes;
  const result = await deps.submit({ lead_id: lead.id, inquiry_id: choice.request.id, file_b64: b64(first.bytes), filename: first.filename, mime: first.mime });
  await deps.reply(lead, to, choice.request.id, replyFor(lead, { kind: 'submitted', request: choice.request, file: first.filename, result, extra: rest.map((r) => r.filename) }));
  return { taken, outcome: 'submitted', inquiry_id: choice.request.id };
}
