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
};

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
    const one = `${box}/messages/${encodeURIComponent(m.id)}`;
    let attachments: Array<Record<string, unknown>> = [];
    if (m.hasAttachments) {
      try {
        const a = await d.fetchFn(`${one}/attachments`, { headers: auth });
        const aj = a.ok ? await a.json() as { value?: Array<Record<string, unknown>> } : { value: [] };
        attachments = (aj.value || []).filter((x) => x['@odata.type'] === '#microsoft.graph.fileAttachment' && x.contentBytes)
          .slice(0, 6).map((x) => ({ filename: x.name, content_type: x.contentType, content: x.contentBytes }));
      } catch (_e) { attachments = []; }
    }
    const body = JSON.stringify(inboundPayload(m, mailbox, attachments));
    let ok = false, duplicate = false;
    try {
      const h = await svixHeaders(d.signingSecret, body, 'msg_' + M365_INBOUND_PREFIX.slice(0, -1) + '_' + m.id.slice(-40).replace(/[^A-Za-z0-9]/g, ''), now());
      const r = await d.fetchFn(d.inboundUrl + '?s=' + encodeURIComponent(d.inboundToken), { method: 'POST', headers: { 'Content-Type': 'application/json', ...h }, body });
      const rj = await r.json().catch(() => ({})) as { duplicate?: boolean };
      ok = r.ok; duplicate = !!rj?.duplicate;
    } catch (_e) { ok = false; }
    if (!ok) { counts.hand_failed++; continue; }   // left unread and unseen: the next tick hands it again
    if (duplicate) counts.duplicate++; else counts.handed++;
    try {
      const p = await d.fetchFn(one, { method: 'PATCH', headers: { ...auth, 'Content-Type': 'application/json' }, body: JSON.stringify({ isRead: true }) });
      if (!p.ok) counts.mark_failed++;
    } catch (_e) { counts.mark_failed++; }
  }
  if (counts.hand_failed) return await done('error', counts.hand_failed + ' message(s) could not be handed to resend_inbound; left in the Inbox for the next tick');
  return await done('ok', 'read');
}
