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
    // THE FLAG WAS NOT THE QUESTION (customer_support, 22 Sep 2026, finding INT-02). This read
    // `if (wa_templates_ready === 'true') return already_ready`. That flag is written ONCE, by the
    // run that first saw every tracked template approved, and nothing ever writes it back — so the
    // watcher switched itself off the day the first batch landed and never polled again. Measured
    // 22 Sep: SEVEN templates sat in Twilio's 'received' state (login_code en/ar and
    // supplier_account_notice en/ar from 18 Sep, three UTILITY re-submissions from 14 Sep,
    // supplier_quote_accepted en/ar from 6 Sep), four of them already named in wa_template_sids,
    // while wa_templates_ready said 'true'. The same stale flag also gated the scheduler
    // (fn_resilience_orphan_steps_due), so both halves agreed and neither was right.
    //
    // The question is the WORK: is anything still undecided? 'received' is Twilio's word for
    // submitted-and-waiting, so the test is the absence of a verdict rather than a list of the
    // words Twilio currently uses for waiting. Same predicate as the scheduler's gate, so the two
    // cannot drift apart. A read failure does NOT short-circuit: if we cannot tell, we poll.
    const { data: undecided, error: undecidedErr } = await sb.from('messaging_template')
      .select('sid').eq('channel', 'whatsapp').not('status', 'in', '("approved","rejected")').limit(1);
    if (!undecidedErr && (undecided?.length ?? 0) === 0
        && ((await sec('wa_templates_ready')) || 'false') === 'true') {
      // nothing waiting on Meta and the channel is open = idle run, deliberately not logged
      return J({ ok:true, already_ready:true });
    }
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
    // WRITE DOWN WHAT TWILIO SAID (22 Sep 2026). This loop has always asked Twilio per sid and then
    // thrown the answer away: nothing here wrote public.messaging_template, so that table's
    // last_checked_at was 12 days stale and a rejection was visible only in an agent_runs note that
    // scrolls. Two consequences follow from the write. Whoever reads the template register sees the
    // truth, and fn_resilience_orphan_steps_due's new wa_templates gate — "undecided and not asked
    // about for 20 hours" — actually SHUTS after a run, so the daily cadence is a cadence and not
    // every beat. UPDATE, not upsert: every sid in wa_template_sids already has a row, and an
    // insert would have to invent the name, category and template_key columns it does not know.
    let stamped = 0, stampErrs = 0;
    for (const x of statuses) {
      if (x.status === 'unknown' || String(x.status).startsWith('error:')) continue;  // no verdict, no stamp
      const now = new Date().toISOString();
      const { error: upErr, count } = await sb.from('messaging_template')
        .update({ status: x.status, last_checked_at: now }, { count: 'exact' }).eq('sid', x.sid);
      if (upErr) { stampErrs++; continue; }
      stamped += count ?? 0;
      // approved_at is WHEN IT WAS APPROVED, so it is written once and never moved by a later poll
      // that merely re-reads the same verdict. `.is(null)` is what makes the write idempotent.
      if (x.status === 'approved') {
        const { error: apErr } = await sb.from('messaging_template')
          .update({ approved_at: now }).eq('sid', x.sid).is('approved_at', null);
        if (apErr) stampErrs++;
      }
    }
    if (stampErrs) await logThrottled('template_register_not_stamped', 60, 'error', { total: sids.length, stamp_errors: stampErrs }, stampErrs + ' of ' + statuses.length + ' template statuses could not be written to messaging_template; the register keeps showing a stale status and the scheduler gate that reads last_checked_at stays open, so this watcher polls Twilio every beat instead of once a day');
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
    return J({ ok:true, total:sids.length, approved, rejected, all_approved:allApproved, register_stamped:stamped, register_errors:stampErrs, statuses });
  }catch(e){ await logRun('error', { stage:'run' }, 'wa_templates_watch crashed: '+String((e as Error)?.message||e)+'; WhatsApp template approval was not checked this cycle, so wa_templates_ready may stay false and WhatsApp alerts to suppliers and customers stay off'); return J({ ok:false, error:String((e as Error)?.message||e) }, 500); }
}));
