// THE CHARGE'S FACTS THE ACCOUNTANT RECONCILES (accountant, 13 Nov 2026, ledger 1685). Pure, so it is tested without
// Stripe (_shared/charge_facts.test.ts). In: the PaymentIntent read with expand[]=latest_charge.balance_transaction, and that
// balance transaction. Out: the columns public.fn_accountant_reconciles_reveal compares, and paid_at, the moment the
// charge succeeded, which starts the refund window (public.fn_reveal_refund_window_ends through trg_reveal_window).
// A fact Stripe did not give is left out, never guessed: the reconcile then waits for it.
// deno-lint-ignore-file no-explicit-any
export function chargeFacts(pi: any, bt: any): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  const n = (x: unknown) => (typeof x === 'number' && Number.isFinite(x) ? x : null);
  const received = n(pi?.amount_received);
  if (received != null) out.stripe_amount_received_fils = received;
  if (n(bt?.amount) != null) out.stripe_bt_amount_fils = bt.amount;
  if (typeof bt?.currency === 'string' && bt.currency) out.stripe_bt_currency = String(bt.currency).toLowerCase();
  const paid = n(pi?.latest_charge?.created) ?? n(bt?.created);
  if (paid != null && paid > 1_000_000_000) out.paid_at = new Date(paid * 1000).toISOString();
  return out;
}
