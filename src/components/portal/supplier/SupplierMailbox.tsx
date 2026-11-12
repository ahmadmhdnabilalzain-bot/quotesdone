'use client';
// MESSAGES — the supplier's mailbox with each customer, behind the reveal (15 Sep 2026, sales_engineer).
//
// Founder's spec: a mailbox between the supplier and the customer, opened only after the customer paid the
// reveal fee for that job; before any win the tab says so, professionally, in both languages. The gate is
// the server's (messages_api `mailbox` returns gate.open; `thread` and `send` re-check the reveal on every
// call; messages/chat_threads carry no client grant — see supabase/functions/messages_api/mailbox.ts). This
// component only renders what it is told. The revealed jobs (Projects: the customer's contact and the
// 5-working-day rule) are passed in by the portal as `jobs`, so their one implementation is kept.
// This replaces the Messages/Thread pair that lived inside SupplierPortal.tsx.
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Lock, MessageSquare } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { call } from './api';
import { firstRead } from './tabPrefetch';
import { ws } from './workspaceCopy';

type Lang = 'en' | 'ar' | string;
type Thread = { inquiry_id: string; supplier_id: number; subject: string | null; respond_by: string | null; acknowledged_at: string | null; chat_status: string; last: string | null; last_at: string | null; unread: number };
type Box = { ok: boolean; gate: { open: boolean; revealed_jobs: number }; threads: Thread[]; unread_total: number };

const date = (d: string | null, lang: Lang) => (d ? new Date(d).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '');
const statusLabel = (lang: Lang, s: string) => ws(lang, 'mb_status_' + (['open', 'none', 'banned', 'closed'].includes(s) ? s : 'closed'));

