import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { LangSwitch } from './LangSwitch';

export function SiteHeader() {
  const t = useTranslations('nav');
  const link =
    'rounded-lg px-3 py-2 text-[13.5px] font-medium text-muted transition-colors duration-200 hover:bg-teal-light/[0.06] hover:text-white';
  return (
    <>
      <a className="skip" href="#main">Skip to main content</a>
      <header className="sticky top-0 z-40 border-b border-transparent bg-navy-deep/[0.74] backdrop-blur-xl backdrop-saturate-150 supports-[backdrop-filter]:bg-navy-deep/[0.62]">
        <div className="container-x flex h-16 items-center gap-6">
          <Link href="/" className="font-head text-[19px] font-bold tracking-tight text-white">
            Quotes<span className="text-teal">Done</span>
          </Link>
          <nav className="ms-2 hidden items-center gap-0.5 md:flex">
            <Link href="/#how" className={link}>{t('how')}</Link>
            <Link href="/#why" className={link}>{t('why')}</Link>
            <Link href="/portal" className={link}>{t('suppliers')}</Link>
            <Link href="/blog/" className={link}>{t('blog')}</Link>
          </nav>
          <div className="ms-auto flex items-center gap-2">
            <LangSwitch />
            <Link href="/me" className="hidden px-3 py-2 text-[13.5px] font-medium text-muted transition-colors hover:text-white sm:block">
              {t('login')}
            </Link>
            <Link
              href="/me"
              className="btn-key rounded-full bg-teal px-5 py-2.5 text-[14px] font-bold text-[#04231F] shadow-[0_10px_30px_-14px_rgba(20,184,166,.55)] transition-colors duration-200 hover:bg-[#1ED0BC]"
            >
              {t('getQuotes')}
            </Link>
          </div>
        </div>
      </header>
    </>
  );
}
