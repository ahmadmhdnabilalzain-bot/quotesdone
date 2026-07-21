// faq — public FAQ from company_faq, unified header + chrome (language button + chat widget) matching the site.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const ASSET='https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand';
const esc = (s: unknown) => String(s ?? '').replace(/[&<>]/g, (c)=>({'&':'&amp;','<':'&lt;','>':'&gt;'} as any)[c]);
const ORDER: [string,string][] = [
  ['Company Identity','About QuotesDone'], ['Customer','For Customers'], ['Supplier','For Suppliers'],
  ['RFQ','Requests (RFQs)'], ['Quotation','Quotations'], ['Marketplace','The Marketplace'],
  ['Financial','Fees & Payments'], ['Smart Engine','The Smart Engine'], ['Technical','Technical & Standards'],
  ['Documents','Documents'], ['Security','Security'], ['Integrations','Integrations'],
  ['Operations','How Things Work'], ['Company Policies','Policies'], ['Future Vision','Our Vision'],
];
const HEADER=`<header class="site"><div class="wrap"><a class="brand" href="/"><img src="${ASSET}/qd_lockup_light.png?v=2" alt="QuotesDone" style="height:26px;width:auto;display:block"></a><nav class="snav"><a href="/services/">Services</a><a href="/blog/">Blog</a><a href="/faq/">FAQ</a><a href="/about/">About</a><a href="/contact/">Contact</a></nav><a class="cta" href="/app">Get free quotes</a></div></header>`;

