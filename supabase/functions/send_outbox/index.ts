// send_outbox - flushes queued EMAIL notifications via Resend. Honors email_suppressions, daily cap, unsubscribe, supplier-send gate + stale guard.
// v14: internal/admin emails now get a structured, branded HTML template (headings, bullets, links) + internal footer. Added ?preview mode. Retries up to 3, then dead-letter. verify_jwt=false (secret-gated).
// v16: agent_runs instrumentation. This runs every 2 minutes and previously returned ok:true no matter what,
//      so 'email_enabled=false', a missing Resend key, or a hit daily cap looked identical to a healthy flush
//      while mail silently piled up. Recurring config states are throttled to one row per hour so the
//      2-minute cadence cannot bury the signal; idle runs with no work are not logged at all.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { encodeBase64 } from 'jsr:@std/encoding/base64';
import { requireInternal } from '../_shared/internal_auth.ts';
import { BRAND, lockupImg } from '../_shared/brand.ts';
import { arabicFrame } from './arabic_frame.ts';
import { OWNED_CHANNEL_FILTER, ownsChannel } from './channels.ts';
import { observe } from '../_shared/observe.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN_BASE = (Deno.env.get('SUPABASE_URL') || '') + '/functions/v1';
const MAX_ATTEMPTS = 3;
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 28 Jul 2026 (missed by the 27 Jul sweep): sec() returns undefined/'' when the
// app_secrets read fails or the row is missing, and the guard below compared strictly, so a caller
// posting {} matched and gained full service-role authority on a function that requires no JWT. The
// stored secret must now be a real value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
async function tmplRow(n: string) { try { const { data } = await admin.from('templates').select('content').eq('name', n).maybeSingle(); return (data?.content as string) || ''; } catch { return ''; } }
function esc(s: string) { return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
// BRAND: the founder's kit is on file (public.company_brand). Every colour below is one of its
// rows, and this file now renders on NAVY, so it uses the on-navy pair throughout. The on-white
// link (teal-deep #0B8276) is gone from here -- it was correct when the mail was white and is
// near-invisible on #123041. Brand teal #14B8A6 remains an accent that never carries text.
// v18 (8 Sep 2026): renderBody's output is placed on the DARK internal card, so it needs the
// on-navy pair, not the on-white one. company_brand.contrast.links states it outright -- "On navy:
// teal-light #6EE7D4" -- and teal-deep #0B8276 is the on-WHITE link, near-invisible on #123041.
// The body colour had the same fault: #1f2937 is dark grey, which on navy is grey on black.
const DARK_LINK = '#6EE7D4', DARK_INK = '#EAF4F2';
function linkify(s: string) { return s.replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" style="color:' + DARK_LINK + '">$1</a>'); }

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

// Turn a plain-text agent body into structured HTML: ALL-CAPS short lines -> headings, -/• lines -> bullets, URLs -> links.
function renderBody(raw: string) {
  const lines = String(raw || '').split('\n'); let html = ''; let inList = false;
  const closeList = () => { if (inList) { html += '</ul>'; inList = false; } };
  for (const line of lines) {
    const t = line.replace(/\s+$/, '');
    if (!t) { closeList(); html += '<div style="height:8px"></div>'; continue; }
    if (/^[=\-_]{3,}$/.test(t)) { continue; }
    if (/^\s*[-•*]\s+/.test(t)) { if (!inList) { html += '<ul style="margin:6px 0 6px 18px;padding:0">'; inList = true; } html += '<li style="margin:3px 0;font-size:15px;line-height:1.55;color:' + DARK_INK + '">' + linkify(esc(t.replace(/^\s*[-•*]\s+/, ''))) + '</li>'; continue; }
    closeList();
    if (t === t.toUpperCase() && /[A-Z]/.test(t) && t.length <= 64) { html += '<h3 style="margin:18px 0 6px;font-size:13px;font-weight:800;color:' + DARK_LINK + ';text-transform:uppercase;letter-spacing:.04em">' + esc(t) + '</h3>'; continue; }
    html += '<p style="margin:0 0 9px;font-size:15px;line-height:1.6;color:' + DARK_INK + '">' + linkify(esc(t)) + '</p>';
  }
  closeList();
  return html;
}
function tmpl(opts: { body: string; logo: string; name: string; title: string; channelEmail: string; unsub: string; wrapper?: string; internal?: boolean; subject?: string }) {
  const { body, logo, name, title, channelEmail, unsub, wrapper, internal, subject } = opts;
  // v17 (8 Sep 2026): the logo is the horizontal OnDark lockup, not the 192px PWA app tile, so
  // 34x34 with a border-radius would squash a wordmark into a square and round its corners off.
  //
  // v18 (8 Sep 2026, founder: "make the logo a bit bigger... everywhere from now it should [be
  // sized] in terms of the height"). Measured rather than nudged: the supplied lockup is a
  // 1859x460 box holding 1608x176 of artwork, so 62% of its height is empty alpha. At width 170
  // the box came out 42px tall and the visible wordmark 16px -- the same height as the 15px body
  // text beneath it, which is precisely what he was looking at. Widening the box would have spent
  // 62% of every added pixel on nothing.
  //
  // So the size now comes from lockupImg() in _shared/brand.ts, which uses the TRIMMED lockup and
  // takes a HEIGHT. One helper, so email, UI and PDF cannot drift apart, and one unit, because a
  // width means something different for every asset depending on the padding it was drawn inside.
  const logoTag = logo ? lockupImg({ ground: 'dark', height: BRAND.logoHeight.email }) : '';
  const unsubLine = unsub ? `<br><a href="${unsub}" style="color:#9ca3af">Unsubscribe</a> &middot; or reply to this email to be removed.` : '';
  if (wrapper && wrapper.indexOf('{{BODY}}') >= 0) {
    return wrapper.split('{{LOGO}}').join(logoTag).split('{{BODY}}').join(esc(body)).split('{{NAME}}').join(esc(name)).split('{{TITLE}}').join(esc(title)).split('{{REPLY}}').join(esc(channelEmail)).split('{{UNSUB}}').join(unsubLine);
  }
  // v17 (8 Sep 2026): dark, on the brand kit's own navy, and table-based. This fallback is what
  // internal/admin mail uses (it takes no wrapper), and it had the same two faults the customer
  // template had: display:flex, which Outlook's Word engine ignores outright, and a light ground.
  // Colours and their contrast ratios come from company_brand, which records them measured:
  // paper #EAF4F2 on navy 14.4:1 AAA, muted #9DB2B2 7.3:1 AAA, teal-light #6EE7D4 10.8:1 AAA.
  // The kit also states the rule this file previously broke -- on navy the link is teal-light, and
  // brand teal #14B8A6 is an accent that must never carry text.
  const INK = '#EAF4F2', MUTED = '#9DB2B2', SURFACE = '#123041', GROUND = '#06121B', RULE = '#173A4B', DLINK = '#6EE7D4';
  const header = `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="vertical-align:middle">${logoTag}</td>${internal ? `<td align="right" style="vertical-align:middle;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:700;color:${MUTED};letter-spacing:.06em">INTERNAL</td>` : ''}</tr></table>`;
  const titleBlock = (internal && subject) ? `<h2 style="margin:18px 0 12px;font-size:19px;line-height:1.3;color:#FFFFFF;font-family:Arial,Helvetica,sans-serif">${esc(subject)}</h2>` : '';
  const content = internal ? renderBody(body) : `<div dir="auto" style="font-size:15px;line-height:1.65;white-space:pre-wrap;color:${INK};text-align:start;unicode-bidi:plaintext">${esc(body)}</div>`;
  const sig = `<div style="margin-top:26px;padding-top:18px;border-top:1px solid ${RULE};font-size:13px;color:${MUTED};line-height:1.6"><div style="font-weight:700;color:#FFFFFF">${esc(name)}</div><div style="color:${INK}">${esc(title)}, QuotesDone</div><div style="margin-top:3px">${esc(channelEmail)} &middot; <a href="https://quotesdone.com" style="color:${DLINK};text-decoration:none">quotesdone.com</a></div></div>`;
  const footer = internal
    ? `<div style="text-align:center;color:${MUTED};font-size:12px;margin-top:16px;line-height:1.55">QuotesDone OS &middot; internal operations report &middot; Dubai, UAE<br>You're receiving this because you're an administrator of QuotesDone.</div>`
    : `<div style="text-align:center;color:${MUTED};font-size:12px;margin-top:16px;line-height:1.55">QuotesDone &middot; Dubai, UAE<br>You're receiving this because your business is publicly listed and may match clients sourcing on QuotesDone.${unsubLine}</div>`;
  // bgcolor AND inline background on every coloured cell: different clients read different ones,
  // and Outlook is unreliable about background-color on a div.
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark"></head><body style="margin:0;padding:0;background:${GROUND};font-family:Arial,Helvetica,sans-serif"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${GROUND}" style="background:${GROUND};padding:28px 12px"><tr><td align="center"><table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" bgcolor="${SURFACE}" style="max-width:600px;width:100%;background:${SURFACE};border:1px solid ${RULE};border-radius:14px"><tr><td style="padding:30px">${header}${titleBlock}${content}${sig}</td></tr></table><table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%"><tr><td>${footer}</td></tr></table></td></tr></table></body></html>`;
}
// okEveryMs 10 minutes: this polls every 2 minutes, and its logRun/logThrottled rows above already
// carry the business signal. The observe() row adds only the HTTP/latency view, so one healthy
// sample per ten minutes is plenty and 720 rows a day would bury the rows that matter.
Deno.serve(observe('send_outbox', async (req) => {
  try {
    const body = await req.json().catch(() => ({}));
    // AUDIT 9.5 (3 Aug 2026): the unsubscribe footer and the RFC 8058 List-Unsubscribe headers
    // are signed with a dedicated long-lived key. They used to be signed with inbound_secret, so
    // withdrawing it would have both invalidated every delivered link AND - because the link is
    // only built when the key reads back - sent supplier mail with no unsubscribe mechanism at all.
    const unsubKey = await sec('unsubscribe_signing_key');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'send_outbox');
    if (!__auth.ok) { await logThrottled('forbidden', 60, 'error', {}, 'send_outbox called without the inbound secret'); return J({ error: 'forbidden' }, 403); }
    // Preview mode: render the internal/branded template for a sample body without sending.
    if (body.preview) {
      const logo = (await sec('email_logo_url')) || '';
      const sigName = (await sec('email_signature_name')) || 'Ahmad Alzain';
      const sigTitle = (await sec('email_signature_title')) || 'Founder';
      const html = tmpl({ body: String(body.sample || 'SUMMARY\nAll systems healthy.\n\nFINDINGS\n- Uptime 99.9%\n- 2 alerts auto-resolved\n\nNext review at https://quotesdone.com/os'), logo, name: sigName, title: sigTitle, channelEmail: 'info@quotesdone.com', unsub: '', internal: body.internal !== false, subject: String(body.subject || 'Daily operations report') });
      return J({ ok: true, html });
    }
    const enabled = (await sec('email_enabled')) === 'true';
    const supEnabled = (await sec('supplier_emails_enabled')) === 'true';
    const staleH = parseInt((await sec('email_stale_hours')) || '72', 10);
    const key = await sec('resend_api_key');
    const fromSup = (await sec('email_from_supplier')) || 'QuotesDone <supplier@quotesdone.com>';
    const fromInfo = (await sec('email_from_info')) || 'QuotesDone <info@quotesdone.com>';
    const replySup = (await sec('email_reply_supplier')) || 'supplier@quotesdone.com';
    const replyDocs = (await sec('email_reply_supplier_docs')) || 'docs@mail.quotesdone.com';
    const replyInfo = (await sec('email_reply_info')) || 'info@quotesdone.com';
    const logo = (await sec('email_logo_url')) || '';
    const sigName = (await sec('email_signature_name')) || 'Ahmad Alzain';
    const sigTitle = (await sec('email_signature_title')) || 'Founder';
    const tplSup = await tmplRow('email_supplier'); const tplCust = await tmplRow('email_customer');
    const cap = parseInt((await sec('daily_send_cap')) || '80', 10);
    const since = new Date(); since.setUTCHours(0, 0, 0, 0);
    const { count: sentToday } = await admin.from('notifications').select('id', { count: 'exact', head: true }).eq('status', 'sent').gte('sent_at', since.toISOString());
    const remaining = Math.max(0, cap - (sentToday || 0));
    const { data: q } = await admin.from('notifications').select('*').or('status.eq.queued,status.eq.pending,status.is.null').or(OWNED_CHANNEL_FILTER).order('created_at', { ascending: true }).limit(Number(body.limit) || 40);
    const rows = q || [];
    // Previously a silent ok:true - mail just accumulated with no signal anywhere.
    if (!enabled || !key) { await logThrottled('email_disabled', 60, 'error', { pending: rows.length, email_enabled: enabled, has_resend_key: !!key }, 'EMAIL NOT SENDING - ' + (!enabled ? 'email_enabled is not true' : 'resend_api_key missing') + '; ' + rows.length + ' notification(s) waiting'); return J({ ok: true, pending: rows.length, sent: 0, note: 'email disabled or resend_api_key missing - queued and will flush once enabled' }); }
    if (remaining <= 0) { await logThrottled('cap_reached', 60, 'error', { pending: rows.length, cap, sent_today: sentToday || 0 }, 'daily send cap reached - ' + rows.length + ' notification(s) held until tomorrow'); return J({ ok: true, sent: 0, pending: rows.length, note: 'daily send cap reached', cap, sent_today: sentToday || 0 }); }
    const toEmails = [...new Set(rows.map((r: any) => r.to_email).filter(Boolean))];
    let supSet = new Set<string>();
    if (toEmails.length) { const { data: sup } = await admin.from('email_suppressions').select('email').in('email', toEmails); supSet = new Set((sup || []).map((s: any) => s.email)); }
    let sent = 0, failed = 0, retried = 0, deadlettered = 0, skipped = 0, suppressed = 0, held = 0, attached = 0;
    const failNote = async (n: any, msg: string) => {
      const att = (Number(n.attempts) || 0) + 1;
      const dead = att >= MAX_ATTEMPTS;
      await admin.from('notifications').update({ status: dead ? 'failed' : 'queued', attempts: att, last_error: String(msg).slice(0, 500) }).eq('id', n.id);
      failed++; if (dead) deadlettered++; else retried++;
    };
    let lastErr = '';
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
      // 3 SEP 2026: RFC 2606 reserved domains (example.com/net/org, .test, .example, .invalid,
      // localhost) are never deliverable — Resend answers 422 "Invalid to field" and this loop used
      // to log it as a failed run and retry. The demo fixtures address every ZZ DEMO party there on
      // purpose; refusing before any provider call is the clean skip, and it guarantees production
      // never emails a fixture address.
      if (RESERVED_TEST_DOMAIN.test(n.to_email)) { await admin.from('notifications').update({ status: 'skipped', last_error: 'reserved test domain (RFC 2606): never deliverable, refused before any provider call' }).eq('id', n.id); skipped++; continue; }
      if (supSet.has(n.to_email)) { await admin.from('notifications').update({ status: 'suppressed' }).eq('id', n.id); suppressed++; continue; }
      const ageH = (Date.now() - new Date(n.created_at).getTime()) / 3.6e6;
      if (ageH > staleH) { await admin.from('notifications').update({ status: 'held' }).eq('id', n.id); held++; continue; }
      const supplierSide = n.to_role === 'supplier';
      const internal = n.to_role === 'admin' || n.to_role === 'founder';
      const docReq = supplierSide && isDocRequest(n.type);
      if (supplierSide && !supEnabled && !docReq) { await admin.from('notifications').update({ status: 'held' }).eq('id', n.id); held++; continue; }
      if (sent >= remaining) break;
      const from = supplierSide ? fromSup : fromInfo;
      const reply = supplierSide ? (docReq ? replyDocs : replySup) : replyInfo;
      const unsub = (supplierSide && unsubKey) ? `${FN_BASE}/unsubscribe?e=${encodeURIComponent(n.to_email)}&t=${await unsubTok(n.to_email, unsubKey)}` : '';
      const wrapper = supplierSide ? tplSup : (internal ? '' : tplCust);
      // The supplier-portal desk is the sales engineer's (founder, 14 Sep 2026: "its always the sales
      // agent"), so its mail is signed by that seat, not with the founder's name.
      const seatMail = String(n.kind || '').startsWith('sales_engineer_');
      // THE FRAME SPEAKS THE RECIPIENT'S LANGUAGE TOO (founder, 14 Sep 2026). notifications.lang is
      // the registered language; an Arabic body inside an English signature and footer is exactly the
      // mixed message the rule forbids.
      const arMail = !internal && n.lang === 'ar';
      const htmlBody0 = tmpl({ body: n.body || '', logo, name: seatMail ? (arMail ? 'مهندس المبيعات' : 'QuotesDone Sales Engineer') : sigName, title: seatMail ? (arMail ? 'مهندس المبيعات' : 'Sales Engineer') : (arMail ? 'المؤسس' : sigTitle), channelEmail: reply, unsub, wrapper, internal, subject: n.subject || '' });
      const htmlBody = arMail ? arabicFrame(htmlBody0) : htmlBody0;
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
        const mail: Record<string, unknown> = { from, to: [n.to_email], reply_to: reply, subject: n.subject || 'QuotesDone', html: htmlBody };
        if (att.list.length) { mail.attachments = att.list; attached += att.list.length; }
        if (unsub) mail.headers = { 'List-Unsubscribe': `<${unsub}>, <mailto:${reply}?subject=unsubscribe>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' };
        const r = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' }, body: JSON.stringify(mail) });
        // KEEP THE PROVIDER'S OWN NAME FOR THE MESSAGE. status='sent' only ever meant "Resend
        // answered 2xx"; without the id, that claim could never be taken back to the provider and
        // checked. This is what makes "the accountant sent the founder his report" verifiable
        // against Resend instead of against a column this company writes itself.
        if (r.ok) {
          let providerId: string | null = null;
          try { providerId = ((await r.json()) as { id?: string })?.id ?? null; } catch (_e) { /* a 2xx with no body is still an acceptance */ }
          await admin.from('notifications').update({ status: 'sent', sent_at: new Date().toISOString(), provider_message_id: providerId }).eq('id', n.id);
          sent++;
        }
        else { const t = await r.text(); lastErr = String(t).slice(0, 200); await failNote(n, t); console.error('resend fail', n.id, t); }
      } catch (e) { lastErr = String((e as Error)?.message || e).slice(0, 200); await failNote(n, String((e as Error)?.message || e)); console.error(e); }
    }
    // Only log runs that did something. Idle polls (nothing queued) stay out of agent_runs
    // so a real event is never buried under 720 empty rows a day.
    const didWork = sent || failed || suppressed || held || skipped;
    if (deadlettered) await logRun('error', { sent, failed, retried, deadlettered, suppressed, held, skipped, pending: rows.length }, deadlettered + ' email(s) permanently dead-lettered after ' + MAX_ATTEMPTS + ' attempts and will never be delivered. Last error: ' + lastErr);
    else if (failed) await logRun('error', { sent, failed, retried, suppressed, held, skipped, pending: rows.length }, 'Resend rejected ' + failed + ' email(s), will retry. Last error: ' + lastErr);
    else if (didWork) await logRun('ok', { sent, suppressed, held, skipped, pending: rows.length, remaining_today: Math.max(0, remaining - sent) }, held ? (held + ' held (supplier sending gate or stale)') : '');
    return J({ ok: true, sent, failed, retried, deadlettered, skipped, suppressed, held, attached, pending: rows.length, cap, remaining_today: Math.max(0, remaining - sent) });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
}, { okEveryMs: 600000 }));
const RESERVED_TEST_DOMAIN = /@(?:[a-z0-9_-]+[.])*(?:example[.](?:com|net|org)|test|example|invalid|localhost)$/i;
function isDocRequest(type: string) { return /licen[cs]e|renew|expir|doc[_-]?request|document[_-]?request|upload[_-]?doc/i.test(String(type || '')); }
async function unsubTok(email: string, secret: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(email.toLowerCase()));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('').slice(0, 20);
}
