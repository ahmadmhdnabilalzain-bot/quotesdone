// send_outbox - flushes queued EMAIL notifications via Resend. Honors email_suppressions, daily cap, unsubscribe, supplier-send gate + stale guard.
// v14: internal/admin emails now get a structured, branded HTML template (headings, bullets, links) + internal footer. Added ?preview mode. Retries up to 3, then dead-letter. verify_jwt=false (secret-gated).
// v16: agent_runs instrumentation. This runs every 2 minutes and previously returned ok:true no matter what,
//      so 'email_enabled=false', a missing Resend key, or a hit daily cap looked identical to a healthy flush
//      while mail silently piled up. Recurring config states are throttled to one row per hour so the
//      2-minute cadence cannot bury the signal; idle runs with no work are not logged at all.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { encodeBase64 } from 'jsr:@std/encoding/base64';
import { requireInternal, secretOk } from '../_shared/internal_auth.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { tmpl } from './render.ts';
import { arabicFrame } from './arabic_frame.ts';
import { foldEmail, holdForNoUnsubscribe, plainTextPart } from './supplier_mail.ts';
import { holdArabicInvitation, withReplyQuestion } from './invitation_copy.ts';
import { claimQueue, isStale, ownsChannel, STALE_CEILING_H } from './channels.ts';
import { ownDomain, resendPayload } from './payload.ts';
import { LANE_CAPPED_TYPES, heldUntil, holdFor, isLaneType, resolveLane, senderFor } from './invite_lane.ts';
import { OPEN_TOKEN_MS, invitationHtml, openShare, openTracks, pixelBase, pixelUrl } from './open_tracking.ts';
import { M365_FROM_NAME, M365_HARD_CEILING, M365_ID_PREFIX, M365_PENDING_PREFIX, M365_PACE_MS, M365_PER_RUN, M365_SECRET_NAMES, M365_SEED_KIND, M365_INBOX_AGENT, afterRefusal, campaignMail, conversationReplyTo, graphSend, holdForM365, isMailboxReply, laneSide, m365Carries, m365Step, replyMail, m365Mime, m365ReplyTo, messageIdFor, refusalFinding, resolveM365, switchOn } from './m365_lane.ts';
import { UNSUBSCRIBE_MAILBOX } from '../_shared/unsubscribe_mailbox.ts';
import { askMailboxGate, GATE_UNREADABLE_WAIT_MS, mailboxReplyGated } from './mailbox_reply_gate.ts';
import { suppressionStops } from '../_shared/suppression_policy.ts';
import { observe } from '../_shared/observe.ts';
import { J } from '../_shared/json_response.ts';
import { duplicateNote, duplicateOf, recentSends, windowFrom } from '../_shared/outbox_duplicate_guard.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN_BASE = (Deno.env.get('SUPABASE_URL') || '') + '/functions/v1';
const MAX_ATTEMPTS = 3;
// A REFUSAL IS RETRIED LATER, NOT ON THE NEXT POLL, AND A PERMANENT ONE IS NOT RETRIED (it_engineer, 3 Nov 2026, drill D3).
// MEASURED by the drill: failNote put a refused row straight back to 'queued' with no not_before, so the next 2-minute poll
// took it again. Three polls, about four minutes, dead-lettered every message in the queue during a Resend outage of that
// length, and a 422 "Invalid `to` field" was posted twice more before it failed. A retry now waits RETRY_BACKOFF_MS (5, then
// 20 minutes, or the provider's Retry-After when longer, up to an hour), so three attempts span about 25 minutes; a 400 or
// 422 (Resend's "this request is wrong", which no retry changes) fails at once. The claim already honours not_before.
// prevented by: supabase/functions/send_outbox/drill_send_faults.test.ts
const RETRY_BACKOFF_MS = [5 * 60_000, 20 * 60_000];
const RETRY_AFTER_MAX_MS = 60 * 60_000;
const PERMANENT_HTTP = new Set([400, 422]);
function retryAfterMs(v: string | null): number {
  if (!v) return 0;
  const s = Number(v);
  if (Number.isFinite(s)) return Math.max(0, s * 1000);
  const t = Date.parse(v);
  return Number.isFinite(t) ? Math.max(0, t - Date.now()) : 0;
}
// ONE READ FOR THE SETTINGS, NOT TWENTY (it_engineer, 28 Sep 2026, ledger 760). Every call read ~20
// app_secrets keys one round trip at a time before looking at the queue: an IDLE poll averaged 8.4 s
// (agent_runs fn:send_outbox, 64 runs in 6 h, max 26 s), past resilience_ping's 20 s outbox timeout
// often enough that heartbeat step `outbox` failed with "Signal timed out". The keys are read together
// once per request (never cached across requests, so a rotated secret is seen on the next call);
// a key outside the list still reads on its own, exactly as before.
// prevented by: supabase/functions/send_outbox/settings_read_once.test.ts
export const OUTBOX_KEYS = ['unsubscribe_signing_key', 'email_enabled', 'supplier_emails_enabled', 'email_stale_hours',
  'resend_api_key', 'email_from_supplier', 'email_from_info', 'email_reply_supplier', 'email_reply_supplier_docs',
  'email_reply_info', 'email_logo_url', 'unsubscribe_public_base', 'email_asset_public_base', 'email_signature_name',
  'email_signature_name_ar', 'email_signature_title', 'invite_preheader', 'daily_send_cap', 'invite_lane_enabled',
  'invite_lane_from', 'invite_daily_cap', 'invite_m365_enabled', 'invite_m365_mailbox', 'invite_open_tracking', 'outbox_duplicate_window_min'];
let secCache: Map<string, string | undefined> | null = null;
async function warmSecrets() {
  secCache = null;
  const { data, error } = await admin.from('app_secrets').select('key,value').in('key', OUTBOX_KEYS);
  if (error) return;   // fall back to one read per key
  secCache = new Map(OUTBOX_KEYS.map((k) => [k, undefined]));
  for (const r of (data || []) as { key: string; value: string }[]) secCache.set(r.key, r.value);
}
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// The handler reads settings through setting(): a key in the bulk read comes from it, anything else (or
// every key, when the bulk read failed) is the canonical sec() above. sec() itself stays the estate's one
// shape (scripts/checks/shared_helpers_agree.test.mjs); the per-request read lives beside it, not inside it.
const setting = (k: string): Promise<string | undefined> => (secCache?.has(k) ? Promise.resolve(secCache.get(k)) : sec(k));
// FAIL-CLOSED 28 Jul 2026 (missed by the 27 Jul sweep): sec() returns undefined/'' when the
// app_secrets read fails or the row is missing, and the guard below compared strictly, so a caller
// posting {} matched and gained full service-role authority on a function that requires no JWT. The
// stored secret must now be a real value before any caller value can equal it.
// secretOk() is the shared one, in ../_shared/internal_auth.ts.
async function tmplRow(n: string) { try { const { data } = await admin.from('templates').select('content').eq('name', n).maybeSingle(); return (data?.content as string) || ''; } catch { return ''; } }

