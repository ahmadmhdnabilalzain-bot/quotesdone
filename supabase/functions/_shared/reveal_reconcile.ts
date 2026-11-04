// A PAID REVEAL WITH NO SALE IS FOUND AND RECORDED WITHIN THE HOUR (accountant, 3 Nov 2026).
//
// A reveal is recorded from three places (_shared/reveal_sale.ts): stripe_checkout element_pay, element_settle after
// 3-D Secure, and stripe_webhook invoice.paid. Since #1835 the webhook answers Stripe 500 when it cannot read the
// PaymentIntent behind the invoice, so Stripe delivers it again; but Stripe stops retrying after about three days.
// If all three fail, the customer has paid and public.transactions holds nothing. Nothing looked for that.
//
// This is the sweep, pure so it is tested without Stripe or a database (reveal_reconcile.test.ts). The accountant
// runtime (supabase/functions/accountant, action 'reveal_reconcile') gives it Stripe and the books; the accountant's
// seat duty accountant.reveal_reconcile (scripts/sql/a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour.sql)
// calls that every hour and files a finding for whatever it could not record.
//
//   1. LIST what Stripe says was paid in the last N days and names a quote: paid invoices (both reveal flows put
//      metadata.quote_id on the invoice) and succeeded PaymentIntents (the hosted Checkout flow also puts it on the
//      PaymentIntent). A supplier payment (metadata.kind supplier_*) is never a reveal.
//   2. MATCH each against the books by stripe_invoice_id, then payment_ref. A match is recorded; nothing is written.
//   3. RECORD each unmatched payment through recordRevealSale, the one insert every other path uses. Only a pi_ is a
//      payment reference (#1835: recording in_... made the real pi_ look like a second payment), so a payment whose
//      PaymentIntent cannot be read is 'failed' and tried again next hour, never recorded under the invoice id.
//      A payment refunded in full is 'refunded' (nothing to record); a partial refund is 'refunded_unrecorded', for
//      the accountant to judge. A quote already sold under a different PaymentIntent is 'second_payment' (refund).
//
// BOUNDED, PER MODE, LIVE FIRST: at most maxPages pages of 100 per list, at most maxAttempts unmatched payments looked
// at (each costs one or two Stripe reads) and maxRecords sales written per run; the rest are 'deferred' to the next run.
// Newest first, so a payment that can never be recorded (already a finding) cannot starve a new one, and a test-mode
// demo payment whose quote a teardown deleted never spends live's budget (review of #1841). Nothing paid within
// graceSeconds is touched (the other three paths are still running).
// A QUOTE ALREADY SOLD is never handed to recordRevealSale: by then neither the invoice nor the PaymentIntent matched
// that sale, so this is a different payment ('second_payment'), and recording would stamp this invoice id onto the first
// sale (reveal_sale.ts fills an empty stripe_invoice_id) and hide it from every later run (review of #1841).
// IDEMPOTENT: a match writes nothing, and recordRevealSale is idempotent on quote_id (transactions.quote_id is unique).
// deno-lint-ignore-file no-explicit-any
import type { SaleArgs } from './reveal_sale.ts';

export type Mode = 'live' | 'test';

export type Candidate = {
  key: string;                       // the invoice id; the PaymentIntent id when Stripe holds no invoice for it
  mode: Mode;
  livemode: boolean;
  source: 'invoice' | 'payment_intent';
  quoteId: string;
  invoiceId: string | null;
  paymentIntent: string | null;
  customerId: string | null;
  customerEmail: string | null;
  baseFee: number;
  processingFee: number;
  totalCharged: number;
  amountFils: number;
  currency: string;
  paidAt: number | null;             // unix seconds
};

export type OutcomeKind =
  | 'recorded'               // the books already hold it: nothing written
  | 'recovered'              // it had no sale; recordRevealSale wrote one
  | 'second_payment'         // the quote is sold under a different PaymentIntent: this one is for a CEO refund
  | 'refunded'               // never recorded and refunded in full: nothing to record
  | 'refunded_unrecorded'    // never recorded and partly refunded: the accountant decides
  | 'test_mode_not_demo'     // a TEST-mode payment whose quote is not a demo account's: never written (stripe_webhook's rule); a finding
  | 'failed'                 // could not be recorded; tried again next run
  | 'deferred';              // over this run's bound; next run

export type Outcome = Candidate & { outcome: OutcomeKind; transactionId: string | null; error: string | null };

export type Tx = { id: string; quote_id: string | null; payment_ref: string | null; stripe_invoice_id: string | null };

export type ModeRead = { basis: 'measured' | 'not_configured' | 'unreadable'; invoices: number; payment_intents: number; truncated: boolean; reason?: string };

