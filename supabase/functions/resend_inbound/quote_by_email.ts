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
//   WHAT  — by what the MODEL reads (sales_engineer, 12 Nov 2026; founder rulings 1663/1664, LLM-first audit A2). Until
//           then a CODE reader (readQuotationFile) decided: a file it priced was a quotation, and so was an e-mail BODY
//           with one priced line when the supplier had one open request (measured on main 4b7091f08: an invoice for another
//           job was submitted as the quotation, and a body "Grand Total AED 9,450" as AED 9). Now each candidate file, and the body
//           when no file is one, is read by quote_extract's model through supplier_api email_quote_read: it says whether it
//           IS a quotation and reads it. Nothing is read when the supplier has no open request and the mail answers none of
//           our notices (a registering supplier's licence costs no quotation call). A model that does not answer leaves
//           the mail unread: the supplier is told plainly, and it is never priced by code.
//   WHICH — the request: the notice it replies to (In-Reply-To / References carry our qd-notif-<id> Message-ID, or the
//           provider id of the notice), else a request number in the subject or body that is one of HIS open requests,
//           else his only open request. Two or more candidates, or a number that is not one of his open requests: the
//           supplier is ASKED which request, never guessed for.
// The quotation then goes to supplier_api's internal door email_quote (supplier_api/email_quote.ts) WITH that reading (no
// second model call), which places it in the supplier's own quotation thread for the request. It is NOT sent to the
// customer: the supplier is told in English what we read, any figure we need him to confirm ("We read your total as
// AED 12,000 excluding VAT. Is that right?"), and that it reaches the customer only when he checks it and presses Submit
// in the portal, where submit_quote's review and the hold desk run as for every quotation.
// prevented by: resend_inbound/quote_by_email.test.ts
import type { Proposal } from '../quote_extract/quote_from_document.ts';
import type { EmailQuoteInput, EmailQuoteResult } from '../supplier_api/email_quote.ts';
import { jobNoOf } from '../_shared/quote_documents/rows.ts';

export const PORTAL = 'https://quotesdone.com/portal';
/** At most this many model readings per inbound mail: three files and the body (review of #1981, D3). */
export const MAX_READS = 4;
export type OpenRequest = { id: string; rfq_no: number | string | null; category: string | null; emirate: string | null };
export type Lead = { id: number; company_name: string | null; claimed_by: string | null; email: string | null };
export type MailFile = { index: number; filename: string; mime: string; bytes: Uint8Array };
/** What the model read in one candidate (supplier_api email_quote_read). `unread`: no model answer; never priced by code. */
export type Reading = { verdict: 'quotation' | 'not_quotation' | 'unread';
  proposal: (Proposal & { review_reason?: string | null; warnings?: string[]; request_reference?: string }) | null; extracted_by_model?: string | null };

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

/** A quotation is what the MODEL read as one (12 Nov 2026). No price, word or layout makes a mail a quotation here. */
export function isQuotation(r: Reading): boolean {
  return r.verdict === 'quotation' && !!r.proposal;
}

const ref = (o: OpenRequest) => 'RFQ-' + jobNoOf(o);
const what = (o: OpenRequest) => ref(o) + ' (' + [o.category, o.emirate].filter(Boolean).join(', ') + ')';
const money = (n: number) => 'AED ' + n.toLocaleString('en-US', { maximumFractionDigits: 2 });
const hello = (lead: Lead) => 'Dear ' + (String(lead.company_name || '').trim() || 'supplier') + ',\n\n';
const sign = '\n\nQuotesDone supplier support';

export type Outcome =
  | { kind: 'unverified' }
  | { kind: 'ask'; choice: Extract<Choice, { kind: 'ask' }> }
  | { kind: 'none' }
  | { kind: 'unread'; request: OpenRequest | null; files: string[] }
  | { kind: 'not_all_read'; read: string[]; total: number }
  | { kind: 'to_confirm'; request: OpenRequest; file: string; result: EmailQuoteResult; extra: string[]; unread?: string[] };

