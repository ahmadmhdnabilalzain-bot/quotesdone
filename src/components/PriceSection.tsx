import { useTranslations } from 'next-intl';
import { SectionHeader } from '@/components/SectionHeader';
import { PriceGuide } from '@/components/PriceGuide';

export function PriceSection() {
  const t = useTranslations('price');
  return (
    <section id="price" className="container-x py-beat-s md:py-beat">
      <SectionHeader eyebrow={t('eyebrow')} index="04" title={t('title')} sub={t('sub')} />
      <div className="mx-auto mt-12 max-w-[820px]">
        <PriceGuide />
      </div>
    </section>
  );
}
