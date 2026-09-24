// reasoned_books — what an expense document IS, who issued it, and what a bank line IS: reasoned, never
// word-matched. Seat: accountant. 23 Sep 2026, founder_instruction 886-903 (decision points 63-66).
//
// BEFORE: resend_inbound's isReceiptish (a subject/sender regex) decided whether an email was a receipt;
// bank_statement_parse's isBankStatement (/mashreq/ and /statement/) decided whether it was a statement;
// receipt_parse's parsePeriod (/annual|monthly|renew/) decided the cadence and vendorFromAddress + VENDOR_NAMES
// decided the vendor from the sender's domain; and in SQL a description regex (gl_settings bank_charge_pattern,
// owner_transfer_pattern, bank_interest_pattern), a vendor regex (decision_policy accountant_meta_invoice_vendor_pattern,
// accountant_renewal_vendor_patterns) and `ilike '%stripe%'` decided what a bank line or a booked expense WAS.
//
// NOW: three decisions through think() (plan, context, knowledge, a choice among named options, validated):
//   documentKind   accountant.document_kind   bank statement / Meta ads invoice / the renewal of a named licence or
//                                             domain (it_expiry) / a monthly, annual or one-off receipt / other
//   receiptVendor  accountant.receipt_vendor  one of the vendors the books already know, else the name as written
//   bankLineKind   accountant.bank_line       bank charge / owner transfer / bank interest / Stripe payout / other
// What stays deterministic is FORMAT: the amount beside its currency mark, a date, a VAT figure, a TRN's
// digits (_shared/receipt_parse.ts), the statement's rows and balances (_shared/bank_statement_parse.ts).
//
// UNDER THE HOLD think() returns status 'held' and files the question in the accountant's queue. Nothing is
// booked on a word guess: the email is held for the bookkeeper (fn_receipt_hand_to_bookkeeper) exactly as an
// unreadable receipt is, and a bank line keeps kind NULL, which every booking routine skips. When the hold
// lifts, replayHeld reasons the question and deliverBooks (below, called from reasoned_delivery.ts) re-runs
// the accountant's expense_sweep for that email, or hands a non-expenses-mailbox email to the bookkeeper; a
// bank line's kind is applied in SQL by fn_reason_apply_accountant__bank_line.
import { think, type ThinkDeps } from './think.ts';
import type { HeldRow, ThinkResult } from './think.ts';
import type { Reasoned } from './reasoned_decisions.ts';

export type Period = 'monthly' | 'annual' | 'one_off';
export type Renewal = { item: string; kind: string; expires_on: string | null };
export type ExpenseMail = {
  emailId: string; from: string; to: string; subject: string; text: string; docText?: string; filenames: string[];
  mailbox: 'expenses' | 'other'; providerEmailId?: string | null;
  dryRun?: boolean;       // the accountant sweep's dry run reasons but files nothing in the queue
};

const RECEIPTS: Record<string, { period: Period; meaning: string }> = {
  receipt_monthly: { period: 'monthly', meaning: 'a receipt or invoice for something billed every month (a monthly subscription or plan)' },
  receipt_annual: { period: 'annual', meaning: 'a receipt or invoice for something billed once a year' },
  receipt_one_off: { period: 'one_off', meaning: 'a receipt or invoice for a single purchase or usage charge that does not repeat on a schedule' },
};

/** The question every expense decision reads: the envelope, the note and the document text, as given. */
export function mailQuestion(m: ExpenseMail): string {
  return [`From: ${m.from}`, `To: ${m.to}`, `Subject: ${m.subject}`, m.filenames.length ? `Attachments: ${m.filenames.join(', ')}` : '',
    '', m.text, m.docText ? '\n[text of the attached document]\n' + m.docText : ''].filter((x) => x !== '').join('\n').slice(0, 8000);
}
const subjectOf = (m: ExpenseMail) => ({ email_id: m.emailId, mailbox: m.mailbox, provider_email_id: m.providerEmailId ?? null, from: m.from, subject: m.subject.slice(0, 200) });

/** What the document is. Option ids: bank_statement | meta_ads_invoice | renewal:<it_expiry.item> | receipt_* | other. */
export async function documentKind(deps: ThinkDeps, m: ExpenseMail, renewals: Renewal[], register: { vendor: string; cadence: string }[]): Promise<Reasoned<string>> {
  const result = await think(deps, {
    seat: 'accountant', surface: 'accountant.document_kind', question: mailQuestion(m),
    dedupeKey: 'expense_kind:' + m.emailId, subject: subjectOf(m), queueWhenHeld: !m.dryRun,
    context: { audience: 'internal', profile: { company: 'QuotesDone (UAE)', subscription_register: register } },
    decision: {
      name: 'expense_document_kind',
      options: [
        { id: 'bank_statement', meaning: "a statement of the company's own bank account listing its transactions and balances (for example the monthly Mashreq e-statement), not a receipt" },
        { id: 'meta_ads_invoice', meaning: 'a receipt or invoice from Meta (Facebook / Instagram) for advertising the company bought' },
        ...renewals.map((x) => ({ id: 'renewal:' + x.item, meaning: `a receipt paying the registration or renewal of the company's ${x.kind} "${x.item}"${x.expires_on ? ' (it expires ' + x.expires_on + ')' : ''}` })),
        ...Object.entries(RECEIPTS).map(([id, r]) => ({ id, meaning: r.meaning })),
        { id: 'other', meaning: "not a document of the company's own spending: a supplier's company document, a question, a newsletter, a notice with nothing charged, or anything else" },
      ],
    },
  });
  return { value: result.status === 'answered' ? result.decision?.choice ?? null : null, result };
}

