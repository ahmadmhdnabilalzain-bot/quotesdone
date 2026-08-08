'use client';
// ROW #5 §1 — WHAT A SUPPLIER SEES BEFORE THEY HAVE AN ACCOUNT.
//
// The supplier surface opened straight onto a sign-in box. §1 asks for the thing that comes before
// it: what this is, why it is worth their time, and two ways in.
//
// ── "WATCH HOW IT WORKS" IS CALLED "SEE HOW IT WORKS", DELIBERATELY ─────────────────────────────
// The spec's wording implies a video. There is no video. A button labelled "Watch" that plays
// nothing is a small lie told at the exact moment a supplier is deciding whether to trust the
// platform, so the label says "See", and it reveals the four steps that actually happen — which are
// the real flow, not a description of an aspirational one. When a video exists, the label can go
// back to matching the spec word for word.
//
// ── AND THE STEPS ARE THE REAL ONES, INCLUDING THE UNCOMFORTABLE PART ───────────────────────────
// Step 2 says approval depends on a readable, in-date trade licence, because that is what
// save_profile's licence gate actually does and a supplier who learns it after registering has been
// wasted. Nothing here promises work: the platform has no completed jobs yet, and a hero that
// implied a pipeline would be the first false thing a supplier read.
import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';

type Lang = 'en' | 'ar';

const T = {
  en: {
    kicker: 'For suppliers, manufacturers and contractors in the UAE',
    // The spec's value proposition, verbatim.
    valueProp: 'Grow your business with AI-powered procurement',
    sub: 'Tell us about your company in your own words. We build your profile, read your catalog, and put the work that fits you in front of you first.',
    ctaPrimary: 'Become a Verified Supplier',
    ctaSecondary: 'See How It Works',
    stepsTitle: 'How It Works',
    steps: [
      ['Describe your company', 'A few sentences, not twenty form fields. The assistant reads them and builds your profile.'],
      ['Get verified', 'Upload a current trade licence. Approval is automatic once it reads — and refused, with the reason, if it does not.'],
      ['Receive work that fits', 'Requests are matched on your trade, your service area and what you can actually do. Every match shows why.'],
      ['Quote and get paid', 'Quote from the portal. You are paid on the work; QuotesDone charges the customer a reveal fee.'],
    ],
    honest: 'QuotesDone is new. There are no completed jobs on the platform yet, so nothing here promises you a pipeline — only that when work arrives, it is matched on fit.',
  },
  ar: {
    kicker: 'للمورّدين والمصنّعين والمقاولين في الإمارات',
    valueProp: 'نمِّ أعمالك مع مشتريات مدعومة بالذكاء الاصطناعي',
    sub: 'أخبرنا عن شركتك بكلماتك. ننشئ ملفك، ونقرأ كتالوجك، ونضع أمامك العمل الذي يناسبك أولًا.',
    ctaPrimary: 'كن مورّدًا موثّقًا',
    ctaSecondary: 'شاهد كيف يعمل',
    stepsTitle: 'كيف يعمل',
    steps: [
      ['اوصف شركتك', 'بضع جمل، لا عشرون حقلًا. يقرأها المساعد وينشئ ملفك.'],
      ['احصل على التوثيق', 'ارفع رخصة تجارية سارية. الاعتماد تلقائي عند قراءتها — ويُرفض مع ذكر السبب إن تعذّرت.'],
      ['استقبل العمل المناسب', 'تُطابَق الطلبات حسب نشاطك ونطاق خدمتك وقدرتك الفعلية. وكل مطابقة تُظهر سببها.'],
      ['قدّم عرضك واستلم', 'قدّم عرضك من البوابة. تُدفع لك قيمة العمل، وتتقاضى QuotesDone رسوم الكشف من العميل.'],
    ],
    honest: 'QuotesDone منصة جديدة. لا توجد أعمال منجزة بعد، لذا لا نعدك هنا بتدفق عمل — بل بأن ما يصل يُطابَق حسب الملاءمة.',
  },
};
const t = (lang: Lang) => T[lang] || T.en;

export default function SupplierEntryHero({ lang = 'en', onStart }:
  { lang?: Lang; onStart?: () => void }) {
  const L = t(lang);
  const [open, setOpen] = useState(false);

  return (
    <section className="mx-auto w-full max-w-3xl px-4 pt-8 text-center" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <p className="text-[11px] uppercase tracking-[0.18em] text-muted-foreground">{L.kicker}</p>

      <motion.h1
        initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.35 }}
        className="mt-2 text-balance text-[26px] font-semibold leading-[1.25] text-white sm:text-[32px]"
      >
        {L.valueProp}
      </motion.h1>

      <p className="mx-auto mt-3 max-w-xl text-[13.5px] leading-[1.75] text-muted-foreground">{L.sub}</p>

      <div className="mt-5 flex flex-wrap items-center justify-center gap-2.5">
        <button type="button" className="qd-btn" onClick={() => onStart?.()}>{L.ctaPrimary}</button>
        <button
          type="button"
          className="rounded-lg border border-white/20 px-3.5 py-2 text-[13px] text-white/90 hover:bg-white/10"
          aria-expanded={open}
          onClick={() => setOpen((o) => !o)}
        >
          {L.ctaSecondary}
        </button>
      </div>

      <AnimatePresence initial={false}>
        {open && (
          <motion.ol
            initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.25 }}
            className="mt-5 overflow-hidden text-start"
          >
            <h2 className="mb-2 text-[10px] uppercase tracking-wide text-muted-foreground">{L.stepsTitle}</h2>
            {L.steps.map(([head, body], i) => (
              <li key={head} className="qd-panel mb-2 flex items-start gap-3 p-3.5">
                <span aria-hidden className="mt-[1px] flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-primary/20 text-[11px] font-semibold text-primary">
                  {i + 1}
                </span>
                <span className="min-w-0">
                  <b className="block text-[13px] text-white">{head}</b>
                  <span className="mt-0.5 block text-[12px] leading-[1.7] text-muted-foreground">{body}</span>
                </span>
              </li>
            ))}
            {/* The thing a launch page normally leaves out. */}
            <p className="mt-2 text-[11.5px] leading-[1.7] text-muted-foreground/70">{L.honest}</p>
          </motion.ol>
        )}
      </AnimatePresence>
    </section>
  );
}