export type SweepDeps = {
  modes: Mode[];
  /** One page of a Stripe list (GET), or null when Stripe could not be read. */
  list: (mode: Mode, path: string) => Promise<{ data: any[]; has_more: boolean } | null>;
  /** The PaymentIntent behind an invoice that did not carry it, or null. */
  invoicePayment: (mode: Mode, invoiceId: string) => Promise<string | null>;
  /** The PaymentIntent itself, or null when it cannot be read. */
  readPayment: (mode: Mode, pi: string) => Promise<{ status: string; amount_received: number; amount_refunded: number; fee_fils?: number | null; fee_details?: unknown } | null>;
  /** Sales whose stripe_invoice_id, payment_ref or quote_id is one of these. */
  findTransactions: (q: { invoices: string[]; refs: string[]; quotes: string[] }) => Promise<Tx[]>;
  /** Whether the quote's inquiry belongs to a demo account (fn_inquiry_is_demo). Asked only for TEST-mode payments; false when it cannot be told. */
  isDemoQuote: (quoteId: string) => Promise<boolean>;
  /** recordRevealSale. */
  record: (a: SaleArgs) => Promise<{ id: string; created: boolean; other_payment?: string } | { error: string }>;
  /** What Stripe kept on a sale this sweep wrote (stripe_webhook's recordStripeFee does the same); best-effort. */
  recordFee?: (txId: string, feeFils: number, details: unknown) => Promise<void>;
};

export type SweepOptions = { days: number; nowSec: number; maxPages?: number; maxRecords?: number; maxAttempts?: number; graceSeconds?: number };

const isPi = (s: unknown): s is string => typeof s === 'string' && /^pi_[A-Za-z0-9_]+$/.test(s);
const isIn = (s: unknown): s is string => typeof s === 'string' && /^in_[A-Za-z0-9_]+$/.test(s);
const idOf = (x: any): string => (typeof x === 'string' ? x : String(x?.id || ''));
const num = (x: unknown, d = 0) => (Number.isFinite(Number(x)) && x !== null && x !== '' ? Number(x) : d);
const notSupplier = (md: any) => !/^supplier_/.test(String(md?.kind || ''));

export function clampDays(d: unknown): number {
  const n = Math.floor(Number(d));
  return Number.isFinite(n) ? Math.min(90, Math.max(1, n)) : 30;
}

/** A paid invoice naming a quote, as a candidate; null for anything else. */
export function invoiceCandidate(inv: any, mode: Mode): Candidate | null {
  const md = inv?.metadata || {};
  const quoteId = String(md.quote_id || '');
  if (!quoteId || !isIn(inv?.id) || inv?.status !== 'paid' || !notSupplier(md)) return null;
  // The PAID attempt: an invoice can list a canceled attempt before the one that paid it (review of #1841).
  const pays = (inv?.payments?.data || []).filter((p: any) => isPi(idOf(p?.payment?.payment_intent)));
  const pi = idOf((pays.find((p: any) => p?.status === 'paid') || pays[0])?.payment?.payment_intent);
  const amountFils = num(inv.amount_paid);
  const totalCharged = amountFils / 100;
  const baseFee = md.base_fee != null && md.base_fee !== '' ? num(md.base_fee) : totalCharged;
  return {
    key: String(inv.id), mode, livemode: inv.livemode === true, source: 'invoice', quoteId,
    invoiceId: String(inv.id), paymentIntent: isPi(pi) ? pi : null,
    customerId: md.customer_id ? String(md.customer_id) : null,
    customerEmail: inv.customer_email ? String(inv.customer_email).toLowerCase() : null,
    baseFee, processingFee: num(md.processing_fee), totalCharged, amountFils,
    currency: String(inv.currency || 'aed'), paidAt: num(inv?.status_transitions?.paid_at, num(inv.created)) || null,
  };
}

/** A succeeded PaymentIntent naming a quote (the hosted Checkout flow), as a candidate; null for anything else. */
export function paymentIntentCandidate(p: any, mode: Mode): Candidate | null {
  const md = p?.metadata || {};
  const quoteId = String(md.quote_id || '');
  if (!quoteId || !isPi(p?.id) || p?.status !== 'succeeded' || !notSupplier(md)) return null;
  const amountFils = num(p.amount_received, num(p.amount));
  // No card-fee line may be charged (Cabinet Res. 66/2023 Art. 5(3), 24 Sep 2026): what was paid is the base fee.
  return {
    key: String(p.id), mode, livemode: p.livemode === true, source: 'payment_intent', quoteId,
    invoiceId: null, paymentIntent: String(p.id), customerId: md.customer_id ? String(md.customer_id) : null,
    customerEmail: p.receipt_email ? String(p.receipt_email).toLowerCase() : null,
    baseFee: amountFils / 100, processingFee: 0, totalCharged: amountFils / 100, amountFils,
    currency: String(p.currency || 'aed'), paidAt: num(p.created) || null,
  };
}

