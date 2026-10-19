// marketing_send_gate — the send-time rules for a marketing WhatsApp message. Seat: marketing (19 Oct 2026, ruling 1184).
//
// The queue routine (fn_wa_supplier_invite_queue) already refuses to queue while the switch is off or the lead opted
// out, but a row queued earlier can outlive either. send_whatsapp therefore re-reads both the moment a row leaves.
// One list, MARKETING_TYPES, is shared with the SQL opt-out (fn_wa_supplier_invite_opt_out cancels the same types).

export const MARKETING_TYPES: readonly string[] = ['supplier_invite_wa'];
export const isMarketingType = (t: string | null | undefined) => MARKETING_TYPES.includes(String(t || ''));

/** 'send' | 'hold' (switch off: stays queued, never sent) | 'cancel' (the recipient opted out). A missing secret is off. */
export function marketingGate(golive: string | null | undefined, whatsappOpt: string | null | undefined): 'send' | 'hold' | 'cancel' {
  if (String(whatsappOpt || '') === 'none') return 'cancel';
  return String(golive ?? '').trim() === 'true' ? 'send' : 'hold';
}

// "STOP" in any case, with surrounding punctuation, whitespace or emoji-free decoration, in English or Arabic.
const STOP_WORDS = ['stop', 'unsubscribe', 'stopall', 'end', 'cancel', 'opt out', 'optout',
  'إيقاف', 'ايقاف', 'توقف', 'أوقف', 'اوقف', 'الغاء', 'إلغاء', 'إلغاء الاشتراك', 'الغاء الاشتراك'];
const norm = (s: string) => s.normalize('NFKC').toLowerCase()
  .replace(/[ً-ْـ]/g, '')            // Arabic diacritics and tatweel
  .replace(/[^\p{L}\p{N}\s]/gu, ' ').replace(/\s+/g, ' ').trim();
const STOPS = new Set(STOP_WORDS.map(norm));
/** True when the whole message is an opt-out word (not a sentence that merely contains one). */
export const isStop = (body: string | null | undefined) => STOPS.has(norm(String(body || '')));
