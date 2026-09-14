import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { ScrollProgress } from '@/components/motion/primitives';
import { BrandMark } from '@/components/BrandMark';
import { AudienceNav } from './AudienceNav';

export function SiteHeader() {
  const t = useTranslations('nav');
  const link =
    'rounded-lg px-3 py-2 text-[13.5px] font-medium text-muted transition-colors duration-200 hover:bg-teal-light/[0.06] hover:text-white';
  // THE NAV IS NO LONGER A CONSTANT. It was one static array — how · why · FOR SUPPLIERS · blog —
  // rendered identically to a first-time visitor and to a signed-in customer, which is how the
  // site's own header came to offer the supplier portal to a paying customer. The destinations now
  // depend on who is reading; the STRINGS still resolve here, on the server, so nothing about
  // translation moves to the client. See AudienceNav for why only one slot waits for mount.
  const labels = {
    how: t('how'), why: t('why'), blog: t('blog'), suppliers: t('suppliers'),
    services: t('services'), categories: t('categories'),
    login: t('login'), getQuotes: t('getQuotes'), menu: t('menu'), closeMenu: t('closeMenu'),
    myPortal: t('myPortal'), supplierPortal: t('supplierPortal'),
  };
  return (
    <>
      <header className="sticky top-0 z-40 border-b border-[var(--line)] bg-navy-deep/[0.74] backdrop-blur-xl backdrop-saturate-150 supports-[backdrop-filter]:bg-navy-deep/[0.62]">
        <ScrollProgress />
        <div className="container-x flex h-16 items-center gap-1.5 sm:gap-3 md:gap-6">
          <Link
            href="/"
            aria-label="QuotesDone"
            className="group flex items-center gap-2 whitespace-nowrap font-head text-[17px] font-bold tracking-tight text-white sm:text-[19px]"
          >
            <BrandMark className="h-7 w-7 shrink-0 drop-shadow-[0_2px_8px_rgba(20,184,166,.35)] transition-transform duration-300 ease-expo group-hover:rotate-[8deg] group-hover:scale-110 sm:h-[30px] sm:w-[30px]" />
            <span>
              Quotes<span className="text-teal">Done</span>
            </span>
          </Link>
          <AudienceNav labels={labels} linkClass={link} />
        </div>
      </header>
    </>
  );
}
