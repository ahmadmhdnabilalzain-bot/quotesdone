// meta.ts — the Meta (Instagram + Facebook Page) webhook contract, pure and tested (meta.test.ts).
//
// Seat: marketing. 22 Sep 2026, founder: "if there was any communication on Instagram or any social
// media platform, there should be an automated reply in which he [the marketing seat] is aware of
// and he carries on."
//
// What Meta sends (Graph API v21):
//   GET  ?hub.mode=subscribe&hub.verify_token=…&hub.challenge=…   the subscription handshake
//   POST body signed X-Hub-Signature-256: sha256=<hex HMAC-SHA256(app secret, RAW body)>
//     object 'page'      entry[].messaging[] (Messenger DMs, echoes, reads, deliveries)
//                        entry[].changes[] field 'feed' value.item 'comment' (Page comments)
//     object 'instagram' entry[].messaging[] (Instagram DMs, echoes)
//                        entry[].changes[] field 'comments' (Instagram comments)
// entry[].id is OUR Page id / Instagram account id. Anything whose author is that id is us.

export type Platform = 'facebook' | 'instagram';
export type Channel = 'dm' | 'comment';

export interface InboundEvent {
  platform: Platform;
  channel: Channel;
  accountId: string;          // our Page / IG account id (entry.id)
  userId: string;             // the person (PSID / IGSID / commenter id)
  handle: string | null;      // username or name when Meta gives one (comments do; DMs do not)
  messageId: string;          // mid for a DM, comment id for a comment — the idempotency key
  text: string;
  at: Date;                   // when the person wrote it (Meta's timestamp, not our receipt time)
  parentId: string | null;    // post / media id for a comment
  echo: boolean;              // a message the PAGE sent (from us or from a human in the Meta inbox)
  echoAppId: string | null;   // app_id on a Messenger echo: ours means the seat sent it
  echoMetadata: string | null;
}

/** Constant-time comparison of two hex strings. */
function sameHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

/**
 * X-Hub-Signature-256 over the RAW body. A missing secret is a refusal, never a pass: an unsigned
 * webhook would let anyone make the seat talk to (and message) any Instagram user id they typed.
 */
export async function verifySignature(rawBody: string, header: string | null, appSecret: string | undefined): Promise<boolean> {
  if (!appSecret || !header || !header.startsWith('sha256=')) return false;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(appSecret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody)));
  const hex = [...mac].map((b) => b.toString(16).padStart(2, '0')).join('');
  return sameHex(hex, header.slice(7).toLowerCase());
}

/** The GET handshake. Returns the challenge to echo back, or null to refuse (403). */
export function handshake(url: URL, verifyToken: string | undefined): string | null {
  const mode = url.searchParams.get('hub.mode');
  const token = url.searchParams.get('hub.verify_token') || '';
  const challenge = url.searchParams.get('hub.challenge');
  if (mode !== 'subscribe' || !challenge || !verifyToken) return null;
  return sameHex(token, verifyToken) ? challenge : null;
}

const str = (v: unknown) => (v == null ? '' : String(v));

/**
 * Every message or comment in a webhook body, as one flat list. Reads, deliveries, reactions,
 * postbacks without text, edits and deletions are dropped: there is nothing in them to answer.
 * Our OWN comments (author = our account) are dropped here too — that is the comment half of the
 * no-reply-loop rule; the DM half is `echo`, which is kept so the caller can tell the seat's own
 * echo from a human answering in the Meta inbox.
 */