// ATTACHMENTS (9 Sep 2026) ---------------------------------------------------
// Until today this function could not email a file. The Resend payload below was built as
// { from, to, reply_to, subject, html } and nothing else, so every agent that produces a document
// -- the accountant's weekly financial report above all -- could send a LINK and never the thing
// itself. The founder asked for the report as a PDF; a signed URL that expires in seven days is
// not a PDF.
//
// notifications.attachments holds REFERENCES ({bucket, path, filename}), never bytes, and the
// database trigger a20_notifications_attachment_policy has already refused an unsafe bucket, a
// traversal path or a hostile filename before the row could be written. This side re-checks the
// bucket anyway -- the row is data, and a function that reads storage with the service role should
// not trust a jsonb field just because a trigger was supposed to have looked at it.
//
// The byte ceiling lives HERE and not in the trigger, because only this side knows the size: the
// row holds a reference, not the object. Resend's own limit is 40 MB across the message; 20 MB
// leaves room for the HTML body and base64's 4/3 expansion.
const ATTACH_BUCKETS = new Set(['finance-reports', 'finance-docs', 'agent-docs', 'reports', 'compliance-docs']);
const MAX_ATTACH_BYTES = 20 * 1024 * 1024;
type Attach = { filename: string; content: string };
async function resolveAttachments(spec: unknown): Promise<{ ok: true; list: Attach[] } | { ok: false; err: string }> {
  if (spec === null || spec === undefined) return { ok: true, list: [] };
  if (!Array.isArray(spec)) return { ok: false, err: 'attachments is not an array' };
  const list: Attach[] = [];
  let total = 0;
  for (const a of spec) {
    const bucket = String((a as any)?.bucket || ''), path = String((a as any)?.path || ''), filename = String((a as any)?.filename || '');
    if (!ATTACH_BUCKETS.has(bucket)) return { ok: false, err: `attachment bucket not attachable: ${bucket}` };
    if (!path || path.includes('..')) return { ok: false, err: `attachment path refused: ${path}` };
    if (!/^[A-Za-z0-9 ._-]{1,120}$/.test(filename)) return { ok: false, err: `attachment filename refused: ${filename}` };
    const { data, error } = await admin.storage.from(bucket).download(path);
    if (error || !data) return { ok: false, err: `attachment unreadable ${bucket}/${path}: ${error?.message || 'no data returned'}` };
    const bytes = new Uint8Array(await data.arrayBuffer());
    if (!bytes.byteLength) return { ok: false, err: `attachment is empty: ${bucket}/${path}` };
    total += bytes.byteLength;
    if (total > MAX_ATTACH_BYTES) return { ok: false, err: `attachments total ${total} bytes, over the ${MAX_ATTACH_BYTES} ceiling` };
    list.push({ filename, content: encodeBase64(bytes) });
  }
  return { ok: true, list };
}

// Observability -------------------------------------------------------------
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'send_outbox', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging block the mail queue */ }
}
// Recurring config problems (email disabled, cap reached) would otherwise write a row every
// 2 minutes. Emit at most one per window, keyed on counts->>signal.
async function logThrottled(signal: string, minutes: number, status: string, counts: Record<string, unknown>, note: string) {
  try {
    const since = new Date(Date.now() - minutes * 60000).toISOString();
    const { data } = await admin.from('agent_runs').select('id').eq('agent', 'send_outbox')
      .gte('started_at', since).eq('counts->>signal', signal).limit(1);
    if (data && data.length) return;
  } catch (_e) { /* if the check fails, fall through and log */ }
  await logRun(status, { ...counts, signal }, note);
}

