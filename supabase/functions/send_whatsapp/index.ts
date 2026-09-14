// send_whatsapp - sends WhatsApp via Twilio. Single ({to, body}) or flush (drains queued channel='whatsapp' notifications).
// Business-initiated messages use APPROVED templates (ContentSid+ContentVariables) once wa_templates_ready='true'.
// Secret-guarded (inbound_secret). Auth via twilio API key. Sender from twilio_wa_from (digits, no prefix).
// v4: agent_runs instrumentation. Runs every 2 minutes and always returned 200, so three failure modes were
//     invisible: (a) whatsapp_not_configured, (b) wa_templates_ready=false, where queued rows are counted as
//     'skipped' but NOT updated, so they requeue forever and the backlog grows unbounded, (c) Twilio rejections.
//     Recurring states are throttled to one row per hour so the 2-minute cadence cannot bury the signal.
// v5: routes the document-expiry notice. fn_doc_final_notice and fn_reconcile_doc_blocks queue supplier
//     document warnings, but tmplKey() knew only three message types, so those rows resolved to no template
//     and were silently marked 'skipped' - queued, never delivered, and counted as a success. The mapping and
//     a portal destination for varsFor() are added here so delivery starts the moment Meta approves the
//     supplier_doc_expiry template already registered in wa_template_sids.
// v6 (6 Sep 2026): the founder's own alert gets a template, and the ledger gates every send. Founder:
//     "whatsapp token with twilio is with you, fix the template yourself." Every WhatsApp this number ever
//     sent him (13-16 Aug) is 'undelivered' 63016 — a freeform body outside a 24-hour session — because the
//     founder_alert type had no template. tmplKey() now maps it, varsFor() fills {{1}} from the alert line
//     and {{2}} from the detail, and public.messaging_template (written by wa_template_setup and refreshed
//     here from Twilio at most every ten minutes) decides: APPROVED sends; anything else is HELD — supplier
//     and customer rows stay queued, founder rows are marked skipped WITH the reason (the email already
//     carried the alert), and a direct send answers with the reason instead of erroring. No Twilio call is
//     made for a template Meta has not approved, so a pending template never pages anyone.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { isDemoPhone } from '../_shared/demo_identity.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined) || undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

// Observability -------------------------------------------------------------
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'send_whatsapp', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging block sending */ }
}
async function logThrottled(signal: string, minutes: number, status: string, counts: Record<string, unknown>, note: string) {
  try {
    const since = new Date(Date.now() - minutes * 60000).toISOString();
    const { data } = await admin.from('agent_runs').select('id').eq('agent', 'send_whatsapp')
      .gte('started_at', since).eq('counts->>signal', signal).limit(1);
    if (data && data.length) return;
  } catch (_e) { /* if the check fails, fall through and log */ }
  await logRun(status, { ...counts, signal }, note);
}

