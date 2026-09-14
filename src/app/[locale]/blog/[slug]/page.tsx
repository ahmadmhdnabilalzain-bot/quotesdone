import { setRequestLocale } from 'next-intl/server';
import { BlogPost, blogSlugs, blogMeta } from '@/components/BlogPost';
import posts from '@/content/blog.json';
import { SITE, ldHtml, blogPostingLd, breadcrumbLd, textFromHtml } from '@/lib/seo';

// Only the dynamic param — next-intl's `as-needed` prefixing handles the locale,
// exactly as services/[slug] does. Returning `locale` here breaks the unprefixed
// English path.
export function generateStaticParams() { return blogSlugs().map((slug) => ({ slug })); }

type Post = { title: string; excerpt: string | null; meta_desc: string | null; body_html: string; author: string | null; category: string | null; published_at: string | null };
const P = posts as unknown as Record<string, Post>;

export async function generateMetadata(props: { params: Promise<{ locale: string; slug: string }> }) {
  const { locale, slug } = await props.params;
  return blogMeta(slug, locale);
}
export default async function Page(props: { params: Promise<{ locale: string; slug: string }> }) {
  const { locale, slug } = await props.params;
  setRequestLocale(locale);
  const p = P[slug];
  return (<>
    {p && <script type="application/ld+json" dangerouslySetInnerHTML={ldHtml([
      blogPostingLd({ slug, title: p.title, description: p.meta_desc || p.excerpt || textFromHtml(p.body_html),
        published: p.published_at, author: p.author, category: p.category }),
      breadcrumbLd([
        { name: 'Home', url: SITE },
        { name: 'Blog', url: `${SITE}/blog` },
        { name: p.title, url: `${SITE}/blog/${slug}` },
      ]),
    ])} />}
    <BlogPost slug={slug} locale={locale} />
  </>);
}
