import { renderOg, OG_SIZE } from '@/lib/og';
import en from '../../../messages/en.json';
import ar from '../../../messages/ar.json';

// The locale's brand card. buildMeta (src/lib/seo.ts) points every page's og:image and
// twitter:image here unless its segment ships its own (blog posts, service pages).
export const size = OG_SIZE;
export const contentType = 'image/png';
export const alt = 'QuotesDone';

export default async function Image(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  const m = locale === 'ar' ? ar : en;
  const title = m.meta.siteTitle.replace(/^QuotesDone\s*[—-]\s*/, '');
  return renderOg({ locale, kicker: locale === 'ar' ? 'سوق عروض الأسعار' : 'Quotation marketplace', title });
}
