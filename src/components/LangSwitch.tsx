'use client';
import { useTransition } from 'react';
import { useLocale, useTranslations } from 'next-intl';
import { usePathname, useRouter } from '@/i18n/routing';
import { Spinner, useDelayedFlag } from '@/components/ui/busy';
import { startRouteProgress } from '@/components/ui/route-progress';

// A quiet pill with a globe glyph; the visible word is the OTHER language and carries lang on its own
// span, so the Arabic word renders in Readex Pro even on an English page (globals.css [lang] scoping)
// while the button’s aria-label stays in the page’s language.
export function LangSwitch() {
  const t = useTranslations();
  const locale = useLocale();
  const pathname = usePathname();
  const router = useRouter();
  const other = locale === 'ar' ? 'en' : 'ar';
  // Switching locale re-renders the whole page server-side. It was silent, and the button stayed
  // live, so repeated presses queued navigations.
  const [pending, start] = useTransition();
  const shown = useDelayedFlag(pending);
  return (
    <button
      type="button"
      disabled={pending}
      aria-busy={shown || undefined}
      onClick={() => { startRouteProgress(); start(() => router.replace(pathname, { locale: other })); }}
      className="qd-hoverlit inline-flex h-9 items-center gap-1.5 whitespace-nowrap rounded-pill border border-line2 bg-teal-light/3 px-3 text-small font-medium text-paper transition-colors duration-base hover:border-line3 hover:bg-teal-light/6 disabled:cursor-progress sm:px-3.5"
      aria-label={t('langSwitchLabel')}
    >
      {shown ? <Spinner className="text-teal-light" /> : (
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" className="text-teal-light" aria-hidden>
          <circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3c2.6 2.8 2.6 15.2 0 18M12 3c-2.6 2.8-2.6 15.2 0 18" />
        </svg>
      )}
      {/* WEB-13: lang={other} used to sit on the BUTTON, so a screen reader announced the
          aria-label — written in the CURRENT language — with the other language’s voice. Only the
          visible word is in the other language, so only the word carries lang. */}
      <span lang={other}>{t('langSwitch')}</span>
    </button>
  );
}
