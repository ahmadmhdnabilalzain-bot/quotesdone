import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { Reveal } from '@/components/motion/primitives';

// "HOW WE VERIFY" — the third-party proof that is real today (website audit ADOPT 9): the licence
// check, the mandatory six, Stripe as the payment rail with the refund rule, and our own DET
// licence. The /how-we-verify page is built by the legal owner.
type Item = { k: string; v: string };
export function VerifyStrip() {
  const t = useTranslations('verify');
  const items = t.raw('items') as Item[];
  return (
    <section id="verify" className="container-x py-beat-s">
      <Reveal>
        <div className="relative overflow-hidden rounded-[22px] border border-[var(--line2)] bg-navy-deep/60">
          <span className="grid-tech grid-tech-sm opacity-40" aria-hidden />
          <div className="relative flex flex-col gap-2 border-b border-[var(--line)] px-7 py-5 md:flex-row md:items-center md:justify-between">
            <div>
              <span className="font-mono text-[11px] uppercase tracking-[0.2em] text-teal-light rtl:tracking-normal">{t('eyebrow')}</span>
              <h2 className="mt-1.5 font-head text-[22px] font-semibold tracking-[-0.02em] text-white">{t('title')}</h2>
            </div>
            <Link href="/how-we-verify" className="text-[14px] font-semibold text-teal-light underline-offset-4 hover:underline">
              {t('link')} <span aria-hidden className="inline-block rtl:rotate-180">&rarr;</span>
            </Link>
          </div>
          <dl className="relative grid gap-px bg-[var(--line)] md:grid-cols-4">
            {items.map((it) => (
              <div key={it.k} className="bg-navy-deep/90 px-7 py-6">
                <dt className="flex items-center gap-2 font-head text-[15px] font-semibold text-white">
                  <span className="node-dot" aria-hidden />{it.k}
                </dt>
                <dd className="mt-2 text-[13.5px] leading-relaxed text-muted">{it.v}</dd>
              </div>
            ))}
          </dl>
        </div>
      </Reveal>
    </section>
  );
}
