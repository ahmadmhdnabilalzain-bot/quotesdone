'use client';
import { useLocale, useTranslations } from 'next-intl';
import { usePathname, useRouter } from '@/i18n/routing';

export function LangSwitch() {
  const t = useTranslations();
  const locale = useLocale();
  const pathname = usePathname();
  const router = useRouter();
  const other = locale === 'ar' ? 'en' : 'ar';
  return (
    <button
      onClick={() => router.replace(pathname, { locale: other })}
      className="whitespace-nowrap rounded-full border border-[var(--line2)] bg-teal-light/[0.04] px-2.5 py-1.5 text-[12px] font-semibold text-white transition-colors duration-200 hover:border-teal hover:bg-teal/[0.09] sm:px-4 sm:text-[13px]"
      aria-label="Language"
    >
      {t('langSwitch')}
    </button>
  );
}
