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
// "reply stop" line (m365Text) for any client that ignores them.
// sendMail answers 202 with no body, so the provider id we keep is our own Message-ID, written into the MIME:
// notifications.provider_message_id = 'm365:<...>' (the prefix also lets the hard ceiling count this lane's sends).
// Pure apart from the injected fetch and finding writer, so m365_lane.test.ts replays every branch offline.
import { isLaneType, LANE_CAPPED_TYPES } from './invite_lane.ts';
import { invitationCopyLint, withReplyQuestion, type CopyRule } from './invitation_copy.ts';
import { UNSUBSCRIBE_MAILBOX } from '../_shared/unsubscribe_mailbox.ts';

export const M365_SECRET_NAMES = ['MS_TENANT_ID', 'MS_CLIENT_ID', 'MS_CLIENT_SECRET'] as const;
export const M365_REFUSED_ISSUE = 'invite_m365_lane_refused';
export const M365_SEED_KIND = 'invite_m365_seed';
export const M365_HARD_CEILING = 150;
export const M365_ID_PREFIX = 'm365:';
export const HOLD_M365_MS = 30 * 60_000;

export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export type FileFinding = (args: Record<string, unknown>) => Promise<unknown>;
/** fn_it_engineer_finding_close(p_issue_key, p_note). */
export type CloseFinding = (issueKey: string, note: string) => Promise<unknown>;
export type M365 = { active: boolean; refused: boolean; mailbox: string; token: string; why: string };
export const M365_OFF: M365 = { active: false, refused: false, mailbox: '', token: '', why: 'invite_m365_enabled is not true' };

