// AN M365 SEND SAYS WHETHER IT LEFT (2 Nov 2026, sales_engineer; scripts/sql/an_m365_invitation_says_whether_it_left_and_whether_it_bounced.sql).
//
// Graph's sendMail answers 202 with no id and sends no later event, so every invitation from supplier@ read provider_status
// NULL for good (46 of 46 since 29 Oct, measured 2 Nov). This asks Graph, each resilience_ping beat, for up to CLAIM sends
// in the mailbox's Sent Items by the internetMessageId send_outbox gave them (m365_lane.ts messageIdFor), and records what
// Graph answers through fn_m365_sent_status_record: found = 'sent' at Graph's sentDateTime; a 200 with no such message =
// one try, 'unreadable' after five; a refused token, 429, 5xx or timeout is no answer and is never counted (review of
// #1792). It never writes 'delivered': Sent Items proves Exchange sent it, nothing more. A
// bounce is written by fn_mail_bounce_marks_its_send from the delivery report the reply reader hands in.
// Same app and secrets as the reply reader (MS_TENANT_ID / MS_CLIENT_ID / MS_CLIENT_SECRET, Mail.ReadWrite). Counts only:
// resilience_ping is public.
import { graphToken, type Fetch } from './m365_reply_inbox.ts';

export const CLAIM = 20;
export const BUDGET_MS = 20_000;
const GRAPH = 'https://graph.microsoft.com/v1.0';
const SECRET_NAMES = ['MS_TENANT_ID', 'MS_CLIENT_ID', 'MS_CLIENT_SECRET'] as const;

export type Claimed = { notification_id: number; message_id: string };
export type SentDeps = {
  fetchFn: Fetch;
  env: (k: string) => string | undefined;
  mailbox: string | undefined;
  claim: (limit: number) => Promise<Claimed[]>;
  record: (id: number, found: boolean, sentAt: string | null, http: number | null, code: string | null) => Promise<unknown>;
  now?: () => number;
};

/** The Sent Items query for one Message-ID (OData string literal: a single quote is doubled). */
export function sentItemsUrl(mailbox: string, messageId: string): string {
  return `${GRAPH}/users/${encodeURIComponent(mailbox)}/mailFolders/sentitems/messages?` + new URLSearchParams({
    $filter: `internetMessageId eq '${messageId.replace(/'/g, "''")}'`, $select: 'id,internetMessageId,sentDateTime', $top: '1',
  }).toString();
}

/** One beat. Never throws. */
export async function pollM365SentStatus(d: SentDeps): Promise<Record<string, unknown>> {
  const now = d.now || Date.now;
  const t0 = now();
  const c = { claimed: 0, sent: 0, not_found: 0, failed: 0, deferred: 0 };
  const mailbox = String(d.mailbox || '').trim().toLowerCase();
  if (!/^[a-z0-9._+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(mailbox)) return { ok: true, held: 'invite_m365_mailbox is not an address', ...c };
  const [tenant, client, secret] = SECRET_NAMES.map((k) => String(d.env(k) || '').trim());
  if (!tenant || !client || !secret) return { ok: true, held: 'edge secrets not set', ...c };
  let rows: Claimed[];
  try { rows = await d.claim(CLAIM); } catch (e) { return { ok: false, why: 'claim: ' + String((e as Error)?.message || e).slice(0, 160), ...c }; }
  c.claimed = rows.length;
  if (!rows.length) return { ok: true, ...c };
  let auth: Record<string, string>;
  try { auth = { Authorization: 'Bearer ' + await graphToken(d.fetchFn, tenant, client, secret) }; }
  catch (e) {
    // an outage, not an answer about any send: nothing is recorded, and the claim's stamp asks them again in 30 minutes
    return { ok: false, why: String((e as Error)?.message || e).split(secret).join('[redacted]').slice(0, 200), ...c };
  }
  for (const r of rows) {
    if (now() - t0 > BUDGET_MS) { c.deferred++; continue; }   // claimed, so asked again in 30 minutes
    let found = false, sentAt: string | null = null, http: number | null = null, code: string | null = null;
    try {
      const res = await d.fetchFn(sentItemsUrl(mailbox, r.message_id), { headers: auth });
      http = res.status;
      if (res.ok) {
        const j = await res.json().catch(() => ({})) as { value?: Array<{ internetMessageId?: string; sentDateTime?: string }> };
        const hit = (j.value || []).find((m) => m?.internetMessageId === r.message_id);
        found = !!hit; sentAt = hit?.sentDateTime || null;
        if (!found) code = 'm365:not_in_sent_items';
      } else { await res.body?.cancel(); code = 'http:' + res.status; }
    } catch (_e) { code = 'm365:no_answer'; }
    try { await d.record(r.notification_id, found, sentAt, http, code); } catch (_e) { c.failed++; continue; }
    if (found) c.sent++; else if (code === 'm365:not_in_sent_items') c.not_found++; else c.failed++;
  }
  return { ok: true, ...c };
}
