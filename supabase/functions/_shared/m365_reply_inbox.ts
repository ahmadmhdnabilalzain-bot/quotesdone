// REPLIES TO THE MICROSOFT 365 MAILBOX REACH THE PLATFORM (6 Oct 2026; Assigned: it_engineer (mail path) +
// customer_support (inbound)).
//
// WHY. Invitations leave from supplier@quotesdone.com through Graph (send_outbox/m365_lane.ts). Measured 6 Oct 2026:
// SPF, DKIM and DMARC pass, mail-tester 10/10, outbound SCL 1, and still Junk at a Microsoft 365 recipient. The likely
// cause is the Reply-To, suppliers@mail.quotesdone.com: another domain than the From. The lane now sends with no
// Reply-To, so a supplier's reply lands in supplier@quotesdone.com's own Inbox -- which nothing read. This module is
// that reader. It runs inside resilience_ping's itintegrations step (every 15 minutes, no new step and no SQL, the
// way inbox_placement.ts rides there).
//
// WHAT IT DOES, each tick:
//   1. client-credentials token (MS_TENANT_ID / MS_CLIENT_ID / MS_CLIENT_SECRET, edge env, never printed);
//   2. lists the mailbox's Inbox, newest first, Prefer IdType="ImmutableId" so a message keeps its id if a person
//      moves it, received in the last LOOKBACK_DAYS, up to MAX_PAGES pages;
//   3. drops every message whose provider id 'm365:<immutable id>' is already in inbound_messages (the IDEMPOTENCY:
//      resend_inbound keeps provider_email_id under a unique index and answers a second delivery as a duplicate);
//   4. hands each new one to resend_inbound as a Resend 'email.received' delivery -- the SAME handler, tables,
//      threading facts (Message-ID, In-Reply-To, References), customer_support/sales_engineer routing and
//      conversation archive as a reply to suppliers@mail.quotesdone.com. The delivery is Svix-signed with
//      resend_inbound_signing_secret and carries resend_inbound_token, so no second door is opened into a function
//      that books expenses and writes supplier records: it passes exactly the check Resend's own delivery passes;
//   5. marks it read (needs Mail.ReadWrite). A mark that fails is counted, never fatal: step 3 already stops a
//      second hand-off;
//   6. writes ONE agent_runs row under resend_inbound's label (owned; no new label to register) with
//      counts.m365_inbox = 1. status 'ok' is THE PROOF send_outbox reads before it drops the Reply-To
//      (m365_lane.ts m365ReplyTo). Anything else -- unreadable, a failed hand-off -- withdraws the proof at once, and
//      the lane goes back to the old Reply-To on its next run. No reply is ever sent to a mailbox nobody reads.
//
// A 401/403 ON THE LISTING IS THE MISSING PERMISSION. The app was granted Mail.Send only. ONE it_engineer finding
// (M365_INBOX_UNREADABLE) says exactly what the founder clicks; nothing is granted from here.
// Nothing sensitive in the answer: resilience_ping is public, so this returns counts and the reason only.
//
// EVERY MAILBOX A SUPPLIER WRITES TO IS READ (2 Nov 2026, customer_support, ledger 1423+). Founder: "All our emails should
// be with the agents. Whether it was info, management, supplier, the agents need to have access." MEASURED: a real supplier
// wrote a fresh email to management@ and nothing read it; six delivery reports sat unread in supplier@'s Junk.
//   - supplier@'s Junk is also listed. Junk hands over only delivery reports and known senders, never random junk.
//   - pollTenantMailboxes reads every other mailbox on the same tick, listed from Graph (/users) where the app may, else
//     app_secrets.m365_tenant_mailboxes, else DEFAULT_MAILBOXES. People use those mailboxes, so nothing there is ever marked
//     read, moved, deleted or replied to from here. expenses@ keeps its own path, and mail from the founder, staff or our
//     own domains is not handed: expense forwarders could otherwise book through it (resend_inbound expenseSenderOk).
//   - MEASURED 2 Nov: a supplier's reply to info@ landed in management@, which also files mail in an "info quotesdone"
//     folder. So each mailbox's own top-level folders are read too (FILED_FOLDER_CAP), under the Inbox's rules.
//   - REVIEW OF THIS BRANCH, 2 Nov: a known sender or a reply in one of our threads keeps the 14-day lookback. A stranger is
//     handed only after app_secrets.m365_tenant_strangers_from (no value: never), so no old mail is answered. Bank mail
//     (any mashreq* domain, app_secrets.m365_financial_domains) and machine senders are counted only: no body is read or
//     stored. One internetMessageId is handed once across all mailboxes.
//   - its agent_runs row carries counts.m365_tenant, never counts.m365_inbox, so a failure there cannot withdraw the proof
//     send_outbox reads for supplier@ (it selects counts.m365_inbox = 1).
import { isDeliveryReportSender } from './mailbox_bounce.ts';
export const M365_INBOX_UNREADABLE = 'invite_m365_inbox_unreadable';
export const M365_INBOUND_PREFIX = 'm365:';
export const PROOF_LABEL = 'resend_inbound';
export const LOOKBACK_DAYS = 14;
export const PAGE = 25;
export const MAX_PAGES = 4;
// ponytail: at most MAX_HAND hand-offs a tick and none started after HAND_BUDGET_MS; the rest wait 15 minutes in the
// mailbox (unseen, so never lost). Raise both if replies ever arrive faster than ~20 an hour.
export const MAX_HAND = 8;
export const HAND_BUDGET_MS = 30_000;
// ponytail: per-mailbox and tenant caps keep one busy mailbox from starving the tick or the edge CPU limit; the rest wait
// unseen for 15 minutes. The listing carries no bodies; a message's body is read only when it is handed.
export const MAILBOX_HAND_CAP = 4;
export const TENANT_HAND_CAP = 12;
export const MAX_MAILBOXES = 25;
export const JUNK_PAGES = 2;
export const FILED_FOLDER_CAP = 10;
export const FILED_PAGES = 2;
// Graph v1.0 lists no well-known name here, so these go by display name. A folder missed in another language is still
// safe for Sent and Drafts: our own domain is never handed.
const NOT_FILED_MAIL = /^(inbox|junk e-?mail|drafts|sent items|deleted items|outbox|archive|conversation history|clutter|rss (feeds|subscriptions)|sync issues)$/i;
export const DEFAULT_MAILBOXES = ['management@quotesdone.com', 'info@quotesdone.com'];
export const LIST_BUDGET_MS = 20_000;
export const MAX_ATTACHMENT_BYTES = 15 * 1024 * 1024;
const META_SELECT = 'id,internetMessageId,subject,from,receivedDateTime,hasAttachments,internetMessageHeaders';
const MACHINE_LOCAL = /(^|[-_.+])(alerts?|no-?reply|do-?not-?reply|donotreply|dmarc|reports?|notifications?|notify|billing|statements?|invoices?|receipts?|bounces?)([-_.+]|$)/i;
const FINANCIAL_DOMAIN = /(^|\.)mashreq[^.]*\./i;
const DMARC_ATTACHMENT = /dmarc|tlsrpt|![^!]+![0-9]+![0-9]+/i;
const FULL_SELECT = 'id,internetMessageId,subject,from,receivedDateTime,hasAttachments,body,internetMessageHeaders';
const OWN_ADDRESS = /@(?:mail\.)?quotesdone\.(?:com|ae)$/i;
const TENANT_ADDRESS = /^[a-z0-9._+-]+@quotesdone\.(?:com|ae)$/;
const GRAPH = 'https://graph.microsoft.com/v1.0';
const SECRET_NAMES = ['MS_TENANT_ID', 'MS_CLIENT_ID', 'MS_CLIENT_SECRET'] as const;

