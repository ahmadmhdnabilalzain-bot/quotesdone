'use client';
// SPEC §16 Communication Center — "One unified place", over messages_api and customer_documents.
//
// The spec names five channels (supplier chat, WhatsApp, email, documents, calls) attached to three
// things (project, RFQ, supplier). THIS FILE UNIFIES THE TWO THAT THE BACKEND ACTUALLY SERVES A
// CUSTOMER, and states the rest in plain words on the page instead of drawing them:
//
//   SERVED, and rendered here
//     supplier chat  messages_api threads/thread/send/request_chat, gated behind a paid reveal
//     documents      customer_documents, attached per conversation by link.ts — provably, never guessed
//     RFQ + supplier every thread is keyed by (inquiry_id, supplier_id) and both are shown on it
//
//   NOT SERVED, and said so rather than staged
//     WhatsApp   wa_messages exists and holds rows; messages_api does not open it and no
//                customer-authed endpoint exposes it. A "WhatsApp (0)" tab would be a claim.
//     Email      inbound_messages, likewise.
//     Calls      production has NO table that logs a call against an inquiry, supplier or customer.
//                Not an empty one — none.
//     Project    neither public.messages nor public.chat_threads carries project_id, and the thread
//                payload has no project. The RFQ->project link exists on inquiries and would close
//                this, but it is not in anything this surface can read.
//
// AND THE ONE CONTROL THIS FILE DELIBERATELY DOES NOT HAVE: an attach button on the composer.
// messages_api `send` accepts `body` and nothing else, and public.messages has no attachment column,
// so a paperclip here would open a file picker, take the customer's file and drop it. A control that
// appears to work and silently discards is worse than no control. Closing it is a backend change —
// an attachment column or a fn_register_document path for ref_table 'messages' — and until then the
// documents panel above the thread is the honest version of "documents in the conversation".
import * as React from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import { DocumentRow, listDocuments, type VaultDocument } from '../documents';
import {
  listThreads, openThread, requestChat, sendMessage,
  type ChatMessage, type Lang, type ThreadResponse, type ThreadSummary,
} from './api';
import { documentCount, linkDocuments, threadKey, type ThreadDocuments } from './link';

// ---- words --------------------------------------------------------------------------------------
const EN = {
  title: 'Communication center',
  sub: 'Every conversation with a supplier, and the documents that belong to it, on the request they are about.',
  carries_h: 'What this inbox carries',
  carries_chat: 'Your in-portal chat with suppliers you have revealed, on the request it belongs to.',
  carries_docs: 'The documents filed against that request, and the revealed supplier’s own licence and certificates.',
  carries_not_wa: 'WhatsApp and email reach QuotesDone and are handled by our team, but they are not routed into your inbox yet — so nothing here is hiding them.',
  carries_not_calls: 'Phone calls are not logged against your requests anywhere on the platform.',
  carries_not_project: 'A conversation is attached to its request and its supplier. It is not yet attached to a project.',
  loading: 'Loading your conversations…',
  retry: 'Retry',
  back: '← Back to conversations',
  empty_h: 'No conversations yet',
  empty_b: 'Chat opens after you reveal a supplier on one of your quotes. Once it does, the conversation and every document on that request appear here together.',
  empty_norole_h: 'This sign-in has no customer account yet',
  empty_norole_b: 'There is nothing to show until an account exists. Nothing was hidden.',
  err_session: 'Your session has expired. Please sign in again.',
  err_load: 'Could not load your conversations.',
  err_thread: 'Could not open that conversation.',
  rfq: 'Request',
  supplier: 'Supplier',
  docs: 'documents',
  doc_one: 'document',
  unread: 'unread',
  no_messages: 'No messages yet',
  st_none: 'No chat open',
  st_requested: 'Chat requested',
  st_open: 'Chat open',
  st_banned: 'Chat closed',
  docs_h: 'Documents on this conversation',
  docs_rfq: 'Filed against this request',
  docs_supplier: 'From this supplier',
  docs_none: 'No document has been filed against this request, and this supplier has none on file.',
  unlinked_h: 'Also in your vault',
  unlinked_b: 'quotation file(s) we cannot attach to a conversation — a quotation is filed against the quote, and the quote does not name the request it answers in what this page can read. They are all in your document vault.',
  ask_h: 'Ask this supplier a question',
  ask_b: 'Our category assistant answers most questions instantly. If yours genuinely needs the supplier, it opens a direct chat for review.',
  ask_ph: 'What would you like to ask?',
  ask_send: 'Ask',
  asking: 'Asking…',
  answered_h: 'Answered by your category assistant',
  requested_h: 'Sent for review',
  pending: 'Your chat request is pending review. You will be notified if it is opened.',
  closed: 'This chat is closed following a policy violation.',
  compose_ph: 'Write a message…',
  send: 'Send',
  sending: 'Sending…',
  you: 'You',
  msg_blocked: 'Your message was not delivered.',
};