/** What the supplier is told, in English (suppliers are always written in English). */
export function replyFor(lead: Lead, o: Outcome): { subject: string; body: string } {
  if (o.kind === 'unverified') return { subject: 'Please send your quotation through the supplier portal',
    body: hello(lead) + 'We received an e-mail with attachments from your company. If it carried a quotation: we can only accept a quotation by e-mail from the address your company signs in with, and only when your mail server confirms it really came from you, so we have not read it and nothing has been sent to the customer.\n\nPlease sign in to the supplier portal and upload it on the request: ' + PORTAL + sign };
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
  if (o.kind === 'not_all_read') return { subject: 'We read only the first ' + o.read.length + ' attachments of your e-mail',
    body: hello(lead) + 'Your e-mail had ' + o.total + ' attachments. We read only the first ' + o.read.length + ' (' + o.read.map((f) => '"' + f + '"').join(', ')
      + '), and none of them is a quotation. Nothing has been sent to the customer. If your quotation was among the other attachments, please upload it on the request in the supplier portal: ' + PORTAL + sign };
  // NOTHING RETRIES THIS YET (review D6): the reply says what is true and what he can do now, and promises no later reading.
  if (o.kind === 'unread') return { subject: o.request ? 'We could not read your e-mail for ' + ref(o.request) + ' yet' : 'We could not read your e-mail yet',
    body: hello(lead) + 'We received your e-mail' + (o.files.length ? ' with ' + o.files.map((f) => '"' + f + '"').join(', ') : '') + (o.request ? ' for request ' + ref(o.request) : '')
      + ', but we could not read it yet. Nothing has been sent to the customer. If it is your quotation, please upload it on the request in the supplier portal, or e-mail it to us again: ' + PORTAL + sign };
  const r = o.result; const job = ref(o.request);
  // review D7: a file beside the quotation that could not be read is named, so he knows it was not looked at
  const skipped = o.unread?.length ? '\n\nWe could not read ' + o.unread.map((x) => '"' + x + '"').join(', ') + ' yet; if it matters for this quotation, please add it on the request in the supplier portal.' : '';
  const extra = skipped + (o.extra.length ? '\n\nThis e-mail carried more than one quotation file. We used "' + o.file + '"; ' + o.extra.map((x) => '"' + x + '"').join(', ') + ' ' + (o.extra.length === 1 ? 'was' : 'were') + ' not used. If it is another option, add it as a new option on the request in the supplier portal.' : '');
  if (!r.ok) {
    const head = hello(lead) + 'We received your quotation "' + o.file + '" for request ' + job + ' by e-mail, but it has not been sent to the customer. ';
    const why = r.stage === 'extract' && r.code === 'quote_total_ambiguous' && r.review_reason === 'foreign_currency'
      ? 'It is priced in a currency other than AED, and customers compare quotations in AED. Please open the request in the supplier portal and type your AED total.'
      : r.stage === 'job' ? 'This request is no longer open to your company.'
      : r.stage === 'review' && r.code === 'review_closed' ? 'Your quotation for this request has already been submitted. To change it, open the request in the supplier portal.'
      : (r.message || 'We could not place it on the request just now.') + ' Please upload it on the request in the supplier portal.';
    return { subject: 'Your quotation for ' + job + ' needs your attention', body: head + why + '\n\nSupplier portal: ' + PORTAL + extra + sign };
  }
  // WHAT WE READ, AND HIS CONFIRMATION (12 Nov 2026, LLM-first audit A2): an e-mailed quotation is never sent to the customer
  // on our reading alone. He is told the figures, every point the checks raised, and that his Submit sends it.
  // An option's total may include its VAT (review D7): only a single offer's figure is called "excluding VAT".
  const read = (r.amount == null ? 'no total we could be sure of' : r.options > 1 ? money(r.amount) + ' for option 1 of ' + r.options : 'a total of ' + money(r.amount) + ' excluding VAT') + (r.lines ? ', ' + r.lines + ' priced line' + (r.lines === 1 ? '' : 's') : '');
  const points = r.warnings.length ? '\n\nPlease check:\n' + r.warnings.map((w, i) => (i + 1) + '. ' + w).join('\n') : '';
  return { subject: 'Please confirm your quotation for ' + job,
    body: hello(lead) + 'We received your quotation "' + o.file + '" for request ' + job + ' by e-mail and read it: ' + read + '.' + points
      + '\n\nIt has NOT been sent to the customer yet. Please open the request in the supplier portal and check the figures we read'
      + (r.warnings.length ? '; the same questions are waiting for your answer in the quotation thread there, and it can be sent once you have answered them' : '')
      + '. Your Submit sends it: ' + PORTAL + extra + sign };
}

