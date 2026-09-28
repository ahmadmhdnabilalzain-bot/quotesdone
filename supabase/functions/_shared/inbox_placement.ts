// INBOX PLACEMENT, READ BACK FROM THE TWO SEED MAILBOXES (it_engineer, 24 Sep 2026).
//
// Each sending day, fn_invite_placement_due queues one supplier_invite_seed to the founder's Gmail and to his
// Microsoft 365 mailbox from 04:30 UTC, 90 minutes before the batch window opens at 06:00 UTC. It goes through
// the real send path: send_outbox, the effective From (the #963 invitation lane when it is on), Reply-To and
// frame. The subject carries a per-run token, "(ref QD<10 hex>)". This module reads which folder each copy
// landed in and hands the folders to fn_invite_placement_record, which decides the day
// (scripts/sql/the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.sql):
//   * Gmail: users.messages.list with q=subject:<token> and includeSpamTrash, then each message's labelIds and
//     From. SPAM is spam, TRASH is trash, INBOX is inbox (a Promotions or Updates tab is still the Inbox, and the
//     category is kept in the evidence). Anything else, such as archived by a filter, is 'other'.
//   * Outlook: Microsoft Graph lists the messages received since the seed was queued (all folders, plus Junk
//     Email asked directly), following @odata.nextLink up to MAX_PAGES, and matches the token in the subject.
//     parentFolderId is compared with the well-known Inbox, JunkEmail and DeletedItems folder ids.
//
// ONLY THE SEED ITSELF COUNTS (review of #966). A reply or forward carries the token too: its copy in Sent or
// Drafts is skipped (Gmail labels SENT/DRAFT, Graph folders sentitems/drafts), and a message whose From is not
// the effective sender is skipped. A token-bearing mail from anyone else can never read as the seed.
//
// FAIL CLOSED AT THE READER. Missing credentials, an HTTP error, a thrown fetch or a mailbox that is not the seed
// all come back as folder null, never as 'inbox'. The database treats a null folder at the read cutoff as
// 'unread' and holds the batch.
//
// NOTHING SENSITIVE IN THE ANSWER. resilience_ping is a public endpoint (verify_jwt=false), and placementTick's
// return value is part of its response. So it returns counts and verdicts only. The token, the From and the
// notification ids stay in public.invite_placement_check.
//
// THE ALLOWLIST IS EXACT. Two addresses, each tied to its provider. Anything else is refused before any network
// call, and the mailbox the credential opens must itself be that address (Gmail profile, Graph /me). The same two
// addresses are CHECK constraints on public.invite_placement_check, and both must stay in
// scripts/invitation_inbox_check.mjs FOUNDER_INBOXES
// (scripts/checks/the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.test.mjs).
//
// Credentials are read from app_secrets. vault.secrets is empty on this project (measured 24 Sep 2026).
//   Gmail:   google_oauth_client_id, google_oauth_client_secret (the Google client the YouTube connection
//            already uses) + gmail_seed_refresh_token (scope https://www.googleapis.com/auth/gmail.readonly).
//   Graph:   ms_graph_tenant_id, ms_graph_client_id, ms_graph_client_secret, and EITHER
//            ms_graph_seed_refresh_token (delegated Mail.Read + offline_access, read as /me) OR nothing more
//            (application Mail.Read, read as /users/<seed>, which must be limited to that one mailbox by an
//            Exchange ApplicationAccessPolicy).

export const SEED_GMAIL = 'ahmadmhdnabilalzain@gmail.com';
export const SEED_OUTLOOK = 'management@doratajewelries.com';
export const PLACEMENT_SEEDS: readonly string[] = [SEED_GMAIL, SEED_OUTLOOK];
/** Graph pages of 50 followed per list: 500 messages since the seed was queued before a reading gives up. */
export const MAX_PAGES = 10;

export type Folder = 'inbox' | 'spam' | 'trash' | 'other' | 'not_found';
export type Reading = { folder: Folder | null; detail: Record<string, unknown> };
type Fetch = (input: string, init?: RequestInit) => Promise<Response>;
type Sec = (k: string) => Promise<string | undefined | null>;
export type Save = (k: 'ms_graph_seed_refresh_token', v: string) => Promise<{ error?: { message?: string } | null } | unknown>;

/** Exact match only (case and surrounding space folded, as mail addresses are). No domains, no plus-tags. */
export function seedAllowed(addr: unknown, provider?: 'gmail' | 'outlook'): boolean {
  const a = String(addr ?? '').trim().toLowerCase();
  if (provider === 'gmail') return a === SEED_GMAIL;
  if (provider === 'outlook') return a === SEED_OUTLOOK;
  return PLACEMENT_SEEDS.includes(a);
}