const AR: typeof EN = {
  title: 'مركز التواصل',
  sub: 'كل محادثة مع مورّد، والمستندات التي تخصّها، على الطلب الذي تتعلق به.',
  carries_h: 'ما يحتويه هذا الصندوق',
  carries_chat: 'محادثتك داخل المنصة مع المورّدين الذين كشفت عنهم، على الطلب الذي تخصّه.',
  carries_docs: 'المستندات المُرفقة بذلك الطلب، ورخصة وشهادات المورّد الذي كشفت عنه.',
  carries_not_wa: 'رسائل واتساب والبريد الإلكتروني تصل إلى QuotesDone ويتولاها فريقنا، لكنها لا تُوجَّه إلى صندوقك بعد — فلا شيء هنا يخفيها.',
  carries_not_calls: 'المكالمات الهاتفية غير مسجّلة على طلباتك في أي مكان بالمنصة.',
  carries_not_project: 'المحادثة مرتبطة بطلبها وبالمورّد. وهي غير مرتبطة بمشروع بعد.',
  loading: 'جارٍ تحميل محادثاتك…',
  retry: 'إعادة المحاولة',
  back: '→ العودة إلى المحادثات',
  empty_h: 'لا توجد محادثات بعد',
  empty_b: 'تُفتح المحادثة بعد كشفك عن مورّد في أحد عروضك. عندها تظهر هنا المحادثة وكل مستندات ذلك الطلب معًا.',
  empty_norole_h: 'لا يوجد حساب عميل مرتبط بتسجيل الدخول هذا',
  empty_norole_b: 'لا يوجد ما يُعرض حتى يُنشأ الحساب. لم يُخفَ شيء.',
  err_session: 'انتهت جلستك. يُرجى تسجيل الدخول من جديد.',
  err_load: 'تعذّر تحميل محادثاتك.',
  err_thread: 'تعذّر فتح هذه المحادثة.',
  rfq: 'الطلب',
  supplier: 'المورّد',
  docs: 'مستندات',
  doc_one: 'مستند',
  unread: 'غير مقروءة',
  no_messages: 'لا توجد رسائل بعد',
  st_none: 'لا توجد محادثة مفتوحة',
  st_requested: 'تم طلب المحادثة',
  st_open: 'المحادثة مفتوحة',
  st_banned: 'المحادثة مغلقة',
  docs_h: 'مستندات هذه المحادثة',
  docs_rfq: 'مُرفقة بهذا الطلب',
  docs_supplier: 'من هذا المورّد',
  docs_none: 'لم يُرفق أي مستند بهذا الطلب، ولا يوجد لهذا المورّد مستند مسجّل.',
  unlinked_h: 'أيضًا في خزانتك',
  unlinked_b: 'ملف عرض سعر لا يمكننا ربطه بمحادثة — يُؤرشف عرض السعر على العرض نفسه، والعرض لا يذكر الطلب الذي يجيب عنه ضمن ما تقرؤه هذه الصفحة. جميعها في خزانة مستنداتك.',
  ask_h: 'اسأل هذا المورّد',
  ask_b: 'يجيب مساعد الفئة عن معظم الأسئلة فورًا. وإن كان سؤالك يحتاج المورّد فعلًا، يفتح محادثة مباشرة للمراجعة.',
  ask_ph: 'ما الذي تودّ سؤاله؟',
  ask_send: 'اسأل',
  asking: 'جارٍ الإرسال…',
  answered_h: 'أجاب مساعد الفئة',
  requested_h: 'أُرسل للمراجعة',
  pending: 'طلب المحادثة قيد المراجعة. سنُعلمك إذا فُتحت.',
  closed: 'أُغلقت هذه المحادثة إثر مخالفة للسياسة.',
  compose_ph: 'اكتب رسالة…',
  send: 'إرسال',
  sending: 'جارٍ الإرسال…',
  you: 'أنت',
  msg_blocked: 'لم يتم تسليم رسالتك.',
};

