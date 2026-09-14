import posts from '@/content/blog.json';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { Link } from '@/i18n/routing';
import { notFound } from 'next/navigation';
import { buildMeta, textFromHtml } from '@/lib/seo';
import { anchorHeadings, ContentsRail, CtaPanel } from '@/components/DocFrame';
import { Button } from '@/components/ui/button';

type Body = { title: string; excerpt: string | null; meta_desc: string | null; category: string | null; body_html: string };
export type Post = Body & {
  slug: string; author: string | null; published_at: string | null; sort: number | null;
  ar?: Body;
};
const P = posts as unknown as Record<string, Post>;

// Blog UI strings live here, beside the only components that use them, not in messages/*.json.
export const BLOG_T = {
  en: {
    home: 'Home', blog: 'Blog', crumb: 'Breadcrumb', ready: 'Ready when you are',
    ctaH: 'Get real quotes for this job',
    ctaP: 'Post it once. Vetted UAE suppliers compete anonymously — you compare and reveal only the one you choose.',
    cta: 'Get quotes', onlyEnglish: '', indexH: 'QuotesDone blog',
    indexLead: 'Practical guides for buying building, fit-out and home services in the UAE — real price ranges, checklists and the right questions to ask suppliers before you sign.',
    read: 'Read guide →', author: 'QuotesDone', contents: 'In this guide',
  },
  ar: {
    home: 'الرئيسية', blog: 'المدوّنة', crumb: 'مسار التنقل', ready: 'جاهزون متى شئت',
    ctaH: 'احصل على عروض أسعار حقيقية لهذا المشروع',
    ctaP: 'انشر طلبك مرة واحدة، ويتنافس عليه موردون موثّقون في الإمارات بسرّية تامة — تقارن العروض ولا تكشف إلا عن المورد الذي تختاره.',
    cta: 'احصل على عروض الأسعار', onlyEnglish: 'هذا المقال متاح حالياً باللغة الإنجليزية فقط.', indexH: 'مدوّنة QuotesDone',
    indexLead: 'أدلة عملية لشراء خدمات البناء والتشطيبات الداخلية والخدمات المنزلية في الإمارات — نطاقات أسعار حقيقية وقوائم تحقق والأسئلة الصحيحة التي تطرحها على الموردين قبل التوقيع.',
    read: 'اقرأ الدليل ←', author: 'QuotesDone', contents: 'في هذا الدليل',
  },
} as const;
export const blogT = (locale: string) => (locale === 'ar' ? BLOG_T.ar : BLOG_T.en);

/** The post's text in the page locale, and whether it really is that language. */
export function localized(p: Post, locale: string): Body & { lang: 'en' | 'ar' } {
  if (locale === 'ar' && p.ar) return { ...p.ar, lang: 'ar' };
  return { title: p.title, excerpt: p.excerpt, meta_desc: p.meta_desc, category: p.category, body_html: p.body_html, lang: 'en' };
}