export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export type GraphMessage = {
  id: string; internetMessageId?: string; subject?: string; receivedDateTime?: string; hasAttachments?: boolean;
  from?: { emailAddress?: { address?: string; name?: string } }; body?: { contentType?: string; content?: string };
  internetMessageHeaders?: Array<{ name?: string; value?: string }>;
};
export type InboxDeps = {
  fetchFn: Fetch;
  env: (k: string) => string | undefined;
  mailbox: string | undefined;
  /** resend_inbound_token and resend_inbound_signing_secret, read from app_secrets by the caller. */
  inboundToken: string | undefined;
  signingSecret: string | undefined;
  inboundUrl: string;
  /** provider ids already in inbound_messages, out of those asked. */
  onFile: (providerIds: string[]) => Promise<Set<string>>;
  fileFinding: (args: Record<string, unknown>) => Promise<unknown>;
  record: (status: 'ok' | 'held' | 'error', counts: Record<string, unknown>, note: string) => Promise<unknown>;
  now?: () => number;
  /** Who wrote: the founder or staff, a known lead or customer, or a stranger. Throws when it cannot tell. */
  sender?: (address: string) => Promise<SenderKind>;
  /** Of these RFC Message-IDs, those inbound_messages already holds, from any mailbox. */
  messageOnFile?: (ids: string[]) => Promise<Set<string>>;
};
export type SenderKind = 'founder' | 'known' | null;
export type TenantDeps = Omit<InboxDeps, 'mailbox' | 'fileFinding' | 'sender'> & {
  /** supplier@: read by pollReplyInbox, skipped here. */
  inviteMailbox: string | undefined;
  /** app_secrets.m365_tenant_mailboxes, comma separated: used when Graph refuses the /users listing. */
  listedMailboxes: string | undefined;
  /** app_secrets.m365_tenant_strangers_from: ISO time of first deployment. Missing or unreadable: no stranger is handed. */
  strangersFrom: string | undefined;
  /** app_secrets.m365_financial_domains, comma separated, on top of any mashreq* domain. */
  financialDomains: string | undefined;
  sender: (address: string) => Promise<SenderKind>;
};

