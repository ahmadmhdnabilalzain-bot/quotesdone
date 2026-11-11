// THE OVERVIEW'S SIX READS START WHEN THE HTML IS PARSED, NOT WHEN 1.35 MB OF JAVASCRIPT HAS LANDED.
//
// prefetch.ts already moved the five dashboard reads out from behind the kyc gate (14 Sep 2026).
// What was left is a bigger serial step, and it is the one the smoke test has been failing on:
// `warmDashboard` runs inside a React effect, so NOTHING is requested until the /me route's client
// bundle — 1.35 MB brotli across 16 chunks, measured 18 Sep 2026 — has downloaded, parsed and
// hydrated.
//
// MEASURED, 18 Sep 2026, scripts/e2e/portal_cold_first_load.mjs against quotesdone.com:
//   warm browser  shellMs 1064–1198, dataMs 1107–1791  → the six calls add 43–593 ms
//   cold browser  shellMs 1722–10186, dataMs 1613–10207
// and in CI (smoke, 15 Sep 2026) the first of the six calls started 339–1014 ms after navigation
// while the shell itself took 2129–3142 ms. The data is not slow — it is QUEUED BEHIND the shell.
// Six parallel authenticated calls measured 876–923 ms wall from a normal client, and the SQL under
// them is 8 ms (fn_customer_stats) / 0 ms (fn_customer_forecast, fn_twin) / 8 ms
// (fn_customer_decision_support), with the isolates kept warm at 1–3 ms by resilience_ping.
//
// So this script, inlined in the document by the server component below, issues exactly the same six
// requests `warmDashboard` + `load()` would issue, at HTML-parse time. They then run CONCURRENTLY
// with the chunk download instead of after it, and prefetch.ts hands the in-flight promise to the
// component that asks for it. Total settle time collapses towards the shell time.
//
// WHY AN INLINE SCRIPT AND NOT A MODULE. Anything imported is a chunk, and a chunk is the thing
// being waited for. This has to run before the module graph exists, so it is a plain IIFE with no
// imports, no framework and no build step.
//
// IT CAN ONLY EVER READ. Six POSTs whose bodies are `{action:'state'|'my_inquiries'|'overview'|
// 'dashboard'|'threads'|'decision_support'}` — every one a read on the caller's own rows. It sends
// the customer's OWN stored JWT (the same header `call()` in CustomerPortal.tsx sends) and nothing
// else, so it can reach nothing the portal could not reach one second later.
//
// IT REFUSES ON A DEAD TOKEN, exactly like tokenAlive() in CustomerPortal.tsx: an expired JWT would
// spend six round trips to collect six 401s and burn the one refresh attempt `retried` protects.
// With no token, or an unparseable one, it does nothing at all and the portal behaves as before.
//
// EVERY PROMISE IS HANDED OUT AT MOST ONCE (prefetch.ts `boot()` deletes it on read) and only to the
// SAME token that started it. A refresh, a retry, or a different customer asks the server fresh —
// the same rule prefetch.ts already applies to its own in-flight map.
import { SUPA_FN, FN_REGION } from '@/lib/supaEnv';

// THE ASSISTANT'S HISTORY IS THE SEVENTH READ (11 Nov 2026, sales_engineer; nightly run 077cbbfc). The overview's data settled
// at 2.54-2.85 s on three viewports against a 2.5 s budget, and the last call to land was sales_engineer:assist_history,
// started at 1.58-1.74 s (after the bundle, by AssistantPanel's mount) while the six reads above started at 0.37-0.73 s. It is
// started here too, as a plain read. NEVER with a widget chat waiting to be adopted ('qd-chat-conv', lib/widgetConv.ts):
// adopting moves rows (a write), so then the panel sends it itself, with adopt, exactly as before.
// prevented by: scripts/checks/customer_overview_reads_run_in_the_database_region.test.mjs ("assist_history ...")
// The five dashboard keys are prefetch.ts's own ('inq','ov','pd','threads','decision_support');
// 'kyc' is the gate Authed.load() reads. Keeping the names here identical to the ones the
// components `take()` is the whole contract — a renamed key silently degrades to no prefetch.
const lit = (s: string) => JSON.stringify(s).split('<').join('\\u003c').split(String.fromCharCode(0x2028)).join('\\u2028').split(String.fromCharCode(0x2029)).join('\\u2029');
// The region pin is supaEnv.ts fnUrl()'s, so a boot read and the portal's own read land in the same place.
const BOOT = (fn: string, region: string) => `(function(){try{
var F=${lit(fn)},R=${lit(region)};if(!F||F.indexOf('/functions/v1')<0)return;
var t=localStorage.getItem('qd-cust-token')||'';if(!t)return;
var e=(JSON.parse(atob(t.split('.')[1]))||{}).exp||0;if(!(e>Date.now()/1000+60))return;
var l=location.pathname.indexOf('/ar')===0?'ar':'en';
var g=function(p,b){return fetch(F+'/'+p+'?forceFunctionRegion='+R,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+t},body:JSON.stringify(b)}).then(function(r){return r.json()})};
var m={kyc:g('kyc',{action:'state'}),inq:g('customer_api',{action:'my_inquiries'}),ov:g('customer_portal',{action:'overview',lang:l}),pd:g('project_api',{action:'dashboard'}),threads:g('messages_api',{action:'threads'}),decision_support:g('customer_portal',{action:'decision_support',lang:l})};
if(!localStorage.getItem('qd-chat-conv'))m.assist=g('sales_engineer',{action:'assist_history'});
for(var k in m){m[k].catch(function(){})}
window.__qdBoot={token:t,m:m};
}catch(_e){}})();`;

/**
 * Inlined in the /me document. A server component so the URL is stamped at render time and the
 * script carries no import of its own.
 *
 * `lang` is sent for parity with warmDashboard; customer_portal deliberately ignores it and uses
 * customers.locale (see its header), so a URL locale that disagrees with the registered one changes
 * nothing about what comes back.
 */
// The ONLY value interpolated into the script is SUPA_FN — a build-time constant from
// src/lib/supaEnv.ts, never a request, a param or anything a visitor can influence — and it goes in
// through JSON.stringify AND the `<` escape below, so there is no untrusted content in this markup
// to sanitise. (JSON.stringify alone does not escape `</script` or U+2028/U+2029, so the escape is
// there to make a mis-set deployment variable incapable of closing the tag, not because anything
// reachable can set one.)
//
// IT RUNS ON A HARD NAVIGATION ONLY, AND THAT IS THE CASE IT EXISTS FOR. A script element whose
// text React sets through innerHTML is not parser-inserted, so it does not execute on a client-side
// <Link> transition into /me. On such a transition the portal's bundle is ALREADY parsed and
// hydrated — there is no shell to overlap, which is the entire cost this removes — so the
// optimisation applies exactly where the serialisation exists (a typed URL, a bookmark, a refresh,
// the OTP redirect, and the e2e harness's page.goto) and is a no-op, falling straight back to
// warmDashboard's own request, where it does not.
export function BootPrefetch() {
  if (!SUPA_FN || SUPA_FN.startsWith('/')) return null; // a preview with no Supabase target: nothing to call
  return <script id="qd-boot-prefetch" dangerouslySetInnerHTML={{ __html: BOOT(SUPA_FN, FN_REGION) }} />;
}
