// ONE DOOR TO STRIPE'S REFUND API, BOUND TO THE MODE THE PAYMENT WAS MADE IN (14 Sep 2026, accountant).
//
// MEASURED: refunds_api and accountant execute_refunds each carried their own copy of "refund this
// payment", and both read app_secrets.stripe_secret_key unconditionally. stripe_checkout and
// stripe_confirm take a demo account's payment with stripe_secret_key_test (demo_identity.ts,
// stripeKeyNames). So a refund of a TEST payment would have been sent to LIVE Stripe with the live key.
// Stripe would most likely have answered "no such payment_intent", but "most likely refused by the
// other side" is not a control, and the path that decides whether money leaves must not depend on it.
//
// THE RULE NOW, in one place both callers use:
//   1. the key follows the payer, derived on the server exactly as checkout derived it when it took
//      the money: a demo payer is refunded only with stripe_secret_key_test, a real payer only with
//      stripe_secret_key. A missing key is "not configured", never a fall-through to the other one;
//   2. the stored key must itself be of that mode (sk_test_ / sk_live_, or rk_ restricted keys);
//   3. the payment is read back from Stripe with that key BEFORE anything is refunded, and its
//      livemode must equal the mode. A payment Stripe cannot find with this key (it lives in the other
//      mode) or reports in the other mode is refused, and POST /v1/refunds is never called.
import { stripeKeyNames } from './demo_identity.ts';

export type StripeMode = 'live' | 'test';
export type RefundDeps = {
  secret: (key: string) => Promise<string | undefined>;
  fetch?: typeof fetch;
};
// deno-lint-ignore no-explicit-any
export type RefundOk = { ok: true; refund: any; pi: string; mode: StripeMode };
// sent: the POST /v1/refunds request left this process. uncertain: it did, and its outcome is not known
// (a network error, a timeout, a 5xx, an idempotency conflict) -- money may have moved. A caller that
// reserved money must never release it on an uncertain answer; confirmRefundOutcome asks Stripe first.
// deno-lint-ignore no-explicit-any
export type RefundRefused = { ok: false; error: string; mode?: StripeMode; sent?: boolean; uncertain?: boolean; pi?: string; refund?: any };

/**
 * THE ONE IDEMPOTENCY KEY FOR A PAYMENT'S REFUND. Keyed on the transaction, never on a refunds row id:
 * two case rows for one payment (a retry after a failure, or a row written by another path) must reach
 * Stripe as the SAME request, so Stripe itself returns the first refund instead of issuing a second.
 * (PR #640 review: the retired refunds_api 'resolve' used qd_refund_<transaction> and execute_refunds
 * used qd_refund_<refund row>, so one reveal could be refunded twice.)
 */
// A SECOND LEGITIMATE REFUND OF ONE PAYMENT (re-review, 14 Sep 2026): the CEO's mismatch playbook may
// top an under-refund up, or retry a refund Stripe failed. Each is its own Stripe request with its own
// deterministic key, still rooted in the transaction: `topup<refund row>` for a top-up (the row is
// reserved, capped, before Stripe is called) and `retry<fix handoff>` for a retry (a fresh key, because
// reusing the failed attempt's key would return the failed refund). The table caps the total at what
// the customer paid, whatever the key.
export function refundIdempotencyKey(transactionId: string | number, attempt?: string): string {
  const id = String(transactionId ?? '').trim();
  if (!id) throw new Error('a refund idempotency key needs the transaction id');
  const a = String(attempt ?? '').trim();
  if (a && !/^(topup|retry)\d+$/.test(a)) throw new Error('a refund attempt suffix is topup<n> or retry<n>, not ' + a);
  return 'qd_refund_' + id + (a ? '_' + a : '');
}

/** The mode a stored Stripe key belongs to, read off its prefix; null when it is not a Stripe secret. */
export function keyMode(sk: unknown): StripeMode | null {
  const m = /^(?:sk|rk)_(live|test)_/.exec(String(sk ?? ''));
  return m ? (m[1] as StripeMode) : null;
}