/** Whether this row is carried by the Microsoft 365 lane at all (before the lane's state is looked at). */
export function m365Carries(o: { enabled: boolean; type: unknown; kind: unknown; supplierSide: boolean }): boolean {
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

// ---------------------------------------------------------------- the plain-text invitation (marketing)
// One link, no HTML frame, English only, never the word AI, ends with ONE question after the link (invitation_copy.ts).
// The founder's rules, as ruled: any number of suppliers may quote; "top 3" is ONLY what the buyer's comparison report
// recommends; free for the first 1,000 suppliers, with no date attached to it.
export const PORTAL_LINK = /https?:\/\/[^\s<>"]+\/portal\?t=[0-9a-f-]{36}/gi;

// 19 Oct 2026 (marketing + it_engineer, ledger 1113: no campaign email in spam). MEASURED (GlockApps
// 2026-10-19-02:51:47:497t, this lane): 33% inbox, Outlook/Yahoo/AOL 100% spam (EOP SCL 5), Gmail 19 of 20 in
// Promotions, SPF/DKIM/DMARC passing, no blocklist. So the content changed: a short note from a named person,
// addressed to the company and its trade, no promotional word in the subject or the opening, one link, and the
// opt-out in the List-Unsubscribe headers plus one "reply stop" line (no second URL in the body; see m365Text).
export type Who = { company?: string; trade?: string };
const ENTITY: Record<string, string> = { amp: '&', '#038': '&', '#38': '&', quot: '"', '#039': "'", '#39': "'", apos: "'" };
/** A company name as a person writes it: entities decoded, a "| tagline" or " - branch" cut, SHOUTING lowered. */
export function companyName(raw: unknown): string {
  let s = String(raw || '').replace(/&(#0?\d+|[a-z]+);/gi, (m, k) => ENTITY[String(k).toLowerCase()] ?? m);
  s = s.split(/\s[|–—-]\s/)[0].replace(/\s+/g, ' ').trim();
  if (/[؀-ۿ]/.test(s) || /^zz\s*demo/i.test(s) || s.length < 2) return '';
  if (s === s.toUpperCase() && /[A-Z]{4}/.test(s)) {
    s = s.toLowerCase().replace(/\b[a-z]/g, (c) => c.toUpperCase()).replace(/\b(Llc|Fze|Fzco|Fzc|Fz)\b/g, (w) => w.toUpperCase());
  }
  return s;
}
/** "fire_fighting" -> "fire fighting"; '' when there is none. */
export function tradeLabel(slug: unknown): string { return String(slug || '').replace(/[_-]+/g, ' ').trim().toLowerCase(); }
const cap1 = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
/** The subject names the company (and the trade when known). Never "invitation", "free", "commission" or "exclusive". */
export function m365Subject(who: Who = {}): string {
  const c = companyName(who.company); const t = tradeLabel(who.trade);
  const what = t ? `${cap1(t)} quote requests` : 'Quote requests';
  return c ? `${what} for ${c}` : `${what} in the UAE`;
}
export function m365InvitationText(link: string, who: Who = {}): string {
  const c = companyName(who.company); const t = tradeLabel(who.trade);
  return [
    c ? `Hi ${c} team,` : 'Hello,',
    `I'm Ahmad, founder of QuotesDone in Dubai. Companies post requests for quotation with us and we pass each one only to suppliers in the matching trade${t ? `, so I am lining up ${t} suppliers before buyers start posting` : ''}.`,
    'Any number of suppliers can quote on a request, and the buyer receives a comparison report that recommends the top three quotes by value. There is no commission on work you win, and registration costs nothing for the first 1,000 supplier registrations.',
    'Your company page is ready to claim here:\n' + link,
    'Which trades does your company cover?',
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

/** The body this lane sends: the plain variant for an invitation with exactly one portal link; else the row's own body.
 *  A seed row (kind M365_SEED_KIND) keeps its trailing inbox-test ID line at the end of whatever is built. */
export function m365Body(type: unknown, rowBody: string, kind?: unknown, who: Who = {}): string {
  const links = String(rowBody || '').match(PORTAL_LINK) || [];
  const marker = kind === M365_SEED_KIND ? seedMarker(rowBody) : '';
  const own = marker ? String(rowBody).trimEnd().slice(0, -marker.length).trimEnd() : (rowBody || '');
  const built = type !== 'supplier_invite_nudge' && links.length === 1
    ? m365InvitationText(links[0], { company: who.company ?? companyFromBody(own), trade: who.trade }) : withReplyQuestion(own);
  return marker ? built + '\n\n' + marker : built;
}

const DATED = /\b(?:20\d\d|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|deadline|until|expires?|limited time)\b/i;
const UP_TO_THREE = /\b(?:up to|only|maximum of|max(?:imum)?)\s+(?:three|3)\s+(?:suppliers|quotes|quotations)\b/i;

/** Every rule the lane's body must pass before it leaves. Any failure holds the row. */
// For a seed, ONLY the trailing inbox-test ID line is set aside, and only for the rules it cannot honour by being
// there: the date rules (the ID holds a year) and the two question-placement rules (the ID must be the last line).
// Every content rule (English, the word, one link, no HTML, no cap on suppliers) still reads the whole body.
const MARKER_EXEMPT = /date|ends with one question|question comes after/;
export function m365CopyLint(o: { subject: string; body: string; preheader?: string; seed?: boolean }): CopyRule[] {
  const marker = o.seed ? seedMarker(o.body) : '';
  if (marker) {
    const rest = o.body.trimEnd().slice(0, -marker.length).trimEnd();
    const without = new Map(m365CopyLint({ ...o, body: rest, seed: false }).map((l) => [l.rule, l]));
    return m365CopyLint({ ...o, seed: false }).map((l) => (MARKER_EXEMPT.test(l.rule) ? without.get(l.rule) || l : l));
  }
  const links = o.body.match(/https?:\/\/\S+/g) || [];
  const portal = (o.body.match(PORTAL_LINK) || [])[0];
  return [
    ...invitationCopyLint({ lang: 'en', subject: o.subject, body: o.body, preheader: o.preheader || '', link: portal }),
    { rule: 'exactly one link in the body', ok: links.length === 1, detail: `${links.length} links` },
    { rule: 'no HTML in a plain-text invitation', ok: !/<\/?[a-z][^>]*>/i.test(o.body), detail: 'markup found' },
    { rule: '"free for the first 1,000 suppliers" carries no date', ok: !/1,000/.test(o.body) || !DATED.test(o.body), detail: 'a date or deadline word next to the offer' },
    { rule: 'never a cap on how many suppliers quote: any number may quote, top 3 is only the report', ok: !UP_TO_THREE.test(o.body + ' ' + o.subject), detail: 'the forbidden wrong form' },
  ];
}

// ---------------------------------------------------------------- MIME and the send
const b64 = (s: string) => { const bytes = new TextEncoder().encode(s); let bin = ''; for (const b of bytes) bin += String.fromCharCode(b); return btoa(bin); };
const wrap76 = (s: string) => s.replace(/.{1,76}/g, (m) => m + '\r\n').trimEnd();
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
export function m365ReplyTo(o: { proofAt: string | null | undefined; now: Date; fallback: string }): string {
  const t = o.proofAt ? Date.parse(o.proofAt) : NaN;
  const age = o.now.getTime() - t;
  return Number.isFinite(t) && age <= M365_INBOX_PROOF_MAX_AGE_MS && age >= -60_000 ? '' : o.fallback;
}

/** The whole message as MIME (base64, as sendMail's text/plain mode wants it). An empty reply writes no Reply-To. */
export function m365Mime(o: { from: string; to: string; reply: string; subject: string; text: string; unsub: string; unsubMailto: string; messageId: string; now: Date }): string {
  const lines = [
    `From: ${clean(o.from)}`, `To: ${clean(o.to)}`, ...(clean(o.reply) ? [`Reply-To: ${clean(o.reply)}`] : []), `Subject: ${hdr(clean(o.subject) || 'QuotesDone')}`,
    `Date: ${o.now.toUTCString()}`, `Message-ID: ${o.messageId}`, 'MIME-Version: 1.0',
  ];
  if (o.unsub) lines.push(`List-Unsubscribe: <${clean(o.unsub)}>, <mailto:${o.unsubMailto}?subject=unsubscribe>`, 'List-Unsubscribe-Post: List-Unsubscribe=One-Click');
  lines.push('Content-Type: text/plain; charset=utf-8', 'Content-Transfer-Encoding: base64', '', wrap76(b64(o.text.replace(/\r?\n/g, '\r\n'))));
  return b64(lines.join('\r\n'));
}

/** The sent text: body, a short signature and ONE opt-out line. No unsubscribe URL in the body (ledger 1113): a
 *  second link, on another host than the From, is what content filters score; the one-click link is in the
 *  List-Unsubscribe header, and the line below still gives a reader who never sees that header a way out. */
export function m365Text(body: string, _unsub?: string): string {
  return [String(body || '').trim(), '--', 'Ahmad Alzain\nFounder, QuotesDone',
    // the sender's legal identity (release review of #1524); no trade licence number: founder ruling, ledger 993
    'QuotesDone Technologies · Al Furjan, Dubai, UAE · TDRA NOL-26-100000665',
    `Not relevant to you? Reply "stop" or email ${UNSUBSCRIBE_MAILBOX} and I will not write again.`].join('\n\n');
}

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
