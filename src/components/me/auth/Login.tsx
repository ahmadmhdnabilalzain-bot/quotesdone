// @ts-nocheck
'use client';
import { useState } from 'react';
import { useFailover } from '@/lib/otpFailover';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Kicker } from '@/components/ui/sealed';
import { cn } from '@/lib/utils';
import { signupEmailProblem } from '@/lib/signupEmail';
import { t, errText } from '../portalText';
import { call } from '../api';
import { S } from '../styles';
import { AuthShell } from './AuthShell';

function Login({ onAuth, lang }) {
  const failover = useFailover();   // WhatsApp sign-in code -> SMS when Twilio reports it undelivered or late
  const [mode, setMode] = useState('signin'); const [step, setStep] = useState('id'); const [id, setId] = useState(''); const [code, setCode] = useState(''); const [ident, setIdent] = useState(''); const [msg, setMsg] = useState(''); const [busy, setBusy] = useState(false);
  const isSignup = mode === 'signup';
  // An empty press says so, and a sign-up address is checked for shape AND for reserved names that
  // can never receive a code (src/lib/signupEmail.ts; audit 21 Sep 2026, items 26 and 28).
  const send = async () => { const v = id.trim(); if (!v) { setMsg(t(lang, isSignup ? 'err_need_email' : 'err_need_id')); return; } if (isSignup) { const p = signupEmailProblem(v); if (p) { setMsg(t(lang, p)); return; } } setBusy(true); setMsg('');
    let j; try { j = await call('login_otp', { action: 'send', user_kind: 'customer', identifier: v, allow_signup: isSignup, lang }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_code_send')); return; } setBusy(false); if (j && j.ok) { setIdent(j.identifier || v); setStep('code'); if (!v.includes('@')) failover(() => call('login_otp', { action: 'failover', user_kind: 'customer', identifier: j.identifier || v, lang })); } else setMsg(errText(j, lang, 'err_code_send')); };
  const verify = async () => { if (!code.trim()) return; setBusy(true); setMsg(''); let j; try { j = await call('login_otp', { action: 'verify', user_kind: 'customer', identifier: ident, code: code.trim(), lang }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_incorrect')); return; } if (!j || !j.ok || !j.access_token) { setBusy(false); setMsg(errText(j, lang, 'err_incorrect')); return; }
    // THE BUTTON UN-BUSIED WHILE THE PORTAL WAS STILL BOOTING. setBusy(false) fired BEFORE onAuth,
    // so the code was accepted, the button went back to "Verify & sign in", and nothing moved until
    // the dashboard mounted. Busy is HELD across onAuth and released only if it throws — on success
    // this card is replaced by the portal, which carries its own loading state.
    try { await onAuth(j.access_token, j.refresh_token, j.locale); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_incorrect')); } };
  const swap = (m) => { setMode(m); setStep('id'); setMsg(''); setCode(''); };
  return (<AuthShell lang={lang}><Card className="relative w-full overflow-hidden p-6 shadow-e3 sm:p-8">
    <span aria-hidden className="absolute inset-x-10 top-0 h-px bg-linear-to-r from-transparent via-primary/80 to-transparent" />
    <div className="mb-5 md:hidden"><Kicker>{t(lang, 'auth_kicker')}</Kicker></div>
    <div className={cn(S.tabsWrap, 'mb-5 w-full rounded-btn border border-border bg-secondary/40')} role="tablist">
      <button role="tab" aria-selected={!isSignup} className={cn(S.tab, 'flex-1 transition-colors', !isSignup && cn(S.tabOn, 'shadow-e1'))} onClick={() => swap('signin')}>{t(lang, 'tab_signin')}</button>
      <button role="tab" aria-selected={isSignup} className={cn(S.tab, 'flex-1 transition-colors', isSignup && cn(S.tabOn, 'shadow-e1'))} onClick={() => swap('signup')}>{t(lang, 'tab_signup')}</button>
    </div>
    <h1 className="font-head text-[22px] font-semibold tracking-snug text-foreground">{isSignup ? t(lang, 'create_account_title') : t(lang, 'welcome_back')}</h1>
    <div className={cn(S.sub, 'mt-1.5')}>{isSignup ? t(lang, 'signup_sub') : t(lang, 'signin_sub')}</div>
    {step === 'id' ? (<><Input className="mt-5 h-12 text-copy" aria-label={isSignup ? t(lang, 'email_address') : t(lang, 'email_or_mobile')} autoComplete={isSignup ? 'email' : 'username'} placeholder={isSignup ? t(lang, 'email_address') : t(lang, 'email_or_mobile')} value={id} onChange={(e) => setId(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && send()} /><Button size="lg" className="w-full mt-3" disabled={busy} onClick={send}>{busy ? t(lang, 'sending') : (isSignup ? t(lang, 'create_my_account') : t(lang, 'send_code'))}</Button></>)
      : (<><Input className="mt-5 h-12 text-center font-mono text-[18px] tracking-[0.3em]" aria-label={t(lang, 'code_label')} inputMode="numeric" autoComplete="one-time-code" placeholder={t(lang, 'code_placeholder')} value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && verify()} /><div className={S.hint}>{t(lang, 'junk_note')}</div>
        {/* Two controls in a flex column, not two inline buttons: a screen reader read them as one
            run of text ("Verify & sign inUse a different email") — audit 21 Sep 2026, item 28. */}
        <div className="mt-3 flex flex-col items-start gap-2"><Button size="lg" className="w-full" disabled={busy} onClick={verify}>{busy ? t(lang, 'verifying') : (isSignup ? t(lang, 'verify_continue') : t(lang, 'verify_signin'))}</Button><Button variant="link" className="px-0 h-auto" onClick={() => { setStep('id'); setCode(''); setMsg(''); }}>{t(lang, 'use_diff')}</Button></div></>)}
    {msg && <div className={S.err} role="alert">{msg}</div>}
  </Card></AuthShell>);
}
export { Login };
