import { SupplierPortal } from '@/components/portal/SupplierPortal';
import { SupplierBootPrefetch } from '@/components/me/BootPrefetch';
import { PortalBootFallback } from '@/components/portal/supplier/PortalBootFallback';
import { appShellMeta } from '@/lib/seo';

// The supplier portal is a signed-in application shell: localized title and description, a canonical,
// and noindex, from the one helper every app shell uses (audit 2026-09-14: /ar/portal shipped the
// English "QuotesDone — Supplier Portal" title with no description, canonical or robots rule).
export async function generateMetadata(p: { params: Promise<{ locale: string }> }) {
  return appShellMeta((await p.params).locale, 'portal');
}

// The supplier's two first reads start when the HTML is parsed (BootPrefetch.tsx SupplierBootPrefetch), so it comes FIRST.
// A server-rendered line says the portal is opening, and offers a reload if its script never runs (PortalBootFallback).
export default function PortalPage() { return <><SupplierBootPrefetch /><PortalBootFallback /><SupplierPortal /></>; }
