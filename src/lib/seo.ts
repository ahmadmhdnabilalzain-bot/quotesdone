import type { Metadata } from 'next';

export const SITE = 'https://quotesdone.com';
export const BRAND = 'QuotesDone';

/** Trim a description to a length search engines actually render (~155 chars). */
export function clampDesc(s: string, max = 158): string {
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
}): Metadata {
  const { locale, path, title, description, type = 'website', publishedTime, bilingual = true } = opts;
  const clean = path === '/' ? '' : path.replace(/\/$/, '');
  const en = `${SITE}${clean}`;
  const ar = `${SITE}/ar${clean}`;
  const canonical = locale === 'ar' ? ar : en;
  const desc = description ? clampDesc(description) : undefined;

  const languages: Record<string, string> = { 'en-AE': en, en };
  if (bilingual) { languages['ar-AE'] = ar; languages['ar'] = ar; }
  languages['x-default'] = en;

  return {
    metadataBase: new URL(SITE),
    title,
    description: desc,
    alternates: { canonical, languages },
    openGraph: {
      type,
      siteName: BRAND,
      locale: locale === 'ar' ? 'ar_AE' : 'en_AE',
      url: canonical,
      title,
      description: desc,
      ...(publishedTime ? { publishedTime } : {}),
    },
    twitter: { card: 'summary_large_image', title, description: desc },
    robots: { index: true, follow: true },
  };
}
