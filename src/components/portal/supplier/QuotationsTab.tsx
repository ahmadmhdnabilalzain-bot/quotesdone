'use client';
// QUOTATIONS SUBMITTED (founder, 15 Sep 2026). The same inquiries, by job number; opening one opens the
// conversation with the sales engineer (./QuoteReviewChat) where the quotation is attached, reviewed,
// adjusted and submitted. A quote the hold desk is holding for exact details shows its panel here too
// (./SpecHold — the two ways out: fill in the details, or send a revised quotation in the chat).
import { useCallback, useEffect, useRef, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { categoryLabel } from '@/lib/categoryLabel';
import { emirateLabel, srvMsg } from './serverCopy';
import { SpecHoldPanel } from './SpecHold';
import { QuoteReviewChat } from './QuoteReviewChat';
import { failed, qr, REVIEW_STATE, type InquiryListItem, type Lang } from './quoteReviewApi';

const COPY = {
  en: {
    title: 'Quotations submitted', sub: 'Open a job to send your quotation to our sales engineer, answer their review, and submit it.',
    empty: 'No inquiries to quote yet', emptySub: 'Each inquiry you receive appears here by its job number, ready for your quotation.',
    job: 'Job No.', notStarted: 'No quotation yet', open: 'Open conversation', close: 'Close', inquiry: 'Read the inquiry',
    option: (n: number) => `Option ${n}`, loading: 'Loading…', err: 'Something went wrong. Please try again.',
    qst: { draft: 'Held — not sent yet', submitted: 'Sent to the customer', accepted: 'Customer revealed you', withdrawn: 'Withdrawn', expired: 'Expired' } as Record<string, string>,
  },
  ar: {
    title: 'العروض المقدّمة', sub: 'افتح طلبًا لإرسال عرض سعرك إلى مهندس المبيعات، والرد على مراجعته، وتقديمه.',
    empty: 'لا توجد طلبات للتسعير بعد', emptySub: 'يظهر هنا كل طلب يصلك برقمه، جاهزًا لعرض سعرك.',
    job: 'رقم الطلب', notStarted: 'لا يوجد عرض بعد', open: 'افتح المحادثة', close: 'أغلق', inquiry: 'اقرأ الطلب',
    option: (n: number) => `الخيار ${n}`, loading: 'جارٍ التحميل…', err: 'حدث خطأ. يُرجى المحاولة مرة أخرى.',
    qst: { draft: 'محجوز — لم يُرسل بعد', submitted: 'أُرسل إلى العميل', accepted: 'كشف العميل عن عرضك', withdrawn: 'مسحوب', expired: 'منتهي الصلاحية' } as Record<string, string>,
  },
};
const Ltr = ({ children }: { children: React.ReactNode }) => <bdi dir="ltr">{children}</bdi>;
const aed = (n: number | null | undefined) => 'AED ' + Number(n || 0).toLocaleString('en-AE', { maximumFractionDigits: 0 });

export function QuotationsTab({ token, lang, focus = null, onFocused, openInquiry }: { token: string; lang: Lang; focus?: string | null; onFocused?: () => void; openInquiry: (id: string) => void }) {
  const t = COPY[lang];
  const [list, setList] = useState<InquiryListItem[] | null>(null);
  const [err, setErr] = useState('');
  const [open, setOpen] = useState<string | null>(null);
  const alive = useRef(true);
  const load = useCallback(() => qr.inquiries(token).then((j) => { if (!alive.current) return; if (failed(j)) setErr(srvMsg(lang, j, t.err)); else setList(j.inquiries); }), [token, lang, t.err]);
  useEffect(() => { alive.current = true; load(); return () => { alive.current = false; }; }, [load]);
  useEffect(() => {
    if (!focus || !list) return;
    setOpen(focus);
    requestAnimationFrame(() => document.getElementById('qd-qt-' + focus)?.scrollIntoView({ behavior: 'smooth', block: 'start' }));
    onFocused?.();
  }, [focus, list, onFocused]);

  if (err) return <Card role="alert" className="qd-panel p-5 text-[13px]">{err}</Card>;
  if (!list) return <Card className="qd-panel p-5 text-[13px] text-muted-foreground" aria-busy="true">{t.loading}</Card>;
  if (!list.length) return <Card className="qd-panel p-5"><h2 className="text-[15.5px] font-bold text-foreground">{t.empty}</h2><p className="mt-1 max-w-[68ch] text-[13px] leading-relaxed text-muted-foreground">{t.emptySub}</p></Card>;
  return (
    <section aria-labelledby="qd-qt-h">
      <div className="mb-3">
        <h2 id="qd-qt-h" className="text-[15.5px] font-bold tracking-[-.018em] text-foreground">{t.title}</h2>
        <p className="mt-0.5 max-w-[68ch] text-[13px] text-muted-foreground">{t.sub}</p>
      </div>
      <ul className="flex flex-col gap-2.5">
        {list.map((i) => {
          const on = open === i.id;
          const st = i.review ? REVIEW_STATE[i.review.state] : null;
          return (
            <li key={i.id} id={'qd-qt-' + i.id} className={cn('qd-panel overflow-hidden px-4 py-3.5 sm:px-5', on && 'border-primary/40')}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="flex min-w-0 items-start gap-4">
                  <span>
                    <span className="block font-mono text-[10.5px] uppercase text-muted-foreground">{t.job}</span>
                    <span className="block font-mono text-[14px] font-semibold tabular-nums text-primary"><Ltr>{i.job_no}</Ltr></span>
                  </span>
                  <span className="min-w-0">
                    <span className="block truncate text-[14.5px] font-semibold text-foreground">{categoryLabel(i.category || '', lang) || '—'} <span className="font-normal text-muted-foreground">· {emirateLabel(lang, i.emirate || '')}</span></span>
                    <span className="mt-1 flex flex-wrap gap-1.5">
                      {st ? <Badge variant={st.tone}>{lang === 'ar' ? st.ar : st.en}</Badge> : null}
                      {i.quotes.map((q) => (
                        <span key={q.id} className="inline-flex items-center gap-1.5 rounded-chip border border-[var(--line2)] px-2 py-0.5 text-[11.5px] text-foreground">
                          {i.quotes.length > 1 ? t.option(q.option_no) + ' · ' : ''}<span className="font-mono tabular-nums"><Ltr>{aed(q.quote_amount)}</Ltr></span>
                          <span className="text-muted-foreground">· {t.qst[q.status] || q.status}</span>
                        </span>
                      ))}
                      {!st && !i.quotes.length ? <span className="text-[12px] text-muted-foreground">{t.notStarted}</span> : null}
                    </span>
                  </span>
                </div>
                <div className="flex flex-wrap gap-2">
                  <Button size="sm" variant="ghost" onClick={() => openInquiry(i.id)}>{t.inquiry}</Button>
                  <Button size="sm" variant={on ? 'outline' : 'default'} aria-expanded={on} aria-controls={'qd-qt-c-' + i.id} onClick={() => setOpen(on ? null : i.id)}>{on ? t.close : t.open}</Button>
                </div>
              </div>
              {i.quotes.filter((q) => q.on_hold).map((q) => (
                <SpecHoldPanel key={q.id} quoteId={q.id} lang={lang} token={token} onChanged={load} onResubmit={() => setOpen(i.id)} title={i.quotes.length > 1 ? t.option(q.option_no) : null} />
              ))}
              {on ? <div id={'qd-qt-c-' + i.id}><QuoteReviewChat token={token} lang={lang} inquiryId={i.id} onChanged={load} /></div> : null}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
