import type { Metadata } from 'next';
import { CANONICAL_ORIGIN } from './domains';
import { fitTitle } from './titleFit';

// One canonical site. quotesdone.ae serves the same pages to UAE visitors (src/lib/domains.ts), but
// every canonical, hreflang and OG URL points at .com, so search engines index one copy, not two.
export const SITE = CANONICAL_ORIGIN;
const BRAND = 'QuotesDone';

/** Trim a description to a length search engines actually render (~155 chars). */
function clampDesc(s: string, max = 158): string {
  const t = s.replace(/\s+/g, ' ').trim();
  if (t.length <= max) return t;
  const cut = t.slice(0, max);
  const i = cut.lastIndexOf(' ');
  return (i > 60 ? cut.slice(0, i) : cut).replace(/[,;:.\-–—]$/, '') + '…';
}

/** Strip tags/entities from a content blob to derive a description. */
export function textFromHtml(html: string): string {
  return html
    .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&[a-z]+;/gi, ' ')
    .replace(/\s+/g, ' ').trim();
}

/** The locale's brand social card, rendered by src/app/[locale]/opengraph-image.tsx. */
export function ogImageUrl(locale: string): string {
  return `${SITE}/${locale === 'ar' ? 'ar' : 'en'}/opengraph-image`;
}

/**
 * One place that builds every page's metadata: title, description, canonical,
 * hreflang alternates and social cards. `path` is the locale-less route
 * ('' for home, '/terms', '/blog/x'). Locale prefixing is applied here so the
 * canonical and the en/ar alternates always agree.
 */
export function buildMeta(opts: {
  locale: string;
  path: string;
  title: string;
  description?: string;
  type?: 'website' | 'article';
  publishedTime?: string | null;
  /** set false for pages that exist in one language only */
  bilingual?: boolean;
  /** point the canonical (and hreflang set) at another locale-less path, e.g. an emirate page's parent service */
  canonicalPath?: string;
  /** a segment-specific social card; defaults to the locale's brand card */
  image?: string;
}): Metadata {
  const { locale, path, title, description, type = 'website', publishedTime, bilingual = true } = opts;
  const norm = (p: string) => (p === '/' ? '' : p.replace(/\/$/, ''));
  const clean = norm(opts.canonicalPath ?? path);
  const en = `${SITE}${clean}`;
  const ar = `${SITE}/ar${clean}`;
  // An English-only page served under /ar has an English body, so its canonical is the English URL.
  // Measured: /ar/blog/<slug> declared itself canonical while /blog/<slug> never listed it (audit §mobile).
  const canonical = locale === 'ar' && bilingual ? ar : en;
  const desc = description ? clampDesc(description) : undefined;

  const languages: Record<string, string> = { 'en-AE': en, en };
  if (bilingual) { languages['ar-AE'] = ar; languages['ar'] = ar; }
  languages['x-default'] = en;

  // Measured before: twitter:card claimed summary_large_image with no image at all, so every share
  // was a bare text card. Both cards now name the same 1200x630 image.
  const image = opts.image ?? ogImageUrl(locale);
  const images = [{ url: image, width: 1200, height: 630, alt: title }];

  return {
    metadataBase: new URL(SITE),
    title: fitTitle(title),
    description: desc,
    alternates: { canonical, languages },
    openGraph: {
      type,
      siteName: BRAND,
      locale: locale === 'ar' ? 'ar_AE' : 'en_AE',
      url: canonical,
      title,
      description: desc,
      images,
      ...(publishedTime ? { publishedTime } : {}),
    },
    twitter: { card: 'summary_large_image', title, description: desc, images: [image] },
    robots: { index: true, follow: true },
  };
}

