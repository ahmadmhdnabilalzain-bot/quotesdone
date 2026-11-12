// @ts-nocheck
'use client';
import { useEffect, useState } from 'react';
import { readFirstTouch } from '@/lib/firstTouch';
// create_company answers with the supplier `me` would read: the form opens on it, no `me` after it (src/lib/supplierRegistrationReads.ts)
import { supplierFromCreate } from '@/lib/supplierRegistrationReads';
import { srvMsg, TRADE_GROUPS, tradeLabel } from '../serverCopy';
import { call } from '../api';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { Lbl, wentExpired } from './helpers';
import { t } from './copy';
import { S } from './styles';
import { ProfileForm } from './ProfileForm';

// Profile tab for an established supplier. Reuses ProfileForm rather than duplicating it, so the
// same validation, terms handling and save_profile call apply whether the supplier is registering
// for the first time or correcting a detail two years later.
function ProfilePanel({ token, lang, onSaved, initial = null, onExpired = null, goTo = null }) {
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
    <ProfileForm token={token} me={me} onSaved={() => { load(); if (onSaved) onSaved(); }} lang={lang} mode="edit" goTo={goTo} />
  </div>;
}
// THE REGISTRATION, ONE GUIDED FORM FOR BOTH DOORS (11 Nov 2026, customer_support; registration certification findings 7 and 9).
// `initial` is the `me` Dashboard already read: undefined while it is on its way (this reads its own), null for an account with
// no company, the supplier otherwise. It used to read `me` again here, AFTER the dashboard had answered no_company, so the
// public door's Verify -> "Register your company" was three calls in series (login_otp, then dashboard, then this me): 3.48 s
// median on desktop against 3 s. `invited`: the company was claimed from an invitation and has not submitted its registration;
// the form opens on "Finish registering <company>" with what we hold, and `onSkip` opens the workspace instead.
function Onboarding({ token, onDone, lang, onExpired = null, initial = undefined, invited = false, onSkip = null }) {
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
    {!me ? <NewCompany token={token} onReady={(j) => { const s = supplierFromCreate(j); if (s) setMe(s); else load(); }} lang={lang} /> : <ProfileForm token={token} me={me} onSaved={onDone} lang={lang} />}
  </div>);
}
// ONE QUESTION PER FACT, AND THE TRADE IS A CODE (15 Sep 2026, agent: customer_support).
// The emirate was asked twice: one emirate here, then the service-emirate chips in ProfileForm. The
// chips are the answer that is kept (save_profile stores service_emirates and capability coverage
// defaults to them), so this screen no longer asks. The trade was free text over 29 suggestions that
// no taxonomy_trade code carried; it is now one of the 40 codes, which create_company writes to
// leads.sector unchanged. "My trade isn't listed" keeps the founder's open list (14 Sep 2026: a new
// trade is welcome): the typed words are stored in the same column and read by a person.
const TRADE_OTHER = '__other';
function NewCompany({ token, onReady, lang }) {
  const [cname, setCname] = useState(''); const [trade, setTrade] = useState(''); const [other, setOther] = useState(''); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const category = trade === TRADE_OTHER ? (other.trim().slice(0, 60) || null) : (trade || null);
  const create = async () => { if (cname.trim().length < 2) { setMsg(t(lang, 'enter_company')); return; } setBusy(true); setMsg(''); const j = await call('supplier_api', { action: 'create_company', company_name: cname.trim(), category, role: 'supplier', lang, first_touch: (() => { try { return readFirstTouch(window.localStorage); } catch (_e) { return null; } })() }, token); setBusy(false); if (j && j.ok) onReady(j); else setMsg(srvMsg(lang, j, t(lang, 'err_generic'))); };
  // 195 trades read as twelve groups (taxonomy_trade_group), each sorted by its label in the reader's language.
  const byLabel = (a, b) => tradeLabel(lang, a).localeCompare(tradeLabel(lang, b), lang);
  return (<Card className="qd-panel p-5">
    <h2 className={S.h2}>{t(lang, 'onboard_title')}</h2>
    <div className={cn(S.sub, 'mb-2')}>{t(lang, 'onboard_sub')}</div>
    {/* The refusal is said under the name, and goes as soon as he types (browser walk M4: "Enter your company name." stayed). */}
    <Lbl need="req" lang={lang} className="mt-3" text={t(lang, 'company_name')}><Input dir="auto" autoComplete="organization" aria-required="true" aria-invalid={msg === t(lang, 'enter_company') || undefined} placeholder={t(lang, 'company_name')} value={cname} onChange={(e) => { setCname(e.target.value); if (msg) setMsg(''); }} onKeyDown={(e) => e.key === 'Enter' && create()} /></Lbl>
    {msg === t(lang, 'enter_company') && <div role="alert" className={S.err}>{msg}</div>}
    <Lbl need="opt" lang={lang} className="mt-3" text={t(lang, 'trade_label')}>
      <select className={cn(S.field, 'mt-0 bg-card')} value={trade} onChange={(e) => { setTrade(e.target.value); if (msg) setMsg(''); }} aria-describedby="qd-trade-help">
        <option value="">{t(lang, 'trade_ph')}</option>
        {TRADE_GROUPS.map((g) => <optgroup key={g.code} label={lang === 'ar' ? g.ar : g.en}>{[...g.codes].sort(byLabel).map((c) => <option key={c} value={c}>{tradeLabel(lang, c)}</option>)}</optgroup>)}
        <option value={TRADE_OTHER}>{t(lang, 'trade_not_listed')}</option>
      </select>
    </Lbl>
    {trade === TRADE_OTHER && <Lbl className="mt-2" text={t(lang, 'trade_other_ph')}><Input dir="auto" maxLength={60} placeholder={t(lang, 'trade_other_ph')} value={other} onChange={(e) => setOther(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && create()} /></Lbl>}
    <div id="qd-trade-help" className={cn(S.sub, 'mt-1 mb-2 text-[12px]')}>{t(lang, 'trade_help')}</div>
    <Button className="w-full mt-3" busy={busy} disabled={busy} onClick={create}>{busy ? t(lang, 'sending') : t(lang, 'create_company')}</Button>
    {msg && msg !== t(lang, 'enter_company') && <div role="alert" className={S.err}>{msg}</div>}
  </Card>);
}
export { ProfilePanel, Onboarding };
