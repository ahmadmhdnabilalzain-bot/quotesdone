import { setRequestLocale, getTranslations } from 'next-intl/server';
import { buildMeta } from '@/lib/seo';
import { SiteHeader } from '@/components/SiteHeader';
import { Hero } from '@/components/Hero';
import { HowItWorks } from '@/components/HowItWorks';
import { WhyAnonymous } from '@/components/WhyAnonymous';
import { Categories } from '@/components/Categories';
import { CtaBand } from '@/components/CtaBand';
import { SiteFooter } from '@/components/SiteFooter';

export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const params = await props.params;

  const {
    locale
  } = params;

  const t = await getTranslations({ locale, namespace: 'meta' });
  return buildMeta({ locale, path: '/', title: t('siteTitle'), description: t('siteDesc') });
}

export default async function HomePage(props: { params: Promise<{ locale: string }> }) {
  const params = await props.params;

  const {
    locale
  } = params;

  setRequestLocale(locale);
  return (
    <>
      <SiteHeader />
      <main id="main">
        <Hero />
        <HowItWorks />
        <WhyAnonymous />
        <Categories />
        <CtaBand />
      </main>
      <SiteFooter />
    </>
  );
}
