import { setRequestLocale } from 'next-intl/server';
import { BlogPost, blogSlugs, blogMeta } from '@/components/BlogPost';

// Only the dynamic param — next-intl's `as-needed` prefixing handles the locale,
// exactly as services/[slug] does. Returning `locale` here breaks the unprefixed
// English path.
export function generateStaticParams() { return blogSlugs().map((slug) => ({ slug })); }

export function generateMetadata({ params: { slug } }: { params: { locale: string; slug: string } }) {
  return blogMeta(slug);
}
export default function Page({ params: { locale, slug } }: { params: { locale: string; slug: string } }) {
  setRequestLocale(locale);
  return <BlogPost slug={slug} locale={locale} />;
}