export default function SupplierMailbox({ token, lang, openInquiry = null, onOpened, jobs, goTo }:
  { token: string; lang: Lang; openInquiry?: string | null; onOpened?: () => void; jobs?: (openChat: (inquiryId: string) => void) => ReactNode; goTo?: (tab: string) => void }) {
  const [box, setBox] = useState<Box | null>(null);
  const [err, setErr] = useState(false);
  const [open, setOpen] = useState<Thread | null>(null);
  // A tab switch unmounts this; an answer arriving afterwards must not write state.
  const live = useRef(true);
  useEffect(() => { live.current = true; return () => { live.current = false; }; }, []);
  const first = useRef(true);
  const load = () => { setErr(false); const f = first.current; first.current = false; (f ? firstRead(token, 'sup_tab:mailbox') : call('messages_api', { action: 'mailbox' }, token)).then((j) => { if (live.current) { if (j && j.ok) setBox(j); else setErr(true); } }).catch(() => { if (live.current) setErr(true); }); };
  useEffect(() => { load(); }, [token]);
  // Opened from a revealed-job card, or from the portal with an inquiry in hand.
  const openChat = (id: string) => { const th = box?.threads.find((x) => x.inquiry_id === id); if (th) setOpen(th); };
  useEffect(() => { if (openInquiry && box) { openChat(openInquiry); onOpened?.(); } }, [openInquiry, box]);

  if (err) return <section className="qd-panel p-5" role="alert"><p className="text-[13px] text-muted-foreground">{ws(lang, 'mb_err')}</p><Button className="mt-3" size="sm" onClick={load}>{ws(lang, 'mb_retry')}</Button></section>;
  if (!box) return <section className="qd-panel p-5 text-[13px] text-muted-foreground" aria-busy="true">{ws(lang, 'mb_loading')}</section>;

  if (!box.gate.open) return (
    <section aria-labelledby="qd-mb-locked" className="qd-panel qd-lit p-5 sm:p-7">
      <div className="flex flex-col gap-5 sm:flex-row sm:items-start">
        <span aria-hidden className="grid h-12 w-12 shrink-0 place-items-center rounded-full border border-border bg-secondary/40 text-primary"><Lock className="h-5 w-5" /></span>
        <div className="min-w-0 flex-1">
          <h2 id="qd-mb-locked" className="font-head text-h3 tracking-snug text-foreground">{ws(lang, 'mb_locked_h')}</h2>
          <p className="mt-2 max-w-[62ch] text-[13.5px] leading-[1.7] text-muted-foreground">{ws(lang, 'mb_locked_body')}</p>
          <ol className="mt-4 flex flex-col gap-2.5">
            {['mb_step1', 'mb_step2', 'mb_step3'].map((k, i) => (
              <li key={k} className="flex items-start gap-3 text-[13px] text-foreground">
                <span aria-hidden className="grid h-6 w-6 shrink-0 place-items-center rounded-full border border-primary/40 font-mono text-[11px] text-primary"><bdi>{i + 1}</bdi></span>
                <span className="pt-0.5">{ws(lang, k)}</span>
              </li>
            ))}
          </ol>
          {goTo && <Button className="mt-5" variant="outline" onClick={() => goTo('rfqs')}>{ws(lang, 'mb_locked_cta')}</Button>}
        </div>
      </div>
    </section>
  );

  if (open) return <ThreadView token={token} lang={lang} th={open} onBack={() => { setOpen(null); load(); }} />;

  return (
    <div className="flex flex-col gap-5">
      {jobs && <section aria-label={ws(lang, 'mb_jobs_h')}>{jobs(openChat)}</section>}
      <section aria-labelledby="qd-mb-threads">
        <h2 id="qd-mb-threads" className="mb-2.5 px-1 text-[12px] font-bold uppercase tracking-[.04em] text-muted-foreground">{ws(lang, 'mb_threads_h')}</h2>
        <ul className="flex flex-col gap-2.5">
          {box.threads.map((th) => {
            const late = !th.acknowledged_at && th.respond_by && new Date(th.respond_by).getTime() < Date.now();
            return (
              <li key={th.inquiry_id}>
                <button type="button" onClick={() => setOpen(th)} className="qd-panel qd-panel-hover flex min-h-11 w-full items-start justify-between gap-3 p-4 text-start focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring">
                  <span className="flex min-w-0 items-start gap-3">
                    <MessageSquare aria-hidden className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
                    <span className="min-w-0">
                      <b className="text-[13.5px] text-foreground">{ws(lang, 'mb_customer')}</b>{th.subject ? <> · <bdi className="text-[13px] text-foreground/80">{th.subject}</bdi></> : null}
                      <span dir="auto" className="mt-0.5 block truncate text-[12.5px] text-muted-foreground">{th.last || ws(lang, 'mb_no_msgs')}</span>
                    </span>
                  </span>
                  <span className="flex shrink-0 flex-col items-end gap-1">
                    {th.unread ? <Badge variant="default"><bdi>{ws(lang, 'mb_unread', { n: th.unread })}</bdi></Badge> : null}
                    {th.acknowledged_at ? <Badge variant="ok">{ws(lang, 'mb_acked')}</Badge>
                      : th.respond_by ? <Badge variant={late ? 'destructive' : 'secondary'}>{ws(lang, late ? 'mb_overdue' : 'mb_respond_by', { date: date(th.respond_by, lang) })}</Badge> : null}
                    <span className="text-[11.5px] text-muted-foreground">{statusLabel(lang, th.chat_status)}</span>
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      </section>
    </div>
  );
}

function ThreadView({ token, lang, th, onBack }: { token: string; lang: Lang; th: Thread; onBack: () => void }) {
  const [data, setData] = useState<any>(null);
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');
  const live = useRef(true);
  useEffect(() => { live.current = true; return () => { live.current = false; }; }, []);
  const load = () => call('messages_api', { action: 'thread', inquiry_id: th.inquiry_id, supplier_id: th.supplier_id }, token)
    .then((j) => { if (live.current) setData(j); }).catch(() => { if (live.current) setData({ error: true }); });
  useEffect(() => { load(); }, [th.inquiry_id]);
  const send = async () => {
    const body = text.trim(); if (!body) return;
    setBusy(true); setMsg('');
    const j = await call('messages_api', { action: 'send', inquiry_id: th.inquiry_id, supplier_id: th.supplier_id, body }, token).catch(() => null);
    if (!live.current) return;
    setBusy(false);
    if (j && j.ok) { setText(''); load(); } else setMsg(ws(lang, 'mb_send_err'));
  };
  const closed = data && data.chat_status !== 'open';
  return (
    <section aria-labelledby="qd-mb-thread" className="qd-panel p-5">
      <div className="flex items-center justify-between gap-3">
        <h2 id="qd-mb-thread" className="text-[15.5px] font-bold text-foreground">{ws(lang, 'mb_customer')}{th.subject ? <> · <bdi className="font-semibold text-foreground/80">{th.subject}</bdi></> : null}</h2>
        <Button variant="link" className="h-auto min-h-11 px-0" onClick={onBack}>{ws(lang, 'mb_back')}</Button>
      </div>
      <p className="mt-2 rounded-md border border-warn/30 bg-warn/10 px-3 py-2 text-[12px] text-warn-fg">{ws(lang, 'mb_warning')}</p>
      {!data ? <p className="mt-3 text-[13px] text-muted-foreground" aria-busy="true">{ws(lang, 'mb_loading')}</p>
        : data.error ? <p className="mt-3 text-[13px] text-muted-foreground" role="alert">{ws(lang, 'mb_err')}</p>
        : closed ? <p className="mt-3 text-[13px] text-muted-foreground">{ws(lang, data.chat_status === 'banned' ? 'mb_closed_policy' : 'mb_not_open')}</p>
        : <>
          <ol className="my-3 flex max-h-[440px] flex-col gap-2 overflow-y-auto" aria-live="polite">
            {(data.messages || []).length === 0 && <li className="text-[13px] text-muted-foreground">{ws(lang, 'mb_no_msgs')}</li>}
            {(data.messages || []).map((m: any) => (
              <li key={m.id} dir="auto" className={cn('max-w-[78%] rounded-xl px-3 py-2 text-[13.5px] leading-snug', m.sender === 'supplier' ? 'self-end bg-primary/85 text-primary-foreground' : 'self-start bg-secondary text-foreground')}>{m.body}</li>
            ))}
          </ol>
          <form className="flex flex-wrap gap-2.5" onSubmit={(e) => { e.preventDefault(); send(); }}>
            <label className="min-w-0 flex-1">
              <span className="sr-only">{ws(lang, 'mb_type')}</span>
              <textarea dir="auto" rows={2} maxLength={2000} value={text} onChange={(e) => setText(e.target.value)} placeholder={ws(lang, 'mb_type')}
                className="w-full resize-y rounded-md border border-input bg-transparent px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring pointer-coarse:text-[16px]" />
            </label>
            <Button type="submit" className="min-h-11 self-end" disabled={busy || !text.trim()}>{busy ? ws(lang, 'mb_sending') : ws(lang, 'mb_send')}</Button>
          </form>
        </>}
      {msg && <p role="alert" className="mt-2 text-[13px] text-danger-fg">{msg}</p>}
    </section>
  );
}
