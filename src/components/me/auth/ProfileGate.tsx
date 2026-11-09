// @ts-nocheck
'use client';
import { useEffect, useState } from 'react';
import { useFailover } from '@/lib/otpFailover';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { WhatsAppChoice } from '@/components/portal/WhatsAppChoice';
import { waSignupSettled } from '@/components/portal/whatsappChoiceText';
import { drop } from '../prefetch';
import { t, errText, transportFailed } from '../portalText';
import { call } from '../api';
import { S } from '../styles';
import { AuthShell } from './AuthShell';

// Under 18 on today's UTC date, from the YYYY-MM-DD a date input produces. Mirrors
// supabase/functions/_shared/account_rule.ts, which is the authority; this only shows the message early.
function isUnder18(d) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(d || '')); if (!m) return false;
  const t = new Date(); let a = t.getUTCFullYear() - +m[1]; const mo = t.getUTCMonth() + 1, dd = t.getUTCDate();
  if (mo < +m[2] || (mo === +m[2] && dd < +m[3])) a--;
  return a >= 0 && a < 18;
}
function ProfileGate({ token, lang, theme, onDone }) {
  const [st, setSt] = useState(null);
  const [full_name, setFullName] = useState(''); const [phone, setPhone] = useState(''); const [dob, setDob] = useState('');
  const [emCode, setEmCode] = useState(''); const [smsCode, setSmsCode] = useState(''); const [sentSms, setSentSms] = useState(false); const [sentEmail, setSentEmail] = useState(false);
  const [terms, setTerms] = useState(false); const [busy, setBusy] = useState(''); const [msg, setMsg] = useState('');
  // Promotional messages are opt-in (19 Oct 2026, founder, legal finding 2): a SEPARATE box, never pre-ticked,
  // never required. Guarded by scripts/checks/promotional_messages_are_opt_in.test.mjs.
  const [marketingOptIn, setMarketingOptIn] = useState(false);
  const load = () => call('kyc', { action: 'state' }, token).then((j) => { if (transportFailed(j)) { setMsg(t(lang, 'load_failed')); return; } setSt(j); setFullName((x) => x || j.full_name || ''); setPhone((x) => x || j.phone || ''); setDob((x) => x || j.dob || ''); }).catch(() => setMsg(t(lang, 'load_failed')));
  useEffect(() => { drop(); load(); }, []);
  // A HOOK BELONGS ABOVE THE EARLY RETURN (2 Nov 2026, customer sign-up walk, React error #310): this sat below
  // `if (!st) return`, so the render that first had the state called one more hook than the loading render and
  // every new customer's "Complete your account" crashed to "This page couldn't load".
  const failover = useFailover();
  if (!st) return <div className={S.center}>{t(lang, 'loading')}</div>;
  const saveProfile = async () => { if (!dob) { setMsg(t(lang, 'err_dob_required')); return; } if (isUnder18(dob)) { setMsg(t(lang, 'err_under_18')); return; } setBusy('save'); setMsg(''); const j = await call('kyc', { action: 'save_customer', full_name, phone, dob, lang }, token); setBusy(''); if (j && j.ok) load(); else setMsg(errText(j, lang, 'load_failed')); };
  // sentSms carries the CHANNEL, not a boolean: kyc falls back to a voice call when the number is a
  // landline, and telling someone to check their junk folder for a code that is being read down the
  // phone is the wrong instruction.
  // The first code to a UAE mobile goes by WhatsApp (kyc nextChannel, 18 Oct 2026); 'sms' is the explicit failover.
  const sendSms = async (channel?: 'sms' | 'whatsapp') => { if (!phone) { setMsg(t(lang, 'enter_mobile_first')); return; } setBusy('sms'); setMsg(''); const j = await call('kyc', { action: 'send_sms', phone, ...(channel ? { channel } : {}) }, token); setBusy(''); if (j && j.ok) { setSentSms(j.channel || 'sms'); if (j.channel === 'whatsapp') failover(() => call('kyc', { action: 'phone_failover', phone }, token), () => setSentSms('sms_failover')); } else setMsg(errText(j, lang, 'err_code_send')); };
  const verifySms = async () => { setBusy('vsms'); setMsg(''); const j = await call('kyc', { action: 'verify_sms', phone, code: smsCode }, token); setBusy(''); if (j && j.ok) load(); else setMsg(errText(j, lang, 'err_incorrect')); };
  const sendEmailCode = async () => { setBusy('em'); setMsg(''); const j = await call('kyc', { action: 'send_email' }, token); setBusy(''); if (j && j.ok) setSentEmail(true); else setMsg(errText(j, lang, 'err_code_send')); };
  const verifyEmail = async () => { setBusy('vem'); setMsg(''); const j = await call('kyc', { action: 'verify_email', code: emCode }, token); setBusy(''); if (j && j.ok) load(); else setMsg(errText(j, lang, 'err_incorrect')); };
  const acceptTerms = async () => { if (!terms) { setMsg(t(lang, 'must_accept')); return; } setBusy('terms'); setMsg(''); const j = await call('kyc', { action: 'accept_terms', marketing_consent: marketingOptIn === true }, token); if (j && j.ok) {
      // THE CERTIFICATE LANDS AFTER THE ANSWER (kyc accept_terms renders the signed PDF in the background), and the account is
      // complete only once it has (terms_signed). Reading the state once left the customer on this unchanged form, with no word,
      // until they reloaded (measured 2 Nov 2026 by the sign-up walk: still here 60 s after "Finish & continue"). The button
      // stays on "Finishing…" while the state is asked again, every 2.5 s for up to two minutes.
      for (let i = 0; i < 48; i++) { const s = await call('kyc', { action: 'state' }, token).catch(() => null); if (s && s.terms_signed) break; await new Promise((r) => setTimeout(r, 2500)); }
      setBusy(''); onDone();
    } else { setBusy(''); setMsg(errText(j, lang, 'load_failed')); } };
  // DOB IS REQUIRED AGAIN (founder's account rule, 14 Sep 2026: name, date of birth with under-18
  // rejected, OTP-verified mobile/email, Terms). The 6 Sep change made it optional because a customer
  // without one was silently stuck; the fix for silence is a message, not dropping the field. kyc now
  // answers dob_required / under_18 / dob_invalid in words (errText), the under-18 line shows the moment
  // the date is entered, and `complete`, kyc accept_terms and create_inquiry all require it.
  const profileDone = st.full_name && st.phone && st.dob;
  return (<AuthShell lang={lang}><Card className="w-full p-6 sm:p-7">
    <h1 className="font-head text-[20px] font-extrabold tracking-tight text-foreground">{t(lang, 'gate_title')}</h1>
    <div className={cn(S.sub, 'mt-1.5')}>{t(lang, 'gate_sub')}</div>
    <Input className="mt-3" aria-label={t(lang, 'full_name')} autoComplete="name" placeholder={t(lang, 'full_name')} value={full_name} onChange={(e) => setFullName(e.target.value)} />
    <Input className="mt-3" aria-label={t(lang, 'acct_phone')} type="tel" dir="ltr" inputMode="tel" autoComplete="tel" placeholder={t(lang, 'mobile_ph')} value={phone} onChange={(e) => setPhone(e.target.value)} />
    <label htmlFor="qd-dob" className={cn(S.sub, 'mt-3 mb-1 block')}>{t(lang, 'dob_label')}</label>
    {/* The native date picker follows the customer's chosen theme; it was pinned dark (audit 14 Sep). */}
    <Input id="qd-dob" type="date" className="mt-0" style={{ colorScheme: theme === 'light' ? 'light' : 'dark' }} value={dob} required aria-invalid={isUnder18(dob) || undefined} onChange={(e) => setDob(e.target.value)} />
    {isUnder18(dob) && <div className={S.err} role="alert">{t(lang, 'err_under_18')}</div>}
    {/* Always available, not only while the profile is incomplete: the number typed at signup is the
        one the code is sent to, and once all three fields were filled the only way to correct a wrong
        number was to verify it first - which is impossible if it is the wrong number. */}
    <Button className="w-full mt-3" disabled={busy === 'save'} onClick={saveProfile}>{busy === 'save' ? t(lang, 'saving') : t(lang, 'save_details')}</Button>
    {profileDone && <>
      <div className={cn(S.h2, 'mt-4')}>{t(lang, 'verify_mobile')} {st.phone_verified ? <span className="text-primary text-[12px] font-bold ml-1.5">{t(lang, 'verified')}</span> : null}</div>
      {!st.phone_verified && (!sentSms ? <div className="mt-3 flex flex-wrap items-center gap-3"><Button size="sm" disabled={busy === 'sms'} onClick={() => sendSms('whatsapp')}>{busy === 'sms' ? t(lang, 'sending') : t(lang, 'send_wa')}</Button><Button variant="link" className="px-0 h-auto" disabled={busy === 'sms'} onClick={() => sendSms('sms')}>{t(lang, 'send_sms')}</Button></div>
        : <><div className={S.hint}>{t(lang, sentSms === 'call' ? 'call_note' : sentSms === 'whatsapp' ? 'wa_note' : sentSms === 'sms_failover' ? 'wa_failed_note' : 'junk_note')}</div>{sentSms === 'whatsapp' && <Button variant="link" className="px-0 h-auto" disabled={busy === 'sms'} onClick={() => sendSms('sms')}>{t(lang, 'send_by_sms')}</Button>}<div className={S.frow}><Input aria-label={t(lang, 'code_label')} inputMode="numeric" autoComplete="one-time-code" placeholder={t(lang, 'code_placeholder')} value={smsCode} onChange={(e) => setSmsCode(e.target.value)} /><Button size="sm" disabled={busy === 'vsms'} onClick={verifySms}>{t(lang, 'verify')}</Button></div><Button variant="link" className="mt-1 px-0 h-auto" onClick={() => { setSentSms(false); setSmsCode(''); }}>{t(lang, 'use_diff_number')}</Button></>)}
      {/* Asked the moment the mobile is verified, inside sign-up (founder, 14-15 Sep 2026); the terms
          step does not appear until it is answered, and kyc accept_terms refuses without the answer. */}
      {st.phone_verified && !waSignupSettled(st.whatsapp) && <div className="mt-4"><WhatsAppChoice token={token} lang={lang} mode="signup" current={st.whatsapp} mobile={st.phone} onDone={() => load()} /></div>}
      <div className={cn(S.h2, 'mt-4')}>{t(lang, 'verify_email_h')} {st.email_verified ? <span className="text-primary text-[12px] font-bold ml-1.5">{t(lang, 'verified')}</span> : null}</div>
      {!st.email_verified && (!sentEmail ? <Button size="sm" className="mt-3" disabled={busy === 'em'} onClick={sendEmailCode}>{busy === 'em' ? t(lang, 'sending') : t(lang, 'send_email_code')}</Button>
        : <><div className={S.hint}>{t(lang, 'junk_note')}</div><div className={S.frow}><Input aria-label={t(lang, 'code_label')} inputMode="numeric" placeholder={t(lang, 'code_placeholder')} value={emCode} onChange={(e) => setEmCode(e.target.value)} /><Button size="sm" disabled={busy === 'vem'} onClick={verifyEmail}>{t(lang, 'verify')}</Button></div></>)}
      {st.phone_verified && st.email_verified && waSignupSettled(st.whatsapp) && <>
        <label className="flex gap-2 items-center mt-4 text-[13px] text-muted-foreground"><input type="checkbox" checked={terms} onChange={(e) => setTerms(e.target.checked)} /> {t(lang, 'accept_pre')}<a href="/terms" target="_blank" rel="noopener" className="text-primary font-semibold">{t(lang, 'terms_link')}</a>{t(lang, 'accept_post')}</label>
        <label className="flex gap-2 items-start mt-3 text-[13px] text-muted-foreground"><input type="checkbox" className="mt-0.5" checked={marketingOptIn} onChange={(e) => setMarketingOptIn(e.target.checked)} /> {t(lang, 'marketing_opt_in')}</label>
        <Button className="w-full mt-3" disabled={busy === 'terms'} onClick={acceptTerms}>{busy === 'terms' ? t(lang, 'finishing') : t(lang, 'finish_continue')}</Button>
      </>}
    </>}
    {msg && <div className={S.err}>{msg}</div>}
  </Card></AuthShell>);
}
export { isUnder18, ProfileGate };
