// THE MICROSOFT 365 SENDING LANE (5 Oct 2026, founder ledger 1115; Assigned: it_engineer (mail path) + marketing (copy)).
//
// MEASURED: GlockApps placed 54% of the supplier invitation in spam at Outlook/Hotmail/Yahoo/AOL. Resend's shared
// SES IPs sat on 11 blocklists and the invitation left from a new subdomain with no reputation. The company's own
// Microsoft 365 tenant (MX quotesdone-com.mail.protection.outlook.com) has neither problem, so the invitation can
// leave from a real mailbox there, through Microsoft Graph with client credentials.
//
// The same guarantees as invite_lane.ts, one provider over:
//   OFF (app_secrets.invite_m365_enabled, seeded 'false')  nothing changes and no call is made.
//   ON  supplier_invite, supplier_invite_seed and supplier_invite_nudge to a supplier leave from the mailbox in
//       app_secrets.invite_m365_mailbox (seeded 'supplier@quotesdone.com'). Nothing else ever does: never a
//       sign-up code, never a notice. A seed row of kind M365_SEED_KIND takes this lane even with the switch off,
//       so scripts/invitation_inbox_check.mjs --lane=m365 can placement-test it before anyone turns it on.
//   ON but MS_TENANT_ID / MS_CLIENT_ID / MS_CLIENT_SECRET missing, the token refused, or Graph refusing a send:
//       the row is HELD (queued, not_before moved on), NEVER sent through Resend, and ONE it_engineer finding
//       (M365_REFUSED_ISSUE) says why. The secrets are read by name and never printed, logged or put in a finding.
//   CAP the lane's invitations and nudges share invite_daily_cap with the Resend lanes, and the mailbox never sends
//       more than M365_HARD_CEILING a UTC day of anything (Exchange Online's outbound limits are per mailbox).
//
// LIST-UNSUBSCRIBE (checked against Microsoft Learn, 5 Oct 2026): the JSON message's internetMessageHeaders accept
// only custom headers whose names begin "x-"/"X-"; Graph refuses List-Unsubscribe there. sendMail ALSO accepts the
// whole message as base64 MIME (Content-Type: text/plain), and a MIME message carries any RFC 5322 header. So this
// lane sends MIME: List-Unsubscribe and List-Unsubscribe-Post are real headers, and the body still ends with a
// "reply stop" line (STOP_LINE, the body's own last line) for any client that ignores them.
// sendMail answers 202 with no body, so the provider id we keep is our own Message-ID, written into the MIME:
// notifications.provider_message_id = 'm365:<...>' (the prefix also lets the hard ceiling count this lane's sends).
// Pure apart from the injected fetch and finding writer, so m365_lane.test.ts replays every branch offline.
import { isLaneType, LANE_CAPPED_TYPES } from './invite_lane.ts';
import { invitationCopyLint, type CopyRule } from './invitation_copy.ts';

export const M365_SECRET_NAMES = ['MS_TENANT_ID', 'MS_CLIENT_ID', 'MS_CLIENT_SECRET'] as const;
export const M365_REFUSED_ISSUE = 'invite_m365_lane_refused';
export const M365_SEED_KIND = 'invite_m365_seed';
export const M365_HARD_CEILING = 150;
export const M365_ID_PREFIX = 'm365:';
// Written onto notifications.provider_message_id (with the Message-ID) BEFORE the sendMail POST and replaced by the
// M365_ID_PREFIX id once it is recorded sent (send_outbox/index.ts, 3 Nov 2026). Graph has no idempotency key, so a row that
// comes back carrying this was handed to Graph by a run that could not record the outcome, and is never posted again.
// It does not begin with M365_ID_PREFIX, so the lane's daily ceiling (like 'm365:%') never counts it.
// prevented by: supabase/functions/send_outbox/drill_send_faults.test.ts
export const M365_PENDING_PREFIX = 'm365-pending:';
export const HOLD_M365_MS = 30 * 60_000;

export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export type FileFinding = (args: Record<string, unknown>) => Promise<unknown>;
/** fn_it_engineer_finding_close(p_issue_key, p_note). */
export type CloseFinding = (issueKey: string, note: string) => Promise<unknown>;
export type M365 = { active: boolean; refused: boolean; mailbox: string; token: string; why: string };
export const M365_OFF: M365 = { active: false, refused: false, mailbox: '', token: '', why: 'invite_m365_enabled is not true' };

// A SUPPLIER'S REPLY IS ANSWERED FROM THE MAILBOX IT WROTE TO (sales_engineer, 3 Nov 2026). MEASURED: invitation
// 125102 to lead 19820 left this lane from supplier@ (in its Sent Items); the supplier answered supplier@
// (inbound_messages 1829); email_triage's answer, notification 125121 (inbound_reply, to_role NULL), went through
// Resend From info@quotesdone.com, so supplier@'s Outlook showed the supplier's reply and then nothing. All 3
// inbound_reply rows to suppliers since the switch went on (117599, 121564, 125121) went that way. fn_inbox_send
// (scripts/sql/a_supplier_reply_goes_back_from_its_own_mailbox.sql, its own PR, applied after this deploys) writes to_role
// 'supplier' and the lead for a known supplier, and this kind when the message it answers came INTO the
// lane's mailbox; only a row of this kind is carried here. A reply to a supplier who wrote to another mailbox keeps
// the Resend route.
export const M365_REPLY_KIND = 'supplier_mailbox_reply';
/** A reply in a conversation that arrived in the lane's mailbox (fn_inbox_send writes the kind). */
export function isMailboxReply(o: { type: unknown; kind: unknown }): boolean {
  return o.type === 'inbound_reply' && o.kind === M365_REPLY_KIND;
}
/** The recipient side m365Carries reads. A known supplier's reply is to_role 'supplier'. A reply to an unknown sender
 *  who wrote to the supplier mailbox stays to_role NULL (email_triage answers that sender as a customer, in their
 *  language, so the supplier rules must not act on it) and is still that mailbox's conversation. Never another role. */
export function laneSide(r: { to_role: unknown; type: unknown; kind: unknown }): boolean {
  return r.to_role === 'supplier' || (r.to_role == null && isMailboxReply(r));
}

/** Whether this row is carried by the Microsoft 365 lane at all (before the lane's state is looked at). */
export function m365Carries(o: { enabled: boolean; type: unknown; kind: unknown; supplierSide: boolean }): boolean {
  if (o.supplierSide && isMailboxReply(o)) return o.enabled;
  if (!o.supplierSide || !isLaneType(o.type)) return false;
  if (o.type === 'supplier_invite_seed' && o.kind === M365_SEED_KIND) return true;
  return o.enabled;
}

