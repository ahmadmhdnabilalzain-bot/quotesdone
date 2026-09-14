// @ts-nocheck
'use client';
// THE REVEAL GUARANTEE, SHOWN WHERE THE MONEY IS.
//
// The refund promise was a sentence under the Reveal button. Website audit 14 Sep 2026 (trust,
// weeks): show it as the ladder it is, at the moment of payment and again on the revealed job with
// the clock running on the customer's own reveal. Every number is served, never typed here:
// guarantee_terms comes from pricing_config (5 / 3 / 7-14 on 14 Sep) and the clock from the
// customer's own transactions row, counted by workingDays.ts. A term the server did not send hides
// its step rather than inventing one. Refunds are decided by the chief executive seat.
import { motion, useReducedMotion } from 'motion/react';
import { ShieldCheck, Mail, Gavel, Landmark, CreditCard } from 'lucide-react';
import { cn } from '@/lib/utils';
import { t, tf } from './portalText';
import { guaranteeClock } from './workingDays';

export function RevealGuarantee({ lang, fee, terms, facts = null, compact = false }) {
  const reduce = useReducedMotion();
  const w = terms && terms.window_days, c = terms && terms.chase_after_days;
  const bmin = terms && terms.bank_min_days, bmax = terms && terms.bank_max_days;
  if (!w || !c) return null;
  const clock = facts ? guaranteeClock(facts, terms) : null;
  // Which rung the job has reached: 0 paid, 1 chase, 2 final call, 3 refund in motion.
  const reached = !clock ? -1 : clock.phase === 'refund' ? 3 : clock.phase === 'final_call' ? 2 : clock.phase === 'chased' ? 1 : 0;
  const steps = [
    { icon: CreditCard, text: tf(lang, 'g_step_paid', { fee }) },
    { icon: Mail, text: tf(lang, 'g_step_chase', { c }) },
    { icon: Gavel, text: tf(lang, 'g_step_final', { w }) },
    ...(bmin && bmax ? [{ icon: Landmark, text: tf(lang, 'g_step_bank', { bmin, bmax }) }] : []),
  ];
  const pct = clock ? Math.round((clock.day / clock.of) * 100) : 0;
  const phaseText = clock && ({ waiting: t(lang, 'g_ph_waiting'), chased: t(lang, 'g_ph_chased'), final_call: t(lang, 'g_ph_final'), acknowledged: t(lang, 'g_ph_ack'), refund: tf(lang, 'g_ph_refund', { status: facts.refund_status }) })[clock.phase];
  return (
    <section className={cn('qd-panel overflow-hidden p-4', compact && 'p-3.5')} aria-label={t(lang, 'g_title')}>
      <div className="flex items-start gap-3">
        <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-primary/15 text-primary"><ShieldCheck className="h-4 w-4" aria-hidden /></span>
        <div className="min-w-0">
          <h3 className="font-head text-[14px] font-bold text-foreground">{t(lang, 'g_title')}</h3>
          <p className="text-[12.5px] leading-relaxed text-muted-foreground">{t(lang, 'g_sub')}</p>
        </div>
      </div>

      {clock && (
        <div className="mt-3.5">
          <div className="flex items-baseline justify-between gap-2 text-[12.5px]">
            <b className="text-foreground tabular-nums">{clock.elapsed === 0 ? t(lang, 'g_day0') : tf(lang, 'g_day', { d: clock.day, w: clock.of })}</b>
            <span className="text-muted-foreground">{phaseText}</span>
          </div>
          <div className="mt-2 h-2 overflow-hidden rounded-full bg-secondary/70" role="progressbar" aria-valuemin={0} aria-valuemax={clock.of} aria-valuenow={clock.day} aria-label={t(lang, 'g_title')}>
            <motion.div className={cn('h-full rounded-full', clock.phase === 'acknowledged' ? 'bg-primary' : clock.phase === 'final_call' || clock.phase === 'refund' ? 'bg-amber-400' : 'bg-primary')}
              initial={reduce ? false : { width: 0 }} animate={{ width: Math.max(pct, 4) + '%' }} transition={{ duration: reduce ? 0 : 0.9, ease: [0.2, 0.8, 0.2, 1] }} />
          </div>
        </div>
      )}

      <ol className="relative mt-4 space-y-3 ps-1">
        <span aria-hidden className="absolute inset-y-2 start-[15px] w-px bg-border" />
        {steps.map((s, i) => {
          const done = reached >= i; const current = reached === i;
          const Icon = s.icon;
          return (
            <motion.li key={i} className="relative flex items-start gap-3"
              initial={reduce ? false : { opacity: 0, x: lang === 'ar' ? 8 : -8 }} animate={{ opacity: 1, x: 0 }}
              transition={{ duration: reduce ? 0 : 0.3, delay: reduce ? 0 : 0.06 * i }}>
              <span className={cn('relative z-[1] grid h-[30px] w-[30px] shrink-0 place-items-center rounded-full border',
                done ? 'border-primary/50 bg-primary/15 text-primary' : 'border-border bg-card text-muted-foreground',
                current && 'ring-2 ring-primary/35 motion-safe:animate-pulse')}>
                <Icon className="h-3.5 w-3.5" aria-hidden />
              </span>
              <span className={cn('min-w-0 pt-1 text-[12.5px] leading-relaxed', done ? 'text-foreground' : 'text-muted-foreground')}>{s.text}</span>
            </motion.li>
          );
        })}
      </ol>
      <p className="mt-3 text-[11px] text-muted-foreground/80">{t(lang, 'g_workdays')}</p>
    </section>
  );
}