/** What a folder may hand over. The founder, staff and our own domains never; Junk only a delivery report or a known sender. */
export function folderHands(folder: string, from: string, kind: SenderKind): boolean {
  if (kind === 'founder' || OWN_ADDRESS.test(from)) return false;
  return folder !== 'junkemail' || kind === 'known' || isDeliveryReportSender(from);
}

/** A bank or listed financial domain, itself or a subdomain. */
export function financialSender(from: string, listed: string | undefined): boolean {
  const domain = from.split('@')[1] || '';
  if (FINANCIAL_DOMAIN.test(domain + '.')) return true;
  return String(listed || '').toLowerCase().split(',').map((x) => x.trim()).filter(Boolean).some((x) => domain === x || domain.endsWith('.' + x));
}
/** alerts@, no-reply@, dmarc@, billing@ and the like, or a mail system's own report sender. */
export function machineSender(from: string): boolean {
  return MACHINE_LOCAL.test(from.split('@')[0] || '') || isDeliveryReportSender(from);
}
/** The Message-IDs a message answers: In-Reply-To and References. */
export function threadIds(m: GraphMessage): string[] {
  const h = headersOf(m.internetMessageHeaders);
  return [...new Set(`${h['in-reply-to'] || ''} ${h['references'] || ''}`.match(/<[^<>\s]+>/g) || [])];
}

/** The one it_engineer finding when the app may not read the mailbox. Names the permission and the click, no secret. */
export function unreadableFinding(mailbox: string, status: number, code: string): Record<string, unknown> {
  return {
    p_issue_key: M365_INBOX_UNREADABLE,
    p_title: 'Replies to ' + mailbox + ' cannot be read: the Microsoft 365 app lacks the Graph permission Mail.ReadWrite',
    p_where: 'resilience_ping itintegrations (_shared/m365_reply_inbox.ts)', p_blast: 'internal', p_affected: 1,
    p_evidence: {
      mailbox, graph_status: status, graph_code: code,
      effect: 'the invitation lane keeps Reply-To suppliers@mail.quotesdone.com (no reply is lost) and cannot drop it until the reader is proven',
      founder_action: 'Microsoft Entra admin center > App registrations > the QuotesDone mail app (MS_CLIENT_ID) > API permissions > Add a permission > Microsoft Graph > Application permissions > Mail.ReadWrite > Add permissions > Grant admin consent for the tenant',
      optional_restriction: 'Exchange Online PowerShell: New-ApplicationAccessPolicy -AppId <MS_CLIENT_ID> -PolicyScopeGroupId <mail-enabled security group containing ' + mailbox + '> -AccessRight RestrictAccess -Description "QuotesDone mail app: supplier mailbox only"',
    },
    p_ruled_out: [], p_undetermined: [], p_raised_by: 'it_engineer',
  };
}

/** Graph's header list as resend_inbound reads it: lower-case names, the first value of a repeated header kept. */
export function headersOf(list: GraphMessage['internetMessageHeaders']): Record<string, string> {
  const out: Record<string, string> = {};
  for (const h of list || []) {
    const k = String(h?.name || '').toLowerCase().trim();
    if (k && !(k in out)) out[k] = String(h?.value ?? '');
  }
  return out;
}

