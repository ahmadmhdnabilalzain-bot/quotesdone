import { defineRouting } from 'next-intl/routing';
import { createNavigation } from 'next-intl/navigation';

// ONE source of truth for locales. Add a language here and every page gets it —
// no duplicated pages. 'en' is the default (served at /), 'ar' served at /ar.
export const routing = defineRouting({
  locales: ['en', 'ar'],
  defaultLocale: 'en',
  localePrefix: 'as-needed'
});

export const { Link, usePathname, useRouter } = createNavigation(routing);