/** What a reasoned document kind means for the books. null for bank_statement / other. */
export function readingOf(kind: string): { period: Period; readAs: string; renewsItem: string | null } | null {
  if (kind in RECEIPTS) return { period: RECEIPTS[kind].period, readAs: kind, renewsItem: null };
  if (kind === 'meta_ads_invoice') return { period: 'one_off', readAs: kind, renewsItem: null };
  // our own option id, built above: 'renewal:' + it_expiry.item
  if (kind.startsWith('renewal:')) return { period: 'annual', readAs: 'renewal', renewsItem: kind.slice('renewal:'.length) };
  return null;
}

/** Who issued it and was paid. One of the vendors the books already carry, else (a second decision) the name as written. */
export async function receiptVendor(deps: ThinkDeps, m: ExpenseMail, known: string[]): Promise<Reasoned<string>> {
  // one option per vendor, the first spelling the books carry (Github / GitHub are one company)
  const byKey = new Map<string, string>();
  for (const v of known) if (v && v.trim() && !byKey.has(v.trim().toLowerCase())) byKey.set(v.trim().toLowerCase(), v.trim());
  const names = [...byKey.values()].slice(0, 60);
  const q = mailQuestion(m);
  const first = await think(deps, {
    seat: 'accountant', surface: 'accountant.receipt_vendor', question: q,
    dedupeKey: 'expense_vendor:' + m.emailId, subject: subjectOf(m), queueWhenHeld: !m.dryRun,
    context: { audience: 'internal' },
    decision: {
      name: 'vendor',
      options: [
        ...names.map((v) => ({ id: v, meaning: `the company that issued this and was paid is ${v} (a product bought through another platform is that product's company, not the platform)` })),
        { id: 'another_vendor', meaning: 'a company that is not in this list' },
      ],
    },
  });
  if (first.status !== 'answered') return { value: null, result: first };
  if (first.decision?.choice !== 'another_vendor') return { value: first.decision?.choice ?? null, result: first };
  const named = await think(deps, {
    seat: 'accountant', surface: 'accountant.receipt_vendor', question: q,
    dedupeKey: 'expense_vendor_name:' + m.emailId, subject: subjectOf(m), queueWhenHeld: !m.dryRun,
    context: { audience: 'internal', conversation: [{ role: 'seat', text: q }] },
    decision: { name: 'vendor_name', fields: [{ key: 'vendor', question: 'the name of the company that issued this and was paid, exactly as the document writes it' }] },
  });
  const v = named.status === 'answered' ? String(named.decision?.fields?.vendor?.value ?? '').trim() : '';
  return { value: v ? v.slice(0, 120) : null, result: named };
}

export const BANK_KINDS = ['bank_charge', 'owner_transfer', 'bank_interest', 'stripe_payout', 'other'] as const;
export type BankLine = { id: number; value_date: string; description: string; amount_aed: number; account: string };

/** What one statement line is. The sign of the amount is a fact the reasoning is given, not the answer. */
export async function bankLineKind(deps: ThinkDeps, line: BankLine, owner: string | null): Promise<Reasoned<string>> {
  const result = await think(deps, {
    seat: 'accountant', surface: 'accountant.bank_line',
    question: `Bank statement line (${line.account}), ${line.value_date}: "${line.description}", ${line.amount_aed < 0 ? 'debit' : 'credit'} of AED ${Math.abs(line.amount_aed)}.`,
    dedupeKey: 'bank_line:' + line.id, subject: { line_id: line.id },
    context: { audience: 'internal', profile: { licence_holder: owner } },
    decision: {
      name: 'bank_line_kind',
      options: [
        { id: 'bank_charge', meaning: "a fee, commission or maintenance charge the bank took, or the VAT the bank charged on its own fee (a debit)" },
        { id: 'owner_transfer', meaning: `money the licence holder${owner ? ' (' + owner + ')' : ''} moved from his own account into the company (a credit; capital unless he says it is a loan)` },
        { id: 'bank_interest', meaning: 'interest the bank credited on the balance' },
        { id: 'stripe_payout', meaning: "a payout from Stripe of the company's card takings" },
        { id: 'other', meaning: 'anything else: a customer or supplier payment, a refund, a transfer to someone else' },
      ],
    },
  });
  return { value: result.status === 'answered' ? result.decision?.choice ?? null : null, result };
}