function normPhone(p: string){ let s=String(p||'').trim().replace(/[^0-9+]/g,''); if(!s) return ''; if(s.startsWith('00')) s='+'+s.slice(2); if(!s.startsWith('+')){ if(s.startsWith('0')) s='+971'+s.slice(1); else s='+'+s; } return s; }
const SUP_URL='https://quotesdone.com/suppliers';
const APP_URL='https://quotesdone.com/app';
const PORTAL_URL='https://quotesdone.com/portal';
function tmplKey(type:string):string|null{
  const t=(type||'').toLowerCase();
  if(['new_inquiry','inquiry_matched','supplier_new_inquiry'].includes(t)) return 'supplier_new_inquiry';
  if(['new_quote','quote_received','quote_submitted','quote_ready','quote_available'].includes(t)) return 'customer_new_quote';
  if(['reveal_receipt','reveal','supplier_revealed','supplier_unlocked','reveal_unlocked'].includes(t)) return 'customer_supplier_unlocked';
  // 3 SEP 2026: the supplier's side of the reveal. trg_reveal_receipt queues a WhatsApp to the supplier
  // (type quote_accepted) when they registered a number and opted in — the founder's 19 Aug contract:
  // both parties, both channels. Template registered by wa_template_setup under this key; until its
  // SID lands the row stays queued (see the mapped-but-unregistered branch below), never dropped.
  if(['quote_accepted','supplier_quote_accepted','customer_selected_you'].includes(t)) return 'supplier_quote_accepted';
  // Document compliance: final notice before suspension, and the suspension itself. Both are
  // transactional notices about the supplier's own account, which is why the Twilio template is
  // registered under the UTILITY category rather than MARKETING.
  if(['supplier_doc_expiry','doc_final_notice','doc_suspended','doc_expiry'].includes(t)) return 'supplier_doc_expiry';
  // 14 Sep 2026: the sales engineer's notices about a supplier's own quotes and account (a quote on
  // hold, the regenerated quote to approve, its release, the collaboration warning, the matching hold
  // and its lifting). Transactional, UTILITY category. Until wa_template_setup registers the SID the
  // rows stay queued (mapped-but-unregistered), never dropped; the email twin goes meanwhile.
  if(['quote_spec_hold','quote_spec_regenerated','quote_spec_released','supplier_collaboration_warning','supplier_matching_hold','supplier_matching_hold_lifted'].includes(t)) return 'supplier_account_notice';
  // 6 SEP 2026: the founder's own alert. fn_notify_founder queues it (allowed kind, severe level) and
  // wa_flush drains it here. "QuotesDone alert: {{1}}. Details: {{2}}. Open the OS to act." — registered
  // by wa_template_setup under this key.
  if(t==='founder_alert') return 'founder_alert';
  return null;
}
function shortSummary(s:string){ let x=String(s||'').replace(/\s+/g,' ').trim(); x=x.replace(/^(QuotesDone[:\-\s]*)/i,''); return x.slice(0,90)||'your request'; }
// A template variable may not carry a newline, a tab or a run of spaces (Meta refuses the send), so
// every value is flattened and capped before it reaches Twilio.
function waVar(s:string, max:number){ const x=String(s||'').replace(/\s+/g,' ').trim(); return x.length>max ? x.slice(0,max-1)+'…' : x; }
function varsFor(key:string, n:{subject?:string|null; body?:string|null}){
  if (key==='founder_alert') {
    // fn_notify_founder writes 'QuotesDone [level]: event' on the first line and the detail after it.
    const lines = String(n.body||'').split('\n'); const head = lines.shift()||''; const rest = lines.join(' ').trim();
    return {'1': waVar(shortSummary(head||n.subject||'') , 120), '2': waVar(rest || 'see the founder console at quotesdone.com/os', 500)};
  }
  const summary = shortSummary(n.subject||n.body||'');
  const url = key==='supplier_new_inquiry' ? SUP_URL
            : (key==='supplier_doc_expiry' || key==='supplier_quote_accepted' || key==='supplier_account_notice') ? PORTAL_URL
            : APP_URL;
  return {'1':summary,'2':url};
}
async function waSendBody(acct:string, ks:string, kk:string, from:string, to:string, body:string){
  const auth = btoa(ks + ':' + kk);
  const form = new URLSearchParams({ To: 'whatsapp:'+to, From: 'whatsapp:'+from, Body: body });
  const r = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${acct}/Messages.json`, { method:'POST', headers:{ 'Authorization':'Basic '+auth, 'Content-Type':'application/x-www-form-urlencoded' }, body: form.toString() });
  const jd = await r.json().catch(()=>({})); return { ok:r.ok, sid: jd?.sid||null, error: r.ok?null:(jd?.message||('http '+r.status)) };
}
async function waSendTemplate(acct:string, ks:string, kk:string, from:string, to:string, contentSid:string, vars:Record<string,string>){
  const auth = btoa(ks + ':' + kk);
  const form = new URLSearchParams({ To: 'whatsapp:'+to, From: 'whatsapp:'+from, ContentSid: contentSid, ContentVariables: JSON.stringify(vars) });
  const r = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${acct}/Messages.json`, { method:'POST', headers:{ 'Authorization':'Basic '+auth, 'Content-Type':'application/x-www-form-urlencoded' }, body: form.toString() });
  const jd = await r.json().catch(()=>({})); return { ok:r.ok, sid: jd?.sid||null, error: r.ok?null:(jd?.message||('http '+r.status)) };
}
// 6 SEP 2026: the ledger decides. public.messaging_template holds Twilio's word for every registered
// SID; 'approved' is trusted as read, anything else is re-asked of Twilio at most every ten minutes
// and written back, so approval is noticed within ten minutes of Meta's answer with no cron of its own.
// ponytail: an approved row is never re-checked; if Meta later pauses a template the send fails loudly
// and lands in agent_runs — re-ask on a Twilio rejection if that ever happens.
async function templateStatus(auth:string, sid:string, key:string, lang:string):Promise<{status:string; reason:string|null}>{
  const { data: row } = await admin.from('messaging_template').select('status,last_checked_at,approved_at,rejection_reason').eq('sid', sid).maybeSingle();
  const fresh = !!row && (row.status === 'approved' || (!!row.last_checked_at && Date.now() - Date.parse(row.last_checked_at) < 600000));
  if (fresh) return { status: String(row!.status), reason: (row!.rejection_reason as string|null) || null };
  const r = await fetch('https://content.twilio.com/v1/Content/' + sid + '/ApprovalRequests', { headers: { 'Authorization': 'Basic ' + auth } });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) return { status: String(row?.status || 'unknown'), reason: 'twilio http ' + r.status };
  const st = String(j?.whatsapp?.status || j?.status || 'unknown'); const now = new Date().toISOString();
  await admin.from('messaging_template').upsert({ sid, channel: 'whatsapp', template_key: key, lang, status: st, last_checked_at: now,
    name: j?.whatsapp?.name || null, category: j?.whatsapp?.category || null, rejection_reason: j?.whatsapp?.rejection_reason || null,
    approved_at: st === 'approved' ? (row?.approved_at || now) : null }, { onConflict: 'sid' });
  return { status: st, reason: j?.whatsapp?.rejection_reason || null };
}
Deno.serve(observe('send_whatsapp', async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'send_whatsapp');
    if (!__auth.ok) {
      // 4 Aug 2026. An unidentified EXTERNAL process has been presenting an unrecognised credential
      // here every two minutes since 05:06 UTC on 3 Aug - 500+ attempts against an endpoint that
      // sends messages. It was written off as a "phantom caller outside cron.job"; it is outside
      // cron.job, but it is not a phantom. Ruled out by measurement: pg_net logged zero non-200
      // responses over three hours, no object in pg_proc references send_whatsapp, and the repo's
      // only scheduled caller is wa_flush, which authenticates fine and returns 200 alongside it.
      //
      // This row previously recorded that a refusal happened and nothing about who was refused, so
      // the same denial has been logged hourly for a day without ever becoming actionable. A
      // repeated unauthorised caller you cannot name is not noise, it is an open question.
      const ip = req.headers.get('x-forwarded-for') || req.headers.get('cf-connecting-ip') || null;
      await logThrottled('forbidden', 60, 'error', {
        caller_ip: ip, user_agent: (req.headers.get('user-agent') || '').slice(0, 200),
        referer: (req.headers.get('referer') || '').slice(0, 200),
        has_secret_field: typeof (body as { __secret?: unknown })?.__secret === 'string',
        secret_len: typeof (body as { __secret?: unknown })?.__secret === 'string' ? String((body as { __secret?: string }).__secret).length : 0,
      }, 'send_whatsapp refused a caller presenting no accepted internal credential. Identity recorded above so a ' +
         'repeated unauthorised caller can be named rather than counted. The secret VALUE is never logged - only its ' +
         'length, which distinguishes "sent nothing" from "sent something wrong" without disclosing either.');
      return J({ error:'forbidden' }, 403);
    }
    const acct = await sec('twilio_account_sid'); const ks = await sec('twilio_api_key_sid'); const kk = await sec('twilio_api_key_secret'); const from = await sec('twilio_wa_from');
    if (!acct || !ks || !kk || !from) { await logThrottled('not_configured', 60, 'error', {}, 'WHATSAPP NOT SENDING - missing twilio_account_sid / api_key_sid / api_key_secret / wa_from'); return J({ ok:false, error:'whatsapp_not_configured' }, 200); }
    const ready = ((await sec('wa_templates_ready'))||'false')==='true';
    const auth = btoa(ks + ':' + kk);
    let tmpl:any = {};
    try { tmpl = JSON.parse((await sec('wa_template_sids'))||'{}'); } catch(_){ tmpl = {}; }
    // DIRECT SEND. 4 Aug 2026: this accepted only a freeform Body, and freeform is the one thing
    // WhatsApp will not deliver business-initiated. Meta allows Body only inside the 24-hour window
    // the RECIPIENT opens by messaging us first; outside it Twilio returns 63016 and tells you to
    // use ContentSid. The only caller of this path is os_api's Control Mode challenge, sending a
    // code to a phone that has never messaged this number - so that code was never deliverable, and
    // nobody saw it fail because os_api reports delivery as a boolean and swallows the reason.
    // A template is accepted in and out of session, so it is tried first; a freeform body, when one
    // is supplied, is the fallback that still works in-session while a template awaits approval.
    if (body.to && (body.body || body.templateKey)) {
      const to = normPhone(String(body.to)); if (!to || to.length<8) { await logRun('error', { direct: true }, 'bad_phone on direct send: ' + String(body.to || '').slice(0, 40)); return J({ ok:false, error:'bad_phone' }, 200); }
      const tkey = String(body.templateKey || '');
      const tsid = tkey ? (tmpl?.[tkey]?.[String(body.lang || 'en')] || tmpl?.[tkey]?.en || null) : null;
      if (tkey && ready && tsid) {
        // 6 SEP 2026: the ledger answers first. A template Meta has not approved is not sent, not tried
        // and not an error — the caller gets the status and the reason; a freeform body, when supplied,
        // still goes out in-session below.
        const st = await templateStatus(auth, String(tsid), tkey, String(body.lang || 'en'));
        if (st.status === 'approved') {
          const t = await waSendTemplate(acct, ks, kk, from, to, String(tsid), (body.vars || {}) as Record<string,string>);
          if (t.ok) return J({ ok:true, sid:t.sid, via:'template' });
          await logRun('error', { direct: true, template: tkey }, 'direct WhatsApp TEMPLATE send rejected by Twilio: ' + String(t.error || '').slice(0, 200));
        } else if (!body.body) {
          return J({ ok:false, held:true, error:'template_not_approved:' + tkey, status: st.status, reason: st.reason, via:'template' }, 200);
        }
      } else if (tkey) {
        await logRun('error', { direct: true, template: tkey }, 'no approved template registered for "' + tkey + '" (wa_templates_ready=' + ready + ') - falling back to freeform, which only delivers in-session');
      }
      if (!body.body) return J({ ok:false, error: tkey ? ('no_template:' + tkey) : 'nothing_to_send', via:'template' }, 200);
      const res = await waSendBody(acct, ks, kk, from, to, String(body.body).slice(0,1500));
      if (!res.ok) await logRun('error', { direct: true }, 'direct WhatsApp send rejected by Twilio: ' + String(res.error || '').slice(0, 200));
      return J({ ok:res.ok, sid:res.sid, error:res.error, via:'freeform' });
    }
    // SENDER-REPUTATION GUARD (2 Aug 2026). This function is scheduled every 2 minutes and drains
    // 25 rows a run, so the ceiling was ~18,000 WhatsApp messages a day from a number that has
    // never sent a single one. WhatsApp does not ban on volume alone - it bans on QUALITY RATING,
    // which is driven by block-and-report rate - but a brand-new sender that suddenly emits
    // thousands of business-initiated messages to people who never opted in is the fastest way to
    // collect those blocks. Losing the number is not a setback we can buy our way out of: the
    // template approvals, the display name and the tier history go with it.
    // Two limits, both cheap and both at the only chokepoint that exists:
    //   * wa_daily_cap - business-initiated messages in a rolling 24h. Default 40. Meta's own
    //     starting tier for an unverified business is 250 unique conversations/24h and 1,000 once
    //     verified, so 40 is deliberately well inside it while we have no quality history at all.
    //     Raise it in app_secrets - roughly double it per week, and only while Twilio still reports
    //     quality "High". Do not jump straight to the tier limit.
    //   * wa_per_recipient_24h - messages to the SAME number in 24h. Default 1. One unwanted
    //     message is ignored; three in a day is what gets reported.
    // Over-cap rows are left 'queued', so nothing is lost - it just goes out tomorrow.
    const dayCap = Math.max(0, Number((await sec('wa_daily_cap')) ?? 40) || 40);
    const perRecip = Math.max(1, Number((await sec('wa_per_recipient_24h')) ?? 1) || 1);
    const since24 = new Date(Date.now() - 86400e3).toISOString();
    const { count: sentLast24 } = await admin.from('notifications').select('id', { count: 'exact', head: true })
      .eq('channel','whatsapp').eq('status','sent').gte('sent_at', since24);
    let budget = Math.max(0, dayCap - Number(sentLast24 || 0));
    if (budget <= 0) {
      await logThrottled('daily_cap', 180, 'ok', { cap: dayCap, sent_last_24h: Number(sentLast24 || 0) },
        'WhatsApp daily cap of ' + dayCap + ' reached. Queued messages are held, not dropped, and resume automatically. Raise app_secrets.wa_daily_cap only while Twilio reports sender quality High.');
      return J({ ok:true, sent:0, failed:0, skipped:0, requeued:0, unmapped:0, capped:true, cap:dayCap, sent_last_24h:Number(sentLast24||0) });
    }
    const { data: rows } = await admin.from('notifications').select('id,type,to_phone,subject,body,created_at,lang').eq('channel','whatsapp').eq('status','queued').not('to_phone','is',null).order('created_at',{ascending:true}).limit(25);
    const staleH = Number(await sec('wa_stale_hours') || 24);
    let sent=0, failed=0, skipped=0, requeued=0, unmapped=0, capped=0, heldFounder=0, heldStale=0; let lastErr=''; const unmappedTypes = new Set<string>();
    for (const n of (rows||[])) {
      const to = normPhone(String(n.to_phone||'')); if(!to){ await admin.from('notifications').update({status:'failed'}).eq('id',n.id); failed++; continue; }
      // A DEMO MOBILE IS CAPTURED, NEVER SENT (14 Sep 2026). The e2e harness (scripts/e2e/) addresses
      // every demo party at +971 50 000 00xx. Until today this loop checked only that a number was
      // well-formed, so a fixture number would have gone to Twilio - and a number that looks fake is
      // not guaranteed to be unassigned. The database captures these rows before they are ever
      // queued (zzzz_notifications_demo_capture); this is the second, independent lock at the only
      // place a WhatsApp message can leave.
      if (isDemoPhone(to)) { await admin.from('notifications').update({ status: 'suppressed', last_error: 'captured: reserved fixture mobile (+971 50 000 00xx) - recorded for the rehearsal, never handed to Twilio' }).eq('id', n.id); skipped++; continue; }
      // A STALE ALERT IS A LIE, NOT A BACKLOG. Nothing drained this queue between 7 Sep 2026 (when
      // pg_cron was removed and its wa_flush job with it) and 9 Sep, so a 'SCHEDULER DOWN' message
      // sat here for two days while the scheduler was in fact fine. Delivering it on the first tick
      // after the drainer is restored would page the founder about an outage that had already ended.
      // send_outbox has held stale email on the same reasoning since July; this channel never did.
      const ageH = (Date.now() - Date.parse(String(n.created_at))) / 3.6e6;
      if (ageH > staleH) {
        await admin.from('notifications').update({ status: 'held', last_error:
          ('held: this WhatsApp message was ' + Math.round(ageH) + 'h old when the queue was drained, past the ' + staleH + 'h staleness bar. An alert this old describes a situation that has probably changed, so it is retained and NOT delivered.').slice(0,500) }).eq('id', n.id);
        heldStale++; continue;
      }
      if (budget <= 0) { capped++; requeued++; continue; }
      const { count: toThisNumber } = await admin.from('notifications').select('id', { count: 'exact', head: true })
        .eq('channel','whatsapp').eq('status','sent').eq('to_phone', n.to_phone).gte('sent_at', since24);
      if (Number(toThisNumber || 0) >= perRecip) { capped++; requeued++; continue; }
      const key = tmplKey(String(n.type||''));
      // THE RECIPIENT'S REGISTERED LANGUAGE (notifications.lang, stamped from fn_registered_locale).
      // This always took .en, although wa_template_sids holds an Arabic SID for every customer and
      // supplier key - so an Arabic-registered customer got the English template.
      const wlang = n.lang === 'ar' ? 'ar' : 'en';
      const sid = (ready && key && tmpl[key]) ? (tmpl[key][wlang] || null) : null;
      let res;
      if (sid) {
        // 6 SEP 2026: the ledger decides before Twilio is asked to send anything.
        const st = await templateStatus(auth, sid, key!, wlang);
        if (st.status !== 'approved') {
          if (key === 'founder_alert') {
            // The email already carried this alert. Skipped WITH the reason, so the row explains itself and
            // the queue does not carry a founder row Meta has not yet made deliverable.
            await admin.from('notifications').update({ status:'skipped', last_error: ('WhatsApp template founder_alert is ' + st.status + (st.reason ? ' (' + st.reason + ')' : '') + ' at Meta; the email carried this alert').slice(0, 500) }).eq('id', n.id);
            heldFounder++; skipped++; continue;
          }
          // supplier / customer notice: held, never dropped — it goes the moment the template is approved
          skipped++; requeued++; lastErr = 'template ' + key + ' is ' + st.status + (st.reason ? ': ' + String(st.reason).slice(0, 120) : ''); continue;
        }
        res = await waSendTemplate(acct, ks, kk, from, to, sid, varsFor(key!, n));
      } else if (!ready) {
        // NOTE: the row is deliberately left 'queued' so it can go out once templates are approved.
        // That means it will be rescanned every run - tracked as 'requeued' so the backlog is visible.
        skipped++; requeued++; continue;
      } else if (key && !tmpl[key]) {
        // Mapped type whose template SID is not registered yet (or is awaiting Meta approval).
        // Left queued on purpose so it delivers the moment the SID lands - marking it 'skipped'
        // here would silently discard a compliance notice.
        skipped++; requeued++; continue;
      } else {
        // Genuinely unmapped message type: no template will ever match it, so keeping it queued
        // would grow the backlog forever. Marked skipped, but surfaced rather than silent.
        unmapped++; unmappedTypes.add(String(n.type||'(blank)'));
        await admin.from('notifications').update({ status:'skipped' }).eq('id', n.id); skipped++; continue;
      }
      // 3 SEP 2026: a template that Meta has not approved YET is not a failed message. Twilio rejects
      // the send while approval is pending; marking the row 'failed' dropped it for good (only
      // 'queued' rows are drained). Such rows stay queued and deliver the moment the template lands —
      // the same discipline as the mapped-but-unregistered branch above.
      const pendingTemplate = !res.ok && /approv|not (yet )?approved|template.*(pending|invalid|not found)|63016|63042/i.test(String(res.error || ''));
      if (pendingTemplate) { skipped++; requeued++; lastErr = 'template awaiting approval: ' + String(res.error || '').slice(0, 160); continue; }
      await admin.from('notifications').update({ status: res.ok?'sent':'failed', sent_at: res.ok?new Date().toISOString():null }).eq('id', n.id);
      if (res.ok) { sent++; budget--; } else { failed++; lastErr = String(res.error || '').slice(0, 200); }
    }
    if (capped) await logThrottled('rate_capped', 180, 'ok', { capped, cap: dayCap, per_recipient: perRecip },
      capped + ' WhatsApp message(s) held this run by the sender-reputation cap (daily ' + dayCap + ', per recipient ' + perRecip + ' / 24h). They stay queued and go out as budget frees up.');
    // A founder alert held for a pending template is a state, not a failure: recorded once per 3h at 'ok'.
    if (heldFounder) await logThrottled('founder_template_pending', 180, 'ok', { held_founder: heldFounder },
      heldFounder + ' founder WhatsApp alert(s) skipped with the reason: the founder_alert template is not approved at Meta yet (messaging_template). The email carried the alert; nothing was sent to Twilio.');
    // Templates not approved yet + a growing queue is the quiet failure worth surfacing.
    if (requeued) await logThrottled('templates_not_ready', 60, 'error', { requeued, pending: (rows||[]).length },
      requeued + ' WhatsApp notification(s) cannot be sent yet because the matching template is missing or still awaiting Meta approval. They stay queued and are rescanned every run, so this backlog will keep growing until the template SIDs are live.');
    if (unmapped) await logThrottled('unmapped_type', 60, 'error', { unmapped, types: [...unmappedTypes] },
      unmapped + ' WhatsApp notification(s) had a message type with no template mapping in tmplKey(), so they were dropped. Types: ' + [...unmappedTypes].join(', '));
    // A RUN THAT ONLY HELD IS STILL A RUN. Before 9 Sep 2026 this function had never executed at
    // all — agent_runs held zero rows for it, because pg_cron's wa_flush was deleted on 7 Sep and
    // nothing replaced it. When the drainer was restored, its first real action was to HOLD a
    // 35-hour-old alert, and neither branch below logged that: heldStale was in neither condition,
    // so the run that proved the fix worked would have left no trace. A seat whose only work is
    // refusing looks exactly like a seat that is down.
    if (failed) await logRun('error', { sent, failed, skipped, held_stale: heldStale, templates_ready: ready }, 'Twilio rejected ' + failed + ' WhatsApp message(s). Last error: ' + lastErr);
    else if (heldStale) await logRun('ok', { sent, failed, skipped, held_stale: heldStale, templates_ready: ready },
      heldStale + ' WhatsApp message(s) were held as stale: older than ' + staleH + 'h when the queue was drained. They are retained, not sent — an alert that old describes a situation that has probably changed.');
    else if (sent || (skipped && !requeued)) await logRun('ok', { sent, failed, skipped, templates_ready: ready }, '');
    return J({ ok:true, sent, failed, skipped, requeued, unmapped, capped, held_founder: heldFounder, held_stale: heldStale, cap:dayCap, per_recipient_24h:perRecip, templates_ready:ready });
  } catch (e) { const m = String((e as Error)?.message||e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
}));
