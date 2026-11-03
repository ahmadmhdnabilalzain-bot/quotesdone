'use client';
// ROW #5 §18 — THE SUPPLIER COLLABORATION WORKSPACE.
//
// ── "EVERY CUSTOMER RELATIONSHIP GETS A WORKSPACE" ──────────────────────────────────────────────
// A relationship here is an (inquiry, supplier) pair — what chat_threads and messages are keyed on.
// The pieces all existed separately: inquiries held the project, messages held the conversation,
// documents held the files, and nothing joined them into a container the supplier could open.
//
// ── THE LIST IS EMPTY ON PRODUCTION, AND IT SAYS SO WITH ITS POPULATION ─────────────────────────
// 0 inquiries and 0 matches exist. The empty state names both counts, so it can never be mistaken
// for a request that failed or a component that silently rendered nothing.
//
// It is not seeded with a demo relationship. One inquiry insert on production fires twelve
// triggers, including fn_emit_event('inquiry','rfq.created') — which would inject a synthetic event
// into row #2's separately-measured event backbone. Matching would find 0 suppliers because none is
// verified, so no real company would be contacted, but polluting another row's measurement is the
// founder's decision to make.
//
// timeline.pct is NULL before anything has happened, not 0%. A relationship that has not started is
// not a relationship that is 0% complete.
import React, { useCallback, useEffect, useState } from 'react';
import { call } from './api';
import { PanelError, PanelLoading, panelErrorCode, panelErrorText } from './PanelState';
// SP-I-04: a counted noun in Arabic takes four forms, not one. The population line reads
// "{n} طلبًا" for every n without this, which is right only from eleven upwards.
import { AR_NOUN, arCount } from '@/lib/countedNoun';

// «استفسار», not «طلب»: PR #858 settled on one Arabic word for an RFQ across the whole supplier
// surface (workspaceCopy.ts says الاستفسارات everywhere), and two words for one thing on one screen
// reads as two different objects. Nominative dual — nothing governs the count in «{n} على المنصة».

// The adjective agrees with the noun it follows, so "matched" cannot be a suffix bolted onto the
// line above — a dual noun needs a dual adjective and a plural needs a plural.

type FileRow = { name?: string | null; kind?: string | null; category?: string; created_at?: string };
type Workspace = {
  inquiry_id: string;
  project?: { title?: string; category?: string | null; emirate?: string | null; status?: string | null; created_at?: string };
  files?: FileRow[];
  file_categories?: { drawings?: number; specifications?: number; contracts?: number; other?: number };
  message_count?: number; unread?: number; last_activity?: string | null;
  timeline?: { pct?: number | null; stages?: Record<string, number> };
};
type Payload = {
  lead_id?: number;
  count?: number; note?: string | null;
  population?: { inquiries?: number; matches_for_me?: number };
  workspaces?: Workspace[];
};
type Lang = 'en' | 'ar';

const T = {
  en: {
    title: 'Customer Workspaces', loading: 'Opening your workspaces…',
    files: 'Files', messages: 'Messages', timeline: 'Timeline', unread: 'unread',
    drawings: 'Drawings', specifications: 'Specifications', contracts: 'Contracts', other: 'Other',
    noFiles: 'no files shared yet', notStarted: 'not started',
    empty: 'No customer relationships yet.',
    emptyWhy: 'A workspace opens when a customer is matched to you or messages you.',
    matched: 'Matched', messaged: 'Messaged', quoted: 'Quoted', awarded: 'Awarded',
    open: 'Open full thread',
    send: 'Send', sending: 'Sending…', sendFailed: 'Could not send. Try again.',
    composerPlaceholder: 'Reply to this customer…',
    composerBlocked: 'Messaging opens once this relationship has a supplier record.',
    popInquiries: (n: number) => n + ' enquiries on the platform', popMatched: (n: number) => n + ' matched to you',
  },
  ar: {
    title: 'مساحات عمل العملاء', loading: 'جارٍ فتح مساحات العمل…',
    files: 'الملفات', messages: 'الرسائل', timeline: 'الجدول الزمني', unread: 'غير مقروء',
    drawings: 'المخططات', specifications: 'المواصفات', contracts: 'العقود', other: 'أخرى',
    noFiles: 'لم تُشارَك أي ملفات بعد', notStarted: 'لم تبدأ',
    empty: 'لا توجد علاقات عملاء بعد.',
    emptyWhy: 'تُفتح مساحة العمل عند مطابقتكم مع عميل أو عند مراسلته لكم.',
    matched: 'تمت المطابقة', messaged: 'تمت المراسلة', quoted: 'تم التسعير', awarded: 'تمت الترسية',
    open: 'فتح المحادثة كاملة',
    send: 'إرسال', sending: 'جارٍ الإرسال…', sendFailed: 'تعذّر الإرسال. يُرجى المحاولة مرة أخرى.',
    composerPlaceholder: 'اكتبوا ردّكم على هذا العميل…',
    composerBlocked: 'تُفتح المراسلة بعد إنشاء سجل المورّد لهذه العلاقة.',
    popInquiries: (n: number) => arCount(n, AR_NOUN.inquiry) + ' على المنصة', popMatched: (n: number) => arCount(n, AR_NOUN.matchedInquiry),
  },
};
// Two entries of T are functions of a count, so `t` must not offer them: it returns a string.
type StrKey = { [K in keyof typeof T.en]: (typeof T.en)[K] extends string ? K : never }[keyof typeof T.en];
const t = (lang: Lang, k: StrKey): string => (T[lang] || T.en)[k] || T.en[k] || String(k);
// The two population labels are counted, so they are functions of n, not strings.
const pop = (lang: Lang, k: 'popInquiries' | 'popMatched', n: number): string => (T[lang] || T.en)[k](n);

