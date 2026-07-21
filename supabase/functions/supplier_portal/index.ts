// supplier_portal — advanced supplier dashboard API. Supplier-authed (own leads row via claimed_by).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
function b64ToBytes(b64:string){ const bin=atob(String(b64).replace(/^data:[^;]+;base64,/,'')); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
async function sign(bucket:string, path:string|null){ if(!path) return null; try{ const { data } = await admin.storage.from(bucket).createSignedUrl(path, 3600); return data?.signedUrl || null; }catch{ return null; } }
// Every document a supplier can hold, in the order the portal shows them.
//
// Until v4 this map contained ONLY `iso`, which meant save_documents could write an ISO
// certificate and nothing else. The documents tab rendered the trade licence and company
// profile as read-only, and VAT / insurance / manufacturer authorisation had no UI at all.
// The effect was a dead end: fn_supplier_expiries raises "Insurance has expired - upload a
// renewed copy" and routes the supplier to a tab with no insurance field. Worse, an
// established supplier could never replace an expired trade licence, because the only
// licence upload lives in ProfileForm, which renders only while the account still has no
// company. Driving both read and write off one map closes that.
//
// `folder` keeps storage tidy and mirrors what save_profile already writes.
const DOC_KINDS: Record<string, { pathCol: string; nameCol?: string; expCol: string | null; label: string; folder: string; hint: string }> = {
  license:      { pathCol:'license_doc_path',           nameCol:'license_doc_name', expCol:'license_expiry',            label:'Trade licence',              folder:'licence',   hint:'Required. Your current DED / free-zone trade licence.' },
  profile:      { pathCol:'company_profile_doc_path',                               expCol:null,                        label:'Company profile',            folder:'profile',   hint:'Your company introduction deck or PDF. Shown to customers after a reveal.' },
  vat:          { pathCol:'vat_doc_path',                                           expCol:null,                        label:'VAT certificate',            folder:'certs',     hint:'Your TRN certificate. Needed before you can invoice with VAT.' },
  insurance:    { pathCol:'insurance_doc_path',                                     expCol:'insurance_expiry',          label:'Insurance',                  folder:'certs',     hint:'Public liability or contractor all-risk cover.' },
  iso:          { pathCol:'iso_doc_path',                                           expCol:'iso_expiry',                label:'ISO certification',          folder:'certs',     hint:'Any ISO certificate you hold. Strengthens your capability score.' },
  manufacturer: { pathCol:'manufacturer_auth_doc_path',                             expCol:'manufacturer_auth_expiry',  label:'Manufacturer authorisation', folder:'certs',     hint:'Authorised-dealer letters from the brands you carry.' },
  egr:          { pathCol:'egr_doc_path',               nameCol:'egr_doc_name',     expCol:null,                        label:'Establishment card',         folder:'certs',     hint:'Your immigration establishment card (EGR).' },
  iban:         { pathCol:'iban_doc_path',              nameCol:'iban_doc_name',    expCol:null,                        label:'Bank details (IBAN)',        folder:'certs',     hint:'Bank letter confirming your IBAN. Used to pay you.' },
};
const DOC_ORDER = ['license','profile','catalogs','vat','insurance','iso','manufacturer','egr','iban'];

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
      // Column list is derived from DOC_KINDS so adding a document type here needs no edit below.
      const cols = new Set<string>(['catalog_doc_paths']);
      for (const k of Object.values(DOC_KINDS)) { cols.add(k.pathCol); if (k.nameCol) cols.add(k.nameCol); if (k.expCol) cols.add(k.expCol); }
      const { data: l } = await admin.from('leads').select([...cols].join(',')).eq('id', sup.id).maybeSingle();
      const row = (l || {}) as Record<string, unknown>;

      const cats: string[] = Array.isArray(row.catalog_doc_paths) ? (row.catalog_doc_paths as string[]) : [];
      const catalogues: { path: string; name: string; url: string | null }[] = [];
      for (const p of cats.slice(0, 20)) {
        catalogues.push({ path: p, name: String(p).split('/').pop() || 'Catalogue', url: await sign('supplier-docs', p) });
      }

      const today = new Date(); today.setHours(0, 0, 0, 0);
      const docs: Record<string, unknown>[] = [];
      for (const key of DOC_ORDER) {
        if (key === 'catalogs') {
          docs.push({ key:'catalogs', label:'Catalogues', hint:'Product or project catalogues. Upload as many as you like - new files are added, never replaced.',
            path: cats.length ? 'catalogs' : null, expiry:null, url:null, name:null, required:false,
            count: cats.length, urls: catalogues.map((c) => c.url).filter(Boolean), items: catalogues,
            status: cats.length ? 'on_file' : 'missing' });
          continue;
        }
        const k = DOC_KINDS[key]; if (!k) continue;
        const path = (row[k.pathCol] as string) || null;
        const expiry = k.expCol ? ((row[k.expCol] as string) || null) : null;
        // Filename falls back to the stored path's tail so the supplier always sees which file is on record.
        const name = (k.nameCol ? (row[k.nameCol] as string) : null) || (path ? String(path).split('/').pop() : null) || null;
        let status = 'missing';
        if (path) {
          status = 'on_file';
          if (expiry) {
            const d = Math.round((new Date(expiry).getTime() - today.getTime()) / 864e5);
            status = d < 0 ? 'expired' : d <= 30 ? 'expiring' : 'valid';
          }
        }
        docs.push({ key, label: k.label, hint: k.hint, path, name, expiry, has_expiry: !!k.expCol,
          required: key === 'license', status, url: await sign('supplier-docs', path) });
      }

      const required = docs.filter((d) => d.required);
      const complete = docs.filter((d) => d.status !== 'missing').length;
      const expiries = await admin.rpc('fn_supplier_expiries', { p_supplier_id: sup.id });
      return J({ ok:true, documents: docs, expiries: expiries.data || [],
        summary: { total: docs.length, on_file: complete, missing: docs.length - complete,
          required_missing: required.filter((d) => d.status === 'missing').length,
          attention: docs.filter((d) => d.status === 'expired' || d.status === 'expiring').length } });
    }

    if (action === 'save_documents') {
      const items = Array.isArray(b.items) ? b.items : [];
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      const saved: string[] = [];
      const failed: { kind: string; reason: string }[] = [];
      let catAppend: string[] = [];
      for (const it of items) {
        const kindStr = String(it.kind || '');
        if (kindStr === 'catalogs') {
          if (it.original_b64) {
            try {
              const u8 = b64ToBytes(String(it.original_b64));
              const fn = String(it.filename || 'catalog').replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 120);
              const p = `catalogs/${sup.id}/${Date.now()}_${fn}`;
              const { error: upErr } = await admin.storage.from('supplier-docs').upload(p, u8, { contentType: it.mime || 'application/octet-stream', upsert: true });
              if (upErr) { failed.push({ kind: 'catalogs', reason: upErr.message }); continue; }
              catAppend.push(p); saved.push('catalogs');
            } catch (e) { failed.push({ kind: 'catalogs', reason: String((e as Error)?.message || e).slice(0, 200) }); }
          }
          continue;
        }
        const kind = DOC_KINDS[kindStr]; if (!kind) continue;
        if (it.original_b64) {
          // Previously any upload failure was swallowed and the kind was still reported as
          // saved, so a supplier could be told their trade licence was on file when the
          // storage write had failed. Failures are now returned to the caller.
          try {
            const u8 = b64ToBytes(String(it.original_b64));
            const clean = String(it.filename || kindStr).replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 120);
            const p = `${kind.folder}/${sup.id}/${Date.now()}_${clean}`;
            const { error: upErr } = await admin.storage.from('supplier-docs').upload(p, u8, { contentType: it.mime || 'application/octet-stream', upsert: true });
            if (upErr) { failed.push({ kind: kindStr, reason: upErr.message }); continue; }
            upd[kind.pathCol] = p;
            if (kind.nameCol) upd[kind.nameCol] = String(it.filename || clean).slice(0, 200);
          } catch (e) { failed.push({ kind: kindStr, reason: String((e as Error)?.message || e).slice(0, 200) }); continue; }
        }
        if (kind.expCol && it.expiry) upd[kind.expCol] = String(it.expiry).slice(0, 10);
        saved.push(kindStr);
      }
      if (catAppend.length) {
        const { data: cur } = await admin.from('leads').select('catalog_doc_paths').eq('id', sup.id).maybeSingle();
        const existing: string[] = Array.isArray(cur?.catalog_doc_paths) ? (cur!.catalog_doc_paths as string[]) : [];
        upd.catalog_doc_paths = [...existing, ...catAppend].slice(0, 20);
      }
      if (Object.keys(upd).length > 1) await admin.from('leads').update(upd).eq('id', sup.id);
      return J({ ok:true, saved, failed });
    }

    // Why am I not being matched?
    //
    // Every check below mirrors a real clause in match_suppliers_kw. Nothing here is
    // advisory dressed up as a rule, and nothing that genuinely gates matching is omitted,
    // because a supplier acting on this will conclude they have done everything needed.
    //
    // Deliberately NOT listed as blocking: document expiry. fn_supplier_expiries raises
    // alerts saying "upload a renewed copy to stay eligible", but match_suppliers_kw has no
    // expiry clause at all - an expired licence does not currently affect matching. Claiming
    // otherwise here would repeat that false promise.
    if (action === 'eligibility') {
      const { data: l } = await admin.from('leads')
        .select('id,company_name,sector,categories,products,services,capability_summary,emirate,service_emirates,permanently_closed,banned,matching_blocked,registration_submitted_at,source,approval_status,license_doc_path,phone,email')
        .eq('id', sup.id).maybeSingle();
      const r = (l || {}) as Record<string, any>;
      const has = (v: unknown) => !!(v != null && String(v).trim() !== '');

      const blocking: any[] = [];
      if (r.permanently_closed === true) blocking.push({ code:'permanently_closed', title:'Your listing is marked permanently closed', detail:'We will not send you requests while this is set. Contact us if this is wrong.', fix:'contact' });
      if (r.banned === true) blocking.push({ code:'banned', title:'Your account is suspended', detail:'Suspended accounts are excluded from all matching. Contact us to resolve it.', fix:'contact' });
      if (r.matching_blocked === true) blocking.push({ code:'matching_blocked', title:'Matching is switched off for your account', detail:'This is set manually by our team. Contact us to have it reviewed.', fix:'contact' });
      const registered = !!r.registration_submitted_at || r.source === 'self_registered' || String(r.approval_status || '') === 'approved';
      if (!registered) blocking.push({ code:'not_registered', title:'Your registration is not submitted', detail:'Only registered suppliers receive requests. Complete your company profile to submit it.', fix:'profile' });

      // Discoverability: the query matches on sector OR keywords across these four columns.
      // With all of them empty a supplier is unreachable no matter how many requests come in.
      const kwCols = ['products','services','categories','capability_summary'];
      const kwFilled = kwCols.filter((c) => has(r[c]));
      if (!has(r.sector) && kwFilled.length === 0) {
        blocking.push({ code:'undiscoverable', title:'Nothing describes what you supply', detail:'Requests are matched on your sector, products, services and categories. All of these are empty, so no request can reach you.', fix:'profile' });
      }

      const improving: any[] = [];
      if (!has(r.sector)) improving.push({ code:'no_sector', title:'Set your sector', detail:'A matching sector adds 2 points to your score on every request in that category, which decides who makes the shortlist.', fix:'profile' });
      for (const c of kwCols) if (!has(r[c])) improving.push({ code:'empty_' + c, title:'Add your ' + c.replace('_', ' '), detail:'Each keyword found here raises your match score. Empty fields cannot match anything.', fix:'profile' });
      if (!has(r.emirate) && !(Array.isArray(r.service_emirates) && r.service_emirates.length)) {
        improving.push({ code:'no_emirate', title:'Set the emirates you serve', detail:'Suppliers in the customer’s emirate are ranked above everyone else, so this is the single strongest ranking signal.', fix:'profile' });
      }
      if (!has(r.license_doc_path)) improving.push({ code:'no_licence', title:'Upload your trade licence', detail:'Required before your account can be approved.', fix:'documents' });
      if (!has(r.phone)) improving.push({ code:'no_phone', title:'Add a contact number', detail:'Customers cannot reach you after a reveal without one.', fix:'profile' });

      // Reach so far, measured rather than asserted.
      const [{ count: matched }, { count: quoted }] = await Promise.all([
        admin.from('inquiry_matches').select('id', { count:'exact', head:true }).eq('supplier_id', sup.id),
        admin.from('quotes').select('id', { count:'exact', head:true }).eq('supplier_id', sup.id),
      ]);

      return J({ ok:true,
        eligible: blocking.length === 0,
        blocking, improving,
        reach: { matched_requests: matched || 0, quotes_sent: quoted || 0, shortlist_size: 8 },
        note: 'Each request goes to a shortlist of up to 8 suppliers, ranked first by whether you serve the customer’s emirate, then by how well your listing matches what they asked for.' });
    }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