export function switchOn(v: string | undefined): boolean { return String(v || '').trim().toLowerCase() === 'true'; }

/** A refusal message with every secret value removed, whatever the provider echoed back. */
export function scrub(s: string, secrets: string[]): string {
  let out = String(s || '');
  for (const v of secrets) if (v && v.length >= 4) out = out.split(v).join('[redacted]');
  return out.slice(0, 300);
}

/** The one it_engineer finding for a refused lane (token or send). Carries no secret value, only which names are set. */
export function refusalFinding(mailbox: string, refusal: string, secretsPresent: string[]): Record<string, unknown> {
  return {
    p_issue_key: M365_REFUSED_ISSUE,
    p_title: 'The Microsoft 365 invitation lane is on but cannot send; supplier invitations are held until it can',
    p_where: 'edge function send_outbox (send_outbox/m365_lane.ts)', p_blast: 'internal', p_affected: 1,
    p_evidence: { invite_m365_mailbox: mailbox, refusal, secrets_present: secretsPresent,
      effect: 'supplier_invite, supplier_invite_seed and supplier_invite_nudge held (queued, not_before moved on); never sent through Resend; all other mail unaffected' },
    p_ruled_out: [], p_undetermined: [], p_raised_by: 'it_engineer',
  };
}

/**
 * Decide the lane for one run: token in hand, or refused with one finding. Called only when a row in the batch is
 * carried by the lane, so a normal poll with the switch off makes no call.
 */
export async function resolveM365(o: {
  needed: boolean; mailbox: string | undefined; env: (k: string) => string | undefined; fetchFn: Fetch; fileFinding: FileFinding;
}): Promise<M365> {
  if (!o.needed) return M365_OFF;
  const mailbox = String(o.mailbox || '').trim().toLowerCase();
  const [tenant, client, secret] = M365_SECRET_NAMES.map((k) => String(o.env(k) || '').trim());
  const refuse = async (status: string): Promise<M365> => {
    const why = scrub(status, [secret, client]);
    try {
      await o.fileFinding(refusalFinding(mailbox, why, M365_SECRET_NAMES.filter((k) => !!String(o.env(k) || '').trim())));
    } catch (_e) { /* the hold still happens; the reason is also in the returned why */ }
    return { active: false, refused: true, mailbox, token: '', why: 'refused: ' + why };
  };
  if (!/^[a-z0-9._+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(mailbox)) return await refuse(`invite_m365_mailbox '${mailbox}' is not an address`);
  const missing = M365_SECRET_NAMES.filter((k) => !String(o.env(k) || '').trim());
  if (missing.length) return await refuse('edge secret(s) not set: ' + missing.join(', '));
  let r: Response;
  try {
    r = await o.fetchFn(`https://login.microsoftonline.com/${encodeURIComponent(tenant)}/oauth2/v2.0/token`, {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: client, client_secret: secret, scope: 'https://graph.microsoft.com/.default', grant_type: 'client_credentials' }).toString(),
    });
  } catch (e) { return await refuse('the token endpoint did not answer: ' + String((e as Error)?.message || e)); }
  let j: { access_token?: string; error?: string; error_description?: string } = {};
  try { j = await r.json(); } catch { /* handled below */ }
  if (!r.ok || !j.access_token) return await refuse(`token refused (HTTP ${r.status}${j.error ? ', ' + j.error : ''})`);
  // A token alone does not close M365_REFUSED_ISSUE: Graph may still refuse the send. graphSend closes it on a 2xx.
  return { active: true, refused: false, mailbox, token: j.access_token, why: 'token issued' };
}

/** Hold this carried row? 'unverified' = lane refused; 'cap' = shared invite cap or the mailbox ceiling reached. */
export function holdForM365(o: { m365: M365; type: unknown; cappedSentToday: number; inviteCap: number; m365SentToday: number }): 'unverified' | 'cap' | null {
  if (o.m365.refused || !o.m365.active) return 'unverified';
  if (o.m365SentToday >= M365_HARD_CEILING) return 'cap';
  if (LANE_CAPPED_TYPES.includes(o.type as string) && o.cappedSentToday >= Math.min(o.inviteCap, M365_HARD_CEILING)) return 'cap';
  return null;
}

/** What send_outbox does with a carried row. A mailbox reply is never held and never paced: invite_daily_cap is not
 *  its number (a reply is not an invitation, and holdForM365 caps only LANE_CAPPED_TYPES); the mailbox's 150/day
 *  ceiling is, and when the lane is refused, inactive or at that ceiling the reply goes through Resend exactly as it
 *  did before this lane carried replies. An invitation is held or paced as before. */
export type M365Step = 'send' | 'hold' | 'pace' | 'resend';
export function m365Step(o: { reply: boolean; hold: 'unverified' | 'cap' | null; sentThisRun: number }): M365Step {
  if (o.hold) return o.reply ? 'resend' : 'hold';
  if (!o.reply && paceM365(o.sentThisRun)) return 'pace';
  return 'send';
}
/** Graph refused a send: an invitation is held (never sent through Resend); a reply goes through Resend in the same run. */
export function afterRefusal(reply: boolean): 'hold' | 'resend' { return reply ? 'resend' : 'hold'; }

/** The reply as written (email_triage / the Inbox signs its own text), threaded on the supplier's Message-ID. */
export function replyMail(row: { subject?: unknown; body?: unknown; in_reply_to?: unknown }): { subject: string; text: string; inReplyTo: string; bad: string[] } {
  const text = String(row.body || '').trim();
  return { subject: String(row.subject || '').trim() || 'Re: your message', text, inReplyTo: String(row.in_reply_to || '').trim(),
    bad: text ? [] : ['the reply body is empty'] };
}

