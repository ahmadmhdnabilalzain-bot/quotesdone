import { notFound } from 'next/navigation';

// An unmatched path under a locale never reaches [locale]/not-found.tsx on its own: Next.js only
// renders a segment's not-found when notFound() is called inside it. Measured 19 Oct 2026: /zz-nope,
// /ar/zz-nope and /about/zz all served the framework's bare "404: This page could not be found."
// This catch-all routes every unknown path into the designed page, in the visitor's language.
export default function CatchAll() {
  notFound();
}
