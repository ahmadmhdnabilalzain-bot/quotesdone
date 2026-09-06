// send_outbox - flushes queued EMAIL notifications via Resend. Honors email_suppressions, daily cap, unsubscribe, supplier-send gate + stale guard.
// v14: internal/admin emails now get a structured, branded HTML template (headings, bullets, links) + internal footer. Added ?preview mode. Retries up to 3, then dead-letter. verify_jwt=false (secret-gated).
// v16: agent_runs instrumentation. This runs every 2 minutes and previously returned ok:true no matter what,
//      so 'email_enabled=false', a missing Resend key, or a hit daily cap looked identical to a healthy flush
//      while mail silently piled up. Recurring config states are throttled to one row per hour so the
//      2-minute cadence cannot bury the signal; idle runs with no work are not logged at all.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
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
// BRAND (6 Sep 2026): the founder's kit is on file (public.company_brand). Wordmark = navy "Quotes" + teal
// "Done" as in the on-white lockup; links and headings use teal-deep #0B8276, the shade that passes WCAG AA
// on white (brand teal #14B8A6 is 2.5:1 there — an accent, never text). The old #0d9488 was Tailwind's, not ours.
const LINK = '#0B8276';
function linkify(s: string) { return s.replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" style="color:' + LINK + '">$1</a>'); }

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
    if (/^\s*[-•*]\s+/.test(t)) { if (!inList) { html += '<ul style="margin:6px 0 6px 18px;padding:0">'; inList = true; } html += '<li style="margin:3px 0;font-size:15px;line-height:1.55">' + linkify(esc(t.replace(/^\s*[-•*]\s+/, ''))) + '</li>'; continue; }
    closeList();
    if (t === t.toUpperCase() && /[A-Z]/.test(t) && t.length <= 64) { html += '<h3 style="margin:18px 0 6px;font-size:13px;font-weight:800;color:' + LINK + ';text-transform:uppercase;letter-spacing:.04em">' + esc(t) + '</h3>'; continue; }
    html += '<p style="margin:0 0 9px;font-size:15px;line-height:1.6;color:#1f2937">' + linkify(esc(t)) + '</p>';
  }
  closeList();
  return html;
}
function tmpl(opts: { body: string; logo: string; name: string; title: string; channelEmail: string; unsub: string; wrapper?: string; internal?: boolean; subject?: string }) {
  const { body, logo, name, title, channelEmail, unsub, wrapper, internal, subject } = opts;
  const logoTag = logo ? `<img src="${logo}" width="34" height="34" alt="QuotesDone" style="border-radius:8px;display:block"/>` : '';
  const unsubLine = unsub ? `<br><a href="${unsub}" style="color:#9ca3af">Unsubscribe</a> &middot; or reply to this email to be removed.` : '';
  if (wrapper && wrapper.indexOf('{{BODY}}') >= 0) {
    return wrapper.split('{{LOGO}}').join(logoTag).split('{{BODY}}').join(esc(body)).split('{{NAME}}').join(esc(name)).split('{{TITLE}}').join(esc(title)).split('{{REPLY}}').join(esc(channelEmail)).split('{{UNSUB}}').join(unsubLine);
  }
  const header = `<div style="display:flex;align-items:center;gap:10px;margin-bottom:6px">${logoTag}<div style="font-weight:800;font-size:18px;color:#0C2330">Quotes<span style="color:#14B8A6">Done</span></div>${internal ? '<div style="margin-left:auto;font-size:11px;font-weight:700;color:#6b7280;background:#f1f5f4;border:1px solid #e5e7eb;border-radius:999px;padding:3px 10px">INTERNAL</div>' : ''}</div>`;
  const titleBlock = (internal && subject) ? `<h2 style="margin:14px 0 12px;font-size:19px;line-height:1.3;color:#0f172a">${esc(subject)}</h2>` : '';
  const content = internal ? renderBody(body) : `<div style="font-size:15px;line-height:1.6;white-space:pre-wrap">${esc(body)}</div>`;
  const sig = `<div style="margin-top:24px;padding-top:16px;border-top:1px solid #eef0f2;font-size:13px;color:#374151;line-height:1.55"><div style="font-weight:700;color:#0C2330">${esc(name)}</div><div>${esc(title)}, QuotesDone</div><div style="color:#6b7280;margin-top:2px">${esc(channelEmail)} &middot; <a href="https://quotesdone.com" style="color:${LINK};text-decoration:none">quotesdone.com</a></div></div>`;
  const footer = internal
    ? `<div style="text-align:center;color:#9ca3af;font-size:12px;margin-top:14px">QuotesDone OS &middot; internal operations report &middot; Dubai, UAE<br>You're receiving this because you're an administrator of QuotesDone.</div>`
    : `<div style="text-align:center;color:#9ca3af;font-size:12px;margin-top:14px">QuotesDone &middot; Dubai, UAE<br>You're receiving this because your business is publicly listed and may match clients sourcing on QuotesDone.${unsubLine}</div>`;
  return `<!doctype html><html><body style="margin:0;background:#f6f7f9;font-family:Arial,Helvetica,sans-serif;color:#1f2937"><div style="max-width:600px;margin:0 auto;padding:24px"><div style="background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:28px">${header}${titleBlock}${content}${sig}</div>${footer}</div></body></html>`;
}
Deno.serve(async (req) => {
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
    const { data: q } = await admin.from('notifications').select('*').or('status.eq.queued,status.eq.pending,status.is.null').order('created_at', { ascending: true }).limit(Number(body.limit) || 40);
    const rows = q || [];
    // Previously a silent ok:true - mail just accumulated with no signal anywhere.
    if (!enabled || !key) { await logThrottled('email_disabled', 60, 'error', { pending: rows.length, email_enabled: enabled, has_resend_key: !!key }, 'EMAIL NOT SENDING - ' + (!enabled ? 'email_enabled is not true' : 'resend_api_key missing') + '; ' + rows.length + ' notification(s) waiting'); return J({ ok: true, pending: rows.length, sent: 0, note: 'email disabled or resend_api_key missing - queued and will flush once enabled' }); }
    if (remaining <= 0) { await logThrottled('cap_reached', 60, 'error', { pending: rows.length, cap, sent_today: sentToday || 0 }, 'daily send cap reached - ' + rows.length + ' notification(s) held until tomorrow'); return J({ ok: true, sent: 0, pending: rows.length, note: 'daily send cap reached', cap, sent_today: sentToday || 0 }); }
    const toEmails = [...new Set(rows.map((r: any) => r.to_email).filter(Boolean))];
    let supSet = new Set<string>();
    if (toEmails.length) { const { data: sup } = await admin.from('email_suppressions').select('email').in('email', toEmails); supSet = new Set((sup || []).map((s: any) => s.email)); }
    let sent = 0, failed = 0, retried = 0, deadlettered = 0, skipped = 0, suppressed = 0, held = 0;
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
      if (n.channel === 'sms' || n.channel === 'whatsapp') { skipped++; continue; }
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
      const htmlBody = tmpl({ body: n.body || '', logo, name: sigName, title: sigTitle, channelEmail: reply, unsub, wrapper, internal, subject: n.subject || '' });
      try {
        const mail: Record<string, unknown> = { from, to: [n.to_email], reply_to: reply, subject: n.subject || 'QuotesDone', html: htmlBody };
        if (unsub) mail.headers = { 'List-Unsubscribe': `<${unsub}>, <mailto:${reply}?subject=unsubscribe>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' };
        const r = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' }, body: JSON.stringify(mail) });
        if (r.ok) { await admin.from('notifications').update({ status: 'sent', sent_at: new Date().toISOString() }).eq('id', n.id); sent++; }
        else { const t = await r.text(); lastErr = String(t).slice(0, 200); await failNote(n, t); console.error('resend fail', n.id, t); }
      } catch (e) { lastErr = String((e as Error)?.message || e).slice(0, 200); await failNote(n, String((e as Error)?.message || e)); console.error(e); }
    }
    // Only log runs that did something. Idle polls (nothing queued) stay out of agent_runs
    // so a real event is never buried under 720 empty rows a day.
    const didWork = sent || failed || suppressed || held || skipped;
    if (deadlettered) await logRun('error', { sent, failed, retried, deadlettered, suppressed, held, skipped, pending: rows.length }, deadlettered + ' email(s) permanently dead-lettered after ' + MAX_ATTEMPTS + ' attempts and will never be delivered. Last error: ' + lastErr);
    else if (failed) await logRun('error', { sent, failed, retried, suppressed, held, skipped, pending: rows.length }, 'Resend rejected ' + failed + ' email(s), will retry. Last error: ' + lastErr);
    else if (didWork) await logRun('ok', { sent, suppressed, held, skipped, pending: rows.length, remaining_today: Math.max(0, remaining - sent) }, held ? (held + ' held (supplier sending gate or stale)') : '');
    return J({ ok: true, sent, failed, retried, deadlettered, skipped, suppressed, held, pending: rows.length, cap, remaining_today: Math.max(0, remaining - sent) });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
});
const RESERVED_TEST_DOMAIN = /@(?:[a-z0-9_-]+[.])*(?:example[.](?:com|net|org)|test|example|invalid|localhost)$/i;
function isDocRequest(type: string) { return /licen[cs]e|renew|expir|doc[_-]?request|document[_-]?request|upload[_-]?doc/i.test(String(type || '')); }
async function unsubTok(email: string, secret: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(email.toLowerCase()));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('').slice(0, 20);
}
