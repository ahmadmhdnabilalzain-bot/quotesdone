// @ts-nocheck
'use client';
import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { PrivacyControls } from '@/components/portal/PrivacyControls';
import { WhatsAppChoice } from '@/components/portal/WhatsAppChoice';
import { waText } from '@/components/portal/whatsappChoiceText';
import { t, tf, errText } from '../portalText';
// The account rule itself, not a copy: the same function customer_api create_inquiry gates on.
import { accountMissing } from '../../../../supabase/functions/_shared/account_rule';
import { tokenAlive, call } from '../api';
import { S } from '../styles';
import { isUnder18 } from '../auth/ProfileGate';

// customer_api action='me' has served the customer's own row since the portal was written and no
// file in src/ ever called it — the account the customer holds was the one thing they could not
// look at. It is read-only on purpose: there is no endpoint that writes a preference back to the
// profile, so this states which choices are device-local rather than implying they were saved.
// AN ACCOUNT SCREEN YOU COULD NOT CHANGE ANYTHING ON.
//
// This was read-only and said so honestly — "We have no settings endpoint that writes them back to
// your profile yet, so nothing here is saved to your account." The honesty was right and the
// situation was not: customers.locale has been READ for months (my_inquiries serves it, the portal
// applies it on a new device) and nothing has ever written it, so an Arabic customer re-chose their
// language on every device forever. customer_api gained a narrow set_locale for exactly this.
//
// Name and mobile go through kyc save_customer, which is the routine that already validates them —
// and which now clears phone_verified when the number changes. That is the reason the mobile field
// carries a warning rather than a quiet save: the next load will ask them to verify the new number,
// and being told that before they press the button is the difference between a feature and a trap.
// DECLARED ONCE, OUTSIDE THE RENDER (customer-portal audit 21 Sep 2026, item 3). `Row` used to be a
// const inside AccountSettings, so every keystroke made a NEW component type: React unmounted the
// old <Row> subtree — the <Input> with it — and mounted a fresh one, which dropped focus to <body>
// and the rest of the word with it (typing "audit" produced "a"). The WhatsApp row below already
// wrote its grid out by hand for exactly this reason; the Name/Phone/DOB rows had the same bug.
const Row = ({ label, children }) => (
  <div className="grid gap-1 sm:grid-cols-[190px_1fr] sm:items-center sm:gap-3">
    <div className="text-[12.5px] font-medium text-muted-foreground">{label}</div>
    <div className="min-w-0">{children}</div>
  </div>
);
function AccountSettings({ token, lang, onChanged }) {
  const [me, setMe] = useState(null); const [err, setErr] = useState('');
  const [name, setName] = useState(''); const [phone, setPhone] = useState(''); const [dob, setDob] = useState('');
  const [busy, setBusy] = useState(''); const [msg, setMsg] = useState('');
  // A refusal was printed in the same muted grey as "Saved" and never announced (e2e forms probe, 23 Sep
  // 2026: name emptied -> kyc 400 enter_name -> a grey line). An error is an alert now.
  const [msgErr, setMsgErr] = useState(false);
  // THE TERMS VERSION ON FILE vs THE CURRENT ONE (6 Oct 2026, release review of #1240): shown here with an accept
  // button, so a customer is never sent to a page that cannot act. customer_api accept_terms records it.
  const [termsV, setTermsV] = useState(''); const [termsTick, setTermsTick] = useState(false);
  const load = () => call('customer_api', { action: 'me' }, token)
    .then((j) => { if (j && j.customer) { setTermsV(j.terms_current_version || ''); setMe(j.customer); setName(j.customer.full_name || ''); setPhone(j.customer.phone || ''); setDob(String(j.customer.date_of_birth || '').slice(0, 10)); } else setErr(t(lang, 'acct_failed')); })
    .catch(() => setErr(t(lang, 'acct_failed')));
  // DO NOT ASK AN AUTHENTICATED ENDPOINT WHO WE ARE BEFORE WE HAVE A TOKEN. This ran on the first
  // render, when `token` is still '' because it is read from localStorage and from
  // SB().auth.getSession() inside an effect that has not resolved yet. Measured on a signed-in
  // customer: two 401s against /kyc in the console on every load, before the real call succeeded.
  // Wrong in three ways - it spends a round trip per mount, it puts a red error in the console of
  // a working page so a real one is easy to miss, and it burns the one refresh attempt the
  // `retried` flag exists to protect. The effect re-runs when the token arrives, so waiting is free.
  // Wait for a token, and for a token that has not already expired. SB.auth refreshes on its own
  // and the auth listener re-renders with the new one, so this costs nothing but the 401.
  // The WhatsApp answer is served by kyc state, not customer_api me; undefined = not loaded or not
  // served, and the row stays hidden rather than showing a state nobody measured.
  const [wa, setWa] = useState(undefined);
  const loadWa = () => call('kyc', { action: 'state' }, token).then((j) => setWa(j && j.whatsapp ? j.whatsapp : undefined)).catch(() => setWa(undefined));
  useEffect(() => { if (tokenAlive(token)) { load(); loadWa(); } }, [token]);
  if (err) return <div className={S.err}>{err}</div>;
  if (!me) return <div className={S.sub}>{t(lang, 'loading')}</div>;
  const since = me.created_at ? new Date(me.created_at).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '';
  const digits = (v) => String(v || '').replace(/\D/g, '');
  const phoneChanged = digits(phone) !== digits(me.phone);
  const dobChanged = dob !== String(me.date_of_birth || '').slice(0, 10);
  const dirty = (name || '') !== (me.full_name || '') || phoneChanged || dobChanged;
  // Same rule create_inquiry applies, plus the reachable mobile it also requires.
  const missing = accountMissing(me);
  if (!digits(me.phone)) missing.push('mobile_number');
  // A badge belongs to the channel that was verified, and a number that is not there is not verified.
  const phoneOk = !!me.phone_verified && !!digits(me.phone);
  const badge = (ok) => <span className={ok ? 'text-primary font-bold' : ''}>{t(lang, ok ? 'verified' : 'acct_unverified')}</span>;
  const saveProfile = async () => {
    if (isUnder18(dob)) { setMsgErr(true); setMsg(t(lang, 'err_under_18')); return; }
    setBusy('save'); setMsg('');
    // kyc save_customer already validates dob (dob_required / dob_invalid / under_18, answered by errText).
    const j = await call('kyc', { action: 'save_customer', full_name: name, phone, dob: dob || me.date_of_birth || '' }, token);
    setBusy('');
    setMsgErr(!(j && j.ok));
    if (j && j.ok) { setMsg(t(lang, j.phone_reverify_required ? 'acct_reverify' : 'acct_saved')); load(); if (onChanged) onChanged(); }
    else setMsg(errText(j, lang, 'acct_failed'));
  };
  const saveLocale = async (loc) => {
    setBusy('loc'); setMsg('');
    const j = await call('customer_api', { action: 'set_locale', locale: loc }, token);
    setBusy('');
    setMsgErr(!(j && j.ok));
    if (j && j.ok) { setMsg(t(lang, 'acct_saved')); load(); } else setMsg(errText(j, lang, 'acct_failed'));
  };
  return (<div className="flex flex-col gap-4">
    <p className={S.sub}>{t(lang, 'acct_sub')}</p>
    {missing.length ? <Card className="p-4 border-warn-fg/40" role="status">
      <div className="text-[13.5px] font-semibold text-warn-fg">{t(lang, 'acct_incomplete_h')}</div>
      <ul className="mt-1.5 list-disc ps-5 text-[13px] text-foreground">{missing.map((m) => <li key={m}>{t(lang, 'acct_miss_' + m)}</li>)}</ul>
    </Card> : null}
    <Card className="flex flex-col gap-3.5 p-4">
      <Row label={t(lang, 'acct_name')}><Input aria-label={t(lang, 'acct_name')} autoComplete="name" value={name} onChange={(e) => setName(e.target.value)} /></Row>
      <Row label={t(lang, 'acct_phone')}>
        <Input aria-label={t(lang, 'acct_phone')} type="tel" dir="ltr" autoComplete="tel" value={phone} onChange={(e) => setPhone(e.target.value)} inputMode="tel" />
        <div className={cn('mt-1 text-[11.5px]', phoneChanged ? 'text-warn-fg' : 'text-muted-foreground')}>
          {phoneChanged ? t(lang, 'acct_phone_warn') : badge(phoneOk)}
        </div>
      </Row>
      <Row label={t(lang, 'acct_email')}>
        {/* Isolated so a Latin address does not scramble inside an Arabic line. */}
        <div className="text-[13px] text-foreground"><bdi dir="ltr">{me.email || '—'}</bdi></div>
        <div className="mt-1 text-[11.5px] text-muted-foreground">{badge(!!me.email_verified && !!me.email)}</div>
      </Row>
      <Row label={t(lang, 'acct_dob')}>
        <Input type="date" aria-label={t(lang, 'acct_dob')} autoComplete="bday" value={dob} aria-invalid={isUnder18(dob) || undefined} onChange={(e) => setDob(e.target.value)} />
        {isUnder18(dob) && <div className={S.err} role="alert">{t(lang, 'err_under_18')}</div>}
      </Row>
      <Row label={t(lang, 'acct_locale')}>
        <div className="flex flex-wrap gap-2">
          {[['en', 'English'], ['ar', 'العربية']].map(([code, labelText]) => (
            <Button key={code} type="button" size="sm" variant={me.locale === code ? 'default' : 'outline'}
              disabled={busy === 'loc' || me.locale === code} onClick={() => saveLocale(code)}>{labelText}</Button>
          ))}
        </div>
        <div className="mt-1 text-[11.5px] text-muted-foreground">{t(lang, 'lang_note')}</div>
      </Row>
      {/* Same grid as Row, written out: Row is declared inside this render, so anything under it is a
          new component type on every keystroke and would lose the half-typed number and code. */}
      {wa ? <div className="grid gap-1 sm:grid-cols-[190px_1fr] sm:items-start sm:gap-3">
        <div className="text-[12.5px] font-medium text-muted-foreground">{waText(lang, 'row_label')}</div>
        <div className="min-w-0"><WhatsAppChoice token={token} lang={lang} mode="settings" current={wa} mobile={me.phone} onDone={loadWa} /></div>
      </div> : null}
      {termsV && me.tos_accepted_at ? <Row label={t(lang, 'acct_terms')}>
        {me.tos_version === termsV
          ? <div className="text-[13px] text-foreground">{tf(lang, 'acct_terms_ok', { v: termsV })}</div>
          : <div className="flex flex-col gap-2">
              <div className="text-[13px] text-warn-fg">{tf(lang, 'acct_terms_old', { old: me.tos_version || '—', v: termsV })}</div>
              <label className="flex items-center gap-2 text-[12.5px] text-muted-foreground"><input type="checkbox" checked={termsTick} onChange={(e) => setTermsTick(e.target.checked)} /> <a href={lang === 'ar' ? '/ar/terms' : '/terms'} target="_blank" rel="noopener" className="text-primary font-semibold">{t(lang, 'terms_read')}</a></label>
              <div><Button size="sm" disabled={!termsTick || busy === 'terms'} onClick={async () => { setBusy('terms'); setMsg(''); const j = await call('customer_api', { action: 'accept_terms' }, token); setBusy(''); setMsgErr(!(j && j.ok)); if (j && j.ok) { setMsg(t(lang, 'terms_accepted_ok')); setTermsTick(false); load(); } else setMsg(errText(j, lang, 'acct_failed')); }}>{t(lang, 'terms_accept_btn')}</Button></div>
            </div>}
      </Row> : null}
      <Row label={t(lang, 'acct_since')}><div className="text-[13px] text-foreground">{since || '—'}</div></Row>
      <div className="flex flex-wrap items-center gap-3 border-t border-border pt-3.5">
        <Button size="sm" disabled={!dirty || busy === 'save'} onClick={saveProfile}>{busy === 'save' ? t(lang, 'saving') : t(lang, 'save_details')}</Button>
        {msg ? (msgErr ? <span role="alert" className={S.err}>{msg}</span> : <span role="status" className="text-[12.5px] text-muted-foreground">{msg}</span>) : null}
      </div>
    </Card>
    <p className={S.hint}>{t(lang, 'acct_device_note')}</p>
    <PrivacyControls token={token} lang={lang === 'ar' ? 'ar' : 'en'} party="customer" />
  </div>);
}
export { AccountSettings };
