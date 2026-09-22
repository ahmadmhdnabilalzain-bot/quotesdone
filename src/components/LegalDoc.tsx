import legal from '@/content/legal.json';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { CompanyIdentity } from '@/components/CompanyIdentity';
import { PageHero, ContentsRail, takeByClass, anchorHeadings, textOf } from '@/components/DocFrame';
import { notFound } from 'next/navigation';
import { buildMeta, textFromHtml } from '@/lib/seo';
import { arDoc } from '@/lib/arabicDoc';
type Doc = { title: string; html: string };
const DOCS = legal as unknown as Record<string, { en: Doc; ar: Doc }>;
// An archived version of a document is stored under a slug that ends in the version — the page that
// renders it lives at /supplier-agreement/v10, not /supplier-agreement-v10.
// MEASURED 22 SEP 2026 (production walk): /supplier-agreement/v10, /v11 and both /ar copies declared
// canonical and hreflang URLs of /supplier-agreement-v10 and /supplier-agreement-v11 — both 404. The
// path is now rebuilt from the slug, the superseded copies are noindex (the live agreement is the one
// to index), and the version is in the title so the two are never mistaken for the same document.
const ARCHIVED = /^(.*)-(v\d+)$/;

export function metaFor(slug: string, locale: string) {
  const e = DOCS[slug];
  const d = e ? ((e as any)[locale] || e.en) : null;
  if (!d) return { title: 'QuotesDone' };
  const v = ARCHIVED.exec(slug);
  const path = v ? '/' + v[1] + '/' + v[2] : '/' + slug;
  const title = v
    ? d.title + (locale === 'ar' ? ` (${v[2]} — نسخة مؤرشفة)` : ` (${v[2]}, archived)`)
    : d.title;
  // The description is the legal text, not the document switcher: textFromHtml(d.html) opened with
  // the nav ("Terms of Service Privacy Policy Supplier Agreement…") on every legal page (WEB-03).
  const prose = (takeByClass(d.html, 'body')?.el ?? d.html).replace(/<h1\b[^>]*>[\s\S]*?<\/h1>/i, '');
  const body = textFromHtml(prose).replace(d.title, '').trim();
  const meta = buildMeta({ locale, path, title, description: body });
  return v ? { ...meta, robots: { index: false, follow: true } } : meta;
}

const L = {
  en: { kicker: 'Legal', contents: 'On this page', docs: 'Other documents' },
  ar: { kicker: 'الوثائق القانونية', contents: 'في هذه الصفحة', docs: 'وثائق أخرى' },
};

// Each legal document is one HTML file: a document switcher (.nav), a head (.dochead: title and
// version lines), the clauses (.body, h2 per clause) and the governing-law note (.note). The words
// stay in legal.json; this lays them out for long-form reading: the brand hero, a sticky contents
// rail built from the clause headings, and a measure held near 72 characters.
// `lead` renders inside the document column, above the legal text (the refund policy page puts the
// Reveal Guarantee ladder there).
export function LegalDoc({ slug, locale, lead }: { slug: string; locale: string; lead?: React.ReactNode }) {
  const e = DOCS[slug];
  if (!e) return notFound();
  const d = (e as any)[locale] || e.en;
  const t = locale === 'ar' ? L.ar : L.en;
  const html = arDoc(d.html, locale);
  const nav = takeByClass(html, 'nav')?.el ?? '';
  const head = takeByClass(html, 'dochead')?.el ?? '';
  const bodyEl = takeByClass(html, 'body')?.el ?? html;
  const note = takeByClass(html, 'note')?.el ?? '';
  const title = /<h1\b[^>]*>([\s\S]*?)<\/h1>/i.exec(head)?.[1] ?? d.title;
  const meta = [...head.matchAll(/<div class="meta">([\s\S]*?)<\/div>/g)].map((m) => textOf(m[1]));
  const others = [...nav.matchAll(/<a href="([^"]+)" class="(on)?">([\s\S]*?)<\/a>/g)].map((m) => ({ href: m[1], on: !!m[2], label: textOf(m[3]) }));
  const { html: body, list } = anchorHeadings(bodyEl, 'h2', 'clause');

  return (
    <>
      <SiteHeader />
      <main id="main" className="legalx !p-0" dir={locale === 'ar' ? 'rtl' : 'ltr'}>
        <PageHero
          kicker={t.kicker}
          title={<span dangerouslySetInnerHTML={{ __html: title }} />}
        >
          <div className="mt-7 flex flex-col gap-1.5 border-s border-line2 ps-4">
            {meta.map((m) => <span key={m} className="font-mono text-label text-faint">{m}</span>)}
          </div>
        </PageHero>

        <div className="container-x grid gap-10 py-12 md:py-16 lg:grid-cols-[250px_minmax(0,1fr)] lg:gap-16">
          <aside className="min-w-0">
            <ContentsRail
              title={t.contents}
              list={list}
              footer={others.length > 1 ? (
                <div className="mt-6 border-t border-line pt-5">
                  <div className="mb-2 px-2 font-mono text-label uppercase tracking-caps text-faint">{t.docs}</div>
                  <ul className="flex flex-col gap-0.5">
                    {others.map((o) => (
                      <li key={o.href}>
                        <a href={o.href} aria-current={o.on ? 'page' : undefined}
                          className={o.on
                            ? 'block rounded-chip bg-teal/10 px-2 py-1.5 text-small font-medium !text-teal-light'
                            : 'block rounded-chip px-2 py-1.5 text-small !text-muted transition-colors hover:bg-teal-light/[0.05] hover:!text-white'}>
                          {o.label}
                        </a>
                      </li>
                    ))}
                  </ul>
                </div>
              ) : null}
            />
          </aside>
          <article className="min-w-0 max-w-[760px]">
            {lead ? <div className="mb-10">{lead}</div> : null}
            <div
              className="text-copy [&_.card]:mb-6 [&_.muted]:!mb-6 [&_.muted]:!not-italic [&_.muted]:!text-lead [&_h2]:!mb-3 [&_h2]:!mt-14 [&_h2]:scroll-mt-28 [&_h2]:border-t [&_h2]:border-line [&_h2]:pt-8 [&_h2]:!text-h3 [&_li::marker]:text-teal-light [&_p]:!mb-4"
              dangerouslySetInnerHTML={{ __html: body }}
            />
            {note ? <div className="mt-14" dangerouslySetInnerHTML={{ __html: note }} /> : null}
            {slug === 'privacy' && <div className="mt-10"><CompanyIdentity locale={locale} /></div>}
          </article>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