/** 'QuotesDone <info@quotesdone.com>' -> 'info@quotesdone.com'; a bare address is returned folded. */
export function addressOf(from: unknown): string {
  const s = String(from ?? '');
  const m = s.match(/<([^<>\s]+@[^<>\s]+)>/);
  return (m ? m[1] : s).trim().toLowerCase();
}

const TOKEN_RE = /^QD[0-9A-F]{10}$/;

/** A copy the mailbox owner sent or drafted (a reply, a forward) is never the seed's placement. */
export function gmailIsOwnCopy(labelIds: unknown): boolean {
  const l = Array.isArray(labelIds) ? labelIds.map(String) : [];
  return l.includes('SENT') || l.includes('DRAFT');
}

export function gmailFolder(labelIds: unknown): Folder {
  const l = Array.isArray(labelIds) ? labelIds.map(String) : [];
  if (l.includes('SPAM')) return 'spam';
  if (l.includes('TRASH')) return 'trash';
  if (l.includes('INBOX')) return 'inbox';
  return 'other';
}

export type WellKnown = { inbox?: string; junkemail?: string; deleteditems?: string; sentitems?: string; drafts?: string };
export function graphFolder(parentFolderId: unknown, ids: WellKnown): Folder {
  const p = String(parentFolderId ?? '');
  if (!p) return 'other';
  if (ids.junkemail && p === ids.junkemail) return 'spam';
  if (ids.deleteditems && p === ids.deleteditems) return 'trash';
  if (ids.inbox && p === ids.inbox) return 'inbox';
  return 'other';
}

/** Several copies found (a resend): the worst one decides. None found: not_found. */
export function worstFolder(fs: Folder[]): Folder {
  for (const f of ['spam', 'trash', 'other', 'inbox'] as Folder[]) if (fs.includes(f)) return f;
  return 'not_found';
}

const failed = (why: string, extra: Record<string, unknown> = {}): Reading => ({ folder: null, detail: { error: why.slice(0, 300), ...extra } });

async function json(f: Fetch, url: string, init?: RequestInit): Promise<Record<string, unknown>> {
  const r = await f(url, { ...init, signal: AbortSignal.timeout(10000) });
  const t = await r.text();
  if (!r.ok) throw new Error(`${new URL(url).host} ${r.status}: ${t.slice(0, 160)}`);
  return t ? JSON.parse(t) : {};
}

