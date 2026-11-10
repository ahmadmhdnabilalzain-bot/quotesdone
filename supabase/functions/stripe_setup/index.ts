// stripe_setup - token-gated endpoint for the founder to save LIVE Stripe keys directly (values never returned/logged).
//
// AUDIT 5.6 (3 Aug 2026) — webhook subscription is now managed HERE, not by hand in the dashboard.
//
// What the audit found: the live endpoint had enabled_events = ["checkout.session.completed"] and
// NOTHING ELSE, while stripe_webhook/index.ts branches on four refund events as well. Every refund
// the business issued produced no ledger row at all. The refunds tables being empty, and
// "0 quarantine rows, needs_attention false" reading as healthy, were both VACUOUS consequences of
// that — not evidence of health.
//
// It got that way because the subscription lived only in a dashboard nobody re-checked. So the
// required set is declared once, in code, next to the handler that consumes it:
//   action 'webhook_status' reports drift and never changes anything
//   action 'webhook_sync'   makes the endpoint match, additively
// A missing event is now a thing you can ASK about, in the same place you can fix it.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { HANDLED_STRIPE_EVENTS } from '../_shared/stripe_events.ts';
import { observe } from '../_shared/observe.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { syncDomains, syncPaymentMethods } from './payment_methods.ts';
import { BAD_TOKEN_LIMIT, BAD_TOKEN_WINDOW_MS, WEBHOOK_URL_SUFFIX, drift as driftFor, ours, planWebhookEnsure, sameSecret } from './webhook_plan.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
// NO CROSS-ORIGIN ACCESS (14 Sep 2026, security review of #631). This endpoint writes secrets, and it
// answered `Access-Control-Allow-Origin: *`. Its only browser caller is stripe_setup_page, which is
// served from this same Supabase origin and posts here same-origin, so it needs no CORS header at all.
// Every other caller is a server. With no allow-origin header, no other site's page can read an answer.
const CORS: Record<string, string> = {};
const J=(o:unknown,s=200)=>new Response(JSON.stringify(o),{status:s,headers:{'Content-Type':'application/json',...CORS}});
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string)||''; }
async function put(k:string,v:string){ await admin.from('app_secrets').upsert({ key:k, value:v }, { onConflict:'key' }); }

// THE CONTRACT. Every event stripe_webhook actually handles. Until 3 Sep 2026 this was a hand-kept
// mirror of that file's branches; now the handler branches on the same arrays this list is built
// from (_shared/stripe_events.ts), so a branch cannot exist without its subscription.
const REQUIRED_EVENTS: string[] = [...HANDLED_STRIPE_EVENTS];

async function stripe(path:string, sk:string, body?:URLSearchParams){
  const r = await timedFetch('https://api.stripe.com/v1/'+path, {
    method: body ? 'POST' : 'GET',
    headers: { 'Authorization':'Bearer '+sk, ...(body ? {'Content-Type':'application/x-www-form-urlencoded'} : {}) },
    body,
  });
  const j = await r.json().catch(()=>({}));
  return { ok:r.ok, status:r.status, j };
}
// ours() and drift() live in webhook_plan.ts: ONE matcher for "our endpoint", used by every action.
const drift = (ep:any)=>driftFor(ep, REQUIRED_EVENTS);

