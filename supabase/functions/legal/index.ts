import { createClient } from 'jsr:@supabase/supabase-js@2';
const ASSET=Deno.env.get('SUPABASE_URL')!+'/storage/v1/object/public/brand';
const UPDATED='29 June 2026';
const VER='v6';
let I18N='';
const sb=createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function pageHtml(slug:string){ try{ const {data}=await sb.from('pages').select('html').eq('slug',slug).maybeSingle(); return (data?.html as string)||''; }catch(_){ return ''; } }
async function docHtml(slug:string){ try{ const {data}=await sb.from('legal_documents').select('body_html').eq('slug',slug).eq('category','public').maybeSingle(); return (data?.body_html as string)||''; }catch(_){ return ''; } }

const NAV:[string,string][]=[
  ['terms','Terms of Service'],['privacy','Privacy Policy'],['supplier','Supplier Agreement'],
  ['cookie-policy','Cookie Policy'],['refund-policy','Refund & Cancellation'],['acceptable-use','Acceptable Use'],
  ['disclaimer','Disclaimer'],['complaints-policy','Complaints & Disputes'],
];
const PATH:Record<string,string>={ 'terms':'/terms/','privacy':'/privacy/','supplier':'/supplier-agreement/','cookie-policy':'/cookie-policy/','refund-policy':'/refund-policy/','acceptable-use':'/acceptable-use/','disclaimer':'/disclaimer/','complaints-policy':'/complaints/' };
function labelFor(doc:string){ const f=NAV.find(n=>n[0]===doc); return f?f[1]:'Legal'; }
const HEADER=`<header class="site"><div class="wrap"><a class="brand" href="/"><img src="${ASSET}/qd_lockup_light.png?v=2" alt="QuotesDone" style="height:26px;width:auto;display:block"></a><nav class="snav"><a href="/services/">Services</a><a href="/blog/">Blog</a><a href="/faq/">FAQ</a><a href="/about/">About</a><a href="/contact/">Contact</a></nav><a class="cta" href="/app">Get free quotes</a></div></header>`;