// Bidi isolation for Arabic text: a Latin run (AED figures, units, phone numbers, emails, URLs,
// acronyms) inside RTL text is wrapped in <bdi> so "+971 50 931 9355" keeps its digit groups in
// order. Runs start at a Latin letter, digit or "+", may contain spaces and the punctuation such
// runs use, and end at a letter, digit, % or superscript. Only text between tags is touched.
const LATIN_RUN = /[A-Za-z0-9+][A-Za-z0-9+@.,:;/\\\-–—%²³×&#_' ]*[A-Za-z0-9%²³]/g;
export function isolateLatin(html: string): string {
  return html.replace(/(^|>)([^<]+)/g, (_m, lead: string, text: string) =>
    lead + text.replace(LATIN_RUN, (run) => `<bdi>${run}</bdi>`));
}
const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
export const bidiText = (s: string) => isolateLatin(esc(s));

export function blogSlugs(): string[] { return Object.keys(P); }

export function blogMeta(slug: string, locale = 'en') {
  const p = P[slug];
  if (!p) return { title: 'QuotesDone' };
  const t = localized(p, locale);
  return buildMeta({
    locale,
    path: '/blog/' + slug,
    title: `${t.title} — QuotesDone`,
    description: t.meta_desc || t.excerpt || textFromHtml(t.body_html),
    type: 'article',
    publishedTime: p.published_at,
    // advertise the Arabic alternate only when the post has one
    bilingual: Boolean(p.ar),
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
  const p = P[slug];
  if (!p) return notFound();
  const T = blogT(locale);
  const t = localized(p, locale);
  const rtl = t.lang === 'ar';
  const date = fmt(p.published_at, locale);
  const { html: body, list } = anchorHeadings(rtl ? isolateLatin(t.body_html) : t.body_html, 'h2', 'part');
  return (
    <>
      <SiteHeader />
      <main id="main" dir={locale === 'ar' ? 'rtl' : 'ltr'}>
        <section className="qd-keylight relative overflow-hidden border-b border-line">
          <span className="grid-tech" aria-hidden />
          <div className="container-x relative pb-14 pt-14 md:pb-20 md:pt-20">
            <nav aria-label={T.crumb} className="qd-kicker">
              <Link href="/" className="transition-colors hover:text-white">{T.home}</Link>
              <span aria-hidden className="mx-2 text-faint">/</span>
              <Link href="/blog/" className="transition-colors hover:text-white">{T.blog}</Link>
            </nav>
            {t.category && (
              <p className="mt-8 font-mono text-label uppercase tracking-caps text-teal-light">{t.category}</p>
            )}
            <h1
              lang={t.lang} dir={rtl ? 'rtl' : 'ltr'}
              className="mt-4 max-w-[22ch] text-balance font-head text-display-sm text-white"
              {...(rtl ? { dangerouslySetInnerHTML: { __html: bidiText(t.title) } } : { children: t.title })}
            />
            {t.excerpt && (
              <p
                lang={t.lang} dir={rtl ? 'rtl' : 'ltr'}
                className="mt-6 max-w-[62ch] text-pretty text-lead text-muted"
                {...(rtl ? { dangerouslySetInnerHTML: { __html: bidiText(t.excerpt) } } : { children: t.excerpt })}
              />
            )}
            <p className="mt-8 flex flex-wrap items-center gap-3 font-mono text-label text-faint">
              {p.author ? <span>{p.author}</span> : null}
              {p.author && date ? <span aria-hidden className="h-3 w-px bg-[var(--line2)]" /> : null}
              {date ? <span>{date}</span> : null}
            </p>
          </div>
        </section>

        <div className="container-x grid gap-10 py-12 md:py-16 lg:grid-cols-[minmax(0,1fr)_240px] lg:gap-16">
          <article className="min-w-0 max-w-[720px]">
            {locale === 'ar' && !rtl && (
              <p className="mb-10 rounded-panel border border-line2 bg-teal-light/[0.05] px-4 py-3 text-small text-muted">
                {T.onlyEnglish}
              </p>
            )}
            {/* lang/dir follow the text actually shown, so screen readers and translation tools
                handle an English fallback correctly on an Arabic page */}
            <div
              lang={t.lang}
              dir={rtl ? 'rtl' : 'ltr'}
              className="qd-prose [&_h2]:scroll-mt-28"
              dangerouslySetInnerHTML={{ __html: body }}
            />
          </article>
          {list.length > 2 ? <aside className="-order-1 min-w-0 lg:order-none"><ContentsRail title={T.contents} list={list} /></aside> : null}
        </div>

        <CtaPanel kicker={T.ready} title={T.ctaH} body={T.ctaP}>
          <Button asChild size="xl" className="qd-magnet"><Link href="/me">{T.cta}</Link></Button>
        </CtaPanel>
      </main>
      <SiteFooter />
    </>
  );
}
