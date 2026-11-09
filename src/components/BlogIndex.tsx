import posts from '@/content/blog.json';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { Link } from '@/i18n/routing';
import { blogT, localized, bidiText, type Post } from '@/components/BlogPost';
import { PageHero } from '@/components/DocFrame';

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
      <main id="main" dir={locale === 'ar' ? 'rtl' : 'ltr'}>
        <PageHero
          kicker={<nav aria-label={T.crumb} className="inline-flex items-center gap-2">
            <Link href="/" className="transition-colors hover:text-white">{T.home}</Link>
            <span aria-hidden className="text-faint">/</span>
            <span>{T.blog}</span>
          </nav>}
          title={T.indexH}
          lead={T.indexLead}
        />
        <ul className="container-x grid gap-4 py-beat-s sm:grid-cols-2 lg:grid-cols-3">
          {list.map((p, i) => {
            const t = localized(p, locale);
            const rtl = t.lang === 'ar';
            const lead = i === 0; // the first guide leads, two columns wide
            return (
              <li key={p.slug} className={lead ? 'sm:col-span-2' : undefined}>
                <Link
                  href={`/blog/${p.slug}/`}
                  className={`qd-env qd-env-hover qd-lit group flex h-full flex-col p-6 pt-8 md:p-7 md:pt-9 ${lead ? 'qd-env-lg md:min-h-[300px]' : ''}`}
                >
                  <span className="flex items-center justify-between gap-3">
                    {t.category ? <span className="font-mono text-label uppercase tracking-caps text-teal-light">{t.category}</span> : <span />}
                    <span className="tabular font-mono text-label text-faint">{String(i + 1).padStart(2, '0')}</span>
                  </span>
                  {/* oxlint-disable-next-line jsx-a11y/heading-has-content -- false positive: content arrives through the spread (children or dangerouslySetInnerHTML) */}
                  <h2
                    lang={t.lang} dir={rtl ? 'rtl' : 'ltr'}
                    className={`mt-5 text-balance font-head font-semibold tracking-snug text-white ${lead ? 'text-h2' : 'text-[19px] leading-snug'}`}
                    {...(rtl ? { dangerouslySetInnerHTML: { __html: bidiText(t.title) } } : { children: t.title })}
                  />
                  {t.excerpt && (
                    <p
                      lang={t.lang} dir={rtl ? 'rtl' : 'ltr'}
                      className={`mt-3 flex-1 text-muted ${lead ? 'max-w-[60ch] text-lead' : 'text-copy'}`}
                      {...(rtl ? { dangerouslySetInnerHTML: { __html: bidiText(t.excerpt) } } : { children: t.excerpt })}
                    />
                  )}
                  <span className="mt-6 border-t border-line pt-4 text-small font-semibold text-teal-light transition-colors group-hover:text-white">{T.read}</span>
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