export function parseEvents(body: any): InboundEvent[] {
  const platform: Platform | null = body?.object === 'instagram' ? 'instagram' : body?.object === 'page' ? 'facebook' : null;
  if (!platform) return [];
  const out: InboundEvent[] = [];
  for (const e of Array.isArray(body.entry) ? body.entry : []) {
    const accountId = str(e?.id);
    for (const m of Array.isArray(e?.messaging) ? e.messaging : []) {
      const msg = m?.message;
      if (!msg || !msg.mid || msg.is_deleted) continue;
      const text = str(msg.text).trim();
      if (!text) continue;                                   // stickers/attachments only: nothing to answer
      const echo = msg.is_echo === true;
      out.push({
        platform, channel: 'dm', accountId,
        userId: echo ? str(m?.recipient?.id) : str(m?.sender?.id),
        handle: null, messageId: str(msg.mid), text,
        at: new Date(Number(m?.timestamp) || Date.now()), parentId: null, echo,
        echoAppId: echo && msg.app_id != null ? str(msg.app_id) : null,
        echoMetadata: echo && msg.metadata != null ? str(msg.metadata) : null,
      });
    }
    for (const c of Array.isArray(e?.changes) ? e.changes : []) {
      const v = c?.value || {};
      let ev: InboundEvent | null = null;
      if (platform === 'facebook' && c?.field === 'feed' && v.item === 'comment' && v.verb === 'add') {
        ev = { platform, channel: 'comment', accountId, userId: str(v.from?.id), handle: v.from?.name ? str(v.from.name) : null,
          messageId: str(v.comment_id), text: str(v.message).trim(),
          at: new Date(Number(v.created_time) * 1000 || Date.now()), parentId: v.post_id ? str(v.post_id) : null,
          echo: false, echoAppId: null, echoMetadata: null };
      } else if (platform === 'instagram' && c?.field === 'comments') {
        ev = { platform, channel: 'comment', accountId, userId: str(v.from?.id), handle: v.from?.username ? str(v.from.username) : null,
          messageId: str(v.id), text: str(v.text).trim(), at: new Date(), parentId: v.media?.id ? str(v.media.id) : null,
          echo: false, echoAppId: null, echoMetadata: null };
      }
      if (!ev || !ev.messageId || !ev.userId || !ev.text) continue;
      if (ev.userId === accountId) continue;                 // our own comment reply: never answer ourselves
      out.push(ev);
    }
  }
  return out;
}

// ── META'S RULES FOR REPLYING ────────────────────────────────────────────────────────────────────
// Standard messaging: a DM may be answered within 24 hours of the person's last message. A webhook
// retried hours later must not produce a reply outside that window, so the window is measured from
// the person's own timestamp, not from when we received it. Private replies to comments have a
// 7-day window; the seat answers comments publicly, so the same 24 hours is used as a freshness rule.
export const WINDOW_MS = 24 * 3600 * 1000;
export const withinWindow = (at: Date, now = new Date()): boolean => now.getTime() - at.getTime() < WINDOW_MS;

// Messenger allows 2,000 characters and Instagram 1,000; a comment reply is kept short on purpose.
export const maxLen = (platform: Platform, channel: Channel): number => (channel === 'comment' ? 300 : platform === 'instagram' ? 950 : 1900);
export const clip = (s: string, n: number): string => (s.length <= n ? s : s.slice(0, n - 1).replace(/\s+\S*$/, '') + '…');

// The marker the seat puts on every Messenger send; its echo comes back carrying it.
export const OUR_METADATA = 'qd_marketing_seat';

/** The Graph API request that answers one event. Pure, so the shape is tested without a network. */
export function sendRequest(ev: InboundEvent, text: string, pageToken: string): { url: string; body: Record<string, unknown> } {
  const base = 'https://graph.facebook.com/v21.0/';
  const q = '?access_token=' + encodeURIComponent(pageToken);
  if (ev.channel === 'comment') {
    return ev.platform === 'instagram'
      ? { url: base + encodeURIComponent(ev.messageId) + '/replies' + q, body: { message: text } }
      : { url: base + encodeURIComponent(ev.messageId) + '/comments' + q, body: { message: text } };
  }
  return {
    url: base + 'me/messages' + q,
    body: {
      recipient: { id: ev.userId }, messaging_type: 'RESPONSE',
      // Instagram's send API rejects unknown message fields, so the echo marker is Messenger-only;
      // an Instagram echo of our own send is recognised by the pending outbound row instead.
      message: ev.platform === 'facebook' ? { text, metadata: OUR_METADATA } : { text },
    },
  };
}
