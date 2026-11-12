// NO LIVE CARD IS CHARGED WHILE THE STRIPE LIVE HOLD IS ON (it_engineer, 12 Nov 2026; final audit F4, ledger 1642).
//
// MEASURED 11 Nov 2026: app_secrets stripe_secret_key is a live-class key (prefix read only) and stripe_checkout and
// supplier_pay hand it to every account that is not a reserved demo address, so the first real reveal or supplier payment
// would have opened a live Stripe checkout. The founder: Stripe goes live LAST. One switch holds every path that creates
// a live charge: stripe_checkout (the reveal, Checkout and the Payment Element) and supplier_pay (the registration fee and
// the dues checkout). It is FAIL-SAFE: only the exact value 'off' lets a live charge through. Absent, 'on', unreadable (the
// callers' secret() reads a failed read as '') or anything else is held. Demo accounts never reach it: they are served the TEST key pair (demo_identity.ts
// stripeKeyNames) and the hold applies to mode 'live' only, so the e2e reveal on the test key is unaffected.
//   to open live payments:  app_secrets stripe_live_hold = 'off'
export const STRIPE_LIVE_HOLD_KEY = 'stripe_live_hold';

/** True unless the switch reads exactly 'off' (case and spaces ignored). */
export function liveChargeHeld(value: unknown): boolean {
  return String(value ?? '').trim().toLowerCase() !== 'off';
}

/** The hold binds a LIVE charge only; a demo account's test-mode payment is never held. */
export function holdApplies(mode: 'live' | 'test', switchValue: unknown): boolean {
  return mode === 'live' && liveChargeHeld(switchValue);
}

// What the person is told (customers read English or Arabic; suppliers English only, ruling 1008). 503, as every other
// "payment cannot be taken right now" answer of these two functions: nothing was charged and nothing is lost.
export const HELD_FOR_CUSTOMER = {
  ok: false, error: 'payment_opens_soon', code: 'payment_opens_soon',
  message: 'Card payment opens shortly. Your quotes are safe, and our team has been told and will be in touch with you.',
  message_ar: 'الدفع بالبطاقة يُفتح قريبًا. عروضك محفوظة، وفريقنا على علم وسيتواصل معك.',
};
export const HELD_FOR_SUPPLIER = {
  ok: false, error: 'payment_opens_soon', code: 'payment_unavailable',
  message: 'Card payment opens shortly. Nothing has been charged, and our team has been told and will be in touch with you.',
};

/** The CEO seat holds the person who tried to pay: customer_support's review.requested (the registered kind email_triage
 *  uses for "someone has heard nothing"), once per subject (fn_seat_handoff keys on type and subject; a demo party files none). */
export async function handHeldPaymentToCeo(
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ error: { message: string } | null }>,
  subjectTable: string, subjectId: string, detail: Record<string, unknown>,
): Promise<string | null> {
  try {
    const { error } = await rpc('fn_seat_handoff', {
      p_from: 'customer_support', p_to: 'ceo', p_type: 'review.requested', p_subject_table: subjectTable, p_subject_id: subjectId,
      p_payload: { ...detail, held_by: STRIPE_LIVE_HOLD_KEY,
        ask: 'A real account tried to pay while live Stripe payments are held (app_secrets stripe_live_hold). Nothing was charged. Tell the person when payment opens; live payments open when the founder sets stripe_live_hold to off.' },
    });
    return error ? error.message : null;
  } catch (e) { return String((e as Error)?.message || e); }
}
