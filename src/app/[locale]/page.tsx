import { setRequestLocale, getTranslations } from 'next-intl/server';
import { buildMeta } from '@/lib/seo';
import { SiteHeader } from '@/components/SiteHeader';
import { Hero } from '@/components/Hero';
import { EngineStrip } from '@/components/EngineStrip';
import { TwoSided } from '@/components/TwoSided';
import { HowItWorks } from '@/components/HowItWorks';
import { PriceSection } from '@/components/PriceSection';
import { WhyAnonymous } from '@/components/WhyAnonymous';
import { VerifyStrip } from '@/components/VerifyStrip';
import { Categories } from '@/components/Categories';
import { CtaBand } from '@/components/CtaBand';
import { SiteFooter } from '@/components/SiteFooter';

export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  const t = await getTranslations({ locale, namespace: 'meta' });
  return buildMeta({ locale, path: '/', title: t('siteTitle'), description: t('siteDesc') });
}

export default async function HomePage(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return (
    <>
      <SiteHeader />
      <main id="main">
        <Hero />
        <EngineStrip />
        <TwoSided />
        <HowItWorks />
        <PriceSection />
        <WhyAnonymous />
        <VerifyStrip />
        <Categories />
        <CtaBand />
      </main>
      <SiteFooter />
    </>
  );
}