/**
 * One candidate per payment. A PaymentIntent an invoice already names is that invoice's payment. An invoice that
 * did not say which PaymentIntent paid it takes the only PaymentIntent of the same quote and mode that no other
 * invoice names; a PaymentIntent left over is a payment of its own (possibly a second one).
 */
export function mergeCandidates(invoices: Candidate[], intents: Candidate[]): Candidate[] {
  const out = invoices.map((c) => ({ ...c }));
  const named = new Set(out.map((c) => c.paymentIntent).filter(Boolean) as string[]);
  const loose = intents.filter((p) => !named.has(p.paymentIntent!));
  const rest: Candidate[] = [];
  for (const p of loose) {
    const open = out.filter((c) => !c.paymentIntent && c.quoteId === p.quoteId && c.mode === p.mode);
    const same = loose.filter((q) => q.quoteId === p.quoteId && q.mode === p.mode);
    if (open.length === 1 && same.length === 1) {
      open[0].paymentIntent = p.paymentIntent;
      if (!open[0].customerEmail) open[0].customerEmail = p.customerEmail;
    } else rest.push(p);
  }
  return [...out, ...rest];
}

/** The sale that already holds this payment, by invoice and then by payment reference; null when none does. */
export function matchSale(c: Candidate, txs: Tx[]): Tx | null {
  if (c.invoiceId) {
    const t = txs.find((x) => x.stripe_invoice_id === c.invoiceId);
    if (t) return t;
  }
  const refs = [c.paymentIntent, c.invoiceId].filter(Boolean) as string[];
  return txs.find((x) => x.payment_ref != null && refs.includes(x.payment_ref)) || null;
}

async function listAll(deps: SweepDeps, mode: Mode, base: string, maxPages: number) {
  const items: any[] = []; let after = ''; let truncated = false;
  for (let page = 0; ; page++) {
    if (page >= maxPages) { truncated = true; break; }
    const r = await deps.list(mode, base + (after ? '&starting_after=' + encodeURIComponent(after) : ''));
    if (!r) return null;
    items.push(...(r.data || []));
    if (!r.has_more || !r.data?.length) break;
    after = idOf(r.data[r.data.length - 1]);
  }
  return { items, truncated };
}

