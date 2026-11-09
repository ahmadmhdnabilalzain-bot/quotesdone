// @ts-nocheck
'use client';
import { Fragment, useEffect, useRef, useState } from 'react';
import { useFailover } from '@/lib/otpFailover';
import { signupEmailProblem } from '@/lib/signupEmail';
import { call } from '../api';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { BrandMark } from '@/components/BrandMark';
import { Lbl } from './helpers';
import { t } from './copy';
import { S } from './styles';

// WHOSE LISTING THIS IS. Rendered only when the URL carried a valid invitation token that
// claim_lookup resolved. `already_claimed` is a real outcome, not an error: a colleague at the same
// company may have registered first, and telling them that is better than a sign-up form that fails
// at the end with "This company is already claimed by another account."
function InviteBanner({ invite, lang, onStart }) {
  const ar = lang === 'ar';
  if (invite.invalid) return (
    <section className="mx-auto w-full max-w-3xl px-4 pt-6" dir={ar ? 'rtl' : 'ltr'}>
      <Card className="qd-panel p-5" role="status">
        <div className="text-[15px] font-bold text-foreground">{ar ? 'رابط الدعوة هذا غير صالح أو انتهت صلاحيته.' : 'This invitation link is not valid or has expired.'}</div>
        <div className={cn(S.sub, 'mt-2 max-w-[62ch]')}>
          {ar ? 'يمكنكم إنشاء حساب أدناه وتسجيل شركتكم مباشرةً، أو مراسلتنا على management@quotesdone.com.'
              : 'You can still create an account below and register your company, or write to management@quotesdone.com.'}
        </div>
      </Card>
    </section>
  );
  const name = invite.company_name || (ar ? 'شركتكم' : 'your company');
  const taken = !invite.claimable;
  return (
    <section className="mx-auto w-full max-w-3xl px-4 pt-6" dir={ar ? 'rtl' : 'ltr'}>
      <Card className="qd-panel p-5">
        <div className="text-[11px] uppercase tracking-[0.18em] text-primary">
          {ar ? 'دعوة شخصية' : 'Your invitation'}
        </div>
        {/* dir="auto" — a Latin company name inside an RTL page otherwise renders its trailing
            "L.L.C." punctuation on the wrong side. */}
        <div dir="auto" className="mt-1.5 text-[19px] font-extrabold leading-tight text-foreground">{name}</div>
        {invite.emirate ? <div className={cn(S.sub, 'mt-0.5')}>{invite.emirate}</div> : null}
        <div className={cn(S.sub, 'mt-3 max-w-[62ch]')}>
          {taken
            ? (ar ? 'هذه الشركة مسجّلة مسبقًا في QuotesDone. إن كان أحد زملائكم قد سجّلها فيُرجى أن تطلبوا منه إضافتكم، أو سجّلوا الدخول بالبريد الذي استُخدم في التسجيل.'
                  : 'This company is already registered on QuotesDone. If a colleague claimed it, ask them to add you — or sign in with the email they used.')
            : (ar ? 'هذا السجل محجوز لشركتكم، فبياناتكم متوفرة لدينا من السجل التجاري العام. لن تملؤوا نموذجًا فارغًا، بل تصحّحون ما لدينا وتؤكّدونه. أنشئوا حسابكم للمطالبة به.'
                  : 'This listing is reserved for your company. We already hold your details from the public trade directory — you are not filling in a blank form, you are correcting what we have and confirming it. Create your account to claim it.')}
        </div>
        {!taken && <Button className="mt-4" onClick={onStart}>{ar ? 'المطالبة بسجل الشركة' : 'Claim my listing'}</Button>}
      </Card>
    </section>
  );
}
// WHAT WENT WRONG AT SIGN-IN, MATCHED ON A CODE (audit 22 Sep 2026, SP-A-03).
//
// login_otp's refusals used to be matched by their ENGLISH SENTENCE. A regex table over prose is a
// contract nobody signed: two of the nineteen sentences the function can answer matched no pattern
// and fell through to "Something went wrong (400)", and any rewording of a server sentence silently
// broke another one. login_otp now returns a stable `code`, and that is what this reads first.
// Every code login_otp can answer with (supabase/functions/login_otp/index.ts, read 22 Sep 2026),
// each pointing at a copy key that already existed. A code missing from here falls through to the
// sentence table and then to the generic line, so adding a code to the function can never make the
// page worse than it was — but it should be added here the same day.
const LOGIN_CODE = {
  // role_conflict: the address is a customer account, told only after the code proved the mailbox (6 Oct 2026).
  role_conflict: 'conflict_customer', role_conflict_phone: 'conflict_customer_phone', limiter_unavailable: 'le_generic',
  rate_limited: 'le_too_many', too_many_attempts: 'le_attempts', code_burned: 'le_attempts',
  bad_identifier: 'le_bad_id', bad_mobile: 'le_bad_id',
  email_suppressed: 'le_suppressed', ambiguous_phone: 'le_ambiguous', sms_signup_refused: 'le_signup_email',
  no_account_for_number: 'le_no_account', sms_signin_unavailable: 'le_sms_off', sms_not_available_for_number: 'le_sms_off',
  email_not_sent: 'err_code_send', sms_send_failed: 'err_code_send',
  enter_code: 'le_enter_code', code_expired: 'le_expired', wrong_code: 'err_incorrect',
  session_failed: 'le_session', verify_failed: 'le_generic', unexpected_error: 'le_generic',
};
// THE LEGACY PATH. Until every deployed login_otp answers with a code, a sentence is still all some
// refusals carry, so these patterns stay as the fallback. They are matched only when `code` is
// absent or unknown, and nothing new should be added here — add a code to LOGIN_CODE instead.
const LOGIN_ERR = [
  [/too many code requests/i, 'le_too_many'], [/valid (email address or uae )?mobile|valid email address/i, 'le_bad_id'],
  [/do-not-send list/i, 'le_suppressed'], [/more than one quotesdone account/i, 'le_ambiguous'],
  [/cannot create an account from a mobile/i, 'le_signup_email'], [/isn't linked|no account is registered/i, 'le_no_account'],
  [/sms (sign-in is not enabled|codes are not available)/i, 'le_sms_off'], [/could not send the (sms|email)/i, 'err_code_send'],
  [/enter the code/i, 'le_enter_code'], [/too many (incorrect )?attempts/i, 'le_attempts'], [/has expired/i, 'le_expired'],
  [/incorrect or expired/i, 'err_incorrect'], [/could not start your session/i, 'le_session'],
];
export const loginErr = (lang, j, fallbackKey) => {
  const code = String((j && j.code) || '');
  if (LOGIN_CODE[code]) return t(lang, LOGIN_CODE[code]);
  const e = String((j && j.error) || '');
  if (!e) return t(lang, fallbackKey);
  const hit = LOGIN_ERR.find(([re]) => re.test(e));
  return hit ? t(lang, hit[1]) : t(lang, 'le_generic') + (j && j._http ? ' (' + j._http + ')' : '');
};
function Login({ onAuth, lang, startMode }) {
  const failover = useFailover();   // WhatsApp sign-in code -> SMS when Twilio reports it undelivered or late
  const [mode, setMode] = useState(startMode === 'signup' ? 'signup' : 'signin'); const [step, setStep] = useState('id'); const [id, setId] = useState(''); const [code, setCode] = useState(''); const [ident, setIdent] = useState(''); const [msg, setMsg] = useState(''); const [busy, setBusy] = useState(false);
  const isSignup = mode === 'signup';
  // claim_lookup resolves after mount, so startMode arrives late and cannot be a useState initial
  // value. Flip to sign-up when the invitation lands, unless the supplier has already chosen a tab
  // themselves — a link that only ever reaches someone without an account should not open on
  // "Welcome back", but it must not override a deliberate choice either.
  const swapped = useRef(false);
  useEffect(() => { if (startMode === 'signup' && !swapped.current) setMode('signup'); }, [startMode]);
  // An empty press says so, and a sign-up address is checked for shape AND for reserved names that
  // can never receive a code (src/lib/signupEmail.ts; audit 21 Sep 2026, items 26 and 28).
  const send = async () => { const v = id.trim(); if (!v) { setMsg(t(lang, isSignup ? 'err_need_email' : 'err_need_id')); return; } if (isSignup) { const p = signupEmailProblem(v); if (p) { setMsg(t(lang, p)); return; } } setBusy(true); setMsg('');
    let j; try { j = await call('login_otp', { action: 'send', user_kind: 'supplier', identifier: v, allow_signup: isSignup, lang }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_code_send')); return; } setBusy(false); if (j && j.ok) { setIdent(j.identifier || v); setStep('code'); if (!v.includes('@')) failover(() => call('login_otp', { action: 'failover', user_kind: 'supplier', identifier: j.identifier || v, lang })); } else setMsg(loginErr(lang, j, 'err_code_send')); };
  const verify = async () => { if (!code.trim()) return; setBusy(true); setMsg(''); let j; try { j = await call('login_otp', { action: 'verify', user_kind: 'supplier', identifier: ident, code: code.trim() }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_incorrect')); return; } if (!j || !j.ok || !j.access_token) { setBusy(false); setMsg(loginErr(lang, j, 'err_incorrect')); return; } setBusy(false); onAuth(j.access_token, j.refresh_token, j.locale); };
  const swap = (m) => { swapped.current = true; setMode(m); setStep('id'); setMsg(''); setCode(''); };
  return (
    <div className={S.center}><Card className="qd-login qd-panel w-full max-w-[410px] p-6 sm:p-7">
      <div className="mb-5 flex flex-col items-center text-center">
        <span className="qd-brandbadge mb-4 grid h-12 w-12 place-items-center rounded-2xl"><BrandMark className="h-6 w-6" /></span>
        <h1 className={cn(S.h1, 'qd-grad-text font-head')}>{isSignup ? t(lang, 'register_title') : t(lang, 'welcome_back')}</h1>
        {/* THE CODE STEP SAYS WHERE THE CODE WENT (28 Oct 2026, sales_engineer, production browser walk at 1366 and 390 px):
            after "Create my account" the subtitle still read "Enter your work email and we'll create your account", and
            nothing on the screen named the address, so a typo could only be found by waiting for a code that never came. */}
        <div className={cn(S.sub, 'mx-auto mt-2')}>{step === 'code' && ident
          ? t(lang, 'code_sent_to').split('{id}').map((part, i) => i === 0 ? part : <Fragment key={i}><bdi dir="ltr" className="font-semibold text-foreground [overflow-wrap:anywhere]">{ident}</bdi>{part}</Fragment>)
          : (isSignup ? t(lang, 'signup_sub') : t(lang, 'signin_sub'))}</div>
      </div>
      <div className={cn(S.tabsWrap, 'mb-4 flex w-full')}><button className={cn(S.tab, 'flex-1', !isSignup && S.tabOn)} onClick={() => swap('signin')}>{t(lang, 'tab_signin')}</button><button className={cn(S.tab, 'flex-1', isSignup && S.tabOn)} onClick={() => swap('signup')}>{t(lang, 'tab_signup')}</button></div>
      {step === 'id' ? (<>
        <Lbl text={isSignup ? t(lang, 'work_email') : t(lang, 'email_or_mobile')}><Input className="mt-3 min-h-11" autoComplete={isSignup ? 'email' : 'username'} dir="ltr" placeholder={isSignup ? t(lang, 'work_email') : t(lang, 'email_or_mobile')} value={id} onChange={(e) => setId(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && send()} /></Lbl>
        <Button className="w-full mt-3" disabled={busy} onClick={send}>{busy ? t(lang, 'sending') : (isSignup ? t(lang, 'create_my_account') : t(lang, 'send_code'))}</Button>
      </>) : (<>
        <Lbl text={t(lang, 'code_placeholder')}><Input className="mt-3 min-h-11" inputMode="numeric" autoComplete="one-time-code" dir="ltr" placeholder={t(lang, 'code_placeholder')} value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && verify()} /></Lbl>
        <div className={S.hint}>{t(lang, 'junk_note')}</div>
        <div className={S.hint} dir="ltr">{t(lang, 'contact_note')}</div>
        <Button className="w-full mt-3" disabled={busy} onClick={verify}>{busy ? t(lang, 'verifying') : (isSignup ? t(lang, 'verify_continue') : t(lang, 'verify_signin'))}</Button>
        <Button variant="link" className="mt-2 px-0 h-auto" onClick={() => { setStep('id'); setCode(''); setMsg(''); }}>{t(lang, 'use_diff')}</Button>
      </>)}
      {msg && <div className={S.err}>{msg}</div>}
    </Card></div>
  );
}
export { InviteBanner, Login };
