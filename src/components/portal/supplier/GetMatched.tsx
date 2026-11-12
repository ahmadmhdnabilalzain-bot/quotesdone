'use client';
// GET MATCHED — the supplier's one journey, drawn from the eligibility payload (14 Sep 2026).
//
// The dashboard used to open on 24 equal tabs; the one thing each supplier must do next sat in a
// panel under the alerts. supplier_portal's eligibility action already evaluates every real clause
// (the mandatory six from _shared/supplier_registration.ts, the scope gate fn_match_capability opens
// with, and the pauses fn_is_matchable honours), so this screen is that payload drawn as a
// progress ring and an ordered checklist, with the next step as the one primary button.
// Every step and its count come from the server; nothing here is estimated.
import { useEffect, useState } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Kicker, Stepper } from '@/components/ui/sealed';
import { cn } from '@/lib/utils';
import { call } from './api';
import { itemCopy, srvText } from './serverCopy';

type Lang = 'en' | 'ar' | string;
const SERVICES_STEP = 'Confirm your services';
type Step = { code: string; label: string; done: boolean; fix: string };
const EASE = [0.16, 1, 0.3, 1] as const;

function Ring({ done, total, lang }: { done: number; total: number; lang: Lang }) {
  const reduce = useReducedMotion();
  const R = 44, C = 2 * Math.PI * R;
  const frac = total ? done / total : 0;
  return (
    <div className="relative h-beat w-beat shrink-0" role="img"
      aria-label={lang === 'ar' ? `اكتملت ${done} من ${total} خطوات` : `${done} of ${total} steps complete`}>
      <svg viewBox="0 0 100 100" className="h-full w-full -rotate-90">
        <defs>
          <linearGradient id="qd-ring" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="rgb(45,212,191)" /><stop offset="100%" stopColor="rgb(214,178,94)" />
          </linearGradient>
        </defs>
        <circle cx="50" cy="50" r={R} fill="none" stroke="rgba(255,255,255,.08)" strokeWidth="8" />
        <motion.circle cx="50" cy="50" r={R} fill="none" stroke="url(#qd-ring)" strokeWidth="8" strokeLinecap="round"
          strokeDasharray={C}
          initial={reduce ? false : { strokeDashoffset: C }}
          animate={{ strokeDashoffset: C * (1 - frac) }}
          transition={{ duration: 1.1, ease: EASE }}
          style={{ filter: 'drop-shadow(0 0 6px rgba(45,212,191,.35))' }} />
      </svg>
      <div className="absolute inset-0 grid place-items-center text-center">
        <div>
          <div className="font-head text-[26px] font-extrabold leading-none text-foreground tabular-nums">{done}<span className="text-[15px] text-muted-foreground">/{total}</span></div>
          <div className="mt-1 text-[10.5px] font-semibold uppercase tracking-widest text-muted-foreground">{lang === 'ar' ? 'خطوات' : 'steps'}</div>
        </div>
      </div>
    </div>
  );
}

