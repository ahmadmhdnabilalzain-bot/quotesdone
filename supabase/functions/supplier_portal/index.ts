// supplier_portal — advanced supplier dashboard API. Supplier-authed (own leads row via claimed_by).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
function b64ToBytes(b64:string){ const bin=atob(String(b64).replace(/^data:[^;]+;base64,/,'')); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
async function sign(bucket:string, path:string|null){ if(!path) return null; try{ const { data } = await admin.storage.from(bucket).createSignedUrl(path, 3600); return data?.signedUrl || null; }catch{ return null; } }
const DOC_KINDS: Record<string,{ pathCol:string; expCol:string|null }> = {
  iso: { pathCol:'iso_doc_path', expCol:'iso_expiry' },
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const { data: sup } = await admin.from('leads').select('id,company_name,approval_status,registration_status,license_expiry,name_corrected_from').eq('claimed_by', email).maybeSingle();
    if (!sup) return J({ error: 'no_company', hint: 'claim your company first' }, 400);
    const b = await req.json().catch(() => ({} as any));
    const action = b.action;

    async function buildAlerts(){
      const out: any[] = [];
      const { data: exp } = await admin.rpc('fn_supplier_expiries', { p_supplier_id: sup.id });
      for (const e of (exp || [])) {
        if (e.status === 'expired' || e.status === 'expiring') {
          out.push({ kind:'doc_expiry', severity: e.status==='expired'?'high':'medium',
            title: e.doc + (e.status==='expired'?' has expired':' expires soon'),
            detail: 'Expiry ' + e.expiry + ' — ' + (e.days_left<0?('overdue by '+Math.abs(e.days_left)+' days'):(e.days_left+' days left')) + '. Upload a renewed copy to stay eligible.',
            action:'documents' });
        }
      }
      const { data: matches } = await admin.from('inquiry_matches').select('inquiry_id').eq('supplier_id', sup.id);
      const mids = [...new Set((matches || []).map((m:any)=>m.inquiry_id))];
      if (mids.length) {
        const { data: myq } = await admin.from('quotes').select('inquiry_id').eq('supplier_id', sup.id);
        const quoted = new Set((myq || []).map((x:any)=>x.inquiry_id));
        const { data: openInq } = await admin.from('inquiries').select('id').in('id', mids).in('status', ['sent','open','active','collecting','live','quoted']);
        const openIds = (openInq || []).map((x:any)=>x.id).filter((id:any)=>!quoted.has(id));
        if (openIds.length) out.push({ kind:'new_rfq', severity:'medium', count: openIds.length, title: openIds.length+' new RFQ'+(openIds.length>1?'s':'')+' waiting for your quote', detail:'Open requests matched to your capabilities that you have not quoted yet.', action:'inbox' });
      }
      const { count: drafts } = await admin.from('quotes').select('id',{count:'exact',head:true}).eq('supplier_id', sup.id).eq('status','draft');
      if (drafts) out.push({ kind:'draft_quote', severity:'low', count: drafts, title: drafts+' draft quote'+(drafts>1?'s':'')+' to complete', detail:'Add the missing details so we can send them to customers.', action:'inbox' });
      return out;
    }

    if (action === 'overview') {
      const { data: stats, error } = await admin.rpc('fn_supplier_stats', { p_supplier_id: sup.id });
      if (error) return J({ error: error.message }, 500);
      const [{ count: activeMatches }, alerts] = await Promise.all([
        admin.from('inquiry_matches').select('id', { count:'exact', head:true }).eq('supplier_id', sup.id),
        buildAlerts(),
      ]);
      return J({ ok:true, supplier:{ id:sup.id, company_name:sup.company_name, approval_status:sup.approval_status, registration_status:sup.registration_status, license_expiry: sup.license_expiry || null, name_corrected: !!sup.name_corrected_from }, stats, active_matches: activeMatches || 0, alerts, alerts_count: alerts.length });
    }

    if (action === 'notifications') {
      const alerts = await buildAlerts();
      const { data: feed } = await admin.from('notifications').select('id,type,subject,body,created_at,inquiry_id').or(`to_email.eq.${email},and(to_role.eq.supplier,lead_id.eq.${sup.id})`).order('created_at',{ ascending:false }).limit(40);
      return J({ ok:true, alerts, alerts_count: alerts.length, feed: feed || [] });
    }

    if (action === 'documents') {
      const { data: l } = await admin.from('leads').select('license_doc_path,license_expiry,iso_doc_path,iso_expiry,company_profile_doc_path,catalog_doc_paths').eq('id', sup.id).maybeSingle();
      const cats: string[] = Array.isArray(l?.catalog_doc_paths) ? (l!.catalog_doc_paths as string[]) : [];
      const catUrls: string[] = [];
      for (const p of cats.slice(0, 12)) { const u = await sign('supplier-docs', p); if (u) catUrls.push(u); }
      const docs = [
        { key:'license', label:'Trade license', path:l?.license_doc_path, expiry:l?.license_expiry, url: await sign('supplier-docs', l?.license_doc_path) },
        { key:'profile', label:'Company profile', path:l?.company_profile_doc_path, expiry:null, url: await sign('supplier-docs', l?.company_profile_doc_path) },
        { key:'catalogs', label:'Catalogues', path: cats.length ? 'catalogs' : null, expiry:null, count: cats.length, urls: catUrls, url: null },
        { key:'iso', label:'ISO certification', path:l?.iso_doc_path, expiry:l?.iso_expiry, url: await sign('supplier-docs', l?.iso_doc_path) },
      ];
      const expiries = await admin.rpc('fn_supplier_expiries', { p_supplier_id: sup.id });
      return J({ ok:true, documents: docs, expiries: expiries.data || [] });
    }

    if (action === 'save_documents') {
      const items = Array.isArray(b.items) ? b.items : [];
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      const saved: string[] = [];
      let catAppend: string[] = [];
      for (const it of items) {
        const kindStr = String(it.kind || '');
        if (kindStr === 'catalogs') {
          if (it.original_b64) {
            try { const u8 = b64ToBytes(String(it.original_b64)); const fn = String(it.filename || 'catalog').replace(/[^A-Za-z0-9._-]/g,'_').slice(0,120); const p = `catalogs/${sup.id}/${Date.now()}_${fn}`; await admin.storage.from('supplier-docs').upload(p, u8, { contentType: it.mime || 'application/octet-stream', upsert:true }); catAppend.push(p); saved.push('catalogs'); } catch (_e) { /* */ }
          }
          continue;
        }
        const kind = DOC_KINDS[kindStr]; if (!kind) continue;
        if (it.original_b64) {
          try { const u8 = b64ToBytes(String(it.original_b64)); const fn = String(it.filename || it.kind).replace(/[^A-Za-z0-9._-]/g,'_').slice(0,120); const p = `certs/${sup.id}/${Date.now()}_${fn}`; await admin.storage.from('supplier-docs').upload(p, u8, { contentType: it.mime || 'application/octet-stream', upsert:true }); upd[kind.pathCol] = p; } catch (_e) { /* */ }
        }
        if (kind.expCol && it.expiry) upd[kind.expCol] = String(it.expiry).slice(0,10);
        saved.push(kindStr);
      }
      if (catAppend.length) {
        const { data: cur } = await admin.from('leads').select('catalog_doc_paths').eq('id', sup.id).maybeSingle();
        const existing: string[] = Array.isArray(cur?.catalog_doc_paths) ? (cur!.catalog_doc_paths as string[]) : [];
        upd.catalog_doc_paths = [...existing, ...catAppend].slice(0, 20);
      }
      if (Object.keys(upd).length > 1) await admin.from('leads').update(upd).eq('id', sup.id);
      return J({ ok:true, saved });
    }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
