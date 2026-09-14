'use client';
import { useLocale, useTranslations } from 'next-intl';
import { usePathname, useRouter } from '@/i18n/routing';

// A quiet pill with a globe glyph; its label is set in the OTHER language (lang attr), so the
// Arabic word renders in Readex Pro even on an English page (globals.css [lang] scoping).
export function LangSwitch() {
  const t = useTranslations();
  const locale = useLocale();
  const pathname = usePathname();
  const router = useRouter();
  const other = locale === 'ar' ? 'en' : 'ar';
  return (
    <button
      type="button"
      onClick={() => router.replace(pathname, { locale: other })}
      className="qd-hoverlit inline-flex h-9 items-center gap-1.5 whitespace-nowrap rounded-pill border border-line2 bg-teal-light/[0.03] px-3 text-small font-medium text-paper transition-colors duration-base hover:border-line3 hover:bg-teal-light/[0.06] sm:px-3.5"
      aria-label={t('langSwitchLabel')}
      lang={other}
    >
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" className="text-teal-light" aria-hidden>
        <circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3c2.6 2.8 2.6 15.2 0 18M12 3c-2.6 2.8-2.6 15.2 0 18" />
      </svg>
      {t('langSwitch')}
    </button>
  );
}
