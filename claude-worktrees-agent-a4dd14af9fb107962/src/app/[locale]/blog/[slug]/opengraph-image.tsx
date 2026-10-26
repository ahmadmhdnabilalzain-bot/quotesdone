import { renderOg, OG_SIZE } from '@/lib/og';
import posts from '@/content/blog.json';

export const size = OG_SIZE;
export const contentType = 'image/png';
export const alt = 'QuotesDone blog';

const P = posts as unknown as Record<string, { title: string }>;

export default async function Image(props: { params: Promise<{ locale: string; slug: string }> }) {
  const { locale, slug } = await props.params;
  const title = P[slug]?.title ?? 'QuotesDone';
  // Posts are English-only, so the title stays LTR even on the Arabic card.
  return renderOg({ locale, kicker: locale === 'ar' ? 'المدونة' : 'Blog', title, rtl: false });
}
