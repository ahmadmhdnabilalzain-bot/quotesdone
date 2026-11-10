// supplier_api — the company's documents: upload_url, process_docs.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { safeFilename, SAFE_UPLOAD, SAFE_SUPPLIER_PAPERS } from '../../_shared/attachment.ts';
// MALWARE WATCH, 9 Sep 2026. Every file a supplier sends is hashed and looked up before it reaches
// storage; a hash VirusTotal already knows to be malicious is refused here rather than stored,
// forwarded and served back. See _shared/malware.ts for why the lookup blocks and the analysis does not.
import { sanitizeAndScan } from '../../_shared/malware.ts';
import { storedAt } from '../../_shared/stored_at.ts';
import { markReading, modelReadText } from '../../_shared/supplier_doc_trades.ts';
import { LICENCE_BEING_READ_NOTE, licenceLeftUnread, licenceReadState, modelOutcomeOf, type LicenceModelOutcome } from '../../_shared/licence_read_state.ts';
import { afterResponse, readProfileByModel, readStoredDocsLater, signedUpload, type LaterDoc } from '../../_shared/supplier_docs_later.ts';
import { toB64, licenceModelPayload, licenceNameFromModel, licenceNeedsModel, readExpiry, readLicenceFields, readLicenceName, b64Size, READ_MAX_BYTES, tooLargeToRead, type LicenceFields } from '../../_shared/document_expiry.ts';
import { COMPANY_ALREADY_REGISTERED, type LeadWriter, updateLeadSettingAsideClashingLicence } from '../../_shared/duplicate_company.ts';
import { type ActionCtx, J, SUPA_URL, admin, flagOn, logged, secretVal } from '../context.ts';
import { TOO_LARGE } from '../lib/fields.ts';
import { priorCrossCheck, recordServicesCrossCheck } from '../lib/services_check.ts';