// okEveryMs 10 minutes: this polls every 2 minutes, and its logRun/logThrottled rows above already
// carry the business signal. The observe() row adds only the HTTP/latency view, so one healthy
// sample per ten minutes is plenty and 720 rows a day would bury the rows that matter.
Deno.serve(observe('send_outbox', async (req) => {
  // A CLAIM THAT WAS NOT RESOLVED IS GIVEN BACK IN A `finally`, NOT AT THE END OF THE LOOP
  // (corrected 22 Sep 2026 after independent review). The release used to sit after the send loop, and
  // TWO returns jump over it: `!enabled || !key` and `remaining <= 0`. The daily cap is a NORMAL
  // recurring state — this polls every 2 minutes — so with the cap reached each poll claimed a fresh 40
  // rows and abandoned them in 'sending' for the 5-minute expiry, walking the whole queue into
  // 'sending' in slices. Declared out here and released in the finally below, so every exit takes the
  // same path, including the exception one.
  const claimedIds: number[] = [];
  try {
    const body = await req.json().catch(() => ({}));
    await warmSecrets();
    // AUDIT 9.5 (3 Aug 2026): the unsubscribe footer and the RFC 8058 List-Unsubscribe headers
    // are signed with a dedicated long-lived key. They used to be signed with inbound_secret, so
    // withdrawing it would have both invalidated every delivered link AND - because the link is
    // only built when the key reads back - sent supplier mail with no unsubscribe mechanism at all.
    const unsubKey = await setting('unsubscribe_signing_key');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'send_outbox');
    if (!__auth.ok) { await logThrottled('forbidden', 60, 'error', {}, 'send_outbox called without the inbound secret'); return J({ error: 'forbidden' }, 403); }
    // Preview mode: render the internal/branded template for a sample body without sending.
    if (body.preview) {
      const logo = (await setting('email_logo_url')) || '';
      const sigName = (await setting('email_signature_name')) || 'Ahmad Alzain';
      const sigTitle = (await setting('email_signature_title')) || 'Founder';
      const html = tmpl({ body: String(body.sample || 'SUMMARY\nAll systems healthy.\n\nFINDINGS\n- Uptime 99.9%\n- 2 alerts auto-resolved\n\nNext review at https://quotesdone.com/os'), logo, name: sigName, title: sigTitle, channelEmail: 'info@quotesdone.com', unsub: '', internal: body.internal !== false, subject: String(body.subject || 'Daily operations report') });
      return J({ ok: true, html });
    }
    const enabled = (await setting('email_enabled')) === 'true';
    const supEnabled = (await setting('supplier_emails_enabled')) === 'true';
    const staleH = parseInt((await setting('email_stale_hours')) || '72', 10);
    const key = await setting('resend_api_key');
    const fromSup = (await setting('email_from_supplier')) || 'QuotesDone <supplier@quotesdone.com>';
    const fromInfo = (await setting('email_from_info')) || 'QuotesDone <info@quotesdone.com>';
    const replySup = (await setting('email_reply_supplier')) || 'suppliers@mail.quotesdone.com';
    const replyDocs = (await setting('email_reply_supplier_docs')) || 'docs@mail.quotesdone.com';
    const replyInfo = (await setting('email_reply_info')) || 'info@quotesdone.com';
    // The Reply-To of an automatic answer: supplier@ for a lead (leads.email or claimed_by). A failed read keeps the fallback.
    const inboundReplyTo = async (to: string, fallback: string) => {
      const e = String(to || '').trim().toLowerCase();
      const { data: rel } = await admin.rpc('fn_mail_sender_known', { p_email: e });
      const { data: claimed } = rel === 'supplier' ? { data: [{}] } : await admin.from('leads').select('id').ilike('claimed_by', e.replace(/[\\%_]/g, '\\$&')).limit(1);
      if (!claimed?.length) return fallback;
      const p = await admin.from('agent_runs').select('status,finished_at').eq('agent', M365_INBOX_AGENT).eq('counts->>m365_inbox', '1').order('finished_at', { ascending: false }).limit(1).maybeSingle();
      return conversationReplyTo({ type: 'inbound_reply', toSupplier: true, mailbox: await setting('invite_m365_mailbox'), proofAt: !p.error && p.data?.status === 'ok' ? p.data.finished_at as string : null, now: new Date(), fallback });
    };
    const logo = (await setting('email_logo_url')) || '';
    // OUR OWN DOMAIN IN THE MAIL (22 Sep 2026, payload.ts ownDomain): set once quotesdone.com serves the
    // /u/unsubscribe and /m/brand proxies (next.config.mjs). Unset = the project host, as before.
    const unsubBase = (await setting('unsubscribe_public_base')) || `${FN_BASE}/unsubscribe`;
    const assetBase = (await setting('email_asset_public_base')) || '';
    const sigName = (await setting('email_signature_name')) || 'Ahmad Alzain';
    // The founder's name in Arabic script for Arabic mail (instruction 586): a Latin name under an Arabic letter reads as a translation.
    const sigNameAr = (await setting('email_signature_name_ar')) || 'أحمد الزين';
    const sigTitle = (await setting('email_signature_title')) || 'Founder';
    // The invitation's preheader (24 Sep 2026, marketing, ledger 993): the inbox line beside the subject.
    const invitePreheader = (await setting('invite_preheader')) || '';
    const tplSup = await tmplRow('email_supplier'); const tplCust = await tmplRow('email_customer');
    const cap = parseInt((await setting('daily_send_cap')) || '80', 10);
    const since = new Date(); since.setUTCHours(0, 0, 0, 0);
    const { count: sentToday } = await admin.from('notifications').select('id', { count: 'exact', head: true }).eq('status', 'sent').gte('sent_at', since.toISOString());
    const remaining = Math.max(0, cap - (sentToday || 0));
    // CLAIMED, NOT READ (22 Sep 2026, it_engineer, CONN-03 — see channels.ts claimQueue).
    const { data: q, error: qErr } = await claimQueue(admin, Number(body.limit) || 40);
    if (qErr) { await logThrottled('claim_failed', 10, 'error', {}, 'could not claim the outbox queue: ' + qErr.message); return J({ ok: false, error: qErr.message }, 200); }
    // deno-lint-ignore no-explicit-any -- the rows were `any` when they came from selectQueue; the loop below reads a dozen columns off them
    const rows = ((q as any[] | null) || []);
    for (const n of rows) claimedIds.push(n.id);
    // Previously a silent ok:true - mail just accumulated with no signal anywhere.
    if (!enabled || !key) { await logThrottled('email_disabled', 60, 'error', { pending: rows.length, email_enabled: enabled, has_resend_key: !!key }, 'EMAIL NOT SENDING - ' + (!enabled ? 'email_enabled is not true' : 'resend_api_key missing') + '; ' + rows.length + ' notification(s) waiting'); return J({ ok: true, pending: rows.length, sent: 0, note: 'email disabled or resend_api_key missing - queued and will flush once enabled' }); }
    if (remaining <= 0) { await logThrottled('cap_reached', 60, 'error', { pending: rows.length, cap, sent_today: sentToday || 0 }, 'daily send cap reached - ' + rows.length + ' notification(s) held until tomorrow'); return J({ ok: true, sent: 0, pending: rows.length, note: 'daily send cap reached', cap, sent_today: sentToday || 0 }); }
    // CASE-FOLDED BOTH SIDES (21 Sep 2026). email_suppressions is written lower-case by unsubscribe and
    // resend_webhook, and this lookup used to match the queued address exactly, so a supplier whose
    // lead email carried a capital letter (47 leads, measured) unsubscribed and kept being mailed.
    const toEmails = [...new Set(rows.map((r: any) => foldEmail(r.to_email)).filter(Boolean))];
    // WHAT A ROW STOPS (22 Sep 2026): a bounce or complaint stops everything; an 'unsubscribe' stops only the
    // invitation and its reminders (_shared/suppression_policy.ts). Before, an unsubscribe also stopped quote,
    // reveal and account notices to a registered supplier.
    // THE INVITATION LANE (24 Sep 2026, marketing + it_engineer; invite_lane.ts). Flag off = LANE_OFF and no call.
    // On, it asks Resend whether the lane's subdomain is verified before a single invitation uses it.
    // THE MICROSOFT 365 LANE (5 Oct 2026, ledger 1115; m365_lane.ts). A row it carries never reaches the Resend lanes below.
    const m365Enabled = switchOn(await setting('invite_m365_enabled'));
    const carries = (r: any) => m365Carries({ enabled: m365Enabled, type: r.type, kind: r.kind, supplierSide: laneSide(r) });
    const fileFinding = async (args: Record<string, unknown>) => { const { error } = await admin.rpc('fn_it_engineer_finding_upsert', args); if (error) throw error; };
    let m365 = await resolveM365({ needed: rows.some(carries), mailbox: await setting('invite_m365_mailbox'), env: (k) => Deno.env.get(k),
      fetchFn: (u, i) => timedFetch(u, i || {}, 10_000), fileFinding });
    // The refusal finding closes on the first 2xx sendMail of the run (graphSend), never on a token alone.
    let m365Closed = false;
    const closeFinding = async (k: string, note: string) => { if (m365Closed) return; const { error } = await admin.rpc('fn_it_engineer_finding_close', { p_issue_key: k, p_note: note }); if (error) throw error; m365Closed = true; };
    let cappedSentToday = 0, m365SentToday = 0, m365SentRun = 0, m365ProofAt: string | null = null;
    if (m365.active) {
      // Reply-To is dropped only while the reply reader is proven (m365ReplyTo); an unreadable row keeps the old one.
      const p = await admin.from('agent_runs').select('status,finished_at').eq('agent', M365_INBOX_AGENT).eq('counts->>m365_inbox', '1').order('finished_at', { ascending: false }).limit(1).maybeSingle();
      m365ProofAt = !p.error && p.data?.status === 'ok' ? (p.data.finished_at as string) : null;
      const a = await admin.from('notifications').select('id', { count: 'exact', head: true }).in('type', [...LANE_CAPPED_TYPES]).eq('status', 'sent').gte('sent_at', since.toISOString());
      const b = await admin.from('notifications').select('id', { count: 'exact', head: true }).like('provider_message_id', M365_ID_PREFIX + '%').eq('status', 'sent').gte('sent_at', since.toISOString());
      // A count that cannot be read is treated as the ceiling reached: the lane holds rather than guesses.
      cappedSentToday = a.error ? Number.MAX_SAFE_INTEGER : (a.count || 0);
      m365SentToday = b.error ? M365_HARD_CEILING : (b.count || 0);
    }
    const lane = await resolveLane({ enabled: await setting('invite_lane_enabled'), from: await setting('invite_lane_from'), apiKey: key,
      needed: rows.some((r: any) => r.to_role === 'supplier' && isLaneType(r.type) && !carries(r)),
      fetchFn: (u, i) => timedFetch(u, i || {}, 10_000),
      fileFinding });
    // The lane's own daily ceiling is the ramp's number (invite_daily_cap), counted over invitations and nudges actually sent today.
    const laneCapRaw = parseInt((await setting('invite_daily_cap')) || '', 10);
    const laneCap = Number.isFinite(laneCapRaw) && laneCapRaw >= 0 ? laneCapRaw : 30;
    let laneSentToday = 0;
    if (lane.active) {
      const { count } = await admin.from('notifications').select('id', { count: 'exact', head: true })
        .in('type', [...LANE_CAPPED_TYPES]).eq('status', 'sent').gte('sent_at', since.toISOString());
      laneSentToday = count || 0;
    }
    let laneHeld = 0;
    const supReason = new Map<string, string>();
    if (toEmails.length) { const { data: sup } = await admin.from('email_suppressions').select('email,reason').in('email', toEmails); for (const s of (sup || []) as any[]) supReason.set(foldEmail(s.email), String(s.reason || '')); }
    let sent = 0, failed = 0, retried = 0, deadlettered = 0, skipped = 0, suppressed = 0, held = 0, attached = 0, unconfirmed = 0, writeFailed = 0;
    // provider_message_id is cleared: a row that is not sent has no provider message, and this also clears the Microsoft 365
    // pending marker (M365_PENDING_PREFIX) of a mailbox reply Graph refused and Resend then refused, so it is retried, not
    // mistaken next run for a send whose outcome was lost.
    const failNote = async (n: any, msg: string, o: { permanent?: boolean; retryAfterMs?: number } = {}) => {
      const att = (Number(n.attempts) || 0) + 1;
      const dead = !!o.permanent || att >= MAX_ATTEMPTS;
      const waitMs = Math.max(RETRY_BACKOFF_MS[Math.min(att, RETRY_BACKOFF_MS.length) - 1], Math.min(o.retryAfterMs || 0, RETRY_AFTER_MAX_MS));
      await admin.from('notifications').update({ status: dead ? 'failed' : 'queued', attempts: att, last_error: String(msg).slice(0, 500), provider_message_id: null,
        ...(dead ? {} : { not_before: new Date(Date.now() + waitMs).toISOString() }) }).eq('id', n.id);
      failed++; if (dead) deadlettered++; else retried++;
    };
    let lastErr = '';
    // THE SUPPLIER CAMPAIGN EMAIL, BOTH ROUTES (27 Oct 2026): the subject and text come from campaignMail
    // (m365_lane.ts) whether the Microsoft 365 lane or the Resend fallback carries the row. ledger 1113: the note
    // names the company and its trade, read from the lead (a seed has none: its body's opening).
    const campaignFor = async (n: any) => {
      const { data: lead } = n.kind === M365_SEED_KIND ? { data: null } : await admin.from('leads').select('company_name,invite_trades').ilike('email', String(n.to_email).trim().replace(/[\\%_]/g, '\\$&')).limit(1).maybeSingle();
      // NO TRADE IS GUESSED (1 Nov 2026, ledger 1423): invite_trades[0] is the first slug alphabetically, so on 30 Oct a cleaning
      // company and a fire-safety trainer were asked about their "civil works work". GlockApps tested the neutral wording.
      return campaignMail(n, { company: (lead as any)?.company_name ?? undefined });
    };
    // THE INVITATION OPEN (3 Nov 2026, marketing; open_tracking.ts). Share 0 / 'off' or no first-party base: no call, and
    // the email is exactly the untracked one. Otherwise the database picks the arm and the token; a failed call or no
    // token sends the untracked email (an open is never worth a held invitation). The call is cut at OPEN_TOKEN_MS, so a
    // hung database call cannot delay an invitation. Only the Microsoft 365 lane carries the twin: the Resend fallback stays
    // text-only, so a provider's own open or click tracking can never be added to an invitation (review of #1831).
    const openPct = openShare(await setting('invite_open_tracking'));
    const openBase = pixelBase(unsubBase);
    const openHtmlFor = async (n: { id: number; type?: unknown; kind?: unknown; to_role?: unknown; lang?: unknown }, text: string): Promise<string> => {
      if (!openPct || !openBase || !openTracks(n)) return '';
      try {
        const { data, error } = await admin.rpc('fn_invite_open_token', { p_notification_id: n.id }).abortSignal(AbortSignal.timeout(OPEN_TOKEN_MS));
        const pixel = error ? '' : pixelUrl(openBase, data);
        return pixel ? invitationHtml(text, pixel) : '';
      } catch { return ''; }
    };
    // THE SAME MESSAGE TO THE SAME PERSON IS SENT ONCE (it_engineer, 11 Nov 2026, ruling 1631; _shared/outbox_duplicate_guard.ts).
    // Measured: 6 seed-list emails went out twice 42 s apart on 10 Nov. The rows sent to these recipients inside the window are
    // read once; this batch's own rows are added as each one passes, so two identical rows in one batch send once.
    const dupWindow = windowFrom(await setting('outbox_duplicate_window_min'));
    const batchIds = new Set(rows.map((r: any) => String(r.id)));
    const recentRead = await recentSends(admin, rows, dupWindow);
    const recentList = recentRead ? recentRead.filter((r) => !batchIds.has(String(r.id))) : null;
    const duplicateIds: (number | string)[] = [];
    for (const n of rows) {
      // WHATSAPP ROWS EATEN 27 Jul 2026 - the select above pulls every queued row of EVERY channel but
      // this line excluded only 'sms', and the next line marks any row with no to_email as 'skipped'.
      // WhatsApp notifications carry to_phone and never to_email, so each one this poller reached was
      // flipped to 'skipped' before send_whatsapp (which drains channel='whatsapp' AND status='queued')
      // could see it. Running every 2 minutes, this poller almost always won the race - the WhatsApp
      // message was destroyed, not delayed. Exclude 'whatsapp' exactly as 'sms' is excluded: leave the
      // row untouched at 'queued' so its own sender can drain it.
      // 15 Sep 2026: the query now excludes these channels (see channels.ts), so this guard should never
      // fire; it stays as defence in depth, still leaving the row untouched for its own sender.
      if (!ownsChannel(n.channel)) { skipped++; continue; }
      if (!n.to_email) { await admin.from('notifications').update({ status: 'skipped' }).eq('id', n.id); continue; }
      // A ROW THAT WAS HANDED TO MICROSOFT GRAPH IS NEVER SENT AGAIN, BY EITHER LANE (it_engineer, 3 Nov 2026, drill D6/D10).
      // MEASURED by the drill: Graph accepted a sendMail (202), the 'sent' write then failed, and the row went back on the
      // queue (this function's finally, or fn_notifications_claim's 5-minute expiry), so the next tick sent the supplier a
      // second copy. Graph has no idempotency key, so this side must remember: the lane writes M365_PENDING_PREFIX + the
      // Message-ID onto the row BEFORE the POST, and a row that comes back carrying it is recorded sent-unconfirmed (sent,
      // provider_message_id NULL, the reason in last_error: the estate's existing shape for "it left, the answer did not")
      // and never posted again. Checked before the suppression and lane rules on purpose: the lane being switched off since
      // must not send it through Resend instead.
      // prevented by: supabase/functions/send_outbox/drill_send_faults.test.ts
      if (String(n.provider_message_id || '').startsWith(M365_PENDING_PREFIX)) {
        await admin.from('notifications').update({ status: 'sent', sent_at: new Date().toISOString(), provider_message_id: null,
          last_error: ('a previous run handed this message to Microsoft Graph (' + String(n.provider_message_id).slice(M365_PENDING_PREFIX.length) +
            ') and could not record the outcome; sent-unconfirmed, NOT sent again').slice(0, 500) }).eq('id', n.id);
        unconfirmed++; continue;
      }
      // 3 SEP 2026: RFC 2606 reserved domains (example.com/net/org, .test, .example, .invalid,
      // localhost) are never deliverable — Resend answers 422 "Invalid to field" and this loop used
      // to log it as a failed run and retry. The demo fixtures address every ZZ DEMO party there on
      // purpose; refusing before any provider call is the clean skip, and it guarantees production
      // never emails a fixture address.
      if (RESERVED_TEST_DOMAIN.test(n.to_email)) { await admin.from('notifications').update({ status: 'skipped', last_error: 'reserved test domain (RFC 2606): never deliverable, refused before any provider call' }).eq('id', n.id); skipped++; continue; }
      if (supReason.has(foldEmail(n.to_email)) && suppressionStops(supReason.get(foldEmail(n.to_email)), n.type)) { await admin.from('notifications').update({ status: 'suppressed' }).eq('id', n.id); suppressed++; continue; }
      // A SUPPLIER-MAILBOX REPLY LEAVES ONLY WHEN THE READING OF THE MAIL SAID ANSWER (11 Nov 2026, customer_support, ruling
      // 1633; mailbox_reply_gate.ts). A refusal is final ('skipped' with the reason); an unreadable gate is not a yes: the row
      // waits GATE_UNREADABLE_WAIT_MS and is asked again. prevented by: send_outbox/mailbox_reply_gate.test.ts
      if (mailboxReplyGated(n)) {
        const g = await askMailboxGate((f, a) => admin.rpc(f, a), n.id);
        if (!g.send) {
          if (g.refused) { await admin.from('notifications').update({ status: 'skipped', last_error: ('refused at send: ' + g.why).slice(0, 500) }).eq('id', n.id); skipped++; }
          else { await admin.from('notifications').update({ status: 'queued', claimed_at: null, last_error: g.why.slice(0, 500), not_before: new Date(Date.now() + GATE_UNREADABLE_WAIT_MS).toISOString() }).eq('id', n.id); held++; }
          continue;
        }
      }
      const age = isStale(n.created_at, n.not_before, isLaneType(n.type), staleH, new Date());
      if (age.stale) { await admin.from('notifications').update({ status: 'held', last_error: 'held: stale, ' + Math.round(age.hours) + 'h past due (email_stale_hours ' + staleH + ', ceiling ' + STALE_CEILING_H + 'h from creation)' }).eq('id', n.id); held++; continue; }
      if (recentList) {
        const earlier = duplicateOf(n, recentList, dupWindow);
        if (earlier) { await admin.from('notifications').update({ status: 'cancelled', last_error: duplicateNote(earlier) }).eq('id', n.id); duplicateIds.push(n.id); continue; }
        recentList.push({ ...n, status: 'sending', sent_at: new Date().toISOString() });
      }
      // A REPLY IN A CONVERSATION KEEPS ITS RESEND HANDLING (sales_engineer, 3 Nov 2026). fn_inbox_send now writes
      // to_role 'supplier' on a reply to a supplier (so the lead's history counts it); on the Resend route that row
      // is sent exactly as before, when its to_role was NULL: From info@, inboundReplyTo's Reply-To, no supplier frame,
      // gate or unsubscribe footer. Only the Microsoft 365 lane reads the role (carries, above).
      const supplierSide = n.to_role === 'supplier' && n.type !== 'inbound_reply';
      const internal = n.to_role === 'admin' || n.to_role === 'founder';
      const docReq = supplierSide && isDocRequest(n.type);
      if (supplierSide && !supEnabled && !docReq) { await admin.from('notifications').update({ status: 'held', last_error: 'held: supplier_emails_enabled is off' }).eq('id', n.id); held++; continue; }
      // A LANE INVITATION IS HELD, NEVER DIVERTED (review of #963; invite_lane.ts holdFor). Left 'queued' with
      // not_before moved on, so it does not come back into the next claim and crowd out other mail.
      const laneHold = holdFor({ lane, type: n.type, supplierSide: supplierSide && !carries(n), laneSentToday, laneCap });
      if (laneHold) {
        await admin.from('notifications').update({ status: 'queued', claimed_at: null, not_before: heldUntil(laneHold, new Date()).toISOString(),
          last_error: laneHold === 'unverified' ? 'held: the invitation lane is on but ' + lane.why + '; never sent from the main sender'
                                                : 'held: the invitation lane reached invite_daily_cap (' + laneCap + ') today' }).eq('id', n.id);
        laneHeld++; continue;
      }
      if (sent >= remaining) break;
      // Lane inactive = the same From as before the lane existed; active = invitations only (invite_lane.ts senderFor).
      const from = senderFor({ type: n.type, supplierSide, fromSup, fromInfo, lane });
      // A row may name its own Reply-To (notifications.reply_to, constrained to our inbound subdomain): the monthly
      // social calendar carries calendar+<token>@mail.quotesdone.com so the founder's reply reaches resend_inbound.
      const reply = n.reply_to || (supplierSide ? (docReq ? replyDocs : replySup) : n.type === 'inbound_reply' ? await inboundReplyTo(n.to_email, replyInfo) : replyInfo);
      const unsub = (supplierSide && unsubKey) ? `${unsubBase}?e=${encodeURIComponent(n.to_email)}&t=${await unsubTok(n.to_email, unsubKey)}` : '';
      // NO UNSUBSCRIBE, NO SUPPLIER MARKETING (21 Sep 2026). The link and the RFC 8058 headers are only
      // built when unsubscribe_signing_key reads back; when it did not, supplier mail used to go out with
      // neither. A licence/document request is transactional and still goes; everything else waits.
      if (holdForNoUnsubscribe(supplierSide, docReq, unsub)) { await admin.from('notifications').update({ status: 'held', last_error: 'held: no unsubscribe link could be built (unsubscribe_signing_key unreadable); supplier mail never goes without one' }).eq('id', n.id); held++; continue; }
      // NEVER AN ARABIC INVITATION (24 Sep 2026, marketing, ledger 993): held with its reason, not sent.
      if (holdArabicInvitation(n.type, n.lang, supplierSide)) { await admin.from('notifications').update({ status: 'held', last_error: 'held: supplier mail is English only (ledger 993; founder 28 Sep 2026); this row was queued in Arabic' }).eq('id', n.id); held++; continue; }
      if (carries(n)) {
        // An invitation is held, never diverted to Resend: refused lane, shared invite cap or the mailbox's ceiling.
        // A mailbox reply (m365_lane.ts isMailboxReply) is never held or paced: when the lane cannot carry it, it
        // falls through to the Resend route below, exactly as before this lane carried replies (m365Step).
        const isReply = isMailboxReply(n);
        const mh = holdForM365({ m365, type: n.type, cappedSentToday, inviteCap: laneCap, m365SentToday });
        const step = m365Step({ reply: isReply, hold: mh, sentThisRun: m365SentRun });
        if (step === 'hold') {
          await admin.from('notifications').update({ status: 'queued', claimed_at: null, not_before: heldUntil(mh!, new Date()).toISOString(),
            last_error: mh === 'cap' ? 'held: the Microsoft 365 lane reached invite_daily_cap or its ' + M365_HARD_CEILING + '/day ceiling'
                                     : 'held: the Microsoft 365 lane is on but ' + m365.why + '; never sent through Resend' }).eq('id', n.id);
          laneHeld++; continue;
        }
        // PACING (27 Oct 2026, m365_lane.ts paceM365): at most M365_PER_RUN lane sends a run; the rest go back to the queue.
        if (step === 'pace') {
          await admin.from('notifications').update({ status: 'queued', claimed_at: null, not_before: new Date(Date.now() + M365_PACE_MS).toISOString(),
            last_error: 'paced: the Microsoft 365 lane sends at most ' + M365_PER_RUN + ' a run; queued for a later run' }).eq('id', n.id);
          laneHeld++; continue;
        }
        let toResend = step === 'resend';
        if (!toResend) {
          // 27 Oct 2026: the invitation, its nudge and the seed send one approved email (campaignMail, shared with the
          // Resend fallback below); only the seed keeps its (ref QD…) token. A reply sends its own text, threaded.
          const rm = isReply ? replyMail(n) : null;
          const { subject: mSubject, text: mBody, bad } = rm ? { subject: rm.subject, text: rm.text, bad: rm.bad.map((rule) => ({ rule, ok: false, detail: '' })) } : await campaignFor(n);
          if (bad.length) { await admin.from('notifications').update({ status: 'held', last_error: ('held: Microsoft 365 ' + (isReply ? 'reply' : 'invitation copy rule') + ' failed: ' + bad.map((l) => l.rule + ' (' + (l.detail || '') + ')').join('; ')).slice(0, 500) }).eq('id', n.id); held++; continue; }
          // The open-tracking twin is for a campaign row only (open_tracking.ts openTracks); a reply is never tracked.
          const mHtml = rm ? '' : await openHtmlFor(n, mBody);
          const now = new Date(); const mid = messageIdFor(n.id, now);
          // A reply is one person answering another: no List-Unsubscribe, as on its Resend route.
          const mime = m365Mime({ from: M365_FROM_NAME + ' <' + m365.mailbox + '>', to: n.to_email, reply: m365ReplyTo({ proofAt: m365ProofAt, now, fallback: reply }), subject: mSubject, text: mBody, unsub: isReply ? '' : unsub, unsubMailto: UNSUBSCRIBE_MAILBOX, messageId: mid, now, inReplyTo: rm?.inReplyTo, html: mHtml });
          // The pending marker (see M365_PENDING_PREFIX above). If it cannot be written nothing is sent: the finally gives
          // the claim back and a later run tries again, which costs a delay and never a duplicate.
          const mark = await admin.from('notifications').update({ provider_message_id: M365_PENDING_PREFIX + mid }).eq('id', n.id);
          if (mark.error) { writeFailed++; lastErr = ('could not mark the row before the Graph send: ' + mark.error.message).slice(0, 200); continue; }
          try {
            const r = await graphSend((u, i) => timedFetch(u, i || {}, 15_000), m365, mime, mid, closeFinding);
            if (r.ok) {
              const w = await admin.from('notifications').update({ status: 'sent', sent_at: new Date().toISOString(), provider_message_id: r.providerId }).eq('id', n.id);
              // Graph has the message; a failed write leaves the marker, so the next run records it and does not resend.
              if (w.error) { writeFailed++; lastErr = ('Graph accepted notification ' + n.id + ' but the sent write failed: ' + w.error.message).slice(0, 200); }
              // this lane has no Resend webhook, so the lead moves here (1 Nov 2026: 52 sent invitations still read 'queued')
              if (n.type === 'supplier_invite' && n.lead_id) await admin.from('leads').update({ invite_status: 'sent' }).eq('id', n.lead_id).eq('invite_status', 'queued');
              sent++; m365SentToday++; m365SentRun++; if (LANE_CAPPED_TYPES.includes(n.type)) cappedSentToday++;
            } else {
              // Graph refused: every later lane row in the run is held (a reply: sent through Resend), one finding says why.
              m365 = { ...m365, active: false, refused: true, why: 'refused: ' + r.status };
              try { await fileFinding(refusalFinding(m365.mailbox, r.status, M365_SECRET_NAMES.filter((k) => !!Deno.env.get(k)))); } catch (_e) { /* the hold below still happens */ }
              if (afterRefusal(isReply) === 'resend') toResend = true;
              else {
                await admin.from('notifications').update({ status: 'queued', claimed_at: null, not_before: heldUntil('unverified', new Date()).toISOString(), provider_message_id: null,
                  last_error: ('held: ' + r.status + '; never sent through Resend').slice(0, 500) }).eq('id', n.id);
                laneHeld++;
              }
            }
          } catch (e) {
            // No answer: sent-unconfirmed, never sent again (the same rule as the Resend path below).
            lastErr = String((e as Error)?.message || e).slice(0, 200); unconfirmed++;
            await admin.from('notifications').update({ status: 'sent', sent_at: new Date().toISOString(), provider_message_id: null,
              last_error: ('the POST to Microsoft Graph did not return (' + lastErr + '); sent-unconfirmed, will NOT be sent again').slice(0, 500) }).eq('id', n.id);
          }
        }
        if (!toResend) continue;
      }
      const wrapper = supplierSide ? tplSup : (internal ? '' : tplCust);
      // The supplier-portal desk is the sales engineer's (founder, 14 Sep 2026: "its always the sales
      // agent"), so its mail is signed by that seat, not with the founder's name.
      const seatMail = String(n.kind || '').startsWith('sales_engineer_');
      // THE FRAME SPEAKS THE RECIPIENT'S LANGUAGE TOO (founder, 14 Sep 2026). notifications.lang is
      // the registered language; an Arabic body inside an English signature and footer is exactly the
      // mixed message the rule forbids.
      // A SUPPLIER'S FRAME IS ENGLISH (founder, 28 Sep 2026): whatever a row's lang says, a supplier-bound
      // mail never carries the Arabic signature, footer or right-to-left frame.
      const arMail = !internal && !supplierSide && n.lang === 'ar';
      // 22 Sep 2026 (documents-language audit, DL-07): the signature block prints NAME then TITLE, and
      // the sales-engineer seat printed "مهندس المبيعات" in both lines — the Arabic reader saw the same
      // words twice where the English reader saw a person and a desk. The name is the seat, the title
      // is the desk it sits at, in both languages.
      // THE INVITATION ENDS WITH ONE QUESTION (24 Sep 2026, marketing): an English supplier invitation whose
      // stored body does not end with a question gets invitation_copy.ts's, after the link and before the footer.
      // 27 Oct 2026: a supplier campaign row on this fallback route sends the SAME plain-text email as the Microsoft
      // 365 lane (campaignMail): no HTML frame, no link, no closing question, no Al Furjan footer, the opt-out in the
      // List-Unsubscribe headers and the body's own "stop" line. A copy rule failure holds it, as on that lane.
      const camp = supplierSide && isLaneType(n.type) ? await campaignFor(n) : null;
      if (camp?.bad.length) { await admin.from('notifications').update({ status: 'held', last_error: ('held: supplier campaign copy rule failed: ' + camp.bad.map((l) => l.rule + ' (' + (l.detail || '') + ')').join('; ')).slice(0, 500) }).eq('id', n.id); held++; continue; }
      const inviteEn = String(n.type || '').startsWith('supplier_invite') && !arMail;
      const mailBody = inviteEn ? withReplyQuestion(n.body || '') : (n.body || '');
      const htmlBody0 = tmpl({ body: mailBody, logo, name: seatMail ? (arMail ? 'مهندس المبيعات' : 'Sales Engineer') : (arMail ? sigNameAr : sigName), title: seatMail ? (arMail ? 'فريق المبيعات' : 'Sales team') : (arMail ? 'المؤسس' : sigTitle), channelEmail: reply, unsub, wrapper, internal, subject: n.subject || '', preheader: inviteEn ? invitePreheader : '' });
      const htmlBody = ownDomain(arMail ? arabicFrame(htmlBody0) : htmlBody0, Deno.env.get('SUPABASE_URL') || '', assetBase);
      // FAIL CLOSED ON A DOCUMENT WE CANNOT READ. A weekly financial report whose PDF has been
      // moved or deleted must NOT go out as a cheerful covering note with nothing attached: the
      // founder would read "here is this week's report", find no report, and have no way to tell
      // that from a report saying nothing happened. Failing the row keeps it queued for retry and
      // records why in last_error.
      const att = await resolveAttachments(n.attachments);
      if (!att.ok) {
        lastErr = att.err.slice(0, 200);
        await failNote(n, 'attachment could not be prepared, so the email was NOT sent: ' + att.err);
        continue;
      }
      try {
        // The text/plain part is written, not left to be derived from the dark HTML frame: it carries
        // the body, the footer and the unsubscribe URL in the recipient's language.
        // payload.ts builds it (22 Sep 2026) so the exact message can be rendered and inbox-linted offline.
        const mail: Record<string, unknown> = camp
          ? resendPayload({ from, to: n.to_email, reply, subject: camp.subject, html: '', text: camp.text, unsub, unsubMailto: UNSUBSCRIBE_MAILBOX })
          : resendPayload({ from, to: n.to_email, reply, subject: n.subject || 'QuotesDone', html: htmlBody,
          // The mailto half goes to the mailbox resend_inbound reads (_shared/unsubscribe_mailbox.ts), not to
          // the reply-to address.
          text: plainTextPart({ body: mailBody, unsub, ar: arMail, internal }), unsub, unsubMailto: UNSUBSCRIBE_MAILBOX, inReplyTo: n.in_reply_to });
        if (att.list.length) { mail.attachments = att.list; attached += att.list.length; }
        // IDEMPOTENCY-KEY AND A DEADLINE (22 Sep 2026, it_engineer, CONN-03). Resend deduplicates on
        // this header for 24 hours, so the one case a claim cannot prevent — the POST left, the answer
        // did not come back, the row is retried later — costs a duplicate ACCEPTANCE and not a
        // duplicate EMAIL. The key is the notification id, which is what "this message" means here.
        // 15 s: this loop holds up to 40 rows and the whole function answers inside email_cron's 60 s.
        const r = await timedFetch('https://api.resend.com/emails', { method: 'POST', headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json', 'Idempotency-Key': 'qd-notif-' + n.id }, body: JSON.stringify(mail) }, 15_000);
        // KEEP THE PROVIDER'S OWN NAME FOR THE MESSAGE. status='sent' only ever meant "Resend
        // answered 2xx"; without the id, that claim could never be taken back to the provider and
        // checked. This is what makes "the accountant sent the founder his report" verifiable
        // against Resend instead of against a column this company writes itself.
        if (r.ok) {
          let providerId: string | null = null;
          try { providerId = ((await r.json()) as { id?: string })?.id ?? null; } catch (_e) { /* a 2xx with no body is still an acceptance */ }
          await admin.from('notifications').update({ status: 'sent', sent_at: new Date().toISOString(), provider_message_id: providerId }).eq('id', n.id);
          sent++;
          if (lane.active && LANE_CAPPED_TYPES.includes(n.type) && from === lane.from) laneSentToday++;
        }
        else {
          const t = await r.text(); lastErr = ('HTTP ' + r.status + ': ' + t).slice(0, 200);
          await failNote(n, 'Resend answered HTTP ' + r.status + ': ' + t, { permanent: PERMANENT_HTTP.has(r.status), retryAfterMs: retryAfterMs(r.headers.get('retry-after')) });
          console.error('resend fail', n.id, r.status, t);
        }
      } catch (e) {
        // A THROW HERE MEANS THE REQUEST LEFT AND THE ANSWER DID NOT (22 Sep 2026, it_engineer, CONN-03).
        // Before the Idempotency-Key it went to failNote and a timeout on a message Resend had accepted sent
        // it again on the next pass; so the row was marked sent-unconfirmed at once and never retried.
        // RETRIED UNDER THE SAME KEY BEFORE THE CEILING (it_engineer, 3 Nov 2026, drill D3). MEASURED by the drill:
        // with no retry, a message Resend never received was lost (sent-unconfirmed, delivered 0 times), where the
        // qualification matrix (F09.03, D3) asks for "exactly once after recovery". The key above is what makes
        // the retry safe: Resend answers a repeated accepted key with its first answer and sends nothing (24 h;
        // the retries here span about 25 minutes, RETRY_BACKOFF_MS). Only at the ceiling is the row marked 'sent'
        // with provider_message_id NULL and the reason in last_error, this estate's existing way of saying
        // UNCONFIRMED: fn_customer_support_delivery_watch returns 'sent_unconfirmed' for exactly that shape, and
        // fn_originator_checks_delivery refuses to re-send on it.
        // prevented by: supabase/functions/send_outbox/drill_send_faults.test.ts
        lastErr = String((e as Error)?.message || e).slice(0, 200);
        if ((Number(n.attempts) || 0) + 1 < MAX_ATTEMPTS) {
          await failNote(n, 'the POST to Resend did not return (' + lastErr + '); retried later under the same Idempotency-Key (qd-notif-' + n.id + '), so a message Resend did accept is not sent twice');
          console.error(e);
          continue;
        }
        unconfirmed++;
        await admin.from('notifications').update({ status: 'sent', sent_at: new Date().toISOString(), provider_message_id: null,
          last_error: ('the POST to Resend did not return (' + lastErr + '); it may or may not have been accepted, so this row is sent-unconfirmed and will NOT be sent again').slice(0, 500) }).eq('id', n.id);
        console.error(e);
      }
    }
    // Only log runs that did something. Idle polls (nothing queued) stay out of agent_runs
    // so a real event is never buried under 720 empty rows a day.
    const didWork = sent || failed || suppressed || held || skipped || laneHeld || unconfirmed || writeFailed || duplicateIds.length;
    if (duplicateIds.length || !recentList) {
      try {
        await admin.rpc('fn_it_engineer_finding_upsert', {
          p_issue_key: recentList ? 'outbox_duplicate_refused' : 'outbox_duplicate_check_unreadable',
          p_title: recentList ? 'The outbox refused a message already sent to the same person' : 'The outbox could not read what it had just sent, so it could not check for duplicates',
          p_where: 'supabase/functions/send_outbox -> _shared/outbox_duplicate_guard.ts',
          p_blast: recentList ? 'A caller queued the same message to the same person twice inside ' + dupWindow + ' minutes; the repeat was cancelled, not sent.'
            : 'This run sent without the duplicate check (an unreadable history must not stop the outbox).',
          p_affected: duplicateIds.length || rows.length, p_evidence: { notification_ids: duplicateIds.slice(0, 50), window_min: dupWindow } });
      } catch (_e) { /* the refusal stands even if the finding cannot be written */ }
    }
    if (deadlettered) await logRun('error', { sent, failed, retried, deadlettered, suppressed, held, skipped, pending: rows.length }, deadlettered + ' email(s) permanently dead-lettered after ' + MAX_ATTEMPTS + ' attempts (or at once on a permanent 400/422 refusal) and will never be delivered. Last error: ' + lastErr);
    else if (failed) await logRun('error', { sent, failed, retried, suppressed, held, skipped, pending: rows.length }, 'Resend rejected ' + failed + ' email(s), will retry. Last error: ' + lastErr);
    // A database write around a Graph send failed (the marker before it, or the 'sent' record after it): visible here, and
    // the marker makes the next run record the row rather than send it twice.
    else if (writeFailed) await logRun('error', { sent, write_failed: writeFailed, unconfirmed, held, pending: rows.length }, writeFailed + ' notification write(s) around a Microsoft 365 send failed; none is sent twice. Last error: ' + lastErr);
    else if (didWork) await logRun('ok', { sent, suppressed, held, skipped, pending: rows.length, remaining_today: Math.max(0, remaining - sent) }, held ? (held + ' held (supplier sending gate or stale)') : '');
    return J({ ok: true, sent, failed, retried, deadlettered, skipped, suppressed, held, attached, unconfirmed, write_failed: writeFailed, pending: rows.length, cap, remaining_today: Math.max(0, remaining - sent), invite_lane: lane.active ? lane.domain : lane.why, invite_m365: m365.active ? m365.mailbox : m365.why, invite_lane_held: laneHeld });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
  finally {
    // Rows this run resolved are no longer 'sending', so the status filter makes this exact: only a
    // claim nobody finished is handed back. The 5-minute expiry in fn_notifications_claim stays as the
    // backstop for the case where even this write fails.
    if (claimedIds.length) {
      try { await admin.from('notifications').update({ status: 'queued', claimed_at: null }).in('id', claimedIds).eq('status', 'sending'); }
      catch (_e) { /* the 5-minute claim expiry in fn_notifications_claim is the backstop */ }
    }
  }
}, { okEveryMs: 600000 }));
const RESERVED_TEST_DOMAIN = /@(?:[a-z0-9_-]+[.])*(?:example[.](?:com|net|org)|test|example|invalid|localhost)$/i;
function isDocRequest(type: string) { return /licen[cs]e|renew|expir|doc[_-]?request|document[_-]?request|upload[_-]?doc/i.test(String(type || '')); }
async function unsubTok(email: string, secret: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(email.toLowerCase()));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('').slice(0, 20);
}