const STAGES: StrKey[] = ['matched', 'messaged', 'quoted', 'awarded'];

// ── §18: THE CONVERSATION HAPPENS IN THE WORKSPACE, NOT SOMEWHERE ELSE ──────────────────────────
// The card used to carry a message COUNT and a button that navigated away to the global messages
// tab. That is a link to the conversation, not a conversation: the supplier loses the project, the
// files and the timeline the moment they answer, which is the exact opposite of "every customer
// relationship gets a workspace". The composer now lives on the card.
//
// It posts through `messages_api` `send` — the same action the messages tab uses, with the same
// moderation and the same warning path. A second send endpoint would be a second set of rules to
// keep in step, and the one that drifted would be the one nobody was watching.
function WorkspaceComposer({ token, inquiryId, supplierId, lang, onSent }: {
  token?: string | null; inquiryId: string; supplierId?: number; lang: Lang; onSent: () => void;
}) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');

  // Without a supplier id there is nothing to key a thread on. Rendering a dead box would invite
  // the supplier to type a message that goes nowhere, so the reason is shown instead.
  if (!supplierId) return <p className="mt-1.5 text-[10.5px] opacity-45">{t(lang, 'composerBlocked')}</p>;

  const send = async () => {
    const body = text.trim();
    if (!body || busy) return;
    setBusy(true); setMsg('');
    const j = await call('messages_api',
      { action: 'send', inquiry_id: inquiryId, supplier_id: supplierId, body }, token)
      .catch(() => null);
    setBusy(false);
    if (j && j.ok) { setText(''); onSent(); }
    // `warning` is moderation copy the server already wrote for the supplier to read; anything else
    // is a failure, and its raw text is not for them (SP-I-01).
    else setMsg((j && j.warning) || (j ? panelErrorText(lang, panelErrorCode(j)) : t(lang, 'sendFailed')));
  };

  return (
    <div className="mt-1.5">
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void send(); } }}
        placeholder={t(lang, 'composerPlaceholder')}
        rows={2}
        className="w-full resize-y rounded-lg border border-white/15 bg-white/4 px-2.5 py-1.5 text-[11.5px] leading-[1.6] outline-hidden placeholder:opacity-40 focus:border-white/30"
      />
      <button
        type="button" disabled={busy || !text.trim()} onClick={() => void send()}
        className="mt-1 min-h-11 min-w-11 rounded-lg border border-white/20 px-2.5 py-1 text-[11px] disabled:opacity-40 hover:bg-white/10"
      >
        {busy ? t(lang, 'sending') : t(lang, 'send')}
      </button>
      {msg && <p className="mt-1 text-[10.5px] opacity-70">{msg}</p>}
    </div>
  );
}

