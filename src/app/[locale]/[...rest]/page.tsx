import { notFound } from 'next/navigation';

// A path no route claims (e.g. /zz-no-such-page, /ar/zz) never reached [locale]/not-found.tsx: Next
// only renders a segment's not-found when something inside that segment calls notFound(). Measured
// on production 19 Oct 2026 (public QA): /zz-no-such-page and /ar/zz-no-such-page on .com and .ae
// returned the bare framework "404: This page could not be found." with no header, footer or way
// onward, while /blog/<missing> (which calls notFound()) showed the branded page. This catch-all is
// the next-intl pattern: claim every unmatched path inside [locale] and hand it to that page.
export default function CatchAll() {
  notFound();
}
