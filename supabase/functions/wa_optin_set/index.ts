// wa_optin_set - records a user's WhatsApp opt-in consent (service messages only). Sets wa_optin on customers/leads by email.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin':'*', 'Access-Control-Allow-Headers':'authorization, content-type, apikey', 'Access-Control-Allow-Methods':'POST, OPTIONS' };
const J = (o:unknown,s=200)=>new Response(JSON.stringify(o),{status:s,headers:{'Content-Type':'application/json',...CORS}});
Deno.serve(async (req)=>{
  if (req.method==='OPTIONS') return new Response('ok',{headers:CORS});
  try{
    const b = await req.json().catch(()=>({} as any));
    const email = String(b.email||'').trim().toLowerCase();
    const kind = b.user_kind==='supplier' ? 'supplier' : 'customer';
    const optin = b.wa_optin === true;
    if(!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return J({ error:'bad_email' },400);
    if(kind==='customer'){
      const { data } = await admin.from('customers').update({ wa_optin:optin }).eq('email',email).select('id').maybeSingle();
      return J({ ok:true, updated: !!data, wa_optin:optin });
    } else {
      const { data } = await admin.from('leads').update({ wa_optin:optin }).eq('claimed_by',email).select('id').maybeSingle();
      return J({ ok:true, updated: !!data, wa_optin:optin });
    }
  }catch(e){ return J({ error:String((e as Error)?.message||e) },500); }
});
