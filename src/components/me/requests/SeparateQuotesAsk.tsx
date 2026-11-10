'use client';
// THE CUSTOMER IS ASKED, NEVER SPLIT FOR (sales_engineer; evidence run of 10 Nov 2026, ledger 1604, finding c; standing
// rulings 1021 "for breaking big projects into trades, that should be asked to the customer before proceeding" and 1025
// "the default is one contractor").
// A request sent for one contractor that no single contractor matched yet reached nobody. The matcher does not split it on
// its own: it counts the specialists of its trades who could quote it as separate packages (sales_engineer
// lib/turnkey_miss.ts, routing.separate_offer) and this asks the customer. Only their answer re-posts it per trade, through
// the one posting door: customer_api repeat_inquiry with edits.sourcing = 'multi' -> create_inquiry, which records 'multi'
// on the new request and splits it (the database guard a03_inquiry_split_needs_the_customers_choice accepts no other).
// The first request stays as it is, open for one contractor.
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { t, tf, errText } from '../portalText';

type Lang = 'en' | 'ar' | string;
type Answer = { ok?: boolean; error?: string; message?: string; matches?: number } | null;
type Call = (fn: string, body: Record<string, unknown>, token: string) => Promise<Answer>;

export function SeparateQuotesAsk({ inquiryId, specialists, lang, token, call, onPosted }: {
  inquiryId: string | null; specialists: number; lang: Lang; token: string; call: Call; onPosted?: (j: Answer) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const [done, setDone] = useState(false);
  if (!inquiryId || !(specialists > 0)) return null;
  const choose = async () => {
    if (busy) return;
    setBusy(true); setErr('');
    try {
      const j = await call('customer_api', { action: 'repeat_inquiry', inquiry_id: inquiryId, edits: { sourcing: 'multi' } }, token);
      if (j && j.ok) { setDone(true); if (onPosted) onPosted(j); }
      else setErr(errText(j, lang, 'nr_separate_fail'));
    } catch (_e) { setErr(t(lang, 'nr_separate_fail')); }
    setBusy(false);
  };
  return (
    <div className="mt-3 rounded-xl border border-primary/30 bg-primary/5 p-3" role="note">
      <p className="text-copy leading-relaxed text-foreground">{tf(lang, 'nr_separate_ask', { n: specialists })}</p>
      {done
        ? <p className="mt-2 text-[12.5px] font-semibold text-foreground" role="status">{t(lang, 'nr_separate_done')}</p>
        : <Button size="sm" className="mt-2" disabled={busy} onClick={choose}>{busy ? t(lang, 'nr_sending') : t(lang, 'nr_separate_yes')}</Button>}
      {err ? <p className="mt-2 text-[12.5px] text-destructive" role="alert">{err}</p> : null}
    </div>
  );
}