// `initial` is the eligibility payload the dashboard call already carries (supplier_portal `dashboard`,
// 15 Sep 2026); with it the panel renders at once and asks nothing. Without it, it asks for itself.
export default function GetMatched({ token, lang, go, initial = null }: { token: string; lang: Lang; go: (where: string) => void; initial?: any }) {
  const ar = lang === 'ar';
  const [e, setE] = useState<any>(initial);
  const [err, setErr] = useState(false);
  useEffect(() => { if (initial) setE(initial); }, [initial]);
  useEffect(() => {
    if (initial) return;
    let live = true;
    call('supplier_portal', { action: 'eligibility' }, token)
      .then((j) => { if (!live) return; if (j && j.ok) setE(j); else setErr(true); })
      .catch(() => live && setErr(true));
    return () => { live = false; };
  }, [token, initial]);
  if (err) return null;
  if (!e) return <div className="qd-panel mb-4 h-[180px] animate-pulse motion-reduce:animate-none" aria-busy="true" />;

  const blocking: any[] = e.blocking || [];
  const improving: any[] = e.improving || [];
  const reg: any[] = Array.isArray(e.required_to_register) ? e.required_to_register : [];
  const scopeOpen = blocking.some((b) => b.code === 'scope_unconfirmed');
  const steps: Step[] = [
    ...reg.map((r) => ({ code: r.code, label: srvText(lang, r.code, {}, r.code), done: !!r.done, fix: r.fix })),
    // ONE NAME FOR THE ONE STEP LEFT (12 Nov 2026, customer_support; founder ruling 1645, browser walk findings H9 and M12): it was
    // "Confirm your scope" here, "Confirm my scope" on its button, "Confirm the services you offer" on the profile score and "confirmed
    // what your company does" in the header. It is "Confirm your services" everywhere, and it opens the Services tab where he does it.
    // English only: suppliers read English (ruling 1008).
    { code: 'scope', label: SERVICES_STEP, done: !scopeOpen, fix: 'services' },
  ];
  const done = steps.filter((s) => s.done).length;
  const next = steps.find((s) => !s.done);
  const left = steps.filter((s) => !s.done).length;
  // Everything else that stops requests (a pause, a suspension, an empty listing) is listed under the
  // checklist; not_registered and scope_unconfirmed are already the checklist itself.
  const otherBlocking = blocking.filter((b) => b.code !== 'scope_unconfirmed' && b.code !== 'not_registered');
  const fixLabel = (fix: string) => fix === 'documents' ? (ar ? 'الانتقال إلى المستندات' : 'Go to Documents') : fix === 'scope' || fix === 'services' ? SERVICES_STEP : fix === 'contact' ? '' : (ar ? 'الانتقال إلى الملف' : 'Go to Profile');
  // 'settings': availability (busy / paused) is set under Settings (10 Nov 2026; suppliers read English)
  const fixLabelAll = (fix: string) => fix === 'settings' ? 'Go to Settings' : fixLabel(fix);

  return (
    <section aria-labelledby="qd-getmatched-h" className="qd-panel qd-lit mb-4 p-5 sm:p-6">
      <div className="flex flex-col gap-5 sm:flex-row sm:items-center">
        <Ring done={done} total={steps.length} lang={lang} />
        <div className="min-w-0 flex-1">
          <Kicker>{ar ? 'رحلة المورّد' : 'Supplier journey'}</Kicker>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <h2 id="qd-getmatched-h" className="font-head text-h3 tracking-snug text-foreground">{ar ? 'قائمة التسجيل والمطابقة' : 'Registration checklist'}</h2>
            {/* "Not eligible yet" (red) told him what he is not; it now says what is left (M12, 12 Nov 2026). */}
            <Badge dot variant={e.eligible ? 'ok' : 'warn'}>{e.eligible ? (ar ? 'مؤهّل للمطابقة' : 'Eligible for matching') : left ? `${left} step${left === 1 ? '' : 's'} left` : 'See below what is stopping requests'}</Badge>
          </div>
          <p className="mt-1 max-w-[62ch] text-copy text-muted-foreground">
            {next ? (ar ? 'الخطوة التالية: ' : 'Next step: ') + next.label + '.' : srvText(lang, e.note_code, {}, e.note)}
          </p>
          {next && next.fix !== 'contact' && <Button className="mt-3" onClick={() => go(next.fix)}>{fixLabelAll(next.fix)} {ar ? '←' : '→'}</Button>}
        </div>
        {/* 15 Sep 2026: at a fixed 240px the uppercase, letter-spaced "SHORTLIST" was clipped. The column
            now sizes to its content, and the labels are sentence case, not tracked capitals. */}
        <dl className="grid grid-cols-3 gap-4 sm:w-auto sm:min-w-[260px]">
          {[[e.reach?.matched_requests ?? 0, ar ? 'طلبات مطابقة' : 'Matched'], [e.reach?.quotes_sent ?? 0, ar ? 'عروض مُرسلة' : 'Quoted'], [e.reach?.shortlist_size ?? 8, ar ? 'حجم القائمة المختصرة' : 'Shortlist size']].map(([v, l], i) => (
            <div key={i} className="flex min-w-0 flex-col-reverse border-s border-border ps-3"><dt className="mt-1.5 text-[11.5px] leading-snug text-muted-foreground">{l}</dt><dd className="font-head text-[22px] font-semibold leading-none text-foreground tabular-nums"><bdi dir="ltr">{v}</bdi></dd></div>
          ))}
        </dl>
      </div>

      {/* Progress as the kit meter, then the journey as the kit Stepper: done / current (the next
          undone step) / next. Each title is still the button that sends the supplier to the fix. */}
      <div className="mt-5 flex items-center gap-3">
        <span className="qd-meter flex-1" aria-hidden><span style={{ width: `${steps.length ? Math.round((100 * done) / steps.length) : 0}%` }} /></span>
        <span className="font-mono text-label tabular-nums text-muted-foreground">{done}/{steps.length}</span>
      </div>
      <div className="mt-5 border-t border-border pt-5">
        <Stepper steps={steps.map((s) => ({
          state: s.done ? 'done' : s === next ? 'current' : 'next',
          title: (
            <button type="button" disabled={s.done} onClick={() => go(s.fix)}
              className={cn('inline-flex min-h-11 items-center rounded-sm text-start transition-colors focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring',
                s.done ? 'cursor-default text-muted-foreground line-through decoration-white/20' : 'hover:text-primary')}>
              {s.label}
              <span className="sr-only">{s.done ? (ar ? ' — مكتمل' : ' — done') : (ar ? ' — مطلوب' : ' — to do')}</span>
            </button>
          ),
        }))} />
      </div>

      {otherBlocking.length > 0 && (
        <div className="mt-5">
          <h3 className="text-[12.5px] font-bold text-danger">{ar ? 'ما يمنع وصول الطلبات إليكم' : 'Stopping requests reaching you'}</h3>
          <ul className="mt-2 flex flex-col gap-2.5">{otherBlocking.map((it, i) => <Row key={i} it={it} lang={lang} tone="block" go={go} fixLabel={fixLabelAll} />)}</ul>
        </div>
      )}
      {improving.length > 0 && (
        <details className="mt-5 group">
          <summary className="flex min-h-11 cursor-pointer items-center text-[12.5px] font-bold text-muted-foreground">{ar ? `ما يرفع ترتيبكم (${improving.length})` : `Improves your ranking (${improving.length})`}</summary>
          <ul className="mt-2 flex flex-col gap-2.5">{improving.slice(0, 8).map((it, i) => <Row key={i} it={it} lang={lang} tone="improve" go={go} fixLabel={fixLabelAll} />)}</ul>
        </details>
      )}
    </section>
  );
}

function Row({ it, lang, tone, go, fixLabel }: { it: any; lang: Lang; tone: 'block' | 'improve'; go: (w: string) => void; fixLabel: (f: string) => string }) {
  const { title, detail } = itemCopy(lang, it);
  const label = fixLabel(String(it.fix || ''));
  return (
    <li className="flex items-start gap-2.5">
      <span aria-hidden className={cn('mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full', tone === 'block' ? 'bg-danger' : 'bg-primary')} />
      <div className="flex-1">
        <div className="text-[13.5px] font-semibold text-foreground">{title}</div>
        <div className="text-[13px] leading-[1.65] text-muted-foreground max-w-[68ch]">{detail}</div>
        {label && ['profile', 'documents', 'scope', 'services'].includes(it.fix) && (
          <button type="button" className="mt-1 inline-flex min-h-11 items-center text-[12.5px] font-semibold text-primary underline-offset-2 hover:underline" onClick={() => go(it.fix)}>{label} {lang === 'ar' ? '←' : '→'}</button>
        )}
      </div>
    </li>
  );
}
