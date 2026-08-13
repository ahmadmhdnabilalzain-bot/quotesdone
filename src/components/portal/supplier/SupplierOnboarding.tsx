'use client';
// ROW #5 §2 §22 §23 — AI SUPPLIER ONBOARDING. A CONVERSATION, NOT A FORM.
//
// The spec's §1 opens by rejecting "register → fill 20 forms" and §2 says what replaces it: the
// agent asks the supplier about their company, the supplier answers in free text, and the AI builds
// the profile. The portal had 21 form controls on that surface and no extraction path at all.
//
// ── THE EXTRACTED PANEL IS THE HONEST PART ──────────────────────────────────────────────────────
// Every one of the six fields is shown whether or not it was found, and a field the supplier did
// not state reads "not yet" rather than being quietly absent. That is honesty rule #2 — absent is
// not empty, and the population is the six fields the spec enumerates. The supplier can always see
// exactly what the AI believes about them before anything is written.
//
// ── AND NOTHING IS WRITTEN WITHOUT A CONFIRMATION ───────────────────────────────────────────────
// "The AI creates the profile automatically" cannot mean "the AI decides what your company is and
// saves it". The save button is enabled only once a company name and a category exist, it writes
// through the SAME create_company + save_profile path the form uses, and the licence gate in
// save_profile still decides approval. A supplier cannot talk their way to `verified`.
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { SUPA_FN, SUPA_ANON } from '@/lib/supaEnv';

type Lang = 'en' | 'ar';
type Msg = { role: 'user' | 'assistant'; content: string };
type Profile = {
  company_name: string | null; category: string | null; company_type: string | null;
  location: string | null; capability_summary: string | null; markets: string[];
};

const FN = SUPA_FN;
const ANON = SUPA_ANON;

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
    title: 'Let’s build your profile',
    // The opening turn. §2's "the agent starts by asking about the company", verbatim on screen.
    opening: 'Tell me about your company — what you make or install, where you are based, and who you sell to. Write it however you like, in a sentence or ten.',
    placeholder: 'e.g. We are Al Waha Aluminium in Sharjah. We fabricate curtain walling and shopfronts, twelve years in business, and we cover all seven emirates.',
    send: 'Send', thinking: 'Reading what you wrote…',
    whatIHeard: 'What I understood so far', notYet: 'not yet',
    save: 'Save this as my profile', saving: 'Saving…', saved: 'Saved. Your profile is live.',
    needName: 'I still need your company name and trade before I can save this.',
    failed: 'I could not read that just now. You can try again, or fill the profile form instead.',
    fields: {
      company_name: 'Company name', category: 'Trade', company_type: 'Type of business',
      location: 'Based in', capability_summary: 'What you can do', markets: 'Markets you serve',
    },
  },
  ar: {
    title: 'لنُنشئ ملفك',
    opening: 'أخبرني عن شركتك — ماذا تصنع أو تركّب، وأين مقرّك، ولمن تبيع. اكتب كما تشاء، جملة أو عشر.',
    placeholder: 'مثال: نحن الواحة للألمنيوم في الشارقة. نصنع واجهات وستائر زجاجية وواجهات محلات، خبرة اثني عشر عامًا، ونغطي الإمارات السبع.',
    send: 'إرسال', thinking: 'أقرأ ما كتبت…',
    whatIHeard: 'ما فهمته حتى الآن', notYet: 'ليس بعد',
    save: 'احفظ هذا كملفي', saving: 'جارٍ الحفظ…', saved: 'تم الحفظ. ملفك الآن فعّال.',
    needName: 'أحتاج اسم شركتك ونشاطك قبل الحفظ.',
    failed: 'تعذّرت قراءة ذلك الآن. حاول مرة أخرى أو املأ نموذج الملف.',
    fields: {
      company_name: 'اسم الشركة', category: 'النشاط', company_type: 'نوع النشاط',
      location: 'المقر', capability_summary: 'ما يمكنك تنفيذه', markets: 'الأسواق التي تخدمها',
    },
  },
};
const t = (lang: Lang) => T[lang] || T.en;

const FIELDS: (keyof Omit<Profile, never>)[] =
  ['company_name', 'category', 'company_type', 'location', 'capability_summary', 'markets'];

const EMPTY: Profile = {
  company_name: null, category: null, company_type: null,
  location: null, capability_summary: null, markets: [],
};

