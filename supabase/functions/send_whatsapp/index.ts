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
// v7 (18 Sep 2026): a founder alert never stalls on this channel again, and the run log stops
//     blaming Meta for what the reputation cap did. Three founder_alert rows sat queued from
//     17 Sep 18:31Z under {"signal":"templates_not_ready"}, which read as a missing template —
//     but Twilio's Content API says quotesdone_founder_alert_en (HXcb8792bf…) is APPROVED and
//     wa_templates_ready='true'. The real cause was wa_per_recipient_24h=1: every founder alert
//     goes to ONE number, so the 2nd and 3rd of any 24 hours were refused by the per-recipient
//     cap, whose branch does `capped++; requeued++` — and `requeued` is what arms the
//     templates_not_ready signal. Left alone, such a row is requeued until it passes the
//     staleness bar and is silently 'held' (five founder alerts ended that way, 15-16 Sep).
//     Three changes: (a) NEITHER reputation cap applies to the founder — not the per-recipient
//     one and not the daily one, and the run no longer stops at the daily cap while a founder row
//     is queued; the caps exist to stop strangers blocking-and-reporting a new sender, and he is
//     not a stranger; (b) every path that still cannot deliver a FOUNDER row calls
//     fn_wa_founder_alert_fallback, which confirms or queues the email (carrying the row's own
//     kind so the a10 founder-mail trigger admits it) and then marks the row skipped WITH its
//     reason, so it leaves the queue honestly instead of ageing into a silent 'held'; (c) `capped`
//     is no longer counted into `requeued`, so templates_not_ready fires only for a real template.
//     The one exception on purpose: an UNREADABLE template status ('twilio http NNN') requeues
//     rather than retiring the row — not being able to ask Twilio is not Meta refusing.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { observe } from '../_shared/observe.ts';
import { FIXTURE_CAPTURE_NOTE, isDemoPhone } from '../_shared/demo_identity.ts';
// v8 (22 Sep 2026): every send names where Twilio reports delivered / read / failed (supabase/functions/
// wa_status). 'sent' with a SID now means only "Twilio accepted it"; whether it ARRIVED is the
// provider_status that callback (or its 30-minute backstop poll) writes onto the row.
import { statusCallbackUrl } from '../_shared/twilio_status.ts';
import { portfolioGate } from './portfolio_gate.ts';
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

// THE FOUNDER IS NEVER LEFT IN THE QUEUE (18 Sep 2026). WhatsApp can stop delivering for reasons
// that have nothing to do with this code — a template rejected or paused at Meta, a quality
// throttle, a hard Twilio rejection — and a CRITICAL alert must not depend on one channel that can
// stall silently. Every path below that cannot send a founder-addressed row calls this instead of
// requeueing it. fn_wa_founder_alert_fallback confirms the email twin or queues one carrying the
// row's own `kind` (so a10_notifications_founder_mail_policy admits it rather than dropping it),
// then marks THIS row 'skipped' with the reason. It returns null for a row that is not the
// founder's, so the caller falls through to the behaviour it always had.
type WaRow = { id: number; type?: string|null; to_phone?: string|null; to_role?: string|null;
               subject?: string|null; body?: string|null; created_at?: string|null; lang?: string|null; lead_id?: number|null };
// isFounderRow decides the CAP EXEMPTIONS only. Who the founder is for the fallback is decided in
// one place — fn_wa_founder_alert_fallback, which uses a10's own test (to_role, or to_phone equal
// to admin_mfa_phone) — so this function does not pre-filter and the two cannot disagree about a
// row. fn_notify_founder always stamps to_role='founder', so the two agree for every writer today.
const isFounderRow = (n: WaRow) => ['founder','admin','owner'].includes(String(n.to_role || ''));
async function founderFallback(n: WaRow, reason: string): Promise<string|null> {
  try {
    const { data, error } = await admin.rpc('fn_wa_founder_alert_fallback',
      { p_notification_id: n.id, p_reason: String(reason).slice(0, 300) });
    if (error) {
      // The fallback itself failing is the one thing that must never be quiet: the row stays queued
      // so the next tick retries it, and the failure is logged rather than swallowed.
      await logThrottled('founder_fallback_broken', 30, 'error', { notification: n.id }, 'founder WhatsApp fallback FAILED (the alert is still queued): '
        + String(error.message || error).slice(0, 250));
      return null;
    }
    const out = (data as { ok?: boolean; outcome?: string } | null);
    // 'already_handled' means an overlapping run claimed the row first: it is terminal and must NOT
    // be written again by this caller, so it counts as handled even though ok is false.
    if (out?.ok || out?.outcome === 'already_handled') return String(out.outcome);
    return null;
  } catch (e) {
    await logThrottled('founder_fallback_broken', 30, 'error', { notification: n.id }, 'founder WhatsApp fallback threw (the alert is still queued): '
      + String((e as Error)?.message || e).slice(0, 250));
    return null;
  }
}

