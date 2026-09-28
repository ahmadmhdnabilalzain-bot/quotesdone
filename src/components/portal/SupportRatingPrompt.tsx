'use client';
// The rating a closed support case asks for, shown inside both portals (customer_support, #1036).
// site_assistant answers for either side from the verified session: 'support_rating_due' lists this
// account's closed cases still waiting for a rating, 'support_rating' records CSAT 1-5 and, optionally,
// CES 1-7 through fn_support_portal_rate, which refuses a case that is not this account's.
import { useEffect, useState } from 'react';
import { SUPA_ANON as ANON, fnUrl } from '@/lib/supaEnv';

type Due = { case_ref: string; subject: string };
type Lang = 'en' | 'ar';

const COPY = {
  en: {
    title: (ref: string) => `How did we do on case ${ref}?`,
    csat: 'Your satisfaction', csatLo: 'Unhappy', csatHi: 'Very happy',
    ces: 'How easy was it to get it solved? (optional)', cesLo: 'Very hard', cesHi: 'Very easy',
    send: 'Send rating', sending: 'Sending…', thanks: 'Thank you. Your rating was recorded.',
    failed: 'The rating was not saved. Please try again.', later: 'Not now',
  },
  ar: {
    title: (ref: string) => `كيف كانت خدمتنا في البلاغ ${ref}؟`,
    csat: 'مدى رضاكم', csatLo: 'غير راضٍ', csatHi: 'راضٍ جداً',
    ces: 'ما مدى سهولة حل المشكلة؟ (اختياري)', cesLo: 'صعب جداً', cesHi: 'سهل جداً',
    send: 'إرسال التقييم', sending: 'جارٍ الإرسال…', thanks: 'شكراً لكم، تم تسجيل تقييمكم.',
    failed: 'لم يُحفظ التقييم، يُرجى المحاولة مرة أخرى.', later: 'ليس الآن',
  },
};

async function post(token: string, body: Record<string, unknown>) {
  const r = await fetch(fnUrl('site_assistant'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
    body: JSON.stringify(body),
  });
  return r.json().catch(() => null);
}

function Scale({ label, lo, hi, max, value, onPick, rtl }: { label: string; lo: string; hi: string; max: number; value: number | null; onPick: (n: number) => void; rtl: boolean }) {
  return (
    <fieldset className="mt-3">
      <legend className="text-[13px] font-semibold">{label}</legend>
      <div className="mt-1 flex flex-wrap gap-1" role="radiogroup" aria-label={label}>
        {Array.from({ length: max }, (_, i) => i + 1).map((n) => (
          <button key={n} type="button" role="radio" aria-checked={value === n} onClick={() => onPick(n)}
            className={'h-9 w-9 rounded-md border text-sm ' + (value === n ? 'bg-primary text-primary-foreground' : 'bg-background')}>
            {rtl ? n.toLocaleString('ar-EG') : n}
          </button>
        ))}
      </div>
      <div className="mt-1 flex justify-between text-[11px] text-muted-foreground" style={{ maxWidth: max * 40 }}><span>{lo}</span><span>{hi}</span></div>
    </fieldset>
  );
}

export default function SupportRatingPrompt({ token, lang }: { token: string; lang: string }) {
  const L: Lang = lang === 'ar' ? 'ar' : 'en';
  const t = COPY[L];
  const [due, setDue] = useState<Due[]>([]);
  const [csat, setCsat] = useState<number | null>(null);
  const [ces, setCes] = useState<number | null>(null);
  const [state, setState] = useState<'idle' | 'sending' | 'done' | 'failed'>('idle');

  useEffect(() => {
    if (!token) return;
    let live = true;
    post(token, { action: 'support_rating_due' }).then((j) => { if (live && j && j.ok && Array.isArray(j.due)) setDue(j.due); }).catch(() => {});
    return () => { live = false; };
  }, [token]);

  const cur = due[0];
  if (!cur && state !== 'done') return null;
  const next = () => { setDue((d) => d.slice(1)); setCsat(null); setCes(null); setState('idle'); };
  const send = async () => {
    if (!cur || csat == null) return;
    setState('sending');
    const j = await post(token, { action: 'support_rating', case_ref: cur.case_ref, csat, ces }).catch(() => null);
    if (j && j.ok) { setState('done'); setTimeout(next, 2500); } else setState('failed');
  };

  return (
    <aside dir={L === 'ar' ? 'rtl' : 'ltr'} aria-live="polite"
      className="fixed bottom-4 start-4 z-40 w-[min(22rem,calc(100vw-2rem))] rounded-xl border bg-card p-4 text-card-foreground shadow-lg">
      {state === 'done' ? <p className="text-sm">{t.thanks}</p> : (<>
        <p className="text-sm font-semibold">{t.title(cur.case_ref)}</p>
        <Scale label={t.csat} lo={t.csatLo} hi={t.csatHi} max={5} value={csat} onPick={setCsat} rtl={L === 'ar'} />
        <Scale label={t.ces} lo={t.cesLo} hi={t.cesHi} max={7} value={ces} onPick={setCes} rtl={L === 'ar'} />
        {state === 'failed' ? <p className="mt-2 text-[12px] text-destructive">{t.failed}</p> : null}
        <div className="mt-3 flex gap-2">
          <button type="button" disabled={csat == null || state === 'sending'} onClick={send}
            className="h-9 rounded-md bg-primary px-3 text-sm text-primary-foreground disabled:opacity-50">
            {state === 'sending' ? t.sending : t.send}
          </button>
          <button type="button" onClick={next} className="h-9 rounded-md border px-3 text-sm">{t.later}</button>
        </div>
      </>)}
    </aside>
  );
}
