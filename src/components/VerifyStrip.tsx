import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { SectionHeader } from '@/components/SectionHeader';
import s from '@/components/home/sealed.module.css';

// "HOW WE VERIFY" — the third-party proof that is real today (website audit ADOPT 9): the licence
// check, the mandatory six, Stripe as the payment rail with the refund rule, and our own DET
// licence. Set as a numbered specification, not as cards.
type Item = { k: string; v: string };
export function VerifyStrip() {
  const t = useTranslations('verify');
  const items = t.raw('items') as Item[];
  return (
    <section id="verify" className="container-x py-beat-s md:py-beat">
      <SectionHeader
        eyebrow={t('eyebrow')}
        index="04"
        title={t('title')}
        aside={
          <Link href="/how-we-verify" className="text-[14.5px] font-semibold text-teal-light underline-offset-4 hover:underline">
            {t('link')} <span aria-hidden className="inline-block rtl:rotate-180">&rarr;</span>
          </Link>
        }
      />
      <dl className={`${s.rise} mt-12 grid border-t border-[var(--line2)] md:grid-cols-2 lg:grid-cols-4`}>
        {items.map((it, i) => (
          <div key={it.k} className="border-b border-[var(--line)] py-7 md:pe-8 lg:border-b-0 lg:[&:not(:first-child)]:border-s lg:[&:not(:first-child)]:ps-8">
            <span className="font-mono text-[12px] tabular text-teal-light">{String(i + 1).padStart(2, '0')}</span>
            <dt className="mt-4 font-head text-[18px] font-semibold tracking-[-0.02em] text-white rtl:tracking-normal">{it.k}</dt>
            <dd className="mt-2 text-[14px] leading-relaxed text-muted">{it.v}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