Deno.serve(async () => {
  let I18N=''; try{ I18N = await (await fetch(ASSET+'/i18n_chrome.html')).text(); }catch(_e){ I18N=''; }
  const { data: rows } = await admin.from('company_faq').select('section,sort,question,answer')
    .eq('status','approved').eq('public', true).order('sort',{ascending:true}).order('id',{ascending:true});
  const bySection: Record<string, any[]> = {};
  for (const r of (rows||[])) (bySection[r.section] = bySection[r.section] || []).push(r);
  const orderedKeys = ORDER.map(o=>o[0]).filter(k=>bySection[k]);
  for (const k of Object.keys(bySection)) if (!orderedKeys.includes(k)) orderedKeys.push(k);
  const titleOf: Record<string,string> = Object.fromEntries(ORDER);
  let sections = '';
  for (const key of orderedKeys){
    const items = bySection[key] || []; const title = titleOf[key] || key; let qa = '';
    for (const it of items){ qa += `<details class="qa"><summary>${esc(it.question)}</summary><div class="a">${esc(it.answer)}</div></details>`; }
    sections += `<section class="sec"><h2>${esc(title)}</h2>${qa}</section>`;
  }
  const total = (rows||[]).length;
  const faqLd = JSON.stringify({ '@context':'https://schema.org','@type':'FAQPage','mainEntity': (rows||[]).map((r:any)=>({ '@type':'Question','name':String(r.question||''),'acceptedAnswer':{ '@type':'Answer','text':String(r.answer||'') } })) }).replace(/</g, String.fromCharCode(92)+'u003c');

  const html = `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>FAQ — QuotesDone</title>
<meta name="description" content="Frequently asked questions about QuotesDone — the UAE anonymous B2B quotation marketplace. Fees, matching, suppliers, customers, security and more.">
<link rel="canonical" href="https://quotesdone.com/faq/">
<meta property="og:type" content="website"><meta property="og:title" content="FAQ — QuotesDone"><meta property="og:url" content="https://quotesdone.com/faq/"><meta property="og:image" content="${ASSET}/qd_mark.png">
<script type="application/ld+json">${faqLd}</script>
<link rel="icon" href="${ASSET}/favicon.ico">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Sora:wght@500;600;700;800&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
<style>
:root{--bg:#05121A;--bg2:#0A1E27;--panel:rgba(255,255,255,.05);--line:rgba(255,255,255,.10);--line2:rgba(255,255,255,.18);--t:#EAF4F2;--muted:#9DB2B2;--faint:#5E7475;--teal:#2DD4BF;--teal2:#14B8A6;--gold:#E7C579;--r:16px;--maxw:900px}
*{box-sizing:border-box}html{scroll-behavior:smooth;-webkit-text-size-adjust:100%}
body{margin:0;background:radial-gradient(1000px 620px at 82% -14%,rgba(45,212,191,.16),transparent),radial-gradient(760px 520px at 4% 20%,rgba(231,197,121,.07),transparent),linear-gradient(180deg,var(--bg),var(--bg2));color:var(--t);font-family:Inter,system-ui,-apple-system,Segoe UI,Arial,sans-serif;line-height:1.6;min-height:100vh}
a{color:var(--teal);text-decoration:none}a:hover{color:var(--teal2)}
.wrap{max-width:1120px;margin:0 auto;padding:0 20px}
header.site{position:sticky;top:0;z-index:30;background:rgba(5,18,26,.72);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);border-bottom:1px solid var(--line)}
header.site .wrap{display:flex;align-items:center;gap:16px;padding:13px 20px}
.brand{display:inline-flex;align-items:center}
.snav{display:flex;gap:20px;margin-left:6px}
.snav a{color:var(--muted);font-size:14px;font-weight:500}.snav a:hover{color:#fff}
@media(max-width:680px){.snav{display:none}}
.cta{margin-left:auto;background:linear-gradient(135deg,var(--teal),var(--teal2));color:#04121a;font-weight:700;padding:10px 18px;border-radius:12px;box-shadow:0 10px 26px -12px rgba(45,212,191,.7)}
.cta:hover{color:#04121a;filter:brightness(1.05)}
.fwrap{max-width:var(--maxw);margin:0 auto;padding:0 20px}
.hero{padding:54px 0 22px;text-align:center}
.hero h1{font-family:Sora;font-weight:800;font-size:clamp(30px,5vw,46px);margin:0 0 10px;letter-spacing:-.02em;color:#fff}
.hero p{color:var(--muted);max-width:620px;margin:0 auto;font-size:17px}
.search{margin:26px auto 8px;max-width:560px;position:relative}
.search input{width:100%;padding:14px 16px 14px 44px;border-radius:var(--r);border:1px solid var(--line2);background:var(--panel);color:var(--t);font-size:15px;font-family:inherit;outline:none}
.search input:focus{border-color:var(--teal)}
.search svg{position:absolute;left:15px;top:50%;transform:translateY(-50%);opacity:.6}
.content{padding:20px 0 80px}
.sec{margin:34px 0 0}
.sec h2{font-family:Sora;font-weight:700;font-size:14px;text-transform:uppercase;letter-spacing:.12em;color:var(--gold);margin:0 0 12px;padding-bottom:8px;border-bottom:1px solid var(--line)}
details.qa{border:1px solid var(--line);border-radius:14px;background:var(--panel);margin:10px 0;overflow:hidden}
details.qa[open]{border-color:var(--line2)}
details.qa summary{cursor:pointer;list-style:none;padding:16px 46px 16px 18px;font-weight:600;font-size:16px;position:relative;color:var(--t)}
details.qa summary::-webkit-details-marker{display:none}
details.qa summary:after{content:'+';position:absolute;right:18px;top:50%;transform:translateY(-50%);color:var(--teal);font-size:22px;font-weight:400}
details.qa[open] summary:after{content:'–'}
details.qa .a{padding:0 18px 18px;color:var(--muted);font-size:15px}
.nomatch{display:none;text-align:center;color:var(--muted);padding:40px 0}
footer.ft{border-top:1px solid var(--line);padding:26px 0;color:var(--faint);font-size:13px}
.footin{display:flex;flex-wrap:wrap;gap:14px;justify-content:space-between;align-items:center}
.footin a{color:var(--muted)}
</style></head><body>
${HEADER}
<div class="fwrap">
  <div class="hero">
    <h1>Frequently asked questions</h1>
    <p>Everything about how QuotesDone works — matching, fees, suppliers, customers, security and more. ${total} answers, kept up to date.</p>
    <div class="search"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#9DB2B2" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg><input id="q" type="search" placeholder="Search the FAQ…" autocomplete="off"></div>
  </div>
  <div class="content">${sections}<div class="nomatch" id="nm">No answers match your search.</div></div>
</div>
<footer class="ft"><div class="fwrap footin"><span>© ${new Date().getFullYear()} QuotesDone Technologies — Dubai, UAE</span><span><a href="/">Home</a> &nbsp;·&nbsp; <a href="/terms/">Legal &amp; Terms</a></span></div></footer>
<script>
(function(){
  var q=document.getElementById('q'), nm=document.getElementById('nm');
  var items=[].slice.call(document.querySelectorAll('details.qa'));
  var secs=[].slice.call(document.querySelectorAll('.sec'));
  q.addEventListener('input',function(){
    var v=q.value.trim().toLowerCase(); var any=false;
    items.forEach(function(d){
      var t=(d.querySelector('summary').textContent+' '+d.querySelector('.a').textContent).toLowerCase();
      var hit=!v||t.indexOf(v)>-1; d.style.display=hit?'':'none'; if(hit)any=true;
      if(v&&hit){d.setAttribute('open','')}else if(v){d.removeAttribute('open')}
    });
    secs.forEach(function(s){var vis=0;s.querySelectorAll('details.qa').forEach(function(d){if(d.style.display!=='none')vis++});s.style.display=vis?'':'none'});
    nm.style.display=any?'none':'block';
  });
})();
</script>
${I18N}
</body></html>`;
  return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=300' } });
});