/**
 * Metadata for the signed-in app shells (/me, /portal). They were exporting a static English title
 * only and were indexable. next.config.mjs already sends X-Robots-Tag: noindex for these paths; this
 * gives the page the same answer in <meta> plus a title in the visitor's language. (/supplier is the
 * public supplier sales page now, with its own indexable metadata in its page file.)
 * Usage in a page file:
 *   export async function generateMetadata(p: { params: Promise<{ locale: string }> }) {
 *     return appShellMeta((await p.params).locale, 'portal');
 *   }
 */
const SHELL: Record<'me' | 'portal', { en: [string, string]; ar: [string, string] }> = {
  me: {
    en: ['My requests — QuotesDone', 'Post a job, compare anonymous quotes and reveal the supplier you choose.'],
    ar: ['طلباتي — QuotesDone', 'انشر طلبك وقارن عروض الأسعار المجهولة واكشف هوية المورد الذي تختاره.'],
  },
  portal: {
    en: ['Supplier portal — QuotesDone', 'Quote on jobs from anywhere in the UAE, matched to your licence and trade.'],
    // Formal plural, like every other supplier-facing line (audit 22 Sep 2026, SP-I-05): the portal
    // addresses a company, and the singular «رخصتك» read as though it were writing to a friend.
    ar: ['بوابة المورّدين — QuotesDone', 'قدّموا عروض أسعاركم على طلبات من أي مكان في الإمارات تطابق رخصتكم ونشاطكم.'],
  },
};
export function appShellMeta(locale: string, shell: keyof typeof SHELL): Metadata {
  const [title, description] = SHELL[shell][locale === 'ar' ? 'ar' : 'en'];
  return {
    ...buildMeta({ locale, path: '/' + shell, title, description }),
    robots: { index: false, follow: false },
  };
}

// ── Emirate landing pages ───────────────────────────────────────────────────────────────────────
// /services/<slug>-in-<emirate> is /services/<slug> with {{LOC}} substituted (measured: 87,574 vs
// 87,472 bytes for solar vs solar-in-dubai). Until an emirate page has content of its own, it names
// its parent service as canonical and is left out of the sitemap, so 336 near-duplicates stop
// competing with the 48 pages they copy.
export const EMIRATES = ['abu-dhabi', 'ajman', 'dubai', 'fujairah', 'ras-al-khaimah', 'sharjah', 'umm-al-quwain'] as const;
const EMIRATE_RE = new RegExp(`^(.+)-in-(${EMIRATES.join('|')})$`);
/** 'solar-in-dubai' -> { service: 'solar', emirate: 'dubai' }; 'solar' -> { service: 'solar' } */
export function splitServiceSlug(slug: string): { service: string; emirate?: string } {
  const m = slug.match(EMIRATE_RE);
  return m ? { service: m[1], emirate: m[2] } : { service: slug };
}

// ── JSON-LD ─────────────────────────────────────────────────────────────────────────────────────
// Measured before: `grep -rn 'ld+json|schema.org' src` = 0, and none on the live /, /faq or a
// service page. Every builder below serialises content that already exists in the JSON files.
/** Props for <script type="application/ld+json" dangerouslySetInnerHTML={ldHtml(x)} />. `<` is
 *  escaped so a string in the content can never close the script element. */
export function ldHtml(data: unknown): { __html: string } {
  return { __html: JSON.stringify(data).replace(/</g, '\\u003c') };
}

const ORG_ID = `${SITE}/#organization`;
const SOCIALS = [
  'https://www.instagram.com/official.quotesdone/',
  'https://www.linkedin.com/company/quotesdone',
  'https://x.com/QuotesdoneUAE',
  'https://www.facebook.com/quotesdone.UAE',
];

/** Organization + WebSite, on every page from the locale layout. No SearchAction: the site has no
 *  search results URL (the FAQ search box filters in-page), and a SearchAction must name one. */