Deno.serve(observe('stripe_setup', async (req) => {
  if(req.method==='OPTIONS') return new Response(null,{headers:CORS});
  try{
    const b=await req.json().catch(()=>({} as any));
    // THE TOKEN, CHECKED ONE WAY FOR EVERY ACTION (security review of #631). Constant time
    // (webhook_plan.ts sameSecret), and a guessing run is stopped: after BAD_TOKEN_LIMIT failures in
    // the window this answers 429 without comparing anything. Each failure is recorded in agent_runs;
    // the one that trips the limit is recorded as an error, so it is seen.
    const token=String(b.token||'');
    const since=new Date(Date.now()-BAD_TOKEN_WINDOW_MS).toISOString();
    const { count:recentBad } = await admin.from('agent_runs').select('id',{ count:'exact', head:true })
      .eq('agent','stripe_setup').eq('counts->>bad_token','1').gte('started_at', since);
    if((recentBad||0) >= BAD_TOKEN_LIMIT) return J({ ok:false, error:'too_many_attempts' },429);
    const good=await sec('stripe_setup_token');
    if(!(await sameSecret(token, good))){
      const tripped=(recentBad||0)+1>=BAD_TOKEN_LIMIT;
      try{ const at=new Date().toISOString(); await admin.from('agent_runs').insert({ agent:'stripe_setup', status: tripped?'error':'ok', started_at:at, finished_at:at,
        counts:{ bad_token:1, recent:(recentBad||0)+1 },
        note: tripped ? 'stripe_setup refused '+BAD_TOKEN_LIMIT+' wrong setup tokens in 10 minutes and now answers 429 until the window passes.' : 'wrong setup token refused' }); }catch(_e){ /* the refusal stands either way */ }
      return J({ ok:false, error:'bad_token' },403);
    }
    const action=String(b.action||'save');
    if(action==='status'){
      const sk=await sec('stripe_secret_key');
      const mode = sk.startsWith('sk_live')?'LIVE':(sk.startsWith('sk_test')?'TEST':'none');
      if(!sk) return J({ ok:true, key_mode:'none' });
      const ar=await timedFetch('https://api.stripe.com/v1/account',{headers:{'Authorization':'Bearer '+sk}}); const aj=await ar.json();
      return J({ ok:ar.ok, key_mode:mode, charges_enabled:aj?.charges_enabled??null, payouts_enabled:aj?.payouts_enabled??null, country:aj?.country||null, default_currency:aj?.default_currency||null });
    }

    // AUDIT 5.6 — report only. Safe to call at any time; changes nothing.
    if(action==='webhook_status'){
      const sk=await sec('stripe_secret_key');
      if(!sk) return J({ ok:false, error:'no stripe_secret_key stored' });
      const { ok, j } = await stripe('webhook_endpoints?limit=100', sk);
      if(!ok) return J({ ok:false, error:'stripe_list_failed', detail:j?.error?.message||null },502);
      const mine = ours(j?.data||[]);
      const report = mine.map((e:any)=>({ id:e.id, url:e.url, status:e.status, livemode:e.livemode,
                                          enabled_events:e.enabled_events, ...drift(e) }));
      const missingAnywhere = report.some((r:any)=>r.missing.length>0);
      return J({ ok:true, required:REQUIRED_EVENTS, endpoints:report, in_sync:!missingAnywhere && mine.length>0,
                 note: mine.length===0 ? 'No endpoint on this account points at stripe_webhook. Nothing is being delivered.'
                     : missingAnywhere ? 'At least one required event is NOT subscribed. Events not subscribed are never delivered and produce no ledger row.'
                     : 'Every event stripe_webhook handles is subscribed.' });
    }

    // AUDIT 5.6 — make it match. ADDITIVE: the union of what is there and what is required, so an
    // event another integration relies on is never removed by this call.
    if(action==='webhook_sync'){
      const sk=await sec('stripe_secret_key');
      if(!sk) return J({ ok:false, error:'no stripe_secret_key stored' });
      const { ok, j } = await stripe('webhook_endpoints?limit=100', sk);
      if(!ok) return J({ ok:false, error:'stripe_list_failed', detail:j?.error?.message||null },502);
      const mine = ours(j?.data||[]);
      if(!mine.length) return J({ ok:false, error:'no_endpoint', hint:'No endpoint on this account points at '+WEBHOOK_URL_SUFFIX+'. Create it in Stripe first; this action will not invent one.' });
      const results:any[]=[];
      for(const ep of mine){
        const d = drift(ep);
        if(d.wildcard || !d.missing.length){ results.push({ id:ep.id, changed:false, enabled_events:ep.enabled_events, note:'already in sync' }); continue; }
        const union = Array.from(new Set([...(ep.enabled_events||[]), ...REQUIRED_EVENTS]));
        const form = new URLSearchParams();
        for(const e of union) form.append('enabled_events[]', e);
        const up = await stripe('webhook_endpoints/'+ep.id, sk, form);
        results.push({ id:ep.id, changed:up.ok, added:d.missing,
                       enabled_events: up.ok ? up.j?.enabled_events : ep.enabled_events,
                       error: up.ok ? null : (up.j?.error?.message||('http '+up.status)) });
      }
      // Re-read from Stripe rather than trusting the write response: the point of this action is to
      // be able to prove the subscription, not to report that a request was accepted.
      const after = await stripe('webhook_endpoints?limit=100', sk);
      const verified = ours(after.j?.data||[]).map((e:any)=>({ id:e.id, ...drift(e), enabled_events:e.enabled_events }));
      return J({ ok: results.every(r=>r.changed || r.note), required:REQUIRED_EVENTS, results, verified,
                 in_sync: verified.length>0 && verified.every((v:any)=>v.missing.length===0) });
    }

    // 14 Sep 2026 (accountant) — every non-BNPL payment method on, and the wallet domains registered.
    // mode 'live' (default) or 'test'; dry_run:true reports what would change and writes nothing.
    if(action==='payment_methods_sync'){
      const mode = b.mode==='test' ? 'test' : 'live';
      const key = await sec(mode==='test' ? 'stripe_secret_key_test' : 'stripe_secret_key');
      if(!key) return J({ ok:false, error:'no '+(mode==='test'?'stripe_secret_key_test':'stripe_secret_key')+' stored' });
      // A live key must never be used for a test run, or the reverse; say so instead of writing.
      if(!new RegExp('^(sk|rk)_'+mode+'_').test(key)) return J({ ok:false, error:'stored key is not a '+mode+' key' });
      const call = (path:string, form?:URLSearchParams)=>stripe(path, key, form);
      const dry = b.dry_run===true;
      const methods = await syncPaymentMethods(call, dry);
      const domains = await syncDomains(call, dry);
      return J({ ok: methods.ok && domains.ok, mode, dry_run:dry, payment_methods:methods, wallet_domains:domains });
    }

    // WEBHOOK_ENSURE (14 Sep 2026, agent: accountant). The e2e harness paid a real Stripe TEST-mode
    // reveal and nothing recorded it: the TEST account had 0 webhook endpoints, so stripe_webhook never
    // heard of the payment, and no invoice was filed or handed to the sales engineer. Registering one
    // by hand would mean copying a signing secret through a person or a session. It never is: this
    // action creates the endpoint and writes Stripe's signing secret straight into app_secrets, inside
    // this function. The response carries the endpoint id and its events, never the secret.
    //   mode 'test' -> stripe_secret_key_test / stripe_webhook_secret_test
    //   mode 'live' -> stripe_secret_key      / stripe_webhook_secret
    // What it may do is decided by planWebhookEnsure (webhook_plan.ts, tested alone): only a TEST account
    // with no endpoint of ours gets one created and a secret written. LIVE is never created, never
    // duplicated and its secret never written or rotated: an existing live endpoint is synced
    // additively, and a live endpoint whose secret is not stored is refused with the reason. It
    // answers back: every run is recorded in agent_runs, and stripe_webhook logs the mode of each
    // delivery it verifies, so the first event confirms the endpoint works.
    if(action==='webhook_ensure'){
      const t0=new Date().toISOString();
      const mode = b.mode==='test' ? 'test' : (b.mode==='live' ? 'live' : '');
      if(!mode) return J({ ok:false, error:'mode must be "test" or "live"' },400);
      const keyName = mode==='test' ? 'stripe_secret_key_test' : 'stripe_secret_key';
      const whName  = mode==='test' ? 'stripe_webhook_secret_test' : 'stripe_webhook_secret';
      const sk=await sec(keyName);
      // The same prefix guard as elsewhere, for THIS mode: a live key can never create a test
      // endpoint's secret, or the reverse.
      if(!new RegExp('^(sk|rk)_'+mode+'_').test(sk)) return J({ ok:false, error:'no '+mode+' secret key stored under '+keyName },400);
      const list = await stripe('webhook_endpoints?limit=100', sk);
      if(!list.ok) return J({ ok:false, error:'stripe_list_failed', detail:list.j?.error?.message||null },502);
      const plan = planWebhookEnsure({ mode, endpoints: list.j?.data||[], required: REQUIRED_EVENTS, secretStored: !!(await sec(whName)) });
      const record = async (status:string, counts:Record<string,unknown>, note:string)=>{
        try{ await admin.from('agent_runs').insert({ agent:'stripe_setup', status, started_at:t0, finished_at:new Date().toISOString(), counts:{ action:'webhook_ensure', mode, ...counts }, note }); }catch(_e){ /* the answer still reports it */ }
      };
      if(plan.kind==='refuse'){
        await record('ok', { refused:1 }, 'webhook_ensure('+mode+') refused: '+plan.reason);
        return J({ ok:false, mode, error:'refused', reason:plan.reason },409);
      }
      let created=false, id='', events:string[]=[], added:string[]=[], note='';
      if(plan.kind==='create'){
        // By construction only TEST reaches here; asserted again so a future edit cannot write live.
        if(mode!=='test') return J({ ok:false, mode, error:'refused', reason:'a live endpoint is never created here' },409);
        const url = String(Deno.env.get('SUPABASE_URL')||'').replace(/\/+$/,'') + WEBHOOK_URL_SUFFIX;
        const form=new URLSearchParams({ url, description:'QuotesDone stripe_webhook (test), managed by stripe_setup webhook_ensure' });
        for(const e of REQUIRED_EVENTS) form.append('enabled_events[]', e);
        const c=await stripe('webhook_endpoints', sk, form);
        if(!c.ok) return J({ ok:false, error:'stripe_create_failed', detail:c.j?.error?.message||null },502);
        if(c.j?.livemode!==false) return J({ ok:false, error:'mode_mismatch', id:c.j?.id||null },502);
        const signing=String(c.j?.secret||'');
        if(!/^whsec_/.test(signing)) return J({ ok:false, error:'created_without_signing_secret', id:c.j?.id||null },502);
        await put(whName, signing);
        created=true; id=String(c.j.id); events=c.j.enabled_events||[];
      } else {
        const ep=plan.endpoint; id=String(ep.id); events=ep.enabled_events||[];
        if(plan.kind==='sync'){
          const form=new URLSearchParams();
          for(const e of Array.from(new Set([...events, ...REQUIRED_EVENTS]))) form.append('enabled_events[]', e);
          const up=await stripe('webhook_endpoints/'+ep.id, sk, form);
          if(!up.ok) return J({ ok:false, error:'stripe_update_failed', id, detail:up.j?.error?.message||null },502);
          events=up.j?.enabled_events||events; added=plan.missing;
        }
        // Stripe reveals a signing secret only when the endpoint is created. A TEST endpoint whose
        // secret is not stored cannot be repaired by reading it; say so rather than pretend. (LIVE in
        // that state was already refused by the plan.)
        if(!(await sec(whName))) note='This endpoint existed before and its signing secret is not stored under '+whName+'. Stripe shows it only at creation: roll the secret on this endpoint in Stripe, or delete the endpoint and run webhook_ensure again.';
      }
      const secretStored=!!(await sec(whName));
      try{ await admin.from('agent_runs').insert({ agent:'stripe_setup', status: secretStored?'ok':'error', started_at:t0, finished_at:new Date().toISOString(),
        counts:{ action:'webhook_ensure', mode, created, endpoint_id:id, events:events.length, added:added.length, secret_stored:secretStored },
        note:(created?'Created the '+mode+' webhook endpoint and stored its signing secret.':'The '+mode+' webhook endpoint exists'+(added.length?'; subscribed '+added.join(', '):'; already in sync')+'.')+(note?' '+note:'') }); }catch(_e){ /* the answer below still reports it */ }
      return J({ ok:secretStored, mode, created, id, events, added, secret_stored:secretStored, ...(note?{ note }:{}) });
    }

    // save
    const sk=String(b.sk||'').trim();
    const pk=String(b.pk||'').trim();
    const whsec=String(b.whsec||'').trim();
    const saved:string[]=[]; const warn:string[]=[];
    if(sk){ if(!/^sk_(live|test)_/.test(sk)) return J({ ok:false, error:'secret key must start with sk_live_ or sk_test_' }); if(sk.startsWith('sk_test')) warn.push('You pasted a TEST secret key (sk_test) — use sk_live for real payments.'); await put('stripe_secret_key',sk); saved.push('secret key'); }
    if(pk){ if(!/^pk_(live|test)_/.test(pk)) return J({ ok:false, error:'publishable key must start with pk_live_ or pk_test_' }); await put('stripe_publishable_key',pk); saved.push('publishable key'); }
    if(whsec){ if(!/^whsec_/.test(whsec)) return J({ ok:false, error:'webhook secret must start with whsec_' }); await put('stripe_webhook_secret',whsec); saved.push('webhook secret'); }
    if(!saved.length) return J({ ok:false, error:'nothing to save' });
    // verify against Stripe with whatever secret key is now stored
    const cur=await sec('stripe_secret_key');
    const mode = cur.startsWith('sk_live')?'LIVE':(cur.startsWith('sk_test')?'TEST':'none');
    let charges=null, payouts=null, country=null, cur3=null;
    try{ const ar=await timedFetch('https://api.stripe.com/v1/account',{headers:{'Authorization':'Bearer '+cur}}); const aj=await ar.json(); charges=aj?.charges_enabled??null; payouts=aj?.payouts_enabled??null; country=aj?.country||null; cur3=aj?.default_currency||null; }catch(_e){}
    return J({ ok:true, saved, warnings:warn, key_mode:mode, charges_enabled:charges, payouts_enabled:payouts, country, default_currency:cur3 });
  }catch(e){ return J({ ok:false, error:String((e as Error)?.message||e) },500); }
}));
