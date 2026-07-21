import { createClient } from 'jsr:@supabase/supabase-js@2';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
const PROFILE_COLS = ['contact_name','signatory_name','emirates_id','phone','products','services','description','certifications','founded_year','company_type','company_size','trade_license_no','license_authority','license_expiry','trn','bank_name','bank_account_name','bank_iban','license_doc_path','iban_doc_path','egr_doc_path','egr_doc_name','egr_number'];
const YEAR_MS = 365 * 864e5;
const CONCLUDED = ['completed','closed','cancelled'];
// EVIDENCE FIX 19 Jul 2026 -----------------------------------------------------------------
// Terms acceptance here recorded WHEN (accepted_terms_at) and WHICH VERSION
// (accepted_terms_version) but not FROM WHERE. The leads.accepted_terms_ip column already
// existed and auth_api / kyc already populated it - supplier_api, the main registration
// surface, was the one path that did not.
//
// Why it matters: the non-response fine (3%) drives an automated collections -> legal
// escalation path. If a supplier disputes the fine, the platform must evidence that THIS
// party accepted THAT version of the terms at THAT time from THAT address. Timestamp plus
// version without an originating IP is materially weaker evidence.
//
// Same derivation as auth_api line 9 so the two paths produce comparable records.
function clientIp(req: Request): string { return (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || req.headers.get('cf-connecting-ip') || req.headers.get('x-real-ip') || ''; }
const clip = (v: unknown, n: number) => (v == null || String(v).trim() === '') ? null : String(v).slice(0, n);
const numOrNull = (v: unknown) => { const n = Number(v); return isFinite(n) && n !== 0 ? n : (isFinite(n) && String(v).trim() !== '' ? n : null); };
function ratingOf(l: Record<string, any>) { if (!l) return { value: null, count: 0, source: 'Google' }; const appN = Number(l.app_reviews || 0); if (appN > 0) return { value: l.app_rating != null ? Number(l.app_rating) : null, count: appN, source: 'QuotesDone' }; const g = l.rating ?? l.rating_maps; const gn = l.reviews ?? l.reviews_maps; return { value: g != null ? Number(g) : null, count: gn != null ? Number(gn) : 0, source: 'Google' }; }
async function secretVal(key: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', key).maybeSingle(); return data?.value || null; }
function b64ToBytes(b64:string){ const bin=atob(String(b64).replace(/^data:[^;]+;base64,/,'')); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
async function signedRedacted(path: string){ try { const { data } = await admin.storage.from('drawing-files').createSignedUrl(path, 3600); return data?.signedUrl || null; } catch { return null; } }
async function setRegistration(leadId: number) {
  const { data: cfg } = await admin.from('pricing_config').select('supplier_free_count,supplier_reg_fee').eq('id', 1).maybeSingle();
  const { data: cnt } = await admin.rpc('registered_supplier_count');
  const free = (Number(cnt) || 0) < (Number(cfg?.supplier_free_count) || 1000);
  if (free) { await admin.from('leads').update({ registration_status: 'free', registration_fee_due: 0, registration_paid_at: new Date().toISOString(), registration_expires_at: new Date(Date.now() + YEAR_MS).toISOString(), portal_updated_at: new Date().toISOString() }).eq('id', leadId); return { status: 'free', fee_due: 0 }; }
  const fee = Number(cfg?.supplier_reg_fee) || 1000;
  await admin.from('leads').update({ registration_status: 'due', registration_fee_due: fee, portal_updated_at: new Date().toISOString() }).eq('id', leadId);
  return { status: 'due', fee_due: fee };
}
async function aiSummarize(leadId: number) {
  try { const { data: lead } = await admin.from('leads').select('id,company_name,sector,emirate,services,products,description,certifications,verified,service_emirates').eq('id', leadId).maybeSingle(); if (!lead) return; const secret = await secretVal('inbound_secret'); if (!secret) return; const text = [lead.company_name && ('Company: ' + lead.company_name), lead.sector && ('Trade: ' + lead.sector), lead.services && ('Services: ' + lead.services), lead.products && ('Products: ' + lead.products), lead.description && ('About: ' + lead.description), lead.certifications && ('Certifications: ' + lead.certifications)].filter(Boolean).join('\n'); if (!text) return; const r = await fetch(`${SUPA_URL}/functions/v1/profile_ai`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, company_name: lead.company_name, sector: lead.sector, emirate: lead.emirate, text }) }); const jd = await r.json(); if (jd?.ok && jd.profile) { const p = jd.profile; const upd: Record<string, unknown> = {}; if (p.capability_summary) upd.capability_summary = p.capability_summary; if (Array.isArray(p.service_emirates) && p.service_emirates.length && !(Array.isArray(lead.service_emirates) && lead.service_emirates.length)) upd.service_emirates = p.service_emirates; if (p.description && !lead.description) upd.description = p.description; if (p.category && !lead.sector) upd.sector = p.category; if (Object.keys(upd).length) await admin.from('leads').update(upd).eq('id', leadId); } } catch (_e) { /* */ }
}
async function aiReview(lead: Record<string, unknown>) {
  try { const secret = await secretVal('inbound_secret'); if (!secret) return null; const profile: Record<string, unknown> = {}; for (const k of ['company_name','sector','emirate','service_emirates','contact_name','signatory_name','phone','services','products','description','trade_license_no','license_authority','license_expiry','trn','egr_number','bank_name','bank_account_name','bank_iban']) profile[k] = lead[k]; const r = await fetch(`${SUPA_URL}/functions/v1/supplier_review`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, profile }) }); return await r.json(); } catch (_e) { return null; }
}
async function notify(rows: Record<string, unknown>[]) { try { if (rows.length) await admin.from('notifications').insert(rows); } catch (_e) { /* */ } }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const body = await req.json().catch(() => ({})); const action = body.action;

    if (action === 'me') { const { data } = await admin.from('leads').select('id,company_name,emirate,sector,business_role,products,services,description,certifications,company_type,company_size,founded_year,service_emirates,claimed,verified,approval_status,ai_review_notes,registration_submitted_at,accepted_terms_at,contact_name,signatory_name,phone,trade_license_no,license_authority,license_expiry,license_city,name_corrected_from,owner_email_verified,doc_extracted_at,trn,bank_name,bank_account_name,bank_iban,license_doc_path,iban_doc_path,egr_doc_path,egr_doc_name,egr_number,company_profile_doc_path,catalog_doc_paths,registration_status,registration_fee_due,registration_expires_at,app_rating,app_reviews,rating,reviews').eq('claimed_by', email).maybeSingle(); return J({ supplier: data || null }); }
    if (action === 'search') { const q = String(body.q || '').slice(0, 60); if (q.length < 2) return J({ results: [] }); const { data } = await admin.from('leads').select('id,company_name,emirate,business_role,claimed,claimed_by').ilike('company_name', '%' + q + '%').order('reviews', { ascending: false, nullsFirst: false }).limit(8); return J({ results: (data || []).map((r) => ({ ...r, claimable: !r.claimed || r.claimed_by === email })) }); }
    if (action === 'create_company') { const { data: existing } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(); if (existing) return J({ error: 'Your account already manages a company.' }, 409); const name = String(body.company_name || '').trim().slice(0, 160); if (name.length < 2) return J({ error: 'Enter your company name.' }, 400); const { data: ins, error } = await admin.from('leads').insert({ company_name: name, emirate: body.emirate || null, sector: body.category || null, business_role: body.role || 'supplier', claimed: true, claimed_by: email, email, source: 'self_registered', scraped_at: new Date().toISOString().slice(0, 10) }).select('id').maybeSingle(); if (error) return J({ error: error.message }, 500); const reg = await setRegistration(ins!.id); return J({ ok: true, id: ins?.id, registration: reg }); }
    if (action === 'claim') { const id = Number(body.leads_id); const { data: row } = await admin.from('leads').select('id,claimed,claimed_by').eq('id', id).maybeSingle(); if (!row) return J({ error: 'not found' }, 404); if (row.claimed && row.claimed_by !== email) return J({ error: 'This company is already claimed by another account.' }, 409); const { data: existing } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(); if (existing && existing.id !== id) return J({ error: 'Your account already manages another company.' }, 409); await admin.from('leads').update({ claimed: true, claimed_by: email, portal_updated_at: new Date().toISOString() }).eq('id', id); const reg = await setRegistration(id); return J({ ok: true, registration: reg }); }

    if (action === 'process_docs') {
      const { data: sup } = await admin.from('leads').select('id,company_name,services,products,service_emirates').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first' }, 400);
      const secret = await secretVal('inbound_secret');
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      const out: Record<string, unknown> = {};
      const lic = body.license || {};
      if (lic.path) { upd.license_doc_path = String(lic.path); }
      else if (lic.original_b64) { try { const u8 = b64ToBytes(String(lic.original_b64)); const fn = String(lic.filename || 'license').replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 120); const p = `licenses/${sup.id}/${Date.now()}_${fn}`; await admin.storage.from('supplier-docs').upload(p, u8, { contentType: lic.mime || 'application/octet-stream', upsert: true }); upd.license_doc_path = p; } catch (_e) { /* */ } }
      const licImgs = Array.isArray(lic.images) ? lic.images : [];
      if (licImgs.length || lic.file_b64) {
        try { const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, mode: 'license', images: licImgs, file_b64: lic.file_b64, mime: lic.mime, filename: lic.filename }) }); const jd = await r.json();
          if (jd?.ok && jd.doc) { const d = jd.doc;
            if (d.license_number) upd.trade_license_no = d.license_number;
            if (d.license_authority) upd.license_authority = d.license_authority;
            if (d.city) upd.license_city = d.city;
            if (d.expiry_date) upd.license_expiry = d.expiry_date;
            if (d.emirate) upd.emirate = d.emirate;
            if (d.trn) upd.trn = d.trn;
            upd.doc_extracted_at = new Date().toISOString();
            const legal = String(d.legal_name || '').trim(); const cur = String(sup.company_name || '').trim();
            if (legal && legal.toLowerCase() !== cur.toLowerCase()) { upd.name_corrected_from = cur; upd.company_name = legal; }
            out.license = { legal_name: legal, license_number: d.license_number, authority: d.license_authority, city: d.city, expiry: d.expiry_date, emirate: d.emirate, name_corrected: !!upd.name_corrected_from, confidence: d.confidence };
          } else out.license_error = jd?.error || 'extract_failed';
        } catch (e) { out.license_error = String((e as Error)?.message || e); }
      }
      const profImgs: any[] = [];
      const prof = body.company_profile || {};
      if (prof.path) { upd.company_profile_doc_path = String(prof.path); }
      else if (prof.original_b64) { try { const u8 = b64ToBytes(String(prof.original_b64)); const fn = String(prof.filename || 'profile').replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 120); const p = `profiles/${sup.id}/${Date.now()}_${fn}`; await admin.storage.from('supplier-docs').upload(p, u8, { contentType: prof.mime || 'application/octet-stream', upsert: true }); upd.company_profile_doc_path = p; } catch (_e) { /* */ } }
      if (Array.isArray(prof.images)) profImgs.push(...prof.images);
      const cats = Array.isArray(body.catalogs) ? body.catalogs.slice(0, 5) : []; const catPaths: string[] = [];
      for (const c of cats) { if (c?.path) { catPaths.push(String(c.path)); } else if (c?.original_b64) { try { const u8 = b64ToBytes(String(c.original_b64)); const fn = String(c.filename || 'catalog').replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 120); const p = `catalogs/${sup.id}/${Date.now()}_${fn}`; await admin.storage.from('supplier-docs').upload(p, u8, { contentType: c.mime || 'application/octet-stream', upsert: true }); catPaths.push(p); } catch (_e) { /* */ } } if (Array.isArray(c?.images)) profImgs.push(...c.images); }
      if (catPaths.length) upd.catalog_doc_paths = catPaths;
      if (profImgs.length) {
        try { const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, mode: 'profile', images: profImgs.slice(0, 10) }) }); const jd = await r.json();
          if (jd?.ok && jd.profile) { const pf = jd.profile;
            if (pf.summary) upd.capability_summary = pf.summary;
            if (Array.isArray(pf.services) && pf.services.length && !sup.services) upd.services = pf.services.join(', ');
            if (Array.isArray(pf.products) && pf.products.length && !sup.products) upd.products = pf.products.join(', ');
            if (Array.isArray(pf.emirates) && pf.emirates.length && !(Array.isArray(sup.service_emirates) && sup.service_emirates.length)) upd.service_emirates = pf.emirates;
            out.profile = { summary: pf.summary, sectors: pf.sectors, confidence: pf.confidence };
          } else out.profile_error = jd?.error || 'extract_failed';
        } catch (e) { out.profile_error = String((e as Error)?.message || e); }
      }
      await admin.from('leads').update(upd).eq('id', sup.id);
      return J({ ok: true, extracted: out });
    }

    if (action === 'save_profile') {
      const { data: sup } = await admin.from('leads').select('id,company_name,emirate,approval_status,registration_submitted_at,verified').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first' }, 400);
      const { data: pc } = await admin.from('pricing_config').select('auto_approve_suppliers').eq('id', 1).maybeSingle(); const autoApprove = !!pc?.auto_approve_suppliers;
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      for (const c of PROFILE_COLS) if (body[c] !== undefined) upd[c] = body[c];
      if (Array.isArray(body.service_emirates)) upd.service_emirates = body.service_emirates;
      if (body.accept_terms) { upd.accepted_terms_at = new Date().toISOString(); upd.accepted_terms_version = String(body.terms_version || 'v2'); upd.accepted_terms_ip = clientIp(req) || null; }
      const firstSubmit = !sup.registration_submitted_at; if (autoApprove) { upd.approval_status = 'approved'; upd.verified = true; } else if (!sup.verified) { upd.approval_status = 'pending'; } if (firstSubmit) upd.registration_submitted_at = new Date().toISOString();
      await admin.from('leads').update(upd).eq('id', sup.id);
      await aiSummarize(sup.id);
      const { data: full } = await admin.from('leads').select('*').eq('id', sup.id).maybeSingle();
      const review = await aiReview(full || {});
      if (review) { const notes = (review.summary || '') + (Array.isArray(review.issues) && review.issues.length ? '  Issues: ' + review.issues.map((i: { field: string; note: string }) => `${i.field} — ${i.note}`).join('; ') : ''); await admin.from('leads').update({ ai_review_notes: notes.slice(0, 2000), ai_review_flags: review.issues || [], ai_reviewed_at: new Date().toISOString() }).eq('id', sup.id); }
      if (firstSubmit) { const mgmt = (await secretVal('admin_emails') || 'management@quotesdone.com').split(',')[0].trim(); const revLine = review ? ` AI check: ${review.severity || 'clean'} — ${review.summary || ''}` : ''; const lic = full?.name_corrected_from ? ` Licence name corrected from \"${full.name_corrected_from}\" to \"${full.company_name}\".` : ''; const licInfo = full?.trade_license_no ? ` Licence ${full.trade_license_no}${full.license_city ? ', ' + full.license_city : ''}${full.license_expiry ? ', expires ' + full.license_expiry : ''}.` : ''; await notify([ { type: 'supplier_registered', to_email: mgmt, to_role: 'admin', lead_id: sup.id, subject: 'New supplier registered — review needed', body: `New supplier \"${full?.company_name || sup.company_name}\"${full?.emirate ? ' (' + full.emirate + ')' : ''} has registered and is pending your approval.${licInfo}${lic}${revLine}` }, { type: 'registration_received', to_email: email, to_role: 'supplier', lead_id: sup.id, subject: autoApprove ? 'Your QuotesDone supplier account is active' : 'Thanks for registering with QuotesDone', body: autoApprove ? `Your account for ${sup.company_name} is active — you can now receive inquiries and submit quotes.` : `Thank you for registering ${full?.company_name || sup.company_name} with QuotesDone. Our team will verify your trade licence and details, and email you once your account is approved.` } ]); }
      const { data: me } = await admin.from('leads').select('approval_status').eq('id', sup.id).maybeSingle();
      return J({ ok: true, approval_status: me?.approval_status || 'pending', review: review ? { severity: review.severity, summary: review.summary, issues: review.issues } : null });
    }
    if (action === 'pay_registration') { const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(); if (!sup) return J({ error: 'claim your company first' }, 400); await admin.from('leads').update({ registration_status: 'paid', registration_fee_due: 0, registration_paid_at: new Date().toISOString(), registration_expires_at: new Date(Date.now() + YEAR_MS).toISOString() }).eq('id', sup.id); return J({ ok: true }); }
    if (action === 'dashboard') {
      const { data: sup } = await admin.from('leads').select('id,approval_status,app_rating,app_reviews,rating,rating_maps,reviews,reviews_maps').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first' }, 400);
      const [recv, q, t] = await Promise.all([ admin.from('inquiry_matches').select('id', { count: 'exact', head: true }).eq('supplier_id', sup.id), admin.from('quotes').select('id', { count: 'exact', head: true }).eq('supplier_id', sup.id), admin.from('transactions').select('id', { count: 'exact', head: true }).eq('supplier_id', sup.id) ]);
      return J({ active: recv.count || 0, quoted: q.count || 0, won: t.count || 0, approval_status: sup.approval_status, rating: ratingOf(sup) });
    }
    if (action === 'inbox') {
      const { data: sup } = await admin.from('leads').select('id,approval_status').eq('claimed_by', email).maybeSingle(); if (!sup) return J({ error: 'claim your company first' }, 400);
      const { data: matches } = await admin.from('inquiry_matches').select('inquiry_id').eq('supplier_id', sup.id); const ids = (matches || []).map((m) => m.inquiry_id);
      if (!ids.length) return J({ inquiries: [], approval_status: sup.approval_status });
      const { data: inq } = await admin.from('inquiries').select('id,category,emirate,summary,spec,created_at,budget,scope_type,brief_source,boq,boq_confidence,drawing_redacted_paths,status,outcome,hired_supplier_id').in('id', ids).order('created_at', { ascending: false }).limit(25);
      const { data: myq } = await admin.from('quotes').select('inquiry_id,quote_amount,status,notes,lead_time,validity,payment_terms,warranty,scope,conditions,source,original_file_name,submittable').eq('supplier_id', sup.id); const qmap = Object.fromEntries((myq || []).map((x) => [x.inquiry_id, x]));
      const out: any[] = [];
      for (const i of (inq || [])) {
        const pages: string[] = [];
        for (const p of (Array.isArray(i.drawing_redacted_paths) ? i.drawing_redacted_paths : [])) { const u = await signedRedacted(String(p)); if (u) pages.push(u); }
        const concluded = CONCLUDED.includes(String(i.status));
        const youWon = i.hired_supplier_id != null && Number(i.hired_supplier_id) === Number(sup.id);
        out.push({ id: i.id, category: i.category, emirate: i.emirate, summary: i.summary, spec: i.spec, created_at: i.created_at, budget: i.budget || null, scope_type: i.scope_type || null, brief_source: i.brief_source || null, boq: i.boq || null, boq_confidence: i.boq_confidence || null, drawing_file_name: null, drawing_file_url: null, drawing_pages: pages, status: i.status, concluded, you_won: youWon, quote: qmap[i.id] || null });
      }
      return J({ inquiries: out, approval_status: sup.approval_status });
    }
    if (action === 'projects') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(); if (!sup) return J({ error: 'claim your company first' }, 400);
      const { data: projs } = await admin.from('transactions').select('revealed_at,quote_amount,inquiries(category,emirate,summary)').eq('supplier_id', sup.id).order('revealed_at', { ascending: false }).limit(50);
      return J({ projects: (projs || []).map((p: any) => ({ category: p.inquiries?.category || null, emirate: p.inquiries?.emirate || null, summary: p.inquiries?.summary || null, revealed_at: p.revealed_at || null, month: p.revealed_at ? new Date(p.revealed_at).toLocaleDateString('en-GB', { month: 'short', year: 'numeric' }) : null, amount: p.quote_amount })) });
    }
    if (action === 'extract_quote') {
      const { data: sup } = await admin.from('leads').select('id,approval_status,accepted_terms_at').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first' }, 400);
      const inquiry_id = body.inquiry_id;
      const images = Array.isArray(body.images) ? body.images : [];
      if (!images.length) return J({ error: 'Could not read the file pages. Please attach a clear PDF or photo.' }, 400);
      const orig = body.original || {};
      let original_file_path: string | null = null, original_file_name: string | null = null;
      try { if (orig.path) { original_file_path = String(orig.path); original_file_name = String(orig.filename || 'quotation').slice(0, 180); } else if (orig.b64) { const u8 = b64ToBytes(String(orig.b64)); original_file_name = String(orig.filename || 'quotation').slice(0, 180); original_file_path = `quotes/${sup.id}/${inquiry_id}/${Date.now()}_${original_file_name.replace(/[^A-Za-z0-9._-]/g, '_')}`; await admin.storage.from('quote-files').upload(original_file_path, u8, { contentType: orig.mime || 'application/octet-stream', upsert: true }); } } catch (_e) { /* */ }
      const { data: inq } = await admin.from('inquiries').select('category,summary').eq('id', inquiry_id).maybeSingle();
      const secret = await secretVal('inbound_secret');
      let jd: any = {};
      try { const r = await fetch(`${SUPA_URL}/functions/v1/quote_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, images, inquiry: inq || {} }) }); jd = await r.json(); } catch (e) { return J({ error: 'Reading failed, please try again or fill the form.', detail: String((e as Error)?.message || e) }, 502); }
      if (!jd?.ok) return J({ error: jd?.error || 'Could not read the quotation. Please fill the form instead.', detail: jd?.detail || null }, 502);
      return J({ ok: true, proposal: jd.proposal, original_file_path, original_file_name });
    }
    if (action === 'submit_quote') {
      const { data: sup } = await admin.from('leads').select('id,company_name,accepted_terms_at,registration_status,approval_status').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first' }, 400);
      if (!sup.accepted_terms_at) return J({ error: 'accept the supplier terms first' }, 400);
      if (sup.approval_status !== 'approved') return J({ error: 'Your registration is pending verification. You can submit quotes once an admin approves your account (within 3 working days).' }, 403);
      if (sup.registration_status === 'due') return J({ error: 'Your AED 1,000 yearly registration is due. Please complete registration to send quotes.' }, 402);
      const { data: inqStat } = await admin.from('inquiries').select('status').eq('id', body.inquiry_id).maybeSingle();
      if (inqStat && CONCLUDED.includes(String(inqStat.status))) return J({ error: 'This request has been concluded — the customer has already selected a supplier. Thank you for your interest, and best of luck on the next one.' }, 409);
      const amt = Number(body.amount); if (!(amt > 0)) return J({ error: 'invalid amount' }, 400);
      const isUpload = body.source === 'upload';
      const items = Array.isArray(body.items) ? body.items : [];
      const det = { inquiry_id: body.inquiry_id, supplier_id: sup.id, quote_amount: amt, notes: clip(body.notes, 1000), lead_time: clip(body.lead_time, 200), validity: clip(body.validity, 200), payment_terms: clip(body.payment_terms, 400), warranty: clip(body.warranty, 200), scope: clip(body.scope, 2000), conditions: clip(body.conditions, 2000), exclusions: clip(body.exclusions, 2000), source: isUpload ? 'upload' : 'form', anonymized: isUpload, original_file_path: body.original_file_path || null, original_file_name: body.original_file_name || null, masked_terms: Array.isArray(body.masked_terms) ? body.masked_terms : null, structured: items.length > 0 };
      const { data: q, error } = await admin.from('quotes').upsert(det, { onConflict: 'inquiry_id,supplier_id' }).select('id,quote_amount,status').maybeSingle();
      if (error) return J({ error: error.message }, 500);
      if (items.length) {
        try {
          await admin.from('quote_items').delete().eq('quote_id', q!.id);
          const rows = items.slice(0, 80).map((it: any, i: number) => ({ quote_id: q!.id, line_no: i + 1, description: clip(it.description, 300), brand: clip(it.brand, 120), model: clip(it.model, 120), specification: clip(it.specification, 800), qty: numOrNull(it.qty), unit: clip(it.unit, 40), unit_price: numOrNull(it.unit_price), labour: numOrNull(it.labour), install: numOrNull(it.install), commissioning: numOrNull(it.commissioning), amount: numOrNull(it.amount) ?? ((numOrNull(it.qty) || 0) * (numOrNull(it.unit_price) || 0) || null), country_of_origin: clip(it.country_of_origin, 80), notes: clip(it.notes, 300) }));
          const clean = rows.filter((r) => r.description);
          if (clean.length) await admin.from('quote_items').insert(clean);
        } catch (_e) { /* */ }
      }
      let score: any = null; try { const { data } = await admin.rpc('fn_quote_structured_score', { p_quote: String(q!.id) }); score = data; } catch (_e) { /* */ }
      const submittable = !!(score && score.submittable);
      try { await admin.from('quotes').update({ submittable }).eq('id', q!.id); } catch (_e) { /* */ }
      const requireStructured = (await secretVal('require_structured_quotes')) === 'true';
      const pricedItems = items.filter((it: any) => (numOrNull(it.unit_price) || 0) > 0 || (numOrNull(it.amount) || 0) > 0).length;
      const formComplete = det.source === 'form' && pricedItems >= 1 && !!det.validity && !!det.warranty && !!det.lead_time;
      const accept = submittable || formComplete || !requireStructured;
      if (accept) {
        try { await admin.from('quotes').update({ status: 'submitted' }).eq('id', q!.id); } catch (_e) { /* */ }
        await admin.from('inquiries').update({ status: 'quoted' }).eq('id', body.inquiry_id).in('status', ['sent', 'quoted']);
        try { const { data: inq } = await admin.from('inquiries').select('customer_id,summary').eq('id', body.inquiry_id).maybeSingle(); if (inq?.customer_id) { const { data: c } = await admin.from('customers').select('email').eq('id', inq.customer_id).maybeSingle(); if (c?.email) await notify([{ type: 'new_quote', to_email: c.email, to_role: 'customer', inquiry_id: body.inquiry_id, subject: 'You have a new quote on QuotesDone', body: 'A supplier submitted a quote for your request' + (inq.summary ? ': ' + inq.summary : '') + '. Log in to view the full quotation and compare.' }]); } } catch (_e) { /* */ }
        let coaching: any = null; if (!submittable) { try { const { data } = await admin.rpc('fn_quote_coach', { p_quote: String(q!.id) }); coaching = data; } catch (_e) { /* */ } }
        return J({ ok: true, quote: q, submittable, accepted: true, coaching, score });
      } else {
        try { await admin.from('quotes').update({ status: 'draft' }).eq('id', q!.id); } catch (_e) { /* */ }
        let coaching: any = null; try { const { data } = await admin.rpc('fn_quote_coach', { p_quote: String(q!.id) }); coaching = data; } catch (_e) { /* */ }
        return J({ ok: true, quote: q, submittable: false, accepted: false, coaching, score, message: 'Your quote was saved as a draft. Add the missing details so we can send it to the customer.' });
      }
    }
    return J({ error: 'unknown action' }, 400);
  } catch (e) {
    return J({ error: String(e) }, 500);
  }
});
