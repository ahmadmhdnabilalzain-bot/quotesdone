// @ts-nocheck
'use client';
import { useEffect, useRef, useState } from 'react';
import { readFirstTouch } from '@/lib/firstTouch';
// create_company answers with the supplier `me` would read: the form opens on it, no `me` after it (src/lib/supplierRegistrationReads.ts)
import { supplierFromCreate } from '@/lib/supplierRegistrationReads';
import { srvMsg } from '../serverCopy';
import { call } from '../api';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { wentExpired } from './helpers';
import { t } from './copy';
import { S } from './styles';
import { ProfileForm } from './ProfileForm';

// Profile tab for an established supplier. Reuses ProfileForm rather than duplicating it, so the
// same validation, terms handling and save_profile call apply whether the supplier is registering
// for the first time or correcting a detail two years later.
function ProfilePanel({ token, lang, onSaved, initial = null, onExpired = null, goTo = null, onVerified = null }) {
  // Audit 21 Sep 2026, finding 34: the tab re-read `me` the portal had already read, and waited for it.
  const [me, setMe] = useState(initial || undefined);
  const load = () => call('supplier_api', { action: 'me' }, token).then((j) => { if (wentExpired(j, onExpired)) return; setMe(j.supplier || null); }).catch(() => setMe(null));
  useEffect(() => { if (!initial) load(); }, [token]);
  if (me === undefined) return <Card className="qd-panel p-5">{t(lang, 'loading')}</Card>;
  if (!me) return <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'something_wrong')}</div><div className={S.sub}>{t(lang, 'err_generic')}</div></Card>;
  return <div className={S.list}>
    <Card className="qd-panel p-5">
      <div className={S.h2}>{lang === 'ar' ? 'ملف الشركة' : 'Company profile'}</div>
      <div className={cn(S.sub, 'mt-1')}>{lang === 'ar'
        ? 'ما تكتبونه هنا يحدّد الطلبات التي تصلكم؛ إذ تُطابَق الطلبات على القطاع والمنتجات والخدمات والفئات، وكلما كانت أدق زادت فرص مطابقتكم.'
        : 'What you write here decides which requests reach you. Requests are matched on your sector, products, services and categories — the more specific these are, the more you match.'}</div>
    </Card>
    <ProfileForm token={token} me={me} onSaved={() => { load(); if (onSaved) onSaved(); }} lang={lang} mode="edit" goTo={goTo} onExpired={onExpired} onVerified={onVerified} />
  </div>;
}
// THE REGISTRATION, ONE GUIDED FORM FOR BOTH DOORS (11 Nov 2026, customer_support; registration certification findings 7 and 9).
// `initial` is the `me` Dashboard already read: undefined while it is on its way (this reads its own), null for an account with
// no company, the supplier otherwise. It used to read `me` again here, AFTER the dashboard had answered no_company, so the
// public door's Verify -> "Register your company" was three calls in series (login_otp, then dashboard, then this me): 3.48 s
// median on desktop against 3 s. `invited`: the company was claimed from an invitation and has not submitted its registration;
// the form opens on "Finish registering <company>" with what we hold, and `onSkip` opens the workspace instead.
function Onboarding({ token, onDone, lang, onExpired = null, initial = undefined, invited = false, onSkip = null, onVerified = null }) {
  const [me, setMe] = useState(initial);
  // An expired token here offered "Register your company" to a supplier who already has one (SP-C-08).
  const load = () => call('supplier_api', { action: 'me' }, token).then((j) => { if (wentExpired(j, onExpired)) return; setMe(j.supplier || null); }).catch(() => setMe(null));
  useEffect(() => { if (initial === undefined) load(); }, []);
  useEffect(() => { if (initial !== undefined) setMe((m) => (m === undefined ? initial : m)); }, [initial]);
  if (me === undefined) return <div className={S.center}>{t(lang, 'loading')}</div>;
  return (<div className={S.wrap} style={{ maxWidth: 640 }}>
    <h1 dir="auto" className={cn(S.h1, 'mb-1 font-head')}>{invited && me ? t(lang, 'finish_title') + ' ' + me.company_name : t(lang, 'setup_title')}</h1>
    <div className={cn(S.sub, 'mb-3.5')}>{invited && me ? t(lang, 'finish_sub') : me ? t(lang, 'setup_sub_profile') : t(lang, 'setup_sub_company')}</div>
    {invited && me && onSkip ? <Button variant="link" className="mb-2 h-auto px-0" onClick={onSkip}>{t(lang, 'finish_later')}</Button> : null}
    {!me ? <NewCompany token={token} onReady={(j) => { const s = supplierFromCreate(j); if (s) setMe(s); else load(); }} onExists={load} lang={lang} /> : <ProfileForm token={token} me={me} onSaved={onDone} lang={lang} onVerified={onVerified} />}
  </div>);
}
// NOTHING TO TYPE BEFORE THE FORM (12 Nov 2026, sales_engineer, built by it_engineer; founder ruling 1672, after he registered his
// own company on his iPhone: "there was something like pick your category. Let's not add that option ... let these things be
// extracted automatically from the company profile and the trade license ... even the company name, he doesn't have to fill it").
// This screen asked for the company name and a trade picked from 223 codes in twelve groups. Neither is asked now: the trade
// licence names the company (fn_sales_engineer_verifies_supplier) and the reading of the licence and the profile proposes what it
// does, which he confirms on the Services step as before. The supplier's row is created the moment he arrives here, with no name
// (supplier_api/create_company.ts), and the registration form opens on create_company's own answer. While it is created a ring
// turns; a refusal is said in plain words with "Try again", 44 px tall.
// Prevented by: scripts/checks/signup_trade_codes_are_the_taxonomy.test.mjs and the_registration_form_answers_where_he_looks.test.mjs.
function NewCompany({ token, onReady, onExists, lang }) {
  const [busy, setBusy] = useState(true); const [msg, setMsg] = useState('');
  const asked = useRef(false);
  const create = async () => {
    setBusy(true); setMsg('');
    let j = null;
    try { j = await call('supplier_api', { action: 'create_company', role: 'supplier', lang, first_touch: (() => { try { return readFirstTouch(window.localStorage); } catch (_e) { return null; } })() }, token); } catch (_e) { j = null; }
    setBusy(false);
    if (j && j.ok) { onReady(j); return; }
    // the account already has its company (a second tab, a slow `me`): it is read, not created twice
    if (j && j.code === 'company_exists') { onExists(); return; }
    // THE DEPLOY WINDOW (review of #1987, S1): this page can be live a few minutes before supplier_api, whose older create_company still
    // refuses a registration with no name ("Enter your company name."). He has no name box to type in, so he is told it is ours and
    // brief, with "Try again", never that sentence.
    if (j && (j.code === 'enter_company' || /enter your company name/i.test(String(j.error || '')))) { setMsg(t(lang, 'onboard_updating')); return; }
    setMsg(srvMsg(lang, j, t(lang, 'onboard_failed')));
  };
  // once per mount (React may run an effect twice in development)
  useEffect(() => { if (asked.current) return; asked.current = true; create(); }, []);
  return (<Card className="qd-panel p-5">
    <h2 className={S.h2}>{t(lang, 'onboard_title')}</h2>
    <div className={cn(S.sub, 'mb-2')}>{t(lang, 'onboard_sub')}</div>
    {!msg && <div role="status" data-testid="registration-opening" className={cn(S.sub, 'mt-2 flex min-h-11 items-center gap-2 font-semibold text-foreground')}><span aria-hidden="true" className="qd-spin" />{t(lang, 'onboard_starting')}</div>}
    {msg && <div role="alert" data-testid="registration-open-error" className={cn(S.err, 'font-semibold')}>{msg}</div>}
    {msg && <Button className="w-full mt-3 min-h-11" busy={busy} disabled={busy} onClick={create}>{busy ? t(lang, 'sending') : t(lang, 'try_again')}</Button>}
  </Card>);
}
export { ProfilePanel, Onboarding };