export async function readGmail(f: Fetch, sec: Sec, to: string, token: string, sender: string): Promise<Reading> {
  if (!seedAllowed(to, 'gmail')) return failed('refused: not the allowlisted Gmail seed inbox');
  if (!TOKEN_RE.test(token)) return failed('refused: malformed placement token');
  const want = addressOf(sender);
  if (!want.includes('@')) return failed('refused: no effective sender to match');
  try {
    const [id, secret, refresh] = [await sec('google_oauth_client_id'), await sec('google_oauth_client_secret'), await sec('gmail_seed_refresh_token')];
    const missing = [['google_oauth_client_id', id], ['google_oauth_client_secret', secret], ['gmail_seed_refresh_token', refresh]].filter(([, v]) => !v).map(([k]) => k);
    if (missing.length) return failed('missing app_secrets: ' + missing.join(', '));
    const tok = await json(f, 'https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: String(refresh), client_id: String(id), client_secret: String(secret) }) });
    const auth = { Authorization: 'Bearer ' + String(tok.access_token || '') };
    const base = 'https://gmail.googleapis.com/gmail/v1/users/me';
    const me = await json(f, base + '/profile', { headers: auth });
    if (!seedAllowed(me.emailAddress, 'gmail')) return failed('refused: the Gmail credential opens a mailbox that is not the seed');
    const q = new URLSearchParams({ q: 'subject:' + token, includeSpamTrash: 'true', maxResults: '20' });
    const list = await json(f, `${base}/messages?${q}`, { headers: auth });
    const ids = (Array.isArray(list.messages) ? list.messages : []).map((m) => String((m as { id?: unknown }).id));
    const found: { id: string; labels: string[]; folder: Folder }[] = [];
    let ownCopies = 0, otherSender = 0;
    for (const mid of ids) {
      const m = await json(f, `${base}/messages/${encodeURIComponent(mid)}?format=metadata&metadataHeaders=From`, { headers: auth });
      const labels = Array.isArray(m.labelIds) ? m.labelIds.map(String) : [];
      if (gmailIsOwnCopy(labels)) { ownCopies++; continue; }
      const headers = ((m.payload as { headers?: { name?: string; value?: string }[] } | undefined)?.headers) ?? [];
      const from = headers.find((h) => String(h.name).toLowerCase() === 'from')?.value;
      if (addressOf(from) !== want) { otherSender++; continue; }
      found.push({ id: mid, labels, folder: gmailFolder(labels) });
    }
    return { folder: worstFolder(found.map((x) => x.folder)), detail: { provider: 'gmail', messages: found, skipped_own_copies: ownCopies, skipped_other_sender: otherSender } };
  } catch (e) { return failed(String((e as Error)?.message || e), { provider: 'gmail' }); }
}

export async function readOutlook(f: Fetch, sec: Sec, to: string, token: string, sinceIso: string, sender: string, save?: Save): Promise<Reading> {
  if (!seedAllowed(to, 'outlook')) return failed('refused: not the allowlisted Outlook seed inbox');
  if (!TOKEN_RE.test(token)) return failed('refused: malformed placement token');
  const want = addressOf(sender);
  if (!want.includes('@')) return failed('refused: no effective sender to match');
  try {
    const [tenant, id, secret, refresh] = [await sec('ms_graph_tenant_id'), await sec('ms_graph_client_id'),
      await sec('ms_graph_client_secret'), await sec('ms_graph_seed_refresh_token')];
    const missing = [['ms_graph_tenant_id', tenant], ['ms_graph_client_id', id], ['ms_graph_client_secret', secret]].filter(([, v]) => !v).map(([k]) => k);
    if (missing.length) return failed('missing app_secrets: ' + missing.join(', '));
    const delegated = !!refresh;
    const form: Record<string, string> = delegated
      ? { grant_type: 'refresh_token', refresh_token: String(refresh), client_id: String(id), client_secret: String(secret), scope: 'offline_access https://graph.microsoft.com/Mail.Read' }
      : { grant_type: 'client_credentials', client_id: String(id), client_secret: String(secret), scope: 'https://graph.microsoft.com/.default' };
    const tok = await json(f, `https://login.microsoftonline.com/${encodeURIComponent(String(tenant))}/oauth2/v2.0/token`,
      { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(form) });
    // Microsoft rotates a delegated refresh token on use; keeping the new one keeps the 90-day window sliding. A failed
    // store is recorded in the reading's evidence (the message only; never the token) so the finding can say so.
    let rotation: string | null = null;
    if (delegated && tok.refresh_token && tok.refresh_token !== refresh && save) {
      const res = await save('ms_graph_seed_refresh_token', String(tok.refresh_token)).catch((e) => ({ error: { message: String((e as Error)?.message || e) } }));
      const err = (res as { error?: { message?: string } | null } | null)?.error;
      rotation = err ? 'the rotated Graph refresh token was NOT stored: ' + String(err.message || 'unknown error').slice(0, 160) : 'stored';
    }
    const auth = { Authorization: 'Bearer ' + String(tok.access_token || '') };
    const base = delegated ? 'https://graph.microsoft.com/v1.0/me' : `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(SEED_OUTLOOK)}`;
    if (delegated) {
      const me = await json(f, base + '?$select=mail,userPrincipalName', { headers: auth });
      if (!seedAllowed(me.mail, 'outlook') && !seedAllowed(me.userPrincipalName, 'outlook')) return failed('refused: the Graph credential opens a mailbox that is not the seed');
    }
    const ids: WellKnown = {};
    for (const k of ['inbox', 'junkemail', 'deleteditems', 'sentitems', 'drafts'] as const) {
      ids[k] = String((await json(f, `${base}/mailFolders/${k}?$select=id`, { headers: auth })).id || '');
    }
    const q = '$filter=' + encodeURIComponent(`receivedDateTime ge ${new Date(new Date(sinceIso).getTime() - 5 * 60000).toISOString()}`)
      + '&$select=id,subject,from,parentFolderId,inferenceClassification,receivedDateTime&$top=50';
    const seen = new Map<string, { id: string; folder: Folder; focus: unknown }>();
    const looked = new Set<string>();
    let ownCopies = 0, otherSender = 0, pages = 0, truncated = false;
    for (const first of [`${base}/messages?${q}`, `${base}/mailFolders/junkemail/messages?${q}`]) {
      let url: string | null = first;
      for (let n = 0; url; n++) {
        if (n >= MAX_PAGES) { truncated = true; break; }
        const page: Record<string, unknown> = await json(f, url, { headers: auth });
        pages++;
        for (const m of (Array.isArray(page.value) ? page.value : []) as Record<string, unknown>[]) {
          // The Junk listing repeats what the all-folder listing may already have returned: each message once.
          if (!String(m.subject || '').includes(token) || looked.has(String(m.id))) continue;
          looked.add(String(m.id));
          if (m.parentFolderId && (m.parentFolderId === ids.sentitems || m.parentFolderId === ids.drafts)) { ownCopies++; continue; }
          const from = (m.from as { emailAddress?: { address?: string } } | undefined)?.emailAddress?.address;
          if (addressOf(from) !== want) { otherSender++; continue; }
          seen.set(String(m.id), { id: String(m.id), folder: graphFolder(m.parentFolderId, ids), focus: m.inferenceClassification ?? null });
        }
        const next = page['@odata.nextLink'];
        url = typeof next === 'string' && next.startsWith('https://graph.microsoft.com/') ? next : null;
      }
    }
    const found = [...seen.values()];
    const detail = { provider: 'graph', mode: delegated ? 'delegated' : 'application', messages: found, pages,
      skipped_own_copies: ownCopies, skipped_other_sender: otherSender, ...(rotation ? { refresh_token_rotation: rotation } : {}) };
    // Nothing found and the listing stopped at the page bound: that is a reading we could not finish, not a not_found.
    if (!found.length && truncated) return { folder: null, detail: { ...detail, error: `more than ${MAX_PAGES} pages since the seed; not read to the end` } };
    return { folder: worstFolder(found.map((x) => x.folder)), detail };
  } catch (e) { return failed(String((e as Error)?.message || e), { provider: 'graph' }); }
}

type Rpc = (fn: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string; code?: string } | null }>;
type Due = { action?: string; dubai_day?: string; token?: string; since?: string; sender?: string; reason?: string; verdict?: string;
  gmail?: { to?: string; sent?: boolean; folder?: Folder | null }; outlook?: { to?: string; sent?: boolean; folder?: Folder | null } };

