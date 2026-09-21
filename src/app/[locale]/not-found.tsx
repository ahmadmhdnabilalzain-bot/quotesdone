import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { Link } from '@/i18n/routing';
import { getLocale } from 'next-intl/server';

// THE PAGE THAT WAS NOT THERE, IN THE VISITOR'S LANGUAGE (public audit 21 Sep 2026, item 14). Until
// today a wrong URL got Next.js's bare black English "404 | This page could not be found" on both /
// and /ar — no header, no footer, no way onward. This file renders inside the [locale] layout, so it
// carries the site chrome and the locale's direction, and it names the three places a lost visitor
// usually wanted. Unknown locale prefixes still fall to the framework page: the layout has to reject
// them before it can render anything, and next-intl's middleware sends unprefixed paths here.
const T = {
  en: { code: 'Page not found', h: 'That page is not here.', p: 'The link may be out of date, or the address mistyped. These pages are.', home: 'Home', services: 'Services', contact: 'Contact us' },
  ar: { code: 'الصفحة غير موجودة', h: 'هذه الصفحة ليست هنا.', p: 'قد يكون الرابط قديمًا أو العنوان مكتوبًا بشكل خاطئ. هذه الصفحات موجودة.', home: 'الرئيسية', services: 'الخدمات', contact: 'تواصل معنا' },
};

export default async function NotFound() {
  const locale = await getLocale();
  const l = locale === 'ar' ? 'ar' : 'en';
  const t = T[l];
  return (<>
    <SiteHeader />
    <main id="main" dir={l === 'ar' ? 'rtl' : 'ltr'} className="mx-auto flex min-h-[60vh] w-full max-w-[720px] flex-col justify-center px-6 py-20 text-start">
      <p className="font-mono text-label uppercase tracking-caps text-teal-light">404 · {t.code}</p>
      <h1 className="mt-3 font-head text-[32px] font-extrabold leading-tight tracking-tight text-white sm:text-[40px]">{t.h}</h1>
      <p className="mt-3 max-w-[52ch] text-[15px] leading-relaxed text-muted">{t.p}</p>
      <nav aria-label={t.code} className="mt-6 flex flex-wrap gap-3">
        <Link href="/" className="rounded-btn bg-teal px-4 py-2 text-[14px] font-semibold text-navy-deep no-underline">{t.home}</Link>
        <Link href="/services" className="rounded-btn border border-line2 px-4 py-2 text-[14px] font-semibold text-white no-underline">{t.services}</Link>
        <Link href="/contact" className="rounded-btn border border-line2 px-4 py-2 text-[14px] font-semibold text-white no-underline">{t.contact}</Link>
      </nav>
    </main>
    <SiteFooter />
  </>);
}
