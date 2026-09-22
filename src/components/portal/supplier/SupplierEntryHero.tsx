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
import { Button } from '@/components/ui/button';
import { Kicker, Seal, Stepper } from '@/components/ui/sealed';

type Lang = 'en' | 'ar';

const T = {
  en: {
    kicker: 'For suppliers, manufacturers and contractors in the UAE',
    // 14 Sep 2026: the old line sold 'AI-powered procurement' and an assistant that reads your catalog;
    // every model route is on hold, so the page promises only what runs today.
    valueProp: 'Quote on real UAE jobs. Keep 100% of what you win.',
    sub: 'Anonymous requests for the trade your licence covers, from customers anywhere in the UAE. No commission — the customer pays the reveal fee.',
    ctaPrimary: 'Become a Verified Supplier',
    ctaSecondary: 'See How It Works',
    stepsTitle: 'How It Works',
    steps: [
      ['Register your company', 'Company name, emirate and trade, then a verified mobile and email.'],
      ['Get verified', 'Upload a current trade licence and your company profile, enter the licence number and accept the supplier terms. Verification takes up to 3 working days.'],
      ['Receive work that fits', 'Requests from anywhere in the UAE are matched on your trade and what you can actually do. Every match shows why.'],
      ['Quote and get paid', 'Quote from the portal. You are paid on the work; QuotesDone charges the customer a reveal fee.'],
    ],
    honest: 'QuotesDone is new. There are no completed jobs on the platform yet, so nothing here promises you a pipeline — only that when work arrives, it is matched on fit.',
    sealCustomer: 'Customer',
    sealPlaceholder: 'Customer name',
    sealNote: 'Every request reaches you sealed. The customer is named only if they choose your quote.',
  },
  ar: {
    kicker: 'للمورّدين والمصنّعين والمقاولين في الإمارات',
    valueProp: 'قدّموا عروضكم على مشاريع حقيقية في الإمارات، واحتفظوا بكامل قيمة ما تفوزون به.',
    sub: 'طلبات محجوبة الهوية ضمن النشاط الذي تغطيه رخصتكم، من عملاء في جميع أنحاء الإمارات. بلا عمولة، فالعميل هو من يدفع رسوم الكشف.',
    ctaPrimary: 'انضموا إلى المورّدين الموثّقين',
    ctaSecondary: 'تعرّفوا على آلية العمل',
    stepsTitle: 'آلية العمل',
    steps: [
      ['سجّلوا شركتكم', 'اسم الشركة والإمارة والنشاط، ثم رقم جوال وبريد إلكتروني موثّقان.'],
      ['احصلوا على التوثيق', 'ارفعوا رخصة تجارية سارية وملف الشركة، وأدخلوا رقم الرخصة، ووافقوا على شروط المورّدين. يستغرق التوثيق حتى 3 أيام عمل.'],
      ['استقبلوا الأعمال المناسبة', 'تُطابَق الطلبات من جميع أنحاء الإمارات وفق نشاطكم وقدرتكم الفعلية، مع بيان سبب كل مطابقة.'],
      ['قدّموا عرضكم واستلموا قيمته', 'قدّموا عرضكم من خلال البوابة. تُدفع لكم قيمة العمل، وتتقاضى QuotesDone رسوم الكشف من العميل.'],
    ],
    honest: 'QuotesDone منصة جديدة، ولا توجد أعمال منجزة عليها بعد؛ لذا لا نعدكم هنا بتدفق مستمر للأعمال، بل بأن يُطابَق ما يصل وفق الملاءمة.',
    sealCustomer: 'العميل',
    sealPlaceholder: 'اسم العميل',
    sealNote: 'يصلكم كل طلب محجوب الهوية، ولا يُكشف اسم العميل إلا إذا اختار عرض سعركم.',
  },
};
const t = (lang: Lang) => T[lang] || T.en;

export default function SupplierEntryHero({ lang = 'en', onStart }:
  { lang?: Lang; onStart?: () => void }) {
  const L = t(lang);
  const [open, setOpen] = useState(false);

  return (
    <section className="mx-auto w-full max-w-3xl px-4 pt-10 text-center sm:pt-14" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <Kicker className="max-w-full justify-center text-balance">{L.kicker}</Kicker>

      <motion.h1
        initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.35 }}
        className="mx-auto mt-5 max-w-[20ch] text-balance font-head text-display-sm tracking-snug text-foreground"
      >
        {L.valueProp}
      </motion.h1>

      <p className="mx-auto mt-4 max-w-[58ch] text-lead text-muted-foreground">{L.sub}</p>

      {/* The brand motif, shown on the thing it protects: the supplier sees a customer as a sealed bar. */}
      <div className="qd-panel mx-auto mt-6 flex max-w-md flex-col items-center gap-2 px-5 py-4">
        <span className="flex items-center gap-2.5 font-mono text-label uppercase tracking-caps text-muted-foreground">
          {L.sealCustomer}
          <span aria-hidden><Seal>{L.sealPlaceholder}</Seal></span>
        </span>
        <span className="text-small text-muted-foreground">{L.sealNote}</span>
      </div>

      <div className="mt-6 flex flex-wrap items-center justify-center gap-2.5">
        <Button size="lg" onClick={() => onStart?.()}>{L.ctaPrimary}</Button>
        <Button size="lg" variant="outline" aria-expanded={open} onClick={() => setOpen((o) => !o)}>
          {L.ctaSecondary}
        </Button>
      </div>

      <AnimatePresence initial={false}>
        {open && (
          <motion.div
            initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.25 }}
            className="overflow-hidden text-start"
          >
            <div className="qd-panel mt-6 p-5 sm:p-6">
              <h2 className="mb-5 font-mono text-label uppercase tracking-caps text-muted-foreground">{L.stepsTitle}</h2>
              <Stepper steps={L.steps.map(([head, body]) => ({ title: head, body }))} />
              {/* The thing a launch page normally leaves out. */}
              <p className="mt-6 border-t border-border pt-4 text-small text-muted-foreground">{L.honest}</p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </section>
  );
}
