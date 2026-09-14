import { setRequestLocale } from 'next-intl/server';
import { BlogPost, blogSlugs, blogMeta, localized, blogT, type Post } from '@/components/BlogPost';
import posts from '@/content/blog.json';
import { SITE, ldHtml, blogPostingLd, breadcrumbLd, textFromHtml } from '@/lib/seo';

// Only the dynamic param — next-intl's `as-needed` prefixing handles the locale,
// exactly as services/[slug] does. Returning `locale` here breaks the unprefixed
// English path.
export function generateStaticParams() { return blogSlugs().map((slug) => ({ slug })); }

const P = posts as unknown as Record<string, Post>;

export async function generateMetadata(props: { params: Promise<{ locale: string; slug: string }> }) {
  const { locale, slug } = await props.params;
  const m = blogMeta(slug, locale);
  // The post's own card (./opengraph-image.tsx); config images otherwise win over the segment file.
  const img = `${SITE}${locale === 'ar' ? '/ar' : ''}/blog/${slug}/opengraph-image`;
  return { ...m, openGraph: { ...m.openGraph, images: [{ url: img, width: 1200, height: 630 }] }, twitter: { ...m.twitter, images: [img] } };
}
export default async function Page(props: { params: Promise<{ locale: string; slug: string }> }) {
  const { locale, slug } = await props.params;
  setRequestLocale(locale);
  const p = P[slug];
  // W22: the structured data speaks the page's language. A post with no Arabic body stays English
  // (localized() says which), but the crumbs and URLs follow the /ar page the reader is on.
  const b = p ? localized(p, locale) : null;
  const t = blogT(locale);
  const base = `${SITE}${locale === 'ar' ? '/ar' : ''}`;
  return (<>
    {p && b && <script type="application/ld+json" dangerouslySetInnerHTML={ldHtml([
      blogPostingLd({ slug, title: b.title, description: b.meta_desc || b.excerpt || textFromHtml(b.body_html),
        published: p.published_at, author: p.author, category: b.category, locale: b.lang === 'ar' ? 'ar' : undefined }),
      breadcrumbLd([
        { name: t.home, url: base },
        { name: t.blog, url: `${base}/blog` },
        { name: b.title, url: `${base}/blog/${slug}` },
      ]),
    ])} />}
    <BlogPost slug={slug} locale={locale} />
  </>);
}