/** The accountant's hourly duty: every statement line not yet reasoned is reasoned (or held), a few per tick. */
export async function reasonBankLines(deps: ThinkDeps, limit = 10): Promise<{ reasoned: number; held: number; error?: string }> {
  const { data, error } = await deps.rpc('fn_accountant_bank_lines_to_reason', { p_limit: limit });
  if (error) return { reasoned: 0, held: 0, error: error.message };
  let reasoned = 0, held = 0;
  for (const line of (data?.lines ?? []) as BankLine[]) {
    const r = await bankLineKind(deps, line, data?.owner ?? null);
    if (r.value === null) { held++; continue; }
    const { error: e } = await deps.rpc('fn_accountant_bank_line_reasoned', { p_line_id: line.id, p_kind: r.value, p_by: 'reasoning' });
    if (e) return { reasoned, held, error: e.message };
    reasoned++;
  }
  return { reasoned, held };
}

// ── the replay: a held expense question, reasoned after the hold lifts ──────────────────────────
export interface BooksIO {
  /** POST accountant {action:'expense_sweep', email_id} under the seat's own credential; the verdict for that email. */
  accountantSweep(emailId: string): Promise<{ ok: boolean; found?: boolean; verdict?: string | null; err?: string }>;
  /** A non-expenses-mailbox email reasoned to be an expense document: the bookkeeper takes it. */
  receiptToBookkeeper(providerEmailId: string, why: string): Promise<{ ok: boolean; err?: string }>;
}
export type BooksDelivery = { delivered: boolean; via: 'accountant_sweep' | 'bookkeeper' | 'none'; detail?: string };

/** null when the surface is not an expense one. */
export async function deliverBooks(row: HeldRow, r: ThinkResult, io: BooksIO): Promise<BooksDelivery | null> {
  if (row.surface !== 'accountant.document_kind' && row.surface !== 'accountant.receipt_vendor') return null;
  const s = row.subject ?? {};
  const choice = r.decision?.choice ?? null;
  if (row.surface === 'accountant.document_kind' && (choice === 'other' || choice === null)) {
    // Mail to the expenses mailbox that is not an expense document still needs a person's eye (it was held, not handed
    // over, while it waited); mail to another mailbox already took the supplier-document path.
    if (s.mailbox === 'expenses' && s.provider_email_id) {
      const x = await io.receiptToBookkeeper(String(s.provider_email_id), 'Reasoned after the model hold: this email to the expenses mailbox is not a document of the company\'s own spending. ' + r.answer.slice(0, 300));
      return { delivered: x.ok, via: 'bookkeeper', detail: x.err };
    }
    return { delivered: false, via: 'none', detail: 'reasoned: not an expense document; it stays where it was filed' };
  }
  // A webhook with no Resend id (svix:<id>) cannot be found by the sweep, which walks Resend's history by id.
  if (s.mailbox === 'expenses' && s.email_id && !String(s.email_id).startsWith('svix:')) {
    const x = await io.accountantSweep(String(s.email_id));
    // delivered only when the sweep found the email and took it in; anything else is said, never counted as done
    const done = x.ok && x.found !== false && ['booked', 'already_booked', 'bank_statement'].includes(String(x.verdict));
    return { delivered: done, via: 'accountant_sweep', detail: done ? undefined : (x.err ?? (x.found === false ? 'the sweep found no such email' : 'sweep verdict: ' + x.verdict)) };
  }
  if (s.provider_email_id) {
    const x = await io.receiptToBookkeeper(String(s.provider_email_id), 'Reasoned after the model hold: this email is ' + (choice ?? 'an expense document') + '. ' + r.answer.slice(0, 300));
    return { delivered: x.ok, via: 'bookkeeper', detail: x.err };
  }
  return { delivered: false, via: 'none', detail: 'the held row names no email' };
}

// deno-lint-ignore no-explicit-any
type Admin = any;
export function liveBooksIO(admin: Admin): BooksIO {
  const sec = async (k: string) => { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; };
  return {
    accountantSweep: async (emailId) => {
      const { timedFetch } = await import('./timed_fetch.ts');
      const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
      const r = await timedFetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/accountant', {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + key, apikey: key },
        body: JSON.stringify({ __secret: await sec('cred_fn_accountant'), action: 'expense_sweep', email_id: emailId }),
      }, 55_000);
      const j = await r.json().catch(() => ({}));
      if (!r.ok || j?.ok === false) return { ok: false, err: String(j?.error ?? r.status) };
      const m = Array.isArray(j?.messages) ? j.messages.find((x: { email_id?: string }) => x.email_id === emailId) : null;
      return { ok: true, found: j?.found !== false && !!m, verdict: m?.verdict ?? null };
    },
    receiptToBookkeeper: async (providerEmailId, why) => {
      const { data: row } = await admin.from('inbound_messages').select('id').eq('provider_email_id', providerEmailId).order('id', { ascending: false }).limit(1).maybeSingle();
      if (!row?.id) return { ok: false, err: 'inbound_message_not_found' };
      const { error } = await admin.rpc('fn_receipt_hand_to_bookkeeper', { p_inbound_id: row.id, p_review_ids: [], p_reason: why.slice(0, 600) });
      return error ? { ok: false, err: error.message } : { ok: true };
    },
  };
}
