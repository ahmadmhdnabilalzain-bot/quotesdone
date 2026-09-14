import { setRequestLocale, getTranslations } from 'next-intl/server';
import { buildMeta } from '@/lib/seo';
import { SiteHeader } from '@/components/SiteHeader';
import { Hero } from '@/components/Hero';
import { ProductShowcase } from '@/components/home/ProductShowcase';
import { EngineStrip } from '@/components/EngineStrip';
import { TwoSided } from '@/components/TwoSided';
import { VerifyStrip } from '@/components/VerifyStrip';
import { PriceSection } from '@/components/PriceSection';
import { Categories } from '@/components/Categories';
import { CtaBand } from '@/components/CtaBand';
import { SiteFooter } from '@/components/SiteFooter';

export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  const t = await getTranslations({ locale, namespace: 'meta' });
  return buildMeta({ locale, path: '/', title: t('siteTitle'), description: t('siteDesc') });
}

// The Sealed homepage: one idea per section, in the order a buyer decides. The promise (hero),
// the product doing it on a sample job (#how), the six rules behind it (#why), both sides of the
// market, the proof, the price guide, the trades (#cats), and one closing ask.
export default async function HomePage(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return (
    <>
      <SiteHeader />
      <main id="main" className="bg-navy-deep">
        <Hero />
        <ProductShowcase />
        <EngineStrip />
        <TwoSided />
        <VerifyStrip />
        <PriceSection />
        <Categories />
        <CtaBand />
      </main>
      <SiteFooter />
    </>
  );
}
