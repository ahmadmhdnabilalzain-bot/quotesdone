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
import { Seal } from '@/components/ui/sealed';
import { cn } from '@/lib/utils';
import { boqNote } from '@/lib/boqNotes';
import { call } from './api';
import { ws } from './workspaceCopy';

type Lang = 'en' | 'ar' | string;
const EASE = [0.16, 1, 0.3, 1] as const;

// ── Drawing pages ────────────────────────────────────────────────────────────────────────────────
// `failed` is supplier_api inbox's drawing_pages_failed: pages that EXIST on the inquiry and could not
// be signed. Showing the supplier fewer drawings than exist, saying nothing, is the defect this counts
// (18 Sep 2026, sales_engineer) — a supplier priced a villa from the BOQ alone and never knew.
export function DrawingGallery({ pages, lang, failed = 0 }: { pages: string[]; lang: Lang; failed?: number }) {
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
  if (!n && !failed) return null;
  return (
    <div className="qd-frame mt-4">
      <div className="qd-frame-bar">
        <i /><i /><i />
        <span className="ms-1 min-w-0 truncate font-mono text-label uppercase tracking-caps text-muted-foreground">{ar ? 'المخططات (بعد إخفاء الهوية)' : 'Drawings (identity removed)'}</span>
        <span className="ms-auto shrink-0 font-mono text-label tabular-nums text-muted-foreground">{ar ? `${n} ${n === 1 ? 'صفحة' : 'صفحات'}` : `${n} page${n === 1 ? '' : 's'}`}</span>
      </div>
      {failed > 0 ? <p role="status" className="px-3 pt-3 text-[13px] text-warn-fg">{ws(String(lang), n ? 'rfq_pages_unavailable' : 'rfq_pages_none', { n: failed, total: n + failed })}</p> : null}
      <ul className="grid grid-cols-3 gap-2 p-3 sm:grid-cols-4 md:grid-cols-6">
        {pages.map((u, k) => (
          <li key={k}>
            <motion.button type="button"
              onClick={(e) => { opener.current = e.currentTarget; setOpen(k); }}
              whileHover={reduce ? undefined : { y: -2 }} transition={{ duration: 0.2 }}
              className="group relative block aspect-[3/4] w-full overflow-hidden rounded-chip border border-[var(--line2)] bg-black/30 shadow-e1 transition-colors hover:border-primary/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              aria-label={(ar ? 'فتح صفحة المخطط ' : 'Open drawing page ') + (k + 1)}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={u} alt="" loading="lazy" decoding="async" className="h-full w-full object-cover opacity-90 transition-opacity group-hover:opacity-100" />
              <span className="absolute bottom-1 start-1 rounded-sm bg-black/70 px-1.5 py-0.5 font-mono text-[10.5px] text-white tabular-nums">{ar ? 'ص' : 'p'}{String(k + 1).padStart(2, '0')}</span>
            </motion.button>
          </li>
        ))}
      </ul>
      <AnimatePresence>
        {open !== null && (
          <motion.div role="dialog" aria-modal="true" aria-label={(ar ? 'صفحة المخطط ' : 'Drawing page ') + (open + 1) + ' / ' + n}
            className="fixed inset-0 z-50 flex flex-col bg-[rgba(3,10,16,.95)]"
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
            <p className="px-4 pb-3 text-center text-[11.5px] text-white/60">{ar ? 'أُزيلت بيانات العميل والمشروع من المخطط. تنتهي صلاحية الرابط بعد ساعة — أعيدوا فتح التبويب لتحديثه.' : 'Client and project details were removed from this drawing. The link expires after an hour — reopen the tab to refresh it.'}</p>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// ── Bill of quantities ───────────────────────────────────────────────────────────────────────────
export type BoqRow = { section?: string; description?: string; section_ar?: string | null; description_ar?: string | null; qty?: number | null; unit?: string; basis?: string; confidence?: string };
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
  // The readers write these notes in English; the supplier reads them in the portal's language (#821, founder instruction 586).
  const assumptions: string[] = (Array.isArray(boq?.assumptions) ? boq.assumptions : []).map((s: string) => boqNote(String(s), lang));
  const missing: string[] = (Array.isArray(boq?.missing_info) ? boq.missing_info : []).map((s: string) => boqNote(String(s), lang));
  let lastSection = '';
  return (
    <div className="qd-panel mt-4 overflow-hidden p-0">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--line)] px-4 py-3.5">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-head text-[15px] font-semibold tracking-snug text-foreground">{ar ? 'جدول الكميات' : 'Bill of quantities'}</span>
            <span className="rounded-chip border border-[var(--line2)] px-1.5 py-px font-mono text-label tabular-nums text-muted-foreground">{rows.length}</span>
          </div>
          <div className="mt-0.5 text-[12px] text-muted-foreground">
            {ar ? `${rows.length} بند` : `${rows.length} line item${rows.length === 1 ? '' : 's'}`}
            {confidence ? (ar ? ` · ثقة ${CONF[confidence]?.ar || confidence}` : ` · ${confidence} confidence`) : ''}
            {' · '}{ar ? 'حصر أولي من المخطط، يُرجى التحقق من الكميات قبل التسعير' : 'draft take-off from the drawing — check quantities before pricing'}
          </div>
        </div>
        {onQuote && <Button size="sm" onClick={() => onQuote(rows)}>{ar ? 'تقديم عرض سعر على هذا الجدول' : 'Quote against this BOQ'}</Button>}
      </div>
      {/* Kit BOQ language (see BoqShowcase): mono line codes, mono caps header, tabular quantities.
          Kept a real <table> so sections, caption and headers stay announced. */}
      <div className="max-h-[420px] overflow-auto">
        <table className="w-full border-collapse text-[13px]">
          <caption className="sr-only">{ar ? 'جدول الكميات: الوصف والكمية والوحدة' : 'Bill of quantities: description, quantity and unit'}</caption>
          <thead className="sticky top-0 z-[1] bg-card">
            <tr className="font-mono text-label uppercase tracking-caps text-muted-foreground">
              <th scope="col" className="w-14 px-3 py-2.5 text-start font-medium">#</th>
              {/* 21 Sep 2026 (audit finding 27): in RTL the description column collapsed to one word per line
                  because nothing gave it a width; a minimum width keeps the line readable in either direction. */}
              <th scope="col" className="w-[55%] min-w-[16rem] px-3 py-2.5 text-start font-medium">{ar ? 'الوصف' : 'Description'}</th>
              <th scope="col" className="px-3 py-2.5 text-end font-medium">{ar ? 'الكمية' : 'Qty'}</th>
              <th scope="col" className="px-3 py-2.5 text-start font-medium">{ar ? 'الوحدة' : 'Unit'}</th>
              <th scope="col" className="hidden px-3 py-2.5 text-start font-medium sm:table-cell">{ar ? 'الثقة' : 'Confidence'}</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => {
              const sec = String(r.section || '');
              // Arabic UI: the section and description derived by the sales engineer's vocabulary
              // (_shared/boq_arabic.ts); the English original stays under it because it is what the
              // drawing said and what the supplier prices (audit 21 Sep 2026, finding 26).
              const secShown = ar && r.section_ar ? r.section_ar : sec;
              const head = sec && sec !== lastSection ? secShown : '';
              if (head) lastSection = sec;
              const c = CONF[String(r.confidence || '')];
              return [
                head ? <tr key={'s' + i}><th colSpan={5} scope="colgroup" className="border-t border-[var(--line)] bg-white/[.03] px-3 pb-1.5 pt-3 text-start font-mono text-label uppercase tracking-caps text-primary">{head}</th></tr> : null,
                <tr key={i} className="border-t border-[var(--line)] align-top transition-colors hover:bg-white/[.02]">
                  <td className="px-3 py-2.5 font-mono text-label tabular-nums text-primary">{String(i + 1).padStart(3, '0')}</td>
                  <td className="px-3 py-2.5 text-foreground">
                    {ar && r.description_ar
                      ? <><div>{r.description_ar}</div><div dir="ltr" className="mt-0.5 text-start text-[12px] text-muted-foreground">{r.description}</div></>
                      : <div dir="auto">{r.description || '—'}</div>}
                    {r.basis ? <div className="mt-0.5 text-[11.5px] text-muted-foreground">{r.basis}</div> : null}
                  </td>
                  <td className="tabular px-3 py-2.5 text-end font-mono tabular-nums text-foreground">{r.qty == null ? '—' : nf.format(Number(r.qty))}</td>
                  <td className="px-3 py-2.5 font-mono text-label text-muted-foreground">{r.unit || '—'}</td>
                  <td className="hidden px-3 py-2.5 sm:table-cell">{c ? <span className={cn('rounded-chip border px-2 py-0.5 font-mono text-[11px]', c.cls)}>{ar ? c.ar : c.en}</span> : null}</td>
                </tr>,
              ];
            })}
          </tbody>
        </table>
      </div>
      {(assumptions.length > 0 || missing.length > 0) && (
        <div className="grid gap-3 border-t border-[var(--line)] px-4 py-3 text-[12px] text-muted-foreground sm:grid-cols-2">
          {assumptions.length > 0 && <div><div className="mb-1 font-semibold text-foreground/85">{ar ? 'افتراضات' : 'Assumptions'}</div><ul className="list-disc ps-4">{assumptions.slice(0, 8).map((a, i) => <li key={i}>{a}</li>)}</ul></div>}
          {missing.length > 0 && <div><div className="mb-1 font-semibold text-foreground/85">{ar ? 'غير وارد في المخطط' : 'Not on the drawing'}</div><ul className="list-disc ps-4">{missing.slice(0, 8).map((a, i) => <li key={i}>{a}</li>)}</ul></div>}
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
    <span className="inline-flex flex-wrap items-center gap-2 text-[11.5px] text-muted-foreground">
      <span className="font-mono uppercase tracking-caps">{ar ? 'العميل' : 'Customer'}</span>
      <span aria-hidden><Seal>{ar ? 'اسم العميل' : 'Customer name'}</Seal></span>
      <span className="sr-only">{ar ? 'هوية العميل محجوبة' : 'customer identity withheld'}</span>
      <span>{ar ? '— لا تُكشف الهوية إلا إذا اختاركم' : '— identity shared only if they choose you'}</span>
    </span>
  );
}

// ── Pre-reveal clarification thread ──────────────────────────────────────────────────────────────
type Clar = { id: string; question: string; answer?: string | null; asked_at?: string; answered_at?: string | null; supplier_label?: string | null };
// WHAT THE CUSTOMER ASKED FOR (founder, 14 Sep 2026). The sales engineer asks every customer about
// materials, installation, warranty and the date before a request can be posted, and a quote is
// judged against those answers, so the supplier reads them with the brief. The rows are
// spec.customer_requirements.display (docs/contracts/intake_answers.md), written in both languages
// and scrubbed with the rest of the spec before supplier_api returns it.
export function RequestedTerms({ spec, lang }: { spec: any; lang: Lang }) {
  const ar = lang === 'ar';
  const rows = spec?.customer_requirements?.display?.[ar ? 'ar' : 'en'];
  if (!Array.isArray(rows) || !rows.length) return null;
  return (
    <div className="mt-2 rounded-lg border border-border bg-secondary/20 p-2.5">
      <div className="text-[12px] font-semibold text-foreground">{ar ? 'ما طلبه العميل' : 'What the customer asked for'}</div>
      <dl className="mt-1 grid grid-cols-1 gap-x-3 gap-y-0.5 text-[12px] sm:grid-cols-2">
        {rows.map((r: any) => (
          <div key={String(r?.key)} className="flex gap-1.5"><dt className="text-muted-foreground">{r?.label}:</dt><dd className="text-foreground">{r?.value}</dd></div>
        ))}
      </dl>
    </div>
  );
}

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
    if (j && j.ok) { setText(''); setOpenAsk(false); setMsg(ar ? 'أُرسل سؤالكم إلى العميل دون ذكر اسمكم، وسيظهر الرد هنا لجميع المورّدين المطابقين.' : 'Your question was sent to the customer without your name. The answer will appear here for every matched supplier.'); load(); }
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
            {ar ? 'هل النطاق غير واضح؟ اسألوا العميل دون ذكر اسمكم' : 'Scope unclear? Ask the customer (anonymously)'}
          </button>
        : <div className="mt-2 flex flex-col gap-2">
            <label className="text-[12.5px] text-muted-foreground">
              <span>{ar ? 'ما الذي تحتاجون إلى معرفته؟ يرى العميل السؤال دون اسمكم، ويصل الرد إلى جميع المورّدين المطابقين.' : 'What do you need to know? The customer sees the question without your name, and the answer reaches every matched supplier.'}</span>
              <textarea value={text} maxLength={1000} rows={2} onChange={(e) => setText(e.target.value)}
                className="mt-1.5 flex w-full resize-y rounded-md border border-input bg-transparent px-3 py-2 text-sm text-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring" />
            </label>
            <div className="flex gap-2">
              <Button size="sm" disabled={busy || !text.trim()} onClick={ask}>{busy ? (ar ? 'جارٍ الإرسال…' : 'Sending…') : (ar ? 'إرسال السؤال' : 'Send question')}</Button>
              <Button size="sm" variant="outline" onClick={() => { setOpenAsk(false); setText(''); }}>{ar ? 'إلغاء' : 'Cancel'}</Button>
            </div>
          </div>)}
      {msg && <div role="status" className="mt-1.5 text-[12.5px] text-muted-foreground">{msg}</div>}
    </div>
  );
}
