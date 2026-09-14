import posts from '@/content/blog.json';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { Link } from '@/i18n/routing';
import { blogT, localized, bidiText, type Post } from '@/components/BlogPost';

const P = posts as unknown as Record<string, Post>;

// The /blog index is built from blog.json itself, so a post in the data is a post on the index.
// A duplicate is a build failure, not a silently merged card: JSON.parse keeps only the last of
// two identical keys, so the slug field inside each post must equal its key.
// scripts/checks/blog_index_matches_data.mjs scans the raw file for the duplicate keys JSON.parse
// would hide, and reports posts that share a title (two different articles, a content decision).
function ordered(): Post[] {
  const seen = new Set<string>();
  for (const [key, p] of Object.entries(P)) {
    if (p.slug !== key) throw new Error(`blog.json: key "${key}" holds slug "${p.slug}"`);
    if (seen.has(p.slug)) throw new Error(`blog.json: duplicate slug "${p.slug}"`);
    seen.add(p.slug);
  }
  return Object.values(P).sort((a, b) => (a.sort ?? 1e9) - (b.sort ?? 1e9) || a.slug.localeCompare(b.slug));
}

export function BlogIndex({ locale }: { locale: string }) {
  const T = blogT(locale);
  const list = ordered();
  return (
    <>
      <SiteHeader />
      <main id="main" className="container-x py-beat-s md:py-beat" dir={locale === 'ar' ? 'rtl' : 'ltr'}>
        <nav
          aria-label={T.crumb}
          className="mb-8 inline-flex items-center gap-2.5 rounded-full border border-[var(--line2)] bg-teal-light/[0.05] px-3.5 py-1.5 font-mono text-[12px] uppercase tracking-[0.16em] text-faint backdrop-blur"
        >
          <span className="node-dot" aria-hidden />
          <Link href="/" className="transition-colors hover:text-teal-light">{T.home}</Link>
          <span className="text-teal/50">/</span>
          <span>{T.blog}</span>
        </nav>
        <header className="max-w-[820px] border-b border-[var(--line)] pb-8">
          <h1 className="text-brand-grad text-balance font-head text-[clamp(28px,4vw,46px)] font-semibold leading-[1.08] tracking-[-0.035em]">
            {T.indexH}
          </h1>
          <p className="mt-5 max-w-[62ch] text-pretty text-[17px] leading-relaxed text-muted">{T.indexLead}</p>
        </header>
        <ul className="mt-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {list.map((p) => {
            const t = localized(p, locale);
            const rtl = t.lang === 'ar';
            return (
              <li key={p.slug}>
                <Link
                  href={`/blog/${p.slug}/`}
                  className="glass group flex h-full flex-col rounded-[18px] p-6 transition-colors hover:border-teal/40"
                >
                  {t.category && (
                    <span className="font-mono text-[12px] font-semibold uppercase tracking-[0.2em] text-gold">{t.category}</span>
                  )}
                  <h2
                    lang={t.lang} dir={rtl ? 'rtl' : 'ltr'}
                    className="mt-3 text-balance font-head text-[19px] font-semibold leading-snug"
                    {...(rtl ? { dangerouslySetInnerHTML: { __html: bidiText(t.title) } } : { children: t.title })}
                  />
                  {t.excerpt && (
                    <p
                      lang={t.lang} dir={rtl ? 'rtl' : 'ltr'}
                      className="mt-3 flex-1 text-[15px] leading-relaxed text-muted"
                      {...(rtl ? { dangerouslySetInnerHTML: { __html: bidiText(t.excerpt) } } : { children: t.excerpt })}
                    />
                  )}
                  <span className="mt-5 text-[14px] font-semibold text-teal-light">{T.read}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      </main>
      <SiteFooter />
    </>
  );
}
