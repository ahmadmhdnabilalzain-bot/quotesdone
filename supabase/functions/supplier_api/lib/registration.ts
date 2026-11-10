// supplier_api — registration state, the post that brought the company, and proof of the e-mail.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { admin } from '../context.ts';

// AUDIT 4.2 (3 Aug 2026) ------------------------------------------------------------------
// This function used to decide the registration state itself, from registered_supplier_count()
// against pricing_config.supplier_free_count, evaluated AFTER the insert - so the test was
// "N < 1000" when N had already become 1000, and only 999 suppliers were ever free. Supplier
// #1000 came out of it simultaneously subscription_exempt=true (per fn_assign_founding_rank)
// and registration_status='due', registration_fee_due=1000. It also had no date test at all,
// so it marked suppliers 'due' - which submit_quote below refuses on - a full year before the
// contractual charging date of 1 Aug 2027. And it stamped registration_paid_at on free
// suppliers, recording a payment that never happened.
//
// The rule now lives in exactly one place: fn_supplier_registration_state(), enforced on write
// by trg_bz_supplier_registration_state on public.leads. This function no longer decides
// anything - it touches the row so the trigger derives the state, then reports what the single
// source of truth says.
// touch=false when the caller has just updated the row itself (claim): the trigger has already derived the state.
export async function setRegistration(leadId: number, touch = true) {
  if (touch) await admin.from('leads').update({ portal_updated_at: new Date().toISOString() }).eq('id', leadId);
  const { data: st, error } = await admin.rpc('fn_supplier_registration_state', { p_lead_id: leadId });
  if (error || !(st as any)?.ok) return { status: 'unknown', fee_due: 0, may_quote: true, reason: 'registration_state_unavailable' };
  const s = st as any;
  return { status: String(s.status), fee_due: Number(s.fee_due || 0), may_quote: s.may_quote !== false, founding_rank: s.founding_rank ?? null, charging_starts: s.charging_starts ?? null, reason: String(s.reason || '') };
}
// profile_ai and supplier_review were deleted from the repository and from production by the
// 137-function sweep (182308b, 7 Sep 2026); on 14 Sep get_edge_function answers "Function not found".
// Their URL returns a 404 JSON body, which the old review helper returned AS IF it were a review —
// save_profile then wrote a blank ai_review_notes and "AI check: clean" into the registration mail.
// 22 SEP 2026: both calls are REMOVED rather than guarded. A call to a function that is not deployed
// is dead code that looks alive; scripts/checks/no_function_calls_an_undeployed_function.test.mjs now
// fails the build if one comes back. Both were advisory and never gated registration.
//
// EMAIL PROOF (14 Sep 2026). login_otp records proof of e-mail ownership with an UPDATE on
// leads.claimed_by — but at sign-up no lead is claimed by that address yet (create_company or claim
// runs afterwards), so owner_email_verified stayed false for every self-registered and every invited
// supplier, and the e-mail item of the mandatory six could never be ticked. The durable proof is the
// VERIFIED login OTP in email_verifications (verified_at, not used_at: see emailProven); it is read once when
// the company becomes this account's.

// THE POST THAT BROUGHT THEM (sales_engineer with marketing, 23 Sep 2026, instruction 865). When a company
// becomes an account's (create_company or claim), the first visit's UTM the browser kept (src/lib/firstTouch.ts)
// is validated and stored by fn_marketing_first_touch_record. Attribution never blocks a registration.
export async function recordFirstTouch(leadId: number, touch: unknown): Promise<void> {
  if (!touch || typeof touch !== 'object') return;
  const r = await admin.rpc('fn_marketing_first_touch_record', { p_lead_id: leadId, p_touch: touch }).then((x) => x, (e) => ({ error: { message: String(e) } }));
  if (r.error) console.error('first touch not recorded for lead ' + leadId + ': ' + r.error.message);
}
// ONE DEFINITION (10 Nov 2026, customer_support; scripts/sql/an_email_is_proven_only_by_a_code_that_was_verified.sql): a code
// for this address that was VERIFIED (email_verifications.verified_at, set by fn_login_otp_email_verify's 'ok' path only).
// used_at is not proof: a resend and the attempt cap set it too. create_company (claim and insert) and the /portal?t= claim
// all ask this; a failed read is "not proven", never a guess.
export async function emailProven(email: string) {
  const { data, error } = await admin.rpc('fn_email_proven', { p_email: email });
  if (error) { console.error('emailProven: fn_email_proven failed —', error.message); return false; }
  return data === true;
}
