// wa_optin_set - records a user's WhatsApp opt-in consent (service messages only). Sets wa_optin on customers/leads by email.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin':'*', 'Access-Control-Allow-Headers':'authorization, content-type, apikey', 'Access-Control-Allow-Methods':'POST, OPTIONS' };
const J = (o:unknown,s=200)=>new Response(JSON.stringify(o),{status:s,headers:{'Content-Type':'application/json',...CORS}});
async function sec(k:string){ const { data } = await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string | undefined; }
Deno.serve(observe('wa_optin_set', async (req) => {
  if (req.method==='OPTIONS') return new Response('ok',{headers:CORS});
  try{
    const b = await req.json().catch(()=>({} as any));
    const email = String(b.email||'').trim().toLowerCase();
    const kind = b.user_kind==='supplier' ? 'supplier' : 'customer';
    const optin = b.wa_optin === true;
    if(!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return J({ error:'bad_email' },400);
    // UNAUTHENTICATED CONSENT WRITES 27 Jul 2026 -------------------------------------------------
    // This function had no authentication of any kind. verify_jwt=true on the gateway only proves
    // the caller holds SOME project JWT, and the anon key is one - it ships in the public browser
    // bundle. So anyone could POST {email:<any supplier>, wa_optin:false} to silently kill that
    // supplier's WhatsApp notifications, or wa_optin:true to forge a consent record we would then
    // rely on as our PDPL/TDRA evidence that the person agreed to be messaged. Consent we cannot
    // attribute is worse than no consent. Accept only the inbound secret (server-to-server) or a
    // signed-in user changing their OWN row; the portal already sends the user's session token.
    const jwt = (req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called. The
    // `b.__secret &&` short-circuit is kept deliberately, so a signed-in user changing their own
    // consent row does not pay for a verifier round trip.
    let actor = '';
    if (b.__secret && (await requireInternal(admin, b.__secret, 'wa_optin_set')).ok) actor = 'secret';
    else { const { data: au } = await admin.auth.getUser(jwt).catch(()=>({ data:{ user:null } } as any)); const ue = String(au?.user?.email||'').toLowerCase(); if (ue && ue === email) actor = 'self'; }
    if (!actor) return J({ error:'unauthorized' },401);
    if(kind==='customer'){
      const { data } = await admin.from('customers').update({ wa_optin:optin }).eq('email',email).select('id').maybeSingle();
      return J({ ok:true, updated: !!data, wa_optin:optin });
    } else {
      const { data } = await admin.from('leads').update({ wa_optin:optin }).eq('claimed_by',email).select('id').maybeSingle();
      return J({ ok:true, updated: !!data, wa_optin:optin });
    }
  }catch(e){ return J({ error:String((e as Error)?.message||e) },500); }
}));