// ---------------------------------------------------------------- the plain-text invitation (marketing)
// (The wording itself was replaced the same day by variant A, below; the rules in this paragraph still hold.)
// THE FOUNDER'S EMAIL (27 Oct 2026, founder_instruction 1298-1301): "the wording sounds fine to me"; pitched the way
// a very large company writes to a business partner; "safer to not send links"; the signature is "just QuotesDone
// Technologies, Dubai, UAE". So: NO link in the body (quotesdone.com is plain text, no scheme, no path), no HTML frame,
// English only, never the word AI, no street address and no permit or licence number, and the body closes with the
// reply-"stop" line. The opt-out is that line plus the List-Unsubscribe headers (m365Mime). The invitation, its
// day-3/7/14 nudge and the morning placement seed all send this one text, so the placement test measures the real
// email. Free registration for the first 1,000 suppliers matches knowledge/COMPANY_CANON.md and carries no date.
/** Anything a mail client would turn into a link: a scheme, a www. host, or a host followed by a path. */
export const ANY_LINK = /https?:\/\/|\bwww\.|\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}\/[^\s]*/i;
export const STOP_LINE = 'If this isn\'t relevant, reply "stop" and we won\'t contact you again.';
// 2 Nov 2026 (it_engineer, ledger 1445): a person and company in the display name; low-strength evidence only (the vendor
// posts say a role address is flagged; nothing from Microsoft or Yahoo). The comma needs the quoted form (RFC 5322).
export const M365_FROM_NAME = '"Ahmad Alzain, QuotesDone"';
export const SIGNATURE = 'Best regards,\nAhmad Alzain\nFounder, QuotesDone\nQuotesDone Technologies · Dubai, UAE';

// 19 Oct 2026 (marketing + it_engineer, ledger 1113: no campaign email in spam). MEASURED (GlockApps
// 2026-10-19-02:51:47:497t, this lane): 33% inbox, Outlook/Yahoo/AOL 100% spam (EOP SCL 5), Gmail 19 of 20 in
// Promotions, SPF/DKIM/DMARC passing, no blocklist. So the content changed: a short note from a named person,
// addressed to the company and its trade, no promotional word in the subject or the opening, and the opt-out in the
// List-Unsubscribe headers plus one "reply stop" line. Since 27 Oct 2026 the body carries no link at all (above).
export type Who = { company?: string; trade?: string };
// THE GREETING READS A COMPANY NAME, NOT A PAGE TITLE (sales_engineer, 28 Oct 2026). leads.company_name is often a
// scraped page title. MEASURED on notifications 116649-116668: "Speed Blast Trading L.L.C &#8211; Top notch Industrial
// Equipments Suppliers in Dubai, UAE" reached the greeting whole (the entity map had no numeric entities, so the dash cut
// never saw a dash), "CERAMIC MEGA ... TR LLC (Manufacturer and wholesaler of any kind of porcelain tile.)" kept its
// tagline and its capitals, "NRA INTERNATIONAL" became "Nra" and "TRADING L L C" kept its spaces. So: decode every
// entity first, then cut (dash/pipe, a trailing parenthetical, a ", Dubai"/", Suppliers in ..." tail), then case, and a
// name still too long or written like a sentence gets the neutral "Hello," rather than a title.
const ENTITY: Record<string, string> = {
  amp: '&', quot: '"', apos: "'", nbsp: ' ', ndash: '–', mdash: '—', lt: '<', gt: '>', rsquo: "'", lsquo: "'", rdquo: '"', ldquo: '"',
};
const decodeOnce = (s: string) => s.replace(/&(?:#(\d{1,7})|#x([0-9a-f]{1,6})|([a-z]+));/gi, (m, dec, hex, name) => {
  if (name) return ENTITY[name.toLowerCase()] ?? m;
  const cp = dec ? parseInt(dec, 10) : parseInt(hex, 16);
  return cp > 0 && cp <= 0x10ffff ? String.fromCodePoint(cp) : m;
});
/** What follows ", " in a page title rather than a name: an emirate, the country, or a "Suppliers in ..." tagline. */
const PLACE_OR_TAGLINE = /^(?:dubai|uae|u\.a\.e|united arab emirates|abu dhabi|sharjah|ajman|ras al khaimah|fujairah|umm al quwain|al ain|jebel ali)\b|\bsuppliers?\s+in\b/i;
const LEGAL = /^(?:l\.?l\.?c\.?|fze|fzco|fzc|fz|tr|dmcc|pjsc|wll)$/i;
/** Two-letter words that are words, not acronyms, when a name is written in capitals ("AL", "CO", "OF"). */
const SHORT_WORD = new Set('AL EL OF CO BU DE LA LE DA BY TO IN ON OR AT IS AS MY UP NO DR MR MS ST HI'.split(' '));
/** Three-letter acronyms that carry a vowel. Any other three-letter token with a vowel is a word or an abbreviation and is
 *  title-cased: MEASURED on all 20,249 distinct leads.company_name (28 Oct 2026, review of #1706), keeping every 3-letter
 *  token in capitals turned GEN (258 names), ALI (89), IND, MIX, MAT, ENT, AIN, SPA, ENG, BAB and EZZ into shouting. */
const ACRONYM3 = new Set('UAE UAQ RAK MEP NRA MAF ETA ABD'.split(' '));
/** Vowel-less abbreviations that read as words, not acronyms: "Co Ltd", "Pvt", "Svcs" (MEASURED 28 Oct 2026: LTD alone
 *  is in 376 distinct names). */
const ABBREVIATION = new Set('LTD PVT SVC SVCS MKTG TRDG MFG MNFG DVLP SRVS PCKG CNTG BLDG'.split(' '));
/** Title case: a letter after anything but a letter, a digit, "_" or an apostrophe ("Gen.Trading", "Center/L.L.C",
 *  "Ronny's", "18th"). */
