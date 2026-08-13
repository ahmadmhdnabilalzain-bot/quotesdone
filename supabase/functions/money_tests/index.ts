// money_tests - automated invariant checks for the payment paths + security regressions.
// Runs read-only/black-box assertions; alerts the founder (admin notification) on any failure.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'money_tests', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const BASE = Deno.env.get('SUPABASE_URL')!;
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0ZGJsd2xkamtjZ2p2bXFrYmVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3ODU1NDYsImV4cCI6MjA5NjM2MTU0Nn0.cF9ZR_Qo1YBhLvhTLS8aANlYb6c9rTsuQS6kLxGw_Bo';
const J=(o:unknown,s=200)=>new Response(JSON.stringify(o,null,2),{status:s,headers:{'Content-Type':'application/json'}});
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string)||''; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function revealFee(amount:number,cfg:any,at=new Date()){ if(!amount||amount<=0) return 0; const promo=!!cfg.promo_until&&at<=new Date(cfg.promo_until); const rate=Number(promo?cfg.promo_reveal_rate:cfg.standard_reveal_rate); const cap=Number(promo?cfg.promo_reveal_cap:cfg.standard_reveal_cap); return Math.min(Math.round(amount*rate*100)/100, cap); }
async function restGet(path:string){ const r=await fetch(`${BASE}/rest/v1/${path}`,{headers:{apikey:ANON,Authorization:'Bearer '+ANON}}); let b:any=null; try{b=await r.json();}catch(_e){} return {status:r.status, body:b}; }
async function rpc(name:string,body:any){ const r=await fetch(`${BASE}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:ANON,Authorization:'Bearer '+ANON,'Content-Type':'application/json'},body:JSON.stringify(body)}); let b:any=null; try{b=await r.json();}catch(_e){} return {status:r.status, body:b}; }
async function fn(slug:string,body:any,auth:string|null){ const h:any={'Content-Type':'application/json'}; if(auth) h['Authorization']='Bearer '+auth; const r=await fetch(`${BASE}/functions/v1/${slug}`,{method:'POST',headers:h,body:JSON.stringify(body)}); let b:any=null; try{b=await r.json();}catch(_e){} return {status:r.status, body:b}; }
Deno.serve(async (req)=>{
  // H4: self-authenticate on inbound_secret. Previously unauthenticated + verify_jwt=true meant any holder of
  // the public anon key could trigger the probe suite and read which tables are exposed. The daily cron now
  // sends __secret; verify_jwt stays true as defence-in-depth.
  const body = await req.json().catch(()=>({} as any));
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, body?.__secret, 'money_tests');
  if (!__auth.ok) return J({ error:'forbidden' }, 403);
  const results:{name:string,pass:boolean,detail?:string}[]=[];
  const T=(name:string,pass:boolean,detail='')=>results.push({name,pass,detail:pass?undefined:detail});
  let cfgErrMsg='';
  try{
    const {data:cfg,error:cfgErr}=await admin.from('pricing_config').select('*').eq('id',1).maybeSingle();
    if(cfgErr||!cfg) cfgErrMsg='pricing_config row id=1 could not be read, so the reveal-fee maths could not be verified at all and a wrong fee could be charged to customers without any test catching it: '+String(cfgErr?.message||'no pricing_config row')+'. ';
    // 1) fee math
    //
    // THE SUITE DETECTED THE MISSING CONFIG AND THEN DEREFERENCED IT ANYWAY (13 Aug 2026).
    // The line above builds a careful cfgErrMsg for exactly this case, and the fee assertions two
    // lines down read cfg.standard_reveal_rate regardless. With no pricing_config row, revealFee
    // threw on `cfg.promo_until`, the whole runner died before it reached the security and Stripe
    // checks below, and the message it had just written was never logged - the throw happens long
    // before the logRun at the bottom. Measured: money_verify on staging 1 attempt, 1 failure,
    // HTTP 200 with {"ok":false,"passed":0,"failed":1,"results":[{"name":"runner","pass":false,
    // "detail":"Cannot read properties of null (reading 'promo_until')"}]} - and NOT ONE recorded
    // attempt on production. The money invariants have never verified anything on either project.
    //
    // A missing config is now a FAILED assertion with the reason attached, not a crash, and the
    // fee block is skipped rather than run against null. Everything after it - the anon-readability
    // regressions on customers/transactions/app_secrets, the Stripe live-key and charges_enabled
    // checks, the no-auth guards on the money endpoints - now runs on a project that has no
    // pricing_config row, which is the case where those checks matter most.
    T('pricing_config is readable', !!cfg, cfgErrMsg || 'no pricing_config row id=1');
    if(cfg){
      T('fee(10000)=3%', revealFee(10000,cfg)===Math.round(10000*Number(cfg.standard_reveal_rate)*100)/100, 'got '+revealFee(10000,cfg));
      T('fee(0)=0', revealFee(0,cfg)===0);
      T('fee is monotonic', revealFee(50000,cfg) >= revealFee(10000,cfg));
      T('fee never exceeds cap', revealFee(1e12,cfg) <= Number(cfg.standard_reveal_cap));
    }
    // 2) stripe config
    const sk=await sec('stripe_secret_key');
    // WHICH PROJECT THIS IS DECIDES WHAT "CORRECT" MEANS FOR A STRIPE KEY.
    //
    // 'stripe key is LIVE' was asserted unconditionally, so on staging - which must never hold
    // live payment credentials - it could only ever fail. A check that cannot pass on the project
    // it runs against is not a standard, it is noise that trains you to ignore a red line.
    //
    // Inverted rather than skipped, because the staging case is worth asserting in its own right:
    // a live secret key appearing on a non-production project is a real incident, and nothing in
    // the estate was looking for it.
    const PROD_REF='htdblwldjkcgjvmqkbeh';
    const selfRef=(Deno.env.get('SUPABASE_URL')||'').replace(/^https?:\/\//,'').split('.')[0];
    const isProd=selfRef===PROD_REF;
    if(isProd){
      T('stripe key is LIVE', sk.startsWith('sk_live_'), 'key_mode='+(sk.slice(0,8)));
      if(sk){ const ar=await fetch('https://api.stripe.com/v1/account',{headers:{Authorization:'Bearer '+sk}}); const aj=await ar.json(); T('stripe charges_enabled', aj?.charges_enabled===true, JSON.stringify(aj?.charges_enabled)); }
    } else {
      T('stripe key is NOT live off production', !sk.startsWith('sk_live_'), 'a LIVE Stripe secret key is present on '+(selfRef||'a non-production project')+' - remove it');
    }
    // 3) security regressions - sensitive tables must NOT be anon-readable
    const ri=await restGet('reveal_invoices?select=*&limit=1'); T('reveal_invoices not anon-readable', ri.status===401||ri.status===403||(ri.body&&ri.body.code==='42501')||(Array.isArray(ri.body)&&ri.body.length===0), 'status '+ri.status+' '+JSON.stringify(ri.body).slice(0,80));
    const cu=await restGet('customers?select=*&limit=1'); T('customers denied to anon', cu.status===401||cu.status===403||(cu.body&&cu.body.code==='42501'), 'status '+cu.status);
    const tx=await restGet('transactions?select=*&limit=1'); T('transactions denied to anon', tx.status===401||tx.status===403||(tx.body&&tx.body.code==='42501'), 'status '+tx.status);
    const as=await restGet('app_secrets?select=*&limit=1'); T('app_secrets denied to anon', as.status===401||as.status===403||(as.body&&as.body.code==='42501'), 'status '+as.status);
    const fm=await rpc('funnel_metrics',{days:7}); T('funnel_metrics denied to anon', fm.status===401||fm.status===403||(fm.body&&fm.body.code), 'status '+fm.status);
    // 4) money edge-function guards (must reject unauthenticated)
    const co=await fn('stripe_checkout',{quote_id:'00000000-0000-0000-0000-000000000000'},null); T('stripe_checkout rejects no-auth', co.status===401, 'status '+co.status);
    const cf=await fn('stripe_confirm',{},null); T('stripe_confirm rejects no-auth', cf.status===401, 'status '+cf.status);
    const coA=await fn('stripe_checkout',{quote_id:'00000000-0000-0000-0000-000000000000'},ANON); T('stripe_checkout rejects anon token', coA.status===401, 'status '+coA.status);
  }catch(e){ T('runner', false, String((e as Error)?.message||e)); }
  const failed=results.filter(r=>!r.pass);
  let notifyErrMsg='';
  if(failed.length){
    // Founder email: prefer founder_email secret, else first admin_emails entry (OPEN_ISSUES #5).
    const founder=(await sec('founder_email')) || ((await sec('admin_emails')).split(',')[0]||'').trim() || 'management@quotesdone.com';
    const {error:notifyErr}=await admin.from('notifications').insert({ type:'money_test_fail', to_role:'admin', to_email:founder, channel:'email', status:'queued', subject:`⚠️ QuotesDone money/security test FAILED (${failed.length})`, body:'Automated invariant checks failed:\n\n'+failed.map(f=>`- ${f.name}: ${f.detail||''}`).join('\n')+'\n\nInvestigate before taking payments.' });
    if(notifyErr) notifyErrMsg='The founder alert email could not be queued in notifications, so '+failed.length+' failing money/security invariant(s) will go completely unnoticed: '+String(notifyErr.message||notifyErr)+'. ';
  }
  const counts={ total:results.length, passed:results.length-failed.length, failed:failed.length, failing_tests:failed.map(f=>f.name), alert_queued: failed.length? (notifyErrMsg?0:1) : 0 };
  if(failed.length||notifyErrMsg||cfgErrMsg){
    await logRun('error', counts, cfgErrMsg+notifyErrMsg+(failed.length?('Money/security invariant checks failed ('+failed.length+' of '+results.length+'): '+failed.map(f=>f.name+' -> '+(f.detail||'')).join('; ')+'. Payments or data-access protections may be broken.'):''));
  } else {
    await logRun('ok', counts, '');
  }
  return J({ ok:failed.length===0, passed:results.length-failed.length, failed:failed.length, results });
});
