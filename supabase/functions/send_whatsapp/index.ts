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
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
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
  // Document compliance: final notice before suspension, and the suspension itself. Both are
  // transactional notices about the supplier's own account, which is why the Twilio template is
  // registered under the UTILITY category rather than MARKETING.
  if(['supplier_doc_expiry','doc_final_notice','doc_suspended','doc_expiry'].includes(t)) return 'supplier_doc_expiry';
  return null;
}
function shortSummary(s:string){ let x=String(s||'').replace(/\s+/g,' ').trim(); x=x.replace(/^(QuotesDone[:\-\s]*)/i,''); return x.slice(0,90)||'your request'; }
function varsFor(key:string, summary:string){
  const url = key==='supplier_new_inquiry' ? SUP_URL
            : key==='supplier_doc_expiry' ? PORTAL_URL
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
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    const __exp = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'send_whatsapp');
    if (!__auth.ok) { await logThrottled('forbidden', 60, 'error', {}, 'send_whatsapp called without the inbound secret'); return J({ error:'forbidden' }, 403); }
    const acct = await sec('twilio_account_sid'); const ks = await sec('twilio_api_key_sid'); const kk = await sec('twilio_api_key_secret'); const from = await sec('twilio_wa_from');
    if (!acct || !ks || !kk || !from) { await logThrottled('not_configured', 60, 'error', {}, 'WHATSAPP NOT SENDING - missing twilio_account_sid / api_key_sid / api_key_secret / wa_from'); return J({ ok:false, error:'whatsapp_not_configured' }, 200); }
    const ready = ((await sec('wa_templates_ready'))||'false')==='true';
    let tmpl:any = {};
    try { tmpl = JSON.parse((await sec('wa_template_sids'))||'{}'); } catch(_){ tmpl = {}; }
    if (body.to && body.body) {
      const to = normPhone(String(body.to)); if (!to || to.length<8) { await logRun('error', { direct: true }, 'bad_phone on direct send: ' + String(body.to || '').slice(0, 40)); return J({ ok:false, error:'bad_phone' }, 200); }
      const res = await waSendBody(acct, ks, kk, from, to, String(body.body).slice(0,1500));
      if (!res.ok) await logRun('error', { direct: true }, 'direct WhatsApp send rejected by Twilio: ' + String(res.error || '').slice(0, 200));
      return J({ ok:res.ok, sid:res.sid, error:res.error });
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
    const { data: rows } = await admin.from('notifications').select('id,type,to_phone,subject,body').eq('channel','whatsapp').eq('status','queued').not('to_phone','is',null).order('created_at',{ascending:true}).limit(25);
    let sent=0, failed=0, skipped=0, requeued=0, unmapped=0, capped=0; let lastErr=''; const unmappedTypes = new Set<string>();
    for (const n of (rows||[])) {
      const to = normPhone(String(n.to_phone||'')); if(!to){ await admin.from('notifications').update({status:'failed'}).eq('id',n.id); failed++; continue; }
      if (budget <= 0) { capped++; requeued++; continue; }
      const { count: toThisNumber } = await admin.from('notifications').select('id', { count: 'exact', head: true })
        .eq('channel','whatsapp').eq('status','sent').eq('to_phone', n.to_phone).gte('sent_at', since24);
      if (Number(toThisNumber || 0) >= perRecip) { capped++; requeued++; continue; }
      const key = tmplKey(String(n.type||''));
      const sid = (ready && key && tmpl[key]) ? (tmpl[key].en||null) : null;
      let res;
      if (sid) {
        res = await waSendTemplate(acct, ks, kk, from, to, sid, varsFor(key!, shortSummary(n.subject||n.body||'')));
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
      await admin.from('notifications').update({ status: res.ok?'sent':'failed', sent_at: res.ok?new Date().toISOString():null }).eq('id', n.id);
      if (res.ok) { sent++; budget--; } else { failed++; lastErr = String(res.error || '').slice(0, 200); }
    }
    if (capped) await logThrottled('rate_capped', 180, 'ok', { capped, cap: dayCap, per_recipient: perRecip },
      capped + ' WhatsApp message(s) held this run by the sender-reputation cap (daily ' + dayCap + ', per recipient ' + perRecip + ' / 24h). They stay queued and go out as budget frees up.');
    // Templates not approved yet + a growing queue is the quiet failure worth surfacing.
    if (requeued) await logThrottled('templates_not_ready', 60, 'error', { requeued, pending: (rows||[]).length },
      requeued + ' WhatsApp notification(s) cannot be sent yet because the matching template is missing or still awaiting Meta approval. They stay queued and are rescanned every run, so this backlog will keep growing until the template SIDs are live.');
    if (unmapped) await logThrottled('unmapped_type', 60, 'error', { unmapped, types: [...unmappedTypes] },
      unmapped + ' WhatsApp notification(s) had a message type with no template mapping in tmplKey(), so they were dropped. Types: ' + [...unmappedTypes].join(', '));
    if (failed) await logRun('error', { sent, failed, skipped, templates_ready: ready }, 'Twilio rejected ' + failed + ' WhatsApp message(s). Last error: ' + lastErr);
    else if (sent || (skipped && !requeued)) await logRun('ok', { sent, failed, skipped, templates_ready: ready }, '');
    return J({ ok:true, sent, failed, skipped, requeued, unmapped, capped, cap:dayCap, per_recipient_24h:perRecip, templates_ready:ready });
  } catch (e) { const m = String((e as Error)?.message||e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
});