export default function SupplierOnboarding({ token, lang = 'en', goTo }:
  { token?: string | null; lang?: Lang; goTo?: (tab: string) => void }) {
  const L = t(lang);
  // The opening question is turn zero, so the supplier arrives to a question rather than a blank box.
  const [messages, setMessages] = useState<Msg[]>([{ role: 'assistant', content: L.opening }]);
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [profile, setProfile] = useState<Profile>(EMPTY);
  const [saveState, setSaveState] = useState<'' | 'saving' | 'saved' | 'error'>('');
  const endRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => { endRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' }); }, [messages, busy]);

  // A later turn COMPLETES the profile, it does not replace it: a supplier who names their company
  // first and their markets second must not lose the name. Only non-null incoming values overwrite.
  const merge = (prev: Profile, next: Partial<Profile>): Profile => ({
    company_name: next.company_name ?? prev.company_name,
    category: next.category ?? prev.category,
    company_type: next.company_type ?? prev.company_type,
    location: next.location ?? prev.location,
    capability_summary: next.capability_summary ?? prev.capability_summary,
    markets: next.markets?.length ? next.markets : prev.markets,
  });

  async function send() {
    const text = draft.trim();
    if (!text || busy) return;
    const history = messages.slice(-8);
    setMessages((m) => [...m, { role: 'user', content: text }]);
    setDraft(''); setBusy(true);
    const d = await call('supplier_onboard', { action: 'extract', text, history }, token)
      .catch(() => ({ ok: false }));
    setBusy(false);
    if (!d?.ok) { setMessages((m) => [...m, { role: 'assistant', content: L.failed }]); return; }
    setProfile((p) => merge(p, d.profile || {}));
    setMessages((m) => [...m, { role: 'assistant', content: String(d.reply || '') }]);
  }

  const ready = !!(profile.company_name && profile.category);

  // The write goes back through the ordinary path. Nothing here decides approval.
  async function saveProfile() {
    if (!ready || saveState === 'saving') return;
    setSaveState('saving');
    const created = await call('supplier_api', {
      action: 'create_company', company_name: profile.company_name,
      emirate: profile.location, category: profile.category, role: 'supplier',
    }, token).catch(() => ({}));
    // 409 "already manages a company" is the normal path for a supplier who claimed a scraped row —
    // it is not an error, it just means create was unnecessary.
    if (created?.error && !/already manages/i.test(String(created.error))) { setSaveState('error'); return; }
    const saved = await call('supplier_api', {
      action: 'save_profile',
      company_type: profile.company_type,
      description: profile.capability_summary,
      services: profile.capability_summary,
      service_emirates: profile.markets,
    }, token).catch(() => ({}));
    setSaveState(saved?.error ? 'error' : 'saved');
  }

  const shown = useMemo(() => FIELDS.map((f) => {
    const v = profile[f];
    const text = Array.isArray(v) ? (v.length ? v.join(', ') : null) : v;
    return { key: f, label: L.fields[f as keyof typeof L.fields], value: text };
  }), [profile, L]);

  return (
    <div className="flex flex-col gap-4 lg:flex-row" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      {/* THE CONVERSATION */}
      <section className="qd-panel flex min-h-[26rem] flex-1 flex-col overflow-hidden">
        <header className="border-b border-white/10 px-4 py-3 text-[13.5px] font-semibold text-white">{L.title}</header>
        <div className="flex flex-1 flex-col gap-3 overflow-y-auto px-4 py-4">
          <AnimatePresence initial={false}>
            {messages.map((m, i) => (
              <motion.div
                key={i}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.22, ease: 'easeOut' }}
                className={m.role === 'user' ? 'self-end max-w-[85%]' : 'self-start max-w-[85%]'}
              >
                <p className={'rounded-2xl px-3.5 py-2.5 text-[13.5px] leading-[1.65] '
                  + (m.role === 'user'
                    ? 'bg-primary/15 text-white'
                    : 'bg-white/[0.04] text-muted-foreground ring-1 ring-white/10')}>
                  {m.content}
                </p>
              </motion.div>
            ))}
          </AnimatePresence>
          {busy && <p className="self-start text-xs text-muted-foreground">{L.thinking}</p>}
          <div ref={endRef} />
        </div>
        {/* FREE TEXT, NOT FIELDS. Enter sends, Shift+Enter is a newline — a supplier writing a
            paragraph about their company should not have it sent at the first line break. */}
        <div className="border-t border-white/10 p-3">
          <textarea
            className="qd-input min-h-[4.5rem] w-full resize-y text-[13.5px]"
            value={draft}
            placeholder={L.placeholder}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void send(); } }}
          />
          <button type="button" className="qd-btn mt-2 w-full" disabled={busy || !draft.trim()} onClick={() => void send()}>
            {busy ? L.thinking : L.send}
          </button>
        </div>
      </section>

      {/* WHAT THE AI BELIEVES — all six fields, present or not */}
      <aside className="qd-panel w-full shrink-0 p-4 lg:w-[21rem]">
        <h3 className="mb-3 text-[13.5px] font-semibold text-white">{L.whatIHeard}</h3>
        <dl className="flex flex-col gap-2.5">
          {shown.map((f) => (
            <div key={f.key} className="flex flex-col gap-0.5">
              <dt className="text-[11px] uppercase tracking-wide text-muted-foreground">{f.label}</dt>
              <motion.dd
                key={String(f.value)}
                initial={{ opacity: 0.35 }}
                animate={{ opacity: 1 }}
                transition={{ duration: 0.3 }}
                className={f.value ? 'text-[13px] text-white' : 'text-[13px] italic text-muted-foreground/60'}
              >
                {f.value || L.notYet}
              </motion.dd>
            </div>
          ))}
        </dl>
        <button
          type="button"
          className="qd-btn mt-4 w-full"
          disabled={!ready || saveState === 'saving' || saveState === 'saved'}
          onClick={() => void saveProfile()}
        >
          {saveState === 'saving' ? L.saving : saveState === 'saved' ? L.saved : L.save}
        </button>
        {!ready && <p className="mt-2 text-xs leading-[1.6] text-muted-foreground">{L.needName}</p>}
        {saveState === 'saved' && goTo && (
          <button type="button" className="qd-link mt-2 w-full text-xs" onClick={() => goTo('profile')}>
            {L.fields.company_name} →
          </button>
        )}
      </aside>
    </div>
  );
}
