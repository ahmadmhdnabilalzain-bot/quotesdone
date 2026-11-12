// mobileState — the registration form's mobile, e-mail and WhatsApp answer are the SERVER's, read again before Submit lists
// any of them as missing (11 Nov 2026, customer_support; free supplier registration certification, run 1, J4 mobile).
//
// MEASURED ON PRODUCTION. The form reads kyc 'state' once, on mount, through the portal's call(), which gives up at 20 s. When
// that one read is lost (timeout, network, a platform 5xx) the form kept its initial "not verified, no WhatsApp answer" for the
// rest of its life, and Submit, judging from that copy, said "Still needed to register: Verified mobile number, Your answer on
// your WhatsApp number" to a supplier the server had verified: a dead end, because nothing on the form reads kyc again.
//   * J4 run 1: the harness held the form's read while its own kyc whatsapp_choose ran 54,590 ms at the edge (16:00:13 to
//     16:01:07.720Z); the browser aborted the read at 20 s (both browser kyc 'state' calls status 0, neither reached the server),
//     and Submit refused at 16:01:57 although kyc 'state' had answered phone_verified + whatsapp.opt from 16:01:08.
//   * Browsers, the 24 h before (function_edge_logs, kyc, the 18-byte {"action":"state"} body): 24,856 ms at 10 Nov
//     19:58:39Z, 43,808 ms at 11 Nov 04:43:32Z, 10,280 ms at 02:25:47Z. Two of the three are past the 20 s abort. (All three
//     were our own harness browsers in the cloud container, AS "Anthropic, PBC"; kyc's handler ran 118-256 ms in each and the
//     rest was the request waiting on an isolate before the handler started: docs/reports/2026-11-11-kyc-slow-requests.md.)
// So:
//   * a lost read is asked again (readKycState), and a lost answer never overwrites what an earlier answer said;
//   * Submit asks the server before it lists the mobile, the e-mail or the WhatsApp answer as missing (kycItemsMissing), as
//     #1947 made it ask the row for the licence; when even that read is lost, the form lists none of the three and lets
//     save_profile, which enforces the same items on the row (supplier_api/actions/profile.ts missing_required), decide;
//   * a verify_sms whose answer was lost asks kyc whether the number is verified before it says "wrong code".
// Prevented by: src/components/portal/supplier/mobileState.test.mjs.
import { answerWasLost } from './licenceReceived.ts';
import { waSignupSettled } from '../whatsappChoiceText.ts';

export type KycState = {
  ok?: unknown; code?: unknown; phone?: unknown;
  phone_verified?: unknown; email_verified?: unknown;
  whatsapp?: { opt?: unknown; [k: string]: unknown } | null;
  [k: string]: unknown;
} | null | undefined;

/** True only for kyc's own answer to 'state' (ok: true). A timeout, a network loss or a refusal is not a state. */
export const kycAnswered = (k: KycState): boolean => !!(k && k.ok === true);

/**
 * Reads kyc 'state' up to `tries` times, `waitMs` apart, while the answer is LOST (never on our own refusal). The answered
 * state, or null when none came back. `onLost` is told after each lost try, so the form need not wait for the last one.
 */
export async function readKycState(read: () => Promise<KycState>,
    opts: { tries?: number; waitMs?: number; sleep?: (ms: number) => Promise<void>; onLost?: () => void } = {}): Promise<KycState> {
  const tries = opts.tries ?? 3; const waitMs = opts.waitMs ?? 2000;
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((ok) => setTimeout(ok, ms)));
  for (let i = 0; i < tries; i++) {
    if (i) await sleep(waitMs);
    let k: KycState = null;
    try { k = await read(); } catch (_e) { k = null; }
    if (kycAnswered(k)) return k;
    if (!answerWasLost(k as { ok?: unknown; code?: unknown } | null)) return null;   // our own refusal: asking again changes nothing
    if (opts.onLost) opts.onLost();
  }
  return null;
}

export type KycItem = 'reg_mobile' | 'reg_email' | 'reg_whatsapp';

/** The items the form's own copy says are missing, in save_profile's order. */
export function localKycMissing(local: { phoneVerified: boolean; emailVerified: boolean; wa: unknown }): KycItem[] {
  const m: KycItem[] = [];
  if (!local.phoneVerified) m.push('reg_mobile');
  if (!local.emailVerified) m.push('reg_email');
  if (!waSignupSettled(local.wa as never)) m.push('reg_whatsapp');
  return m;
}

/**
 * What Submit may say is missing of the three, from the server's answer. With no answer (lost) nothing is listed here: the
 * form does not know, so it says nothing and save_profile decides on the row. With an answer, the answer decides.
 */
export function kycItemsMissing(server: KycState): KycItem[] {
  if (!kycAnswered(server)) return [];
  const k = server as Exclude<KycState, null | undefined>;
  return localKycMissing({ phoneVerified: k.phone_verified === true, emailVerified: k.email_verified === true, wa: k.whatsapp });
}

// WHAT SETTINGS SAYS ABOUT HIS MOBILE NUMBER (12 Nov 2026, sales_engineer, built by it_engineer; founder ruling 1670: "I just did the
// WhatsApp confirmation and WhatsApp is a phone, so how?"). Measured on production for his company: one code, delivered on WhatsApp at
// 19:53:42Z and accepted at 19:53:56Z, set owner_phone_verified AND whatsapp_verified_at for the same number; nothing set either back.
// Yet Settings' Account card said "Phone ... not verified" beside "Verified WhatsApp number": the card drew the `settings` answer the
// dashboard warmed in the background when it first rendered (tabPrefetch, handed to the tab's first mount however old), while the
// WhatsApp card read kyc 'state' fresh. So the card now follows kyc's own answer whenever it has one (read on mount and after every
// WhatsApp change), and names the channel the number was proven on: one vocabulary, "Mobile number", never "Phone".
//   'verified_wa': verified, and the same number carries a WhatsApp code he typed back (the code proves both; opt 'other')
//   'verified':    verified (by text message or call)
//   'unverified':  not verified yet
export type MobileStatus = 'verified_wa' | 'verified' | 'unverified';
const digits = (v: unknown): string => String(v ?? '').replace(/\D/g, '').replace(/^0+/, '').replace(/^971/, '');
export function mobileStatus(o: { settingsVerified: unknown; kyc: KycState; phone: unknown }): MobileStatus {
  const k = kycAnswered(o.kyc) ? o.kyc : null;
  const verified = k ? k.phone_verified === true : o.settingsVerified === true;
  if (!verified) return 'unverified';
  // Only a code typed back writes opt 'other' (kyc verifiedPatch); "Yes, same number" (choosePatch 'same') sets whatsapp_verified_at
  // with NO code (review of #1984, c2), so it names no channel: a number verified by SMS then answered "same" reads plain "verified".
  const wa = k?.whatsapp as { opt?: unknown; verified?: unknown; phone?: unknown } | null | undefined;
  const mine = digits(o.phone || k?.phone);
  return wa && wa.opt === 'other' && wa.verified === true && mine !== '' && digits(wa.phone) === mine ? 'verified_wa' : 'verified';
}
