'use client';
// Three anonymous quotes arrive in each supplier's own order, then level into one table: rows
// aligned by item, a missing-item flag where one supplier left scope out, and a best-match reason.
// Prices are redaction bars, never figures — a demonstration, not live data.
import { useEffect, useRef, useState } from 'react';
import { LayoutGroup, motion } from 'motion/react';
import { prefersReducedMotion, useSceneGate, type SceneProps } from './gate';

const ITEMS = {
  en: ['Gypsum partitions', 'Ceiling works', 'Paint & finishes', 'Doors & ironmongery', 'MEP first fix'],
  ar: ['قواطع الجبس', 'أعمال الأسقف', 'الدهانات والتشطيبات', 'الأبواب والإكسسوارات', 'التمديدات الكهروميكانيكية الأولى'],
};
const T = {
  en: { supplier: 'Supplier', hidden: 'identity hidden', missing: 'Missing item', best: 'Best match', reason: 'Complete scope · strongest verified track record', demo: 'Demonstration — not live data', item: 'Item',
    alt: 'Demonstration: three anonymous quotes are levelled into one table. Supplier C left out MEP first fix, which is flagged as a missing item. Supplier B is marked best match for complete scope and the strongest verified track record.' },
  ar: { supplier: 'المورّد', hidden: 'الهوية مخفية', missing: 'بند ناقص', best: 'الأنسب', reason: 'نطاق كامل · أقوى سجل موثّق', demo: 'عرض توضيحي — ليست بيانات حيّة', item: 'البند',
    alt: 'عرض توضيحي: تُوحَّد ثلاثة عروض مجهولة الهوية في جدول واحد. المورّد C أغفل التمديدات الكهروميكانيكية الأولى فظهر كبند ناقص، والمورّد B هو الأنسب لنطاقه الكامل وأقوى سجل موثّق.' },
};
const SUPPLIERS = ['A', 'B', 'C'];
const BEST = 1;
const MISSING = { s: 2, item: 4 };
// Each supplier's own ordering of the five items (as their PDF would list them).
const ORDER = [[2, 0, 4, 1, 3], [0, 1, 2, 3, 4], [3, 1, 0, 2]];
const BAR = [[62, 48, 70, 40, 56], [58, 52, 64, 44, 60], [54, 44, 60, 38, 0]];

export default function CompareLevelling({ locale }: SceneProps) {
  const ref = useRef<HTMLDivElement>(null);
  const { active } = useSceneGate(ref);
  const [phase, setPhase] = useState(2); // 0 as received · 1 levelled · 2 levelled + verdict
  const t = T[locale];

  useEffect(() => {
    if (!active || prefersReducedMotion()) return;
    const id = setInterval(() => setPhase((p) => (p + 1) % 3), 3000);
    return () => clearInterval(id);
  }, [active]);

  const levelled = phase > 0;
  const spring = { type: 'spring', stiffness: 260, damping: 30 } as const;

  return (
    <div ref={ref} dir={locale === 'ar' ? 'rtl' : 'ltr'} className="relative w-full overflow-x-auto">
      <LayoutGroup>
        <div className="grid min-w-[520px] gap-x-2 gap-y-1.5" style={{ gridTemplateColumns: 'minmax(120px,1.1fr) repeat(3,minmax(110px,1fr))' }} aria-hidden>
          <span className="self-end pb-1 font-mono text-[12px] uppercase tracking-[0.14em] text-faint" style={{ gridRow: 1, gridColumn: 1 }}>
            {t.item}
          </span>
          {SUPPLIERS.map((s, si) => (
            <div key={s} style={{ gridRow: 1, gridColumn: si + 2 }} className={`rounded-t-lg border-b px-2.5 pb-2 pt-1 transition-colors duration-500 ${phase === 2 && si === BEST ? 'border-gold/60 bg-gold/[0.06]' : 'border-[var(--line)]'}`}>
              <div className="flex items-center gap-1.5">
                <span className="font-head text-[13px] font-semibold text-white">{t.supplier} {s}</span>
                {phase === 2 && si === BEST && (
                  <motion.span initial={{ opacity: 0, scale: 0.85 }} animate={{ opacity: 1, scale: 1 }} className="rounded-full bg-gold/90 px-1.5 py-px font-mono text-[8.5px] font-semibold uppercase tracking-[0.12em] text-[#2A2000]">
                    {t.best}
                  </motion.span>
                )}
              </div>
              <span className="mt-1 flex items-center gap-1.5">
                <span className="redact h-2 w-12" />
                <span className="text-[12px] text-faint">{t.hidden}</span>
              </span>
            </div>
          ))}

          {ITEMS[locale].map((name, item) => (
            <motion.span key={name} animate={{ opacity: levelled ? 1 : 0 }} className="flex items-center text-[12px] text-paper/85" style={{ gridRow: item + 2, gridColumn: 1 }}>
              {name}
            </motion.span>
          ))}

          {SUPPLIERS.map((s, si) =>
            ITEMS[locale].map((name, item) => {
              const pos = ORDER[si].indexOf(item);
              const isMissing = si === MISSING.s && item === MISSING.item;
              if (isMissing && !levelled) return null;
              const row = (levelled ? item : pos) + 2;
              return (
                <motion.div
                  key={`${s}-${item}`}
                  layout
                  transition={spring}
                  style={{ gridRow: row, gridColumn: si + 2 }}
                  className={`flex min-h-[36px] items-center gap-2 rounded-md border px-2.5 py-1.5 ${
                    isMissing ? 'border-gold/60 bg-gold/[0.08]' : phase === 2 && si === BEST ? 'border-gold/25 bg-teal-light/[0.03]' : 'border-[var(--line)] bg-teal-light/[0.03]'
                  }`}
                >
                  {isMissing ? (
                    <span className="flex items-center gap-1.5 text-[12px] font-semibold text-gold">
                      <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden><path d="M6 1 11 10.5H1Z" fill="none" stroke="currentColor" strokeWidth="1.2" /><path d="M6 4.5v3M6 8.6v.4" stroke="currentColor" strokeWidth="1.2" /></svg>
                      {t.missing}
                    </span>
                  ) : (
                    <>
                      <motion.span animate={{ opacity: levelled ? 0 : 1, width: levelled ? 0 : 'auto' }} className="truncate text-[12px] text-muted">
                        {name}
                      </motion.span>
                      <span className="redact ms-auto h-2 shrink-0" style={{ width: BAR[si][item] * 0.8 }} />
                    </>
                  )}
                </motion.div>
              );
            }),
          )}
        </div>
      </LayoutGroup>

      <div className="mt-3 flex min-w-[520px] flex-wrap items-center justify-between gap-2 text-[12px]" aria-hidden>
        <motion.span animate={{ opacity: phase === 2 ? 1 : 0 }} className="text-gold/90">
          {t.supplier} {SUPPLIERS[BEST]} · {t.reason}
        </motion.span>
        <span className="font-mono text-[12px] text-faint">{t.demo}</span>
      </div>
      <p className="sr-only">{t.alt}</p>
    </div>
  );
}
