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
import React, { useEffect, useState } from 'react';

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
  count?: number; note?: string | null;
  population?: { inquiries?: number; matches_for_me?: number };
  workspaces?: Workspace[];
};
type Lang = 'en' | 'ar';

const FN = (process.env.NEXT_PUBLIC_SUPABASE_URL || '') + '/functions/v1';
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

async function call(path: string, body: unknown, token?: string | null) {
  const r = await fetch(FN + '/' + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
    body: JSON.stringify(body),
  });
  return r.json();
}

const T = {
  en: {
    title: 'Customer Workspaces', loading: 'Opening your workspaces…',
    files: 'Files', messages: 'Messages', timeline: 'Timeline', unread: 'unread',
    drawings: 'Drawings', specifications: 'Specifications', contracts: 'Contracts', other: 'Other',
    noFiles: 'no files shared yet', notStarted: 'not started',
    empty: 'No customer relationships yet.',
    emptyWhy: 'A workspace opens when a customer is matched to you or messages you.',
    matched: 'Matched', messaged: 'Messaged', quoted: 'Quoted', awarded: 'Awarded',
    open: 'Open messages',
  },
  ar: {
    title: 'مساحات عمل العملاء', loading: 'جارٍ فتح مساحات العمل…',
    files: 'الملفات', messages: 'الرسائل', timeline: 'الجدول الزمني', unread: 'غير مقروء',
    drawings: 'المخططات', specifications: 'المواصفات', contracts: 'العقود', other: 'أخرى',
    noFiles: 'لم تتم مشاركة ملفات بعد', notStarted: 'لم تبدأ',
    empty: 'لا توجد علاقات عملاء بعد.',
    emptyWhy: 'تُفتح مساحة العمل عند مطابقتك بعميل أو مراسلته لك.',
    matched: 'مطابَق', messaged: 'مراسَل', quoted: 'مسعَّر', awarded: 'مُرسى',
    open: 'فتح الرسائل',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

const STAGES: (keyof typeof T.en)[] = ['matched', 'messaged', 'quoted', 'awarded'];

export default function CollaborationWorkspace({
  token, lang = 'en', goTo,
}: { token?: string | null; lang?: Lang; goTo?: (tab: string) => void }) {
  const [d, setD] = useState<Payload | null>(null);
  const [err, setErr] = useState('');

  useEffect(() => {
    let live = true;
    call('supplier_portal', { action: 'workspaces' }, token).then((j) => {
      if (!live) return;
      if (j && j.ok) setD(j);
      else setErr((j && (j.error || j.hint)) || 'load_err');
    });
    return () => { live = false; };
  }, [token]);

  if (err) return <div className="text-xs opacity-60 p-4">{err}</div>;
  if (!d) return <div className="text-xs opacity-60 p-4">{t(lang, 'loading')}</div>;

  const list = d.workspaces || [];

  return (
    <div className="space-y-4">
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <div className="flex justify-between items-baseline">
          <h3 className="text-xs uppercase tracking-wide opacity-60">{t(lang, 'title')}</h3>
          <span className="text-sm tabular-nums">{d.count ?? 0}</span>
        </div>
        {list.length === 0 && (
          <div className="mt-3 text-[11px] opacity-60 leading-relaxed">
            <p>{t(lang, 'empty')}</p>
            <p className="opacity-70 mt-1">{t(lang, 'emptyWhy')}</p>
            {/* The population behind the empty list — never a silent nothing. */}
            <p className="opacity-40 mt-1.5">
              {d.population?.inquiries ?? 0} inquiries · {d.population?.matches_for_me ?? 0} matched to you
            </p>
          </div>
        )}
      </section>

      {list.map((w) => {
        const fc = w.file_categories || {};
        const pct = w.timeline?.pct;
        const stages = w.timeline?.stages || {};
        return (
          <section key={w.inquiry_id} className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
            <header className="flex items-start justify-between gap-3 mb-3">
              <div className="min-w-0">
                <div className="text-[13px] font-medium truncate">{w.project?.title}</div>
                <div className="text-[11px] opacity-55 truncate">
                  {[w.project?.category, w.project?.emirate, w.project?.status].filter(Boolean).join(' · ')}
                </div>
              </div>
              {(w.unread ?? 0) > 0 && (
                <span className="shrink-0 rounded-full bg-sky-400/20 border border-sky-400/40 px-2 py-0.5 text-[10px] text-sky-200">
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
                  <div className="h-full rounded-full bg-gradient-to-r from-sky-400 to-emerald-400 transition-all duration-700"
                       style={{ width: Math.max(2, pct) + '%' }} />
                </div>
              )}
              <div className="flex gap-1.5 mt-1.5 flex-wrap">
                {STAGES.map((s) => (
                  <span key={s} className={`rounded-full border px-2 py-0.5 text-[10px] ${
                    stages[s] ? 'border-emerald-400/40 bg-emerald-400/10 text-emerald-200' : 'border-white/12 opacity-40'
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
                {goTo && (
                  <button
                    type="button"
                    onClick={() => goTo('messages')}
                    className="mt-1.5 rounded-lg border border-white/20 px-2.5 py-1 text-[11px] hover:bg-white/10"
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
