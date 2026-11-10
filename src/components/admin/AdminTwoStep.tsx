'use client';
// TWO-STEP ADMIN SIGN-IN (security checklist audit 10 Nov 2026, open item 1; it_engineer).
//
// Step 1 is the sign-in the founder already has: a code to the admin e-mail (login_otp, user_kind 'admin'). That
// session is aal1, and since this change no admin door accepts it (_shared/admin_session.ts answers 403
// `two_step_required`). Step 2 is a 6-digit code from an authenticator app — Supabase Auth TOTP, free on every plan.
//   * no authenticator enrolled yet -> ENROL: a QR code and the setup key, then the first code confirms it;
//   * one enrolled                  -> CHALLENGE: the current code;
// either way the session becomes aal2 and the admin doors open. Phone/SMS factors are never offered: they are a paid
// add-on and the founder ruled on 10 Nov 2026 (ledger 1606) that nothing that costs money is added.
//
// LOCK-OUT SAFETY. Nothing here can lock the founder out: an admin with no factor is sent to enrolment, not refused,
// and a half-finished enrolment (QR shown, never confirmed) is cleared and started again. A lost phone is recovered by
// removing the factor in the Supabase dashboard — docs/runbooks/admin-two-step-sign-in.md — after which this page
// enrols a new one. The internal credential the seats and Claude sessions use is not a JWT and is unaffected.
//
// The session lives under its own storage key, so it never mixes with a customer or supplier session on the same
// browser (the three-key trap of 13 Aug 2026). English only: no customer or supplier ever sees this screen.
import { useCallback, useEffect, useState } from 'react';
import type { Factor } from '@supabase/auth-js';
import { supaClient } from '@/lib/supaClient';
import { SUPA_ANON, fnUrl } from '@/lib/supaEnv';
import { standing, startEnrolment as beginEnrolment, verifyCode, type Enrolment } from '@/lib/adminTwoStep';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Kicker } from '@/components/ui/sealed';

const STORAGE_KEY = 'qd-admin-auth';
const sb = () => supaClient(STORAGE_KEY).auth;
const RUNBOOK = 'docs/runbooks/admin-two-step-sign-in.md';

type Step = 'loading' | 'email' | 'email_code' | 'enrol' | 'challenge' | 'done';

async function loginOtp(body: Record<string, unknown>): Promise<Record<string, unknown>> {
  const r = await fetch(fnUrl('login_otp'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SUPA_ANON },
    body: JSON.stringify({ ...body, user_kind: 'admin', lang: 'en' }),
  });
  try { return await r.json(); } catch { return { ok: false, error: 'bad_response', status: r.status }; }
}

const msgOf = (e: unknown, fallback: string) => {
  const m = e && typeof e === 'object' && 'message' in e ? String((e as { message: unknown }).message || '') : '';
  return m || fallback;
};