/** One Graph message as the Resend 'email.received' delivery resend_inbound already handles. */
export function inboundPayload(m: GraphMessage, mailbox: string, attachments: Array<Record<string, unknown>>): Record<string, unknown> {
  const headers = headersOf(m.internetMessageHeaders);
  const isHtml = String(m.body?.contentType || '').toLowerCase() === 'html';
  return {
    type: 'email.received',
    data: {
      email_id: M365_INBOUND_PREFIX + m.id,
      message_id: m.internetMessageId || headers['message-id'] || null,
      from: m.from?.emailAddress?.address || '',
      to: mailbox,
      subject: m.subject || '',
      ...(isHtml ? { html: m.body?.content || '' } : { text: m.body?.content || '' }),
      headers,
      attachments,
      created_at: m.receivedDateTime || null,
    },
  };
}

const b64 = (u8: Uint8Array) => { let s = ''; for (const b of u8) s += String.fromCharCode(b); return btoa(s); };

/** The Svix headers resend_inbound's verifySvix accepts: base64 HMAC-SHA256 over "<id>.<ts>.<body>". */
export async function svixHeaders(secret: string, body: string, id: string, nowMs: number): Promise<Record<string, string>> {
  const ts = String(Math.floor(nowMs / 1000));
  const raw = secret.startsWith('whsec_') ? secret.slice(6) : secret;
  const key = await crypto.subtle.importKey('raw', Uint8Array.from(atob(raw), (c) => c.charCodeAt(0)), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(id + '.' + ts + '.' + body)));
  return { 'svix-id': id, 'svix-timestamp': ts, 'svix-signature': 'v1,' + b64(mac) };
}

async function token(f: Fetch, tenant: string, client: string, secret: string): Promise<string> {
  const r = await f(`https://login.microsoftonline.com/${encodeURIComponent(tenant)}/oauth2/v2.0/token`, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: client, client_secret: secret, scope: 'https://graph.microsoft.com/.default', grant_type: 'client_credentials' }).toString(),
  });
  const j = await r.json().catch(() => ({})) as { access_token?: string; error?: string };
  if (!r.ok || !j.access_token) throw new Error(`token refused (HTTP ${r.status}${j.error ? ', ' + j.error : ''})`);
  return j.access_token;
}

