import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { LangSwitch } from './LangSwitch';
import { MobileNav } from './MobileNav';
import { ScrollProgress, SpringHover } from '@/components/motion/primitives';
import { BrandMark } from '@/components/BrandMark';

export function SiteHeader() {
  const t = useTranslations('nav');
  const link =
    'rounded-lg px-3 py-2 text-[13.5px] font-medium text-muted transition-colors duration-200 hover:bg-teal-light/[0.06] hover:text-white';
  // one nav definition, rendered twice — desktop inline, mobile in the sheet
  const NAV = [
    { href: '/#how', label: t('how') },
    { href: '/#why', label: t('why') },
    { href: '/portal', label: t('suppliers') },
    { href: '/blog/', label: t('blog') },
  ];
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
          <nav className="ms-2 hidden items-center gap-0.5 md:flex">
            {NAV.map((n) => (
              <Link key={n.href} href={n.href} className={link}>{n.label}</Link>
            ))}
          </nav>
          <div className="ms-auto flex items-center gap-1 sm:gap-2">
            <LangSwitch />
            <Link href="/me" className="hidden px-3 py-2 text-[13.5px] font-medium text-muted transition-colors hover:text-white sm:block">
              {t('login')}
            </Link>
            <SpringHover className="rounded-full">
              <Link
                href="/me"
                className="btn-key whitespace-nowrap rounded-full bg-teal px-2.5 py-2.5 text-[12.5px] font-bold leading-none text-[#04231F] shadow-[0_10px_30px_-14px_rgba(20,184,166,.55)] transition-colors duration-200 hover:bg-[#1ED0BC] sm:px-5 sm:text-[14px]"
              >
                {t('getQuotes')}
              </Link>
            </SpringHover>
            <MobileNav
              items={NAV}
              login="/me"
              loginLabel={t('login')}
              menuLabel={t('menu')}
              closeLabel={t('closeMenu')}
            />
          </div>
        </div>
      </header>
    </>
  );
}