const W = (lang: Lang) => (lang === 'ar' ? AR : EN);
const errText = (lang: Lang, code: string) =>
  (code === 'unauthorized' || code === 'forbidden' ? W(lang).err_session : W(lang).err_load);

const fmtWhen = (iso: string | null | undefined, lang: Lang) => {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
};

const statusWord = (s: string, lang: Lang) => {
  const w = W(lang);
  return s === 'open' ? w.st_open : s === 'requested' ? w.st_requested : s === 'banned' ? w.st_banned : w.st_none;
};

/** The one line that tells the customer what is and is not in front of them. */
function CarriesNote({ lang }: { lang: Lang }) {
  const w = W(lang);
  return (
    <Card className="p-4">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{w.carries_h}</div>
      <ul className="mt-2 space-y-1.5 text-[12.5px] leading-relaxed">
        <li className="text-foreground">{w.carries_chat}</li>
        <li className="text-foreground">{w.carries_docs}</li>
        <li className="text-muted-foreground">{w.carries_not_wa}</li>
        <li className="text-muted-foreground">{w.carries_not_calls}</li>
        <li className="text-muted-foreground">{w.carries_not_project}</li>
      </ul>
    </Card>
  );
}

// ---- one conversation ---------------------------------------------------------------------------
function ConversationView({
  token, lang, thread, docs, onBack, onOpenRfq,
}: {
  token: string; lang: Lang; thread: ThreadSummary;
  docs: ThreadDocuments<VaultDocument>;
  onBack: () => void;
  onOpenRfq?: (inquiryId: string) => void;
}) {
  const w = W(lang);
  const [data, setData] = React.useState<ThreadResponse | null>(null);
  const [err, setErr] = React.useState('');
  const [text, setText] = React.useState('');
  const [question, setQuestion] = React.useState('');
  const [busy, setBusy] = React.useState(false);
  const [notice, setNotice] = React.useState<{ tone: 'info' | 'error'; head?: string; body: string } | null>(null);
  const endRef = React.useRef<HTMLDivElement | null>(null);

  const load = React.useCallback(async () => {
    setErr('');
    const r = await openThread(token, thread.inquiry_id, thread.supplier_id);
    if (!r.ok) { setErr(r.error === 'forbidden' ? w.err_thread : errText(lang, r.error)); return; }
    setData(r.data);
  }, [token, lang, thread.inquiry_id, thread.supplier_id, w.err_thread]);

  React.useEffect(() => { load(); }, [load]);
  React.useEffect(() => { endRef.current?.scrollIntoView({ block: 'nearest' }); }, [data?.messages?.length]);

  const status = data?.chat_status || thread.chat_status || 'none';
  const messages: ChatMessage[] = data?.messages || [];

  const doSend = async () => {
    const body = text.trim();
    if (!body) return;
    setBusy(true); setNotice(null);
    const r = await sendMessage(token, thread.inquiry_id, thread.supplier_id, body);
    setBusy(false);
    if (!r.ok) { setNotice({ tone: 'error', body: r.error }); return; }
    if (r.data.ok === false) {
      // A refusal, not a transport failure. The platform's own sentence is shown verbatim.
      setNotice({ tone: 'error', head: w.msg_blocked, body: r.data.warning || '' });
      return;
    }
    setText('');
    if (r.data.message) setData((d) => (d ? { ...d, messages: [...(d.messages || []), r.data.message as ChatMessage] } : d));
  };

  const doAsk = async () => {
    const q = question.trim();
    if (!q) return;
    setBusy(true); setNotice(null);
    const r = await requestChat(token, thread.inquiry_id, thread.supplier_id, q);
    setBusy(false);
    if (!r.ok) { setNotice({ tone: 'error', body: r.error }); return; }
    if (r.data.answered && r.data.answer) { setNotice({ tone: 'info', head: w.answered_h, body: r.data.answer }); setQuestion(''); return; }
    setNotice({ tone: 'info', head: w.requested_h, body: r.data.note || w.pending });
    setQuestion('');
    load();
  };

  const nDocs = documentCount(docs);

  return (
    <section className="flex flex-col gap-4" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <Button type="button" variant="link" className="h-auto self-start px-0" onClick={onBack}>{w.back}</Button>

      <Card className="p-4">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div className="min-w-0">
            <div className="text-[16px] font-extrabold text-foreground">{thread.counterpart}</div>
            <div className="mt-0.5 text-[12.5px] text-muted-foreground">
              <span className="font-semibold text-foreground">{w.rfq}:</span>{' '}
              {onOpenRfq ? (
                <button type="button" className="underline underline-offset-2 hover:text-foreground" onClick={() => onOpenRfq(thread.inquiry_id)}>
                  {thread.subject}
                </button>
              ) : thread.subject}
            </div>
          </div>
          <Badge variant={status === 'open' ? 'default' : 'secondary'}>{statusWord(status, lang)}</Badge>
        </div>
      </Card>

      {/* DOCUMENTS IN THE CONVERSATION — attached by link.ts, which never guesses. */}
      <div>
        <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
          {w.docs_h}{nDocs ? ` · ${nDocs} ${nDocs === 1 ? w.doc_one : w.docs}` : ''}
        </div>
        {nDocs === 0 ? (
          <Card className="p-4 text-[13px] text-muted-foreground">{w.docs_none}</Card>
        ) : (
          <div className="grid gap-3">
            {docs.rfq.length ? <div className="text-[11.5px] text-muted-foreground">{w.docs_rfq}</div> : null}
            {docs.rfq.map((d) => <DocumentRow key={d.id} doc={d} token={token} lang={lang} />)}
            {docs.supplier.length ? <div className="text-[11.5px] text-muted-foreground">{w.docs_supplier}</div> : null}
            {docs.supplier.map((d) => <DocumentRow key={d.id} doc={d} token={token} lang={lang} />)}
          </div>
        )}
      </div>

      {err ? (
        <Card className="p-4">
          <div role="alert" className="text-[13px] font-semibold text-destructive">{err}</div>
          <Button type="button" variant="outline" size="sm" className="mt-2.5" onClick={load}>{w.retry}</Button>
        </Card>
      ) : null}

      {/* THE CHAT ITSELF. */}
      <Card className="flex flex-col overflow-hidden p-0">
        <div className="max-h-[46vh] min-h-[120px] flex-1 space-y-2.5 overflow-y-auto px-4 py-3">
          {!data ? <Skeleton className="h-16 w-full rounded-lg" />
            : messages.length ? messages.map((m) => (
              <div key={m.id} className={cn('flex', m.sender === 'customer' ? 'justify-end' : 'justify-start')}>
                <div className={cn('max-w-[85%] whitespace-pre-wrap rounded-2xl px-3.5 py-2 text-[13.5px] leading-relaxed',
                  m.sender === 'customer' ? 'bg-primary text-primary-foreground' : 'border border-border bg-secondary/60 text-foreground')}>
                  {m.body}
                  <div className={cn('mt-1 text-[10.5px]', m.sender === 'customer' ? 'text-primary-foreground/70' : 'text-muted-foreground')}>
                    {m.sender === 'customer' ? w.you : thread.counterpart} · {fmtWhen(m.created_at, lang)}
                  </div>
                </div>
              </div>
            )) : <div className="text-[13px] text-muted-foreground">{data.note || w.no_messages}</div>}
          <div ref={endRef} />
        </div>

        {/* The platform's off-platform-contact term, verbatim — it carries a stated penalty. */}
        {data?.warning ? (
          <div className="border-t border-border bg-secondary/30 px-4 py-2 text-[11.5px] leading-snug text-muted-foreground">
            {data.warning}
          </div>
        ) : null}

        {notice ? (
          <div role={notice.tone === 'error' ? 'alert' : 'status'} aria-live="polite"
            className={cn('border-t px-4 py-2.5 text-[12.5px] leading-relaxed',
              notice.tone === 'error' ? 'border-destructive/40 bg-destructive/10 text-destructive' : 'border-primary/35 bg-primary/10 text-foreground')}>
            {notice.head ? <div className="font-semibold">{notice.head}</div> : null}
            {notice.body ? <div className={notice.head ? 'mt-0.5' : ''}>{notice.body}</div> : null}
          </div>
        ) : null}

        {/* No paperclip. See the file header: `send` accepts a body and nothing else. */}
        {status === 'open' ? (
          <div className="flex items-end gap-2 border-t border-border px-3 py-2.5">
            <textarea
              rows={1}
              className="flex-1 resize-none rounded-xl border border-border bg-secondary/40 px-3 py-2 text-[13.5px] text-foreground outline-none focus:border-primary/60"
              placeholder={w.compose_ph}
              value={text}
              onChange={(e) => setText(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); doSend(); } }}
            />
            <Button type="button" disabled={busy || !text.trim()} onClick={doSend}>{busy ? w.sending : w.send}</Button>
          </div>
        ) : status === 'requested' ? (
          <div className="border-t border-border px-4 py-3 text-[13px] text-muted-foreground">{w.pending}</div>
        ) : status === 'banned' ? (
          <div className="border-t border-border px-4 py-3 text-[13px] text-destructive">{w.closed}</div>
        ) : (
          <div className="border-t border-border px-4 py-3">
            <div className="text-[13px] font-semibold text-foreground">{w.ask_h}</div>
            <p className="mt-0.5 text-[12px] leading-relaxed text-muted-foreground">{w.ask_b}</p>
            <div className="mt-2 flex items-end gap-2">
              <textarea
                rows={2}
                className="flex-1 resize-none rounded-xl border border-border bg-secondary/40 px-3 py-2 text-[13.5px] text-foreground outline-none focus:border-primary/60"
                placeholder={w.ask_ph}
                value={question}
                onChange={(e) => setQuestion(e.target.value)}
              />
              <Button type="button" disabled={busy || !question.trim()} onClick={doAsk}>{busy ? w.asking : w.ask_send}</Button>
            </div>
          </div>
        )}
      </Card>
    </section>
  );
}

