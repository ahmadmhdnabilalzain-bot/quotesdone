import { setRequestLocale } from 'next-intl/server';
import { SiteHeader } from '@/components/SiteHeader';
import { Hero } from '@/components/Hero';
import { HowItWorks } from '@/components/HowItWorks';
import { WhyAnonymous } from '@/components/WhyAnonymous';
import { Categories } from '@/components/Categories';
import { CtaBand } from '@/components/CtaBand';
import { SiteFooter } from '@/components/SiteFooter';

export default function HomePage({ params: { locale } }: { params: { locale: string } }) {
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
