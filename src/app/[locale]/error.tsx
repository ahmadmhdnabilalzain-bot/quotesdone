'use client';

import { useEffect } from 'react';
import { useParams } from 'next/navigation';

// THE PAGE A CRASH LANDS ON, IN THE VISITOR'S LANGUAGE (launch-readiness audit, 9 Nov 2026).
// Before this file a render error anywhere under /[locale] showed Next.js's bare English error screen,
// with no way onward. This boundary renders inside the [locale] layout, so the visitor keeps the
// direction and fonts of their language, and it offers a retry (reset re-renders the failed segment)
// and a way home. Server-side render errors are already reported to the estate by
// src/instrumentation.ts (onRequestError → site_error_ingest); the digest shown here is the same id,
// so a visitor who quotes it to support can be matched to that report.
const T = {
  en: { code: 'Something went wrong', h: 'This page did not load.', p: 'It is our fault, not yours. Try again, or go back to the home page.', retry: 'Try again', home: 'Home', ref: 'Reference' },
  ar: { code: 'حدث خطأ', h: 'تعذّر تحميل هذه الصفحة.', p: 'الخطأ من جهتنا وليس منك. حاول مرة أخرى، أو عُد إلى الصفحة الرئيسية.', retry: 'حاول مرة أخرى', home: 'الرئيسية', ref: 'رقم المرجع' },
};

export default function LocaleError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const params = useParams<{ locale?: string }>();
  const l = params?.locale === 'ar' ? 'ar' : 'en';
  const t = T[l];

  useEffect(() => {
    // The browser console is the one place a client-only error is visible during support; keep it.
    console.error(error);
  }, [error]);

  return (
    <main id="main" dir={l === 'ar' ? 'rtl' : 'ltr'} className="mx-auto flex min-h-[60vh] w-full max-w-[720px] flex-col justify-center px-6 py-20 text-start">
      <p className="font-mono text-label uppercase tracking-caps text-teal-light">{t.code}</p>
      <h1 className="mt-3 font-head text-[32px] font-extrabold leading-tight tracking-tight text-white sm:text-[40px]">{t.h}</h1>
      <p className="mt-3 max-w-[52ch] text-[15px] leading-relaxed text-muted">{t.p}</p>
      <div className="mt-6 flex flex-wrap gap-3">
        <button type="button" onClick={() => reset()} className="rounded-btn bg-teal px-4 py-2 text-[14px] font-semibold text-navy-deep">{t.retry}</button>
        <a href={l === 'ar' ? '/ar' : '/'} className="rounded-btn border border-line2 px-4 py-2 text-[14px] font-semibold text-white no-underline">{t.home}</a>
      </div>
      {error.digest ? <p className="mt-6 font-mono text-[12px] text-muted">{t.ref}: {error.digest}</p> : null}
    </main>
  );
}
