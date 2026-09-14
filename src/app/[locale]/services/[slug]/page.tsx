import { setRequestLocale } from 'next-intl/server';
import { ServiceDoc, svcParams, svcMeta } from '@/components/ServiceDoc';
import { SITE, buildMeta, splitServiceSlug, ldHtml, serviceLd, breadcrumbLd } from '@/lib/seo';

export function generateStaticParams() { return svcParams().map((slug) => ({ slug })); }

const EMIRATE_NAME: Record<string, { en: string; ar: string }> = {
  'abu-dhabi': { en: 'Abu Dhabi', ar: 'أبوظبي' }, ajman: { en: 'Ajman', ar: 'عجمان' }, dubai: { en: 'Dubai', ar: 'دبي' },
  fujairah: { en: 'Fujairah', ar: 'الفجيرة' }, 'ras-al-khaimah': { en: 'Ras Al Khaimah', ar: 'رأس الخيمة' },
  sharjah: { en: 'Sharjah', ar: 'الشارقة' }, 'umm-al-quwain': { en: 'Umm Al Quwain', ar: 'أم القيوين' },
};

export async function generateMetadata(props: { params: Promise<{ locale: string; slug: string }> }) {
  const { locale, slug } = await props.params;
  const m = svcMeta(slug, locale);
  const { service, emirate } = splitServiceSlug(slug);
  // Emirate pages are {{LOC}} substitutions of the parent service page; until they carry content of
  // their own, the canonical (and hreflang set) is the parent's.
  if (emirate && typeof m.title === 'string') {
    const parent = buildMeta({ locale, path: '/services/' + slug, canonicalPath: '/services/' + service, title: m.title, description: m.description ?? undefined });
    return { ...m, alternates: parent.alternates, openGraph: { ...m.openGraph, url: parent.alternates?.canonical as string } };
  }
  return m;
}

export default async function Page(props: { params: Promise<{ locale: string; slug: string }> }) {
  const { locale, slug } = await props.params;
  setRequestLocale(locale);
  const m = svcMeta(slug, locale);
  const { emirate } = splitServiceSlug(slug);
  const ar = locale === 'ar';
  const pre = ar ? `${SITE}/ar` : SITE;
  const name = typeof m.title === 'string' ? m.title : 'QuotesDone';
  const area = emirate ? EMIRATE_NAME[emirate][ar ? 'ar' : 'en'] : (ar ? 'الإمارات العربية المتحدة' : 'United Arab Emirates');
  return (<>
    <script type="application/ld+json" dangerouslySetInnerHTML={ldHtml([
      serviceLd({ name, description: m.description ?? name, url: `${pre}/services/${slug}`, areaServed: area, locale }),
      breadcrumbLd([
        { name: ar ? 'الرئيسية' : 'Home', url: pre },
        { name: ar ? 'الخدمات' : 'Services', url: `${pre}/services` },
        { name, url: `${pre}/services/${slug}` },
      ]),
    ])} />
    <ServiceDoc slug={slug} locale={locale} />
  </>);
}