export default function CollaborationWorkspace({
  token, lang = 'en', goTo,
}: { token?: string | null; lang?: Lang; goTo?: (tab: string) => void }) {
  const [d, setD] = useState<Payload | null>(null);
  const [err, setErr] = useState('');

  // Re-readable, because sending a message from the card changes the message count and can move the
  // timeline stage. A composer that posts and leaves the card showing the old numbers teaches the
  // supplier not to trust the card.
  const load = useCallback(async () => {
    setErr('');
    const j = await call('supplier_portal', { action: 'workspaces' }, token);
    if (j && j.ok) setD(j); else setErr(panelErrorCode(j));
  }, [token]);

  useEffect(() => { void load(); }, [load]);

  if (err) return <PanelError lang={lang} code={err} onRetry={() => { void load(); }} />;
  if (!d) return <PanelLoading lang={lang} text={t(lang, 'loading')} />;

  const list = d.workspaces || [];

  return (
    <div className="space-y-4" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <section className="rounded-2xl border border-white/10 bg-white/3 backdrop-blur-xl p-4">
        <div className="flex justify-between items-baseline">
          <h3 className="text-xs uppercase tracking-wide opacity-60">{t(lang, 'title')}</h3>
          <span className="text-sm tabular-nums">{d.count ?? 0}</span>
        </div>
        {list.length === 0 && (
          <div className="mt-3 text-[11px] opacity-60 leading-relaxed">
            <p>{t(lang, 'empty')}</p>
            <p className="opacity-70 mt-1">{t(lang, 'emptyWhy')}</p>
            {/* The population behind the empty list — never a silent nothing. SP-I-02: it was the
                one line on this panel still written in English on /ar. */}
            <p className="opacity-40 mt-1.5">
              {pop(lang, 'popInquiries', d.population?.inquiries ?? 0)} · {pop(lang, 'popMatched', d.population?.matches_for_me ?? 0)}
            </p>
          </div>
        )}
      </section>

      {list.map((w) => {
        const fc = w.file_categories || {};
        const pct = w.timeline?.pct;
        const stages = w.timeline?.stages || {};
        return (
          <section key={w.inquiry_id} className="rounded-2xl border border-white/10 bg-white/3 backdrop-blur-xl p-4">
            <header className="flex items-start justify-between gap-3 mb-3">
              <div className="min-w-0">
                <div className="text-[13px] font-medium truncate">{w.project?.title}</div>
                <div className="text-[11px] opacity-55 truncate">
                  {[w.project?.category, w.project?.emirate, w.project?.status].filter(Boolean).join(' · ')}
                </div>
              </div>
              {(w.unread ?? 0) > 0 && (
                <span className="shrink-0 rounded-full bg-info/20 border border-info/40 px-2 py-0.5 text-[10px] text-info-fg">
                  {w.unread} {t(lang, 'unread')}
                </span>
              )}
            </header>

            {/* §18's timeline. NULL renders as "not started", never as a 0% bar. */}
            <div className="mb-3">
              <div className="flex justify-between text-[11px] mb-1">
                <span className="opacity-60">{t(lang, 'timeline')}</span>
                <span className="tabular-nums">{pct == null ? t(lang, 'notStarted') : pct + '%'}</span>
              </div>
              {pct != null && (
                <div className="h-1.5 rounded-full bg-white/10 overflow-hidden">
                  <div className="h-full rounded-full bg-linear-to-r from-sky-400 to-emerald-400 transition-all duration-700"
                       style={{ width: Math.max(2, pct) + '%' }} />
                </div>
              )}
              <div className="flex gap-1.5 mt-1.5 flex-wrap">
                {STAGES.map((s) => (
                  <span key={s} className={`rounded-full border px-2 py-0.5 text-[10px] ${
                    stages[s] ? 'border-ok/40 bg-ok/10 text-ok-fg' : 'border-white/12 opacity-40'
                  }`}>
                    {stages[s] ? '✓ ' : ''}{t(lang, s)}
                  </span>
                ))}
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              {/* §18's files, in the three categories the spec names. */}
              <div>
                <div className="text-[10px] uppercase tracking-wide opacity-50 mb-1">{t(lang, 'files')}</div>
                {(w.files || []).length === 0 ? (
                  <p className="text-[11px] opacity-45">{t(lang, 'noFiles')}</p>
                ) : (
                  <div className="flex flex-wrap gap-1.5">
                    {(['drawings', 'specifications', 'contracts', 'other'] as const).map((c) =>
                      (fc[c] ?? 0) > 0 ? (
                        <span key={c} className="rounded-full border border-white/15 px-2 py-0.5 text-[10px]">
                          {t(lang, c)} {fc[c]}
                        </span>
                      ) : null,
                    )}
                  </div>
                )}
              </div>
              <div>
                <div className="text-[10px] uppercase tracking-wide opacity-50 mb-1">{t(lang, 'messages')}</div>
                <div className="text-sm tabular-nums">{w.message_count ?? 0}</div>
                {/* The reply box is IN the workspace. The link out is secondary now, for reading
                    back a long history — not the only way to answer a customer. */}
                <WorkspaceComposer
                  token={token} inquiryId={w.inquiry_id} supplierId={d.lead_id}
                  lang={lang} onSent={() => { void load(); }}
                />
                {goTo && (
                  <button
                    type="button"
                    onClick={() => goTo('messages')}
                    className="mt-1.5 inline-flex min-h-11 min-w-11 items-center text-[10.5px] underline underline-offset-2 opacity-55 hover:opacity-90"
                  >
                    {t(lang, 'open')}
                  </button>
                )}
              </div>
            </div>
          </section>
        );
      })}
    </div>
  );
}
