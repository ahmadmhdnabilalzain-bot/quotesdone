import posts from '@/content/blog.json';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { Link } from '@/i18n/routing';
import { getTranslations } from 'next-intl/server';
import { notFound } from 'next/navigation';
import { buildMeta, textFromHtml } from '@/lib/seo';

type Post = {
  slug: string; title: string; excerpt: string | null; meta_desc: string | null;
  body_html: string; author: string | null; category: string | null;
  published_at: string | null; sort: number | null;
};
const P = posts as unknown as Record<string, Post>;

export function blogSlugs(): string[] { return Object.keys(P); }

export function blogMeta(slug: string, locale = 'en') {
  const p = P[slug];
  if (!p) return { title: 'QuotesDone' };
  return buildMeta({
    locale,
    path: '/blog/' + slug,
    title: `${p.title} — QuotesDone`,
    description: p.meta_desc || p.excerpt || textFromHtml(p.body_html),
    type: 'article',
    publishedTime: p.published_at,
    // posts exist in English only — do not advertise an Arabic alternate
    bilingual: false,
  });
}

const fmt = (iso: string | null, locale: string) => {
  if (!iso) return null;
  try {
    return new Date(iso).toLocaleDateString(locale === 'ar' ? 'ar-AE' : 'en-GB',
      { year: 'numeric', month: 'long', day: 'numeric' });
  } catch { return null; }
};

export async function BlogPost({ slug, locale }: { slug: string; locale: string }) {
  const tb = await getTranslations({ locale, namespace: 'blog' });
  const p = P[slug];
  if (!p) return notFound();
  const date = fmt(p.published_at, locale);
  return (
    <>
      <SiteHeader />
      <main id="main" className="container-x py-beat-s md:py-beat" dir={locale === 'ar' ? 'rtl' : 'ltr'}>
        <nav
          aria-label="Breadcrumb"
          className="mb-8 inline-flex items-center gap-2.5 rounded-full border border-[var(--line2)] bg-teal-light/[0.05] px-3.5 py-1.5 font-mono text-[11px] uppercase tracking-[0.16em] text-faint backdrop-blur"
        >
          <span className="node-dot" aria-hidden />
          <Link href="/" className="transition-colors hover:text-teal-light">Home</Link>
          <span className="text-teal/50">/</span>
          <Link href="/blog/" className="transition-colors hover:text-teal-light">Blog</Link>
        </nav>

        <article className="max-w-[820px]">
          <header className="border-b border-[var(--line)] pb-8">
            {p.category && (
              <p className="font-mono text-[11px] font-semibold uppercase tracking-[0.2em] text-gold">{p.category}</p>
            )}
            <h1 lang="en" dir="ltr" className="text-brand-grad mt-4 max-w-[20ch] text-balance font-head text-[clamp(28px,4vw,46px)] font-semibold leading-[1.08] tracking-[-0.035em]">
              {p.title}
            </h1>
            {p.excerpt && (
              <p lang="en" dir="ltr" className="mt-5 max-w-[62ch] text-pretty text-[17px] leading-relaxed text-muted">{p.excerpt}</p>
            )}
            <p className="mt-6 font-mono text-[11px] text-faint">
              {p.author}{p.author && date ? ' · ' : ''}{date}
            </p>
          </header>

          {locale !== 'en' && (
            <p className="mt-8 rounded-xl border border-[var(--line2)] bg-teal-light/[0.05] px-4 py-3 text-[14px] text-muted">
              {tb('onlyEnglish')}
            </p>
          )}

          {/* content is English regardless of the page locale — declare it so
              screen readers and translation tools handle it correctly */}
          <div
            lang="en"
            dir="ltr"
            className="qd-prose mt-10"
            dangerouslySetInnerHTML={{ __html: p.body_html }}
          />

          <aside className="glass mesh-glow relative mt-14 overflow-hidden rounded-[22px] p-8 text-center sm:p-10">
            <span className="corners absolute inset-3" aria-hidden />
            <p className="inline-flex items-center gap-2.5 font-mono text-[10.5px] font-semibold uppercase tracking-[0.2em] text-teal-light">
              <span className="node-dot" aria-hidden />
              Ready when you are
            </p>
            <h2 className="text-brand-grad mt-4 text-balance font-head text-[clamp(22px,3vw,28px)] font-semibold tracking-[-0.02em]">
              Get real quotes for this job
            </h2>
            <p className="mx-auto mt-3 max-w-[48ch] text-[15px] leading-relaxed text-muted">
              Post it once. Vetted UAE suppliers compete anonymously — you compare and reveal only the one you choose.
            </p>
            <Link
              href="/me"
              className="btn-key press mt-7 inline-block rounded-full bg-teal px-8 py-3.5 text-[15px] font-bold text-[#04231F] shadow-[0_14px_38px_-14px_rgba(20,184,166,.7)] transition-all duration-200 hover:bg-[#1ED0BC] hover:shadow-[0_18px_44px_-14px_rgba(20,184,166,.9)]"
            >
              Get quotes
            </Link>
          </aside>
        </article>
      </main>
      <SiteFooter />
    </>
  );
}
