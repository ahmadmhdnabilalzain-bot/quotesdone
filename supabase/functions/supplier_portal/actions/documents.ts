// supplier_portal — documents, save_documents, remove_document, set_expiry.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here from index.ts on 9 Nov 2026 (sales_engineer: the 791-line index.ts split into modules, a pure move).
import { clearerCopyAsk } from '../../_shared/clearer_copy.ts';
import { safeFilename, SAFE_UPLOAD } from '../../_shared/attachment.ts';
// MALWARE WATCH, 9 Sep 2026 — see _shared/malware.ts. A refused file is reported in `failed`
// exactly as a refused SHAPE already was, so a supplier is never told a document is on file when
// the scanner refused it.
import { sanitizeAndScan } from '../../_shared/malware.ts';
import { REQUIRED_DOC_KEYS } from '../../_shared/supplier_registration.ts';
import { markReading, modelReadText } from '../../_shared/supplier_doc_trades.ts';
import { LICENCE_BEING_READ_NOTE, MODEL_ANSWER_BUDGET_MS, licenceLeftUnread, licenceReadState, modelOutcomeOf, recordLicenceReadNote, LICENCE_READINGS_CLEARED, keepsAcceptedReading, recordAcceptedReadingKept, type LicenceModelOutcome } from '../../_shared/licence_read_state.ts';
import { afterResponse, ownPath, readProfileByModel, readStoredDocsLater, type LaterDoc } from '../../_shared/supplier_docs_later.ts';
import { storedAt } from '../../_shared/stored_at.ts';
// EVERY DOCUMENT READS ITS OWN DATES, AND OFFERS VIEW / DOWNLOAD / REPLACE / REMOVE (founder
// instruction 524, 21 Sep 2026). _shared/document_expiry.ts reads the expiry off the bytes by code
// before any model is asked; ./document_actions.ts holds the Remove refusal and the version row.
import { modelReadingToRow, readExpiry, readLicenceFields, readLicenceName, b64Size, READ_MAX_BYTES, tooLargeToRead, type ExpiryRead, type LicenceFields } from '../../_shared/document_expiry.ts';
import { removeRefusal, versionRow, type ExpiryNote, type VersionSnapshot } from '../document_actions.ts';
import { COMPANY_ALREADY_REGISTERED, type LeadWriter, updateLeadSettingAsideClashingLicence } from '../../_shared/duplicate_company.ts';
import { type ActionCtx, flagOn, J, failed, admin, SUPA_URL } from '../context.ts';
import { DOC_KINDS, listDocuments } from '../lib/documents.ts';