// ---- the center ----------------------------------------------------------------------------------
export interface CommunicationCenterProps {
  /** Customer Supabase JWT — the same token CustomerPortal already holds. */
  token: string;
  lang?: Lang;
  /** Called with the conversation's inquiry_id when the customer taps the request it is about. */
  onOpenRfq?: (inquiryId: string) => void;
  /** Change this to force a refetch. */
  refreshKey?: number;
  className?: string;
}

export function CommunicationCenter({ token, lang = 'en', onOpenRfq, refreshKey = 0, className }: CommunicationCenterProps) {
  const w = W(lang);
  const [threads, setThreads] = React.useState<ThreadSummary[] | null>(null);
  const [role, setRole] = React.useState<'customer' | 'supplier' | null>(null);
  const [docs, setDocs] = React.useState<VaultDocument[]>([]);
  const [openKey, setOpenKey] = React.useState<string | null>(null);
  const [err, setErr] = React.useState('');
  const [reloads, setReloads] = React.useState(0);

  React.useEffect(() => {
    let live = true;
    setThreads(null); setErr('');
    // Both halves of the unified view, in parallel. A vault failure must not blank the inbox —
    // documents are additive here, so they fail to an empty list and the conversations still load.
    Promise.all([listThreads(token), listDocuments(token, null, 200)]).then(([t, d]) => {
      if (!live) return;
      if (!t.ok) { setErr(errText(lang, t.error)); setThreads([]); return; }
      setThreads(Array.isArray(t.data.threads) ? t.data.threads : []);
      setRole(t.data.role ?? null);
      setDocs(d.ok && Array.isArray(d.data.documents) ? d.data.documents : []);
    });
    return () => { live = false; };
  }, [token, lang, refreshKey, reloads]);

  const linked = React.useMemo(() => linkDocuments(threads || [], docs), [threads, docs]);
  const open = threads?.find((t) => threadKey(t) === openKey) || null;

  if (open) {
    return (
      <div className={className}>
        <ConversationView
          token={token} lang={lang} thread={open}
          docs={linked.byThread[threadKey(open)] || { rfq: [], supplier: [] }}
          onBack={() => { setOpenKey(null); setReloads((n) => n + 1); }}
          onOpenRfq={onOpenRfq}
        />
      </div>
    );
  }

  return (
    <section className={cn('flex flex-col gap-4', className)} dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <header>
        <h2 className="text-xl font-extrabold text-foreground">{w.title}</h2>
        <p className="mt-1 max-w-3xl text-[13px] leading-relaxed text-muted-foreground">{w.sub}</p>
      </header>

      <CarriesNote lang={lang} />

      {err ? (
        <Card className="p-4">
          <div role="alert" className="text-[13px] font-semibold text-destructive">{err}</div>
          <Button type="button" variant="outline" size="sm" className="mt-2.5" onClick={() => setReloads((n) => n + 1)}>{w.retry}</Button>
        </Card>
      ) : null}

      {!threads && !err ? (
        <div className="grid gap-3" aria-hidden="true">
          {[0, 1].map((i) => <Skeleton key={i} className="h-[92px] w-full rounded-lg" />)}
        </div>
      ) : null}

      {threads && !threads.length && !err ? (
        <Card className="p-5">
          <div className="text-[15px] font-bold text-foreground">{role === null ? w.empty_norole_h : w.empty_h}</div>
          <p className="mt-1.5 text-[13px] leading-relaxed text-muted-foreground">{role === null ? w.empty_norole_b : w.empty_b}</p>
        </Card>
      ) : null}

      {threads && threads.length ? (
        <div className="grid gap-3">
          {threads.map((t) => {
            const k = threadKey(t);
            const n = documentCount(linked.byThread[k]);
            return (
              <Card key={k} className="cursor-pointer p-4 transition-colors hover:border-primary/40" onClick={() => setOpenKey(k)}>
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="text-[14px] font-bold text-foreground">{t.counterpart}</div>
                    <div className="mt-0.5 text-[12px] text-muted-foreground">
                      <span className="font-semibold">{w.rfq}:</span> {t.subject}
                    </div>
                    <div className="mt-1 truncate text-[12.5px] text-muted-foreground">{t.last || w.no_messages}</div>
                  </div>
                  <div className="flex shrink-0 flex-col items-end gap-1">
                    {t.unread ? (
                      <span className="rounded-full bg-primary px-2 py-0.5 text-[11px] font-bold text-primary-foreground">
                        {t.unread} {w.unread}
                      </span>
                    ) : null}
                    <span className="text-[11.5px] text-muted-foreground">{statusWord(t.chat_status, lang)}</span>
                    {n ? <span className="text-[11.5px] text-muted-foreground">{n} {n === 1 ? w.doc_one : w.docs}</span> : null}
                    {t.last_at ? <span className="text-[11px] text-muted-foreground">{fmtWhen(t.last_at, lang)}</span> : null}
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      ) : null}

      {/* Documents no conversation can claim are DECLARED, not dropped. */}
      {threads && threads.length && linked.unlinkable.length ? (
        <Card className="p-4">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{w.unlinked_h}</div>
          <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
            {linked.unlinkable.length} {w.unlinked_b}
          </p>
        </Card>
      ) : null}
    </section>
  );
}
