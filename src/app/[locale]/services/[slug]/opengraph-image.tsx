import { renderOg, OG_SIZE } from '@/lib/og';
import { splitServiceSlug } from '@/lib/seo';
import services from '@/content/services.json';

export const size = OG_SIZE;
export const contentType = 'image/png';
export const alt = 'QuotesDone service';

const S = services as unknown as Record<string, Record<string, { title: string }>>;

export default async function Image(props: { params: Promise<{ locale: string; slug: string }> }) {
  const { locale, slug } = await props.params;
  // Emirate pages canonicalise to their parent service, so they share its card.
  const { service } = splitServiceSlug(slug);
  const d = S[service];
  const raw = (d?.[locale] ?? d?.en)?.title ?? 'QuotesDone';
  const uae = locale === 'ar' ? 'الإمارات' : 'the UAE';
  const title = raw.replace(/\{\{LOC_THE\}\}/g, uae).replace(/\{\{LOC\}\}/g, locale === 'ar' ? 'الإمارات' : 'UAE');
  return renderOg({ locale, kicker: locale === 'ar' ? 'الخدمات' : 'Services', title });
}
