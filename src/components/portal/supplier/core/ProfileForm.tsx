// @ts-nocheck
'use client';
import { useEffect, useRef, useState } from 'react';
import { useFailover } from '@/lib/otpFailover';
import EmirateCheckboxes from '../EmirateCheckboxes';
import { srvMsg, srvText } from '../serverCopy';
import { call, freshToken, REASONING_TIMEOUT_MS, tooBigToRead, sizeMb } from '../api';
import { uaeMobile } from '../uaeMobile';
import { WhatsAppChoice } from '../../WhatsAppChoice';
import { waSignupSettled } from '../../whatsappChoiceText';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { Need, Lbl, FilePick, UploadBar } from './helpers';
import { uploadDirect, preparePhoto } from './upload';
import { t } from './copy';
import { S } from './styles';
import { AgreementSheet } from './AgreementSheet';
import { expiredLicenceNote, licenceHasExpired, licenceBeingRead, licenceDate, LICENCE_BEING_READ_NOTE } from '../licenceExpiry';
import { answerWasLost, awaitLateLicenceRead, licenceStoredSince, recheckLicenceStored, waitsForLateRead, LICENCE_READING_NOTE, LICENCE_RECEIVED_NOTE } from '../licenceReceived';
import { readKycState, kycAnswered, kycItemsMissing, localKycMissing } from '../mobileState';
import { licenceFileProblem, paperFileProblem, LICENCE_ACCEPT, PAPER_ACCEPT } from '../fileCheck';
import { draftKey, draftOf, saveDraft, readDraft, clearRegistrationDrafts, chooseAgainNote } from '../registrationDraft';

// The tab's own sessionStorage, or nothing (a private window can refuse it; registrationDraft.ts wraps every call).
const tabStore = () => { try { return window.sessionStorage; } catch (_e) { return null; } };
// A REFUSAL THAT IS THE CONNECTION'S IS NAMED AS THE CONNECTION'S (12 Nov 2026, customer_support; browser walk M6): call() answers
// `network` / `timeout` and serverCopy gives both one sentence; a dropped upload is `network` (upload.ts).
const lostLine = (j) => !!j && (j.code === 'network' || j.code === 'timeout' || j.status === 0);

