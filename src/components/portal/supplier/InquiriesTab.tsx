'use client';
// INQUIRIES RECEIVED (founder, 15 Sep 2026). Every inquiry sent to this supplier, by its job number;
// opening one shows the inquiry as the sales engineer prepared it — the scope, what the customer asked
// for, the redacted drawings and the bill of quantities — with its documents downloadable.
//
// It replaces the RFQ inbox's card list and reuses its parts (./RfqParts: the drawing gallery, the BOQ
// table, the requested terms, the withheld customer and the anonymous Q&A). Everything comes from
// supplier_api's inquiries_list / inquiry_detail / inquiry_documents, which read the inbox and its
// scrubbers: only redacted drawings and the scrubbed BOQ are ever offered, and nothing identifies the
// customer before a reveal.
import { useCallback, useEffect, useRef, useState } from 'react';
import { useReducedMotion } from 'motion/react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { categoryLabel } from '@/lib/categoryLabel';
import { emirateLabel, srvMsg } from './serverCopy';
import { ws } from './workspaceCopy';
import DocActions from '../DocActions';
import { BoqTable, ClarifyThread, DrawingGallery, RequestedTerms, WithheldCustomer } from './RfqParts';
import { aedIn, failed, openPdf, qr, saveInline, REVIEW_STATE, type InquiryDetail, type InquiryDocuments, type InquiryListItem, type Lang } from './quoteReviewApi';
import { Ltr } from '@/lib/Ltr';

const COPY = {
  en: {
    title: 'Inquiries received', sub: 'Every request matched to your company, by job number. Open one to read it as our sales engineer prepared it.',
    empty: 'No inquiries yet', emptySub: 'When a customer’s request matches your trade and emirates, it arrives here with its job number, the scope, the drawings and the bill of quantities.',
    job: 'Job No.', received: 'Received', boq: (n: number) => `BOQ ${n} line${n === 1 ? '' : 's'}`, drawings: (n: number) => `${n} drawing page${n === 1 ? '' : 's'}`,
    scope: 'Scope', documents: 'Documents', download: 'Download', noDocs: 'No documents were attached to this inquiry.',
    boqFile: (n: number) => `Bill of quantities (${n} lines, CSV)`, page: (n: number) => `Drawing page ${n} (identity removed)`,
    inqPdf: 'Inquiry document (PDF)', pdfEn: 'English', pdfAr: 'Arabic', preparing: 'Preparing…', pdfFailed: 'The document could not be prepared. Please try again.',
    quote: 'Send your quotation to the sales engineer', form: 'Or type it into the quote form', closeForm: 'Close the form', sentOk: 'Your quotation was submitted.', sentHeld: 'Your quotation is saved and on hold: the card below lists what is still needed.',
    concluded: 'Concluded — the customer has chosen.', won: 'You won this job.', quoted: 'Your quotation', loading: 'Loading inquiries…', err: 'Something went wrong. Please try again.', retry: 'Try again',
    boqHeld: 'The bill of quantities is held back because we could not prove it free of the customer’s details. Price from the drawings and the scope.',
    budget: 'Budget', open: 'Open', close: 'Close',
  },
  ar: {
    title: 'الاستفسارات الواردة', sub: 'كل طلب طابق شركتك، برقم الطلب. افتح أيًّا منها لتقرأه كما أعدّه مهندس المبيعات.',
    empty: 'لا توجد طلبات بعد', emptySub: 'عندما يطابق طلب عميل تخصصك وإماراتك، يصل هنا برقم الطلب والنطاق والمخططات وجدول الكميات.',
    job: 'رقم الطلب', received: 'تاريخ الاستلام', boq: (n: number) => `جدول الكميات: ${n} بند`, drawings: (n: number) => `${n} صفحة مخطط`,
    scope: 'النطاق', documents: 'المستندات', download: 'تنزيل', noDocs: 'لم تُرفق مستندات بهذا الطلب.',
    boqFile: (n: number) => `جدول الكميات (${n} بندًا، CSV)`, page: (n: number) => `صفحة المخطط ${n} (بعد إخفاء الهوية)`,
    inqPdf: 'مستند الاستفسار (PDF)', pdfEn: 'بالإنجليزية', pdfAr: 'بالعربية', preparing: 'جارٍ التحضير…', pdfFailed: 'تعذّر تحضير المستند. يُرجى المحاولة مرة أخرى.',
    quote: 'أرسل عرض سعرك إلى مهندس المبيعات', form: 'أو اكتبه في نموذج العرض', closeForm: 'أغلق النموذج', sentOk: 'تم تقديم عرض سعرك.', sentHeld: 'حُفظ عرض سعرك وهو معلّق: البطاقة أدناه تذكر ما يلزم بعد.',
    concluded: 'انتهى — اختار العميل.', won: 'فزت بهذا الطلب.', quoted: 'عرضك', loading: 'جارٍ تحميل الطلبات…', err: 'حدث خطأ. يُرجى المحاولة مرة أخرى.', retry: 'أعد المحاولة',
    boqHeld: 'حُجب جدول الكميات لأننا لم نتمكّن من إثبات خلوّه من بيانات العميل. سعّر من المخططات والنطاق.',
    budget: 'الميزانية', open: 'افتح', close: 'أغلق',
  },
};
const day = (d: string, lang: Lang) => new Date(d).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
// deno-style loose shape the legacy quote form reads (SupplierPortal QuoteForm): the inquiry and its quotes.
export type LegacyInquiry = { id: string; quote: unknown; quotes: unknown[]; [k: string]: unknown };

