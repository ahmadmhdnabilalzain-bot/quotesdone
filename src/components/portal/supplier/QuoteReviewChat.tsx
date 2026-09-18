'use client';
// THE QUOTATION CONVERSATION WITH THE SALES ENGINEER (founder, 15 Sep 2026: "this is the most
// important part in the whole supplier portal").
//
// The supplier attaches a quotation; the sales engineer reviews it at once and either approves it for
// submission or lists the adjustments and clarifications line by line; the supplier answers in text or
// with a revised file; then chooses to upload a new version or have the engineer generate the
// standardised quotation; and the quotation is submitted to the job. The conversation, its state and
// every rule live on the server (supplier_api quote_review_flow.ts) — this component only shows the
// thread the server returns and sends what the supplier does, so a mobile app drives the same flow.
//
// "Reviewing your quotation, please wait…" shows while the upload is in flight, and while the server
// says the review is running (it is polled every two seconds until it is not).
import { useCallback, useEffect, useRef, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { srvMsg } from './serverCopy';
import { failed, fileToBase64, qr, REVIEW_STATE, type Issue, type Lang, type MessageView, type ThreadView } from './quoteReviewApi';

const ACCEPT = 'application/pdf,.pdf,.xlsx,.xls,.csv,.ods,.doc,.docx,.odt,.rtf,.txt,.eml,.msg,.zip';
const EASE = [0.16, 1, 0.3, 1] as const;
const COPY = {
  en: {
    engineer: 'Sales engineer', you: 'You', attach: 'Attach quotation', attachNew: 'Attach a revised file', send: 'Send', sending: 'Sending…',
    placeholder: 'Reply to the sales engineer — for example "validity 30 days" or "BOQ line 3 excluded — by others"',
    reviewing: 'Reviewing your quotation, please wait…', reviewingSub: 'Checking every BOQ line, quantities, AED prices, VAT, validity, delivery and specifications.',
    generate: 'Generate it for me', reupload: 'I will upload a new version', submit: (job: string) => `Submit to Job ${job}`, submitting: 'Submitting…',
    open: (n: number) => `${n} open point${n === 1 ? '' : 's'}`, tracked: 'Each stays open until you answer it.',
    adjustment: 'Adjustment', clarification: 'Clarification', choice: 'Your choice', line: (n: number) => `Your line ${n}`, boq: (n: number) => `BOQ line ${n}`,
    closed: 'This conversation is closed.', submitted: 'Submitted to the job. The customer sees your quotation without your name until they reveal it.',
    download: 'Download', pdf: 'Open the standardised quotation (PDF)', loading: 'Opening the conversation…', err: 'Something went wrong. Please try again.',
    fileTip: 'PDF with text, Excel, Word, CSV or email — up to 10 MB.', label: 'Message to the sales engineer', log: 'Conversation with the sales engineer',
  },
  ar: {
    engineer: 'مهندس المبيعات', you: 'أنت', attach: 'أرفق عرض السعر', attachNew: 'أرفق ملفًا معدّلًا', send: 'إرسال', sending: 'جارٍ الإرسال…',
    placeholder: 'اكتب ردك لمهندس المبيعات — مثل "الصلاحية 30 يومًا" أو "البند 3 مستثنى — من قبل الغير"',
    reviewing: 'جارٍ مراجعة عرض سعرك، يُرجى الانتظار…', reviewingSub: 'أتحقق من كل بنود جدول الكميات والكميات والأسعار بالدرهم والضريبة والصلاحية والتسليم والمواصفات.',
    generate: 'أعدّه لي', reupload: 'سأرفع نسخة جديدة', submit: (job: string) => `قدّم إلى الطلب ${job}`, submitting: 'جارٍ التقديم…',
    open: (n: number) => (n === 1 ? 'نقطة واحدة مفتوحة' : n === 2 ? 'نقطتان مفتوحتان' : `${n} نقاط مفتوحة`), tracked: 'تبقى كل نقطة مفتوحة إلى أن تجيب عنها.',
    adjustment: 'تعديل', clarification: 'استيضاح', choice: 'اختيارك', line: (n: number) => `بندك ${n}`, boq: (n: number) => `البند ${n} من الجدول`,
    closed: 'أُغلقت هذه المحادثة.', submitted: 'قُدّم العرض إلى الطلب. يرى العميل عرضك دون اسمك إلى أن يكشف عنه.',
    download: 'تنزيل', pdf: 'افتح العرض الموحّد (PDF)', loading: 'جارٍ فتح المحادثة…', err: 'حدث خطأ. يُرجى المحاولة مرة أخرى.',
    fileTip: 'PDF نصي أو Excel أو Word أو CSV أو بريد إلكتروني — حتى 10 ميغابايت.', label: 'رسالة إلى مهندس المبيعات', log: 'المحادثة مع مهندس المبيعات',
  },
};
const Ltr = ({ children }: { children: React.ReactNode }) => <bdi dir="ltr">{children}</bdi>;
/** Only an https link is rendered or opened — never a javascript: or data: URL from a response. */
const safeUrl = (u: string | null | undefined) => (u && /^https:\/\//i.test(u) ? u : null);
const time =(d: string, lang: Lang) => new Date(d).toLocaleTimeString(lang === 'ar' ? 'ar-AE' : 'en-GB', { hour: '2-digit', minute: '2-digit' });

function Reviewing({ lang }: { lang: Lang }) {
  const t = COPY[lang]; const reduce = useReducedMotion();
  return (
    <motion.div role="status" aria-live="polite" className="flex max-w-[560px] items-start gap-3 rounded-2xl rounded-ss-sm border border-primary/30 bg-primary/[.06] px-4 py-3"
      initial={reduce ? false : { opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={reduce ? undefined : { opacity: 0 }} transition={{ duration: 0.22, ease: EASE }}>
      <span aria-hidden className="mt-1.5 flex gap-1">
        {[0, 1, 2].map((i) => (
          <motion.span key={i} className="h-1.5 w-1.5 rounded-full bg-primary"
            animate={reduce ? undefined : { opacity: [0.25, 1, 0.25], y: [0, -2, 0] }}
            transition={reduce ? undefined : { duration: 1.1, repeat: Infinity, delay: i * 0.16, ease: 'easeInOut' }} />
        ))}
      </span>
      <span className="min-w-0">
        <span className="block text-[13.5px] font-semibold text-foreground">{t.reviewing}</span>
        <span className="mt-0.5 block text-[12px] leading-relaxed text-muted-foreground">{t.reviewingSub}</span>
      </span>
    </motion.div>
  );
}

function IssueList({ issues, lang }: { issues: Issue[]; lang: Lang }) {
  const t = COPY[lang];
  return (
    <ol className="mt-2 flex flex-col gap-1.5">
      {issues.map((x, i) => (
        <li key={`${x.code}:${x.line_no ?? ''}:${x.boq_line ?? ''}:${x.attr ?? ''}`} className="flex items-start gap-2.5 rounded-md border border-[var(--line)] bg-background/50 px-2.5 py-2 text-[13px] leading-relaxed">
          <span className="mt-px font-mono text-[11.5px] tabular-nums text-muted-foreground"><Ltr>{String(i + 1).padStart(2, '0')}</Ltr></span>
          <span className="min-w-0 flex-1">
            <span className="mb-1 flex flex-wrap gap-1.5">
              <span className={cn('rounded-chip border px-1.5 py-px text-[11px] font-semibold', x.kind === 'adjustment' ? 'border-warn/40 bg-warn/10 text-warn-fg' : 'border-primary/40 bg-primary/10 text-primary')}>{x.kind === 'adjustment' ? t.adjustment : t.clarification}</span>
              {x.boq_line ? <span className="rounded-chip border border-[var(--line2)] px-1.5 py-px text-[11px] text-muted-foreground">{t.boq(x.boq_line)}</span> : null}
              {x.line_no && !x.boq_line ? <span className="rounded-chip border border-[var(--line2)] px-1.5 py-px text-[11px] text-muted-foreground">{t.line(x.line_no)}</span> : null}
            </span>
            <span className="text-foreground">{lang === 'ar' ? x.ar : x.en}</span>
          </span>
        </li>
      ))}
    </ol>
  );
}

function Bubble({ m, lang, token }: { m: MessageView; lang: Lang; token: string }) {
  const t = COPY[lang]; const eng = m.role === 'sales_engineer';
  const body = eng ? ((lang === 'ar' ? m.body_ar : m.body_en) || m.body_en || '') : (m.text || '');
  // An engineer's review is "header\n\n1. …\n2. …\n\nfooter"; the points render as a list from `issues`.
  const parts = eng && m.issues && m.issues.length ? body.split('\n\n') : null;
  const [opening, setOpening] = useState(false);
  const openPdf = async (quoteId: string) => {
    setOpening(true);
    const j = await qr.quotePdf(token, quoteId, lang).catch(() => null);
    setOpening(false);
    const u = safeUrl(j && j.url ? String(j.url) : null);
    if (u) window.open(u, '_blank', 'noopener');
  };
  return (
    <li className={cn('flex flex-col gap-1', eng ? 'items-start' : 'items-end')}>
      <span className="px-1 text-[11.5px] text-muted-foreground">{eng ? t.engineer : t.you} · <Ltr>{time(m.created_at, lang)}</Ltr></span>
      <div dir="auto" className={cn('max-w-[min(620px,100%)] rounded-2xl px-4 py-3 text-[13.5px] leading-relaxed',
        eng ? 'rounded-ss-sm border border-[var(--line2)] bg-card text-foreground' : 'rounded-se-sm bg-primary/15 text-foreground',
        m.kind === 'submitted' && 'border-primary/50 bg-primary/10')}>
        {parts ? <>
          <p className="whitespace-pre-line">{parts[0]}</p>
          <IssueList issues={m.issues!} lang={lang} />
          {/* parts[1] is the numbered list the IssueList above renders; everything after it is the
              engineer's closing text. Rendering only the LAST segment dropped any middle paragraph. */}
          {parts.slice(2).map((p, i) => <p key={i} className="mt-2 whitespace-pre-line text-[12.5px] text-muted-foreground">{p}</p>)}
        </> : body ? <p className="whitespace-pre-line">{body}</p> : null}
        {m.attachments.map((a) => (
          <div key={`${a.kind}:${a.name}:${a.quote_id ?? ''}`} className={cn('flex flex-wrap items-center gap-2', body ? 'mt-2.5' : '')}>
            <span aria-hidden className="rounded-sm border border-[var(--line2)] px-1.5 py-0.5 font-mono text-[10.5px] uppercase text-muted-foreground">{(a.name.split('.').pop() || 'file').slice(0, 4)}</span>
            <span className="min-w-0 truncate text-[12.5px] text-foreground"><Ltr>{a.name}</Ltr></span>
            {a.kind === 'quotation_file' && safeUrl(a.url) ? <a className="text-[12.5px] font-semibold text-primary underline-offset-2 hover:underline" href={safeUrl(a.url)!} target="_blank" rel="noopener noreferrer">{t.download}</a> : null}
            {a.kind === 'standard_quote' && a.quote_id ? <Button size="sm" variant="outline" disabled={opening} onClick={() => openPdf(a.quote_id!)}>{t.pdf}</Button> : null}
          </div>
        ))}
      </div>
    </li>
  );
}

export function QuoteReviewChat({ token, lang, inquiryId, onChanged }: { token: string; lang: Lang; inquiryId: string; onChanged?: () => void }) {
  const t = COPY[lang];
  const [th, setTh] = useState<ThreadView | null>(null);
  const [err, setErr] = useState('');
  const [text, setText] = useState('');
  const [busy, setBusy] = useState<null | 'upload' | 'send' | 'choose' | 'submit'>(null);
  const fileRef = useRef<HTMLInputElement | null>(null);
  const endRef = useRef<HTMLDivElement | null>(null);
  const alive = useRef(true);
  // Every request takes a number; only the answer to the latest one is shown, so a poll that was
  // already in flight can never overwrite what a newer action returned (React review, 15 Sep 2026).
  const seq = useRef(0);

  const adopt = useCallback((j: unknown, n: number) => {
    if (!alive.current || n !== seq.current) return;
    if (failed(j as ThreadView)) { setErr(srvMsg(lang, j, t.err)); return; }
    const v = j as ThreadView; setTh(v); setErr(v.notice ? v.notice.message : '');
  }, [lang, t.err]);

  useEffect(() => {
    alive.current = true;
    (async () => {
      const n = ++seq.current;
      const j = await qr.thread(token, inquiryId, lang);
      if (!failed(j) && j.state === 'none' && j.can_write && n === seq.current) { const m = ++seq.current; adopt(await qr.start(token, inquiryId, lang), m); }
      else adopt(j, n);
    })();
    return () => { alive.current = false; };
  }, [token, inquiryId, lang, adopt]);

  // The server says a review is running (e.g. started from another device): poll until it is not.
  useEffect(() => {
    if (!th || !th.reviewing || busy) return;
    const h = setInterval(async () => { const n = ++seq.current; adopt(await qr.thread(token, inquiryId, lang), n); }, 2000);
    return () => clearInterval(h);
  }, [th, busy, token, inquiryId, lang, adopt]);

  const count = th ? th.messages.length : 0;
  useEffect(() => { endRef.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); }, [count, busy]);

  const run = async (kind: NonNullable<typeof busy>, fn: () => Promise<unknown>) => {
    setBusy(kind); setErr('');
    const n = ++seq.current;
    const started = Date.now();
    const j = await fn().catch(() => ({ error: 'network' }));
    // Long enough to read the status line, never longer than the review itself when it is slow.
    if (kind === 'upload') { const wait = 900 - (Date.now() - started); if (wait > 0) await new Promise((r) => setTimeout(r, wait)); }
    if (!alive.current) return;
    setBusy(null); adopt(j, n);
    if (onChanged && !failed(j as ThreadView)) onChanged();
  };
  const onFile = async (f: File | undefined) => {
    if (!f) return;
    if (f.size > 10 * 1024 * 1024) { setErr(lang === 'ar' ? 'الملف أكبر من 10 ميغابايت.' : 'That file is larger than 10 MB.'); return; }
    const b64 = await fileToBase64(f);
    const note = text.trim(); setText('');
    await run('upload', () => qr.upload(token, inquiryId, { b64, filename: f.name, mime: f.type || '' }, lang, note || undefined));
    if (fileRef.current) fileRef.current.value = '';
  };
  const send = async () => { const v = text.trim(); if (!v) return; setText(''); await run('send', () => qr.message(token, inquiryId, v, lang)); };

  if (!th) return <div className="rounded-panel border border-[var(--line)] p-4 text-[13px] text-muted-foreground" aria-busy="true">{err || t.loading}</div>;
  const st = REVIEW_STATE[th.state];
  const reviewing = busy === 'upload' || th.reviewing;
  const openPts = th.open_requests.filter((q) => q.kind !== 'choice');
  const closed = th.state === 'submitted' || th.state === 'closed';

  return (
    <section aria-label={t.log} className="mt-4 overflow-hidden rounded-panel border border-[var(--line)] bg-background/40">
      <header className="flex flex-wrap items-center justify-between gap-2 border-b border-[var(--line)] px-4 py-3">
        <div className="flex min-w-0 items-center gap-2.5">
          <span aria-hidden className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-primary/15 font-mono text-[11px] font-bold text-primary">SE</span>
          <div className="min-w-0">
            <div className="text-[13.5px] font-semibold text-foreground">{t.engineer} · QuotesDone</div>
            <div className="font-mono text-[11.5px] tabular-nums text-muted-foreground">{lang === 'ar' ? 'الطلب ' : 'Job '}<Ltr>{th.job_no}</Ltr>{th.file ? <> · <Ltr>{th.file.name}</Ltr></> : null}</div>
          </div>
        </div>
        <Badge variant={st.tone}>{lang === 'ar' ? st.ar : st.en}</Badge>
      </header>

      <div className="max-h-[60vh] overflow-y-auto px-3 py-4 sm:px-4">
        <ul role="log" aria-live="polite" aria-label={t.log} className="flex flex-col gap-3.5">
          {th.messages.map((m) => <Bubble key={m.id} m={m} lang={lang} token={token} />)}
        </ul>
        <AnimatePresence>{reviewing ? <div className="mt-3.5"><Reviewing lang={lang} /></div> : null}</AnimatePresence>
        <div ref={endRef} />
      </div>

      {openPts.length > 0 && !closed ? (
        <div className="border-t border-[var(--line)] bg-warn/[.06] px-4 py-2.5 text-[12.5px]">
          <span className="font-semibold text-foreground">{t.open(openPts.length)}</span>
          <span className="text-muted-foreground"> — {t.tracked}</span>
        </div>
      ) : null}

      <div className="border-t border-[var(--line)] px-3 py-3 sm:px-4">
        {err ? <div role="alert" className="mb-2 text-[13px] text-danger-fg">{err}</div> : null}
        {closed ? (
          <div role="status" className="text-[13px] text-muted-foreground">{th.state === 'submitted' ? t.submitted : t.closed}</div>
        ) : (
          <>
            {th.can_choose ? (
              <div className="mb-3 flex flex-wrap gap-2" role="group" aria-label={t.choice}>
                <Button disabled={!!busy} onClick={() => run('choose', () => qr.choose(token, inquiryId, 'generate', lang))}>{busy === 'choose' ? t.submitting : t.generate}</Button>
                <Button variant="outline" disabled={!!busy} onClick={() => run('choose', () => qr.choose(token, inquiryId, 'reupload', lang))}>{t.reupload}</Button>
              </div>
            ) : null}
            {th.can_submit ? (
              <div className="mb-3"><Button disabled={!!busy} onClick={() => run('submit', () => qr.submit(token, inquiryId, lang))}>{busy === 'submit' ? t.submitting : t.submit(th.job_no)}</Button></div>
            ) : null}
            <label className="sr-only" htmlFor={'qd-rv-' + inquiryId}>{t.label}</label>
            <textarea id={'qd-rv-' + inquiryId} value={text} rows={2} maxLength={2000} disabled={!th.can_write || !!busy || th.reviewing}
              placeholder={t.placeholder} onChange={(e) => setText(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); send(); } }}
              className="flex w-full resize-y rounded-md border border-input bg-transparent px-3 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:opacity-60" />
            <div className="mt-2 flex flex-wrap items-center justify-between gap-2">
              <div className="flex flex-wrap items-center gap-2">
                <input ref={fileRef} type="file" accept={ACCEPT} className="sr-only" tabIndex={-1} aria-label={th.file ? t.attachNew : t.attach} id={'qd-rv-file-' + inquiryId} onChange={(e) => onFile(e.target.files?.[0])} disabled={!th.can_upload || !!busy} />
                <Button variant={th.file ? 'outline' : 'default'} disabled={!th.can_upload || !!busy || th.reviewing} onClick={() => fileRef.current?.click()}>{th.file ? t.attachNew : t.attach}</Button>
                <span className="text-[11.5px] text-muted-foreground">{t.fileTip}</span>
              </div>
              <Button variant="outline" disabled={!text.trim() || !th.can_write || !!busy || th.reviewing} onClick={send}>{busy === 'send' ? t.sending : t.send}</Button>
            </div>
          </>
        )}
      </div>
    </section>
  );
}