export function AdminTwoStep() {
  const [step, setStep] = useState<Step>('loading');
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [msg, setMsg] = useState('');
  const [busy, setBusy] = useState(false);
  const [enrolment, setEnrolment] = useState<Enrolment | null>(null);
  const [factor, setFactor] = useState<Factor | null>(null);
  const [expires, setExpires] = useState<number | null>(null);
  const [copied, setCopied] = useState(false);

  const startEnrolment = useCallback(async () => {
    setBusy(true); setMsg('');
    try { setEnrolment(await beginEnrolment(sb())); }
    catch (e) { setMsg(msgOf(e, 'Enrolment could not start. Reload the page and try again.')); }
    setBusy(false);
  }, []);

  // Where this session stands (src/lib/adminTwoStep.ts): no session -> e-mail; aal2 -> done; a verified factor ->
  // challenge; else enrol, and the QR is prepared as that step opens (a failure offers "Try again").
  const settle = useCallback(async () => {
    const st = await standing(sb());
    setMsg(''); setCode('');
    setFactor(st.factor); setExpires(st.expiresAt); setStep(st.step);
    if (st.step === 'enrol') await startEnrolment();
  }, [startEnrolment]);

  // On mount the persisted session (localStorage, an external system) decides the first step; the state is set after
  // the auth reads resolve, not synchronously.
  // oxlint-disable-next-line react/set-state-in-effect
  useEffect(() => { settle().catch((e) => { setMsg(msgOf(e, 'Sign-in is unavailable right now. Reload the page.')); setStep('email'); }); }, [settle]);

  const sendEmailCode = async () => {
    const v = email.trim();
    if (!v.includes('@')) { setMsg('Enter the admin e-mail address.'); return; }
    setBusy(true); setMsg('');
    const j = await loginOtp({ action: 'send', identifier: v }).catch((): Record<string, unknown> => ({ ok: false }));
    setBusy(false);
    if (j && j.ok) { setEmail(String(j.identifier || v)); setStep('email_code'); }
    else setMsg('The code could not be sent. Check the address and try again.');
  };

  const verifyEmailCode = async () => {
    if (!code.trim()) return;
    setBusy(true); setMsg('');
    const j = await loginOtp({ action: 'verify', identifier: email, code: code.trim() }).catch((): Record<string, unknown> => ({ ok: false }));
    if (!j || !j.ok || !j.access_token) { setBusy(false); setMsg('That code was not accepted. Check it, or send a new one.'); return; }
    const { error } = await sb().setSession({ access_token: String(j.access_token), refresh_token: String(j.refresh_token || '') });
    setBusy(false);
    if (error) { setMsg(msgOf(error, 'The session could not be started.')); return; }
    await settle().catch((e) => setMsg(msgOf(e, 'Could not read this session. Sign in again.')));
  };

  const verifyTotp = async () => {
    const factorId = step === 'enrol' ? enrolment?.factorId : factor?.id;
    if (!factorId) { setMsg('Reload the page and sign in again.'); return; }
    setBusy(true); setMsg('');
    const r = await verifyCode(sb(), factorId, code);
    setBusy(false);
    if (!r.ok) { setMsg(r.reason === 'format' ? 'Enter the 6-digit code from your authenticator app.' : 'That code was not accepted. Codes change every 30 seconds; enter the current one.'); return; }
    setEnrolment(null);
    await settle().catch((e) => setMsg(msgOf(e, 'Could not read this session. Sign in again.')));
  };

  const copyToken = async () => {
    const { data } = await sb().getSession();
    if (!data.session) return;
    try { await navigator.clipboard.writeText(data.session.access_token); setCopied(true); setTimeout(() => setCopied(false), 2500); }
    catch { setMsg('The browser refused the clipboard.'); }
  };

  const signOut = async () => { await sb().signOut(); setFactor(null); setEnrolment(null); setStep('email'); };

  const codeInput = (onEnter: () => void, label: string) => (
    <Input className="mt-5 h-12 text-center font-mono text-[18px] tracking-[0.3em]" aria-label={label} inputMode="numeric"
      autoComplete="one-time-code" placeholder="000000" value={code} onChange={(e) => setCode(e.target.value)}
      onKeyDown={(e) => { if (e.key === 'Enter') onEnter(); }} />
  );

  return (
    <div lang="en" dir="ltr" className="mx-auto grid w-full max-w-[1080px] items-center gap-10 px-4 py-10 sm:px-5 md:min-h-[76vh] md:grid-cols-[1.05fr_minmax(380px,420px)] md:py-16">
      <div className="hidden md:block">
        <Kicker>Administrators</Kicker>
        <h2 className="mt-5 font-head text-h2 text-foreground">Two-step sign-in</h2>
        <p className="mt-4 max-w-[46ch] text-lead text-muted-foreground">
          Admin actions need two things: a code sent to the admin e-mail, and the 6-digit code from an authenticator app on
          your phone. Whoever reads the mailbox alone cannot act as admin.
        </p>
        <ol className="mt-8 flex flex-col divide-y divide-border border-y border-border">
          {['Sign in with the code sent to your admin e-mail.', 'First time: scan the QR code with an authenticator app (Google Authenticator, Microsoft Authenticator, 1Password).', 'Enter the 6-digit code it shows. Admin actions open for this session.'].map((t, i) => (
            <li key={i} className="flex items-start gap-4 py-3.5">
              <span className="tabular mt-0.5 w-6 shrink-0 font-mono text-label text-primary">{String(i + 1).padStart(2, '0')}</span>
              <span className="text-copy leading-relaxed text-foreground/90">{t}</span>
            </li>
          ))}
        </ol>
      </div>
      <div className="w-full justify-self-center md:justify-self-end">
        <Card className="relative w-full overflow-hidden p-6 shadow-e3 sm:p-8">
          <span aria-hidden className="absolute inset-x-10 top-0 h-px bg-linear-to-r from-transparent via-primary/80 to-transparent" />
          <div className="mb-5 md:hidden"><Kicker>Administrators</Kicker></div>

          {step === 'loading' && <output className="block text-copy text-muted-foreground">Checking this session…</output>}

          {step === 'email' && (<>
            <h1 className="font-head text-[22px] font-semibold tracking-snug text-foreground">Admin sign-in</h1>
            <p className="mt-1.5 text-[13px] leading-relaxed text-muted-foreground">Step 1 of 2: a code to your admin e-mail.</p>
            <Input className="mt-5 h-12 text-copy" aria-label="Admin e-mail" autoComplete="username" type="email" placeholder="Admin e-mail"
              value={email} onChange={(e) => setEmail(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') sendEmailCode(); }} />
            <Button size="lg" className="mt-3 w-full" disabled={busy} onClick={sendEmailCode}>{busy ? 'Sending…' : 'Send code'}</Button>
          </>)}

          {step === 'email_code' && (<>
            <h1 className="font-head text-[22px] font-semibold tracking-snug text-foreground">Check your e-mail</h1>
            <p className="mt-1.5 text-[13px] leading-relaxed text-muted-foreground">Step 1 of 2: enter the code sent to {email}. If it is not in the inbox, look in junk.</p>
            {codeInput(verifyEmailCode, 'E-mail code')}
            <div className="mt-3 flex flex-col items-start gap-2">
              <Button size="lg" className="w-full" disabled={busy} onClick={verifyEmailCode}>{busy ? 'Checking…' : 'Continue'}</Button>
              <Button variant="link" className="h-auto px-0" onClick={() => { setStep('email'); setCode(''); setMsg(''); }}>Use a different address</Button>
            </div>
          </>)}

          {step === 'enrol' && (<>
            <h1 className="font-head text-[22px] font-semibold tracking-snug text-foreground">Set up your authenticator</h1>
            <p className="mt-1.5 text-[13px] leading-relaxed text-muted-foreground">
              Step 2 of 2, first time only. Scan this QR code with an authenticator app, then enter the 6-digit code it shows.
            </p>
            {enrolment ? (<>
              {/* The QR is an SVG data URL from Supabase Auth; CSP img-src already allows data:. */}
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={enrolment.qr} alt="QR code for your authenticator app" width={184} height={184} className="mx-auto mt-5 rounded-md bg-white p-2" />
              <p className="mt-3 text-xs leading-relaxed text-muted-foreground">Cannot scan? Enter this setup key in the app instead:</p>
              <code className="mt-1 block break-all rounded-md border border-border bg-secondary/40 px-3 py-2 font-mono text-[13px] text-foreground">{enrolment.secret}</code>
              {codeInput(verifyTotp, 'Authenticator code')}
              <Button size="lg" className="mt-3 w-full" disabled={busy} onClick={verifyTotp}>{busy ? 'Checking…' : 'Confirm and finish'}</Button>
            </>) : <output className="mt-5 block text-copy text-muted-foreground">{busy ? 'Preparing your QR code…' : ''}</output>}
            {!enrolment && !busy && msg && <Button variant="secondary" className="mt-3 w-full" onClick={startEnrolment}>Try again</Button>}
          </>)}

          {step === 'challenge' && (<>
            <h1 className="font-head text-[22px] font-semibold tracking-snug text-foreground">Authenticator code</h1>
            <p className="mt-1.5 text-[13px] leading-relaxed text-muted-foreground">Step 2 of 2: enter the 6-digit code from your authenticator app{factor?.friendly_name ? ` (${factor.friendly_name})` : ''}.</p>
            {codeInput(verifyTotp, 'Authenticator code')}
            <Button size="lg" className="mt-3 w-full" disabled={busy} onClick={verifyTotp}>{busy ? 'Checking…' : 'Verify'}</Button>
            <p className="mt-4 text-xs leading-relaxed text-muted-foreground">
              Lost the phone with your authenticator? The release operator removes the old authenticator from your account in the
              Supabase dashboard (the steps are in {RUNBOOK}); you then sign in here and set up a new one.
            </p>
          </>)}

          {step === 'done' && (<>
            <h1 className="font-head text-[22px] font-semibold tracking-snug text-foreground">Two-step sign-in complete</h1>
            <p className="mt-1.5 text-[13px] leading-relaxed text-muted-foreground">
              This session has passed both steps, so the admin functions accept it. It renews itself while this tab is open
              {expires ? `; the current token is valid until ${new Date(expires * 1000).toLocaleTimeString()}` : ''}.
            </p>
            <div className="mt-5 flex flex-col gap-2">
              <Button variant="secondary" className="w-full" onClick={copyToken}>{copied ? 'Copied' : 'Copy access token for an admin call'}</Button>
              <Button variant="outline" className="w-full" onClick={signOut}>Sign out</Button>
            </div>
          </>)}

          {msg && <div className="mt-2 text-[13px] text-danger-fg" role="alert">{msg}</div>}
        </Card>
      </div>
    </div>
  );
}