const word = (w: string) => w.toLowerCase().replace(/(^|[^a-z0-9_'’])([a-z])/g, (_m, p, c) => p + c.toUpperCase());
/** One token of a name written in capitals: a legal suffix or a 2-3 letter acronym stays, anything else is title-cased. */
const capsToken = (w: string) => {
  const bare = w.replace(/[^A-Za-z.]/g, '');
  if (LEGAL.test(bare)) return w.toUpperCase();
  const letters = w.replace(/[^A-Z]/g, '');
  if (letters === w && !ABBREVIATION.has(w) && ((w.length === 2 && !SHORT_WORD.has(w)) || (w.length === 3 && (ACRONYM3.has(w) || !/[AEIOUY]/.test(w))) ||
    (w.length === 4 && !/[AEIOUY]/.test(w)))) return w;
  return word(w);
};
/** One part of a hyphenated capitals token ("LLC-SPC", "HI-TECH", "AL-FUTTAIM"): a legal suffix, a known acronym or a
 *  vowel-less one stays; anything else is title-cased, so "HI" and "AL" read as words here (review of #1706). */
const hyphenPart = (w: string) => {
  if (LEGAL.test(w.replace(/[^A-Za-z.]/g, ''))) return w.toUpperCase();
  const keep = /^[A-Z]{2,4}$/.test(w) && !ABBREVIATION.has(w) && (ACRONYM3.has(w) || !/[AEIOUY]/.test(w));
  return keep ? w : word(w);
};
/** A company name as a person writes it: entities decoded, a page-title tail cut, SHOUTING lowered; '' for the neutral
 *  greeting. It never throws: the greeting is not worth a failed send, so any exception reads as "no name". */
export function companyName(raw: unknown): string {
  try { return nameFrom(raw); } catch { return ''; }
}
function nameFrom(raw: unknown): string {
  let s = decodeOnce(decodeOnce(String(raw || '')));          // twice: "&amp;#8211;" is a dash too
  s = s.replace(/\s+/g, ' ').split(/\s*[|»]\s*|\s[–—-]\s|:\s/)[0]; // "Name – tagline", "Name |tagline", "Name: tagline", "Name » x"
  s = s.replace(/\s*\([^()]*\)?\s*$/, '');                   // "Name (Manufacturer and wholesaler of ...)"
  const comma = s.indexOf(', ');
  if (comma > 0 && PLACE_OR_TAGLINE.test(s.slice(comma + 2))) s = s.slice(0, comma);
  s = s.replace(/\bL\s+L\s+C\b/g, 'LLC').replace(/[\s,;:|–—-]+$/, '').trim();
  if (/[؀-ۿ]/.test(s) || /^zz\s*demo/i.test(s) || s.length < 2) return '';
  // a registered name carrying a web address ("www.khaazay.com online division of ...") gets the neutral greeting:
  // the founder's email carries no link, and the name is never cut into something the company did not write
  if (/https?:\/\/|\bwww\.|\b[a-z0-9-]+\.(?:com|ae|net|org|co|biz|info)\b/i.test(s)) return '';
  // still a title, not a name: too long, too many words, a comma-separated keyword list, or written to the reader. Words
  // are counted without "&" and legal suffixes: a registered name like "AL MARZOQI AUTO ACCESSORIES & MOBILE PHONE TRADING
  // CO LLC" is long and is still a name (MEASURED 28 Oct 2026: a plain 8-word / 60-char cap sent 280 such names to "Hello,").
  const words = s.split(' ').filter((w) => w !== '&' && !LEGAL.test(w.replace(/[^A-Za-z.]/g, '')));
  if (s.length > 80 || words.length > 10 || (s.match(/, /g) || []).length >= 2) return '';
  if (words.length >= 4 && /\b(?:we|our|you|your)\b/i.test(s)) return '';
  if (s === s.toUpperCase() && /[A-Z]{4}/.test(s)) return s.split(' ').map((t) => (t.includes('-') ? t.split('-').map(hyphenPart).join('-') : capsToken(t))).join(' ')
      .replace(/\b(?:Llc|Fze|Fzco|Fzc|Dmcc|Pjsc|Wll)\b/g, (w) => w.toUpperCase());   // a suffix inside a dotted token: "Studio-Ati.FZE"
  return s.split(' ').map((w) => (LEGAL.test(w.replace(/[^A-Za-z.]/g, '')) && /[a-z]/.test(w) && w.length > 2 ? w.toUpperCase() : w)).join(' ');
}
/** "fire_fighting" -> "fire fighting"; '' when there is none. */
export function tradeLabel(slug: unknown): string { return String(slug || '').replace(/[_-]+/g, ' ').trim().toLowerCase(); }
const cap1 = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
// VARIANT A, "ONE QUESTION, NO OFFER" (it_engineer, 27 Oct 2026; founder: "approved. dont ask me", the choice delegated).
// MEASURED: GlockApps 2026-10-27-09:33:53:634t placed the 27 Oct text above (bullet list "What you get", "Free
// registration", "No commission", "To join, register at quotesdone.com") in Junk at 18 of 18 Microsoft seeds, SPF/DKIM/DMARC
// passing and no blocklist, so content and reputation were what was left. This text keeps the founder's rules (no link, no
// domain written out, English, never the word AI, the signature, the stop line) and drops every offer phrase: no list, no
// "free", "join", "register", "commission" or "1,000". It is short (~80 words) and asks one question a supplier answers by
// replying, because a reply is the strongest positive signal a new mailbox can earn. Report:
// docs/reports/QuotesDone Campaign/GLOCKAPPS_27_OCT_RESULT_AND_FIX_PLAN.md (variants B and C are there, unapplied).
// THE COPY TEST (15 Nov 2026, marketing; scripts/sql/the_invitation_ramps_on_measured_health_and_tests_its_copy.sql). Three
// variants, each held to the same rules (m365CopyLint: no link, English, never the word, the signature, the stop line, no
// offer, no date): A is the founder-approved text above, unchanged; B and C are the report's variants of 27 Oct
// (docs/reports/QuotesDone Campaign/GLOCKAPPS_27_OCT_RESULT_AND_FIX_PLAN.md), B without its offer phrase ("no commission") and
// C made honest (buyers have not started sending requests yet). The database fixes each lead's variant once and writes it on
// the row's kind ('invite_variant:b'); a row without one (a seed, an older row) is variant A. The nudge carries the same kind.
export type InviteVariant = 'a' | 'b' | 'c';
export const INVITE_VARIANTS: readonly InviteVariant[] = ['a', 'b', 'c'];
export function variantOfKind(kind: unknown): InviteVariant {
  const m = /^invite_variant:([a-z])$/.exec(String(kind || ''));
  return m && (INVITE_VARIANTS as readonly string[]).includes(m[1]) ? (m[1] as InviteVariant) : 'a';
}
/** The subject asks; it names the trade when known, else the company. Never "invitation", "free", "commission" or "exclusive". */
export function m365Subject(who: Who = {}, variant: InviteVariant = 'a'): string {
  const t = tradeLabel(who.trade);
  if (variant === 'b') return 'Which trades does your company cover?';
  if (variant === 'c') return t ? `Do you take on ${t} work?` : 'Do you take on work for companies in the UAE?';
  return t ? `A question about your ${t} work` : 'A question about your work in the UAE';
}
/** Variant A (27 Oct 2026), or the variant under test. Company and trade when known, else the neutral wording. */
export function m365InvitationText(who: Who = {}, variant: InviteVariant = 'a'): string {
  const c = companyName(who.company); const t = tradeLabel(who.trade);
  const hello = c ? `Hi ${c} team,` : 'Hello,';
  // VARIANT B, MADE TRUE (15 Nov 2026, review of the funnel branch, item 1). It used to say "Companies in the UAE post their
  // requests for quotation with us" (they have not started) and "If you reply with them, we will set up your company page for
  // you": nothing performs that (ledger 1401, email_triage/account_facts.ts NO_SETUP_FOR_THEM forbids the model to offer it),
  // so a supplier who replied would have been told to do the steps himself. What a reply does get is true: email_triage
  // answers it with the company's own claim link (withClaimLink), and only the supplier can verify, upload and accept.
  if (variant === 'b') {
    return [
      hello,
      "I'm Ahmad, founder of QuotesDone in Dubai. Companies in the UAE will post their requests for quotation with us, and each request will go only to suppliers in that exact trade. Buyers have not started sending requests yet: we are putting the supplier list together first.",
      "Which trades does your company cover? If you reply with them, I will send you your company's own sign-up link, so you can add your company and those trades yourself.",
      SIGNATURE,
      STOP_LINE,
    ].join('\n\n');
  }
  if (variant === 'c') {
    return [
      hello,
      `Do you take on ${t ? t + ' work' : 'work in your trade'} for companies in the UAE? I'm Ahmad, founder of QuotesDone in Dubai, and before buyers ` +
        `start sending requests for quotation I am collecting the ${t ? t + ' ' : ''}suppliers each request will go to.`,
      SIGNATURE,
      STOP_LINE,
    ].join('\n\n');
  }
  return [
    hello,
    "I'm Ahmad, founder of QuotesDone in Dubai. QuotesDone is a platform where companies in the UAE post requests for quotation, and each request goes only to suppliers who work in that exact trade.",
    `We are putting together our list of ${t ? t + ' ' : ''}suppliers now, before buyers start sending requests. ` +
      `Would your company like to receive ${t ? t + ' requests' : 'the requests that match your trade'} when they come in?`,
    SIGNATURE,
    STOP_LINE,
  ].join('\n\n');
}
// THE ONE LAST NOTE TO A PARKED LEAD (15 Nov 2026, sales_engineer; review of the funnel branch, item 5). It was queued as a
// supplier_registration_reminder, which senderFor sends through Resend from supplier@ (not the Microsoft 365 lane whose GlockApps
// verdict its gate read), with a wa.me link and a registration link (against the no-link rule of 27 Oct 2026, founder_instruction
// 1301: the campaign mail carries no link; the claim link goes only in the model's answer to a supplier who wrote back), outside
// m365CopyLint and invite_daily_cap. Now it is the last nudge: type supplier_invite_nudge, kind FINAL_TOUCH_KIND, so it is a lane
// type (INVITE_LANE_TYPES) on the lane the placement gate measured, inside the one daily cap (LANE_CAPPED_TYPES), stopped by an
// opt-out (OPT_OUT_TYPES), counted by the bounce judgement, and its words pass the same copy rules. No link: a reply is the way in,
// and the reply is answered by the model with the company's own sign-up link (email_triage withClaimLink).
// scripts/sql/every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note.sql queues it.
export const FINAL_TOUCH_KIND = 'invite_final_touch';
export function isFinalTouch(row: { type?: unknown; kind?: unknown }): boolean {
  return row.type === 'supplier_invite_nudge' && row.kind === FINAL_TOUCH_KIND;
}
export function m365FinalTouchSubject(who: Who = {}): string {
  const t = tradeLabel(who.trade);
  return t ? `One last note about ${t} requests` : 'One last note from QuotesDone';
}
/** The company's number, written out (src/content/company.json `phone.number`; the check the_supplier_funnel_runs_itself compares them). */
export const FINAL_TOUCH_PHONE = '+1 218 316 6814';
export function m365FinalTouchText(who: Who = {}): string {
  const c = companyName(who.company); const t = tradeLabel(who.trade);
  return [
    c ? `Hi ${c} team,` : 'Hello,',
    `I'm Ahmad, founder of QuotesDone in Dubai. I wrote to you a few weeks ago about the list of ${t ? t + ' ' : ''}suppliers we are putting together ` +
      'before buyers start sending requests for quotation; each request will go only to suppliers who work in that exact trade.',
    'This is the last time I will write about it. If your company would like to receive ' + (t ? t + ' requests' : 'the requests that match your trade') +
      ", reply to this email and I will send you your company's own sign-up link.",
    // The number as plain text, no link and no tel: (founder ruling 1301 of 27 Oct 2026, applied 16 Nov); src/content/company.json `phone`.
    `If you would rather talk on WhatsApp, our number is ${FINAL_TOUCH_PHONE}.`,
    SIGNATURE,
    STOP_LINE,
  ].join('\n\n');
}
/** The company on a stored body's "Dear X," / "Hi X team," opening, for a row with no lead behind it (a seed). */
export function companyFromBody(body: string): string {
  const m = /^(?:dear|hi|hello)\s+(.+?)(?:\s+team)?,\s*$/i.exec(String(body || '').split(/\r?\n/)[0] || '');
  return m ? m[1] : '';
}

// THE MORNING SEED KEEPS ITS PLACEMENT TOKEN (ceo, 26 Oct 2026). _shared/inbox_placement.ts finds the day's seed in
// the two seed mailboxes ONLY by the "(ref QD<10 hex>)" token fn_invite_placement_due puts on the row's subject. #1566
// (19 Oct) rebuilt every Microsoft 365 subject with m365Subject and dropped it: measured 20-26 Oct, both copies of all
// five seeds read not_found (0 token matches, 0 other-sender skips), so every day's batch was held and 0 invitations
// left. A supplier_invite_seed row that carries a token keeps it on the rebuilt subject; no other row ever has one.
const PLACEMENT_REF = /\(ref QD[0-9A-F]{10}\)/;
export function withPlacementRef(subject: string, row: { type?: unknown; subject?: unknown }): string {
  const ref = row.type === 'supplier_invite_seed' ? PLACEMENT_REF.exec(String(row.subject || ''))?.[0] : undefined;
  return ref && !subject.includes(ref) ? `${subject} ${ref}` : subject;
}

// A placement-test seed (GlockApps) is matched by an inbox-test ID on the LAST line of the body, e.g.
// "id:2026-10-05-18:36:55:550t". 5 Oct 2026: m365Body rebuilt the text from the link alone, dropped that line,
// and GlockApps matched 0 of 80 seeds. Only a seed row carries it; a real invitation or nudge never does.
const SEED_MARKER = /^id:[0-9A-Za-z:_-]{6,64}$/;

/** The inbox-test ID on the last non-empty line of a body, or '' when there is none. */
export function seedMarker(body: string): string {
  const last = String(body || '').trimEnd().split(/\r?\n/).pop()?.trim() || '';
  return SEED_MARKER.test(last) ? last : '';
}

/** The body this lane sends: the founder's text for the invitation, its nudge and the seed alike, whatever the row
 *  stored. A seed row (kind M365_SEED_KIND) keeps its trailing inbox-test ID line as the last line. */
export function m365Body(type: unknown, rowBody: string, kind?: unknown, who: Who = {}): string {
  const marker = kind === M365_SEED_KIND ? seedMarker(rowBody) : '';
  const own = marker ? String(rowBody).trimEnd().slice(0, -marker.length).trimEnd() : (rowBody || '');
  const w = { company: who.company ?? companyFromBody(own), trade: who.trade };
  const built = isFinalTouch({ type, kind }) ? m365FinalTouchText(w) : m365InvitationText(w, variantOfKind(kind));
  return marker ? built + '\n\n' + marker : built;
}

/** THE ONE SUPPLIER CAMPAIGN EMAIL, WHICHEVER ROUTE CARRIES IT (27 Oct 2026, coordinator follow-up to #1614).
 *  send_outbox builds the subject and text here for the Microsoft 365 lane AND the Resend fallback, so switching
 *  invite_m365_enabled off can never bring back the old email (link, closing question, Al Furjan footer).
 *  `bad` lists the copy rules the email fails; any failure holds the row on either route. */
export function campaignMail(row: { type?: unknown; body?: unknown; subject?: unknown; kind?: unknown }, who: Who = {}):
  { subject: string; text: string; bad: CopyRule[] } {
  const body = String(row.body || '');
  const company = who.company ?? companyFromBody(body);
  const text = m365Body(row.type, body, row.kind, { ...who, company });
  const subject = withPlacementRef(isFinalTouch(row) ? m365FinalTouchSubject({ company, trade: who.trade })
                                                    : m365Subject({ company, trade: who.trade }, variantOfKind(row.kind)), row);
  // THE RULES READ OUR COPY, NOT THE SUPPLIER'S OWN NAME (27 Oct 2026, review of #1614). Measured that day: 11 of
  // 17,401 eligible leads were held because their registered name tripped a copy rule meant for our wording:
  // "Eastlake Dec.Design" and "... CARPETS & NOV TRADING" read as month names next to the 1,000 offer, "2003 ALUMINIUM
  // WORKS" and "CHINA 2008 BUILDING MATERIAL" as dates, "AI TRADING EST" as the forbidden word. So the copy rules run
  // with the rendered name masked, and the no-link rule ALSO runs on the email exactly as sent (a name carrying a web
  // address never reaches it: companyName gives the neutral greeting instead).
  const name = companyName(company);
  const mask = (s: string) => (name ? s.split(name).join('Company') : s);
  const bad = m365CopyLint({ subject: mask(subject), body: mask(text), seed: row.kind === M365_SEED_KIND }).filter((l) => !l.ok);
  if (ANY_LINK.test(text) || ANY_LINK.test(subject)) {
    bad.push({ rule: 'no link anywhere in the email as sent', ok: false, detail: String((text + ' ' + subject).match(ANY_LINK)?.[0] || '') });
  }
  return { subject, text, bad };
}

const DATED = /\b(?:20\d\d|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|deadline|until|expires?|limited time)\b/i;
// THE TWO FALSE CLAIMS (15 Nov 2026, review of the funnel branch, item 1). Variant B said both and the test of the day missed them
// (it looked only for "buyers are sending"): "we will set up your company page for you" (nothing performs it, ledger 1401) and
// "Companies in the UAE post their requests for quotation with us" with no word that buyers have not started. A sentence about
// buyers posting is honest only beside one saying they have not started (variant A: "before buyers start sending requests").
export const PROMISE_WE_DO_NOT_KEEP = /\b(?:we|i|our team)(?:\s+(?:will|can|would|shall)|'ll)?\s+(?:then\s+)?(?:set\s*up|create|build|make|register|complete|fill\s+in|publish|list)\b[^.?!]{0,60}\b(?:page|profile|account|listing|registration|for\s+you)\b/i;
export const BUYERS_ARE_SENDING = /\b(?:buyers|customers|companies|clients)\s+are\s+(?:already\s+)?(?:sending|posting|submitting)\b/i;
export const BUYERS_POST = /\b(?:companies|buyers|customers|clients)\b[^.?!]{0,40}\b(?:post|send|submit|share)s?\b[^.?!]{0,30}\brequests?\b/i;
export const NOT_STARTED = /\bbefore\s+(?:buyers|companies|customers)\s+start|\b(?:have|has)\s+not\s+started|\b(?:haven't|hasn't)\s+started|\bnot\s+started\s+yet/i;
export function claimsBuyersExist(body: string): boolean {
  return BUYERS_ARE_SENDING.test(body) || (BUYERS_POST.test(body) && !NOT_STARTED.test(body));
}
const UP_TO_THREE = /\b(?:up to|only|maximum of|max(?:imum)?)\s+(?:three|3)\s+(?:suppliers|quotes|quotations)\b/i;

/** Every rule the lane's body must pass before it leaves. Any failure holds the row. */
// For a seed, ONLY the trailing inbox-test ID line is set aside, and only for the rules it cannot honour by being
// there: the date rules (the ID holds a year) and the closing-line rule (the ID must be the last line).
// Every content rule (English, the word, no link, no HTML, no cap on suppliers) still reads the whole body.
const MARKER_EXEMPT = /date|closes with/;
// The question-ending rules of invitationCopyLint belong to the stored Resend-lane copy; the founder's approved text
// (27 Oct 2026) closes with the reply-"stop" line instead, so this lane does not apply them.
const NOT_THIS_LANE = /question/;
export function m365CopyLint(o: { subject: string; body: string; preheader?: string; seed?: boolean }): CopyRule[] {
  const marker = o.seed ? seedMarker(o.body) : '';
  if (marker) {
    const rest = o.body.trimEnd().slice(0, -marker.length).trimEnd();
    const without = new Map(m365CopyLint({ ...o, body: rest, seed: false }).map((l) => [l.rule, l]));
    return m365CopyLint({ ...o, seed: false }).map((l) => (MARKER_EXEMPT.test(l.rule) ? without.get(l.rule) || l : l));
  }
  return [
    ...invitationCopyLint({ lang: 'en', subject: o.subject, body: o.body, preheader: o.preheader || '' }).filter((l) => !NOT_THIS_LANE.test(l.rule)),
    { rule: 'no link anywhere in the email (founder, 27 Oct 2026: "safer to not send links")', ok: !ANY_LINK.test(o.body) && !ANY_LINK.test(o.subject),
      detail: String((o.body + ' ' + o.subject).match(ANY_LINK)?.[0] || '') },
    { rule: 'the body closes with the reply-"stop" opt-out line', ok: o.body.trimEnd().endsWith(STOP_LINE), detail: 'last line: ' + o.body.trimEnd().split('\n').pop() },
    { rule: 'the signature names no street address and no permit or licence number (founder, 27 Oct 2026)', ok: !/al[\s-]*furjan|\bNOL-|TDRA|licen[cs]e\s*(no|number)|\b1633275\b/i.test(o.body),
      detail: 'Al Furjan, a TDRA permit or a licence number found' },
    { rule: 'no HTML in a plain-text invitation', ok: !/<\/?[a-z][^>]*>/i.test(o.body), detail: 'markup found' },
    { rule: '"free for the first 1,000 suppliers" carries no date', ok: !/1,000/.test(o.body) || !DATED.test(o.body), detail: 'a date or deadline word next to the offer' },
    { rule: 'never a cap on how many suppliers quote: any number may quote, top 3 is only the report', ok: !UP_TO_THREE.test(o.body + ' ' + o.subject), detail: 'the forbidden wrong form' },
    { rule: 'never promises to set up their page or do a step for them (ledger 1401: nothing performs it; only they verify, upload and accept)',
      ok: !PROMISE_WE_DO_NOT_KEEP.test(o.body), detail: String(o.body.match(PROMISE_WE_DO_NOT_KEEP)?.[0] || '') },
    { rule: 'never says buyers already send requests (they have not started: a sentence about buyers posting is paired with "not started")',
      ok: !claimsBuyersExist(o.body), detail: String(o.body.match(BUYERS_ARE_SENDING)?.[0] || o.body.match(BUYERS_POST)?.[0] || '') },
  ];
}

// ---------------------------------------------------------------- MIME and the send
const b64 = (s: string) => { const bytes = new TextEncoder().encode(s); let bin = ''; for (const b of bytes) bin += String.fromCharCode(b); return btoa(bin); };
const hdr = (s: string) => (/^[\x20-\x7e]*$/.test(s) ? s : `=?UTF-8?B?${b64(s)}?=`);
const clean = (s: string) => String(s || '').replace(/[\r\n]+/g, ' ').trim();

export function messageIdFor(notificationId: number | string, now: Date): string {
  return `<qd-notif-${notificationId}.${now.getTime()}@quotesdone.com>`;
}

// ---------------------------------------------------------------- Reply-To (6 Oct 2026, it_engineer)
// MEASURED 6 Oct 2026: an invitation from this lane passed SPF, DKIM (selector1, d=quotesdone.com) and DMARC, scored
// 10/10 at mail-tester with outbound SCL 1, and still landed in Junk at a Microsoft 365 recipient. Its From was
// supplier@quotesdone.com and its Reply-To suppliers@mail.quotesdone.com (app_secrets.email_reply_supplier): a
// Reply-To on another domain than the From is a phishing signal. So the lane sends with NO Reply-To and a reply goes
// to the mailbox itself -- but only once _shared/m365_reply_inbox.ts has PROVED, on a recent tick, that it can read
// that mailbox and hand its mail to resend_inbound. Until then the old Reply-To stays, so a reply is never sent to a
// mailbox nobody reads. The proof is the newest agent_runs row of M365_INBOX_AGENT carrying counts.m365_inbox, status 'ok'.
export const M365_INBOX_AGENT = 'resend_inbound';   // = m365_reply_inbox.ts PROOF_LABEL; its rows carry counts.m365_inbox = 1
export const M365_INBOX_PROOF_MAX_AGE_MS = 2 * 60 * 60_000;
/** '' = no Reply-To header (replies reach the From mailbox); otherwise the fallback, kept until the reader is proven. */
// A SUPPLIER ANSWERED IN A CONVERSATION REPLIES INTO THE READ SUPPLIER MAILBOX (2 Nov 2026, customer_support). MEASURED:
// notification 117599 (inbound_reply, Resend, From and Reply-To info@) was answered 13 minutes later and the reply landed
// in management@, read by nothing. inbound_reply has no to_role, so it took the customer's Reply-To. supplier@ is on the
// From's own domain, so the cross-domain reasoning above does not apply. Only while its reader is proven; otherwise the
// old Reply-To stands.
export function conversationReplyTo(o: { type: unknown; toSupplier: boolean; mailbox: string | undefined; proofAt: string | null | undefined; now: Date; fallback: string }): string {
  const mailbox = String(o.mailbox || '').trim();
  if (o.type !== 'inbound_reply' || !o.toSupplier || !/@quotesdone\.com$/i.test(mailbox)) return o.fallback;
  return m365ReplyTo({ proofAt: o.proofAt, now: o.now, fallback: o.fallback }) === '' ? mailbox : o.fallback;
}
export function m365ReplyTo(o: { proofAt: string | null | undefined; now: Date; fallback: string }): string {
  const t = o.proofAt ? Date.parse(o.proofAt) : NaN;
  const age = o.now.getTime() - t;
  return Number.isFinite(t) && age <= M365_INBOX_PROOF_MAX_AGE_MS && age >= -60_000 ? '' : o.fallback;
}

// THE TEXT PART IS QUOTED-PRINTABLE, NOT BASE64 (it_engineer, 27 Oct 2026). A person's mail client writes a plain
// English note as 7bit or quoted-printable; a base64-encoded text/plain body that is almost all ASCII is what bulk
// tools emit, and content filters score it (SpamAssassin's MIME_BASE64_TEXT is the public example). Quoted-printable
// keeps every ASCII character readable and encodes only the few UTF-8 ones ("·", "–"). MEASURED the same day on a
// received copy (founder's Gmail, raw): Exchange rebuilds the MIME on the way out and re-encodes the text part itself,
// so this changes what we SUBMIT, not what arrives; it is kept because it is harmless and tested. RFC 2045 §6.7:
// "=" and non-ASCII bytes as =XX, a space or tab before a line break as =20/=09, lines at most 76 characters with a
// soft break "=". The envelope itself stays base64: that is sendMail's own text/plain input format, not a MIME part.
const QP_HEX = (b: number) => '=' + b.toString(16).toUpperCase().padStart(2, '0');
export function qpEncode(text: string): string {
  return text.replace(/\r?\n/g, '\n').split('\n').map((line) => {
    const bytes = new TextEncoder().encode(line);
    const tokens: string[] = [];
    bytes.forEach((b, i) => {
      const last = i === bytes.length - 1;
      if ((b === 0x20 || b === 0x09) && last) tokens.push(QP_HEX(b));
      else if (b === 0x09 || (b >= 0x20 && b <= 0x7e && b !== 0x3d)) tokens.push(String.fromCharCode(b));
      else tokens.push(QP_HEX(b));
    });
    const out: string[] = []; let cur = '';
    for (const t of tokens) { if (cur.length + t.length > 75) { out.push(cur + '='); cur = ''; } cur += t; }
    out.push(cur);
    return out.join('\r\n');
  }).join('\r\n');
}

/** The whole message as MIME (base64, as sendMail's text/plain mode wants it). An empty reply writes no Reply-To.
 *  inReplyTo (a mailbox reply) writes In-Reply-To and References, so it threads under the supplier's message.
 *  `html` (3 Nov 2026, open_tracking.ts): absent or '' = the plain-text message exactly as before; otherwise
 *  multipart/alternative with the SAME text part first and the HTML twin second (RFC 2046 5.1.4: last part preferred).
 *  A reply (inReplyTo set) is ALWAYS plain text: its html is ignored, so a threaded answer can never carry a pixel. */
export function m365Mime(o: { from: string; to: string; reply: string; subject: string; text: string; unsub: string; unsubMailto: string; messageId: string; now: Date; inReplyTo?: string | null; html?: string }): string {
  const irt = clean(String(o.inReplyTo ?? ''));
  const thread = irt ? [`In-Reply-To: ${irt.startsWith('<') ? irt : '<' + irt + '>'}`] : [];
  if (thread.length) thread.push('References: ' + thread[0].slice('In-Reply-To: '.length));
  const html = irt ? '' : String(o.html || '');
  const lines = [
    `From: ${clean(o.from)}`, `To: ${clean(o.to)}`, ...(clean(o.reply) ? [`Reply-To: ${clean(o.reply)}`] : []), `Subject: ${hdr(clean(o.subject) || 'QuotesDone')}`,
    `Date: ${o.now.toUTCString()}`, `Message-ID: ${o.messageId}`, ...thread, 'MIME-Version: 1.0',
  ];
  if (o.unsub) lines.push(`List-Unsubscribe: <${clean(o.unsub)}>, <mailto:${o.unsubMailto}?subject=unsubscribe>`, 'List-Unsubscribe-Post: List-Unsubscribe=One-Click');
  const textPart = ['Content-Type: text/plain; charset=utf-8', 'Content-Transfer-Encoding: quoted-printable', '', qpEncode(o.text)];
  if (!html) {
    lines.push(...textPart);
  } else {
    const b = 'qd-alt-' + o.messageId.replace(/[^A-Za-z0-9]/g, '').slice(0, 48);
    lines.push(`Content-Type: multipart/alternative; boundary="${b}"`, '', `--${b}`, ...textPart, `--${b}`,
      'Content-Type: text/html; charset=utf-8', 'Content-Transfer-Encoding: quoted-printable', '', qpEncode(html), `--${b}--`, '');
  }
  return b64(lines.join('\r\n'));
}

// PACING (it_engineer, 27 Oct 2026). MEASURED: the 112 GlockApps seeds of 27 Oct were queued at once at 09:41Z and
// send_outbox, which runs every 15 minutes, sent 20 of them back to back in each run (09:46, 10:01, 10:16, 10:31-32,
// 10:46-47; about 4 s apart). A new mailbox whose whole history is bursts of 20 to strangers looks like a bulk tool.
// Microsoft Learn ("Troubleshoot outbound sending limits", best practices for bulk senders): "Spread bulk sends over
// time rather than sending all at once". So the lane sends at most M365_PER_RUN messages a run; the rest of the run's
// lane rows go back to the queue (not_before = now + M365_PACE_MS) for a later run. At one run per 15 minutes that is
// 20 an hour, which still finishes Week 2's 10-15 invitations in under an hour and a 112-seed test in about 6 hours.
export const M365_PER_RUN = 5;
export const M365_PACE_MS = 10 * 60_000;
/** Hold this lane row for pacing? true once this run has already sent M365_PER_RUN through the lane. */
export function paceM365(sentThisRun: number): boolean { return sentThisRun >= M365_PER_RUN; }

export type SendResult = { ok: true; providerId: string } | { ok: false; refused: true; status: string } | { ok: false; refused: false; status: string };

/** POST the MIME. 202 = accepted. A refusal is returned (the caller holds + files); a throw means no answer came.
 *  19 Oct 2026 (review of #1473): M365_REFUSED_ISSUE closes only here, on a 2xx sendMail, never on a token issued,
 *  so the finding cannot flap shut while Graph is still refusing sends. */
export async function graphSend(fetchFn: Fetch, m365: M365, mime: string, messageId: string, closeFinding?: CloseFinding): Promise<SendResult> {
  const r = await fetchFn(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(m365.mailbox)}/sendMail`, {
    method: 'POST', headers: { Authorization: `Bearer ${m365.token}`, 'Content-Type': 'text/plain' }, body: mime,
  });
  if (r.status === 202 || r.ok) {
    try { await closeFinding?.(M365_REFUSED_ISSUE, 'closed by send_outbox: Graph sendMail accepted a message (HTTP ' + r.status + ')'); }
    catch (_e) { /* closing is bookkeeping; the send already happened */ }
    return { ok: true, providerId: M365_ID_PREFIX + messageId };
  }
  let detail = '';
  try { const j = await r.json(); detail = String(j?.error?.code || '') + ' ' + String(j?.error?.message || ''); } catch { /* status alone */ }
  return { ok: false, refused: true, status: `Graph sendMail answered HTTP ${r.status} ${detail}`.trim().slice(0, 300) };
}
