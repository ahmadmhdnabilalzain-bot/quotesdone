'use client';
// WHAT THE SUPPLIER PRICES, SHOWN ON THE PAGE (14 Sep 2026).
//
// supplier_api's inbox already returns the redacted drawing pages (signed for 1 h from the
// drawing-files bucket) and the scrubbed BOQ object (`boq.boq`, rows of section / description / qty /
// unit / basis / confidence from drawing_boq). The RFQ card rendered them as "Drawing p1" text links
// and "BOQ: 7 line items" — the supplier quoted a drawing they could not see on the page and a bill of
// quantities they could not read (website audit 2026-09-14, supplier portal finding 20).
//
// Three parts: the drawing pages as thumbnails with a keyboard-operable lightbox, the BOQ as a table
// with a "quote against this BOQ" action that pre-fills the quote form's line items, and the
// pre-reveal clarification thread (messages_api clarify_list / clarify_ask — the anonymous Q&A where
// an answer reaches every matched supplier, replacing the window.prompt/alert "Scope unclear?" link).
import { useCallback, useEffect, useRef, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { call } from './api';

type Lang = 'en' | 'ar' | string;
const EASE = [0.16, 1, 0.3, 1] as const;

// ── Drawing pages ────────────────────────────────────────────────────────────────────────────────
export function DrawingGallery({ pages, lang }: { pages: string[]; lang: Lang }) {
  const ar = lang === 'ar';
  const [open, setOpen] = useState<number | null>(null);
  const reduce = useReducedMotion();
  const closeRef = useRef<HTMLButtonElement | null>(null);
  const opener = useRef<HTMLElement | null>(null);
  const n = pages.length;
  const go = useCallback((d: number) => setOpen((i) => (i === null ? i : (i + d + n) % n)), [n]);
  useEffect(() => {
    if (open === null) return;
    closeRef.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(null);
      else if (e.key === 'ArrowRight') go(ar ? -1 : 1);
      else if (e.key === 'ArrowLeft') go(ar ? 1 : -1);
    };
    window.addEventListener('keydown', onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => { window.removeEventListener('keydown', onKey); document.body.style.overflow = prev; opener.current?.focus(); };
  }, [open, go, ar]);
  if (!n) return null;
  return (
    <div className="mt-3">
      <div className="mb-1.5 flex items-baseline justify-between gap-2">
        <span className="text-[11.5px] font-semibold uppercase tracking-[.08em] text-muted-foreground">{ar ? 'المخططات (بعد إخفاء الهوية)' : 'Drawings (identity removed)'}</span>
        <span className="text-[11px] text-muted-foreground/80">{ar ? `${n} ${n === 1 ? 'صفحة' : 'صفحات'}` : `${n} page${n === 1 ? '' : 's'}`}</span>
      </div>
      <ul className="grid grid-cols-3 gap-2 sm:grid-cols-4 md:grid-cols-6">
        {pages.map((u, k) => (
          <li key={k}>
            <motion.button type="button"
              onClick={(e) => { opener.current = e.currentTarget; setOpen(k); }}
              whileHover={reduce ? undefined : { y: -2 }} transition={{ duration: 0.2 }}
              className="group relative block aspect-[3/4] w-full overflow-hidden rounded-lg border border-[var(--line)] bg-black/30 shadow-[var(--key)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              aria-label={(ar ? 'افتح صفحة المخطط ' : 'Open drawing page ') + (k + 1)}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={u} alt="" loading="lazy" decoding="async" className="h-full w-full object-cover opacity-90 transition-opacity group-hover:opacity-100" />
              <span className="absolute bottom-1 start-1 rounded bg-black/65 px-1.5 py-0.5 text-[10.5px] font-semibold text-white tabular-nums">{ar ? 'ص' : 'p'}{k + 1}</span>
            </motion.button>
          </li>
        ))}
      </ul>
      <AnimatePresence>
        {open !== null && (
          <motion.div role="dialog" aria-modal="true" aria-label={(ar ? 'صفحة المخطط ' : 'Drawing page ') + (open + 1) + ' / ' + n}
            className="fixed inset-0 z-50 flex flex-col bg-[rgba(3,10,16,.92)] backdrop-blur-sm"
            initial={reduce ? false : { opacity: 0 }} animate={{ opacity: 1 }} exit={reduce ? undefined : { opacity: 0 }}
            onClick={(e) => { if (e.target === e.currentTarget) setOpen(null); }}>
            <div className="flex items-center justify-between gap-3 px-4 py-3 text-white">
              <span className="text-sm font-semibold tabular-nums">{(ar ? 'صفحة ' : 'Page ') + (open + 1) + ' / ' + n}</span>
              <div className="flex gap-2">
                {n > 1 && <Button size="sm" variant="outline" onClick={() => go(-1)} aria-label={ar ? 'الصفحة السابقة' : 'Previous page'}>{ar ? '→' : '←'}</Button>}
                {n > 1 && <Button size="sm" variant="outline" onClick={() => go(1)} aria-label={ar ? 'الصفحة التالية' : 'Next page'}>{ar ? '←' : '→'}</Button>}
                <Button ref={closeRef} size="sm" variant="outline" onClick={() => setOpen(null)}>{ar ? 'إغلاق' : 'Close'}</Button>
              </div>
            </div>
            <div className="flex min-h-0 flex-1 items-center justify-center p-3" onClick={(e) => { if (e.target === e.currentTarget) setOpen(null); }}>
              <motion.img key={open} src={pages[open]} alt={(ar ? 'صفحة المخطط ' : 'Drawing page ') + (open + 1)}
                className="max-h-full max-w-full rounded-md bg-white object-contain shadow-[var(--lift)]"
                initial={reduce ? false : { opacity: 0, scale: 0.98 }} animate={{ opacity: 1, scale: 1 }} transition={{ duration: 0.35, ease: EASE }} />
            </div>
            <p className="px-4 pb-3 text-center text-[11.5px] text-white/60">{ar ? 'أُزيلت بيانات العميل والمشروع من المخطط. تنتهي صلاحية الرابط بعد ساعة — أعد فتح التبويب لتحديثه.' : 'Client and project details were removed from this drawing. The link expires after an hour — reopen the tab to refresh it.'}</p>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// ── Bill of quantities ───────────────────────────────────────────────────────────────────────────
export type BoqRow = { section?: string; description?: string; qty?: number | null; unit?: string; basis?: string; confidence?: string };
const CONF: Record<string, { en: string; ar: string; cls: string }> = {
  high: { en: 'high', ar: 'عالية', cls: 'bg-primary/15 text-primary border-primary/40' },
  medium: { en: 'medium', ar: 'متوسطة', cls: 'bg-warn/10 text-warn-fg border-warn/30' },
  low: { en: 'low', ar: 'منخفضة', cls: 'bg-white/5 text-muted-foreground border-white/15' },
};
export function BoqTable({ boq, confidence, lang, onQuote }: { boq: any; confidence?: string | null; lang: Lang; onQuote?: (rows: BoqRow[]) => void }) {
  const ar = lang === 'ar';
  const rows: BoqRow[] = Array.isArray(boq?.boq) ? boq.boq : [];
  if (!rows.length) return null;
  const nf = new Intl.NumberFormat(ar ? 'ar-AE' : 'en-AE', { maximumFractionDigits: 2 });
  const assumptions: string[] = Array.isArray(boq?.assumptions) ? boq.assumptions : [];
  const missing: string[] = Array.isArray(boq?.missing_info) ? boq.missing_info : [];
  let lastSection = '';
  return (
    <div className="qd-panel mt-3 overflow-hidden p-0">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-[var(--line)] px-4 py-3">
        <div>
          <div className="text-[13.5px] font-bold text-foreground">{ar ? 'جدول الكميات' : 'Bill of quantities'}</div>
          <div className="text-[11.5px] text-muted-foreground">
            {ar ? `${rows.length} بند` : `${rows.length} line item${rows.length === 1 ? '' : 's'}`}
            {confidence ? (ar ? ` · ثقة ${CONF[confidence]?.ar || confidence}` : ` · ${confidence} confidence`) : ''}
            {' · '}{ar ? 'حصر أولي من المخطط — تحقّق من الكميات قبل التسعير' : 'draft take-off from the drawing — check quantities before pricing'}
          </div>
        </div>
        {onQuote && <Button size="sm" onClick={() => onQuote(rows)}>{ar ? 'قدّم عرضًا على هذا الجدول' : 'Quote against this BOQ'}</Button>}
      </div>
      <div className="max-h-[420px] overflow-auto">
        <table className="w-full border-collapse text-[13px]">
          <caption className="sr-only">{ar ? 'جدول الكميات: الوصف والكمية والوحدة' : 'Bill of quantities: description, quantity and unit'}</caption>
          <thead className="sticky top-0 z-[1] bg-card/95 backdrop-blur">
            <tr className="text-[11px] uppercase tracking-[.06em] text-muted-foreground">
              <th scope="col" className="w-10 px-3 py-2 text-start font-semibold">#</th>
              <th scope="col" className="px-3 py-2 text-start font-semibold">{ar ? 'الوصف' : 'Description'}</th>
              <th scope="col" className="px-3 py-2 text-end font-semibold">{ar ? 'الكمية' : 'Qty'}</th>
              <th scope="col" className="px-3 py-2 text-start font-semibold">{ar ? 'الوحدة' : 'Unit'}</th>
              <th scope="col" className="hidden px-3 py-2 text-start font-semibold sm:table-cell">{ar ? 'الثقة' : 'Confidence'}</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => {
              const sec = String(r.section || '');
              const head = sec && sec !== lastSection ? sec : '';
              if (head) lastSection = sec;
              const c = CONF[String(r.confidence || '')];
              return [
                head ? <tr key={'s' + i}><th colSpan={5} scope="colgroup" className="bg-white/[.03] px-3 pb-1 pt-2.5 text-start text-[11.5px] font-bold text-primary">{head}</th></tr> : null,
                <tr key={i} className="border-t border-[var(--line)] align-top">
                  <td className="px-3 py-2 text-muted-foreground tabular-nums">{i + 1}</td>
                  <td className="px-3 py-2 text-foreground">
                    <div>{r.description || '—'}</div>
                    {r.basis ? <div className="mt-0.5 text-[11.5px] text-muted-foreground">{r.basis}</div> : null}
                  </td>
                  <td className="px-3 py-2 text-end font-semibold tabular-nums text-foreground">{r.qty == null ? '—' : nf.format(Number(r.qty))}</td>
                  <td className="px-3 py-2 text-muted-foreground">{r.unit || '—'}</td>
                  <td className="hidden px-3 py-2 sm:table-cell">{c ? <span className={cn('rounded-full border px-2 py-0.5 text-[11px] font-semibold', c.cls)}>{ar ? c.ar : c.en}</span> : null}</td>
                </tr>,
              ];
            })}
          </tbody>
        </table>
      </div>
      {(assumptions.length > 0 || missing.length > 0) && (
        <div className="grid gap-3 border-t border-[var(--line)] px-4 py-3 text-[12px] text-muted-foreground sm:grid-cols-2">
          {assumptions.length > 0 && <div><div className="mb-1 font-semibold text-foreground/85">{ar ? 'افتراضات' : 'Assumptions'}</div><ul className="list-disc ps-4">{assumptions.slice(0, 8).map((a, i) => <li key={i}>{a}</li>)}</ul></div>}
          {missing.length > 0 && <div><div className="mb-1 font-semibold text-foreground/85">{ar ? 'معلومات ناقصة' : 'Not on the drawing'}</div><ul className="list-disc ps-4">{missing.slice(0, 8).map((a, i) => <li key={i}>{a}</li>)}</ul></div>}
        </div>
      )}
    </div>
  );
}

// ── Anonymous identity, shown as withheld ────────────────────────────────────────────────────────
// The redaction bar is the brand's own primitive for a withheld value. Pre-reveal, the customer's
// identity exists and we hold it; showing it as a bar makes the anonymity rule visible instead of
// implied.
export function WithheldCustomer({ lang }: { lang: Lang }) {
  const ar = lang === 'ar';
  return (
    <span className="inline-flex items-center gap-2 text-[11.5px] text-muted-foreground">
      <span>{ar ? 'العميل' : 'Customer'}</span>
      <span aria-hidden className="redact redact-bar" style={{ width: 84, height: 11 }} />
      <span className="sr-only">{ar ? 'هوية العميل محجوبة' : 'customer identity withheld'}</span>
      <span>{ar ? '— تُكشف الهوية فقط إذا اختارك' : '— identity shared only if they choose you'}</span>
    </span>
  );
}

// ── Pre-reveal clarification thread ──────────────────────────────────────────────────────────────
type Clar = { id: string; question: string; answer?: string | null; asked_at?: string; answered_at?: string | null; supplier_label?: string | null };
export function ClarifyThread({ inquiryId, token, lang, canAsk }: { inquiryId: string; token: string; lang: Lang; canAsk: boolean }) {
  const ar = lang === 'ar';
  const [items, setItems] = useState<Clar[] | null>(null);
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');
  const [openAsk, setOpenAsk] = useState(false);
  const load = useCallback(async () => {
    const j = await call('messages_api', { action: 'clarify_list', inquiry_id: inquiryId }, token).catch(() => null);
    setItems(j && j.ok && Array.isArray(j.items) ? j.items : []);
  }, [inquiryId, token]);
  useEffect(() => { load(); }, [load]);
  const ask = async () => {
    const q = text.trim(); if (!q) return;
    setBusy(true); setMsg('');
    const j = await call('messages_api', { action: 'clarify_ask', inquiry_id: inquiryId, text: q.slice(0, 1000) }, token).catch(() => null);
    setBusy(false);
    if (j && j.ok) { setText(''); setOpenAsk(false); setMsg(ar ? 'أُرسل سؤالك إلى العميل دون ذكر اسمك. سيظهر الرد هنا لكل المورّدين المطابقين.' : 'Your question was sent to the customer without your name. The answer will appear here for every matched supplier.'); load(); }
    else setMsg(ar ? 'تعذّر إرسال السؤال. يُرجى المحاولة مرة أخرى.' : 'Could not send your question. Please try again.');
  };
  const fmt = (d?: string | null) => (d ? new Date(d).toLocaleDateString(ar ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short' }) : '');
  const list = items || [];
  return (
    <div className="mt-3">
      {list.length > 0 && (
        <div className="rounded-lg border border-[var(--line)] bg-white/[.02] p-3">
          <div className="mb-2 text-[11.5px] font-semibold uppercase tracking-[.08em] text-muted-foreground">{ar ? 'أسئلة وأجوبة قبل الكشف' : 'Questions before the reveal'}</div>
          <ol className="flex flex-col gap-2.5">
            {list.map((c) => (
              <li key={c.id} className="text-[13px]">
                <div className="text-foreground"><span className="font-semibold text-primary">{ar ? 'س: ' : 'Q: '}</span>{c.question}
                  <span className="ms-2 text-[11px] text-muted-foreground">{c.supplier_label ? c.supplier_label + ' · ' : ''}{fmt(c.asked_at)}</span></div>
                <div className="mt-0.5 text-muted-foreground">{c.answer
                  ? <><span className="font-semibold text-foreground/85">{ar ? 'ج: ' : 'A: '}</span>{c.answer}<span className="ms-2 text-[11px]">{fmt(c.answered_at)}</span></>
                  : <em>{ar ? 'بانتظار رد العميل' : 'Waiting for the customer'}</em>}</div>
              </li>
            ))}
          </ol>
        </div>
      )}
      {canAsk && (!openAsk
        ? <button type="button" className="mt-2 text-[12.5px] font-semibold text-muted-foreground underline underline-offset-2 hover:text-primary" onClick={() => { setOpenAsk(true); setMsg(''); }}>
            {ar ? 'النطاق غير واضح؟ اسأل العميل (دون ذكر اسمك)' : 'Scope unclear? Ask the customer (anonymously)'}
          </button>
        : <div className="mt-2 flex flex-col gap-2">
            <label className="text-[12.5px] text-muted-foreground">
              <span>{ar ? 'ما الذي تحتاج إلى معرفته؟ يرى العميل السؤال دون اسمك، ويصل الرد إلى كل المورّدين المطابقين.' : 'What do you need to know? The customer sees the question without your name, and the answer reaches every matched supplier.'}</span>
              <textarea value={text} maxLength={1000} rows={2} onChange={(e) => setText(e.target.value)}
                className="mt-1.5 flex w-full resize-y rounded-md border border-input bg-transparent px-3 py-2 text-sm text-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring" />
            </label>
            <div className="flex gap-2">
              <Button size="sm" disabled={busy || !text.trim()} onClick={ask}>{busy ? (ar ? 'جارٍ الإرسال…' : 'Sending…') : (ar ? 'أرسل السؤال' : 'Send question')}</Button>
              <Button size="sm" variant="outline" onClick={() => { setOpenAsk(false); setText(''); }}>{ar ? 'إلغاء' : 'Cancel'}</Button>
            </div>
          </div>)}
      {msg && <div role="status" className="mt-1.5 text-[12.5px] text-muted-foreground">{msg}</div>}
    </div>
  );
}
