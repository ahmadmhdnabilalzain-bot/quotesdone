import mk from '@/content/marketing.json';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { CompanyIdentity } from '@/components/CompanyIdentity';
import { AllTrades } from '@/components/AllTrades';
import { PageHero, splitHero, takeByClass, textOf } from '@/components/DocFrame';
import { ProductFrame, Seal } from '@/components/ui/sealed';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { notFound } from 'next/navigation';
import { buildMeta, textFromHtml } from '@/lib/seo';
import { arDoc } from '@/lib/arabicDoc';
type Doc = { title: string; html: string };
const M = mk as unknown as Record<string, { en: Doc; ar: Doc }>;
export function mkMeta(slug: string, locale: string) {
  const e = M[slug];
  const d = e ? ((e as any)[locale] || e.en) : null;
  if (!d) return { title: 'QuotesDone' };
  // The breadcrumb is navigation, not prose: /contact's description read "Home · Contact Contact
  // QuotesDone…" (WEB-03). Drop the crumb, then take the opening copy.
  const crumb = takeByClass(d.html, 'crumb');
  const prose = crumb ? crumb.before + crumb.after : d.html;
  const body = textFromHtml(prose).replace(d.title, '').trim();
  return buildMeta({ locale, path: '/' + slug, title: d.title, description: body });
}

const L = {
  en: {
    sample: 'Sample data', verifyTitle: 'verification / new supplier', verifyStatus: '5 of 6',
    six: ['Business name', 'Mobile number', 'Email address', 'Trade licence', 'Company profile', 'Signed terms'],
    checked: 'Checked', pending: 'Pending', supplier: 'Supplier',
    services: 'Guides for common jobs', trades: 'guides',
  },
  ar: {
    sample: 'بيانات نموذجية', verifyTitle: 'التحقق / مورد جديد', verifyStatus: '5 من 6',
    six: ['الاسم التجاري', 'رقم الهاتف المحمول', 'البريد الإلكتروني', 'الرخصة التجارية', 'ملف الشركة', 'الشروط الموقّعة'],
    checked: 'تم التحقق', pending: 'قيد المراجعة', supplier: 'المورد',
    services: 'أدلة لأعمال شائعة', trades: 'دليلاً',
  },
};

/** What "verified" means, as the checklist a supplier moves through (illustrative, labelled sample). */
function VerifyFrame({ t }: { t: typeof L.en }) {
  return (
    <ProductFrame title={t.verifyTitle} sampleLabel={t.sample} status={t.verifyStatus} className="shadow-e3">
      <div className="border-b border-line px-5 py-4 text-copy text-muted">
        {t.supplier} <Seal>Al Noor Flooring LLC</Seal>
      </div>
      {/* no scroll stagger: it held the last rows back while the hero was fully in view */}
      <ul>
        {t.six.map((s, i) => (
          <li key={s} className="qd-row" style={{ gridTemplateColumns: '28px minmax(0,1fr) auto' }}>
            <span className="tabular font-mono text-label text-faint">{String(i + 1).padStart(2, '0')}</span>
            <span className="truncate text-body text-paper">{s}</span>
            {i < 5 ? <Badge variant="ok" dot>{t.checked}</Badge> : <Badge variant="info" dot>{t.pending}</Badge>}
          </li>
        ))}
      </ul>
    </ProductFrame>
  );
}

/** /services: the trade chips become a ledger index (ruled rows, mono serials; ui/sealed shape system). */
function ServiceIndex({ html }: { html: string }) {
  const links = [...html.matchAll(/<a href="([^"]+)">([\s\S]*?)<\/a>/g)].map((m) => ({ href: m[1], label: textOf(m[2]) }));
  return (
    <ul className="qd-ledger qd-ticks grid lg:grid-cols-2 lg:gap-x-12">
      {links.map((l, i) => (
        <li key={l.href}>
          <a href={l.href} className="group grid grid-cols-[2.75rem_minmax(0,1fr)_auto] items-center gap-x-4 py-4 !text-paper focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-teal md:grid-cols-[4.5rem_minmax(0,1fr)_auto] md:gap-x-6">
            <span className="qd-ledger-no" aria-hidden>{String(i + 1).padStart(2, '0')}</span>
            <span className="min-w-0 flex-1 font-head text-[16px] font-semibold leading-snug tracking-snug text-white">{l.label}</span>
            <span aria-hidden className="text-faint transition-transform duration-base group-hover:translate-x-1 group-hover:text-teal-light rtl:rotate-180 rtl:group-hover:-translate-x-1">→</span>
          </a>
        </li>
      ))}
    </ul>
  );
}

export function MarketingDoc({ slug, locale }: { slug: string; locale: string }) {
  const e = M[slug];
  if (!e) return notFound();
  const d = (e as any)[locale] || e.en;
  const t = locale === 'ar' ? L.ar : L.en;
  const hero = splitHero(arDoc(d.html, locale));
  let rest = hero.rest;
  let index: string | null = null;
  if (slug === 'services') {
    const chips = takeByClass(rest, 'chips');
    if (chips) { index = chips.el; rest = (chips.before + chips.after).replace(/<h2>[^<]*<\/h2>/, '').replace(/<div class="wrap"><section>\s*<\/section><\/div>/, ''); }
  }
  const aside = slug === 'how-we-verify' ? <VerifyFrame t={t} /> : undefined;
  return (
    <>
      <SiteHeader />
      <main id="main" dir={locale === 'ar' ? 'rtl' : 'ltr'}>
        <PageHero
          center={slug === 'about'}
          kicker={hero.kicker ? <span className="[&_a]:text-inherit [&_a:hover]:text-white" dangerouslySetInnerHTML={{ __html: hero.kicker }} /> : undefined}
          title={<span className="[&_.g]:text-teal-light" dangerouslySetInnerHTML={{ __html: hero.title ?? d.title }} />}
          lead={hero.lead ? <span dangerouslySetInnerHTML={{ __html: hero.lead }} /> : undefined}
          actions={hero.actions.length ? hero.actions.map((a) => (
            <Button key={a.href} asChild size="lg" variant={a.ghost ? 'secondary' : 'default'} className="qd-magnet"><a href={a.href}>{a.label}</a></Button>
          )) : undefined}
          aside={aside}
        />
        {/* The whole offer first; the service pages below are guides for common jobs, not the scope. */}
        {slug === 'services' ? <AllTrades /> : null}
        {index ? (
          <section className="container-x py-beat-s">
            <div className="mb-8 flex items-baseline justify-between gap-4 border-b border-line pb-5">
              <span className="font-mono text-label uppercase tracking-caps text-faint">{t.services}</span>
              <span className="tabular font-mono text-label text-faint">{(index.match(/<a /g) || []).length} {t.trades}</span>
            </div>
            <ServiceIndex html={index} />
          </section>
        ) : null}
        {/* styles: globals.css §9 (.mk base + .mk-<slug> where a page has its own block) */}
        {textOf(rest) ? <div className={`mk mk-${slug} pb-beat-s`} dangerouslySetInnerHTML={{ __html: rest }} /> : null}
      </main>
      {slug === 'about' && <div className="container-x pb-beat-s"><CompanyIdentity locale={locale} /></div>}
      <SiteFooter />
    </>
  );
}
