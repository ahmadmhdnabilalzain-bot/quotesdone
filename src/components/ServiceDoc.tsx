import services from '@/content/services.json';
import { SERVICES_CSS } from '@/content/servicesCss';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { notFound } from 'next/navigation';
import { buildMeta, textFromHtml } from '@/lib/seo';

type Loc = { en_the: string; en: string; ar_the: string; ar: string };
const EM: Record<string, Loc> = {
  'abu-dhabi': { en_the: 'Abu Dhabi', en: 'Abu Dhabi', ar_the: 'أبوظبي', ar: 'أبوظبي' },
  'ajman': { en_the: 'Ajman', en: 'Ajman', ar_the: 'عجمان', ar: 'عجمان' },
  'dubai': { en_the: 'Dubai', en: 'Dubai', ar_the: 'دبي', ar: 'دبي' },
  'fujairah': { en_the: 'Fujairah', en: 'Fujairah', ar_the: 'الفجيرة', ar: 'الفجيرة' },
  'ras-al-khaimah': { en_the: 'Ras Al Khaimah', en: 'Ras Al Khaimah', ar_the: 'رأس الخيمة', ar: 'رأس الخيمة' },
  'sharjah': { en_the: 'Sharjah', en: 'Sharjah', ar_the: 'الشارقة', ar: 'الشارقة' },
  'umm-al-quwain': { en_the: 'Umm Al Quwain', en: 'Umm Al Quwain', ar_the: 'أم القيوين', ar: 'أم القيوين' },
};
const BASE: Loc = { en_the: 'the UAE', en: 'UAE', ar_the: 'الإمارات', ar: 'الإمارات' };
type Doc = { title: string; html: string };
const S = services as unknown as Record<string, { en: Doc; ar: Doc }>;

function parse(slug: string): { service: string; loc: Loc } {
  const m = slug.match(/^(.+)-in-(abu-dhabi|ajman|dubai|fujairah|ras-al-khaimah|sharjah|umm-al-quwain)$/);
  if (m && S[m[1]]) return { service: m[1], loc: EM[m[2]] };
  return { service: slug, loc: BASE };
}
function sub(txt: string, loc: Loc, locale: string): string {
  const the = locale === 'ar' ? loc.ar_the : loc.en_the;
  const bare = locale === 'ar' ? loc.ar : loc.en;
  return txt.replace(/\{\{LOC_THE\}\}/g, the).replace(/\{\{LOC\}\}/g, bare);
}
// For Arabic, keep internal cross-links inside the /ar locale.
// Skip already-/ar links, Next asset paths, external/anchor links, and /blog (AR blog posts not migrated).
function arLinks(html: string): string {
  return html.replace(/href="\/(?!ar[\/"]|_next|blog)/g, 'href="/ar/');
}
export function svcParams(): string[] {
  const out: string[] = [];
  for (const s of Object.keys(S)) { out.push(s); for (const e of Object.keys(EM)) out.push(s + '-in-' + e); }
  return out;
}
export function svcMeta(slug: string, locale: string) {
  const { service, loc } = parse(slug); const d = S[service];
  if (!d) return { title: 'QuotesDone' };
  const c = (d as any)[locale] || d.en;
  const title = sub(c.title, loc, locale);
  const body = textFromHtml(sub(c.html, loc, locale)).replace(title, '').trim();
  return buildMeta({ locale, path: '/services/' + slug, title, description: body });
}
export function ServiceDoc({ slug, locale }: { slug: string; locale: string }) {
  const { service, loc } = parse(slug); const d = S[service];
  if (!d) return notFound();
  const c = (d as any)[locale] || d.en;
  let html = sub(c.html, loc, locale);
  if (locale === 'ar') html = arLinks(html);
  return (
    <>
      <SiteHeader />
      <style dangerouslySetInnerHTML={{ __html: SERVICES_CSS }} />
      <main id="main" className="mk" dir={locale === 'ar' ? 'rtl' : 'ltr'} dangerouslySetInnerHTML={{ __html: html }} />
      <SiteFooter />
    </>
  );
}