function shell(title:string, body:string, current:string){
  const nav=NAV.map(([k,t])=>`<a href="${PATH[k]||('/'+k+'/')}" class="${k===current?'on':''}">${t}</a>`).join('');
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${title} — QuotesDone Legal Centre</title>
<meta name="description" content="${title} for QuotesDone Technologies — the UAE B2B anonymous quotation marketplace. Operator: DET E-Trader Licence No. 1633275, Dubai, UAE.">
<link rel="canonical" href="https://quotesdone.com${PATH[current]||('/'+current+'/')}">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Sora:wght@400;600;700;800&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
<link rel="icon" href="${ASSET}/favicon.ico" sizes="any"><link rel="icon" type="image/png" sizes="32x32" href="${ASSET}/favicon-32.png"><link rel="apple-touch-icon" href="${ASSET}/apple-touch.png"><meta name="theme-color" content="#05121A">
<style>:root{--bg:#05121A;--panel:rgba(255,255,255,.05);--line:rgba(255,255,255,.10);--line2:rgba(255,255,255,.18);--t:#EAF4F2;--mut:#9DB2B2;--faint:#5E7475;--teal:#2DD4BF;--teal2:#14B8A6;--gold:#E7C579}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;background:radial-gradient(1000px 620px at 82% -14%,rgba(45,212,191,.16),transparent),radial-gradient(760px 520px at 4% 20%,rgba(231,197,121,.07),transparent),var(--bg);color:var(--t);font:16px/1.72 Inter,system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;-webkit-font-smoothing:antialiased;overflow-x:hidden}
a{color:var(--teal);text-decoration:none}a:hover{color:var(--teal2)}
h1,h2,h3{font-family:Sora,Inter,sans-serif;color:#fff}
header.site{position:sticky;top:0;z-index:30;background:rgba(5,18,26,.72);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);border-bottom:1px solid var(--line)}
header.site .wrap{display:flex;align-items:center;gap:16px;padding:13px 20px}
.brand{display:inline-flex;align-items:center}
.snav{display:flex;gap:20px;margin-left:6px}
.snav a{color:var(--mut);font-size:14px;font-weight:500}.snav a:hover{color:#fff}
@media(max-width:680px){.snav{display:none}}
.cta{margin-left:auto;background:linear-gradient(135deg,var(--teal),var(--teal2));color:#04121a;font-weight:700;padding:10px 18px;border-radius:12px;box-shadow:0 10px 26px -12px rgba(45,212,191,.7)}
.cta:hover{color:#04121a;filter:brightness(1.05)}
.wrap{max-width:880px;margin:0 auto;padding:0 20px}
.docwrap{max-width:880px;margin:0 auto;padding:24px 20px 54px}
.crumb{font-size:12.5px;color:var(--faint);margin:16px 0 16px}.crumb a{color:var(--mut)}
.nav{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:20px}
.nav a{font-size:12.5px;font-weight:600;text-decoration:none;color:var(--mut);background:var(--panel);border:1px solid var(--line);border-radius:999px;padding:8px 14px;transition:.15s}
.nav a:hover{color:#fff;border-color:var(--line2)}
.nav a.on{background:linear-gradient(135deg,var(--teal),var(--teal2));color:#04222b;border-color:transparent}
.doc{background:var(--panel);border:1px solid var(--line);border-radius:18px;padding:34px 40px;box-shadow:0 24px 60px -30px rgba(0,0,0,.7)}
.dochead{border-bottom:1px solid var(--line2);padding-bottom:16px;margin-bottom:6px}
.dochead h1{font-size:28px;margin:0 0 6px;color:#fff;letter-spacing:-.01em}
.dochead .meta{color:var(--mut);font-size:13px}
.body{margin-top:10px}
.body>h1:first-child{display:none}
.body .muted{color:var(--mut);font-size:13.5px;font-style:italic;margin:0 0 12px}
.body p{margin:0 0 12px;color:#d4e4e2}
.body h1{font-size:22px;color:#fff;margin:26px 0 8px}
.body h2{font-size:18px;color:#fff;margin:28px 0 8px;padding-left:12px;border-left:3px solid var(--teal)}
.body h3{font-size:15px;color:#fff;margin:16px 0 6px}
.body ol,.body ul{padding-left:22px}.body li{margin:6px 0;color:#d4e4e2}
.body a{color:var(--teal);font-weight:600}.body strong{color:#fff}
.body table{width:100%;border-collapse:collapse;font-size:14px;margin:12px 0}.body th,.body td{border:1px solid var(--line);padding:8px 10px;text-align:left;color:#d4e4e2}.body th{background:var(--panel);color:#fff}
html[dir=rtl] .body h2{padding-left:0;padding-right:12px;border-left:0;border-right:3px solid var(--teal)}
html[dir=rtl] .body ol,html[dir=rtl] .body ul{padding-left:0;padding-right:22px}
html[dir=rtl] .body th,html[dir=rtl] .body td{text-align:right}
.note{background:rgba(45,212,191,.06);border:1px solid var(--line2);border-left:3px solid var(--teal);border-radius:12px;padding:14px 16px;font-size:12.5px;color:var(--mut);margin-top:26px;line-height:1.65}
.note b{color:#fff}
.contact{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:20px 24px;margin-top:18px}
.contact .ct b{color:#fff}.contact .ct div{color:var(--mut);font-size:13px}
.cbtns{display:flex;gap:10px;flex-wrap:wrap}
.btn{display:inline-flex;align-items:center;gap:7px;text-decoration:none;font-weight:700;font-size:14px;border-radius:11px;padding:11px 18px;cursor:pointer;border:0}
.btn.primary{background:linear-gradient(135deg,var(--teal),var(--teal2));color:#04222b}
.btn.ghost{background:var(--panel);border:1px solid var(--line2);color:var(--t)}
.ft{max-width:880px;margin:0 auto;padding:26px 20px 54px;text-align:center;color:var(--faint);font-size:12px;line-height:1.9}
.ft a{color:var(--mut)}
@media(max-width:560px){.doc{padding:24px 20px}}
</style></head><body>
${HEADER}
<div class="docwrap">
<div class="crumb"><a href="/">Home</a> › Legal › ${title}</div>
<nav class="nav">${nav}</nav>
<article class="doc"><div class="dochead"><h1>${title}</h1><div class="meta">QuotesDone Technologies · Version ${VER} · Last updated ${UPDATED}</div><div class="meta">The English version of this document is the governing version.</div></div><div class="body">${body}</div>
<div class="note"><b>Operator:</b> QuotesDone Technologies, Dubai DET E-Trader (Professional) Licence No. 1633275, Commercial Register No. 2883503, Dubai, UAE. <b>Governing law:</b> the laws of the United Arab Emirates, including the Commercial Transactions Law (Federal Decree-Law No. 50 of 2022), the Electronic Transactions and Trust Services Law (Federal Decree-Law No. 46 of 2021), the Consumer Protection Law (Federal Law No. 15 of 2020) and Cabinet Resolution No. 66 of 2023, the Personal Data Protection Law (Federal Decree-Law No. 45 of 2021), and the Civil Transactions Law (Federal Decree-Law No. 25 of 2025, in force from 1 June 2026). Disputes are subject to the competent courts of Dubai.</div>
</article>
<div class="contact"><div class="ct"><b>Questions about this document?</b><div>Our team usually replies within one business day.</div></div><div class="cbtns"><a class="btn primary" href="mailto:management@quotesdone.com">✉ Email us</a><a class="btn ghost" href="/contact/">Contact us</a></div></div>
</div>
<footer class="ft">QuotesDone Technologies · DET E-Trader Licence No. 1633275 · Dubai, United Arab Emirates<br><a href="mailto:management@quotesdone.com">management@quotesdone.com</a> · <a href="/contact/">Contact</a> · <a href="/">quotesdone.com</a></footer>
${I18N}</body></html>`;
}
const FALLBACK=`<p>This document is being updated. Please contact management@quotesdone.com.</p>`;

Deno.serve(async (req)=>{
  const url=new URL(req.url);
  let doc=(url.searchParams.get('doc')||'terms').toLowerCase();
  if(!NAV.find(n=>n[0]===doc)) doc='terms';
  const embed=url.searchParams.get('embed')==='1';
  try{ I18N = await (await fetch(ASSET+'/i18n_chrome.html')).text(); }catch(_e){ I18N=''; }
  let body:string;
  if(doc==='terms'){ body=(await pageHtml('legal_terms_body'))||FALLBACK; }
  else if(doc==='supplier'){ body=(await pageHtml('legal_supplier_body'))||FALLBACK; }
  else { body=(await docHtml(doc))||FALLBACK; }
  if(embed){ return new Response(body,{headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','Access-Control-Allow-Origin':'*'}}); }
  return new Response(shell(labelFor(doc), body, doc),{headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'}});
});