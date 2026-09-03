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
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin':'*', 'Access-Control-Allow-Headers':'authorization, content-type, apikey', 'Access-Control-Allow-Methods':'POST, OPTIONS' };
const J=(o:unknown,s=200)=>new Response(JSON.stringify(o),{status:s,headers:{'Content-Type':'application/json',...CORS}});
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string)||''; }
async function put(k:string,v:string){ await admin.from('app_secrets').upsert({ key:k, value:v }, { onConflict:'key' }); }

// THE CONTRACT. Every event stripe_webhook actually handles. Until 3 Sep 2026 this was a hand-kept
// mirror of that file's branches; now the handler branches on the same arrays this list is built
// from (_shared/stripe_events.ts), so a branch cannot exist without its subscription.
const REQUIRED_EVENTS: string[] = [...HANDLED_STRIPE_EVENTS];
const WEBHOOK_URL_SUFFIX = '/functions/v1/stripe_webhook';

async function stripe(path:string, sk:string, body?:URLSearchParams){
  const r = await fetch('https://api.stripe.com/v1/'+path, {
    method: body ? 'POST' : 'GET',
    headers: { 'Authorization':'Bearer '+sk, ...(body ? {'Content-Type':'application/x-www-form-urlencoded'} : {}) },
    body,
  });
  const j = await r.json().catch(()=>({}));
  return { ok:r.ok, status:r.status, j };
}
// Only our own endpoint is ever touched. A Stripe account can carry endpoints belonging to other
// integrations and silently rewriting one of those would be a genuinely bad day.
function ours(list:any[]){ return (list||[]).filter((e:any)=>String(e?.url||'').endsWith(WEBHOOK_URL_SUFFIX)); }
function drift(ep:any){
  const have = new Set<string>((ep?.enabled_events||[]) as string[]);
  const wildcard = have.has('*');
  return { missing: wildcard ? [] : REQUIRED_EVENTS.filter(e=>!have.has(e)), wildcard };
}

Deno.serve(async (req)=>{
  if(req.method==='OPTIONS') return new Response(null,{headers:CORS});
  try{
    const b=await req.json().catch(()=>({} as any));
    const token=String(b.token||'');
    const good=await sec('stripe_setup_token');
    if(!good || token!==good) return J({ ok:false, error:'bad_token' },403);
    const action=String(b.action||'save');
    if(action==='status'){
      const sk=await sec('stripe_secret_key');
      const mode = sk.startsWith('sk_live')?'LIVE':(sk.startsWith('sk_test')?'TEST':'none');
      if(!sk) return J({ ok:true, key_mode:'none' });
      const ar=await fetch('https://api.stripe.com/v1/account',{headers:{'Authorization':'Bearer '+sk}}); const aj=await ar.json();
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
    try{ const ar=await fetch('https://api.stripe.com/v1/account',{headers:{'Authorization':'Bearer '+cur}}); const aj=await ar.json(); charges=aj?.charges_enabled??null; payouts=aj?.payouts_enabled??null; country=aj?.country||null; cur3=aj?.default_currency||null; }catch(_e){}
    return J({ ok:true, saved, warnings:warn, key_mode:mode, charges_enabled:charges, payouts_enabled:payouts, country, default_currency:cur3 });
  }catch(e){ return J({ ok:false, error:String((e as Error)?.message||e) },500); }
});