function Documents({ token, lang, id }: { token: string; lang: Lang; id: string }) {
  const t = COPY[lang];
  const [d, setD] = useState<InquiryDocuments | null>(null);
  // A failed fetch used to leave the section rendering nothing, which reads as "this job has no
  // drawings or BOQ" — the opposite of the truth. It says so, and offers the retry, instead.
  const [err, setErr] = useState(false);
  const [n, setN] = useState(0);
  // THE INQUIRY AS A DOCUMENT (21 Sep 2026; founder instruction 435). The sales engineer's template
  // as a PDF, English or Arabic, printed by supplier_api inquiry_pdf on the same renderer as the
  // quotation and cached there. It sits first in the documents list because it is the document the
  // drawings and the BOQ belong to.
  const [busy, setBusy] = useState<Lang | null>(null);
  const [pdfErr, setPdfErr] = useState(false);
  const inquiryPdf = async (l: Lang) => { setBusy(l); setPdfErr(false); const ok = await openPdf(() => qr.inquiryPdf(token, id, l)); setBusy(null); if (!ok) setPdfErr(true); };
  useEffect(() => {
    let on = true;
    qr.documents(token, id).then((j) => { if (!on) return; if (failed(j)) setErr(true); else { setD(j); setErr(false); } })
      .catch(() => { if (on) setErr(true); });
    return () => { on = false; };
  }, [token, id, n]);
  const pdfRow = (
    <li className="flex flex-wrap items-center justify-between gap-2 px-3 py-2">
      <span className="min-w-0 text-[13px] font-semibold text-foreground">{t.inqPdf}</span>
      <span className="flex items-center gap-1.5">
        <Button size="sm" variant="outline" disabled={!!busy} onClick={() => inquiryPdf('en')} lang="en">{busy === 'en' ? t.preparing : t.pdfEn}</Button>
        <Button size="sm" variant="outline" disabled={!!busy} onClick={() => inquiryPdf('ar')} lang="ar">{busy === 'ar' ? t.preparing : t.pdfAr}</Button>
      </span>
      {pdfErr ? <span role="alert" className="basis-full text-[12px] text-danger-fg">{t.pdfFailed}</span> : null}
    </li>
  );
  if (err) return (
    <div className="mt-4">
      <h3 className="text-[13px] font-semibold text-foreground">{t.documents}</h3>
      <p className="mt-1 text-[12.5px] text-muted-foreground">{t.err}</p>
      <Button className="mt-2" size="sm" variant="outline" onClick={() => { setErr(false); setN((x) => x + 1); }}>{t.retry}</Button>
    </div>
  );
  if (!d) return null;
  return (
    <div className="mt-4">
      <h3 className="text-[13px] font-semibold text-foreground">{t.documents}</h3>
      {!d.documents.length ? <p className="mt-1 text-[12.5px] text-muted-foreground">{t.noDocs}</p> : null}
      {(
        <ul className="mt-2 divide-y divide-[var(--line)] rounded-md border border-[var(--line)]">
          {pdfRow}
          {d.documents.map((doc, k) => (
            <li key={`${doc.kind}:${doc.name}:${k}`} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2">
              <span className="min-w-0 text-[13px] text-foreground">{doc.kind === 'boq_csv' ? t.boqFile(doc.lines) : t.page(k + 1)}<span className="ms-2 font-mono text-[11px] text-muted-foreground"><Ltr>{doc.name}</Ltr></span></span>
              {/* The four actions (instruction 524). These are the customer's documents: View / Download
                  work; Replace / Remove say so. A BOQ is inline content, so both open it through saveInline. */}
              {doc.kind === 'drawing_page'
                ? (/^https:\/\//i.test(doc.url) ? <DocActions lang={lang} name={doc.name} url={doc.url} sealed="customers_inquiry" /> : null)
                : <DocActions lang={lang} name={doc.name} sealed="customers_inquiry" onView={() => saveInline(doc.name, doc.content, doc.mime)} onDownload={() => saveInline(doc.name, doc.content, doc.mime)} />}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function Detail({ token, lang, id, onQuote, renderQuoteForm }: { token: string; lang: Lang; id: string; onQuote: (id: string) => void; renderQuoteForm?: (inq: LegacyInquiry, done: (r?: { held?: boolean }) => void) => React.ReactNode }) {
  const t = COPY[lang];
  const [d, setD] = useState<InquiryDetail['inquiry'] | null>(null);
  const [err, setErr] = useState('');
  const [form, setForm] = useState(false);
  // Submit confirmation (audit 21 Sep 2026, finding 33: the form closed with no word of what happened).
  const [sent, setSent] = useState<'' | 'ok' | 'held'>('');
  const alive = useRef(true);
  const load = useCallback(() => qr.inquiry(token, id).then((j) => { if (!alive.current) return; if (failed(j)) setErr(srvMsg(lang, j, t.err)); else setD(j.inquiry); }), [token, id, lang, t.err]);
  useEffect(() => { alive.current = true; load(); return () => { alive.current = false; }; }, [load]);
  if (err) return <p role="alert" className="px-4 pb-4 text-[13px] text-danger-fg">{err}</p>;
  if (!d) return <div className="space-y-2 px-4 pb-4" aria-busy="true">{[70, 90, 55].map((w) => <div key={w} className="h-3 animate-pulse rounded bg-white/[.06] motion-reduce:animate-none" style={{ width: w + '%' }} />)}</div>;
  const canQuote = !d.concluded && !d.revealed;
  const q = d.quotes[0];
  return (
    <div className="border-t border-[var(--line)] px-4 pb-5 pt-4 sm:px-5">
      <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-[12.5px] sm:grid-cols-4">
        <div><dt className="text-muted-foreground">{t.job}</dt><dd className="font-mono font-semibold tabular-nums text-foreground"><Ltr>{d.job_no}</Ltr></dd></div>
        <div><dt className="text-muted-foreground">{t.received}</dt><dd className="text-foreground">{day(d.created_at, lang)}</dd></div>
        <div><dt className="text-muted-foreground">{lang === 'ar' ? 'التخصص' : 'Trade'}</dt><dd className="text-foreground">{categoryLabel(d.category || '', lang) || '—'}</dd></div>
        <div><dt className="text-muted-foreground">{lang === 'ar' ? 'الإمارة' : 'Emirate'}</dt><dd className="text-foreground">{emirateLabel(lang, d.emirate || '') || '—'}</dd></div>
      </dl>
      <div className="mt-3">{d.you_won ? <span className="text-[13px] font-semibold text-primary">{t.won}</span> : d.concluded ? <span className="text-[13px] text-muted-foreground">{t.concluded}</span> : !d.revealed ? <WithheldCustomer lang={lang} /> : null}</div>
      {d.summary ? <section className="mt-4"><h3 className="text-[13px] font-semibold text-foreground">{t.scope}</h3>{lang === 'ar' && d.summary_ar
        ? <><p className="mt-1 max-w-[70ch] text-[13.5px] leading-relaxed text-foreground/90">{d.summary_ar}</p><p dir="auto" className="mt-1 max-w-[70ch] text-[12px] text-muted-foreground">{d.summary}</p></>
        : <p dir="auto" className="mt-1 max-w-[70ch] text-[13.5px] leading-relaxed text-foreground/90">{d.summary}</p>}{d.budget ? <p className="mt-1 text-[12px] text-muted-foreground">{t.budget}: {d.budget}</p> : null}</section> : null}
      <RequestedTerms spec={d.spec} lang={lang} />
      <Documents token={token} lang={lang} id={d.id} />
      <DrawingGallery pages={d.drawing_pages} failed={Number(d.drawing_pages_failed || 0)} lang={lang} />
      <BoqTable boq={d.boq} confidence={d.boq_confidence} lang={lang} />
      {d.boq_withheld ? <p className="mt-3 text-[12.5px] text-muted-foreground">{t.boqHeld}</p> : null}
      {/* A question stays possible after a quote exists (audit 21 Sep 2026, finding 30): the answer reaches every
          matched supplier and a supplier revises its quote on it. Only a concluded or revealed job closes it. */}
      <ClarifyThread inquiryId={d.id} token={token} lang={lang} canAsk={canQuote} />
      {q ? <p className="mt-4 text-[13px] text-foreground">{t.quoted}: <span className="font-mono tabular-nums"><Ltr>{aedIn(lang, q.quote_amount)}</Ltr></span></p> : null}
      {canQuote ? (
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <Button onClick={() => onQuote(d.id)}>{t.quote}</Button>
          {renderQuoteForm ? <Button variant="ghost" aria-expanded={form} onClick={() => setForm(!form)}>{form ? t.closeForm : t.form}</Button> : null}
        </div>
      ) : null}
      {sent ? <p role="status" className="mt-3 text-[13px] text-foreground">{sent === 'held' ? t.sentHeld : t.sentOk}</p> : null}
      {form && renderQuoteForm ? renderQuoteForm({ ...d, quote: q ?? null, quotes: d.quotes }, (r) => { setForm(false); setSent(r?.held ? 'held' : 'ok'); load(); }) : null}
    </div>
  );
}

export function InquiriesTab({ token, lang, focus = null, onFocused, onQuote, renderQuoteForm }: {
  token: string; lang: Lang; focus?: string | null; onFocused?: () => void; onQuote: (id: string) => void;
  renderQuoteForm?: (inq: LegacyInquiry, done: (r?: { held?: boolean }) => void) => React.ReactNode;
}) {
  const t = COPY[lang];
  const [list, setList] = useState<InquiryListItem[] | null>(null);
  const [err, setErr] = useState('');
  const [open, setOpen] = useState<string | null>(null);
  const reduce = useReducedMotion();
  useEffect(() => { let on = true; qr.inquiries(token).then((j) => { if (!on) return; if (failed(j)) setErr(srvMsg(lang, j, t.err)); else setList(j.inquiries); }); return () => { on = false; }; }, [token, lang, t.err]);
  useEffect(() => {
    if (!focus || !list) return;
    setOpen(focus);
    // reduce ? 'auto' : 'smooth' — the gate every other scrollIntoView in the portal already uses.
    requestAnimationFrame(() => document.getElementById('qd-inq-' + focus)?.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' }));
    onFocused?.();
  }, [focus, list, onFocused, reduce]);

  if (err) return <Card role="alert" className="qd-panel p-5 text-[13px]">{err}</Card>;
  if (!list) return <Card className="qd-panel p-5 text-[13px] text-muted-foreground" aria-busy="true">{t.loading}</Card>;
  if (!list.length) return <Card className="qd-panel p-5"><h2 className="text-[15.5px] font-bold text-foreground">{t.empty}</h2><p className="mt-1 max-w-[68ch] text-[13px] leading-relaxed text-muted-foreground">{t.emptySub}</p></Card>;
  return (
    <section aria-labelledby="qd-inq-h">
      <div className="mb-3">
        <h2 id="qd-inq-h" className="text-[15.5px] font-bold tracking-[-.018em] text-foreground">{t.title}</h2>
        <p className="mt-0.5 max-w-[68ch] text-[13px] text-muted-foreground">{t.sub}</p>
      </div>
      <ul className="flex flex-col gap-2.5">
        {list.map((i) => {
          const on = open === i.id;
          const q = i.quotes[0];
          const st = i.review ? REVIEW_STATE[i.review.state] : null;
          return (
            <li key={i.id} id={'qd-inq-' + i.id} className={cn('qd-panel overflow-hidden p-0 transition-colors', on && 'border-primary/40')}>
              <button type="button" aria-expanded={on} aria-controls={'qd-inq-d-' + i.id} onClick={() => setOpen(on ? null : i.id)}
                className="grid w-full grid-cols-[auto_1fr_auto] items-start gap-x-4 gap-y-1 px-4 py-3.5 text-start focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring sm:px-5">
                <span className="pt-0.5">
                  <span className="block font-mono text-[10.5px] uppercase text-muted-foreground">{t.job}</span>
                  <span className="block font-mono text-[14px] font-semibold tabular-nums text-primary"><Ltr>{i.job_no}</Ltr></span>
                </span>
                <span className="min-w-0">
                  <span className="block truncate text-[14.5px] font-semibold text-foreground">{categoryLabel(i.category || '', lang) || '—'} <span className="font-normal text-muted-foreground">· {emirateLabel(lang, i.emirate || '')}</span></span>
                  <span className="mt-0.5 block text-[12px] text-muted-foreground">
                    {day(i.created_at, lang)}
                    {i.boq_lines ? ' · ' + t.boq(i.boq_lines) : ''}
                    {i.drawing_pages_expected || i.drawing_pages ? ' · ' + t.drawings(i.drawing_pages_expected || i.drawing_pages) : ''}
                    {i.drawing_pages_failed ? ' · ' + ws(lang, 'rfq_pages_row_missing', { n: i.drawing_pages_failed }) : ''}
                  </span>
                </span>
                <span className="flex flex-col items-end gap-1">
                  {i.you_won ? <Badge variant="ok">{t.won}</Badge> : i.concluded ? <Badge variant="secondary">{lang === 'ar' ? 'منتهٍ' : 'Concluded'}</Badge> : null}
                  {st ? <Badge variant={st.tone}>{lang === 'ar' ? st.ar : st.en}</Badge> : q ? <span className="font-mono text-[12px] tabular-nums text-foreground"><Ltr>{aedIn(lang, q.quote_amount)}</Ltr></span> : null}
                  <span aria-hidden className="text-[11.5px] text-muted-foreground">{on ? t.close : t.open}</span>
                </span>
              </button>
              {on ? <div id={'qd-inq-d-' + i.id}><Detail token={token} lang={lang} id={i.id} onQuote={onQuote} renderQuoteForm={renderQuoteForm} /></div> : null}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