export async function documentActions(c: ActionCtx): Promise<Response | undefined> {
  const { email, body, action } = c;
    // UPLOADS UP TO 100 MB GO STRAIGHT TO STORAGE (19 Oct 2026, sales_engineer; _shared/supplier_docs_later.ts). Vercel
    // caps a request body at 4.5 MB, so a profile or catalogue no longer travels as base64: this returns a signed upload
    // for a path in the supplier's own folder, the browser uploads to it, and process_docs / save_documents name the path.
    if (action === 'upload_url') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const r = await signedUpload(admin, Number(sup.id), String(body.kind || ''), body.filename, body.mime);
      return r.ok ? J(r) : J({ error: r.error, code: r.error, message: r.message }, r.status);
    }

    if (action === 'process_docs') {
      // FOUNDER RULING 1177 (7 Oct 2026): "it should always read". A model read that fails (a 5xx, a truncated or
      // unparseable answer) is asked once more before the document counts as unread; the gateway already falls back
      // to the route's second model inside each call (model_policy.document_extraction).
      const extract = async (body: Record<string, unknown>) => {
        let jd: any = null;
        for (let attempt = 0; attempt < 2; attempt++) {
          try {
            const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(120_000) });
            jd = await r.json().catch(() => null);
            if (jd?.ok) return jd;
          } catch (e) { jd = { error: String((e as Error)?.message || e) }; }
        }
        return jd;
      };
      const { data: sup } = await admin.from('leads').select('id,company_name,services,products,service_emirates').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const secret = await secretVal('cred_fn_supplier_api');
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      const out: Record<string, unknown> = {};
      // Every stored licence, profile and catalogue is also READ BY CODE into a trade proposal the
      // supplier confirms (15 Sep 2026, _shared/supplier_doc_trades.ts). The model calls below still
      // run and still refuse under the OpenRouter hold; nothing here waits on them.
      const readQueue: LaterDoc[] = [];
      const lic = body.license || {};
      // 14 Sep 2026 (sales_engineer): a path is recorded only when it is this supplier's own and
      // storage holds the object - otherwise the supplier sees success for a file that is not there
      // and the backup queues a document it can never copy.
      const own = async (p: unknown, folder: string) => { const s = String(p); return s.startsWith(`${folder}/${sup.id}/`) && !s.includes('..') && await storedAt(admin, 'supplier-docs', s); };
      const notStored = (what: string) => J({ error: 'document_not_found', code: 'document_not_found', message: `We could not find your ${what} in our records. Please upload it again.` }, 400);
      if (lic.path) { if (!(await own(lic.path, 'licenses')) && !(await own(lic.path, 'licence'))) return notStored('trade licence'); upd.license_doc_path = String(lic.path); readQueue.push({ path: String(lic.path), name: String(lic.path).split('/').pop() || 'licence', kind: 'licence' }); }
      // AUDIT 9.1 (3 Aug 2026). The trade licence upload. Three defects in one line:
      //   * no type check at all - the bytes went to storage as whatever the caller declared,
      //     defaulting to application/octet-stream, so an HTML document or an executable stored
      //     cleanly as a supplier's trade licence and was later served back to an admin reviewer;
      //   * the filename was only character-filtered, so the stored extension could disagree with
      //     the content ("licence.pdf" holding HTML);
      //   * the whole thing sat in try/catch with an empty handler, so a failed upload was
      //     SILENT - the supplier saw success, license_doc_path was never set, and the document
      //     review queue simply never saw a licence.
      else if (lic.original_b64) {
        // refused before it is decoded or parsed (document_expiry.ts READ_MAX_BYTES: 19.3 MB was HTTP 546 here on 1 Nov)
        if (b64Size(lic.original_b64) > READ_MAX_BYTES) return J(tooLargeToRead(b64Size(lic.original_b64), 'trade licence'), 413);
        const sc = await sanitizeAndScan({ input: String(lic.original_b64), declaredMime: lic.mime, filename: lic.filename || 'license', allow: SAFE_UPLOAD,
                                           scan: { source: 'supplier_api.license', subject: String(sup.id), filename: lic.filename, bucket: 'supplier-docs' } });
        if (!sc.ok) return J({ ...sc.body, message: sc.body.error === 'malware_detected' ? sc.body.message : 'That licence file cannot be accepted. Please upload a PDF or a clear photo (JPEG or PNG) of your trade licence.' }, sc.status);
        const s = sc.result;
        const p = `licenses/${sup.id}/${Date.now()}_${safeFilename(lic.filename || 'license', s.mime)}`;
        const up = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
        if (up.error || !(await storedAt(admin, 'supplier-docs', p))) { logged('licence upload', up.error ?? 'storage does not hold the object after upload'); return J({ error: 'upload_failed', code: 'upload_failed', message: 'We could not store your trade licence. Please try again.' }, 502); }
        upd.license_doc_path = p;
        readQueue.push({ path: p, name: String(lic.filename || 'licence'), kind: 'licence', bytes: s.bytes, mime: s.mime });
      }
      const licImgs = Array.isArray(lic.images) ? lic.images : [];
      // CODE READS THE EXPIRY FIRST (22 Sep 2026, SEATS-02; founder instruction 524). This block
      // went straight to license_extract, which runs through ai_gateway — under the founder's
      // OpenRouter hold that is a 502 on every registration, so a licence uploaded here never got
      // an expiry date at all while supplier_portal's Documents tab read the same document by code.
      // Same reader, same rule as the portal: a date only counts when an expiry keyword stands
      // beside it, and a scan (no text layer) returns nothing rather than a guess.
      const licBytes = readQueue.find((d) => d.kind === 'licence' && d.bytes)
        || (upd.license_doc_path ? await (async () => {
             try {
               const dl = await admin.storage.from('supplier-docs').download(String(upd.license_doc_path));
               if (!dl.data) return null;
               return { bytes: new Uint8Array(await dl.data.arrayBuffer()), mime: dl.data.type || 'application/pdf' } as { bytes: Uint8Array; mime: string };
             } catch (_e) { return null; }
           })() : null);
      // the same ceiling for a licence that came by path: refused before any reader parses it
      if (licBytes?.bytes && licBytes.bytes.length > READ_MAX_BYTES) return J(tooLargeToRead(licBytes.bytes.length, 'trade licence'), 413);
      // What CODE measured off the document. The model below may add what code cannot read
      // (licence number, authority, legal name) but must never overwrite this date.
      let codeExpiry: string | null = null;
      // The licence's printed company name, read by code (24 Sep 2026). The sales engineer's review
      // compares it with the registered name (fn_supplier_licence_name_mismatch); null = not read.
      let codeName: string | null = null;
      if (licBytes?.bytes) { try { codeName = await readLicenceName(licBytes.bytes, licBytes.mime || 'application/pdf'); } catch (_e) { codeName = null; } }
      // A NEW licence replaces the old name even when nothing is read: a stale name must never match for a new
      // document. null = not read, and the review then holds the registration (licence_name_unread).
      if (licBytes?.bytes) upd.licence_legal_name = codeName;
      // ...and so does its expiry (12 Oct 2026, stage-2 run 3 S02): the OLD licence's date must never judge a new
      // document. Code or the model below writes the new one's expiry only when it reads one; else it stays unread.
      if (licBytes?.bytes) { upd.license_expiry = null; upd.doc_extracted_at = null; }
      // EVERY LABELLED FIELD, BY CODE (7 Oct 2026, accuracy suite ledger 1162). Until today the licence number, the
      // authority and the emirate were written only from the model, whose switch is off, so a text licence's number
      // was never recorded. Code's reading is written first; the model below fills only what code left unread.
      let licIssue: string | null | undefined;   // undefined = no licence in this call: leave the column alone
      let codeFields: Partial<LicenceFields> = {};
      if (licBytes?.bytes) { try { codeFields = await readLicenceFields(licBytes.bytes, licBytes.mime || 'application/pdf'); } catch (_e) { codeFields = {}; } }
      // ...and its number and authority (2 Nov 2026, ledger 1442): what the old licence printed never judges a new one.
      if (licBytes?.bytes) { upd.trade_license_no = null; upd.license_authority = null; }
      if (codeFields.licence_no) upd.trade_license_no = codeFields.licence_no;
      // THE ISSUE DATE (2 Nov 2026, ledger 1467): read and kept when the licence prints one; never required.
      if (licBytes?.bytes) licIssue = codeFields.issue_date || null;
      if (codeFields.authority) upd.license_authority = codeFields.authority;
      if (codeFields.emirate) upd.emirate = codeFields.emirate;
      // The supplier reads this note in the portal, so it is written in both languages the
      // registration speaks (the estate's rule: a document message is English and fully Arabic).
      const noteBoth = (en: string, ar: string) => { out.license_expiry_note = en; out.license_expiry_note_ar = ar; };
      if (licBytes?.bytes) {
        try {
          const docRead = await readExpiry(licBytes.bytes, licBytes.mime || 'application/pdf');
          if (docRead) {
            codeExpiry = docRead.expiry;
            upd.license_expiry = docRead.expiry;
            upd.doc_extracted_at = new Date().toISOString();
            out.license = { expiry: docRead.expiry, source: 'text', keyword: docRead.keyword, read_by: 'code', licence_name: codeName };
          } else {
            noteBoth('We could not read an expiry date from your trade licence — it may be a scan, or it may not print a date beside an expiry label. Nothing was guessed.',
                     'لم نتمكن من قراءة تاريخ انتهاء رخصتكم التجارية. قد يكون الملف صورة ممسوحة ضوئياً، أو لا يذكر تاريخاً بجانب كلمة الانتهاء. ولم نخمّن أي تاريخ.');
          }
        } catch (e) {
          noteBoth('We could not read your trade licence file (' + String((e as Error)?.message || e).slice(0, 120) + '). Nothing was guessed.',
                   'تعذّرت قراءة ملف رخصتكم التجارية. ولم نخمّن أي تاريخ.');
        }
      }
      // The model path — legal name, licence number, authority, emirate, TRN — is behind the same
      // flag the portal uses (app_secrets.document_expiry_ai). With the flag off nothing is asked
      // of a gateway that cannot answer, and nothing above depends on it.
      // A scan the code could not name is sent from storage when the portal did not resend it (24 Sep 2026).
      // The model is asked when code left the name, the number OR the expiry unread (licenceNeedsModel), not only the name.
      // WHOSE FAILURE AN UNREAD FIELD IS (10 Nov 2026, customer_support; _shared/licence_read_state.ts). 'not_needed' until the
      // model is wanted; extract_failed used to be answered to the browser and stored nowhere, so the gate asked the supplier
      // for a clearer copy of a licence OUR reader had failed on.
      let modelOutcome: LicenceModelOutcome = 'not_needed';
      const modelDoc = licenceModelPayload({ ...lic, images: licImgs }, licBytes?.bytes ? { bytes: licBytes.bytes, mime: licBytes.mime || 'application/pdf' } : null,
        licBytes?.bytes && licenceNeedsModel({ ...codeFields, legal_name_en: codeName, expiry_date: codeFields.expiry_date }) ? null : codeName);
      const modelWanted = !!licBytes?.bytes && licenceLeftUnread(upd);
      if (modelWanted && !modelDoc) modelOutcome = 'not_sent';
      if (modelDoc && !(await flagOn('document_expiry_ai'))) { if (modelWanted) modelOutcome = 'off'; }
      else if (modelDoc) {
        try { const jd = await extract({ __secret: secret, subject: { supplier_id: sup.id, email }, mode: 'license', ...modelDoc });
          modelOutcome = modelOutcomeOf(jd);
          // An unreadable read (licence_extract.normaliseLicence: no name, or 'low') carries no fields and writes none.
          if (jd?.ok && jd.doc && !jd.doc.unreadable) { const d = jd.doc;
            if (d.license_number && !codeFields.licence_no) upd.trade_license_no = d.license_number;
            if (d.license_authority && !codeFields.authority) upd.license_authority = d.license_authority;
            // A scan's activities, read by the model, are read for trades exactly as a text licence's are (exact code
            // or meaning, supplier_doc_trades), and only when code read no activities line itself.
            const q = readQueue.find((x) => x.kind === 'licence');
            if (q && !codeFields.activities?.length) q.photo_text = modelReadText('licence', d.activities);
            if (d.city) upd.license_city = d.city;
            // CODE FIRST, AND THE MODEL DOES NOT OVERRULE IT (founder: "code first, LLM only where
            // code can't"). When the document itself printed a date beside an expiry keyword, that
            // reading stands; the model's date is only recorded beside it, and a disagreement is
            // returned so a human can see the two rather than being silently resolved.
            if (d.expiry_date) {
              if (codeExpiry) {
                if (String(d.expiry_date) !== codeExpiry) out.license_expiry_model_differs = { code: codeExpiry, model: d.expiry_date };
              } else upd.license_expiry = d.expiry_date;
            }
            if (d.emirate && !codeFields.emirate) upd.emirate = d.emirate;
            if (d.issue_date && !licIssue) licIssue = String(d.issue_date).slice(0, 10);
            if (d.trn) upd.trn = d.trn;
            upd.doc_extracted_at = new Date().toISOString();
            // 24 Sep 2026: the licence name is RECORDED, never copied over the registered name. Copying it
            // made the name check the founder asked for always pass; the review now compares the two
            // (fn_supplier_licence_name_mismatch) and a mismatch is action_required. Code's reading wins.
            const legal = String(d.legal_name || '').trim();
            const modelName = licenceNameFromModel(d);
            if (modelName && !codeName) upd.licence_legal_name = modelName;
            // Merged, never replaced (main): out.license may already carry the expiry code measured,
            // and overwriting it would lose the reading that is actually written to the row.
            // `trn` is SP-C-09 of #858: process_docs read the TRN off the licence and wrote it to the
            // row (upd.trn above) but never returned it, though the form reads out.license.trn.
            out.license = { ...(out.license as Record<string, unknown> || {}),
              legal_name: legal, license_number: d.license_number, authority: d.license_authority, city: d.city,
              expiry: codeExpiry || d.expiry_date, model_expiry: d.expiry_date, emirate: d.emirate, trn: d.trn,
              licence_name: upd.licence_legal_name ?? null, confidence: d.confidence, issue_date: licIssue ?? null };
          } else out.license_error = jd?.doc?.unreadable ? 'licence_unreadable' : (jd?.error || 'extract_failed');
        } catch (e) { modelOutcome = 'failed'; out.license_error = String((e as Error)?.message || e); }
      }
      // THE READ STATE IS STORED WITH THE FIELDS (one write, so z20's re-verification sees both). 'ours_failed' holds the
      // registration as licence_being_read (fn_sales_engineer_verifies_supplier), the sweep reads it again, and the supplier
      // is told it is on our side. Only a licence read in this call carries a state.
      if (licBytes?.bytes) {
        const state = licenceReadState(licenceLeftUnread(upd), modelOutcome);
        upd.licence_read_state = state; upd.licence_read_at = new Date().toISOString();
        out.license_read_state = state;
        if (state === 'ours_failed') { out.license_expiry_note = LICENCE_BEING_READ_NOTE; delete out.license_expiry_note_ar; }
      } else if (lic.path || lic.original_b64) {
        // the licence was recorded but its bytes could not be fetched back to read: that is ours, never the supplier's
        upd.licence_read_state = 'ours_failed'; upd.licence_read_at = new Date().toISOString(); out.license_read_state = 'ours_failed';
      }
      const profImgs: any[] = [];
      // Extracted services for THIS run, kept aside so they can be cross-checked against the
      // supplier's own typed text once the row has been written (see the 29 Jul 2026 header).
      let xServices: string[] = [];
      const prof = body.company_profile || {};
      // A path is a file the browser uploaded straight to storage (upload_url): it has not been through the type and
      // malware gate yet, so it is gated on its stored bytes before it is read (gate: true, _shared/supplier_docs_later.ts).
      if (prof.path) { if (!(await own(prof.path, 'profiles'))) return notStored('company profile'); upd.company_profile_doc_path = String(prof.path); readQueue.push({ path: String(prof.path), name: String(prof.filename || String(prof.path).split('/').pop() || 'profile'), kind: 'profile', mime: prof.mime ? String(prof.mime) : undefined, gate: true }); }
      // AUDIT 9.1. Company profile document - same treatment as the trade licence above.
      else if (prof.original_b64) {
        const sc = await sanitizeAndScan({ input: String(prof.original_b64), declaredMime: prof.mime, filename: prof.filename || 'profile', allow: SAFE_SUPPLIER_PAPERS,
                                           scan: { source: 'supplier_api.company_profile', subject: String(sup.id), filename: prof.filename, bucket: 'supplier-docs' } });
        if (!sc.ok) return J({ ...sc.body, message: sc.body.error === 'malware_detected' ? sc.body.message : sc.body.error === 'file_too_large' ? TOO_LARGE('company profile') : 'That company profile cannot be accepted. Please upload a PDF, a Word or PowerPoint file, or an image (JPEG or PNG).' }, sc.status);
        const s = sc.result;
        const p = `profiles/${sup.id}/${Date.now()}_${safeFilename(prof.filename || 'profile', s.mime)}`;
        const up = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
        if (up.error || !(await storedAt(admin, 'supplier-docs', p))) { logged('profile upload', up.error ?? 'storage does not hold the object after upload'); return J({ error: 'upload_failed', code: 'upload_failed', message: 'We could not store your company profile. Please try again.' }, 502); }
        upd.company_profile_doc_path = p;
        // Read after the response (supplier_docs_later.ts); the picture / scan model step is profileHook below.
        readQueue.push({ path: p, name: String(prof.filename || 'profile'), kind: 'profile', bytes: s.bytes, mime: s.mime });
      }
      if (Array.isArray(prof.images)) profImgs.push(...prof.images);
      const cats = Array.isArray(body.catalogs) ? body.catalogs.slice(0, 5) : []; const catPaths: string[] = [];
      // AUDIT 9.1. Catalogues. A rejected catalogue is refused outright rather than skipped,
      // because silently dropping one is how a supplier ends up believing a document is on file.
      for (const c of cats) {
        if (c?.path) { if (!(await own(c.path, 'catalogs'))) return notStored('catalogue'); catPaths.push(String(c.path)); readQueue.push({ path: String(c.path), name: String(c.filename || String(c.path).split('/').pop() || 'catalogue'), kind: 'catalogue', mime: c.mime ? String(c.mime) : undefined, gate: true }); }
        else if (c?.original_b64) {
          const sc = await sanitizeAndScan({ input: String(c.original_b64), declaredMime: c.mime, filename: c.filename || 'catalog', allow: SAFE_SUPPLIER_PAPERS,
                                             scan: { source: 'supplier_api.catalog', subject: String(sup.id), filename: c.filename, bucket: 'supplier-docs' } });
          if (!sc.ok) return J({ ...sc.body, message: sc.body.error === 'malware_detected' ? sc.body.message : sc.body.error === 'file_too_large' ? TOO_LARGE('catalogue') : 'One of your catalogue files cannot be accepted. Please upload PDFs, Word or PowerPoint files, or images (JPEG or PNG).' }, sc.status);
          const s = sc.result;
          const p = `catalogs/${sup.id}/${Date.now()}_${safeFilename(c.filename || 'catalog', s.mime)}`;
          const up = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
          if (up.error || !(await storedAt(admin, 'supplier-docs', p))) { logged('catalogue upload', up.error ?? 'storage does not hold the object after upload'); return J({ error: 'upload_failed', code: 'upload_failed', message: 'We could not store one of your catalogue files. Please try again.' }, 502); }
          catPaths.push(p);
          readQueue.push({ path: p, name: String(c.filename || 'catalogue'), kind: 'catalogue', bytes: s.bytes, mime: s.mime });
        }
        if (Array.isArray(c?.images)) profImgs.push(...c.images);
      }
      // Append, never replace. Assigning catPaths wholesale wiped every catalogue the supplier
      // had already uploaded the moment they added one more - silent data loss, no warning, no
      // undo. supplier_portal.save_documents already appends; this is the registration path
      // catching up to it. Same 20-file ceiling so the two paths agree.
      if (catPaths.length) {
        const { data: curCat } = await admin.from('leads').select('catalog_doc_paths').eq('id', sup.id).maybeSingle();
        const existingCat: string[] = Array.isArray(curCat?.catalog_doc_paths) ? (curCat!.catalog_doc_paths as string[]) : [];
        upd.catalog_doc_paths = [...existingCat, ...catPaths.filter((p) => !existingCat.includes(p))].slice(0, 20);
      }
      // THE PROFILE MODEL STEP RUNS AFTER THE RESPONSE (19 Oct 2026, sales_engineer; _shared/supplier_docs_later.ts). A
      // picture, or a profile PDF with no text layer (13 Oct 2026, it_engineer: Menasco, 87 pages, 0 characters), goes to
      // license_extract's profile mode (ruling 1177), up to PROFILE_PDF_MODEL_MAX; a PDF pdf.js could not parse is held
      // unreadable, never taken for a scan. Its findings are written to the row on their own update.
      const askProfile = async (b: Record<string, unknown>) => {
        const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, mode: 'profile', ...b }), signal: AbortSignal.timeout(120_000) });
        const j = await r.json().catch(() => null);
        return { ...(j ?? {}), status: r.status };
      };
      const runProfileModel = async (pq?: LaterDoc) => {
        // THE ONE PROFILE READ (review of #1796): the Documents tab and registration read a picture or a scan through readProfileByModel, with the
        // same size and page caps, the same two attempts, the same subject for the spend, and the same finding when both attempts fail.
        // Here the browser's own page images (profImgs) are sent when it rendered any, ahead of which goes a picture profile's own bytes.
        const pqImage = !!(pq?.bytes && pq.mime && /^image\//i.test(pq.mime));
        const images = profImgs.length ? [...(pqImage ? [{ b64: toB64(pq!.bytes!), mime: pq!.mime }] : []), ...profImgs] : undefined;
        const holder: LaterDoc = pq ?? { path: '', name: 'profile', kind: 'profile' };
        const res = await readProfileByModel(holder, askProfile, { subject: { supplier_id: sup.id, email }, admin, ...(images ? { images } : {}) });
        if (!res.asked) return;
        const mUpd: Record<string, unknown> = {};
        if (!(res.ok && res.profile)) return;   // readProfileByModel has logged it and filed the finding
        const pf = res.profile as Record<string, any>;
        if (pf.summary) mUpd.capability_summary = pf.summary;
        // DOCUMENTS LEAD (spec, 29 Jul 2026): what the documents say ALWAYS becomes leads.services; the supplier's own
        // words are kept as the declared value and cross-checked below.
        if (Array.isArray(pf.services) && pf.services.length) { xServices = pf.services.map((s: unknown) => String(s).trim()).filter(Boolean).slice(0, 40); mUpd.services = xServices.join(', '); }
        // The services the model read off a picture are read for trades exactly as a text profile's lines are.
        // (readProfileByModel sets photo_text itself when it read the document's own bytes; with the browser's pages it is set here for a picture)
        if (pq && images && pqImage) pq.photo_text = modelReadText('profile', pf.lines);
        if (Array.isArray(pf.products) && pf.products.length && !sup.products) mUpd.products = pf.products.join(', ');
        if (Array.isArray(pf.emirates) && pf.emirates.length && !(Array.isArray(sup.service_emirates) && sup.service_emirates.length)) mUpd.service_emirates = pf.emirates;
        if (Object.keys(mUpd).length) { const { error } = await admin.from('leads').update(mUpd).eq('id', sup.id); if (error) console.error('process_docs: profile fields not saved —', error.message); }
        // DOUBLE CONFIRMATION (spec, 29 Jul 2026): the documents' services against the supplier's typed ones, recorded in
        // agent_actions, a review item on a conflict. The declared text is the last cross-check's when one exists.
        if (xServices.length) {
          const prior = await priorCrossCheck(sup.id);
          await recordServicesCrossCheck(sup.id, sup.company_name, xServices, prior.found ? prior.declared : (sup.services ?? null));
        }
      };
      // 5 Aug 2026. This is the ONLY database write in process_docs, and it carries the storage
      // path, every extracted licence field and the company-name correction. Its result was
      // discarded, so a failed write returned `{ok:true, extracted:{…}}` — a complete, plausible
      // payload describing a licence that was never saved. The supplier is told their trade licence
      // is on file when it is not, and the document review queue never sees it. The storage uploads
      // twenty lines above already check `up.error` and return 502; this now matches them.
      // Found by verify_supplier_docs.mjs, which asserts the ROW rather than the response.
      // A licence number another claimed company holds is set aside (the rest of the row is still
      // written) and handed to a human: _shared/duplicate_company.ts.
      const { error: updErr, licenceSetAside } = await updateLeadSettingAsideClashingLicence(admin as unknown as LeadWriter, sup.id, upd, 'supplier_api.process_docs');
      // Its own write, so a deploy that lands before the column (SQL leads_keep_the_licence_issue_date) costs only this line.
      if (!updErr && licIssue !== undefined) { const ri = await admin.from('leads').update({ license_issue_date: licIssue }).eq('id', sup.id); if (ri.error) console.error('process_docs: licence issue date not saved —', ri.error.message); }
      if (licenceSetAside) {
        const lic = out.license as Record<string, unknown> | undefined;
        if (lic) delete lic.license_number;   // never fill the form with a number the row does not hold
        out.licence_set_aside = true;
        out.licence_notice = COMPANY_ALREADY_REGISTERED;
      }
      if (updErr) {
        console.error('process_docs: leads update failed —', updErr.message);
        return J({ error: 'save_failed', code: 'save_failed', message: 'We read your documents but could not save them to your profile. Please try again.' }, 502);
      }
      // READ AFTER THE ANSWER (19 Oct 2026, sales_engineer; _shared/supplier_docs_later.ts). After the row write, so only
      // documents now on the supplier's row are read. Each is marked 'reading' first, so the portal shows it being read
      // and a read that dies stays held; the read - the gate for a file that came by path, the profile model step, the
      // trade read - runs after the response, and a read still 'reading' 10 minutes on is read again by the sweep.
      if (readQueue.length) {
        const markErr = await markReading(admin, Number(sup.id), readQueue);
        if (markErr) console.error(JSON.stringify({ at: 'supplier_api.process_docs.markReading', supplier: sup.id, error: markErr }));
        out.documents_reading = readQueue.map((d) => d.path);
        let modelRan = false;
        const job = (async () => {
          // a scanned catalogue is read by the same model; its lines are its own photo_text and it writes no profile field
          await readStoredDocsLater(admin, Number(sup.id), readQueue, { profile: async (d) => { modelRan = true; await runProfileModel(d); },
            catalogue: async (d) => { await readProfileByModel(d, askProfile, { subject: { supplier_id: sup.id, email }, admin }); } });
          if (!modelRan && profImgs.length) await runProfileModel();
        })();
        const w = afterResponse(job, 'supplier_api.process_docs.later'); if (w) await w;
      } else if (profImgs.length) { const w = afterResponse(runProfileModel(), 'supplier_api.process_docs.later'); if (w) await w; }
      return J({ ok: true, extracted: out });
    }
}