/** One tick. Never throws; returns counts and a reason only. */
export async function pollReplyInbox(d: InboxDeps): Promise<Record<string, unknown>> {
  const now = d.now || Date.now;
  const t0 = now();
  const mailbox = String(d.mailbox || '').trim().toLowerCase();
  const counts = { m365_inbox: 1, listed: 0, new: 0, handed: 0, duplicate: 0, hand_failed: 0, mark_failed: 0, deferred: 0 };
  const done = async (status: 'ok' | 'held' | 'error', why: string, extra: Record<string, unknown> = {}) => {
    try { await d.record(status, { ...counts, ...extra }, 'm365 reply inbox (' + mailbox + '): ' + why); } catch (_e) { /* the answer still says */ }
    return { ok: status !== 'error', readable: status === 'ok', why, ...counts, ...extra };
  };
  if (!/^[a-z0-9._+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(mailbox)) return await done('held', 'invite_m365_mailbox is not an address');
  const [tenant, client, secret] = SECRET_NAMES.map((k) => String(d.env(k) || '').trim());
  const missing = SECRET_NAMES.filter((k) => !String(d.env(k) || '').trim());
  if (missing.length) return await done('held', 'edge secret(s) not set: ' + missing.join(', '));
  if (!d.inboundToken || !d.signingSecret) return await done('error', 'resend_inbound_token or resend_inbound_signing_secret unreadable; nothing can be handed in');
  let auth: Record<string, string>;
  try { auth = { Authorization: 'Bearer ' + await token(d.fetchFn, tenant, client, secret), Prefer: 'IdType="ImmutableId", outlook.body-content-type="text"' }; }
  catch (e) { return await done('error', String((e as Error)?.message || e).split(secret).join('[redacted]').slice(0, 200)); }

  // ---- list
  const since = new Date(t0 - LOOKBACK_DAYS * 86_400_000).toISOString();
  const box = `${GRAPH}/users/${encodeURIComponent(mailbox)}`;
  let url: string | null = `${box}/mailFolders/inbox/messages?` + new URLSearchParams({
    $filter: `receivedDateTime ge ${since}`, $orderby: 'receivedDateTime desc', $top: String(PAGE),
    $select: 'id,internetMessageId,subject,from,receivedDateTime,hasAttachments,body,internetMessageHeaders',
  }).toString();
  const fresh: GraphMessage[] = [];
  for (let page = 0; url && page < MAX_PAGES; page++) {
    let r: Response;
    try { r = await d.fetchFn(url, { headers: auth }); } catch (e) { return await done('error', 'the Graph listing did not answer: ' + String((e as Error)?.message || e).slice(0, 160)); }
    if (r.status === 401 || r.status === 403) {
      const j = await r.json().catch(() => ({})) as { error?: { code?: string } };
      const code = String(j?.error?.code || '');
      try { await d.fileFinding(unreadableFinding(mailbox, r.status, code)); } catch (_e) { /* the held row still withdraws the proof */ }
      return await done('held', `Graph refused the Inbox listing (HTTP ${r.status} ${code}); Mail.ReadWrite is not granted`);
    }
    if (!r.ok) return await done('error', `Graph answered the Inbox listing with HTTP ${r.status}`);
    const j = await r.json().catch(() => ({})) as { value?: GraphMessage[]; '@odata.nextLink'?: string };
    const list = (j.value || []).filter((m) => m && typeof m.id === 'string' && m.id);
    counts.listed += list.length;
    const seen = list.length ? await d.onFile(list.map((m) => M365_INBOUND_PREFIX + m.id)) : new Set<string>();
    const unseen = list.filter((m) => !seen.has(M365_INBOUND_PREFIX + m.id));
    fresh.push(...unseen);
    // newest first: a page with nothing new means everything older was handled on an earlier tick
    if (!unseen.length) break;
    url = j['@odata.nextLink'] || null;
  }
  counts.new = fresh.length;

  // ---- hand over, oldest first, so a conversation reaches the platform in the order it was written
  for (const m of fresh.reverse()) {
    if (counts.handed + counts.duplicate + counts.hand_failed >= MAX_HAND || now() - t0 > HAND_BUDGET_MS) { counts.deferred++; continue; }
    // the same message already taken from another mailbox: one answer per message
    const mid = String(m.internetMessageId || '');
    if (mid && d.messageOnFile) {
      let dup = false;
      try { dup = (await d.messageOnFile([mid])).has(mid); } catch (_e) { /* the handler still refuses a same-id redelivery */ }
      if (dup) { counts.duplicate++; if (!await markRead(d, box, auth, m.id)) counts.mark_failed++; continue; }
    }
    const r = await handOver(d, box, mailbox, auth, m);
    if (r === 'failed') { counts.hand_failed++; continue; }   // left unread and unseen: the next tick hands it again
    if (r === 'duplicate') counts.duplicate++; else counts.handed++;
    if (!await markRead(d, box, auth, m.id)) counts.mark_failed++;
  }
  // Junk never touches the proof: a reply in the Inbox is read whatever Junk answers.
  const junk: Tally = { handed: 0, duplicate: 0, hand_failed: 0, mark_failed: 0, deferred: 0, not_handed: 0, lookup_failed: 0, skipped: 0, same_message: 0 };
  const junkStatus = await sweep(d, mailbox, box, auth, 'junkemail', JUNK_PAGES, Math.max(0, MAX_HAND - counts.handed - counts.duplicate), t0, junk, true, d.sender || (() => Promise.resolve(null)), new Map());
  const junkCounts = { junk_handed: junk.handed, junk_not_handed: junk.not_handed, junk_failed: junk.hand_failed + junk.lookup_failed + (junkStatus === 200 ? 0 : 1) };
  if (counts.hand_failed) return await done('error', counts.hand_failed + ' message(s) could not be handed to resend_inbound; left in the Inbox for the next tick', junkCounts);
  return await done('ok', 'read', junkCounts);
}

type Sweep = Pick<InboxDeps, 'fetchFn' | 'inboundToken' | 'signingSecret' | 'inboundUrl' | 'onFile' | 'now' | 'messageOnFile'>;
type Tally = { handed: number; duplicate: number; hand_failed: number; mark_failed: number; deferred: number; not_handed: number; lookup_failed: number; skipped: number; same_message: number };

/** Hands one whole message to resend_inbound, Svix-signed exactly as Resend's own delivery. Nothing else is done to it. */
async function handOver(d: Sweep, box: string, mailbox: string, auth: Record<string, string>, m: GraphMessage): Promise<'handed' | 'duplicate' | 'failed'> {
  const now = d.now || Date.now;
  const one = `${box}/messages/${encodeURIComponent(m.id)}`;
  let attachments: Array<Record<string, unknown>> = [];
  if (m.hasAttachments) {
    try {
      const a = await d.fetchFn(`${one}/attachments`, { headers: auth });
      const aj = a.ok ? await a.json() as { value?: Array<Record<string, unknown>> } : { value: [] };
      attachments = (aj.value || []).filter((x) => x['@odata.type'] === '#microsoft.graph.fileAttachment' && x.contentBytes && Number(x.size || 0) <= MAX_ATTACHMENT_BYTES)
        .slice(0, 6).map((x) => ({ filename: x.name, content_type: x.contentType, content: x.contentBytes }));
    } catch (_e) { attachments = []; }
  }
  const body = JSON.stringify(inboundPayload(m, mailbox, attachments));
  try {
    const h = await svixHeaders(String(d.signingSecret), body, 'msg_' + M365_INBOUND_PREFIX.slice(0, -1) + '_' + m.id.slice(-40).replace(/[^A-Za-z0-9]/g, ''), now());
    const r = await d.fetchFn(d.inboundUrl + '?s=' + encodeURIComponent(String(d.inboundToken)), { method: 'POST', headers: { 'Content-Type': 'application/json', ...h }, body });
    const rj = await r.json().catch(() => ({})) as { duplicate?: boolean };
    return !r.ok ? 'failed' : rj?.duplicate ? 'duplicate' : 'handed';
  } catch (_e) { return 'failed'; }
}

/** supplier@ only. No other mailbox is ever marked (its people read it). A mark that fails is counted, never fatal. */
async function markRead(d: Sweep, box: string, auth: Record<string, string>, id: string): Promise<boolean> {
  try {
    const p = await d.fetchFn(`${box}/messages/${encodeURIComponent(id)}`, { method: 'PATCH', headers: { ...auth, 'Content-Type': 'application/json' }, body: JSON.stringify({ isRead: true }) });
    return p.ok;
  } catch (_e) { return false; }
}

/**
 * One folder of one mailbox: list the envelopes, keep what is new and allowed, read and hand at most `cap`, oldest first.
 * Returns the listing's HTTP status (0: no answer). Mail not handed stays unseen, so it is looked at again next tick.
 */
async function sweep(d: Sweep, mailbox: string, box: string, auth: Record<string, string>, folder: string, pages: number, cap: number, t0: number,
  c: Tally, mark: boolean, sender: (a: string) => Promise<SenderKind>, kinds: Map<string, SenderKind>,
  gate?: (m: GraphMessage, from: string, kind: SenderKind) => Promise<boolean>, handedIds: Set<string> = new Set()): Promise<number> {
  const now = d.now || Date.now;
  const since = new Date(t0 - LOOKBACK_DAYS * 86_400_000).toISOString();
  let url: string | null = `${box}/mailFolders/${encodeURIComponent(folder)}/messages?` + new URLSearchParams({ $filter: `receivedDateTime ge ${since}`, $orderby: 'receivedDateTime desc', $top: String(PAGE), $select: META_SELECT }).toString();
  const fresh: GraphMessage[] = [];
  let status = 200;
  try {
    for (let page = 0; url && page < pages; page++) {
      if (now() - t0 > LIST_BUDGET_MS) { c.deferred++; break; }
      const r: Response = await d.fetchFn(url, { headers: auth });
      status = r.status;
      if (!r.ok) { await r.body?.cancel(); return status; }
      const j = await r.json().catch(() => ({})) as { value?: GraphMessage[]; '@odata.nextLink'?: string };
      const list = (j.value || []).filter((m) => m && typeof m.id === 'string' && m.id);
      const seen = list.length ? await d.onFile(list.map((m) => M365_INBOUND_PREFIX + m.id)) : new Set<string>();
      fresh.push(...list.filter((m) => !seen.has(M365_INBOUND_PREFIX + m.id)));
      // Unlike the supplier Inbox, a page with nothing new proves nothing older was handled: mail not handed is never on file.
      url = j['@odata.nextLink'] || null;
    }
  } catch (_e) { return 0; }
  let used = 0;
  for (const m of fresh.reverse()) {
    if (now() - t0 > HAND_BUDGET_MS) { c.deferred++; continue; }
    const from = String(m.from?.emailAddress?.address || '').trim().toLowerCase();
    let kind = kinds.get(from);
    if (kind === undefined) {
      try { kind = from ? await sender(from) : null; kinds.set(from, kind); }
      catch (_e) { c.lookup_failed++; continue; }   // who wrote is unknown: not handed, looked at again next tick
    }
    if (!from || !folderHands(folder, from, kind)) { c.not_handed++; continue; }
    const mid = String(m.internetMessageId || '');
    try {
      if (gate && !await gate(m, from, kind)) { c.skipped++; continue; }
      if (mid && (handedIds.has(mid) || (d.messageOnFile && (await d.messageOnFile([mid])).has(mid)))) { c.same_message++; continue; }
    } catch (_e) { c.lookup_failed++; continue; }
    if (used >= cap) { c.deferred++; continue; }
    used++;
    let whole: GraphMessage;
    try {
      const r = await d.fetchFn(`${box}/messages/${encodeURIComponent(m.id)}?$select=${FULL_SELECT}`, { headers: auth });
      if (!r.ok) { await r.body?.cancel(); c.hand_failed++; continue; }
      whole = await r.json() as GraphMessage;
    } catch (_e) { c.hand_failed++; continue; }
    const r = await handOver(d, box, mailbox, auth, { ...m, ...whole, id: m.id, hasAttachments: !!(m.hasAttachments && whole.hasAttachments) });
    if (r === 'failed') { c.hand_failed++; continue; }
    if (mid) handedIds.add(mid);
    if (r === 'duplicate') c.duplicate++; else c.handed++;
    if (mark && !await markRead(d, box, auth, m.id)) c.mark_failed++;
  }
  return status;
}

/** A mailbox's own top-level folders that can hold filed mail; null when Graph would not list them. */
async function filedFolders(d: Sweep, box: string, auth: Record<string, string>): Promise<string[] | null> {
  try {
    const r = await d.fetchFn(`${box}/mailFolders?$top=50&$select=id,displayName`, { headers: auth });
    if (!r.ok) { await r.body?.cancel(); return null; }
    const j = await r.json() as { value?: Array<{ id?: string; displayName?: string }> };
    return (j.value || []).filter((f) => f?.id && !NOT_FILED_MAIL.test(String(f.displayName || '').trim())).map((f) => String(f.id)).slice(0, FILED_FOLDER_CAP);
  } catch (_e) { return null; }
}

/** The mailboxes to read: Graph's own list where the app may ask, else app_secrets, else the two the founder named. */
async function tenantMailboxes(d: TenantDeps, auth: Record<string, string>): Promise<{ boxes: string[]; source: string }> {
  const keep = (list: unknown[]) => {
    const invite = String(d.inviteMailbox || '').trim().toLowerCase();
    return [...new Set(list.map((a) => String(a || '').trim().toLowerCase()))]
      .filter((a) => TENANT_ADDRESS.test(a) && a !== invite && !/^expenses?@/.test(a));
  };
  try {
    const out: unknown[] = [];
    let url: string | null = `${GRAPH}/users?$select=mail&$top=100`;
    let refused = false;
    for (let page = 0; url && page < 3; page++) {
      const r: Response = await d.fetchFn(url, { headers: auth });
      if (!r.ok) { await r.body?.cancel(); refused = true; break; }
      const j = await r.json() as { value?: Array<{ mail?: string | null }>; '@odata.nextLink'?: string };
      out.push(...(j.value || []).map((u) => u?.mail));
      url = j['@odata.nextLink'] || null;
    }
    if (!refused && out.length) return { boxes: keep(out).slice(0, MAX_MAILBOXES), source: 'graph' };
  } catch (_e) { /* the list below */ }
  const listed = keep(String(d.listedMailboxes || '').split(','));
  return listed.length ? { boxes: listed.slice(0, MAX_MAILBOXES), source: 'app_secrets' } : { boxes: keep(DEFAULT_MAILBOXES), source: 'default' };
}

/** One tick over every other mailbox of the tenant. Never throws; the answer carries counts only (resilience_ping is public). */
export async function pollTenantMailboxes(d: TenantDeps): Promise<Record<string, unknown>> {
  const now = d.now || Date.now;
  const t0 = now();
  const c: Tally = { handed: 0, duplicate: 0, hand_failed: 0, mark_failed: 0, deferred: 0, not_handed: 0, lookup_failed: 0, skipped: 0, same_message: 0 };
  const counts = { m365_tenant: 1, mailboxes: 0, no_mailbox: 0, refused: 0, list_failed: 0, out_of_time: 0, attachments_dropped: 0, source: 'none' };
  const done = async (status: 'ok' | 'held' | 'error', why: string, detail = '') => {
    try { await d.record(status, { ...counts, ...c }, 'm365 tenant mailboxes: ' + why + detail); } catch (_e) { /* the answer still says */ }
    return { ok: status !== 'error', why, ...counts, ...c };
  };
  const [tenant, client, secret] = SECRET_NAMES.map((k) => String(d.env(k) || '').trim());
  if (!tenant || !client || !secret) return await done('held', 'edge secrets not set');
  if (!d.inboundToken || !d.signingSecret) return await done('error', 'resend_inbound_token or resend_inbound_signing_secret unreadable');
  let auth: Record<string, string>;
  try { auth = { Authorization: 'Bearer ' + await token(d.fetchFn, tenant, client, secret), Prefer: 'IdType="ImmutableId", outlook.body-content-type="text"' }; }
  catch (e) { return await done('error', String((e as Error)?.message || e).split(secret).join('[redacted]').slice(0, 200)); }
  const { boxes, source } = await tenantMailboxes(d, auth);
  counts.source = source;
  // The start moves each 15-minute tick, so the last mailbox is not always the one the budget cuts off.
  const start = boxes.length ? Math.floor(t0 / 900_000) % boxes.length : 0;
  const kinds = new Map<string, SenderKind>();
  const handedIds = new Set<string>();
  const cutoff = Date.parse(String(d.strangersFrom || ''));
  // BY DECISION, strangers stay off until app_secrets.m365_tenant_strangers_from is set: without it, only known senders
  // and replies in our threads are handed.
  // Decided from the envelope: what is refused here has no body read and nothing stored.
  const gateFor = (box: string) => async (m: GraphMessage, from: string, kind: SenderKind): Promise<boolean> => {
    if (financialSender(from, d.financialDomains)) return false;
    let allowed = kind === 'known';
    if (!allowed) {
      const ids = threadIds(m);
      allowed = ids.some((i) => i.includes('qd-notif-')) || (ids.length > 0 && !!d.messageOnFile && (await d.messageOnFile(ids)).size > 0);
    }
    if (!allowed) {
      if (machineSender(from)) return false;
      if (!Number.isFinite(cutoff) || !(Date.parse(String(m.receivedDateTime || '')) >= cutoff)) return false;
    }
    if (m.hasAttachments) {
      const r = await d.fetchFn(`${box}/messages/${encodeURIComponent(m.id)}/attachments?$select=name,contentType,size`, { headers: auth });
      if (!r.ok) { await r.body?.cancel(); throw new Error('attachment list refused'); }
      const list = ((await r.json()) as { value?: Array<{ name?: string; contentType?: string; size?: number }> }).value || [];
      if (!allowed && list.some((a) => DMARC_ATTACHMENT.test(String(a.name || '') + ' ' + String(a.contentType || '')))) return false;
      if (list.reduce((n, a) => n + Number(a.size || 0), 0) > MAX_ATTACHMENT_BYTES) { m.hasAttachments = false; counts.attachments_dropped++; }
    }
    return true;
  };
  const read: string[] = [];
  const spent = () => c.handed + c.duplicate + c.hand_failed;
  for (let i = 0; i < boxes.length; i++) {
    if (now() - t0 > HAND_BUDGET_MS) { counts.out_of_time = boxes.length - i; break; }
    const mailbox = boxes[(start + i) % boxes.length];
    const box = `${GRAPH}/users/${encodeURIComponent(mailbox)}`;
    const before = spent();
    const room = () => Math.max(0, Math.min(MAILBOX_HAND_CAP - (spent() - before), TENANT_HAND_CAP - spent()));
    const gate = gateFor(box);
    const status = await sweep(d, mailbox, box, auth, 'inbox', MAX_PAGES, room(), t0, c, false, d.sender, kinds, gate, handedIds);
    if (status === 404) { counts.no_mailbox++; continue; }   // an account with no mailbox
    if (status === 401 || status === 403) { counts.refused++; continue; }
    if (status !== 200) { counts.list_failed++; continue; }
    counts.mailboxes++; read.push(mailbox);
    if (await sweep(d, mailbox, box, auth, 'junkemail', JUNK_PAGES, room(), t0, c, false, d.sender, kinds, gate, handedIds) !== 200) counts.list_failed++;
    const filed = await filedFolders(d, box, auth);
    if (!filed) { counts.list_failed++; continue; }
    for (const f of filed) if (await sweep(d, mailbox, box, auth, f, FILED_PAGES, room(), t0, c, false, d.sender, kinds, gate, handedIds) !== 200) counts.list_failed++;
  }
  const detail = '; read ' + (read.join(', ') || 'none') + ' (list from ' + source + ')';
  if (c.hand_failed || counts.list_failed || c.lookup_failed) return await done('error', 'a failure is left for the next tick', detail);
  if (!counts.mailboxes) return await done('held', 'no mailbox could be read', detail);
  return await done('ok', 'read', detail);
}
