// admin_insights — admin surface for marketplace analytics (#2) + fraud flags (#11) + supplier twin/reputation.
// Same admin auth as crm_pipeline: inbound __secret OR admin-email + valid MFA session.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function jwtClaims(t: string){ try{ const p=String(t||'').split('.')[1]; if(!p) return {} as any; const s=atob(p.replace(/-/g,'+').replace(/_/g,'/')); return JSON.parse(s); }catch(_e){ return {} as any; } }
async function mfaOk(sid: string){ if(!sid) return false; const { data } = await admin.from('admin_mfa_sessions').select('expires_at').eq('session_id', sid).gt('expires_at', new Date().toISOString()).maybeSingle(); return !!data; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    let who = 'secret'; let authed = false; let jwt = '';
    if (body.__secret && body.__secret === (await sec('inbound_secret'))) authed = true;
    if (!authed) {
      jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
      const { data: { user } } = await admin.auth.getUser(jwt);
      const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
      if (user?.email && allow.includes(user.email.toLowerCase())) { authed = true; who = user.email.toLowerCase(); }
    }
    if (!authed) return J({ error: 'forbidden — not an admin' }, 403);
    const action = String(body.action || '');
    const viaSecret = (who === 'secret');
    const sid = viaSecret ? '' : ((jwtClaims(jwt).session_id as string) || '');
    if (!viaSecret) { if (!(await mfaOk(sid))) return J({ error: 'mfa_required' }, 401); }

    if (action === 'marketplace_analytics') {
      const { data } = await admin.rpc('fn_marketplace_analytics');
      return J({ ok: true, analytics: data });
    }

    if (action === 'fraud_scan') { const { data } = await admin.rpc('fn_fraud_scan'); return J({ ok: true, result: data }); }

    if (action === 'fraud_list') {
      const st = String(body.status || 'open');
      let q = admin.from('fraud_flags').select('*');
      if (st !== 'all') q = q.eq('status', st);
      const { data } = await q.order('severity', { ascending: true }).order('created_at', { ascending: false }).limit(300);
      return J({ ok: true, flags: data || [] });
    }
    if (action === 'fraud_decide') {
      const kind = String(body.kind || ''), stype = String(body.subject_type || ''), sid2 = String(body.subject_id || ''), status = String(body.status || '');
      if (!kind || !stype || !sid2 || !['reviewed','dismissed','confirmed','open'].includes(status)) return J({ error: 'kind, subject_type, subject_id, status required' }, 400);
      const { error } = await admin.from('fraud_flags').update({ status, updated_at: new Date().toISOString() }).eq('kind', kind).eq('subject_type', stype).eq('subject_id', sid2);
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true });
    }

    if (action === 'supplier_intel') {  // twin + reputation for the CRM supplier drawer
      const id = Number(body.supplier_id || body.id); if (!id) return J({ error: 'supplier_id required' }, 400);
      const { data: twin } = await admin.from('supplier_twin').select('*').eq('supplier_id', id).maybeSingle();
      const { data: rep } = await admin.from('supplier_reputation').select('*').eq('supplier_id', id).maybeSingle();
      return J({ ok: true, twin: twin || null, reputation: rep || null });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
