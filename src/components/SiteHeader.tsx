import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { ScrollProgress } from '@/components/motion/ScrollProgress';
import { BrandMark } from '@/components/BrandMark';
import { PointerLight } from '@/components/ui/pointer-light';
import { AudienceNav, type NavService } from './AudienceNav';

/**
 * The Sealed header: a translucent sealed bar (navy glass over the grain, a teal specular hairline
 * along its foot, the scroll progress on that hairline). Strings resolve here on the server; the
 * audience-specific slot and the Services mega-menu live in AudienceNav (client).
 * The mega-menu reads the SAME taxonomy as the homepage Categories grid (messages cats.items), so the
 * header and the grid can never list different services.
 */
export function SiteHeader() {
  const t = useTranslations('nav');
  const c = useTranslations('cats');
  const labels = {
    how: t('how'), why: t('why'), blog: t('blog'), suppliers: t('suppliers'),
    services: t('services'), categories: t('categories'),
    login: t('login'), getQuotes: t('getQuotes'), menu: t('menu'), closeMenu: t('closeMenu'),
    myPortal: t('myPortal'), supplierPortal: t('supplierPortal'),
    servicesLead: c('sub'),
    about: t('about'), allTrades: c('allTrades'), guides: c('guides'),
  };
  const services = (c.raw('items') as { title: string; slug: string; tags: string | string[] }[]).map<NavService>((s) => ({
    slug: s.slug,
    title: s.title,
    tag: (Array.isArray(s.tags) ? s.tags : String(s.tags ?? '').split('·')).map((x) => x.trim()).filter(Boolean).slice(0, 2).join(' · '),
  }));
  return (
    <header className="sticky top-0 z-40">
      <PointerLight />
      <div className="relative border-b border-line bg-navy-deep/70 backdrop-blur-xl backdrop-saturate-150 supports-backdrop-filter:bg-navy-deep/55">
        <div aria-hidden className="pointer-events-none absolute inset-0 bg-noise bg-size-[64px] opacity-[.035]" />
        <div aria-hidden className="pointer-events-none absolute inset-x-0 -bottom-px h-px bg-[linear-gradient(90deg,transparent,rgba(110,231,212,.35)_30%,rgba(110,231,212,.35)_70%,transparent)]" />
        <ScrollProgress />
        <div className="container-x relative flex h-[68px] items-center gap-2 sm:gap-4 lg:gap-8">
          <Link
            href="/"
            aria-label="QuotesDone"
            className="group flex shrink-0 items-center gap-2.5 whitespace-nowrap font-head text-[18px] font-semibold tracking-tight text-white sm:text-[19px]"
          >
            {/* The official mark (drawn inside a padded 800-unit box) is framed, not redrawn: scaled
                about the artwork's own centre so it fills the tile. */}
            <span className="relative grid h-9 w-9 place-items-center overflow-hidden rounded-panel border border-line2 bg-surf shadow-e1 transition-[border-color,box-shadow] duration-slow ease-expo group-hover:border-line3 group-hover:shadow-glow-teal">
              <BrandMark className="h-9 w-9 origin-[56%_52%] scale-[2.05] transition-transform duration-slow ease-expo group-hover:scale-[2.2]" />
            </span>
            <span className="hidden min-[360px]:inline">Quotes<span className="text-teal-light">Done</span></span>
          </Link>
          <AudienceNav labels={labels} services={services} />
        </div>
      </div>
    </header>
  );
}
