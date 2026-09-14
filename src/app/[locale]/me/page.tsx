import type { Metadata } from 'next';
import { CustomerPortal } from '@/components/me/CustomerPortal';

// The portal is a signed-in shell: it has no content a search engine should hold, and on /ar it
// was indexed under an English title (audit 14 Sep 2026). Localised title, never indexed.
export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  const ar = locale === 'ar';
  return {
    title: ar ? 'QuotesDone — طلباتي' : 'QuotesDone — My Requests',
    description: ar ? 'بوابة العملاء: انشر طلبك وقارن عروض الأسعار بشكل مجهول.' : 'Customer portal: post a request and compare anonymous quotes.',
    robots: { index: false, follow: false },
  };
}

export default function MePage() { return <CustomerPortal />; }
