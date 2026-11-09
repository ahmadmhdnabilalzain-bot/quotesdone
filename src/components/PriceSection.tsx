import { useTranslations } from 'next-intl';
import { SectionHeader } from '@/components/SectionHeader';
import { PriceGuide } from '@/components/PriceGuide';
import '@/components/home/sealed.module.css';

export function PriceSection() {
  const t = useTranslations('price');
  return (
    <section id="price" className="container-x py-beat-s md:py-beat">
      <div className="grid gap-12 lg:grid-cols-12 lg:gap-10">
        <div className="lg:col-span-5">
          <SectionHeader eyebrow={t('eyebrow')} index="05" title={t('title')} sub={t('sub')} />
        </div>
        <div className={`reveal lg:col-span-7`}>
          <PriceGuide />
        </div>
      </div>
    </section>
  );
}