/** The secret key for this payer's mode, or a refusal. Never the other mode's key. */
export async function refundKey(deps: RefundDeps, demoPayer: boolean): Promise<{ ok: true; sk: string; mode: StripeMode } | RefundRefused> {
  const { secret: name, mode } = stripeKeyNames(demoPayer);
  const sk = (await deps.secret(name)) || '';
  if (!sk) return { ok: false, mode, error: `${name} is not set. A ${mode} payment is refunded only with the ${mode} key, so nothing was sent to Stripe.` };
  if (keyMode(sk) !== mode) return { ok: false, mode, error: `${name} does not hold a ${mode} key (it reads as ${keyMode(sk) ?? 'not a Stripe secret key'}), so nothing was sent to Stripe.` };
  return { ok: true, sk, mode };
}

/**
 * Refund `amountFils` of the payment `ref` (a pi_… or a cs_…) for a payer, idempotent on `idem`.
 * `demoPayer` must come from the payer's account on the server (isDemoEmail on customers.email),
 * never from the request.
 */
export async function stripeRefund(
  deps: RefundDeps,
  o: { demoPayer: boolean; ref: string; amountFils: number; idem: string; metadata?: Record<string, string> },
): Promise<RefundOk | RefundRefused> {
  const f = deps.fetch ?? fetch;
  if (!o.ref) return { ok: false, error: 'no Stripe payment reference on record, so there is no charge to refund' };
  if (!(o.amountFils > 0)) return { ok: false, error: 'no amount to refund' };
  const k = await refundKey(deps, o.demoPayer);
  if (!k.ok) return k;
  const auth = { Authorization: 'Bearer ' + k.sk };
  const live = k.mode === 'live';

  // Read the payment back with the key we are about to refund with, and check the mode it lives in.
  let pi = o.ref;
  try {
    if (o.ref.startsWith('cs_')) {
      const sr = await f('https://api.stripe.com/v1/checkout/sessions/' + encodeURIComponent(o.ref), { headers: auth });
      const sj = await sr.json().catch(() => ({}));
      if (!sr.ok || !sj?.payment_intent) return { ok: false, mode: k.mode, error: `checkout session ${o.ref} is not readable with the ${k.mode} key (${String(sj?.error?.message || sr.status)}); refusing rather than refunding across modes` };
      if (Boolean(sj.livemode) !== live) return { ok: false, mode: k.mode, error: `checkout session ${o.ref} is a ${sj.livemode ? 'live' : 'test'} payment but the payer is ${k.mode}; refused` };
      pi = String(sj.payment_intent);
    }
    const pr = await f('https://api.stripe.com/v1/payment_intents/' + encodeURIComponent(pi), { headers: auth });
    const pj = await pr.json().catch(() => ({}));
    if (!pr.ok) return { ok: false, mode: k.mode, error: `payment ${pi} is not readable with the ${k.mode} key (${String(pj?.error?.message || pr.status)}); it was made in the other mode or does not exist, and nothing was refunded` };
    if (Boolean(pj.livemode) !== live) return { ok: false, mode: k.mode, error: `payment ${pi} is a ${pj.livemode ? 'live' : 'test'} payment but the payer is ${k.mode}; refused` };
  } catch (e) {
    return { ok: false, mode: k.mode, error: 'network error reading the payment from Stripe: ' + String((e as Error)?.message || e) };
  }

  const form = new URLSearchParams();
  form.set('payment_intent', pi);
  form.set('amount', String(Math.round(o.amountFils)));
  form.set('reason', 'requested_by_customer');
  for (const [key, v] of Object.entries(o.metadata || {})) form.set('metadata[' + key + ']', v);
  // Our key rides on the refund itself, so a lost answer can be matched on Stripe afterwards.
  form.set('metadata[qd_idempotency_key]', o.idem);
  try {
    const r = await f('https://api.stripe.com/v1/refunds', {
      method: 'POST',
      headers: { ...auth, 'Content-Type': 'application/x-www-form-urlencoded', 'Idempotency-Key': o.idem },
      body: form.toString(),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) {
      // 4xx is Stripe refusing the request; 5xx and 409 (an idempotent request still in flight) say
      // nothing certain about whether a refund exists.
      const uncertain = r.status >= 500 || r.status === 409;
      return { ok: false, mode: k.mode, sent: true, uncertain, pi, error: 'Stripe ' + (uncertain ? 'could not confirm' : 'refused') + ' the refund (HTTP ' + r.status + '): ' + String(j?.error?.message || '').slice(0, 250) };
    }
    // 'pending' is a normal state for some methods; 'failed' and 'canceled' are not.
    if (j?.status && !['succeeded', 'pending'].includes(String(j.status))) {
      return { ok: false, mode: k.mode, sent: true, uncertain: false, pi, refund: j, error: 'Stripe refund came back ' + String(j.status) };
    }
    return { ok: true, refund: j, pi, mode: k.mode };
  } catch (e) {
    return { ok: false, mode: k.mode, sent: true, uncertain: true, pi, error: 'network error or timeout calling Stripe refunds: ' + String((e as Error)?.message || e) };
  }
}

/**
 * NEVER RELEASE A RESERVATION BLIND (PR #640 re-review). After a refused or unanswered stripeRefund,
 * ask Stripe what actually exists under our key -- the refund by id if one came back, otherwise the
 * payment's refunds matched on metadata.qd_idempotency_key -- and answer:
 *   settle  : Stripe holds a succeeded/pending refund under our key; record it, do not release;
 *   release : confirmed that no money moved (nothing was sent, Stripe refused, or the refund failed);
 *   hold    : cannot confirm either way; keep the reservation and try again under the SAME key.
 */
export async function confirmRefundOutcome(
  deps: RefundDeps,
  o: { demoPayer: boolean; ref: string; idem: string },
  res: RefundRefused,
  // deno-lint-ignore no-explicit-any
): Promise<{ outcome: 'settle'; refund: any; pi: string } | { outcome: 'release'; error: string } | { outcome: 'hold'; error: string }> {
  if (!res.sent) return { outcome: 'release', error: res.error };
  const f = deps.fetch ?? fetch;
  const k = await refundKey(deps, o.demoPayer);
  if (!k.ok) return { outcome: 'hold', error: 'cannot read Stripe to confirm: ' + k.error };
  const auth = { Authorization: 'Bearer ' + k.sk };
  const pi = res.pi || o.ref;
  // deno-lint-ignore no-explicit-any
  let found: any = null;
  try {
    if (res.refund?.id) {
      const r = await f('https://api.stripe.com/v1/refunds/' + encodeURIComponent(String(res.refund.id)), { headers: auth });
      if (!r.ok) return { outcome: 'hold', error: 'Stripe did not answer for refund ' + res.refund.id + ' (HTTP ' + r.status + '): ' + res.error };
      found = await r.json();
    } else {
      const r = await f('https://api.stripe.com/v1/refunds?limit=100&payment_intent=' + encodeURIComponent(pi), { headers: auth });
      if (!r.ok) return { outcome: 'hold', error: 'Stripe did not list the refunds on ' + pi + ' (HTTP ' + r.status + '): ' + res.error };
      const j = await r.json();
      // deno-lint-ignore no-explicit-any
      found = (j?.data || []).find((x: any) => x?.metadata?.qd_idempotency_key === o.idem) || null;
    }
  } catch (e) {
    return { outcome: 'hold', error: 'could not reach Stripe to confirm: ' + String((e as Error)?.message || e) + '; ' + res.error };
  }
  if (found && ['succeeded', 'pending'].includes(String(found.status))) return { outcome: 'settle', refund: found, pi };
  if (found && ['failed', 'canceled'].includes(String(found.status))) return { outcome: 'release', error: 'Stripe shows the refund ' + found.status + ': ' + res.error };
  if (found) return { outcome: 'hold', error: 'Stripe shows the refund ' + String(found.status) + '; waiting: ' + res.error };
  return res.uncertain ? { outcome: 'hold', error: 'no refund under our key yet, and the attempt was not answered: ' + res.error }
                       : { outcome: 'release', error: res.error };
}
