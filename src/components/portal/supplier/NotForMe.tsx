'use client';
// "NOT FOR ME" AND THE UNANSWERED COUNT (sales_engineer, 16 Nov 2026; holes SUPPLIER 2, OPERATIONS H8). Before this a supplier had
// no way to say a request was not his: the FAQ told him to ignore it, and three ignored requests stopped his work without a word.
//   * NotForMe: one tap, an optional reason in his own words (the weekly review's model reads it), then, when the request's trade is
//     his and not his last, one more tap to stop receiving that trade. The tap is his confirmation (supplier_api not_for_me.ts).
//   * UnansweredNote: his count of unanswered requests that reached him, what it means and "I'm available" (supplier_api standing,
//     say_available). Shown only when the count is above zero.
// English only, whatever the page's language: a supplier is never given Arabic (founder ruling 1008;
// scripts/checks/nothing_a_supplier_reads_can_be_arabic.test.mjs).
import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { call } from './api';
import type { Lang } from './quoteReviewApi';

const COPY = {
  en: {
    notForMe: 'Not for me', why: 'Why? (optional: it helps us send you the right requests)', send: 'Send', cancel: 'Cancel', sending: 'Sending…',
    done: 'Noted: this request is not for you. It never counts against you.', declined: 'You said this request is not for you.',
    stop: (t: string) => `Stop sending me ${t} requests`, stopped: (t: string) => `Done: you will not receive ${t} requests any more. You can add it back under Services.`,
    err: 'That did not go through. Please try again.',
    note: (n: number, limit: number) => `${n} of ${limit} requests sent to you went unanswered. At ${limit} in a row we pause new requests to you.`,
    paused: (limit: number) => `${limit} requests in a row went unanswered, so new requests to you are paused.`,
    how: 'Press “Not for me” on requests that are not yours (that never counts), or tell us you are available.',
    available: 'I’m available', cleared: 'Thank you. Your count is back to zero and new requests will reach you.',
  },
};

export function NotForMe({ token, lang, inquiryId, declined = false, onDone }: { token: string; lang: Lang; inquiryId: string; declined?: boolean; onDone?: () => void }) {
  const t = COPY.en; void lang;
  const [stage, setStage] = useState<'idle' | 'asking' | 'sending' | 'done'>(declined ? 'done' : 'idle');
  const [reason, setReason] = useState('');
  const [offer, setOffer] = useState<{ trades: string[]; label: string } | null>(null);
  const [stopped, setStopped] = useState('');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  // busy-exempt: the stage 'sending' is this press's busy state: Send is disabled and reads t.sending until the answer
  const decline = async () => {
    setStage('sending'); setErr('');
    const j = await call('supplier_api', { action: 'decline_request', inquiry_id: inquiryId, reason: reason.trim() || null }, token);
    if (!j?.ok) { setStage('asking'); setErr(j?.code === 'already_quoted' && j?.error ? String(j.error) : t.err); return; }
    setOffer(j.offer ?? null); setStage('done'); onDone?.();
  };
  const stop = async () => {
    if (!offer || busy) return;
    setErr(''); setBusy(true);
    const j = await call('supplier_api', { action: 'remove_work', trades: offer.trades, from_decline: true, inquiry_id: inquiryId, reason: reason.trim() || null }, token).finally(() => setBusy(false));
    if (!j?.ok) { setErr(j?.error ? String(j.error) : t.err); return; }
    setStopped(offer.label); setOffer(null);
  };
  if (stage === 'done') {
    return (
      <div className="mt-4 space-y-2" role="status">
        <p className="text-[13px] text-foreground">{declined && !offer && !stopped ? t.declined : t.done}</p>
        {offer ? <Button variant="ghost" onClick={stop} disabled={busy} aria-busy={busy}>{t.stop(offer.label)}</Button> : null}
        {stopped ? <p className="text-[13px] text-foreground">{t.stopped(stopped)}</p> : null}
        {err ? <p role="alert" className="text-[12.5px] text-danger-fg">{err}</p> : null}
      </div>
    );
  }
  if (stage === 'idle') return <div className="mt-3"><Button variant="ghost" onClick={() => setStage('asking')}>{t.notForMe}</Button></div>;
  return (
    <div className="mt-3 max-w-[60ch] space-y-2">
      <label className="block text-[12.5px] text-muted-foreground" htmlFor={'qd-nfm-' + inquiryId}>{t.why}</label>
      <textarea id={'qd-nfm-' + inquiryId} dir="auto" rows={2} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)}
        className="w-full rounded-md border border-input bg-card px-3 py-2 text-sm text-foreground outline-hidden focus-visible:ring-1 focus-visible:ring-ring pointer-coarse:text-[16px]" />
      <div className="flex flex-wrap gap-2">
        <Button onClick={decline} disabled={stage === 'sending'}>{stage === 'sending' ? t.sending : t.send}</Button>
        <Button variant="ghost" onClick={() => { setStage('idle'); setErr(''); }}>{t.cancel}</Button>
      </div>
      {err ? <p role="alert" className="text-[12.5px] text-danger-fg">{err}</p> : null}
    </div>
  );
}

export function UnansweredNote({ token, lang }: { token: string; lang: Lang }) {
  const t = COPY.en; void lang;
  const [s, setS] = useState<{ strikes: number; strike_limit: number } | null>(null);
  const [msg, setMsg] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let on = true;
    call('supplier_api', { action: 'standing' }, token).then((j) => { if (on && j?.ok && j.standing) setS({ strikes: Number(j.standing.strikes) || 0, strike_limit: Number(j.standing.strike_limit) || 3 }); });
    return () => { on = false; };
  }, [token]);
  if (msg) return <p role="status" className="qd-panel mb-3 p-4 text-[13px] text-foreground">{msg}</p>;
  if (!s || s.strikes <= 0) return null;
  const available = async () => { setBusy(true); const j = await call('supplier_api', { action: 'say_available' }, token).finally(() => setBusy(false)); setMsg(j?.ok ? t.cleared : t.err); };
  return (
    <div role="status" className="qd-panel mb-3 space-y-2 p-4">
      <p className="text-[13px] text-foreground">{s.strikes >= s.strike_limit ? t.paused(s.strike_limit) : t.note(s.strikes, s.strike_limit)}</p>
      <p className="text-[12.5px] text-muted-foreground">{t.how}</p>
      <Button onClick={available} disabled={busy} aria-busy={busy}>{t.available}</Button>
    </div>
  );
}