// The routines not applied yet (undefined function, undefined table, PostgREST's "not in the schema cache"): the
// code deploys on merge while its SQL may still be pending. Recorded as skipped, not as a failing step -- the
// same codes and the same wording as PR #961's runPostmasterStep. Nothing is queued, so the gate holds the batch.
export const SCHEMA_MISSING = new Set(['42883', '42P01', 'PGRST202', 'PGRST205']);

/** What a public response may carry: the action, the day, a verdict or a reason, and folder names. */
function publicView(d: Due): Record<string, unknown> {
  const o: Record<string, unknown> = { action: d.action ?? null };
  if (d.dubai_day) o.dubai_day = d.dubai_day;
  if (d.verdict) o.verdict = d.verdict;
  if (d.reason) o.reason = d.reason;
  return o;
}

/** One heartbeat: queue / read / settle, all decided by the database; this only takes the readings. */
export async function placementTick(rpc: Rpc, f: Fetch, sec: Sec, save?: Save): Promise<Record<string, unknown>> {
  const { data, error } = await rpc('fn_invite_placement_due');
  if (error) {
    if (SCHEMA_MISSING.has(String(error.code))) return { ok: true, skipped: 'schema not applied', code: error.code };
    return { ok: false, error: 'fn_invite_placement_due: ' + error.message };
  }
  const due = (data ?? {}) as Due;
  if (due.action !== 'read') return { ok: true, ...publicView(due) };
  // A side is read only once its seed has left and until it has a folder that is not not_found; a side not read
  // this beat is sent as null, which the database treats as "no new reading".
  const want = (s?: { sent?: boolean; folder?: Folder | null }) => !!s?.sent && (!s.folder || s.folder === 'not_found');
  const [g, o] = await Promise.all([
    want(due.gmail) ? readGmail(f, sec, String(due.gmail?.to), String(due.token), String(due.sender)) : Promise.resolve(null),
    want(due.outlook) ? readOutlook(f, sec, String(due.outlook?.to), String(due.token), String(due.since), String(due.sender), save) : Promise.resolve(null),
  ]);
  if (!g && !o) return { ok: true, action: 'waiting_for_send', dubai_day: due.dubai_day };
  const rec = await rpc('fn_invite_placement_record', { p_day: due.dubai_day, p_gmail: g, p_outlook: o });
  if (rec.error) return { ok: false, error: 'fn_invite_placement_record: ' + rec.error.message };
  return { ok: true, action: 'read', dubai_day: due.dubai_day, gmail: g ? g.folder ?? 'unread' : null, outlook: o ? o.folder ?? 'unread' : null,
           verdict: (rec.data as { verdict?: unknown } | null)?.verdict ?? null };
}
