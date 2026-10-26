import { SupplierPortal } from '@/components/portal/SupplierPortal';
import { appShellMeta } from '@/lib/seo';

// The supplier portal is a signed-in application shell: localized title and description, a canonical,
// and noindex, from the one helper every app shell uses (audit 2026-09-14: /ar/portal shipped the
// English "QuotesDone — Supplier Portal" title with no description, canonical or robots rule).
export async function generateMetadata(p: { params: Promise<{ locale: string }> }) {
  return appShellMeta((await p.params).locale, 'portal');
}

export default function PortalPage() { return <SupplierPortal />; }
