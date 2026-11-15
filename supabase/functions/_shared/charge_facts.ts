// THE CHARGE'S FACTS THE ACCOUNTANT RECONCILES (accountant, 13 Nov 2026, ledger 1685). Pure, so it is tested without
// Stripe (_shared/charge_facts.test.ts). In: the PaymentIntent read with expand[]=latest_charge.balance_transaction, and that
// balance transaction. Out: the columns public.fn_accountant_reconciles_reveal compares (chargeFacts), and paid_at, the
// moment the charge succeeded, which starts the refund window (chargePaidAt; public.fn_reveal_refund_window_ends).
// A fact Stripe did not give is left out, never guessed: the reconcile then waits for it.
// deno-lint-ignore-file no-explicit-any
export function chargeFacts(pi: any, bt: any): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  const received = num(pi?.amount_received);
  if (received != null) out.stripe_amount_received_fils = received;
  if (num(bt?.amount) != null) out.stripe_bt_amount_fils = bt.amount;
  if (typeof bt?.currency === 'string' && bt.currency) out.stripe_bt_currency = String(bt.currency).toLowerCase();
  return out;
}

/**
 * The moment the charge succeeded, ISO, or null when Stripe gave none. Written in its OWN write-once update (review of
 * 13 Nov 2026, item 1): a sale that already carries paid_at (the element flow, a healed sale) must still get the figures,
 * and a figure update must never be skipped because the paid time is known.
 */
export function chargePaidAt(pi: any, bt: any): string | null {
  const paid = num(pi?.latest_charge?.created) ?? num(bt?.created);
  return paid != null && paid > 1_000_000_000 ? new Date(paid * 1000).toISOString() : null;
}

/**
 * Stripe's dispute fee and any fee it returned, in fils, from a Dispute's balance_transactions (13 Nov 2026, R3): the
 * withdrawal carries the fee; a reinstatement after a won dispute may carry it back as a negative fee.
 */
export function disputeFees(dp: any): { fee_fils: number; fee_returned_fils: number } | null {
  const bts = Array.isArray(dp?.balance_transactions) ? dp.balance_transactions : null;
  if (!bts) return null;
  let fee = 0, back = 0;
  for (const b of bts) { const f = num(b?.fee); if (f == null) continue; if (f > 0) fee += f; else back += -f; }
  return { fee_fils: fee, fee_returned_fils: back };
}

const num = (x: unknown) => (typeof x === 'number' && Number.isFinite(x) ? x : null);
