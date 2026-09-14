import posts from '@/content/blog.json';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { Link } from '@/i18n/routing';
import { notFound } from 'next/navigation';
import { buildMeta, textFromHtml } from '@/lib/seo';

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
    read: 'Read guide →', author: 'QuotesDone',
  },
  ar: {
    home: 'الرئيسية', blog: 'المدوّنة', crumb: 'مسار التنقل', ready: 'جاهزون متى شئت',
    ctaH: 'احصل على عروض أسعار حقيقية لهذا المشروع',
    ctaP: 'انشر طلبك مرة واحدة، ويتنافس عليه موردون موثّقون في الإمارات بسرّية تامة — تقارن العروض ولا تكشف إلا عن المورد الذي تختاره.',
    cta: 'احصل على عروض الأسعار', onlyEnglish: 'هذا المقال متاح حالياً باللغة الإنجليزية فقط.', indexH: 'مدوّنة QuotesDone',
    indexLead: 'أدلة عملية لشراء خدمات البناء والتشطيبات الداخلية والخدمات المنزلية في الإمارات — نطاقات أسعار حقيقية وقوائم تحقق والأسئلة الصحيحة التي تطرحها على الموردين قبل التوقيع.',
    read: 'اقرأ الدليل ←', author: 'QuotesDone',
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
          <Link href="/blog/" className="transition-colors hover:text-teal-light">{T.blog}</Link>
        </nav>

        <article className="max-w-[820px]">
          <header className="border-b border-[var(--line)] pb-8">
            {t.category && (
              <p className="font-mono text-[12px] font-semibold uppercase tracking-[0.2em] text-gold">{t.category}</p>
            )}
            <h1
              lang={t.lang} dir={rtl ? 'rtl' : 'ltr'}
              className="text-brand-grad mt-4 max-w-[20ch] text-balance font-head text-[clamp(28px,4vw,46px)] font-semibold leading-[1.08] tracking-[-0.035em]"
              {...(rtl ? { dangerouslySetInnerHTML: { __html: bidiText(t.title) } } : { children: t.title })}
            />
            {t.excerpt && (
              <p
                lang={t.lang} dir={rtl ? 'rtl' : 'ltr'}
                className="mt-5 max-w-[62ch] text-pretty text-[17px] leading-relaxed text-muted"
                {...(rtl ? { dangerouslySetInnerHTML: { __html: bidiText(t.excerpt) } } : { children: t.excerpt })}
              />
            )}
            <p className="mt-6 font-mono text-[12px] text-faint">
              {p.author}{p.author && date ? ' · ' : ''}{date}
            </p>
          </header>

          {locale === 'ar' && !rtl && (
            <p className="mt-8 rounded-xl border border-[var(--line2)] bg-teal-light/[0.05] px-4 py-3 text-[14px] text-muted">
              {T.onlyEnglish}
            </p>
          )}

          {/* lang/dir follow the text actually shown, so screen readers and translation tools
              handle an English fallback correctly on an Arabic page */}
          <div
            lang={t.lang}
            dir={rtl ? 'rtl' : 'ltr'}
            className="qd-prose mt-10"
            dangerouslySetInnerHTML={{ __html: rtl ? isolateLatin(t.body_html) : t.body_html }}
          />

          <aside className="glass mesh-glow relative mt-14 overflow-hidden rounded-[22px] p-8 text-center sm:p-10">
            <span className="corners absolute inset-3" aria-hidden />
            <p className="inline-flex items-center gap-2.5 font-mono text-[12px] font-semibold uppercase tracking-[0.2em] text-teal-light">
              <span className="node-dot" aria-hidden />
              {T.ready}
            </p>
            <h2 className="text-brand-grad mt-4 text-balance font-head text-[clamp(22px,3vw,28px)] font-semibold tracking-[-0.02em]">
              {T.ctaH}
            </h2>
            <p className="mx-auto mt-3 max-w-[48ch] text-[15px] leading-relaxed text-muted">
              {T.ctaP}
            </p>
            <Link
              href="/me"
              className="btn-key press mt-7 inline-block rounded-full bg-teal px-8 py-3.5 text-[15px] font-bold text-[#04231F] shadow-[0_14px_38px_-14px_rgba(20,184,166,.7)] transition-all duration-200 hover:bg-[#1ED0BC] hover:shadow-[0_18px_44px_-14px_rgba(20,184,166,.9)]"
            >
              {T.cta}
            </Link>
          </aside>
        </article>
      </main>
      <SiteFooter />
    </>
  );
}
