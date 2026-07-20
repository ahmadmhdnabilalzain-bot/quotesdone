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
      className="rounded-full border border-white/25 bg-navy-deep/70 px-4 py-1.5 text-[13px] font-semibold text-white hover:bg-white/10"
      aria-label="Language"
    >
      {t('langSwitch')}
    </button>
  );
}