export function siteLd(locale: string) {
  const home = locale === 'ar' ? `${SITE}/ar` : SITE;
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'Organization',
        '@id': ORG_ID,
        name: BRAND,
        legalName: 'QuotesDone Technologies',
        url: SITE,
        logo: `${SITE}/brand/pwa-512.png`,
        email: 'management@quotesdone.com',
        areaServed: { '@type': 'Country', name: 'United Arab Emirates' },
        address: { '@type': 'PostalAddress', addressLocality: 'Dubai', addressCountry: 'AE' },
        // No licence number here: founder rule, never in marketing or profile copy (company_facts.json marketing_surfaces).
        sameAs: SOCIALS,
      },
      {
        '@type': 'WebSite',
        '@id': `${SITE}/#website`,
        name: BRAND,
        url: home,
        inLanguage: locale === 'ar' ? 'ar-AE' : 'en-AE',
        publisher: { '@id': ORG_ID },
      },
    ],
  };
}

export function breadcrumbLd(items: { name: string; url: string }[]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: items.map((it, i) => ({ '@type': 'ListItem', position: i + 1, name: it.name, item: it.url })),
  };
}

export function serviceLd(o: { name: string; description: string; url: string; areaServed: string; locale: string }) {
  return {
    '@context': 'https://schema.org',
    '@type': 'Service',
    name: o.name,
    description: clampDesc(o.description, 300),
    url: o.url,
    serviceType: o.name,
    inLanguage: o.locale === 'ar' ? 'ar-AE' : 'en-AE',
    provider: { '@id': ORG_ID },
    areaServed: o.areaServed,
  };
}

/** FAQ html is `<details class="qa"><summary>Q</summary><div class="a">A</div></details>` blocks. */
export function faqPairs(html: string): { q: string; a: string }[] {
  const out: { q: string; a: string }[] = [];
  const re = /<details[^>]*>\s*<summary[^>]*>([\s\S]*?)<\/summary>([\s\S]*?)<\/details>/gi;
  for (let m; (m = re.exec(html)); ) {
    const q = textFromHtml(m[1]); const a = textFromHtml(m[2]);
    if (q && a) out.push({ q, a });
  }
  return out;
}

/** HowTo for /how-it-works, built from the same steps the page renders, so the two cannot disagree. */
export function howToLd(o: { name: string; description: string; url: string; steps: { title: string; body: string }[]; locale: string }) {
  return {
    '@context': 'https://schema.org',
    '@type': 'HowTo',
    name: o.name,
    description: clampDesc(o.description, 300),
    url: o.url,
    inLanguage: o.locale === 'ar' ? 'ar-AE' : 'en-AE',
    step: o.steps.map((s, i) => ({ '@type': 'HowToStep', position: i + 1, name: s.title, text: s.body })),
  };
}

export function faqLd(pairs: { q: string; a: string }[], locale: string) {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    inLanguage: locale === 'ar' ? 'ar-AE' : 'en-AE',
    mainEntity: pairs.map((p) => ({ '@type': 'Question', name: p.q, acceptedAnswer: { '@type': 'Answer', text: p.a } })),
  };
}

// /ar pages carried the English headline, English URL and inLanguage 'en' (website audit W22).
// The locale is accepted either as p.locale or as the second argument; both callers exist.
export function blogPostingLd(p: { slug: string; title: string; description: string; published: string | null; author: string | null; category: string | null; locale?: string }, locale: string = 'en') {
  const ar = (p.locale ?? locale) === 'ar';
  const url = `${SITE}${ar ? '/ar' : ''}/blog/${p.slug}`;
  return {
    '@context': 'https://schema.org',
    '@type': 'BlogPosting',
    headline: p.title,
    description: clampDesc(p.description, 300),
    url,
    mainEntityOfPage: url,
    image: `${url}/opengraph-image`,
    inLanguage: ar ? 'ar-AE' : 'en',
    ...(p.published ? { datePublished: p.published, dateModified: p.published } : {}),
    ...(p.category ? { articleSection: p.category } : {}),
    author: p.author && p.author !== BRAND ? { '@type': 'Person', name: p.author } : { '@id': ORG_ID },
    publisher: { '@id': ORG_ID },
  };
}