export async function documentActions(c: ActionCtx): Promise<Response | undefined> {
  const { email, sup, b, action } = c;
    // ONE LIST, READ AFTER EVERY WRITE (audit 21 Sep 2026, finding 16). The Documents tab used to ask
    // for this list in a second round trip after each upload, and rendered the answer over its own
    // staged state; save_documents, remove_document and set_expiry now return the fresh list in the
    // same response, so the card, the counter and the unlock panel are painted from one read.
    if (action === 'documents') return J(await listDocuments(sup.id));

    if (action === 'save_documents') {
      // Capped (15 Sep 2026): every item is malware-scanned and licence/profile/catalogues are now
      // also read by code, one after another, inside an edge function's CPU budget. Nine document
      // kinds plus a handful of catalogues fits; supplier_api.process_docs is bounded to 7 the same way.
      const items = Array.isArray(b.items) ? b.items.slice(0, 15) : [];
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      const saved: string[] = [];
      let licenceNotice = false;
      let licIssue: string | null | undefined;
      let acceptedKeptFor = '';   // the new licence file an approved supplier's accepted reading stands beside (review of #1982, L3-2)   // the licence's printed issue date (2 Nov 2026, ledger 1467); undefined = no licence in this call
      const failedUploads: { kind: string; reason: string }[] = [];  // NOT 'failed' - that name belongs to the module-level refusal helper above, and shadowing it here is how the raw Postgres message stayed in this reply until 22 Sep 2026.
      const { data: _isec } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_supplier_portal').maybeSingle();
      const INBOUND_SECRET = (_isec?.value as string) || '';
      // What each column holds BEFORE this save: a replaced file becomes a doc_versions row after the
      // write succeeds (instruction 524 — Replace keeps the previous version).
      const beforeCols = new Set<string>(); for (const k of Object.values(DOC_KINDS)) { beforeCols.add(k.pathCol); if (k.nameCol) beforeCols.add(k.nameCol); if (k.expCol) beforeCols.add(k.expCol); }
      const { data: beforeRow } = await admin.from('leads').select([...beforeCols].join(',')).eq('id', sup.id).maybeSingle();
      const before = (beforeRow || {}) as Record<string, unknown>;
      const aiOn = await flagOn('document_expiry_ai');
      const read: Record<string, ExpiryNote> = {};
      let catAppend: string[] = [];
      // Licence, profile and catalogues are also read by code into a trade proposal (15 Sep 2026,
      // _shared/supplier_doc_trades.ts) — the same reading supplier_api.process_docs does.
      const readQueue: LaterDoc[] = [];
      // A FILE UPLOADED STRAIGHT TO STORAGE (19 Oct 2026, sales_engineer; supplier_api upload_url): a profile or catalogue
      // arrives as a path. It is recorded only when it is this supplier's own and storage holds it, and it is gated on its
      // stored bytes before it is read (gate: true, _shared/supplier_docs_later.ts).
      const byPath = async (it: { path?: unknown }, kind: 'profile' | 'catalogue') =>
        !!it.path && ownPath(it.path, kind, sup.id) && await storedAt(admin, 'supplier-docs', String(it.path)).catch(() => false);
      for (const it of items) {
        const kindStr = String(it.kind || '');
        if (kindStr === 'catalogs') {
          if (it.path) {
            if (!(await byPath(it, 'catalogue'))) { failedUploads.push({ kind: 'catalogs', reason: 'We could not find that catalogue in our records. Please upload it again.' }); continue; }
            catAppend.push(String(it.path)); saved.push('catalogs');
            readQueue.push({ path: String(it.path), name: String(it.filename || 'catalogue'), kind: 'catalogue', mime: it.mime ? String(it.mime) : undefined, gate: true });
          } else if (it.original_b64) {
            // AUDIT 9.1 (3 Aug 2026). Sanitised from the bytes before storage; see
            // supabase/functions/_shared/attachment.ts. A rejection is reported to the supplier
            // in `failed` rather than swallowed, so they are never told a document is on file
            // when it was refused.
            try {
              const sc = await sanitizeAndScan({ input: String(it.original_b64), declaredMime: it.mime, filename: it.filename || 'catalog', allow: SAFE_UPLOAD,
                                                 scan: { source: 'supplier_portal.catalogs', subject: String(sup.id), filename: it.filename, bucket: 'supplier-docs' } });
              if (!sc.ok) { failedUploads.push({ kind: 'catalogs', reason: String(sc.body.detail || sc.body.error) }); continue; }
              const s = sc.result;
              const p = `catalogs/${sup.id}/${Date.now()}_${safeFilename(it.filename || 'catalog', s.mime)}`;
              const { error: upErr } = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
              if (upErr) { failedUploads.push({ kind: 'catalogs', reason: upErr.message }); continue; }
              catAppend.push(p); saved.push('catalogs');
              readQueue.push({ path: p, name: String(it.filename || 'catalogue'), kind: 'catalogue', bytes: s.bytes, mime: s.mime });
            } catch (e) { failedUploads.push({ kind: 'catalogs', reason: String((e as Error)?.message || e).slice(0, 200) }); }
          }
          continue;
        }
        const kind = DOC_KINDS[kindStr]; if (!kind) continue;
        // The sanitised bytes, kept for the expiry read below; null when nothing was uploaded.
        let stored: { bytes: Uint8Array; mime: string } | null = null;
        if (kindStr === 'profile' && it.path) {
          if (!(await byPath(it, 'profile'))) { failedUploads.push({ kind: kindStr, reason: 'We could not find that company profile in our records. Please upload it again.' }); continue; }
          upd[kind.pathCol] = String(it.path);
          if (kind.nameCol) upd[kind.nameCol] = safeFilename(it.filename || 'profile', String(it.mime || 'application/pdf')).slice(0, 200);
          readQueue.push({ path: String(it.path), name: String(it.filename || 'profile'), kind: 'profile', mime: it.mime ? String(it.mime) : undefined, gate: true });
        } else if (it.original_b64) {
          // A licence or certificate is read in this request (name, fields, expiry): above READ_MAX_BYTES it is refused before
          // it is decoded or parsed (a 24 MB licence was HTTP 546 here, 28 Oct; document_expiry.ts READ_MAX_BYTES).
          if (b64Size(it.original_b64) > READ_MAX_BYTES) { failedUploads.push({ kind: kindStr, reason: tooLargeToRead(b64Size(it.original_b64), kindStr === 'license' ? 'trade licence' : 'document').message }); continue; }
          // Previously any upload failure was swallowed and the kind was still reported as
          // saved, so a supplier could be told their trade licence was on file when the
          // storage write had failed. Failures are now returned to the caller.
          try {
            // AUDIT 9.1 (3 Aug 2026). These are trade licences, insurance certificates and ISO
            // certificates - documents an admin opens in a browser during review. Before this they
            // were stored as whatever the caller declared, defaulting to application/octet-stream,
            // with the extension taken from the caller's filename. The type is now decided from the
            // bytes and the extension is forced to match it.
            const sc = await sanitizeAndScan({ input: String(it.original_b64), declaredMime: it.mime, filename: it.filename || kindStr, allow: SAFE_UPLOAD,
                                               scan: { source: 'supplier_portal.' + kindStr, subject: String(sup.id), filename: it.filename, bucket: 'supplier-docs' } });
            if (!sc.ok) { failedUploads.push({ kind: kindStr, reason: String(sc.body.detail || sc.body.error) }); continue; }
            const s = sc.result;
            const clean = safeFilename(it.filename || kindStr, s.mime);
            const p = `${kind.folder}/${sup.id}/${Date.now()}_${clean}`;
            const { error: upErr } = await admin.storage.from('supplier-docs').upload(p, s.bytes, { contentType: s.mime, upsert: true });
            if (upErr) { failedUploads.push({ kind: kindStr, reason: upErr.message }); continue; }
            upd[kind.pathCol] = p;
            if (kind.nameCol) upd[kind.nameCol] = clean.slice(0, 200);
            stored = { bytes: s.bytes, mime: s.mime };
            if (kindStr === 'license' || kindStr === 'profile') readQueue.push({ path: p, name: clean, kind: kindStr === 'license' ? 'licence' : 'profile', bytes: s.bytes, mime: s.mime });
          } catch (e) { failedUploads.push({ kind: kindStr, reason: String((e as Error)?.message || e).slice(0, 200) }); continue; }
        }
        // #86: read the trade-licence expiry (and licence no / authority) SERVER-SIDE from the
        // uploaded document, so the expiry gate can't be bypassed with a self-typed date. The typed
        // value is used only as a fallback when extraction fails or the document has no clear date.
        let licExpiryFromDoc = false;
        let fieldsLeftUnread = false;
        // INSTRUCTION 524: code reads the date first. For every kind that carries an expiry the
        // stored bytes are read by _shared/document_expiry.ts (text-stream PDFs; a scan returns
        // null and is said so). The licence keeps #86 — a read date is written, a typed one never
        // is. Insurance / ISO / manufacturer: a typed date is written as before; a date read off
        // the document is RETURNED for the supplier to confirm (set_expiry) and never written
        // unconfirmed. Nothing is ever invented.
        let docRead: ExpiryRead | null = null;
        if (kind.expCol && stored) { try { docRead = await readExpiry(stored.bytes, stored.mime); } catch (_e) { docRead = null; } }
        // THE ROW CARRIES THE MODEL'S READING ONLY (12 Nov 2026, sales_engineer; founder rulings 1663, 1664; review of #1978, F1), as in
        // supplier_api process_docs. Code's name, number, authority, emirate, issue date and expiry were written here first; now a new
        // licence clears what the old one printed and only the model's reading is written. Code still reads the file: what it read is
        // the evidence of the disagreement note, never a value on the row, never shown, never an expiry acted on.
        let codeName: string | null = null;
        let codeFields: Partial<LicenceFields> = {};
        const keepAccepted = keepsAcceptedReading(sup.approval_status);
        if (kindStr === 'license' && stored) {
          try { codeName = await readLicenceName(stored.bytes, stored.mime); } catch (_e) { codeName = null; }
          try { codeFields = await readLicenceFields(stored.bytes, stored.mime); } catch (_e) { codeFields = {}; }
          // What the old licence printed never judges a new one (2 Nov 2026, ledger 1442): supplier_api clears these too. An APPROVED
          // supplier keeps the reading we accepted until this file's reading lands (_shared/licence_read_state.ts keepsAcceptedReading).
          if (!keepAccepted) {
            upd.licence_legal_name = null; upd.trade_license_no = null; upd.license_authority = null; upd.license_expiry = null; upd.doc_extracted_at = null;
            licIssue = null;
          }
          // THE MODEL READS EVERY LICENCE (rulings 1663, 1664): not only when code left a field unread (licenceNeedsModel).
          fieldsLeftUnread = true;
        }
        // code's licence expiry is evidence only (above); the certificate kinds below keep their own rule
        const codeLicenceExpiry = kindStr === 'license' ? docRead?.expiry ?? null : null;
        if (kindStr === 'license') docRead = null;
        if (kindStr === 'license' && docRead) {
          upd.license_expiry = docRead.expiry; licExpiryFromDoc = true; upd.doc_extracted_at = new Date().toISOString();
          read.license = { kind: 'license', expiry: docRead.expiry, source: 'text', needs_confirm: false, typed: null };
        } else if (kind.expCol && kindStr !== 'license' && stored) {
          const typed = it.expiry ? String(it.expiry).slice(0, 10) : null;
          if (docRead) read[kindStr] = { kind: kindStr, expiry: docRead.expiry, source: 'text', needs_confirm: !typed || typed !== docRead.expiry, typed };
          else if (aiOn && INBOUND_SECRET) {
            // The model path, only behind the flag: license_extract 'cert' mode already pulls the
            // governing date off an insurance schedule, ISO certificate or dealer letter.
            try {
              const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: INBOUND_SECRET, mode: 'cert', file_b64: String(it.original_b64), mime: it.mime, filename: it.filename }), signal: AbortSignal.timeout(MODEL_ANSWER_BUDGET_MS) });
              const jd = await r.json();
              if (jd?.ok && jd.found_expiry && jd.cert?.expiry_date) read[kindStr] = { kind: kindStr, expiry: String(jd.cert.expiry_date), source: 'ai', needs_confirm: true, typed };
            } catch (_e) { /* the honest 'unread' note below */ }
            if (!read[kindStr]) read[kindStr] = { kind: kindStr, expiry: null, source: null, needs_confirm: false, typed, unread: true, message: clearerCopyAsk('supplier', 'en', String(it.filename || kindStr)) };
          } else read[kindStr] = { kind: kindStr, expiry: null, source: null, needs_confirm: false, typed, unread: true, message: clearerCopyAsk('supplier', 'en', String(it.filename || kindStr)) };
        }
        // WHOSE FAILURE AN UNREAD FIELD IS (10 Nov 2026, customer_support; _shared/licence_read_state.ts): the same rule as
        // supplier_api process_docs. A model that is off, failed or had nothing to send is OUR failure, never the file's.
        let licModel: LicenceModelOutcome = 'not_needed';
        if (kindStr === 'license' && (!licExpiryFromDoc || fieldsLeftUnread)) licModel = !it.original_b64 ? 'not_sent' : !(aiOn && INBOUND_SECRET) ? 'off' : 'failed';
        if (kindStr === 'license' && !licExpiryFromDoc && it.original_b64 && !(aiOn && INBOUND_SECRET)) {
          read.license = { kind: 'license', expiry: null, source: null, needs_confirm: false, typed: null, unread: true, message: clearerCopyAsk('supplier', 'en', String(it.filename || kindStr)) };
        }
        if (kindStr === 'license' && (!licExpiryFromDoc || fieldsLeftUnread) && it.original_b64 && aiOn && INBOUND_SECRET) {
          try {
            const isImg = /^image\//.test(String(it.mime || ''));
            const payload: Record<string, unknown> = isImg
              ? { __secret: INBOUND_SECRET, mode: 'license', images: [{ b64: String(it.original_b64), mime: it.mime }] }
              : { __secret: INBOUND_SECRET, mode: 'license', file_b64: String(it.original_b64), mime: it.mime, filename: it.filename };
            // BOUNDED (11 Nov 2026, customer_support; _shared/licence_read_state.ts MODEL_ANSWER_BUDGET_MS). This call had no timeout and
            // sat before the one write that attaches the stored file: a model that hung held the answer to the edge's wall clock, the
            // portal gave up at 90 s and the file never reached the row. Past the budget it is 'failed' -> 'ours_failed': the file is
            // attached, the supplier is told the reading is ours, and supplier_api docs_reread reads it again.
            const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload), signal: AbortSignal.timeout(MODEL_ANSWER_BUDGET_MS) });
            const jd = await r.json();
            licModel = modelOutcomeOf(jd);
            // "this file cannot be read" is the new file's reading: the accepted one does not outlive it (the file is held)
            if (keepAccepted && licModel === 'unreadable') { Object.assign(upd, LICENCE_READINGS_CLEARED); licIssue = null; }
            if (jd?.ok && jd.doc && !jd.doc.unreadable) {
              const d = jd.doc;
              // THE MODEL'S READING IS THE READING (rulings 1663/1664): the one row rule supplier_api applies (modelReadingToRow).
              const r = modelReadingToRow(d, { fields: codeFields, expiry: codeLicenceExpiry, name: codeName, issue: licIssue });
              const { doc_extracted_at: _at, ...rowUpd } = r.upd;
              // the new reading replaces the accepted one WHOLE: a field it did not read is unread, never the old licence's value
              if (keepAccepted) Object.assign(upd, LICENCE_READINGS_CLEARED);
              Object.assign(upd, rowUpd); licIssue = (keepAccepted ? r.merged.issue_date : r.issue) ?? null;
              const expiry = (upd.license_expiry as string | null) ?? null;
              licExpiryFromDoc = !!expiry;
              if (expiry) read.license = { kind: 'license', expiry: String(expiry), source: 'ai', needs_confirm: false, typed: null };
              // the note for our reviewer never holds the supplier's answer, and its failure is only logged (review of #1978, F6)
              const w = afterResponse(recordLicenceReadNote(admin, sup.id, 'supplier_portal.save_documents', { disagreements: r.disagreements, check: jd.check ?? null, path: upd.license_doc_path }), 'supplier_portal.save_documents.licence_read_note');
              if (w) w.catch(() => {});
              // The scan's activities, as the model read them, are read for trades like a text licence's (ruling 1177).
              const q = readQueue.find((x) => x.kind === 'licence');
              if (q) q.photo_text = modelReadText('licence', d.activities);
              upd.doc_extracted_at = new Date().toISOString();
            }
          } catch (_e) { /* fall back to the typed value below */ }
          if (!licExpiryFromDoc) read.license = { kind: 'license', expiry: null, source: null, needs_confirm: false, typed: null, unread: true, message: clearerCopyAsk('supplier', 'en', String(it.filename || kindStr)) };
        }
        if (kindStr === 'license' && stored) {
          const state = licenceReadState(licenceLeftUnread(upd), licModel);
          upd.licence_read_state = state; upd.licence_read_at = new Date().toISOString();
          // the supplier is never asked for a clearer copy of a licence OUR reader failed on
          if (state === 'ours_failed') read.license = { kind: 'license', expiry: null, source: null, needs_confirm: false, typed: null, unread: true, being_read: true, message: LICENCE_BEING_READ_NOTE };
          // staff are told the fields on file are the previously accepted reading while this file is read (review of #1982, L3-2)
          if (state === 'ours_failed' && keepAccepted) acceptedKeptFor = String(upd.license_doc_path ?? '');
        }
        // LICENCE EXPIRY FIX 27 Jul 2026. The fallback above ran whenever extraction had not produced
        // a date - including when NO document was attached at all, since the extraction block requires
        // it.original_b64. A supplier could therefore POST { kind:'license', expiry:'2030-01-01' } with
        // no file and push their own licence expiry three years out, which defeats the whole point of
        // #86 and of fn_reconcile_doc_blocks (the daily job that suspends matching on an expired
        // licence). license_expiry is now only ever written from what license_extract read off the
        // document; a typed licence expiry is never trusted. Other kinds keep the typed value - none of
        // them is read server-side and none of them is self-asserted against an automatic suspension.
        if (kindStr === 'license') {
          if (!licExpiryFromDoc && it.expiry) {
            failedUploads.push(it.original_b64
              ? { kind: kindStr, reason: 'Your trade licence file was saved, but we could not read the expiry date from it, so the expiry on file is unchanged. Please upload a clear copy of the full licence page (PDF or a sharp photo).' }
              : { kind: kindStr, reason: 'A trade licence document is required. The licence expiry is read from the licence itself and cannot be entered by hand — please attach your current trade licence.' });
            if (!it.original_b64) continue;
          }
        } else if (kind.expCol && it.expiry) upd[kind.expCol] = String(it.expiry).slice(0, 10);
        saved.push(kindStr);
      }
      if (catAppend.length) {
        const { data: cur } = await admin.from('leads').select('catalog_doc_paths').eq('id', sup.id).maybeSingle();
        const existing: string[] = Array.isArray(cur?.catalog_doc_paths) ? (cur!.catalog_doc_paths as string[]) : [];
        upd.catalog_doc_paths = [...existing, ...catAppend].slice(0, 20);
      }
      // 5 Aug 2026. The uploads above report per-file outcomes in `saved`/`failed`, but THIS write
      // is what attaches any of them to the supplier. Its result was discarded, so a failed write
      // reported every file as saved while no path ever reached the row — the same defect as
      // supplier_api's process_docs and save_profile.
      if (Object.keys(upd).length > 1) {
        // A licence number another claimed company holds is set aside, the rest of the row is written,
        // and the clash goes to a human (_shared/duplicate_company.ts, review of #962).
        const { error: updErr, licenceSetAside } = await updateLeadSettingAsideClashingLicence(admin as unknown as LeadWriter, sup.id, upd, 'supplier_portal.save_documents');
        if (licenceSetAside) { licenceNotice = true; failedUploads.push({ kind: 'license', reason: COMPANY_ALREADY_REGISTERED.error }); }
        if (updErr) {
          // SP-I-01, the one that survived #858 (review, 22 Sep 2026): this still put the raw
          // Postgres text in `detail` for the browser. Same treatment as the other thirteen — the
          // real message goes to the function log, the supplier gets the stable code.
          return failed('save_documents', 'save_failed', 'Your files were uploaded but could not be attached to your profile. Please try again.', updErr, 502);
        }
      }
      if (acceptedKeptFor) { const w = afterResponse(recordAcceptedReadingKept(admin, sup.id, 'supplier_portal.save_documents', acceptedKeptFor), 'supplier_portal.save_documents.accepted_reading_kept'); if (w) w.catch(() => {}); }
      if (licIssue !== undefined) { const ri = await admin.from('leads').update({ license_issue_date: licIssue }).eq('id', sup.id); if (ri.error) console.error('save_documents: licence issue date not saved —', ri.error.message); }
      // REPLACE KEEPS THE PREVIOUS VERSION. After the row write succeeded, every column that held a
      // file and now holds another becomes a doc_versions row (entity 'supplier_document',
      // '<lead>:<kind>'). The old object stays in storage and in the Dropbox backup.
      const versioned: string[] = [];
      for (const [kindStr, k] of Object.entries(DOC_KINDS)) {
        const prev = before[k.pathCol] as string | null;
        if (!prev || upd[k.pathCol] === undefined || upd[k.pathCol] === prev) continue;
        const snap: VersionSnapshot = { event: 'replaced', kind: kindStr, path: prev, name: (k.nameCol ? (before[k.nameCol] as string) : null) || prev.split('/').pop() || null,
          expiry: k.expCol ? ((before[k.expCol] as string) || null) : null, at: new Date().toISOString() };
        const { data: v } = await admin.rpc('_next_docver', { p_type: 'supplier_document', p_id: `${sup.id}:${kindStr}` });
        const { error: vErr } = await admin.from('doc_versions').insert(versionRow(Number(sup.id), snap, Number(v || 1)));
        if (!vErr) versioned.push(kindStr); else console.error('save_documents: version row failed —', vErr.message);
      }
      // READ AFTER THE ANSWER (19 Oct 2026, sales_engineer; _shared/supplier_docs_later.ts): each document is marked 'reading'
      // now, so the list below already says so, and is read after the response. A PHOTO-ONLY COMPANY PROFILE IS READ TOO
      // (ruling 1177), as supplier_api.process_docs reads it: the picture goes to license_extract's profile mode and the
      // services it reads are read for trades through photo_text.
      const later = readQueue.slice(0, 7);
      if (later.length) {
        const markErr = await markReading(admin, Number(sup.id), later);
        if (markErr) console.error(JSON.stringify({ at: 'supplier_portal.save_documents.markReading', supplier: sup.id, error: markErr }));
        // A PICTURE OR A SCANNED PDF is read by the same model the licence uses, with the licence's two attempts (2 Nov 2026, ledger 1442:
        // "is our agent actually reading the company profile"). Before, only a picture was sent and a scanned PDF stayed needs_ocr.
        // When the model cannot read it the document stays needs_ocr: never a false "no trades".
        const profile = async (d: LaterDoc) => {
          if (!(aiOn && INBOUND_SECRET)) return;
          await readProfileByModel(d, async (b) => {
            const r = await fetch(`${SUPA_URL}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: INBOUND_SECRET, mode: 'profile', ...b }), signal: AbortSignal.timeout(120_000) });
            const jd = await r.json().catch(() => null);
            return { ...(jd ?? {}), status: r.status };
          }, { subject: { supplier_id: Number(sup.id), email }, admin });
        };
        const w = afterResponse(readStoredDocsLater(admin, Number(sup.id), later, { profile, catalogue: profile }), 'supplier_portal.save_documents.later'); if (w) await w;
      }
      // The fresh list rides on the answer (finding 16): what the row holds NOW, not what the tab guessed.
      const fresh = await listDocuments(Number(sup.id));
      return J({ ok:true, saved, failed: failedUploads, ...(licenceNotice ? { licence_set_aside: true, licence_notice: COMPANY_ALREADY_REGISTERED } : {}), read, versioned, documents: fresh.documents, expiries: fresh.expiries, summary: fresh.summary, ...(later.length ? { documents_reading: later.map((d) => d.path) } : {}) });
    }

    // REMOVE HIDES, NEVER DESTROYS (instruction 524). The column is cleared and what it held goes to
    // doc_versions; the storage object and its backup stay. Refused, with a readable reason, on a
    // mandatory-six document of an approved supplier (./document_actions.ts). A sanctioned party is
    // refused above the switch. Catalogues: one path out of the array, the same way.
    if (action === 'remove_document') {
      const kindStr = String(b.kind || '');
      if (kindStr === 'catalogs') {
        const path = String(b.path || '');
        const { data: cur } = await admin.from('leads').select('catalog_doc_paths').eq('id', sup.id).maybeSingle();
        const list: string[] = Array.isArray(cur?.catalog_doc_paths) ? (cur!.catalog_doc_paths as string[]) : [];
        if (!path || !list.includes(path)) { const r = removeRefusal({ kind: kindStr, known: true, onFile: false, required: false, approval_status: sup.approval_status })!; return J({ ok: false, error: 'remove_refused', code: r.code, message: r.message }, 409); }
        const { error } = await admin.from('leads').update({ catalog_doc_paths: list.filter((p) => p !== path), portal_updated_at: new Date().toISOString() }).eq('id', sup.id);
        if (error) return failed('remove_document', 'remove_failed', 'We could not remove that document. Please try again.', error, 502);
        const snap: VersionSnapshot = { event: 'removed', kind: 'catalogs', path, name: path.split('/').pop() || null, expiry: null, at: new Date().toISOString() };
        const { data: v } = await admin.rpc('_next_docver', { p_type: 'supplier_document', p_id: `${sup.id}:catalogs` });
        await admin.from('doc_versions').insert(versionRow(Number(sup.id), snap, Number(v || 1)));
        return J({ ok: true, removed: 'catalogs', path });
      }
      const kind = DOC_KINDS[kindStr];
      const cols = kind ? [kind.pathCol, kind.nameCol, kind.expCol].filter(Boolean) as string[] : [];
      const { data: cur } = kind ? await admin.from('leads').select(cols.join(',')).eq('id', sup.id).maybeSingle() : { data: null };
      const row = (cur || {}) as Record<string, unknown>;
      const prev = kind ? (row[kind.pathCol] as string | null) : null;
      const refusal = removeRefusal({ kind: kindStr, known: !!kind, onFile: !!prev, required: REQUIRED_DOC_KEYS.includes(kindStr), approval_status: sup.approval_status });
      if (refusal || !kind || !prev) { const r = refusal!; return J({ ok: false, error: 'remove_refused', code: r.code, message: r.message }, r.code === 'mandatory_of_approved' ? 409 : 400); }
      const clear: Record<string, unknown> = { [kind.pathCol]: null, portal_updated_at: new Date().toISOString() };
      if (kind.nameCol) clear[kind.nameCol] = null;
      if (kind.expCol) clear[kind.expCol] = null;
      const { error } = await admin.from('leads').update(clear).eq('id', sup.id);
      if (error) return failed('remove_document', 'remove_failed', 'We could not remove that document. Please try again.', error, 502);
      const snap: VersionSnapshot = { event: 'removed', kind: kindStr, path: prev, name: (kind.nameCol ? (row[kind.nameCol] as string) : null) || prev.split('/').pop() || null,
        expiry: kind.expCol ? ((row[kind.expCol] as string) || null) : null, at: new Date().toISOString() };
      const { data: v } = await admin.rpc('_next_docver', { p_type: 'supplier_document', p_id: `${sup.id}:${kindStr}` });
      await admin.from('doc_versions').insert(versionRow(Number(sup.id), snap, Number(v || 1)));
      const fresh = await listDocuments(Number(sup.id));
      return J({ ok: true, removed: kindStr, documents: fresh.documents, expiries: fresh.expiries, summary: fresh.summary });
    }

    // THE SUPPLIER CONFIRMS A DATE THE DOCUMENT WAS READ TO SAY (instruction 524). Only for the kinds
    // whose expiry a supplier may state — never the licence, whose date is written from the licence
    // alone (#86). The value is what the portal showed them, or what they corrected it to.
    if (action === 'set_expiry') {
      const kindStr = String(b.kind || '');
      const kind = DOC_KINDS[kindStr];
      if (!kind || !kind.expCol || kindStr === 'license') return J({ error: 'expiry_not_settable', kind: kindStr }, 400);
      const expiry = String(b.expiry || '').slice(0, 10);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(expiry) || isNaN(Date.parse(expiry))) return J({ error: 'bad_expiry' }, 400);
      const { data: cur } = await admin.from('leads').select(kind.pathCol).eq('id', sup.id).maybeSingle();
      if (!(cur as Record<string, unknown> | null)?.[kind.pathCol]) return J({ error: 'nothing_on_file', kind: kindStr }, 409);
      const { error } = await admin.from('leads').update({ [kind.expCol]: expiry, portal_updated_at: new Date().toISOString() }).eq('id', sup.id);
      if (error) return failed('set_expiry', 'expiry_save_failed', 'We could not save that expiry date. Please try again.', error, 502);
      const fresh = await listDocuments(Number(sup.id));
      return J({ ok: true, kind: kindStr, expiry, documents: fresh.documents, expiries: fresh.expiries, summary: fresh.summary });
    }
}
