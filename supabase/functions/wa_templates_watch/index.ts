// wa_templates_watch - polls Twilio for WhatsApp template approval; when ALL approved, flips wa_templates_ready='true' and emails the founder.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { requestDelivery } from '../_shared/deliver.ts';
const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await sb.from('agent_runs').insert({ agent: 'wa_templates_watch', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
async function logThrottled(signal: string, minutes: number, status: string, counts: Record<string, unknown>, note: string) {
  try {
    const since = new Date(Date.now() - minutes * 60000).toISOString();
    const { data } = await sb.from('agent_runs').select('id').eq('agent', 'wa_templates_watch')
      .gte('started_at', since).eq('counts->>signal', signal).limit(1);
    if (data && data.length) return;
  } catch (_e) { /* fall through and log */ }
  await logRun(status, { ...counts, signal }, note);
}
async function sec(k:string){ const {data}=await sb.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
const J=(o:unknown,s=200)=>new Response(JSON.stringify(o,null,2),{status:s,headers:{'Content-Type':'application/json'}});

Deno.serve(observe('wa_templates_watch', async (req)=>{
  try{
    // AUDIT 9.5 (4 Aug 2026). This handler never read the request. It had NO internal gate at all -
    // `Deno.serve(async ()=>{...})` - and ran as the service role. Its only protection was
    // verify_jwt, and the anon key is a valid JWT that ships in the frontend, so anyone holding the
    // public key could invoke it. It reads Twilio credentials, enumerates template approval statuses
    // into its response, writes app_secrets.wa_templates_ready and queues founder mail.
    //
    // Not in the D3/D5 inventory and not in v_internal_secret_migration_progress either, because the
    // view counts crons that present a secret and this one presented none.
    const body = await req.json().catch(()=>({} as Record<string, unknown>));
    const __auth = await requireInternal(sb, (body as { __secret?: unknown })?.__secret, 'wa_templates_watch');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    // already ready = idle run that does no work, deliberately not logged
    if(((await sec('wa_templates_ready'))||'false')==='true') return J({ ok:true, already_ready:true });
    const ks=await sec('twilio_api_key_sid'); const kk=await sec('twilio_api_key_secret');
    if(!ks||!kk) { await logThrottled('no_twilio_creds', 60, 'error', { stage:'config' }, 'twilio_api_key_sid/secret missing from app_secrets: WhatsApp template approval can never be detected, so wa_templates_ready is never flipped and suppliers and customers never receive WhatsApp job, quote or unlock alerts'); return J({ ok:false, error:'no_twilio_creds' }); }
    const auth='Basic '+btoa(`${ks}:${kk}`);
    let mapParseErr='';
    let map:any={}; try{ map=JSON.parse((await sec('wa_template_sids'))||'{}'); }catch(_){ mapParseErr=String(_); map={}; }
    const sids:{name:string,sid:string}[]=[];
    for(const [k,v] of Object.entries(map)){ for(const [lang,sid] of Object.entries(v as any)){ sids.push({name:`${k}_${lang}`, sid:sid as string}); } }
    if(!sids.length) { await logThrottled('no_template_sids', 60, 'error', { stage:'config', map_parse_failed: mapParseErr ? 1 : 0 }, (mapParseErr ? ('wa_template_sids is not valid JSON ('+mapParseErr+'), so no templates are tracked; ') : 'wa_template_sids is empty, so no templates are tracked; ')+'approval can never complete, wa_templates_ready is never flipped and WhatsApp alerts to suppliers and customers stay permanently off'); return J({ ok:false, error:'no_template_sids' }); }
    const statuses:any[]=[]; let approved=0, rejected=0;
    for(const s of sids){
      let st='unknown';
      try{
        const r=await fetch(`https://content.twilio.com/v1/Content/${s.sid}/ApprovalRequests`,{ headers:{ 'Authorization':auth } });
        const j=await r.json();
        st = j?.whatsapp?.status || j?.status || 'unknown';
      }catch(e){ st='error:'+String(e); }
      if(st==='approved') approved++; else if(st==='rejected') rejected++;
      statuses.push({ name:s.name, sid:s.sid, status:st });
    }
    const allApproved = approved===sids.length;
    if(allApproved){
      const { error: readyErr } = await sb.from('app_secrets').upsert({ key:'wa_templates_ready', value:'true' }, { onConflict:'key' });
      // Founder email: prefer founder_email secret, else first admin_emails entry (OPEN_ISSUES #5).
      const founder = (await sec('founder_email')) || (((await sec('admin_emails'))||'').split(',')[0]||'').trim() || 'management@quotesdone.com';
      const { error: notifErr } = await requestDelivery(sb, { type:'wa_templates_ready', to_role:'admin', to_email:founder, channel:'email', status:'queued', subject:'✅ WhatsApp templates approved — notifications are now LIVE', body:'All 6 WhatsApp templates have been approved by Meta. QuotesDone will now send WhatsApp alerts (new job, new quote, supplier unlocked) to opted-in suppliers and customers automatically. No action needed.' });
      // stop future polling
      let cronErr='';
      try{ const { error: rpcErr } = await sb.rpc('cron_unschedule_wa_watch'); if(rpcErr) cronErr=String(rpcErr.message); }catch(_){ cronErr=String(_); /* ignore if not present */ }
      const anotes:string[]=[];
      if(readyErr) anotes.push('all '+sids.length+' WhatsApp templates are approved but writing wa_templates_ready=true FAILED ('+String(readyErr.message)+'); WhatsApp alerts stay switched off for suppliers and customers and this watcher will re-run and re-notify every 15 minutes');
      if(notifErr) anotes.push('founder notification insert failed ('+String(notifErr.message)+'); nobody was told that WhatsApp notifications are now live');
      if(cronErr) anotes.push('cron_unschedule_wa_watch failed ('+cronErr+'); this watcher keeps polling Twilio every 15 minutes forever');
      if(!anotes.length) anotes.push('all '+sids.length+' WhatsApp templates approved: wa_templates_ready flipped to true, founder notified and polling unscheduled. WhatsApp job/quote/unlock alerts are now live');
      await logRun((readyErr||notifErr||cronErr) ? 'error' : 'ok', { total:sids.length, approved, rejected, all_approved:true, ready_write_failed: readyErr?1:0, notify_failed: notifErr?1:0, cron_unschedule_failed: cronErr?1:0 }, anotes.join(' | '));
    } else {
      const bad = statuses.filter((x:any)=> x.status==='unknown' || String(x.status).startsWith('error:'));
      if(rejected){ await logThrottled('templates_rejected', 60, 'error', { total:sids.length, approved, rejected, unknown: bad.length }, rejected+' of '+sids.length+' WhatsApp templates were REJECTED by Meta ('+statuses.filter((x:any)=>x.status==='rejected').map((x:any)=>x.name).join(',')+'); approval can never reach 100%, so wa_templates_ready is never flipped and suppliers and customers will never receive WhatsApp job, quote or unlock alerts until the templates are resubmitted'); }
      else if(bad.length){ await logThrottled('twilio_status_unknown', 60, 'error', { total:sids.length, approved, rejected, unknown: bad.length }, 'could not read an approval status for '+bad.length+' of '+sids.length+' templates ('+bad.map((x:any)=>x.name+'='+x.status).slice(0,6).join(',')+'); those templates can never be counted as approved, so wa_templates_ready is never flipped and WhatsApp alerts stay off indefinitely'); }
      // otherwise: templates simply still pending = idle run that did no work, deliberately not logged
    }
    return J({ ok:true, total:sids.length, approved, rejected, all_approved:allApproved, statuses });
  }catch(e){ await logRun('error', { stage:'run' }, 'wa_templates_watch crashed: '+String((e as Error)?.message||e)+'; WhatsApp template approval was not checked this cycle, so wa_templates_ready may stay false and WhatsApp alerts to suppliers and customers stay off'); return J({ ok:false, error:String((e as Error)?.message||e) }, 500); }
}));
