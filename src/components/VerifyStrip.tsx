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
      <dl className={`reveal mt-12 grid border-t border-(--line2) md:grid-cols-2 lg:grid-cols-4`}>
        {items.map((it, i) => (
          <div key={it.k} className="border-b border-(--line) py-7 md:pe-8 lg:border-b-0 lg:not-first:border-s lg:not-first:ps-8">
            {/* The index sits inside the <dt>: a <div> in a <dl> may hold only dt/dd, and the bare <span>
                here cost the homepage its accessibility 1.0 (Lighthouse definition-list, 14 Sep 2026). */}
            <dt className="font-head text-[18px] font-semibold tracking-[-0.02em] text-white rtl:tracking-normal">
              <span className="mb-4 block font-mono text-[12px] font-normal tracking-normal tabular text-teal-light" aria-hidden>{String(i + 1).padStart(2, '0')}</span>
              {it.k}
            </dt>
            <dd className="mt-2 text-[14px] leading-relaxed text-muted">{it.v}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
