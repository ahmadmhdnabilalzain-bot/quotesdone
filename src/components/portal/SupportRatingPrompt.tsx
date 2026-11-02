'use client';
// The rating a closed support case asks for, shown inside both portals (customer_support, #1036).
// The portals are the sales engineer's (founder, 14 Sep 2026: "no other agent is involved in customer or
// supplier portal"), so the portal asks its own sales-owned function, never Support's widget: sales_engineer
// for a customer, supplier_api for a supplier. Each answers from the verified session: 'support_rating_due'
// lists this account's closed cases still waiting for a rating, 'support_rating' records CSAT 1-5 and,
// optionally, CES 1-7 through fn_support_portal_rate, which refuses a case that is not this account's.
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
    failed: 'The rating was not saved. Please try again.', later: 'Not now', rate: 'Rate',
  },
  ar: {
    title: (ref: string) => `كيف كانت خدمتنا في البلاغ ${ref}؟`,
    csat: 'مدى رضاكم', csatLo: 'غير راضٍ', csatHi: 'راضٍ جداً',
    ces: 'ما مدى سهولة حل المشكلة؟ (اختياري)', cesLo: 'صعب جداً', cesHi: 'سهل جداً',
    send: 'إرسال التقييم', sending: 'جارٍ الإرسال…', thanks: 'شكراً لكم، تم تسجيل تقييمكم.',
    failed: 'لم يُحفظ التقييم، يُرجى المحاولة مرة أخرى.', later: 'ليس الآن', rate: 'تقييم',
  },
};

type Api = 'sales_engineer' | 'supplier_api';

// "Not now" is remembered for the browser session, so the card does not come back on every page the customer opens.
const SKIP_KEY = 'qd_rating_skipped';
const skipped = (): string[] => { try { return JSON.parse(sessionStorage.getItem(SKIP_KEY) || '[]'); } catch { return []; } };
const skip = (ref: string) => { try { sessionStorage.setItem(SKIP_KEY, JSON.stringify([...skipped(), ref])); } catch { /* storage unavailable: it asks again next load */ } };

async function post(api: Api, token: string, body: Record<string, unknown>) {
  const r = await fetch(fnUrl(api), {
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

export default function SupportRatingPrompt({ token, lang, api }: { token: string; lang: string; api: Api }) {
  // A supplier is always English (founder ruling 1008) whatever language the caller passes: the supplier portal's
  // constant is not the only guard, the component holds the rule itself.
  const L: Lang = api === 'supplier_api' ? 'en' : lang === 'ar' ? 'ar' : 'en';
  const t = COPY[L];
  const [due, setDue] = useState<Due[]>([]);
  const [csat, setCsat] = useState<number | null>(null);
  const [ces, setCes] = useState<number | null>(null);
  const [state, setState] = useState<'idle' | 'sending' | 'done' | 'failed'>('idle');
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!token) return;
    let live = true;
    // OFF THE CRITICAL PATH (19 Oct 2026, platform-on simulation): on a cold sales_engineer this call took
    // 3.1 s and held the customer overview at 4.1 s against the 2.5 s target, while the RPC itself runs in
    // 3 ms. A rating prompt is never the page's data, so it is asked for once the overview has settled.
    const ask = () => post(api, token, { action: 'support_rating_due' }).then((j) => { if (live && j && j.ok && Array.isArray(j.due)) setDue(j.due.filter((d: Due) => !skipped().includes(d.case_ref))); }).catch(() => {});
    const timer = window.setTimeout(ask, 3000);
    return () => { live = false; window.clearTimeout(timer); };
  }, [api, token]);

  const cur = due[0];
  if (!cur && state !== 'done') return null;
  const next = () => { setDue((d) => d.slice(1)); setCsat(null); setCes(null); setState('idle'); setOpen(false); };
  const notNow = () => { if (cur) skip(cur.case_ref); next(); };
  const send = async () => {
    if (!cur || csat == null) return;
    setState('sending');
    const j = await post(api, token, { action: 'support_rating', case_ref: cur.case_ref, csat, ces }).catch(() => null);
    if (j && j.ok) { setState('done'); setTimeout(next, 2500); } else setState('failed');
  };

  // The corner OPPOSITE the sidebar (end, not start) and one line until the customer chooses to rate. The open card was
  // 22rem x 15rem over the sidebar's Account and Documents items on a laptop, and over the request box on a phone
  // (stage 2 run f0b2de8f, 2 Nov 2026: "nav item Account could not be pressed", "something lies on top of the box").
  return (
    <aside dir={L === 'ar' ? 'rtl' : 'ltr'} aria-live="polite"
      className="fixed bottom-4 end-4 z-40 w-[min(22rem,calc(100vw-2rem))] rounded-xl border bg-card p-3 text-card-foreground shadow-lg">
      {state === 'done' ? <p className="text-sm">{t.thanks}</p> : !open ? (
        <div className="flex items-center gap-2">
          <p className="min-w-0 flex-1 text-sm font-semibold">{t.title(cur.case_ref)}</p>
          <button type="button" onClick={() => setOpen(true)} className="h-9 rounded-md bg-primary px-3 text-sm text-primary-foreground">{t.rate}</button>
          <button type="button" onClick={notNow} className="h-9 rounded-md border px-3 text-sm">{t.later}</button>
        </div>
      ) : (<>
        <p className="text-sm font-semibold">{t.title(cur.case_ref)}</p>
        <Scale label={t.csat} lo={t.csatLo} hi={t.csatHi} max={5} value={csat} onPick={setCsat} rtl={L === 'ar'} />
        <Scale label={t.ces} lo={t.cesLo} hi={t.cesHi} max={7} value={ces} onPick={setCes} rtl={L === 'ar'} />
        {state === 'failed' ? <p className="mt-2 text-[12px] text-destructive">{t.failed}</p> : null}
        <div className="mt-3 flex gap-2">
          <button type="button" disabled={csat == null || state === 'sending'} onClick={send}
            className="h-9 rounded-md bg-primary px-3 text-sm text-primary-foreground disabled:opacity-50">
            {state === 'sending' ? t.sending : t.send}
          </button>
          <button type="button" onClick={notNow} className="h-9 rounded-md border px-3 text-sm">{t.later}</button>
        </div>
      </>)}
    </aside>
  );
}
