// marketing_send_gate — the send-time rules for a marketing WhatsApp message. Seat: marketing (19 Oct 2026, ruling 1184).
// 27 Oct 2026: also the invitation template text, its gate on BOTH switches and the brake, and the sender-quality rule.
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

// ---------------------------------------------------------------------------------------------------------------
// 27 OCT 2026 (marketing, ruling 1184; founder 1301 "safer to not send links"). The WhatsApp supplier invitation
// leaves only when EVERY one of these holds, read the moment the row leaves (fn_wa_supplier_invite_gate holds the
// same rules at queue time; a row queued earlier can outlive any of them). send_whatsapp uses supplierInviteGate;
// marketingGate above is the 19 Oct two-input form, kept because its test pins the opt-out and switch cases.
//   * wa_supplier_invite_golive = 'true'  -- the WhatsApp channel's own switch
//   * invite_enabled = 'true'             -- the supplier campaign's master switch (paused until a GlockApps test
//                                            shows Outlook >= 80% inbox, ledger 1312); WhatsApp never runs ahead of it
//   * no open brake finding               -- it_watch_finding 'deliverability:supplier_invite_wa' (a sender-quality
//                                            drop or a STOP-rate spike); resumed only by resolving the finding
//   * the recipient has not opted out     -- leads.whatsapp_opt = 'none' cancels instead of holding
// A missing secret is OFF. Anything but the exact string 'true' is OFF.
export type InviteGateInput = { golive?: string | null; inviteEnabled?: string | null; brakeOpen: boolean; whatsappOpt?: string | null };
export function supplierInviteGate(s: InviteGateInput): { action: 'send' | 'hold' | 'cancel'; why: string } {
  if (String(s.whatsappOpt || '') === 'none') return { action: 'cancel', why: 'the recipient opted out of WhatsApp' };
  if (String(s.golive ?? '').trim() !== 'true') return { action: 'hold', why: 'held: wa_supplier_invite_golive is not true' };
  if (String(s.inviteEnabled ?? '').trim() !== 'true') return { action: 'hold', why: 'held: invite_enabled is not true (the supplier campaign is paused)' };
  if (s.brakeOpen) return { action: 'hold', why: 'held: the WhatsApp invitation brake is on (it_watch_finding ' + WA_BRAKE_FINDING_KEY + ')' };
  return { action: 'send', why: 'every switch is on and no brake is open' };
}

// THE QUALITY-RATING BRAKE. Meta rates a sender HIGH / MEDIUM / LOW (older surfaces: GREEN / YELLOW / RED) from the
// blocks and reports its recipients file; a sender left at LOW has its messaging limit cut and can be disconnected.
// So marketing leaves only from a sender Twilio reports ONLINE with quality HIGH. Anything else -- MEDIUM, LOW, an
// unknown or absent rating, OFFLINE -- holds every invitation (fail closed). A reading below HIGH also opens the brake
// finding through fn_wa_sender_quality_record, so the hold outlives a later recovery until a person resolves it.
export const WA_BRAKE_FINDING_KEY = 'deliverability:supplier_invite_wa';
export function senderQualityOk(rating: unknown, status: unknown): boolean {
  const r = String(rating ?? '').trim().toUpperCase(); const s = String(status ?? '').trim().toUpperCase();
  return s === 'ONLINE' && (r === 'HIGH' || r === 'GREEN');
}
/** Our sender out of Twilio's GET /v2/Channels/Senders page, or null. `from` is the number, digits or +digits. */
export function pickSender(list: unknown, from: string): { sid: string; status: string; rating: string | null; limit: string | null } | null {
  const want = 'whatsapp:+' + String(from || '').replace(/\D/g, '');
  // deno-lint-ignore no-explicit-any
  const senders = ((list as { senders?: Array<Record<string, any>> } | null)?.senders) || [];
  const s = senders.find((x) => String(x?.sender_id || '').replace(/\s/g, '') === want);
  if (!s) return null;
  return { sid: String(s.sid || ''), status: String(s.status || ''), rating: s.properties?.quality_rating ?? null, limit: s.properties?.messaging_limit ?? null };
}

// THE TEMPLATE, drafted by marketing (WhatsApp templates are Claude's, never the founder's: memory
// whatsapp-templates-are-claudes). DRAFT ONLY: not submitted to Meta (the campaign is paused, ledger 1312);
// wa_template_setup action=create submits it when the go comes. MARKETING category: an invitation to join is
// promotional under Meta's rules, so it is never dressed up as UTILITY. English only (suppliers, 28 Sep). No link
// (ruling 1301): the supplier replies, or registers at the bare domain, exactly as the approved email says.
// {{1}} is the trade label and sits mid-sentence (Meta refuses a variable at either end). Two quick-reply buttons:
// "Set up my page" (a reply, handed to the sales engineer by fn_marketing_files_wa_invite_reply) and "Stop" (an
// opt-out: isStop -> fn_wa_supplier_invite_opt_out). The body still names STOP for a client that hides buttons.
export const WA_INVITE_TEMPLATE_EN =
  'Hello from QuotesDone. We connect companies in the UAE with qualified suppliers: each request for quotation reaches ' +
  'only the suppliers registered for that exact trade. We are now onboarding {{1}} suppliers ahead of our buyer launch. ' +
  'Requests that match your trade come directly to you, you choose which ones to quote on, and there is no commission ' +
  'on work you win. Registration is free for our first 1,000 suppliers. To join, reply with the trades you cover and ' +
  'our team will set up your company page for you, or register at quotesdone.com. ' +
  'If this isn\'t relevant, reply STOP and we won\'t message you again.';
export const WA_INVITE_BUTTONS: readonly { id: string; title: string }[] = [
  { id: 'supplier_invite_yes', title: 'Set up my page' },
  { id: 'supplier_invite_stop', title: 'Stop' },
];
export const WA_INVITE_SAMPLE_TRADE = 'office furniture';
/** The trade as the template variable carries it: one line, lower case, at most 60 characters; empty reads "new". */
export function waInviteTrade(trade: unknown): string {
  return String(trade ?? '').replace(/[_-]+/g, ' ').replace(/\s+/g, ' ').trim().toLowerCase().slice(0, 60) || 'new';
}
/** The text one recipient reads. */
export const renderWaInvite = (trade: unknown) => WA_INVITE_TEMPLATE_EN.replace('{{1}}', waInviteTrade(trade));