export async function sweepReveals(deps: SweepDeps, o: SweepOptions): Promise<{ modes: Record<string, ModeRead>; outcomes: Outcome[]; checked: number; too_recent: number }> {
  const maxPages = Math.max(1, o.maxPages ?? 5);
  const maxRecords = Math.max(0, o.maxRecords ?? 25);
  const maxAttempts = Math.max(0, o.maxAttempts ?? 50);
  const grace = Math.max(0, o.graceSeconds ?? 900);
  const since = o.nowSec - clampDays(o.days) * 86400;
  const modes: Record<string, ModeRead> = {};
  let all: Candidate[] = [];
  for (const mode of deps.modes) {
    const inv = await listAll(deps, mode, `invoices?status=paid&limit=100&created[gte]=${since}&expand[]=data.payments`, maxPages);
    const pis = inv ? await listAll(deps, mode, `payment_intents?limit=100&created[gte]=${since}`, maxPages) : null;
    if (!inv || !pis) { modes[mode] = { basis: 'unreadable', invoices: 0, payment_intents: 0, truncated: false, reason: 'a Stripe list could not be read' }; continue; }
    const ic = inv.items.map((x) => invoiceCandidate(x, mode)).filter(Boolean) as Candidate[];
    const pc = pis.items.map((x) => paymentIntentCandidate(x, mode)).filter(Boolean) as Candidate[];
    modes[mode] = { basis: 'measured', invoices: ic.length, payment_intents: pc.length, truncated: inv.truncated || pis.truncated };
    all = all.concat(mergeCandidates(ic, pc));
  }
  const ready = all.filter((c) => c.paidAt == null || c.paidAt <= o.nowSec - grace);
  const tooRecent = all.length - ready.length;
  const txs = ready.length ? await deps.findTransactions({
    invoices: [...new Set(ready.map((c) => c.invoiceId).filter(Boolean) as string[])],
    refs: [...new Set(ready.flatMap((c) => [c.paymentIntent, c.invoiceId]).filter(Boolean) as string[])],
    quotes: [...new Set(ready.map((c) => c.quoteId))],
  }) : [];

  const outcomes: Outcome[] = [];
  const budget: Record<string, { attempts: number; records: number }> = {};
  const seenPi = new Set<string>();
  const done = (c: Candidate, outcome: OutcomeKind, transactionId: string | null = null, error: string | null = null) =>
    outcomes.push({ ...c, outcome, transactionId, error });
  const order = (c: Candidate) => (c.mode === 'live' ? 0 : 1);
  for (const c of [...ready].sort((a, b) => order(a) - order(b) || (b.paidAt ?? 0) - (a.paidAt ?? 0))) {
    const held = matchSale(c, txs);
    if (held) { done(c, 'recorded', held.id); continue; }
    // A TEST-MODE PAYMENT MAY ONLY EVER TOUCH DEMO DATA (stripe_webhook's testEventIsDemo; review of #1841): one whose
    // quote is not provably a demo account's is never recorded and spends none of the budget. An unanswerable check is "no".
    if (c.mode === 'test') {
      let demo = false;
      try { demo = (await deps.isDemoQuote(c.quoteId)) === true; } catch (_e) { demo = false; }
      if (!demo) { done(c, 'test_mode_not_demo'); continue; }
    }
    const b = (budget[c.mode] ??= { attempts: 0, records: 0 });
    if (b.attempts >= maxAttempts) { done(c, 'deferred'); continue; }
    b.attempts++;
    let pi = c.paymentIntent;
    if (!pi && c.invoiceId) pi = await deps.invoicePayment(c.mode, c.invoiceId);
    if (!isPi(pi)) { done(c, 'failed', null, 'the PaymentIntent behind the invoice could not be read'); continue; }
    // One payment, one outcome: a hosted-Checkout invoice and its PaymentIntent can both reach here (review of #1841).
    if (seenPi.has(pi)) continue;
    seenPi.add(pi);
    const cc = { ...c, paymentIntent: pi };
    // Recorded since the books were read (a racing path), by the PaymentIntent the invoice did not carry.
    const late = txs.find((t) => t.payment_ref === pi);
    if (late) { done(cc, 'recorded', late.id); continue; }
    const pay = await deps.readPayment(c.mode, pi);
    if (!pay) { done(cc, 'failed', null, 'the PaymentIntent could not be read'); continue; }
    if (pay.status !== 'succeeded') { done(cc, 'failed', null, 'the PaymentIntent is ' + pay.status + ', not succeeded'); continue; }
    if (pay.amount_refunded > 0) {
      done(cc, pay.amount_refunded >= pay.amount_received ? 'refunded' : 'refunded_unrecorded');
      continue;
    }
    const before = txs.find((t) => t.quote_id === c.quoteId) || null;
    if (before) {
      // A Checkout Session reference (cs_...) names no payment, so whether this is that sale's payment cannot be told.
      if (/^cs_/.test(String(before.payment_ref || ''))) {
        done(cc, 'failed', before.id, 'the quote\'s sale carries Checkout Session reference ' + before.payment_ref + ', so whether this payment is that sale cannot be told');
      } else done(cc, 'second_payment', before.id);
      continue;
    }
    if (b.records >= maxRecords) { done(cc, 'deferred'); continue; }
    b.records++;
    let res;
    try {
      res = await deps.record({ quoteId: c.quoteId, customerId: c.customerId, baseFee: c.baseFee, processingFee: c.processingFee,
        totalCharged: c.totalCharged, paymentRef: pi, invoiceId: c.invoiceId || '' });
    } catch (e) { res = { error: String((e as Error)?.message || e) }; }
    if ('error' in res) { done(cc, 'failed', null, String(res.error).slice(0, 300)); continue; }
    // The sale exists now: a second payment of the same quote later in this run is seen as one (review of #1841).
    txs.push({ id: res.id, quote_id: c.quoteId, payment_ref: pi, stripe_invoice_id: c.invoiceId });
    if (res.other_payment) { done(cc, 'second_payment', res.id); continue; }
    done(cc, res.created ? 'recovered' : 'recorded', res.id);
    if (res.created && deps.recordFee && typeof pay.fee_fils === 'number') {
      try { await deps.recordFee(res.id, pay.fee_fils, pay.fee_details ?? null); } catch (_e) { /* a record, never a reason to fail */ }
    }
  }
  return { modes, outcomes, checked: ready.length, too_recent: tooRecent };
}

/** What the SQL record routine keeps: every outcome except a plain match, which needs no row. */
export function reportable(outcomes: Outcome[]): Record<string, unknown>[] {
  return outcomes.filter((x) => x.outcome !== 'recorded').map((x) => ({
    key: x.key, mode: x.mode, livemode: x.livemode, source: x.source, quote_id: x.quoteId, invoice_id: x.invoiceId,
    payment_intent: x.paymentIntent, customer_id: x.customerId, customer_email: x.customerEmail, amount_fils: x.amountFils,
    currency: x.currency, paid_at: x.paidAt, outcome: x.outcome, transaction_id: x.transactionId, error: x.error,
  }));
}