// `mode` distinguishes first-time REGISTRATION (Onboarding) from an established supplier
// EDITING their profile (the Profile tab). Document uploads (trade licence, company profile,
// catalogues) are shown only during registration. In edit mode they are hidden and the supplier
// is pointed to the Documents tab, which is the single home for every document file — the same
// file is never asked for in two places.
//
// EVERY ANSWER WHERE HE LOOKS, AND EVERY PRESS SHOWS IT IS WORKING (12 Nov 2026, customer_support; browser perfection walk H1, H2,
// H7, M2, M4, M8, M16, M17, M21; founder ruling 1645: "some buttons are not clickable, there is no loading animation when you are
// submitting something"). Measured on production at 390x844: every mid-form error was one line under Submit, 459-1,046 px from
// the control pressed; nothing moved during any submit (1.1-10.1 s). Now each step has its own message under its own control
// (licErr, mobileErr, mailErr; Submit's own is scrolled into view and focused), each press shows a turning ring (Button busy), an
// upload shows its progress, Submit says each step it is on, and what he typed survives a reload (../registrationDraft.ts).
// Prevented by: scripts/checks/the_registration_form_answers_where_he_looks.test.mjs and the unit tests it names.
function ProfileForm({ token, me, onSaved, lang, mode = 'register' }) {
  const isEdit = mode === 'edit';
  const ar = lang === 'ar';
  // The token in use: a 401 at any step is refreshed once (api.ts freshToken) and the step asked again with the new one (M7).
  const tok = useRef(token);
  useEffect(() => { tok.current = token; }, [token]);
  const fresh = async (j) => { if (!(j && j._expired)) return null; const nt = await freshToken(); if (nt) tok.current = nt; return nt; };
  // What he had typed before a reload, for this account only (H7). Not in edit mode: an approved company's profile is the row's.
  const dKey = draftKey(me); const owner = String(me.claimed_by || me.id || '');
  const draft = useRef(undefined);
  if (draft.current === undefined) draft.current = isEdit ? null : readDraft(tabStore(), dKey, owner);
  const d0 = draft.current;
  const [f, setF] = useState({
    contact_name: (d0 && d0.contact_name) || me.contact_name || '', signatory_name: me.signatory_name || '', owner_dob: me.owner_dob || '', phone: (d0 && d0.phone) || me.phone || '',
    products: me.products || '', services: me.services || '', description: me.description || '',
    trade_license_no: me.trade_license_no || '', license_authority: me.license_authority || '', license_expiry: me.license_expiry || '',
    trn: me.trn || '', egr_number: me.egr_number || '', founded_year: me.founded_year || '', company_type: me.company_type || '', company_size: me.company_size || '',
  });
  const [emirates, setEmirates] = useState((d0 && d0.emirates.length && d0.emirates) || me.service_emirates || []); const [terms, setTerms] = useState(!!me.accepted_terms_at || !!(d0 && d0.terms));
  // Promotional messages are opt-in (19 Oct 2026, founder, legal finding 2): a SEPARATE box, never pre-ticked,
  // never required. Guarded by scripts/checks/promotional_messages_are_opt_in.test.mjs.
  // Not restored from a draft: the box is his act each time it is ticked (scripts/checks/promotional_messages_are_opt_in.test.mjs).
  const [marketingOptIn, setMarketingOptIn] = useState(false);
  const [profileFile, setProfileFile] = useState(null); const [catalogFiles, setCatalogFiles] = useState([]); const [catCut, setCatCut] = useState(false); const [docsSent, setDocsSent] = useState(false);
  const [profErr, setProfErr] = useState('');
  const [phoneVerified, setPhoneVerified] = useState(false); const [smsSent, setSmsSent] = useState<string | false>(false); const [smsCode, setSmsCode] = useState('');
  // vbusy names the press that is working ('wa' | 'sms' | 'verify_sms' | 'mail' | 'verify_mail'), so only that button turns.
  const [vbusy, setVbusy] = useState('');
  const [mobileErr, setMobileErr] = useState(''); const [mailErr, setMailErr] = useState(''); const [mailNote, setMailNote] = useState('');
  const [emailVerified, setEmailVerified] = useState(!!me.owner_email_verified); const [mailSent, setMailSent] = useState(false); const [mailCode, setMailCode] = useState('');
  // wa: kyc's `whatsapp` answer. Registration waits for it (founder, 15 Sep 2026: "It's in the sign
  // up"): save() lists it as missing and supplier_api save_profile refuses without it (reg_whatsapp).
  const [wa, setWa] = useState(undefined);
  const [saved, setSaved] = useState(false);
  const [agreementOpen, setAgreementOpen] = useState(false);
  // SAVE WAITS FOR THE KYC STATE (run 71b75b60, en/mobile): Save pressed before this read resolved checked a
  // phoneVerified that was still its initial false, refused "missing mobile" on screen in 36 ms and sent nothing.
  const [kycRead, setKycRead] = useState(false);
  // THE MOBILE IS THE SERVER'S (11 Nov 2026, customer_support; certification run 1, J4: the one read was lost at the 20 s abort
  // and the form said "not verified" for good). Only kyc's own answer is applied, so a lost read never overwrites an earlier
  // answer; a lost read is asked again, and the button waits only for the first try (../mobileState.ts).
  const readKyc = () => call('kyc', { action: 'state' }, tok.current);
  const applyKyc = (k) => {
    if (!kycAnswered(k)) return false;
    if (k.phone_verified) setPhoneVerified(true); if (k.email_verified) setEmailVerified(true); setWa(k.whatsapp);
    if (k.phone) setF((o) => (String(o.phone || '').trim() ? o : { ...o, phone: String(k.phone) }));
    return true;
  };
  const loadKyc = () => readKycState(readKyc, { onLost: () => setKycRead(true) }).then(applyKyc).finally(() => setKycRead(true));
  useEffect(() => { loadKyc(); }, []);
  // WhatsApp first (kyc nextChannel, 18 Oct 2026); smsSent holds the channel that carried the code, 'sms' is the explicit failover.
  const failover = useFailover();
  const kyc = async (body) => { let j = await call('kyc', body, tok.current); if (await fresh(j)) j = await call('kyc', body, tok.current); return j; };
  const sendSms = async (channel?: 'sms' | 'whatsapp') => { const e164 = uaeMobile(f.phone); if (!e164) { setMobileErr(t(lang, 'mobile_format')); return; } if (e164 !== f.phone) set('phone', e164); setVbusy(channel === 'sms' ? 'sms' : 'wa'); setMobileErr(''); const j = await kyc({ action: 'send_sms', phone: e164, ...(channel ? { channel } : {}) }); setVbusy(''); if (j && j.ok) { setSmsSent(j.channel || 'sms'); if (j.channel === 'whatsapp') failover(() => call('kyc', { action: 'phone_failover', phone: e164 }, tok.current), () => setSmsSent('sms_failover')); } else setMobileErr(srvMsg(lang, j, t(lang, 'could_not_sms'))); };
  // A verify whose answer was lost asks kyc whether the number is now verified before it says "wrong code": the code is used
  // once, so a second try with it would be refused even though the first one took (../mobileState.ts).
  const verifySms = async () => {
    if (!smsCode.trim()) { setMobileErr(t(lang, 'le_enter_code')); return; }
    setVbusy('verify_sms'); setMobileErr('');
    const j = await kyc({ action: 'verify_sms', phone: f.phone, code: smsCode });
    if (j && j.ok) { setVbusy(''); setPhoneVerified(true); return; }
    const k = answerWasLost(j) ? await readKycState(readKyc, { tries: 2 }) : null;
    setVbusy('');
    if (applyKyc(k) && k.phone_verified) return;
    setMobileErr(srvMsg(lang, j, t(lang, 'wrong_code')));
  };
  // E-MAIL, THE ONE ITEM OF THE SIX WITH NO BUTTON (14 Sep 2026). The form showed "e-mail not yet
  // verified" with nothing to press, and save_profile now requires it. kyc send_email / verify_email
  // already existed; this is their caller. (supplier_api also records it from the sign-up OTP, so most
  // suppliers will never see this.)
  const sendMail = async () => { setVbusy('mail'); setMailErr(''); setMailNote(''); const j = await kyc({ action: 'send_email' }); setVbusy(''); if (j && j.ok) { setMailSent(true); setMailNote(t(lang, 'email_sent')); } else setMailErr(srvMsg(lang, j, t(lang, 'could_not_email'))); };
  const verifyMail = async () => { if (!mailCode.trim()) { setMailErr(t(lang, 'le_enter_code')); return; } setVbusy('verify_mail'); setMailErr(''); const j = await kyc({ action: 'verify_email', code: mailCode }); setVbusy(''); if (j && j.ok) { setEmailVerified(true); setMailNote(''); } else setMailErr(srvMsg(lang, j, t(lang, 'wrong_code'))); };
  // An expired licence is said at the upload, not first at Submit (11 Nov 2026, registration certification finding 6): licExpired
  // turns the note into an alert with what to do (../licenceExpiry.ts). A licence already on file that has expired says so on load.
  const [licExpired, setLicExpired] = useState(!!me.license_doc_path && licenceHasExpired(me.license_expiry));
  const [uploading, setUploading] = useState(false); const [licNote, setLicNote] = useState(me.license_doc_path ? (licenceHasExpired(me.license_expiry) ? expiredLicenceNote(me.license_expiry, me.trade_license_no) : t(lang, 'lic_on_file')) : '');
  const [licOnFile, setLicOnFile] = useState(!!me.license_doc_path);
  // The licence step's own line for what went wrong (H1), what it is doing now (H2) and the file to try again with (B1, M6).
  const [licErr, setLicErr] = useState(''); const [licStage, setLicStage] = useState(''); const [licProgress, setLicProgress] = useState(null); const [licRetry, setLicRetry] = useState(null);
  // The licence file the row names as far as this form knows: a lost answer is rechecked against it (../licenceReceived.ts).
  const licPath = useRef(String(me.license_doc_path || ''));
  const readRow = () => call('supplier_api', { action: 'me' }, tok.current).then((r) => (r && r.supplier) || null);
  // One upload's second look at a reading that lands after the answer (../licenceReceived.ts awaitLateLicenceRead). A newer upload
  // or leaving the form moves the counter, which stops it.
  const licUpload = useRef(0);
  useEffect(() => () => { licUpload.current++; }, []);
  // The licence step's sentence for what was read: the number, the expiry as a reader writes a date (L1: "3 May", not ISO), or
  // that it has expired.
  const readNote = (no, expiry) => t(lang, 'read_lic') + (no ? ' — ' + no : '') + (expiry ? t(lang, 'expires_comma') + licenceDate(expiry) : '') + '.';
  const showLicenceRead = (no, authority, expiry) => {
    setF((o) => ({ ...o, trade_license_no: no || o.trade_license_no, license_authority: authority || o.license_authority, license_expiry: expiry || o.license_expiry }));
    const gone = licenceHasExpired(expiry); setLicExpired(gone);
    setLicNote(gone ? expiredLicenceNote(expiry, no) : readNote(no, expiry));
  };
  const [busy, setBusy] = useState(false); const [msg, setMsgNow] = useState('');
  // Submit's own refusal, as the codes of the missing items: shown only while one is still missing (M4: ticking the agreement
  // took "Still needed to register: Signed supplier terms." away from nothing).
  const [missing, setMissing] = useState([]);
  const [stage, setStage] = useState(''); const [stageProgress, setStageProgress] = useState(null);
  const submitMsg = useRef(null);
  const set = (k, v) => setF((o) => ({ ...o, [k]: v }));
  // THE LICENCE DEAD-END (audit 2026-09-14, BLOCKS CONVERSION). After any upload licNote became
  // non-empty ("Licence uploaded." when extraction returned nothing), which HID the typed licence-number
  // field, while save() still refused without a number. Under the OpenRouter hold license_extract never
  // returns, so every new supplier could neither type the number nor submit. Now: the upload itself
  // counts as the licence (the server's gate is path OR number, and the mandatory six say the same),
  // the number field is always shown, and extraction only fills it in when it happens to answer.
  // A failed STORE is reported as a failure instead of being announced as "uploaded".
  // THE LICENCE GOES STRAIGHT TO STORAGE, SMALL (12 Nov 2026, customer_support; browser walk B1, M1, M2, M6). It went as base64
  // three times in one request (original_b64, file_b64, images): a 4.32 MB phone photo was 17.29 MB, and at 1.5 Mbit/s up it was
  // cut off at 102 s with "We could not store your licence file. Please try again with a PDF or a clear photo." Now a wrong type
  // or an empty file is refused here at once (../fileCheck.ts), a photo is made small (upload.ts preparePhoto), the file goes up
  // once on a signed URL with its progress shown (upload.ts uploadDirect 'licence'), and process_docs is given its path
  // (supplier_api/actions/documents.ts reads, gates and stores it exactly as the inline file). A failure keeps the file chosen,
  // so "Try again" is one tap, and leaves the licence already on file as it was said ("Done" only for a stored, in-date licence).
  const upLicense = async (file) => {
    if (!file) return;
    const picked = file; const before = licPath.current; const was = { note: licNote, expired: licExpired };
    setLicErr(''); setLicRetry(null);
    const upload = ++licUpload.current;
    const wrong = licenceFileProblem(file);
    if (wrong) { setLicErr(wrong); return; }
    setLicNote(''); setLicExpired(false); setUploading(true); setLicStage('preparing'); setLicProgress(null);
    const fail = (line, retry = false) => { setLicErr(line); if (retry) setLicRetry(picked); setLicNote(was.note); setLicExpired(was.expired); setLicStage(''); setLicProgress(null); setUploading(false); };
    try {
      file = await preparePhoto(file);
      // The read ceiling, after a photo has been made small (api.ts MAX_READ_BYTES; a PDF is as it was picked).
      if (tooBigToRead(file)) { fail(srvText(lang, 'file_too_large_read', { mb: sizeMb(file) })); return; }
      setLicStage('uploading'); setLicProgress(0);
      const progress = (p) => { if (licUpload.current === upload) setLicProgress(p); };
      let d = await uploadDirect('licence', file, tok.current, progress);
      if (d.error && (await fresh(d.error))) d = await uploadDirect('licence', file, tok.current, progress);
      if (licUpload.current !== upload) return;
      if (d.error) { fail(srvMsg(lang, d.error, t(lang, 'lic_upload_failed')), true); return; }
      setLicStage('reading'); setLicProgress(null);
      // The row names the file before anything reads it, and the model holds the answer at most MODEL_ANSWER_BUDGET_MS (10 s;
      // supplier_api/lib/licence_store_first.ts). The reasoning wait stays the ceiling for a slow scan.
      const token = tok.current;
      let j = await call('supplier_api', { action: 'process_docs', license: { path: d.path, filename: d.filename, mime: d.mime } }, token, { timeoutMs: REASONING_TIMEOUT_MS });
      if (await fresh(j)) j = await call('supplier_api', { action: 'process_docs', license: { path: d.path, filename: d.filename, mime: d.mime } }, tok.current, { timeoutMs: REASONING_TIMEOUT_MS });
      if (licUpload.current !== upload) return;
      // A LOST ANSWER IS NOT A REFUSAL (11 Nov 2026, customer_support; certification run 2, J5: stored at 1.7 s, the browser cut off
      // at ~30 s, the screen said "could not store"). The row is read again; a licence newer than the one on file before this upload
      // is shown as received. Only our own refusal, or a row that never names the file, is said as a failure.
      const kept = !(j && j.ok) && answerWasLost(j) ? await recheckLicenceStored(readRow, before) : null;
      setLicStage(''); setUploading(false);
      if (kept) {
        licPath.current = String(kept.license_doc_path); setLicOnFile(true);
        setF((o) => ({ ...o, trade_license_no: kept.trade_license_no || o.trade_license_no, license_authority: kept.license_authority || o.license_authority, license_expiry: kept.license_expiry || o.license_expiry }));
        setLicNote(LICENCE_RECEIVED_NOTE);
      }
      else if (!(j && j.ok)) { fail(j && j._expired ? t(lang, 'session_ended_form') : srvMsg(lang, j, t(lang, 'lic_upload_failed')), lostLine(j) || answerWasLost(j)); }
      // "Done" only for a file the server says it now holds (M2: an empty file used to be announced "Licence uploaded").
      else if (!(j.extracted && j.extracted.license_doc_path)) { fail(t(lang, 'lic_upload_failed'), true); }
      else {
        setLicOnFile(true); licPath.current = String(j.extracted.license_doc_path);
        const ex = (j.extracted && j.extracted.license) || null;
        if (ex) { setF((o) => ({ ...o, trade_license_no: ex.license_number || o.trade_license_no, license_authority: ex.authority || o.license_authority, license_expiry: ex.expiry || o.license_expiry, trn: ex.trn || o.trn })); const gone = licenceHasExpired(ex.expiry); setLicExpired(gone); setLicNote(gone ? expiredLicenceNote(ex.expiry, ex.license_number) : readNote(ex.license_number, ex.expiry)); }
        else setLicNote(t(lang, 'lic_uploaded_type'));
        // our reader has not finished (a photo or scan during a model outage): said as ours, never as a request to the supplier
        if (licenceBeingRead(j.extracted)) { setLicExpired(false); setLicNote(LICENCE_BEING_READ_NOTE); }   // process_docs answers { extracted: { license_read_state } }
        // THE READING LANDS AFTER THE ANSWER (final audit R2, 12 Nov 2026): when our reader has not read it, the row is read again until it
        // does, and what it read is shown; a licence code already read (or found expired) keeps its own sentence
        if (waitsForLateRead(j.extracted) && licPath.current) {
          const path = licPath.current;
          setLicExpired(false); setLicNote(LICENCE_READING_NOTE);
          awaitLateLicenceRead(readRow, path, { stop: () => licUpload.current !== upload }).then((row) => {
            if (licUpload.current !== upload) return;
            if (!row) { setLicNote(LICENCE_BEING_READ_NOTE); return; }
            if (row.trade_license_no || row.license_authority || row.license_expiry) showLicenceRead(row.trade_license_no, row.license_authority, row.license_expiry);
            else setLicNote(t(lang, 'lic_uploaded_type'));
          });
        }
        // The document was saved but its licence number belongs to another claimed company, so the number
        // was set aside for a human (supabase/functions/_shared/duplicate_company.ts). Existing copy.
        if (j.extracted && j.extracted.licence_set_aside) setLicErr(srvText(lang, 'company_already_registered'));
      }
    } catch (_e) { fail(t(lang, 'lic_upload_failed'), true); }
  };
  // A profile or catalogue that cannot go is said at the pick, under its own control (M1); it is uploaded at Submit.
  const pickProfile = (fl) => { if (!fl) return; const p = paperFileProblem(fl, 'company profile'); setProfErr(p || ''); if (p) return; setProfileFile(fl); setDocsSent(false); };
  const pickCatalogues = (a) => { const all = (a || []).filter((x) => !paperFileProblem(x, 'catalogue')); const bad = (a || []).find((x) => paperFileProblem(x, 'catalogue')); setProfErr(bad ? paperFileProblem(bad, 'catalogue') : ''); setCatalogFiles(all.slice(0, 5)); setCatCut(all.length > 5); setDocsSent(false); };
  // WHAT HE TYPED IS KEPT FOR THIS TAB (H7): the fields and the files' names, a moment after each change; never a code or a file.
  useEffect(() => {
    if (isEdit) return undefined;
    const id = setTimeout(() => saveDraft(tabStore(), dKey, draftOf(owner, { emirates, phone: f.phone, contact_name: f.contact_name, terms, marketing: marketingOptIn, profileFile, catalogFiles })), 300);
    return () => clearTimeout(id);
  }, [emirates, f.phone, f.contact_name, terms, marketingOptIn, profileFile, catalogFiles]);
  const chooseAgain = chooseAgainNote(d0, { profile: !profileFile && !me.company_profile_doc_path, catalogues: !catalogFiles.length });
  // Submit's refusal names only what is still missing now (M4).
  const stillMissing = missing.filter((c) => !((c === 'reg_terms' && terms) || (c === 'reg_profile' && (profileFile || me.company_profile_doc_path)) || (c === 'reg_licence' && licOnFile)
    || (c === 'reg_mobile' && phoneVerified) || (c === 'reg_email' && emailVerified) || (c === 'reg_whatsapp' && waSignupSettled(wa))));
  const bottomMsg = msg || (stillMissing.length ? srvText(lang, 'missing_required', { missing: stillMissing }) : '');
  // Submit's answer is brought to where he is looking and given the focus (H1: on 1440x900 it sat 8 px below the screen). Every
  // sentence Submit says goes through setMsg, which also ends the step line above it.
  const bringUp = () => requestAnimationFrame(() => { const el = submitMsg.current; if (!el) return; el.scrollIntoView({ block: 'center', behavior: 'smooth' }); el.focus({ preventScroll: true }); });
  const setMsg = (m) => { setMsgNow(m); if (m) { setStage(''); setStageProgress(null); bringUp(); } };
  const tellMissing = (codes) => { setMsgNow(''); setMissing(codes); bringUp(); };
  const save = async () => {
    setMissing([]); setMsg('');
    // The mandatory six, checked here in the same order and with the same codes save_profile enforces
    // (supabase/functions/_shared/supplier_registration.ts), so the refusal a supplier sees on screen
    // and the one the server would give cannot disagree. An approved company editing its profile is
    // not re-gated — the server does not re-gate it either.
    if (me.approval_status !== 'approved') {
      const missing = [];
      // The mobile, the e-mail and the WhatsApp answer are the SERVER's: when this form's copy says one is missing, kyc is asked
      // before it is listed, and with no answer at all none is listed here and save_profile decides on the row (../mobileState.ts).
      let kycMissing = localKycMissing({ phoneVerified, emailVerified, wa });
      if (kycMissing.length) {
        setBusy(true); setStage('checking');
        const k = await readKycState(readKyc, { tries: 2 });
        setBusy(false); setStage('');
        applyKyc(k); kycMissing = kycItemsMissing(k);
      }
      missing.push(...kycMissing);
      // The licence item is the STORED FILE, as fn_supplier_mandatory_six decides it. A typed number never counted
      // there, and save_profile never writes one (PROFILE_COLS): see the licence fields below (10 Nov 2026).
      // The row decides, not this form's memory of an answer: a licence stored behind a lost answer is on file (../licenceReceived.ts).
      let onFile = licOnFile;
      if (!onFile) { const row = await readRow().catch(() => null); if (licenceStoredSince('', row)) { onFile = true; licPath.current = String(row.license_doc_path); setLicOnFile(true); setLicNote(LICENCE_RECEIVED_NOTE); } }
      if (!onFile) missing.push('reg_licence');
      if (!profileFile && !me.company_profile_doc_path) missing.push('reg_profile');
      if (!terms) missing.push('reg_terms');
      if (missing.length) { tellMissing(missing); return; }
    } else if (!terms) { setMsg(t(lang, 'must_accept')); return; }
    setBusy(true); setMsg('');
    try {
      // A retry after a certificate failure does not upload the same files again (review of #695).
      if (!docsSent && (profileFile || catalogFiles.length)) {
        let prof;
        const upload = async (kind, fl, n, m) => {
          setStage(kind === 'profile' ? 'profile' : 'catalogue:' + n + ':' + m); setStageProgress(0);
          const sized = await preparePhoto(fl);
          let d = await uploadDirect(kind, sized, tok.current, setStageProgress);
          if (d.error && (await fresh(d.error))) d = await uploadDirect(kind, sized, tok.current, setStageProgress);
          setStageProgress(null);
          return d;
        };
        if (profileFile) { const d = await upload('profile', profileFile, 1, 1); if (d.error) { setBusy(false); setMsg(d.error._expired ? t(lang, 'session_ended_form') : srvMsg(lang, d.error, srvText(lang, 'direct_upload_failed'))); return; } prof = d; }
        const cats = [];
        const list = catalogFiles.slice(0, 5);
        for (let i = 0; i < list.length; i++) { const d = await upload('catalogue', list[i], i + 1, list.length); if (d.error) { setBusy(false); setMsg(d.error._expired ? t(lang, 'session_ended_form') : srvMsg(lang, d.error, srvText(lang, 'direct_upload_failed'))); return; } cats.push(d); }
        setStage('saving');
        let pj = await call('supplier_api', { action: 'process_docs', company_profile: prof, catalogs: cats }, tok.current);
        if (await fresh(pj)) pj = await call('supplier_api', { action: 'process_docs', company_profile: prof, catalogs: cats }, tok.current);
        if (!(pj && pj.ok)) { setBusy(false); setMsg(pj && pj._expired ? t(lang, 'session_ended_form') : srvMsg(lang, pj, t(lang, 'save_error'))); return; }
        setDocsSent(true);
      }
      setStage('saving');
      // The checkbox's own value (audit 15 Sep 2026: a constant "yes" was sent whatever it said).
      const payload = { action: 'save_profile', service_emirates: emirates, accept_terms: terms, marketing_consent: marketingOptIn === true };
      // Only fields save_profile keeps (supplier_api/lib/fields.ts PROFILE_COLS). The licence number, authority and expiry
      // are read from the uploaded file and never taken from the browser, so they are not sent.
      // Prevented by scripts/checks/a_registration_field_the_server_discards_is_not_offered.test.mjs.
      const strk = ['contact_name', 'signatory_name', 'phone', 'products', 'services', 'description', 'trn', 'egr_number', 'company_type', 'company_size'];
      for (const k of strk) if (String(f[k] || '').trim()) payload[k] = f[k];
      if (uaeMobile(f.phone)) payload.phone = uaeMobile(f.phone);
      if (String(f.founded_year || '').trim()) payload.founded_year = Number(f.founded_year);
      let j = await call('supplier_api', payload, tok.current);
      // A DEAD SESSION AT SUBMIT (browser walk M7): refreshed once and asked again; a 401 means nothing was saved, so it cannot twice.
      if (await fresh(j)) j = await call('supplier_api', payload, tok.current);
      // A CERTIFICATE THAT FAILED ONCE FAILED FOREVER (21 Sep 2026, campaign registration walk). Under
      // load the first certificate write timed out (compliance_archive: "cert_record_failed … statement
      // timeout", measured on production). The acceptance was recorded but no signed PDF exists, so every
      // later save_profile answers missing_required [reg_terms] — and this function returned on that
      // answer BEFORE the kyc call below, the only thing that issues the certificate. Ticked, saved,
      // refused, forever. Now the certificate is requested exactly when that is what is missing, and the
      // save is asked once more. Prevented by scripts/checks/an_invited_supplier_can_finish_registering.test.mjs.
      if (terms && j && j.saved && j.code === 'missing_required' && ((j.params && j.params.missing) || []).includes('reg_terms')) {
        const k0 = await call('kyc', { action: 'accept_terms' }, tok.current).catch(() => null);
        if (k0 && k0.ok) j = await call('supplier_api', payload, tok.current);
      }
      // The server's own list of what is missing is shown as the form's (M4), and a session that stayed dead says what is kept (M7).
      if (!(j && j.ok) && j && j.code === 'missing_required' && j.params && Array.isArray(j.params.missing)) { setBusy(false); setStage(''); tellMissing(j.params.missing); return; }
      if (!(j && j.ok) && j && j._expired) { setBusy(false); setMsg(t(lang, 'session_ended_form')); return; }
      if (!(j && j.ok)) { setBusy(false); setMsg(srvMsg(lang, j, t(lang, 'could_not_save'))); return; }
      // The signed acceptance certificate. Its failure used to be swallowed, so a supplier could finish
      // registration with no certificate on file. The save above stands; pressing again retries both.
      if (terms) {
        setStage('signing');
        const k = await call('kyc', { action: 'accept_terms' }, tok.current).catch(() => null);
        // A CALL THAT ONLY RAN OUT OF TIME IS NOT A REFUSAL (11 Nov 2026, customer_support; local certification round, J4 phone:
        // kyc accept_terms answered 200 after 25.7 s, the portal had stopped waiting at 20 s and said "we could not issue your
        // signed acceptance certificate", a dead end at Submit). save_profile above has already recorded the acceptance, its
        // trigger asks compliance_archive for the certificate, and fn_sales_engineer_resigns_unsigned_agreements signs it again
        // within minutes if it did not land; the dashboard says "Signing your Supplier Agreement…" until it does. So a timeout or a
        // lost connection goes on to the workspace; a real refusal still stops here and says so.
        const lost = !k || k.code === 'timeout' || k.code === 'network';
        if (!(k && k.ok) && !lost) { setBusy(false); setMsg(t(lang, 'terms_cert_failed')); return; }
      }
      // Registered: the draft is done with (H7).
      if (!isEdit) clearRegistrationDrafts(tabStore());
      setStage(isEdit ? '' : 'opening');
      setBusy(false);
      // Audit 21 Sep 2026, finding 32: Save closed with nothing on screen to say it worked.
      if (isEdit) { setSaved(true); setTimeout(() => setSaved(false), 6000); }
      onSaved();
    } catch (_e) { setBusy(false); setMsg(t(lang, 'save_error')); }
  };
  // Audit 21 Sep 2026, finding 48: "✓ Trade licence" put the state inside the heading's name (a screen
  // reader read "check mark trade licence"). The state is a badge after the name, in words.
  // A done item drops its "Required" (L3: "Done" stood beside "Required").
  const ok = (on) => (on ? <Badge variant="ok" className="ms-2 align-middle">{ar ? 'مكتمل' : 'Done'}</Badge> : null);
  const need = (done) => (!isEdit && !done ? <Need lang={lang} req /> : null);
  const licDone = licOnFile && !licExpired;
  const stageText = stage === 'checking' ? t(lang, 'st_checking') : stage === 'profile' ? t(lang, 'st_profile') : stage.startsWith('catalogue:') ? t(lang, 'st_catalogue').replace('{n}', stage.split(':')[1]).replace('{m}', stage.split(':')[2])
    : stage === 'saving' ? t(lang, 'st_saving') : stage === 'signing' ? t(lang, 'st_signing') : stage === 'opening' ? t(lang, 'st_opening') : '';
  const licStageText = licStage === 'preparing' ? t(lang, 'lic_preparing') : licStage === 'uploading' ? t(lang, 'lic_uploading') + (licProgress != null ? ' ' + Math.round(licProgress * 100) + '%' : '') : licStage === 'reading' ? t(lang, 'reading_lic') : '';
  const agreementHref = (ar ? '/ar' : '') + '/supplier-agreement';
  const fieldLine = 'mt-1.5 text-[13px] pointer-coarse:text-[15px] leading-snug';
  return (<Card className="qd-panel p-5">
    <h2 className={S.h2}>{t(lang, 'pf_company')}</h2>
    {/* The form registers a new supplier AND is where an existing one corrects a detail; it says which. */}
    <div className={cn(S.sub, 'mb-2')}>
      {isEdit
        ? (ar ? <>تحرير ملف <b dir="auto">{me.company_name}</b>. ما تكتبونه هنا يحدّد الطلبات التي تصلكم، ويُرجى حفظ التغييرات في الأسفل.</>
              : <>Editing the profile for <b dir="auto">{me.company_name}</b>. What you write here decides which requests reach you; save your changes at the bottom.</>)
        : <>{t(lang, 'registering_pre')}<b dir="auto">{me.company_name}</b>{me.name_corrected_from ? t(lang, 'corrected') : ''}{t(lang, 'registering_post')}</>}
    </div>
    {chooseAgain && <div role="status" className={cn(S.sub, 'mb-2 rounded-md border border-border bg-secondary/30 px-3 py-2 font-semibold text-foreground')}>{chooseAgain}</div>}
    {/* REQUIRED FIRST (M21): the form opened on the optional emirates list, and Trade licence began at y = 807 of 844. The
        emirates come after the documents in registration; the Profile tab keeps them first. */}
    {isEdit && <EmirateCheckboxes lang={lang} value={emirates} onChange={setEmirates} legend={<>{t(lang, 'pf_emirates')}</>} />}

    {/* ── REGISTRATION = THE MANDATORY SIX ───────────────────────────────────────────────────────
        Founder decision: name, mobile, e-mail (both verified), trade licence, company profile, signed
        terms; everything else optional (memory: supplier-verification-mandatory-six). The 8 Aug
        "five things" note (licence, profile, catalogue, mobile, e-mail) is superseded: the catalogue is
        optional. Contact name, products and services stay on the Profile tab, asked once inside. */}
    <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'h_trade')}{ok(licDone)}{need(licDone)}</h3>
    {!isEdit && <>
      <div className={cn(S.sub, 'mb-1.5')}>{t(lang, 'trade_sub')}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5">
        <FilePick lang={lang} accept={LICENCE_ACCEPT} busy={uploading} describedBy="qd-lic-line" testId="pick-licence" onPick={(fl) => fl && upLicense(fl)} />
        {licRetry && !uploading && <Button variant="outline" className="min-h-11" onClick={() => upLicense(licRetry)}>{t(lang, 'try_again')}</Button>}
      </div>
      <div id="qd-lic-line" className="min-h-0">
        {uploading && <div role="status" className={cn(fieldLine, 'flex items-center gap-2 text-muted-foreground')}><span aria-hidden="true" className="qd-spin" />{licStageText}</div>}
        {uploading && licStage === 'uploading' && <UploadBar progress={licProgress} label={t(lang, 'lic_uploading')} />}
        {licErr && <div role="alert" data-testid="licence-error" className={cn(fieldLine, 'font-semibold text-danger-fg')}>{licErr}{licRetry ? ' ' + t(lang, 'file_kept') : ''}</div>}
        {!uploading && licNote && (licExpired
          ? <div role="alert" data-testid="licence-expired" className={cn(S.sub, 'font-semibold text-destructive')}>{licNote}</div>
          : <div role="status" className={cn(S.sub, 'font-semibold text-primary')}>{licNote}</div>)}
      </div>
    </>}
    {/* AS READ FROM THE FILE, NOT TYPED (10 Nov 2026, customer_support, supplier-journey audit). These were inputs, and
        save_profile has never kept them: the licence number, authority and expiry are written only from the stored file
        (PROFILE_COLS, 15 Sep 2026), and the gate asks for a clearer copy when they do not read. A typed number was dropped
        without a word, while this form counted it as the licence. They show what was read; a new upload changes them.
        PLAIN TEXT, NOT A BOX (12 Nov 2026, browser walk M8): two read-only inputs looked like boxes that could not be typed in,
        and the authority was cut off. Shown once something was read; nothing is shown before. */}
    {(f.trade_license_no || f.license_authority) && <dl className="mt-3 grid grid-cols-1 gap-x-4 gap-y-1 rounded-md border border-border bg-secondary/20 px-3 py-2.5 sm:grid-cols-[auto_1fr]" data-testid="licence-read">
      <ReadField text={t(lang, 'lic_no')} value={f.trade_license_no} ltr />
      <ReadField text={t(lang, 'authority')} value={f.license_authority} />
      {f.license_expiry ? <ReadField text={t(lang, 'lic_expiry')} value={licenceDate(f.license_expiry)} /> : null}
    </dl>}

    <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'pf_contact')}{ok(phoneVerified && emailVerified)}{need(phoneVerified && emailVerified)}</h3>
    {/* E-mail is shown with its state, never asked for again: the supplier signed in with it. */}
    <div className={cn(S.sub, 'mb-1.5')}>
      <span dir="ltr">{me.claimed_by || ''}</span>
      {emailVerified
        ? <b className="text-primary"> · {t(lang, 'email_verified')}</b>
        : <b className="text-warn-fg"> · {t(lang, 'email_unverified')}</b>}
    </div>
    {!emailVerified && (!mailSent
      ? <Button variant="link" className="px-0 h-auto min-h-11" busy={vbusy === 'mail'} disabled={!!vbusy} onClick={sendMail}>{t(lang, 'verify_my_email')}</Button>
      : <div className={S.frow}><Lbl visible lang={lang} text={t(lang, 'email_code')}><Input inputMode="numeric" autoComplete="one-time-code" dir="ltr" placeholder={t(lang, 'code_placeholder')} value={mailCode} onChange={(e) => { setMailCode(e.target.value); setMailErr(''); }} /></Lbl><Button size="sm" className="self-end" busy={vbusy === 'verify_mail'} disabled={!!vbusy} onClick={verifyMail}>{t(lang, 'verify')}</Button></div>)}
    {!emailVerified && mailNote && <div role="status" className={cn(fieldLine, 'text-muted-foreground')}>{mailNote}</div>}
    {!emailVerified && mailErr && <div role="alert" className={cn(fieldLine, 'font-semibold text-danger-fg')}>{mailErr}</div>}
    <div className={S.frow}><Lbl className="flex-1" need={isEdit || phoneVerified ? null : 'req'} visible lang={lang} text={t(lang, 'mobile')}><Input type="tel" autoComplete="tel" dir="ltr" inputMode="tel" aria-describedby="qd-mobile-fmt" aria-invalid={!!f.phone && !uaeMobile(f.phone)} aria-required={!isEdit} readOnly={smsSent && !phoneVerified} placeholder="05X XXX XXXX" value={f.phone} onChange={(e) => { set('phone', e.target.value); setMobileErr(''); }} /></Lbl></div>
    {/* The format hint is for typing; once the number is verified it is not needed (L9). */}
    {!phoneVerified && <div id="qd-mobile-fmt" className={cn(S.sub, 'mt-1 text-[12px] pointer-coarse:text-[14px]', f.phone && !uaeMobile(f.phone) && 'text-danger-fg')}>{t(lang, 'mobile_format')}</div>}
    {phoneVerified ? <div className={cn(S.sub, 'font-semibold text-primary')}>{t(lang, 'mobile_verified')}</div> : (!smsSent ? <div className="mt-1.5 flex flex-wrap items-center gap-3"><Button variant="link" className="px-0 h-auto min-h-11" busy={vbusy === 'wa'} disabled={!!vbusy} onClick={() => sendSms('whatsapp')}>{vbusy === 'wa' ? t(lang, 'sending') : t(lang, 'verify_my_mobile')}</Button><Button variant="link" className="px-0 h-auto min-h-11" busy={vbusy === 'sms'} disabled={!!vbusy} onClick={() => sendSms('sms')}>{vbusy === 'sms' ? t(lang, 'sending') : t(lang, 'verify_by_sms')}</Button></div> : <><div className={S.hint}>{t(lang, smsSent === 'whatsapp' ? 'wa_note' : smsSent === 'sms_failover' ? 'wa_failed_note' : 'junk_note')}</div>{smsSent === 'whatsapp' && <Button variant="link" className="px-0 h-auto min-h-11" busy={vbusy === 'sms'} disabled={!!vbusy} onClick={() => sendSms('sms')}>{t(lang, 'send_by_sms')}</Button>}<div className={S.frow}><Lbl visible lang={lang} text={t(lang, 'sms_code')}><Input inputMode="numeric" autoComplete="one-time-code" dir="ltr" placeholder={t(lang, 'code_placeholder')} value={smsCode} onChange={(e) => { setSmsCode(e.target.value); setMobileErr(''); }} onKeyDown={(e) => e.key === 'Enter' && verifySms()} /></Lbl><Button size="sm" className="self-end" busy={vbusy === 'verify_sms'} disabled={!!vbusy} onClick={verifySms}>{t(lang, 'verify')}</Button></div>
      {/* The number is read-only while a code is out, so verify_sms checks the number that was texted
          (review of #695); this reopens it. */}
      <Button variant="link" className="px-0 h-auto min-h-11" onClick={() => { setSmsSent(false); setSmsCode(''); setMobileErr(''); }}>{t(lang, 'change_mobile')}</Button></>)}
    {/* The mobile step's own answer, under the mobile (H1: it was 459-673 px away, under Submit). */}
    {mobileErr && <div role="alert" data-testid="mobile-error" className={cn(fieldLine, 'font-semibold text-danger-fg')}>{mobileErr}</div>}
    {/* NOT `!isEdit` (21 Sep 2026, campaign registration walk). An INVITED supplier claims a listing
        that already exists, so Onboarding never runs and they finish registering on the Profile tab —
        edit mode. save() below demands this answer from every supplier not yet approved, and the
        question was rendered only outside edit mode: "Still needed to register: Your answer on your
        WhatsApp number" with nothing on screen to answer it, a dead end for every invited supplier.
        The question now shows exactly when save() would ask for it.
        Prevented by scripts/checks/an_invited_supplier_can_finish_registering.test.mjs. */}
    {me.approval_status !== 'approved' && phoneVerified && !waSignupSettled(wa) && <div className="mt-3">
      {/* Enforced by save() like the six, so it carries the same Required marker (review of #695). */}
      {/* S.h2 like the other required headers, but not a heading: WhatsAppChoice's own h2 follows. */}
      <div className={cn(S.h2, 'mb-1')}>{srvText(lang, 'reg_whatsapp')}<Need lang={lang} req /></div>
      <WhatsAppChoice token={token} lang={lang} mode="signup" current={wa} mobile={f.phone} onDone={() => loadKyc()} /></div>}

    {/* The contact person is asked at sign-up too (Optional), not only once inside. */}
    <div className={S.frow}><Lbl className="flex-1" need={isEdit ? null : 'opt'} visible lang={lang} text={t(lang, 'contact_name')}><Input autoComplete="name" dir="auto" placeholder={t(lang, 'contact_name')} value={f.contact_name} onChange={(e) => set('contact_name', e.target.value)} /></Lbl>{isEdit && <Lbl className="flex-1" visible lang={lang} text={t(lang, 'signatory')}><Input placeholder={t(lang, 'signatory')} value={f.signatory_name} onChange={(e) => set('signatory_name', e.target.value)} /></Lbl>}</div>
    {isEdit && <>
      <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'h_offer')}</h3>
      {/* Visible labels (M17): the placeholder vanished as he typed, and with it the only name the box had. */}
      <Lbl className="mt-3" visible lang={lang} text={t(lang, 'products_ph')}><Input placeholder={t(lang, 'products_ph')} value={f.products} onChange={(e) => set('products', e.target.value)} /></Lbl>
      <Lbl className="mt-3" visible lang={lang} text={t(lang, 'services_ph')}><Input placeholder={t(lang, 'services_ph')} value={f.services} onChange={(e) => set('services', e.target.value)} /></Lbl>
      <Lbl className="mt-3" visible lang={lang} text={t(lang, 'desc_ph')}><textarea className={cn(S.area, 'mt-0')} rows={3} placeholder={t(lang, 'desc_ph')} value={f.description} onChange={(e) => set('description', e.target.value)} /></Lbl>
    </>}
    {!isEdit && <>
      <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'doc_profile')}{ok(!!profileFile || !!me.company_profile_doc_path)}{need(!!profileFile || !!me.company_profile_doc_path)}</h3>
      <div className={cn(S.sub, 'mb-1')}>{ar ? 'الملف التعريفي مطلوب؛ الكتالوجات اختيارية ويمكن إضافتها لاحقًا من تبويب المستندات.' : 'The company profile is required; catalogues are optional and can be added later from Documents.'}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><span className={S.sub}>{t(lang, 'company_profile_pdf')}</span><FilePick lang={lang} accept={PAPER_ACCEPT} busy={busy && stage === 'profile'} testId="pick-profile" onPick={pickProfile} />{profileFile && <span className={cn(S.sub, 'font-semibold text-foreground [overflow-wrap:anywhere]')}>{profileFile.name}</span>}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><span className={S.sub}>{t(lang, 'catalogs_ph')}<Need lang={lang} /></span><FilePick lang={lang} accept={PAPER_ACCEPT} multiple busy={busy && stage.startsWith('catalogue')} testId="pick-catalogues" onPick={pickCatalogues} />{catalogFiles.length ? <span className={S.sub}>{catalogFiles.length} {t(lang, 'selected')}</span> : null}</div>
      {profErr && <div role="alert" data-testid="profile-error" className={cn(fieldLine, 'font-semibold text-danger-fg')}>{profErr}</div>}
      {/* Catalogues were cut to 5 silently (audit 15 Sep 2026). The limit is stated, and a cut is announced. */}
      <div role={catCut ? 'status' : undefined} className={cn(S.sub, 'mt-1 text-[12px] pointer-coarse:text-[14px]', catCut && 'font-semibold text-warn-fg')}>{t(lang, catCut ? 'catalogs_cut' : 'catalogs_limit')}</div>
      <div className="mt-4"><EmirateCheckboxes lang={lang} value={emirates} onChange={setEmirates} legend={<>{t(lang, 'pf_emirates')}<Need lang={lang} /></>} /></div>
    </>}
    {isEdit && <div className={cn(S.sub, 'mt-3 rounded-md border border-border bg-secondary/30 px-3 py-2.5')}>{ar ? 'تُدار الرخصة التجارية والملف التعريفي والكتالوجات من تبويب المستندات، حتى لا يُطلب الملف نفسه في مكانين.' : 'Your trade licence, company profile and catalogues are managed in the Documents tab — so the same file is never asked for in two places.'}</div>}

    {/* ONE SENTENCE, A BOX A FINGER CAN HIT (H4): the label was a flex row of four items, so at 390 px it broke into four columns
        beside a 13x13 box. The box is 20x20, the words are one sentence with the link inside it, and the row is 44 px tall. The
        link opens the agreement over the form (M22) and leaves the box as it was. */}
    <label className="mt-3.5 flex min-h-11 cursor-pointer items-start gap-3 py-1 text-[13.5px] pointer-coarse:text-[15px] leading-snug text-muted-foreground" data-testid="accept-terms">
      <input type="checkbox" className="mt-0.5 h-5 w-5 shrink-0 rounded border-input accent-[hsl(var(--primary))] focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring" aria-required={!isEdit} checked={terms} onChange={(e) => setTerms(e.target.checked)} />
      <span>{t(lang, 'accept_pre')}<a href={agreementHref} target="_blank" rel="noopener" className="font-semibold text-primary underline underline-offset-2" onClick={(e) => { if (e.metaKey || e.ctrlKey || e.shiftKey) return; e.preventDefault(); e.stopPropagation(); setAgreementOpen(true); }}>{t(lang, 'terms_link')}</a>{t(lang, 'accept_post')}{!isEdit && !terms && <Need lang={lang} req />}</span>
    </label>
    {!isEdit && <label className="mt-2.5 flex min-h-11 cursor-pointer items-start gap-3 py-1 text-[13px] pointer-coarse:text-[14px] leading-snug text-muted-foreground"><input type="checkbox" className="mt-0.5 h-5 w-5 shrink-0 rounded border-input accent-[hsl(var(--primary))]" checked={marketingOptIn} onChange={(e) => setMarketingOptIn(e.target.checked)} /><span>{t('en', 'marketing_opt_in')}</span></label>}
    <AgreementSheet open={agreementOpen} onClose={() => setAgreementOpen(false)} href={agreementHref} />
    <Button className="w-full mt-3" busy={busy} disabled={busy || uploading || !kycRead} onClick={save}>
      {busy ? (isEdit ? (ar ? 'جارٍ الحفظ…' : 'Saving…') : t(lang, 'submitting'))
            : isEdit ? (ar ? 'حفظ التغييرات' : 'Save changes') : t(lang, 'submit_approval')}
    </Button>
    {/* What Submit is doing, step by step (H2: 8-10 s of "Submitting…"), and the upload's progress. */}
    {stageText && <div role="status" data-testid="submit-stage" className={cn(fieldLine, 'flex items-center gap-2 text-muted-foreground')}>{stageText}{stageProgress != null ? ' ' + Math.round(stageProgress * 100) + '%' : ''}</div>}
    {stageProgress != null && <UploadBar progress={stageProgress} label={stageText} />}
    {bottomMsg && <div ref={submitMsg} tabIndex={-1} role="alert" data-testid="submit-error" className={cn(S.err, 'font-semibold outline-hidden')}>{bottomMsg}</div>}
    {saved && !bottomMsg && <div role="status" className={cn(S.sub, 'mt-2 font-semibold text-primary')}>{ar ? 'تم حفظ التغييرات.' : 'Changes saved.'}</div>}
  </Card>);
}
// What was read off the licence, as text (M8). `text={…}` names the field; there is no box to type in.
function ReadField({ text, value, ltr = false }) {
  return <><dt className="text-[12px] pointer-coarse:text-[14px] font-semibold text-muted-foreground">{text}</dt><dd className="text-[14px] pointer-coarse:text-[15px] font-semibold text-foreground [overflow-wrap:anywhere]" dir={ltr ? 'ltr' : 'auto'}>{value || '—'}</dd></>;
}
export { ProfileForm };
