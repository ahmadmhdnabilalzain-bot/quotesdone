// @ts-nocheck
'use client';
// NO SUPPLIER COULD QUOTE THE EXACT SPEC — ASK THE CUSTOMER (founder ruling, 14 Sep 2026).
//
// customer_api my_inquiries serves each open offer on inq.spec_offers; one tap answers it through
// customer_api spec_offer_reply ({ offer_id, choice: option_id | 'no' }). Only the fields below are
// rendered — never a quote label or a supplier name — so the question cannot leak who offered what.
import { useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { ListChecks } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { t, tf, errText } from './portalText';
import { countPhrase } from '@/lib/countedNoun';

const fmtDate = (s, lang) => { const d = new Date(s); return isNaN(d.getTime()) ? String(s || '') : d.toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'long', year: 'numeric' }); };

export function SpecOffer({ inq, token, lang, call, onDone }) {
  const reduce = useReducedMotion();
  const [busy, setBusy] = useState(null); const [done, setDone] = useState({}); const [err, setErr] = useState({});
  const offers = inq.spec_offers || [];
  if (!offers.length) return null;

  const reply = async (o, choice, value) => {
    if (busy || done[o.id]) return;
    setBusy(o.id); setErr((e) => ({ ...e, [o.id]: '' }));
    const j = await call('customer_api', { action: 'spec_offer_reply', offer_id: o.id, choice }, token).catch(() => null);
    setBusy(null);
    if (j && j.ok) {
      setDone((d) => ({ ...d, [o.id]: j.state === 'accepted' ? tf(lang, 'so_accepted', { v: value }) : t(lang, 'so_declined') }));
      onDone && onDone();
    } else setErr((e) => ({ ...e, [o.id]: errText(j, lang) }));
  };

  return (
    <section className="qd-panel p-4 sm:p-5" onClick={(e) => e.stopPropagation()} aria-label={t(lang, 'so_title')}>
      <h3 className="flex items-center gap-2 font-head text-[15px] font-semibold tracking-snug text-foreground"><ListChecks className="h-4 w-4 text-primary" aria-hidden />{t(lang, 'so_title')}</h3>
      <p className="mt-1 text-small leading-relaxed text-muted-foreground">{t(lang, 'so_body')}</p>
      <div className="mt-3 flex flex-col gap-2.5">
        <AnimatePresence initial={false}>
          {offers.map((o) => {
            const locked = busy === o.id || !!done[o.id];
            return (
              <motion.div key={o.id} layout={!reduce} initial={reduce ? false : { opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }}
                className={cn('rounded-card border bg-secondary/20 p-3', done[o.id] ? 'border-border' : 'border-warn/40')}>
                <div className="font-mono text-label uppercase tracking-caps text-primary">{tf(lang, 'so_line', { n: o.line_no })} · {lang === 'ar' ? (o.label_ar || o.label_en) : o.label_en}</div>
                <p className="mt-0.5 text-[13px] font-medium text-foreground">{o.item}</p>
                <p className="mt-0.5 text-[13px] text-muted-foreground">{tf(lang, 'so_asked', { v: o.requested })}</p>
                <div className="mt-2 flex flex-wrap gap-2">
                  {(o.alternatives || []).map((a) => (
                    <Button key={a.option_id} size="sm" variant="outline" disabled={locked} className="h-auto flex-col items-start py-1.5 text-start"
                      onClick={() => reply(o, a.option_id, a.value)}>
                      <span>{tf(lang, 'so_yes', { v: a.value })}</span>
                      <span className="text-[11.5px] font-normal text-muted-foreground">{countPhrase(lang, a.suppliers, 'supplier')}</span>
                    </Button>
                  ))}
                  <Button size="sm" variant="ghost" disabled={locked} onClick={() => reply(o, 'no', '')}>{t(lang, 'so_no')}</Button>
                </div>
                {busy === o.id ? <p className="mt-2 text-[12px] text-muted-foreground">{t(lang, 'so_sending')}</p>
                  : done[o.id] ? <p className="mt-2 text-[12.5px] text-primary" role="status">{done[o.id]}</p>
                  : o.reply_by ? <p className="mt-2 text-[12px] text-muted-foreground">{tf(lang, 'so_by', { d: fmtDate(o.reply_by, lang) })}</p> : null}
                {err[o.id] ? <div className="mt-2 text-[12.5px] text-danger" role="alert">{err[o.id]}</div> : null}
              </motion.div>
            );
          })}
        </AnimatePresence>
      </div>
    </section>
  );
}