function normPhone(p: string){ let s=String(p||'').trim().replace(/[^0-9+]/g,''); if(!s) return ''; if(s.startsWith('00')) s='+'+s.slice(2); if(!s.startsWith('+')){ if(s.startsWith('0')) s='+971'+s.slice(1); else s='+'+s; } return s; }
const SUP_URL='https://quotesdone.com/suppliers';
const APP_URL='https://quotesdone.com/me';
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
  // 22 Sep 2026: licence_renewal is fn_licence_expiry_sweep's T-30/14/7 ask; its WhatsApp twin is fanned
  // out from the email to the confirmed number and rides the same approved document-expiry template.
  if(['supplier_doc_expiry','doc_final_notice','doc_suspended','doc_expiry','licence_renewal'].includes(t)) return 'supplier_doc_expiry';
  // 14 Sep 2026: the sales engineer's notices about a supplier's own quotes and account (a quote on
  // hold, the regenerated quote to approve, its release, the collaboration warning, the matching hold
  // and its lifting). Transactional, UTILITY category. Until wa_template_setup registers the SID the
  // rows stay queued (mapped-but-unregistered), never dropped; the email twin goes meanwhile.
  if(['quote_spec_hold','quote_spec_regenerated','quote_spec_released','supplier_collaboration_warning','supplier_matching_hold','supplier_matching_hold_lifted'].includes(t)) return 'supplier_account_notice';
  // 23 Sep 2026 (instruction 858): the 3-working-day portfolio reminder is a notice about the supplier's
  // own account too. {{1}} is its subject, {{2}} the portal, which opens on the Services tab.
  if(t==='supplier_portfolio_incomplete') return 'supplier_account_notice';
  // 6 SEP 2026: the founder's own alert. fn_notify_founder queues it (allowed kind, severe level) and
  // wa_flush drains it here. "QuotesDone alert: {{1}}. Details: {{2}}. Open the OS to act." — registered
  // by wa_template_setup under this key.
  if(t==='founder_alert') return 'founder_alert';
  // 23 Sep 2026: a reasoned answer to the customer's own question, due after their 24-hour window closed
  // (_shared/reasoned_delivery.ts). Held queued until the support_reply template is approved.
  if(t==='support_reply') return 'support_reply';
  return null;
}
// 18 SEP 2026: the founder authorised the submission and supplier_account_notice now HAS a template
// (wa_template_setup catalogue, EN + AR, UTILITY). This branch is therefore reached only while Meta
// is still reviewing it, or if its SID were ever unregistered again — so the note no longer says a
// template will never exist, it says the row is waiting for one. The email twin remains the record.
const AWAITING_TEMPLATE_NOTE = 'awaiting template: the supplier_account_notice WhatsApp template is submitted but not yet registered as an approved SID, so this row stays queued and goes the moment it lands. The email twin carried this notice.';
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
  // support_reply: {{1}} their question (the subject), {{2}} the answer (the body), each one line.
  if (key==='support_reply') return {'1': waVar(shortSummary(n.subject||''), 120), '2': waVar(String(n.body||''), 700)};
  const summary = shortSummary(n.subject||n.body||'');
  const url = key==='supplier_new_inquiry' ? SUP_URL
            : (key==='supplier_doc_expiry' || key==='supplier_quote_accepted' || key==='supplier_account_notice') ? PORTAL_URL
            : APP_URL;
  return {'1':summary,'2':url};
}
// THE SEND, AND WHAT IT MEANS WHEN IT DOES NOT COME BACK (22 Sep 2026, it_engineer, CONN-03).
// Both of these used a bare `await fetch` with no deadline and no catch. A timeout or a dropped
// connection therefore threw out of the whole drain loop, the row stayed 'queued', and the next run
// sent it AGAIN — after Twilio had already accepted it. `threw` is the third outcome the caller needs:
// not accepted, not rejected, UNKNOWN, and a message that may already have gone is never re-sent.
//
// NO IDEMPOTENCY KEY, AND THAT IS NOT PARITY WITH EMAIL — SAID PLAINLY (22 Sep 2026, after independent
// review asked for it). send_outbox sends Resend an `Idempotency-Key`, which Resend honours for 24
// hours, so a retried email row cannot become a second email. Twilio's Messages.json offers no
// equivalent, so nothing here can make a repeated POST a no-op at the provider. What closes the gap
// instead, and exactly how far:
//   * the claim means two CONCURRENT senders cannot hold the same row at all;
//   * this request is bounded at 15 s and the claim expires at 5 minutes, so a second sender can never
//     pick up a row the first is still sending;
//   * a request that does not return is recorded as sent-unconfirmed and never drained again.
//   * RESIDUAL, not closed: if the isolate DIES between Twilio accepting the message and the row being
//     updated, no catch runs, the row stays 'sending', and the claim requeues it after 5 minutes — one
//     duplicate WhatsApp message. Narrow, real, and unfixable from this side while Twilio has no key.
type WaSend = { ok: boolean; sid: string | null; error: string | null; threw?: boolean };
async function twilioSend(acct:string, auth:string, form:URLSearchParams): Promise<WaSend> {
  try {
    const r = await timedFetch(`https://api.twilio.com/2010-04-01/Accounts/${acct}/Messages.json`,
      { method:'POST', headers:{ 'Authorization':'Basic '+auth, 'Content-Type':'application/x-www-form-urlencoded' }, body: form.toString() }, 15_000);
    const jd = await r.json().catch(()=>({}));
    return { ok:r.ok, sid: jd?.sid||null, error: r.ok?null:(jd?.message||('http '+r.status)) };
  } catch (e) {
    return { ok:false, sid:null, threw:true, error: 'the request to Twilio did not return: ' + String((e as Error)?.message || e).slice(0,160) };
  }
}
function waSendBody(acct:string, ks:string, kk:string, from:string, to:string, body:string){
  return twilioSend(acct, btoa(ks + ':' + kk),
    new URLSearchParams({ To: 'whatsapp:'+to, From: 'whatsapp:'+from, Body: body, StatusCallback: statusCallbackUrl() }));
}
function waSendTemplate(acct:string, ks:string, kk:string, from:string, to:string, contentSid:string, vars:Record<string,string>){
  return twilioSend(acct, btoa(ks + ':' + kk),
    new URLSearchParams({ To: 'whatsapp:'+to, From: 'whatsapp:'+from, ContentSid: contentSid, ContentVariables: JSON.stringify(vars), StatusCallback: statusCallbackUrl() }));
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
  // A CLAIM THAT WAS NOT RESOLVED IS GIVEN BACK IN A `finally` (22 Sep 2026, CONN-03; the finally,
  // rather than a block after the loop, after independent review found send_outbox's equivalent
  // jumped over by two early returns). Most branches below deliberately leave a row for the next run —
  // capped by the reputation budget, waiting on a template, requeued because Twilio could not be
  // asked. Those rows were 'queued' before the claim existed and must be 'queued' again when this run
  // ends, or they wait out the claim's 5-minute expiry for nothing. Rows this run DID resolve are no
  // longer 'sending', so the status filter makes the release exact rather than a blanket reset.
  const claimedIds: number[] = [];
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
    // THE CAPS ARE NOT FOR THE FOUNDER (18 Sep 2026). Both the daily cap and the per-recipient cap
    // exist to stop a brand-new sender emitting business-initiated messages to people who never
    // opted in, because their block-and-report is what costs the number. The founder asked for this
    // channel himself and will not report his own company, and his alerts are the one traffic that
    // must not wait for tomorrow's budget. So the run does not stop while a founder row is queued:
    // it drains the founder's rows and leaves everyone else's for the budget to free up.
    const { count: founderQueued } = await admin.from('notifications').select('id', { count: 'exact', head: true })
      .eq('channel','whatsapp').eq('status','queued').in('to_role', ['founder','admin','owner']);
    const founderWaiting = Number(founderQueued || 0) > 0;
    if (budget <= 0 && !founderWaiting) {
      await logThrottled('daily_cap', 180, 'ok', { cap: dayCap, sent_last_24h: Number(sentLast24 || 0) },
        'WhatsApp daily cap of ' + dayCap + ' reached. Queued messages are held, not dropped, and resume automatically. Raise app_secrets.wa_daily_cap only while Twilio reports sender quality High.');
      return J({ ok:true, sent:0, failed:0, skipped:0, requeued:0, unmapped:0, capped:true, cap:dayCap, sent_last_24h:Number(sentLast24||0) });
    }
    // CLAIMED, NOT READ (22 Sep 2026, it_engineer, CONN-03). This was a plain SELECT of status='queued',
    // and this function runs every 2 minutes AND from the resilience tick, so two overlapping runs both
    // saw the same row and both asked Twilio to send it. fn_notifications_claim takes the rows with
    // FOR UPDATE SKIP LOCKED and moves them to 'sending' in one statement; a claim older than 5 minutes
    // is requeued, so a run that dies costs 5 minutes and not the message. The channel, the
    // not-null-handset filter, the created_at order and the limit are all inside the claim.
    const { data: rows, error: claimErr } = await admin.rpc('fn_notifications_claim', { p_channel: 'whatsapp', p_limit: 25 });
    if (claimErr) { await logThrottled('claim_failed', 10, 'error', {}, 'could not claim the WhatsApp queue: ' + claimErr.message); return J({ ok:false, error: claimErr.message }); }
    for (const n of (rows || []) as WaRow[]) claimedIds.push(n.id);
    const staleH = Number(await sec('wa_stale_hours') || 24);
    let sent=0, failed=0, skipped=0, requeued=0, unmapped=0, capped=0, heldFounder=0, heldStale=0, fellBack=0, unconfirmed=0; let lastErr=''; const unmappedTypes = new Set<string>();
    const fallbackOutcomes = new Set<string>();
    // Every founder path funnels through here so the counter and the log agree on what happened.
    const tryFallback = async (n: WaRow, reason: string) => {
      const out = await founderFallback(n, reason);
      if (out) { fellBack++; skipped++; fallbackOutcomes.add(out); return true; }
      return false;
    };
    for (const n of (rows||[])) {
      const to = normPhone(String(n.to_phone||'')); if(!to){ await admin.from('notifications').update({status:'failed'}).eq('id',n.id); failed++; continue; }
      // A DEMO MOBILE IS CAPTURED, NEVER SENT (14 Sep 2026). The e2e harness (scripts/e2e/) addresses
      // every demo party at +971 50 000 00xx. Until today this loop checked only that a number was
      // well-formed, so a fixture number would have gone to Twilio - and a number that looks fake is
      // not guaranteed to be unassigned. The database captures these rows before they are ever
      // queued (zzzz_notifications_demo_capture); this is the second, independent lock at the only
      // place a WhatsApp message can leave.
      if (isDemoPhone(to)) { await admin.from('notifications').update({ status: 'suppressed', last_error: FIXTURE_CAPTURE_NOTE }).eq('id', n.id); skipped++; continue; }
      // A STALE ALERT IS A LIE, NOT A BACKLOG. Nothing drained this queue between 7 Sep 2026 (when
      // pg_cron was removed and its wa_flush job with it) and 9 Sep, so a 'SCHEDULER DOWN' message
      // sat here for two days while the scheduler was in fact fine. Delivering it on the first tick
      // after the drainer is restored would page the founder about an outage that had already ended.
      // send_outbox has held stale email on the same reasoning since July; this channel never did.
      const ageH = (Date.now() - Date.parse(String(n.created_at))) / 3.6e6;
      if (ageH > staleH) {
        // A stale FOUNDER alert is still checked for its email twin before it is shelved: holding
        // it is a judgement about WhatsApp timeliness, not a decision that he need not be told.
        if (await tryFallback(n, 'stale: ' + Math.round(ageH) + 'h old, past the ' + staleH + 'h WhatsApp staleness bar')) { heldStale++; continue; }
        await admin.from('notifications').update({ status: 'held', last_error:
          ('held: this WhatsApp message was ' + Math.round(ageH) + 'h old when the queue was drained, past the ' + staleH + 'h staleness bar. An alert this old describes a situation that has probably changed, so it is retained and NOT delivered.').slice(0,500) }).eq('id', n.id);
        heldStale++; continue;
      }
      // 23 Sep 2026 (instruction 858, review of #869): after the staleness bar (so a held row still expires at 24h), the portfolio reminder is re-read when its WhatsApp
      // copy actually leaves, not only when the email was written. A supplier who completed his portfolio
      // after the email must not get a WhatsApp telling him he is still incomplete. FAILS CLOSED
      // (portfolio_gate.ts): an error or a timeout leaves the row queued with its reason, never sends it.
      if (String(n.type || '') === 'supplier_portfolio_incomplete') {
        const g = await portfolioGate((fn, args, signal) => (signal ? admin.rpc(fn, args).abortSignal(signal) : admin.rpc(fn, args)), n.lead_id);
        if (g.action === 'cancel') { await admin.from('notifications').update({ status: 'cancelled', last_error: g.reason }).eq('id', n.id); skipped++; continue; }
        // held like a row waiting on its template: the claim lapses and the next run re-checks it
        if (g.action === 'hold') { await admin.from('notifications').update({ last_error: g.reason }).eq('id', n.id); skipped++; requeued++; lastErr = g.reason; continue; }
      }
      // A capped row is NOT a requeue caused by a template. Counting it as one is what made three
      // founder alerts read as "templates_not_ready" for a day while the template was approved.
      if (budget <= 0 && !isFounderRow(n)) { capped++; continue; }
      // THE PER-RECIPIENT CAP IS NOT FOR THE FOUNDER. It exists so a stranger who never opted in
      // does not get three business-initiated messages in a day and report the sender; the founder
      // asked for this channel himself and will not report his own company. Applying it to him
      // meant only the FIRST alert of any 24 hours ever reached him, and the rest aged out.
      if (!isFounderRow(n)) {
        const { count: toThisNumber } = await admin.from('notifications').select('id', { count: 'exact', head: true })
          .eq('channel','whatsapp').eq('status','sent').eq('to_phone', n.to_phone).gte('sent_at', since24);
        if (Number(toThisNumber || 0) >= perRecip) { capped++; continue; }
      }
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
          // "We could not ASK Twilio" is not "Meta has not approved it". templateStatus returns the
          // last cached status with reason 'twilio http NNN' when the Content API is unreachable,
          // and a cached status can be any age. Retiring a founder row terminally on that would let
          // a transient Twilio outage decide the alert is undeliverable, so it is requeued instead
          // and resolved by the next run that can reach Twilio.
          if (String(st.reason || '').startsWith('twilio http')) {
            skipped++; requeued++; lastErr = 'could not read template status from Twilio: ' + st.reason; continue;
          }
          if (key === 'founder_alert' || isFounderRow(n)) {
            // 18 Sep 2026: this used to ASSERT that "the email carried this alert" without ever
            // checking. The fallback checks, queues the email if it did not, and only then marks
            // the row skipped with its reason.
            const why = 'WhatsApp template ' + key + ' is ' + st.status + (st.reason ? ' (' + String(st.reason).slice(0, 120) + ')' : '') + ' at Meta';
            if (await tryFallback(n, why)) { heldFounder++; continue; }
            await admin.from('notifications').update({ status:'skipped', last_error: (why + '; no founder fallback applied').slice(0, 500) }).eq('id', n.id);
            heldFounder++; skipped++; continue;
          }
          // supplier / customer notice: held, never dropped — it goes the moment the template is approved
          skipped++; requeued++; lastErr = 'template ' + key + ' is ' + st.status + (st.reason ? ': ' + String(st.reason).slice(0, 120) : ''); continue;
        }
        res = await waSendTemplate(acct, ks, kk, from, to, sid, varsFor(key!, n));
      } else if (!ready) {
        // NOTE: the row is deliberately left 'queued' so it can go out once templates are approved.
        // That means it will be rescanned every run - tracked as 'requeued' so the backlog is visible.
        // A founder row does not wait: it goes by email now.
        if (await tryFallback(n, 'wa_templates_ready is false')) continue;
        skipped++; requeued++; continue;
      } else if (key && !tmpl[key]) {
        // Mapped type whose template SID is not registered yet (or is awaiting Meta approval).
        // Left queued on purpose so it delivers the moment the SID lands - marking it 'skipped'
        // here would silently discard a compliance notice.
        // 15 SEP 2026: supplier_account_notice has NO template registered and no approved UTILITY
        // template fits it (the approved ones are about a new inquiry, a quote, a reveal or document
        // expiry). Registering one needs the founder's own Meta submission, so it is not done from
        // here. fn_supplier_notice queues the email twin first, so the notice goes by email; this row
        // says why it is waiting instead of sitting silently in the queue. Stamped once.
        if (key === 'supplier_account_notice') await admin.from('notifications').update({ last_error: AWAITING_TEMPLATE_NOTE }).eq('id', n.id).is('last_error', null);
        if (await tryFallback(n, 'no WhatsApp template SID registered for "' + key + '"')) continue;
        skipped++; requeued++; continue;
      } else {
        // Genuinely unmapped message type: no template will ever match it, so keeping it queued
        // would grow the backlog forever. Marked skipped, but surfaced rather than silent.
        unmapped++; unmappedTypes.add(String(n.type||'(blank)'));
        if (await tryFallback(n, 'message type "' + String(n.type||'(blank)') + '" has no WhatsApp template mapping')) continue;
        await admin.from('notifications').update({ status:'skipped', last_error: ('no WhatsApp template mapping for type "' + String(n.type||'(blank)') + '"').slice(0,500) }).eq('id', n.id); skipped++; continue;
      }
      // THE REQUEST LEFT AND THE ANSWER DID NOT (22 Sep 2026, CONN-03). Twilio may have accepted it.
      // The row is marked 'sent' with provider_message_id NULL, which is this estate's existing way of
      // saying unconfirmed (fn_customer_support_delivery_watch returns 'sent_unconfirmed' for exactly
      // that shape and fn_originator_checks_delivery refuses to re-send on it), with the reason stored.
      // Anything else here re-sends a message that may already have arrived.
      if (res.threw) {
        await admin.from('notifications').update({ status: 'sent', sent_at: new Date().toISOString(), provider_message_id: null,
          last_error: (String(res.error || '') + '; it may or may not have been accepted, so this row is sent-unconfirmed and will NOT be sent again').slice(0, 500) }).eq('id', n.id);
        unconfirmed++; lastErr = String(res.error || '').slice(0, 200); continue;
      }
      // 3 SEP 2026: a template that Meta has not approved YET is not a failed message. Twilio rejects
      // the send while approval is pending; marking the row 'failed' dropped it for good (only
      // 'queued' rows are drained). Such rows stay queued and deliver the moment the template lands —
      // the same discipline as the mapped-but-unregistered branch above.
      const pendingTemplate = !res.ok && /approv|not (yet )?approved|template.*(pending|invalid|not found)|63016|63042/i.test(String(res.error || ''));
      if (pendingTemplate) {
        lastErr = 'template awaiting approval: ' + String(res.error || '').slice(0, 160);
        if (await tryFallback(n, lastErr)) continue;
        skipped++; requeued++; continue;
      }
      if (!res.ok) {
        // Twilio rejected it outright. For anyone else that is a failed row; for the founder it is
        // the exact case the fallback exists for — the alert still has to reach him.
        lastErr = String(res.error || '').slice(0, 200);
        // tryFallback already counted this row once (fellBack + skipped) and the database already
        // moved it to 'skipped'. Counting it as `failed` as well would put one row in two buckets
        // and raise "Twilio rejected N messages" for a row the email fallback resolved — the same
        // class of lying counter this version exists to remove.
        if (await tryFallback(n, 'Twilio rejected the WhatsApp send: ' + lastErr)) continue;
      }
      // THE SID IS THE PROOF (21 Sep 2026). Measured: 24 of 24 WhatsApp rows marked 'sent' since 18 Sep
      // carried provider_message_id NULL, so every founder alert's WhatsApp twin came back to the
      // delivery watch as 'sent_unconfirmed', was escalated to the CEO as "did not arrive", and reached
      // the founder as "The CEO has not answered an IT report" — four emails in four days about
      // messages Twilio had accepted. Twilio returns the message SID on every accepted send; it is
      // stored where the outbox stores Resend's id, so a WhatsApp send is confirmed or failed, never
      // unconfirmed.
      await admin.from('notifications').update({ status: res.ok?'sent':'failed', sent_at: res.ok?new Date().toISOString():null,
        provider_message_id: res.ok ? (res.sid || null) : null,
        last_error: res.ok?null:String(res.error||'').slice(0,500) }).eq('id', n.id);
      if (res.ok) { sent++; budget--; } else { failed++; lastErr = String(res.error || '').slice(0, 200); }
    }
    if (capped) await logThrottled('rate_capped', 180, 'ok', { capped, cap: dayCap, per_recipient: perRecip },
      capped + ' WhatsApp message(s) held this run by the sender-reputation cap (daily ' + dayCap + ', per recipient ' + perRecip + ' / 24h). They stay queued and go out as budget frees up.');
    // A founder alert that WhatsApp could not carry is only acceptable because the email did. Say so
    // with the outcome the fallback actually measured, never as an assumption.
    // Logged at 'error', not 'ok'. The compensating control working is not the same as the channel
    // working: once these rows are marked terminal they vanish from the queue, so if this line were
    // 'ok' a sustained WhatsApp outage would leave nothing above the severity filter at all.
    if (fellBack) await logThrottled('founder_fallback_to_email', 60, 'error', { fell_back: fellBack, outcomes: [...fallbackOutcomes] },
      fellBack + ' founder WhatsApp alert(s) could not be sent and were taken off the queue with their reason. ' +
      'Email outcome: ' + [...fallbackOutcomes].join(', ') + '. "emailed" means this run queued the email; ' +
      '"email_twin_already_sent" means fn_notify_founder\'s email already carried it; ' +
      '"blocked_by_founder_mail_policy" means founder_mail_policy routes that kind to its owning seat instead ' +
      '(recorded in founder_alerts, NOT delivered to him).');
    // A founder alert held for a pending template is a state, not a failure: recorded once per 3h at 'ok'.
    if (heldFounder) await logThrottled('founder_template_pending', 180, 'ok', { held_founder: heldFounder },
      heldFounder + ' founder WhatsApp alert(s) skipped with the reason: the founder_alert template is not approved at Meta yet (messaging_template). The email carried the alert; nothing was sent to Twilio.');
    // Templates not approved yet + a growing queue is the quiet failure worth surfacing. `requeued`
    // now counts ONLY rows a template blocked: a row held by the daily or per-recipient cap is
    // counted in `capped` alone, so this signal can no longer accuse Meta of the cap's work.
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
    return J({ ok:true, sent, failed, skipped, requeued, unmapped, capped, unconfirmed, fell_back: fellBack,
               fallback_outcomes: [...fallbackOutcomes], held_founder: heldFounder, held_stale: heldStale,
               cap:dayCap, per_recipient_24h:perRecip, templates_ready:ready });
  } catch (e) { const m = String((e as Error)?.message||e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
  finally {
    if (claimedIds.length) {
      try { await admin.from('notifications').update({ status: 'queued', claimed_at: null }).in('id', claimedIds).eq('status', 'sending'); }
      catch (_e) { /* the 5-minute claim expiry in fn_notifications_claim is the backstop */ }
    }
  }
}));
