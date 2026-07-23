import { setRequestLocale } from 'next-intl/server';
import { BlogPost, blogSlugs, blogMeta } from '@/components/BlogPost';

// Only the dynamic param — next-intl's `as-needed` prefixing handles the locale,
// exactly as services/[slug] does. Returning `locale` here breaks the unprefixed
// English path.
export function generateStaticParams() { return blogSlugs().map((slug) => ({ slug })); }

export async function generateMetadata(props: { params: Promise<{ locale: string; slug: string }> }) {
  const params = await props.params;

  const {
    locale,
    slug
  } = params;

  return blogMeta(slug, locale);
}
export default async function Page(props: { params: Promise<{ locale: string; slug: string }> }) {
  const params = await props.params;

  const {
    locale,
    slug
  } = params;

  setRequestLocale(locale);
  return <BlogPost slug={slug} locale={locale} />;
}
