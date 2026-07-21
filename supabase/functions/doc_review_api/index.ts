// doc_review_api - admin reviews AI-classified inbound supplier documents; approve attaches to profile.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type':'application/json', ...CORS } });
const DOC_COL: Record<string,[string,string]> = { trade_license:['license_doc_path','license_doc_name'], vat_trn:['license_doc_path','license_doc_name'], bank_letter:['iban_doc_path','iban_doc_name'], company_profile:['egr_doc_path','egr_doc_name'], catalogue:['egr_doc_path','egr_doc_name'] };
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user?.email) return J({ error:'unauthorized' }, 401);
    const { data: al } = await admin.from('app_secrets').select('value').eq('key','admin_emails').maybeSingle();
    const admins = String(al?.value||'management@quotesdone.com').toLowerCase().split(',').map(s=>s.trim());
    if (!admins.includes(user.email.toLowerCase())) return J({ error:'forbidden' }, 403);
    const body = await req.json().catch(()=>({})); const action = String(body.action||'queue');
    if (action === 'queue') {
      const { data } = await admin.from('doc_reviews').select('*').eq('status','pending').order('created_at',{ascending:false}).limit(50);
      const out = [] as any[];
      for (const r of data||[]) {
        let url=null; try { const { data: s } = await admin.storage.from('supplier-docs').createSignedUrl(r.file_path, 3600); url=s?.signedUrl||null; } catch {}
        let company=null; if (r.lead_id){ const { data: l } = await admin.from('leads').select('company_name').eq('id',r.lead_id).maybeSingle(); company=l?.company_name||null; }
        out.push({ ...r, company, file_url: url });
      }
      return J({ queue: out });
    }
    if (action === 'approve') {
      const id = Number(body.id); if(!id) return J({error:'id required'},400);
      const { data: r } = await admin.from('doc_reviews').select('*').eq('id',id).maybeSingle();
      if(!r) return J({error:'not found'},404);
      if (r.lead_id && r.ai_category && DOC_COL[r.ai_category]) { const [pc,nc]=DOC_COL[r.ai_category]; const upd:any={}; upd[pc]=r.file_path; upd[nc]=r.file_name; await admin.from('leads').update(upd).eq('id',r.lead_id); }
      await admin.from('doc_reviews').update({ status:'approved', decided_by:user.email, decided_at:new Date().toISOString() }).eq('id',id);
      return J({ ok:true, attached: !!(r.lead_id && DOC_COL[r.ai_category]) });
    }
    if (action === 'reject') { const id=Number(body.id); if(!id) return J({error:'id required'},400); await admin.from('doc_reviews').update({ status:'rejected', decided_by:user.email, decided_at:new Date().toISOString() }).eq('id',id); return J({ ok:true }); }
    return J({ error:'unknown action' }, 400);
  } catch (e) { return J({ error:String((e as Error)?.message||e) }, 500); }
});
