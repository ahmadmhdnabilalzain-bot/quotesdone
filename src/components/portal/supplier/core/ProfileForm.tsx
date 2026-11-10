// @ts-nocheck
'use client';
import { useEffect, useState } from 'react';
import { useFailover } from '@/lib/otpFailover';
import EmirateCheckboxes from '../EmirateCheckboxes';
import { srvMsg, srvText } from '../serverCopy';
import { call, REASONING_TIMEOUT_MS, tooBigToRead, sizeMb } from '../api';
import { uaeMobile } from '../uaeMobile';
import { WhatsAppChoice } from '../../WhatsAppChoice';
import { waSignupSettled } from '../../whatsappChoiceText';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { Need, Lbl, FilePick } from './helpers';
import { uploadDirect, fileToImages } from './upload';
import { t } from './copy';
import { S } from './styles';

// `mode` distinguishes first-time REGISTRATION (Onboarding) from an established supplier
// EDITING their profile (the Profile tab). Document uploads (trade licence, company profile,
// catalogues) are shown only during registration. In edit mode they are hidden and the supplier
// is pointed to the Documents tab, which is the single home for every document file — the same
// file is never asked for in two places.
function ProfileForm({ token, me, onSaved, lang, mode = 'register' }) {
  const isEdit = mode === 'edit';
  const ar = lang === 'ar';
  const [f, setF] = useState({
    contact_name: me.contact_name || '', signatory_name: me.signatory_name || '', owner_dob: me.owner_dob || '', phone: me.phone || '',
    products: me.products || '', services: me.services || '', description: me.description || '',
    trade_license_no: me.trade_license_no || '', license_authority: me.license_authority || '', license_expiry: me.license_expiry || '',
    trn: me.trn || '', egr_number: me.egr_number || '', founded_year: me.founded_year || '', company_type: me.company_type || '', company_size: me.company_size || '',
  });
  const [emirates, setEmirates] = useState(me.service_emirates || []); const [terms, setTerms] = useState(!!me.accepted_terms_at);
  // Promotional messages are opt-in (19 Oct 2026, founder, legal finding 2): a SEPARATE box, never pre-ticked,
  // never required. Guarded by scripts/checks/promotional_messages_are_opt_in.test.mjs.
  const [marketingOptIn, setMarketingOptIn] = useState(false);
  const [profileFile, setProfileFile] = useState(null); const [catalogFiles, setCatalogFiles] = useState([]); const [catCut, setCatCut] = useState(false); const [docsSent, setDocsSent] = useState(false);
  const [phoneVerified, setPhoneVerified] = useState(false); const [smsSent, setSmsSent] = useState<string | false>(false); const [smsCode, setSmsCode] = useState(''); const [vbusy, setVbusy] = useState(false);
  const [emailVerified, setEmailVerified] = useState(!!me.owner_email_verified); const [mailSent, setMailSent] = useState(false); const [mailCode, setMailCode] = useState('');
  // wa: kyc's `whatsapp` answer. Registration waits for it (founder, 15 Sep 2026: "It's in the sign
  // up"): save() lists it as missing and supplier_api save_profile refuses without it (reg_whatsapp).
  const [wa, setWa] = useState(undefined);
  const [saved, setSaved] = useState(false);
  // SAVE WAITS FOR THE KYC STATE (run 71b75b60, en/mobile): Save pressed before this read resolved checked a
  // phoneVerified that was still its initial false, refused "missing mobile" on screen in 36 ms and sent nothing.
  const [kycRead, setKycRead] = useState(false);
  const loadKyc = () => call('kyc', { action: 'state' }, token).then((k) => { if (k && k.phone_verified) setPhoneVerified(true); if (k && k.email_verified) setEmailVerified(true); setWa(k ? k.whatsapp : undefined); }).finally(() => setKycRead(true));
  useEffect(() => { loadKyc(); }, []);
  // WhatsApp first (kyc nextChannel, 18 Oct 2026); smsSent holds the channel that carried the code, 'sms' is the explicit failover.
  const failover = useFailover();
  const sendSms = async (channel?: 'sms' | 'whatsapp') => { const e164 = uaeMobile(f.phone); if (!e164) { setMsg(t(lang, 'mobile_format')); return; } if (e164 !== f.phone) set('phone', e164); setVbusy(true); setMsg(''); const j = await call('kyc', { action: 'send_sms', phone: e164, ...(channel ? { channel } : {}) }, token); setVbusy(false); if (j && j.ok) { setSmsSent(j.channel || 'sms'); if (j.channel === 'whatsapp') failover(() => call('kyc', { action: 'phone_failover', phone: e164 }, token), () => setSmsSent('sms_failover')); } else setMsg(srvMsg(lang, j, t(lang, 'could_not_sms'))); };
  const verifySms = async () => { setVbusy(true); setMsg(''); const j = await call('kyc', { action: 'verify_sms', phone: f.phone, code: smsCode }, token); setVbusy(false); if (j && j.ok) setPhoneVerified(true); else setMsg(srvMsg(lang, j, t(lang, 'wrong_code'))); };
  // E-MAIL, THE ONE ITEM OF THE SIX WITH NO BUTTON (14 Sep 2026). The form showed "e-mail not yet
  // verified" with nothing to press, and save_profile now requires it. kyc send_email / verify_email
  // already existed; this is their caller. (supplier_api also records it from the sign-up OTP, so most
  // suppliers will never see this.)
  const sendMail = async () => { setVbusy(true); setMsg(''); const j = await call('kyc', { action: 'send_email' }, token); setVbusy(false); if (j && j.ok) { setMailSent(true); setMsg(t(lang, 'email_sent')); } else setMsg(srvMsg(lang, j, t(lang, 'could_not_email'))); };
  const verifyMail = async () => { setVbusy(true); setMsg(''); const j = await call('kyc', { action: 'verify_email', code: mailCode }, token); setVbusy(false); if (j && j.ok) { setEmailVerified(true); setMsg(''); } else setMsg(srvMsg(lang, j, t(lang, 'wrong_code'))); };
  const [uploading, setUploading] = useState(false); const [licNote, setLicNote] = useState(me.license_doc_path ? t(lang, 'lic_on_file') : '');
  const [licOnFile, setLicOnFile] = useState(!!me.license_doc_path);
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const set = (k, v) => setF((o) => ({ ...o, [k]: v }));
  // THE LICENCE DEAD-END (audit 2026-09-14, BLOCKS CONVERSION). After any upload licNote became
  // non-empty ("Licence uploaded." when extraction returned nothing), which HID the typed licence-number
  // field, while save() still refused without a number. Under the OpenRouter hold license_extract never
  // returns, so every new supplier could neither type the number nor submit. Now: the upload itself
  // counts as the licence (the server's gate is path OR number, and the mandatory six say the same),
  // the number field is always shown, and extraction only fills it in when it happens to answer.
  // A failed STORE is reported as a failure instead of being announced as "uploaded".
  const upLicense = async (file) => {
    if (!file) return; setLicNote(''); setMsg('');
    if (tooBigToRead(file)) { setMsg(srvText(lang, 'file_too_large_read', { mb: sizeMb(file) })); return; }
    setUploading(true);
    try {
      const { images, b64, mime } = await fileToImages(file);
      // The licence is read before the answer (the model, up to two attempts): the reasoning wait, not 20 s (see save_documents).
      const j = await call('supplier_api', { action: 'process_docs', license: { original_b64: b64, file_b64: b64, images, filename: file.name, mime } }, token, { timeoutMs: REASONING_TIMEOUT_MS });
      if (!(j && j.ok)) { setMsg(srvMsg(lang, j, t(lang, 'lic_upload_failed'))); }
      else {
        setLicOnFile(true);
        const ex = (j.extracted && j.extracted.license) || null;
        if (ex) { setF((o) => ({ ...o, trade_license_no: ex.license_number || o.trade_license_no, license_authority: ex.authority || o.license_authority, license_expiry: ex.expiry || o.license_expiry, trn: ex.trn || o.trn })); setLicNote(t(lang, 'read_lic') + (ex.license_number ? ' — ' + ex.license_number : '') + (ex.expiry ? t(lang, 'expires_comma') + ex.expiry : '') + '.'); }
        else setLicNote(t(lang, 'lic_uploaded_type'));
        // The document was saved but its licence number belongs to another claimed company, so the number
        // was set aside for a human (supabase/functions/_shared/duplicate_company.ts). Existing copy.
        if (j.extracted && j.extracted.licence_set_aside) setMsg(srvText(lang, 'company_already_registered'));
      }
    } catch (_e) { setMsg(t(lang, 'lic_upload_failed')); }
    setUploading(false);
  };
  const save = async () => {
    // The mandatory six, checked here in the same order and with the same codes save_profile enforces
    // (supabase/functions/_shared/supplier_registration.ts), so the refusal a supplier sees on screen
    // and the one the server would give cannot disagree. An approved company editing its profile is
    // not re-gated — the server does not re-gate it either.
    if (me.approval_status !== 'approved') {
      const missing = [];
      if (!phoneVerified) missing.push('reg_mobile');
      if (!emailVerified) missing.push('reg_email');
      if (!waSignupSettled(wa)) missing.push('reg_whatsapp');
      // The licence item is the STORED FILE, as fn_supplier_mandatory_six decides it. A typed number never counted
      // there, and save_profile never writes one (PROFILE_COLS): see the licence fields below (10 Nov 2026).
      if (!licOnFile) missing.push('reg_licence');
      if (!profileFile && !me.company_profile_doc_path) missing.push('reg_profile');
      if (!terms) missing.push('reg_terms');
      if (missing.length) { setMsg(srvText(lang, 'missing_required', { missing })); return; }
    } else if (!terms) { setMsg(t(lang, 'must_accept')); return; }
    setBusy(true); setMsg('');
    try {
      // A retry after a certificate failure does not upload the same files again (review of #695).
      if (!docsSent && (profileFile || catalogFiles.length)) {
        let prof;
        if (profileFile) { const d = await uploadDirect('profile', profileFile, token); if (d.error) { setBusy(false); setMsg(srvMsg(lang, d.error, srvText(lang, 'direct_upload_failed'))); return; } prof = d; }
        const cats = [];
        for (const cf of catalogFiles.slice(0, 5)) { const d = await uploadDirect('catalogue', cf, token); if (d.error) { setBusy(false); setMsg(srvMsg(lang, d.error, srvText(lang, 'direct_upload_failed'))); return; } cats.push(d); }
        const pj = await call('supplier_api', { action: 'process_docs', company_profile: prof, catalogs: cats }, token);
        if (!(pj && pj.ok)) { setBusy(false); setMsg(srvMsg(lang, pj, t(lang, 'save_error'))); return; }
        setDocsSent(true);
      }
      // The checkbox's own value (audit 15 Sep 2026: a constant "yes" was sent whatever it said).
      const payload = { action: 'save_profile', service_emirates: emirates, accept_terms: terms, marketing_consent: marketingOptIn === true };
      // Only fields save_profile keeps (supplier_api/lib/fields.ts PROFILE_COLS). The licence number, authority and expiry
      // are read from the uploaded file and never taken from the browser, so they are not sent.
      // Prevented by scripts/checks/a_registration_field_the_server_discards_is_not_offered.test.mjs.
      const strk = ['contact_name', 'signatory_name', 'phone', 'products', 'services', 'description', 'trn', 'egr_number', 'company_type', 'company_size'];
      for (const k of strk) if (String(f[k] || '').trim()) payload[k] = f[k];
      if (uaeMobile(f.phone)) payload.phone = uaeMobile(f.phone);
      if (String(f.founded_year || '').trim()) payload.founded_year = Number(f.founded_year);
      let j = await call('supplier_api', payload, token);
      // A CERTIFICATE THAT FAILED ONCE FAILED FOREVER (21 Sep 2026, campaign registration walk). Under
      // load the first certificate write timed out (compliance_archive: "cert_record_failed … statement
      // timeout", measured on production). The acceptance was recorded but no signed PDF exists, so every
      // later save_profile answers missing_required [reg_terms] — and this function returned on that
      // answer BEFORE the kyc call below, the only thing that issues the certificate. Ticked, saved,
      // refused, forever. Now the certificate is requested exactly when that is what is missing, and the
      // save is asked once more. Prevented by scripts/checks/an_invited_supplier_can_finish_registering.test.mjs.
      if (terms && j && j.saved && j.code === 'missing_required' && ((j.params && j.params.missing) || []).includes('reg_terms')) {
        const k0 = await call('kyc', { action: 'accept_terms' }, token).catch(() => null);
        if (k0 && k0.ok) j = await call('supplier_api', payload, token);
      }
      if (!(j && j.ok)) { setBusy(false); setMsg(srvMsg(lang, j, t(lang, 'could_not_save'))); return; }
      // The signed acceptance certificate. Its failure used to be swallowed, so a supplier could finish
      // registration with no certificate on file. The save above stands; pressing again retries both.
      if (terms) {
        const k = await call('kyc', { action: 'accept_terms' }, token).catch(() => null);
        if (!(k && k.ok)) { setBusy(false); setMsg(t(lang, 'terms_cert_failed')); return; }
      }
      setBusy(false);
      // Audit 21 Sep 2026, finding 32: Save closed with nothing on screen to say it worked.
      if (isEdit) { setSaved(true); setTimeout(() => setSaved(false), 6000); }
      onSaved();
    } catch (_e) { setBusy(false); setMsg(t(lang, 'save_error')); }
  };
  // Audit 21 Sep 2026, finding 48: "✓ Trade licence" put the state inside the heading's name (a screen
  // reader read "check mark trade licence"). The state is a badge after the name, in words.
  const ok = (on) => (on ? <Badge variant="ok" className="ms-2 align-middle">{ar ? 'مكتمل' : 'Done'}</Badge> : null);
  return (<Card className="qd-panel p-5">
    <h2 className={S.h2}>{t(lang, 'pf_company')}</h2>
    {/* The form registers a new supplier AND is where an existing one corrects a detail; it says which. */}
    <div className={cn(S.sub, 'mb-2')}>
      {isEdit
        ? (ar ? <>تحرير ملف <b dir="auto">{me.company_name}</b>. ما تكتبونه هنا يحدّد الطلبات التي تصلكم، ويُرجى حفظ التغييرات في الأسفل.</>
              : <>Editing the profile for <b dir="auto">{me.company_name}</b>. What you write here decides which requests reach you; save your changes at the bottom.</>)
        : <>{t(lang, 'registering_pre')}<b dir="auto">{me.company_name}</b>{me.name_corrected_from ? t(lang, 'corrected') : ''}{t(lang, 'registering_post')}</>}
    </div>
    <EmirateCheckboxes lang={lang} value={emirates} onChange={setEmirates} legend={<>{t(lang, 'pf_emirates')}{!isEdit && <Need lang={lang} />}</>} />

    {/* ── REGISTRATION = THE MANDATORY SIX ───────────────────────────────────────────────────────
        Founder decision: name, mobile, e-mail (both verified), trade licence, company profile, signed
        terms; everything else optional (memory: supplier-verification-mandatory-six). The 8 Aug
        "five things" note (licence, profile, catalogue, mobile, e-mail) is superseded: the catalogue is
        optional. Contact name, products and services stay on the Profile tab, asked once inside. */}
    <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'h_trade')}{ok(licOnFile)}{!isEdit && <Need lang={lang} req />}</h3>
    {!isEdit && <>
      <div className={cn(S.sub, 'mb-1.5')}>{t(lang, 'trade_sub')}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><FilePick lang={lang} accept="image/*,application/pdf" onPick={(fl) => fl && upLicense(fl)} />{uploading && <span className={S.sub} role="status">{t(lang, 'reading_lic')}</span>}</div>
      {licNote && <div role="status" className={cn(S.sub, 'font-semibold text-primary')}>{licNote}</div>}
    </>}
    {/* AS READ FROM THE FILE, NOT TYPED (10 Nov 2026, customer_support, supplier-journey audit). These were inputs, and
        save_profile has never kept them: the licence number, authority and expiry are written only from the stored file
        (PROFILE_COLS, 15 Sep 2026), and the gate asks for a clearer copy when they do not read. A typed number was dropped
        without a word, while this form counted it as the licence. They show what was read; a new upload changes them. */}
    <div className={S.frow}>
      <Lbl className="flex-1 min-w-[180px]" visible lang={lang} text={t(lang, 'lic_no')}><Input dir="ltr" readOnly aria-readonly="true" tabIndex={-1} className="bg-muted/40" placeholder={t(lang, 'lic_no')} value={f.trade_license_no} /></Lbl>
      <Lbl className="flex-1 min-w-[180px]" visible lang={lang} text={t(lang, 'authority')}><Input readOnly aria-readonly="true" tabIndex={-1} className="bg-muted/40" placeholder={t(lang, 'authority')} value={f.license_authority} /></Lbl>
    </div>

    <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'pf_contact')}{ok(phoneVerified && emailVerified)}{!isEdit && <Need lang={lang} req />}</h3>
    {/* E-mail is shown with its state, never asked for again: the supplier signed in with it. */}
    <div className={cn(S.sub, 'mb-1.5')}>
      <span dir="ltr">{me.claimed_by || ''}</span>
      {emailVerified
        ? <b className="text-primary"> · {t(lang, 'email_verified')}</b>
        : <b className="text-warn-fg"> · {t(lang, 'email_unverified')}</b>}
    </div>
    {!emailVerified && (!mailSent
      ? <Button variant="link" className="px-0 h-auto" disabled={vbusy} onClick={sendMail}>{t(lang, 'verify_my_email')}</Button>
      : <div className={S.frow}><Lbl text={t(lang, 'email_code')}><Input inputMode="numeric" autoComplete="one-time-code" dir="ltr" placeholder={t(lang, 'email_code')} value={mailCode} onChange={(e) => setMailCode(e.target.value)} /></Lbl><Button size="sm" disabled={vbusy} onClick={verifyMail}>{t(lang, 'verify')}</Button></div>)}
    <div className={S.frow}><Lbl className="flex-1" need={isEdit ? null : 'req'} lang={lang} text={t(lang, 'mobile')}><Input type="tel" autoComplete="tel" dir="ltr" inputMode="tel" aria-describedby="qd-mobile-fmt" aria-invalid={!!f.phone && !uaeMobile(f.phone)} aria-required={!isEdit} readOnly={smsSent && !phoneVerified} placeholder="05X XXX XXXX" value={f.phone} onChange={(e) => set('phone', e.target.value)} /></Lbl></div>
    <div id="qd-mobile-fmt" className={cn(S.sub, 'mt-1 text-[12px]', f.phone && !uaeMobile(f.phone) && !phoneVerified && 'text-danger-fg')}>{t(lang, 'mobile_format')}</div>
    {phoneVerified ? <div className={cn(S.sub, 'font-semibold text-primary')}>{t(lang, 'mobile_verified')}</div> : (!smsSent ? <div className="mt-1.5 flex flex-wrap items-center gap-3"><Button variant="link" className="px-0 h-auto" disabled={vbusy} onClick={() => sendSms('whatsapp')}>{vbusy ? t(lang, 'sending') : t(lang, 'verify_my_mobile')}</Button><Button variant="link" className="px-0 h-auto" disabled={vbusy} onClick={() => sendSms('sms')}>{t(lang, 'verify_by_sms')}</Button></div> : <><div className={S.hint}>{t(lang, smsSent === 'whatsapp' ? 'wa_note' : smsSent === 'sms_failover' ? 'wa_failed_note' : 'junk_note')}</div>{smsSent === 'whatsapp' && <Button variant="link" className="px-0 h-auto" disabled={vbusy} onClick={() => sendSms('sms')}>{t(lang, 'send_by_sms')}</Button>}<div className={S.frow}><Lbl text={t(lang, 'sms_code')}><Input inputMode="numeric" autoComplete="one-time-code" dir="ltr" placeholder={t(lang, 'sms_code')} value={smsCode} onChange={(e) => setSmsCode(e.target.value)} /></Lbl><Button size="sm" disabled={vbusy} onClick={verifySms}>{t(lang, 'verify')}</Button></div>
      {/* The number is read-only while a code is out, so verify_sms checks the number that was texted
          (review of #695); this reopens it. */}
      <Button variant="link" className="px-0 h-auto" onClick={() => { setSmsSent(false); setSmsCode(''); setMsg(''); }}>{t(lang, 'change_mobile')}</Button></>)}
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
    <div className={S.frow}><Lbl className="flex-1" need={isEdit ? null : 'opt'} lang={lang} text={t(lang, 'contact_name')}><Input autoComplete="name" dir="auto" placeholder={t(lang, 'contact_name')} value={f.contact_name} onChange={(e) => set('contact_name', e.target.value)} /></Lbl>{isEdit && <Lbl className="flex-1" text={t(lang, 'signatory')}><Input placeholder={t(lang, 'signatory')} value={f.signatory_name} onChange={(e) => set('signatory_name', e.target.value)} /></Lbl>}</div>
    {isEdit && <>
      <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'h_offer')}</h3>
      <Lbl text={t(lang, 'products_ph')}><Input className="mt-3" placeholder={t(lang, 'products_ph')} value={f.products} onChange={(e) => set('products', e.target.value)} /></Lbl>
      <Lbl text={t(lang, 'services_ph')}><Input className="mt-3" placeholder={t(lang, 'services_ph')} value={f.services} onChange={(e) => set('services', e.target.value)} /></Lbl>
      <Lbl text={t(lang, 'desc_ph')}><textarea className={S.area} rows={3} placeholder={t(lang, 'desc_ph')} value={f.description} onChange={(e) => set('description', e.target.value)} /></Lbl>
    </>}
    {!isEdit && <>
      <h3 className={cn(S.h2, 'mt-4')}>{t(lang, 'doc_profile')}{ok(!!profileFile || !!me.company_profile_doc_path)}<Need lang={lang} req /></h3>
      <div className={cn(S.sub, 'mb-1')}>{ar ? 'الملف التعريفي مطلوب؛ الكتالوجات اختيارية ويمكن إضافتها لاحقًا من تبويب المستندات.' : 'The company profile is required; catalogues are optional and can be added later from Documents.'}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><span className={S.sub}>{t(lang, 'company_profile_pdf')}</span><FilePick lang={lang} accept=".pdf,.docx,.pptx,.jpg,.jpeg,.png" onPick={(fl) => { setProfileFile(fl); setDocsSent(false); }} />{profileFile && <span className={S.sub}>{profileFile.name}</span>}</div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5"><span className={S.sub}>{t(lang, 'catalogs_ph')}<Need lang={lang} /></span><FilePick lang={lang} accept=".pdf,.docx,.pptx,.jpg,.jpeg,.png" multiple onPick={(a) => { const all = a || []; setCatalogFiles(all.slice(0, 5)); setCatCut(all.length > 5); setDocsSent(false); }} />{catalogFiles.length ? <span className={S.sub}>{catalogFiles.length} {t(lang, 'selected')}</span> : null}</div>
      {/* Catalogues were cut to 5 silently (audit 15 Sep 2026). The limit is stated, and a cut is announced. */}
      <div role={catCut ? 'status' : undefined} className={cn(S.sub, 'mt-1 text-[12px]', catCut && 'font-semibold text-warn-fg')}>{t(lang, catCut ? 'catalogs_cut' : 'catalogs_limit')}</div>
    </>}
    {isEdit && <div className={cn(S.sub, 'mt-3 rounded-md border border-border bg-secondary/30 px-3 py-2.5')}>{ar ? 'تُدار الرخصة التجارية والملف التعريفي والكتالوجات من تبويب المستندات، حتى لا يُطلب الملف نفسه في مكانين.' : 'Your trade licence, company profile and catalogues are managed in the Documents tab — so the same file is never asked for in two places.'}</div>}

    <label className="flex gap-2 items-center mt-3.5 text-[13px] text-muted-foreground"><input type="checkbox" aria-required={!isEdit} checked={terms} onChange={(e) => setTerms(e.target.checked)} /> {t(lang, 'accept_pre')}<a href={(ar ? '/ar' : '') + '/supplier-agreement'} target="_blank" rel="noopener" className="text-primary font-semibold">{t(lang, 'terms_link')}</a>{t(lang, 'accept_post')}{!isEdit && <Need lang={lang} req />}</label>
    {!isEdit && <label className="flex gap-2 items-start mt-2.5 text-[13px] text-muted-foreground"><input type="checkbox" className="mt-0.5" checked={marketingOptIn} onChange={(e) => setMarketingOptIn(e.target.checked)} /> {t('en', 'marketing_opt_in')}</label>}
    <Button className="w-full mt-3" disabled={busy || uploading || !kycRead} onClick={save}>
      {busy ? (isEdit ? (ar ? 'جارٍ الحفظ…' : 'Saving…') : t(lang, 'submitting'))
            : isEdit ? (ar ? 'حفظ التغييرات' : 'Save changes') : t(lang, 'submit_approval')}
    </Button>
    {msg && <div role="alert" className={S.err}>{msg}</div>}
    {saved && !msg && <div role="status" className={cn(S.sub, 'mt-2 font-semibold text-primary')}>{ar ? 'تم حفظ التغييرات.' : 'Changes saved.'}</div>}
  </Card>);
}
export { ProfileForm };
