// send_whatsapp - sends WhatsApp via Twilio. Single ({to, body}) or flush (drains queued channel='whatsapp' notifications).
// Business-initiated messages use APPROVED templates (ContentSid+ContentVariables) once wa_templates_ready='true'.
// Secret-guarded (inbound_secret). Auth via twilio API key. Sender from twilio_wa_from (digits, no prefix).
// v4: agent_runs instrumentation. Runs every 2 minutes and always returned 200, so three failure modes were
//     invisible: (a) whatsapp_not_configured, (b) wa_templates_ready=false, where queued rows are counted as
//     'skipped' but NOT updated, so they requeue forever and the backlog grows unbounded, (c) Twilio rejections.
//     Recurring states are throttled to one row per hour so the 2-minute cadence cannot bury the signal.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined) || undefined; }

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
function tmplKey(type:string):string|null{
  const t=(type||'').toLowerCase();
  if(['new_inquiry','inquiry_matched','supplier_new_inquiry'].includes(t)) return 'supplier_new_inquiry';
  if(['new_quote','quote_received','quote_submitted','quote_ready','quote_available'].includes(t)) return 'customer_new_quote';
  if(['reveal_receipt','reveal','supplier_revealed','supplier_unlocked','reveal_unlocked'].includes(t)) return 'customer_supplier_unlocked';
  return null;
}
function shortSummary(s:string){ let x=String(s||'').replace(/\s+/g,' ').trim(); x=x.replace(/^(QuotesDone[:\-\s]*)/i,''); return x.slice(0,90)||'your request'; }
function varsFor(key:string, summary:string){
  const url = key==='supplier_new_inquiry' ? SUP_URL : APP_URL;
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
    if (body.__secret !== (await sec('inbound_secret'))) { await logThrottled('forbidden', 60, 'error', {}, 'send_whatsapp called without the inbound secret'); return J({ error:'forbidden' }, 403); }
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
    const { data: rows } = await admin.from('notifications').select('id,type,to_phone,subject,body').eq('channel','whatsapp').eq('status','queued').not('to_phone','is',null).order('created_at',{ascending:true}).limit(25);
    let sent=0, failed=0, skipped=0, requeued=0; let lastErr='';
    for (const n of (rows||[])) {
      const to = normPhone(String(n.to_phone||'')); if(!to){ await admin.from('notifications').update({status:'failed'}).eq('id',n.id); failed++; continue; }
      const key = tmplKey(String(n.type||''));
      const sid = (ready && key && tmpl[key]) ? (tmpl[key].en||null) : null;
      let res;
      if (sid) {
        res = await waSendTemplate(acct, ks, kk, from, to, sid, varsFor(key!, shortSummary(n.subject||n.body||'')));
      } else if (!ready) {
        // NOTE: the row is deliberately left 'queued' so it can go out once templates are approved.
        // That means it will be rescanned every run - tracked as 'requeued' so the backlog is visible.
        skipped++; requeued++; continue;
      } else {
        await admin.from('notifications').update({ status:'skipped' }).eq('id', n.id); skipped++; continue;
      }
      await admin.from('notifications').update({ status: res.ok?'sent':'failed', sent_at: res.ok?new Date().toISOString():null }).eq('id', n.id);
      if (res.ok) sent++; else { failed++; lastErr = String(res.error || '').slice(0, 200); }
    }
    // Templates not approved yet + a growing queue is the quiet failure worth surfacing.
    if (requeued) await logThrottled('templates_not_ready', 60, 'error', { requeued, pending: (rows||[]).length },
      requeued + ' WhatsApp notification(s) cannot be sent because wa_templates_ready is false. They stay queued and are rescanned every run, so this backlog will keep growing until templates are approved.');
    if (failed) await logRun('error', { sent, failed, skipped, templates_ready: ready }, 'Twilio rejected ' + failed + ' WhatsApp message(s). Last error: ' + lastErr);
    else if (sent || (skipped && !requeued)) await logRun('ok', { sent, failed, skipped, templates_ready: ready }, '');
    return J({ ok:true, sent, failed, skipped, templates_ready:ready });
  } catch (e) { const m = String((e as Error)?.message||e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
});
