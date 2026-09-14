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
import { Link } from '@/i18n/routing';
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
    // fee is null on the refund policy page: there is no quote there, so no amount is invented.
    { icon: CreditCard, text: fee == null ? t(lang, 'g_step_paid_any') : tf(lang, 'g_step_paid', { fee }) },
    { icon: Mail, text: tf(lang, 'g_step_chase', { c }) },
    { icon: Gavel, text: tf(lang, 'g_step_final', { w }) },
    ...(bmin && bmax ? [{ icon: Landmark, text: tf(lang, 'g_step_bank', { bmin, bmax }) }] : []),
  ];
  const pct = clock ? Math.round((clock.day / clock.of) * 100) : 0;
  const phaseText = clock && ({ waiting: t(lang, 'g_ph_waiting'), chased: t(lang, 'g_ph_chased'), final_call: t(lang, 'g_ph_final'), acknowledged: t(lang, 'g_ph_ack'), refund: tf(lang, 'g_ph_refund', { status: facts.refund_status }) })[clock.phase];
  return (
    <section className={cn('qd-panel overflow-hidden', compact ? 'p-4' : 'p-5')} aria-label={t(lang, 'g_title')}>
      <div className="flex items-start gap-3">
        <span className="grid h-9 w-9 shrink-0 place-items-center rounded-panel border border-primary/30 bg-primary/10 text-primary"><ShieldCheck className="h-4 w-4" aria-hidden /></span>
        <div className="min-w-0">
          <h3 className="font-head text-[15px] font-semibold tracking-snug text-foreground">{t(lang, 'g_title')}</h3>
          <p className="mt-0.5 text-small leading-relaxed text-muted-foreground">{t(lang, 'g_sub')}</p>
        </div>
      </div>

      {clock && (
        <div className="mt-4 rounded-card border border-border bg-secondary/30 px-3.5 py-3">
          <div className="flex items-baseline justify-between gap-2">
            <b className="tabular font-mono text-[12.5px] text-foreground">{clock.elapsed === 0 ? t(lang, 'g_day0') : tf(lang, 'g_day', { d: clock.day, w: clock.of })}</b>
            <span className="text-small text-muted-foreground">{phaseText}</span>
          </div>
          <div className="qd-meter mt-2" role="progressbar" aria-valuemin={0} aria-valuemax={clock.of} aria-valuenow={clock.day} aria-label={t(lang, 'g_title')}>
            <motion.span className={cn(clock.phase === 'final_call' || clock.phase === 'refund' ? '!bg-none !bg-warn' : '')}
              initial={reduce ? false : { width: 0 }} animate={{ width: Math.max(pct, 4) + '%' }} transition={{ duration: reduce ? 0 : 0.9, ease: [0.2, 0.8, 0.2, 1] }} />
          </div>
        </div>
      )}

      {/* The kit Stepper's markup (done gold / current teal / next quiet) on theme tokens, so the
          light portal keeps its contrast; the kit component itself paints text-white. */}
      <ol className="qd-stagger reveal-stagger relative mt-5 flex flex-col gap-4">
        <span className="qd-step-line" aria-hidden />
        {steps.map((s, i) => {
          const done = reached > i; const current = reached === i;
          const Icon = s.icon;
          return (
            <li key={i} className="relative flex items-start gap-3.5">
              <span className={cn('relative z-10 grid h-8 w-8 shrink-0 place-items-center rounded-full border',
                done ? 'border-accent/60 bg-accent/15 text-accent'
                  : current ? 'border-primary bg-primary/15 text-primary shadow-glow-teal'
                  : 'border-border bg-card text-muted-foreground')}>
                <Icon className="h-3.5 w-3.5" aria-hidden />
              </span>
              <span className="min-w-0 pt-1.5">
                <span className="block font-mono text-label uppercase tracking-caps text-muted-foreground/80">{String(i + 1).padStart(2, '0')}</span>
                <span className={cn('block text-small leading-relaxed', done || current ? 'text-foreground' : 'text-muted-foreground')}>{s.text}</span>
              </span>
            </li>
          );
        })}
      </ol>
      <p className="mt-4 border-t border-border pt-3 text-[11px] text-muted-foreground/80">{t(lang, 'g_workdays')}{' '}
        <Link href="/how-we-verify" className="font-semibold text-primary underline-offset-2 hover:underline">{t(lang, 'g_verify')}</Link></p>
    </section>
  );
}
