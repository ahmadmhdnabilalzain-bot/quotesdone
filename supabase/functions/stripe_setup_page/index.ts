// stripe_setup_page - serves the private Stripe key-entry form (public GET). The form posts keys to stripe_setup (token-gated).
const ANON='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0ZGJsd2xkamtjZ2p2bXFrYmVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3ODU1NDYsImV4cCI6MjA5NjM2MTU0Nn0.cF9ZR_Qo1YBhLvhTLS8aANlYb6c9rTsuQS6kLxGw_Bo';
const FN='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/stripe_setup';
const HTML=`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Stripe setup — QuotesDone</title>
<style>body{font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;background:#f4f8f7;color:#0f2f2b;margin:0}.w{max-width:520px;margin:0 auto;padding:24px 16px}.c{background:#fff;border:1px solid #e8efee;border-radius:14px;padding:22px}h1{font-size:20px;margin:0 0 6px}.m{color:#5b6b68;font-size:13px}label{display:block;font-weight:600;font-size:13px;margin:14px 0 4px}input{width:100%;padding:11px 12px;border:1px solid #cdd8d6;border-radius:9px;font-size:14px}button{background:#0d9488;color:#fff;border:0;border-radius:9px;padding:12px 18px;font-weight:700;font-size:14px;cursor:pointer;margin-top:16px}button.s{background:#eef4f3;color:#0f2f2b}#o{margin-top:14px;font-size:13px;white-space:pre-wrap;line-height:1.6}.ok{color:#0a7d68}.err{color:#b42318}</style></head>
<body><div class="w"><div class="c"><h1>QuotesDone — Stripe live keys</h1>
<div class="m">Paste your keys from Stripe Dashboard &rarr; Developers &rarr; API keys. Stored securely server-side; never shown back. Use <b>Live</b> keys (sk_live_ / pk_live_). Add <code>?t=YOUR_TOKEN</code> to the URL.</div>
<label>Secret key (sk_live_...)</label><input id="sk" type="password" autocomplete="off" placeholder="sk_live_...">
<label>Publishable key (pk_live_..., optional)</label><input id="pk" type="password" autocomplete="off" placeholder="pk_live_...">
<label>Webhook signing secret (whsec_..., optional)</label><input id="wh" type="password" autocomplete="off" placeholder="whsec_...">
<button id="save">Save keys</button> <button id="chk" class="s">Check status</button>
<div id="o"></div></div></div>
<script>
var FN=${JSON.stringify(FN)},A=${JSON.stringify(ANON)};
function tok(){return new URLSearchParams(location.search).get('t')||'';}
async function call(p){var r=await fetch(FN,{method:'POST',headers:{'Authorization':'Bearer '+A,'apikey':A,'Content-Type':'application/json'},body:JSON.stringify(Object.assign({token:tok()},p))});return r.json();}
function show(j){var o=document.getElementById('o');if(!j||j.ok===false){o.innerHTML="<span class='err'>"+((j&&j.error)||'Error')+"</span>";return;}var L=[];if(j.saved)L.push("<span class='ok'>Saved: "+j.saved.join(', ')+"</span>");if(j.warnings&&j.warnings.length)L.push("<span class='err'>"+j.warnings.join('<br>')+"</span>");if(j.key_mode)L.push('Key mode: <b>'+j.key_mode+'</b>');if(j.charges_enabled!=null)L.push('Live charges enabled: <b>'+j.charges_enabled+'</b>');if(j.payouts_enabled!=null)L.push('Payouts enabled: <b>'+j.payouts_enabled+'</b>');if(j.country)L.push('Country: '+j.country+' '+((j.default_currency||'').toUpperCase()));o.innerHTML=L.join('<br>');}
document.getElementById('save').onclick=async function(){this.disabled=true;this.textContent='Saving...';show(await call({action:'save',sk:document.getElementById('sk').value,pk:document.getElementById('pk').value,whsec:document.getElementById('wh').value}));this.disabled=false;this.textContent='Save keys';};
document.getElementById('chk').onclick=async function(){show(await call({action:'status'}));};
</script></body></html>`;
Deno.serve(()=> new Response(HTML,{ headers:{ 'Content-Type':'text/html; charset=utf-8' } }));