export type QuoteMailDeps = {
  openRequests: (leadId: number) => Promise<OpenRequest[]>;
  /** The requests of THIS supplier's notices that the reply's threading headers name. */
  threaded: (leadId: number, notificationIds: number[], messageIds: string[]) => Promise<string[]>;
  listedProven: (email: string) => Promise<boolean>;
  /** The model's reading of one candidate (supplier_api email_quote_read). `requests`: his open requests, for the model. */
  read: (f: MailFile, requests: OpenRequest[]) => Promise<Reading>;
  submit: (input: EmailQuoteInput) => Promise<EmailQuoteResult>;
  /** `dedupe`: one such reply per key (the unverified reply: one per company per day). */
  reply: (lead: Lead, to: string, inquiryId: string | null, msg: { subject: string; body: string }, dedupe?: string) => Promise<void>;
};
export type Mail = { from: string; subject: string; text: string; inReplyTo: string | null; references: string | null; senderAuth: boolean };

const b64 = (u8: Uint8Array) => { let s = ''; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000)); return btoa(s); };

/** The quotation route. Answers which attachments it took (the profile path skips them) and what happened. */
export async function quoteByEmail(mail: Mail, lead: Lead | null, files: MailFile[], deps: QuoteMailDeps): Promise<{ taken: number[]; outcome: Outcome['kind'] | null; inquiry_id: string | null }> {
  const nothing = { taken: [] as number[], outcome: null, inquiry_id: null };
  if (!lead?.id || !String(lead.claimed_by || '').includes('@')) return nothing;   // an unclaimed listing cannot quote
  const open = await deps.openRequests(lead.id);
  const threaded = await deps.threaded(lead.id, notificationIdsIn(mail.inReplyTo, mail.references), messageIdsIn(mail.inReplyTo, mail.references));
  // No open request and no reply to one of our notices: nothing here can be a quotation for him, and nothing is read.
  if (!open.length && !threaded.length) return nothing;
  // WHO FIRST (review of #1981, D3): nothing is read for, and nothing is answered to, a sender we cannot prove. A mail that
  // failed authentication from a supplier's address used to cost up to 7 readings (14 gateway attempts) and, with the model
  // down, sent the real supplier an 'unread' reply. It now takes the ordinary path (stored for review, email_triage).
  const to = String(lead.claimed_by).trim().toLowerCase();
  const listed = String(lead.email || '').trim().toLowerCase();
  const proven = mail.from === listed && mail.from !== to ? await deps.listedProven(listed) : false;
  if (!verifiedSender(lead, mail.from, mail.senderAuth, proven)) {
    // review of #1981 N3: a real supplier whose mail failed authentication is told what main told him, at his SIGN-IN address
    // (never the unproven From), with no model call: we cannot accept a quotation by e-mail from it; upload it in the portal.
    if (!files.length) return nothing;
    // One per company per day (review of #1981, minor): a spoofer cannot make the real supplier receive one per forged mail.
    await deps.reply(lead, to, null, replyFor(lead, { kind: 'unverified' }), 'quote_by_email:unverified:' + lead.id + ':' + new Date().toISOString().slice(0, 10));
    return { taken: [], outcome: 'unverified', inquiry_id: null };
  }
  const numbers = requestNumbersIn(mail.subject, mail.text);
  // THE MODEL READS THE CANDIDATES IN ONE ROUND, AT MOST MAX_READS (review D3): the first three files and the body, in
  // parallel, so a mail costs at most 4 quote_extract calls (8 gateway attempts) and waits one reading (p90 30 s; each read
  // is cut at 100 s by supplier_docs.ts). A fourth file or more is not read here and stays on the profile path. The body's
  // reading is used only when no file is a quotation.
  const cand = files.slice(0, MAX_READS - 1);
  const body: MailFile | null = String(mail.text || '').trim().length >= 20 ? { index: -1, filename: 'quotation-email.txt', mime: 'text/plain', bytes: new TextEncoder().encode(mail.text) } : null;
  const readings = await Promise.all([...cand, ...(body ? [body] : [])].map((f) => deps.read(f, open).catch((): Reading => ({ verdict: 'unread', proposal: null }))));
  const quotes: { f: MailFile; r: Reading }[] = cand.map((f, i) => ({ f, r: readings[i] })).filter((x) => isQuotation(x.r));
  const unread = cand.filter((_f, i) => readings[i].verdict === 'unread');
  // A body the model could not read is left to email_triage as correspondence (no reply from here during an outage).
  if (!quotes.length && body && isQuotation(readings[cand.length])) quotes.push({ f: body, r: readings[cand.length] });
  // A request number the quotation itself prints (read by the model) counts when it is one of HIS open requests; any other
  // number (his own quote number) is not a request reference and never turns a one-request mail into a question (D7).
  const mine = new Set(open.map((o) => String(Number(o.rfq_no))));
  const cited = quotes.map((q) => String(q.r.proposal?.request_reference || '')).flatMap((t) => requestNumbersIn(t, /^\d{3,9}$/.test(t.trim()) ? '#' + t.trim() : '')).filter((n) => mine.has(n));
  const choice = chooseRequest(open, threaded, [...new Set([...numbers, ...cited])]);
  if (!quotes.length && files.length > cand.length) {
    // review N3: more files than MAX_READS allows, none of those read a quotation: he is told which were read, never silently
    // told "added to your profile" while his quotation may be the fifth file.
    await deps.reply(lead, to, choice.kind === 'one' ? choice.request.id : null, replyFor(lead, { kind: 'not_all_read', read: cand.map((f) => f.filename), total: files.length }));
    return { taken: [], outcome: 'not_all_read', inquiry_id: choice.kind === 'one' ? choice.request.id : null };
  }
  if (!quotes.length) {
    if (!unread.length) return nothing;
    // NOT READ, NOT LOST, NOT PRICED BY CODE: the files stay on the profile path (stored and listed for review); he is told.
    await deps.reply(lead, to, choice.kind === 'one' ? choice.request.id : null,
      replyFor(lead, { kind: 'unread', request: choice.kind === 'one' ? choice.request : null, files: unread.map((f) => f.filename) }));
    return { taken: [], outcome: 'unread', inquiry_id: choice.kind === 'one' ? choice.request.id : null };
  }
  const taken = quotes.map((q) => q.f.index).filter((i) => i >= 0);
  if (choice.kind !== 'one') {
    await deps.reply(lead, to, null, replyFor(lead, choice.kind === 'ask' ? { kind: 'ask', choice } : { kind: 'none' }));
    return { taken, outcome: choice.kind, inquiry_id: null };
  }
  const [first, ...rest] = quotes;
  const result = await deps.submit({ lead_id: lead.id, inquiry_id: choice.request.id, file_b64: b64(first.f.bytes), filename: first.f.filename, mime: first.f.mime,
    reading: { proposal: first.r.proposal, extracted_by_model: first.r.extracted_by_model ?? null } });
  await deps.reply(lead, to, choice.request.id, replyFor(lead, { kind: 'to_confirm', request: choice.request, file: first.f.filename, result, extra: rest.map((r) => r.f.filename), unread: unread.map((f) => f.filename) }));
  return { taken, outcome: 'to_confirm', inquiry_id: choice.request.id };
}
