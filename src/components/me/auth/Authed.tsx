// @ts-nocheck
'use client';
import { useEffect, useState, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { take } from '../prefetch';
import { t, transportFailed } from '../portalText';
import { SB, tokenAlive, call, warmDashboard } from '../api';
import { S } from '../styles';
import { ProfileGate } from './ProfileGate';
import { Dashboard } from '../dashboard/Dashboard';

function Authed({ token, lang, strip, theme, onSwapTheme, onSetLang, onSignOut, onServedLocale }) {
  const [k, setK] = useState(null); const [err, setErr] = useState('');
  // A 401 IS A QUESTION BEFORE IT IS A VERDICT. The stored access token can be an hour old — the
  // page may have been restored from localStorage long after it was minted — and the refresh token
  // beside it is still good. Ask for a new session ONCE before telling somebody their session has
  // expired; the auth listener in CustomerPortal picks the new token up from there. If the refresh
  // also fails, the session really is over and the message is true.
  // A LOAD THAT RESOLVES AFTER ITS TOKEN IS GONE MUST NOT WRITE STATE. The first kyc read is now a
  // promise started at HTML-parse time (BootPrefetch.tsx), so it can be in flight far longer than
  // the same-tick fetch it replaced — long enough for Supabase's own refresh to hand the component
  // a new token and start a newer load. The effect below clears this ref on cleanup, so only the
  // live invocation sets k/err and an older answer is dropped instead of overwriting a fresher one.
  const alive = useRef(true);
  const load = (retried) => {
    setErr('');
    take(token, 'kyc', () => call('kyc', { action: 'state' }, token)).then(async (j) => {
      if (!alive.current) return;
      // A warmed (boot-prefetch) answer that failed in transit is asked once more, fresh (call() itself retries a read),
      // before the customer sees "Couldn't load your account".
      if (transportFailed(j)) { j = await call('kyc', { action: 'state' }, token); if (!alive.current) return; }
      if (j && j.error === 'unauthorized') {
        if (retried) { setErr('unauth'); return; }
        try {
          const rt = localStorage.getItem('qd-cust-refresh') || '';
          const { data } = await SB().auth.refreshSession(rt ? { refresh_token: rt } : undefined);
          if (data && data.session && data.session.access_token) return; // the listener re-renders with the new token
        } catch (_e) {}
        setErr('unauth');
        return;
      }
      if (transportFailed(j)) { setErr('net'); return; }
      setK(j || {});
    }).catch(() => { if (alive.current) setErr('net'); });
  };
  // DO NOT ASK AN AUTHENTICATED ENDPOINT WHO WE ARE BEFORE WE HAVE A TOKEN. This ran on the first
  // render, when `token` is still '' because it is read from localStorage and from
  // SB().auth.getSession() inside an effect that has not resolved yet. Measured on a signed-in
  // customer: two 401s against /kyc in the console on every load, before the real call succeeded.
  // Wrong in three ways - it spends a round trip per mount, it puts a red error in the console of
  // a working page so a real one is easy to miss, and it burns the one refresh attempt the
  // `retried` flag exists to protect. The effect re-runs when the token arrives, so waiting is free.
  // Wait for a token, and for a token that has not already expired. SB.auth refreshes on its own
  // and the auth listener re-renders with the new one, so this costs nothing but the 401.
  useEffect(() => {
    alive.current = true;
    if (tokenAlive(token)) { warmDashboard(token, lang); load(); }
    return () => { alive.current = false; };
  }, [token]);
  if (err === 'unauth') return <>{strip}<div className={S.center}><Card className="w-full max-w-[400px] p-5"><div className={S.sub}>{t(lang, 'session_expired')}</div><Button className="w-full mt-3" onClick={onSignOut}>{t(lang, 'tab_signin')}</Button></Card></div></>;
  if (err) return <>{strip}<div className={S.center}><Card className="w-full max-w-[400px] p-5"><div className={S.sub}>{t(lang, 'load_failed')}</div>{/* () => load(), not load: a click handler passes the MouseEvent as the first argument, which
        would arrive as `retried` and skip the one refresh attempt this retry exists to make. */}
    <Button className="w-full mt-3" onClick={() => load()}>{t(lang, 'retry')}</Button></Card></div></>;
  if (!k) return <>{strip}<div className={S.center}>{t(lang, 'loading')}</div></>;
  const complete = k.full_name && k.dob && k.phone_verified && k.email_verified && k.terms_signed;
  if (!complete) return <>{strip}<main id="main"><ProfileGate token={token} lang={lang} theme={theme} onDone={() => load()} /></main></>;
  // kyc={k}: the state this component already fetched carries `whatsapp`, so the dashboard's one-time
  // question needs no second round trip.
  return <Dashboard token={token} lang={lang} theme={theme} onSwapTheme={onSwapTheme} onSetLang={onSetLang} onSignOut={onSignOut} onServedLocale={onServedLocale} kyc={k} />;
}
export { Authed };
