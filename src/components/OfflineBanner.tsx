'use client';

import { useSyncExternalStore } from 'react';

// A calm notice while the browser has no network (launch checklist, 19 Nov 2026). Mounted once in the
// [locale] layout. It reads navigator.onLine and the window's online/offline events; the server snapshot
// is "online", so nothing is rendered on the server and there is no hydration mismatch. It is a status
// line, not an alert: role="status" announces politely, takes no focus and has nothing to dismiss because
// it goes away by itself when the connection returns. Wording is the layout's own inline en/ar pattern
// (as SKIP and the route-progress label), so it works even if the message files failed to load.
const TEXT = {
  en: "You're offline — we'll retry when you're back",
  ar: 'لا يوجد اتصال بالإنترنت — سنعيد المحاولة عند عودة الاتصال',
};

function subscribe(cb: () => void) {
  window.addEventListener('online', cb);
  window.addEventListener('offline', cb);
  return () => { window.removeEventListener('online', cb); window.removeEventListener('offline', cb); };
}

export function OfflineBanner({ lang }: { lang: 'en' | 'ar' }) {
  const online = useSyncExternalStore(subscribe, () => navigator.onLine, () => true);
  if (online) return null;
  return (
    <output
      aria-live="polite"
      className="fixed inset-x-0 top-0 z-[90] border-b border-line2 bg-navy-deep px-4 pb-2 pt-[max(0.5rem,env(safe-area-inset-top))] text-center text-[14px] text-paper shadow-e2"
    >
      {TEXT[lang]}
    </output>
  );
}
