import type { Metadata } from 'next';
import { SupplierPortal } from '@/components/portal/SupplierPortal';
import { buildMeta } from '@/lib/seo';

// The supplier portal is a signed-in application shell, not content: it is kept out of the index
// (noindex) but still carries a localized title/description and a canonical, so /ar/portal no longer
// ships the English "QuotesDone — Supplier Portal" title with no description (audit 2026-09-14).
export async function generateMetadata(props: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await props.params;
  const ar = locale === 'ar';
  const meta = buildMeta({
    locale,
    path: '/portal',
    title: ar ? 'بوابة المورّدين — QuotesDone' : 'Supplier portal — QuotesDone',
    description: ar
      ? 'بوابة المورّدين في QuotesDone: استقبل طلبات تسعير مجهولة الهوية تطابق تخصصك وإمارتك، وقدّم عروضك بلا عمولة على الأعمال التي تفوز بها.'
      : 'The QuotesDone supplier portal: receive anonymous requests for quotation that match your trade and emirate, and quote with no commission on the work you win.',
  });
  return { ...meta, robots: { index: false, follow: false } };
}

export default function PortalPage() { return <SupplierPortal />; }
