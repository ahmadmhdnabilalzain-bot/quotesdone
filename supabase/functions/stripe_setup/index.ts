// stripe_setup - token-gated endpoint for the founder to save LIVE Stripe keys directly (values never returned/logged).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin':'*', 'Access-Control-Allow-Headers':'authorization, content-type, apikey', 'Access-Control-Allow-Methods':'POST, OPTIONS' };
const J=(o:unknown,s=200)=>new Response(JSON.stringify(o),{status:s,headers:{'Content-Type':'application/json',...CORS}});
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string)||''; }
async function put(k:string,v:string){ await admin.from('app_secrets').upsert({ key:k, value:v }, { onConflict:'key' }); }
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
