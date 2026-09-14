'use client';

// THE HERO AND THE CLOSING BAND KNOW WHO IS READING, THE WAY THE HEADER ALREADY DID.
//
// Hero and CtaBand were static: a signed-in supplier was still offered "Get quotes" into the
// customer portal and "Join as a supplier" (website audit, IA section). This reuses the header's
// token read (readAudience) and swaps the buttons. SSR and the first client frame render the
// visitor set, so there is no hydration mismatch and the text is on screen before hydration.
import { useEffect, useState } from 'react';
import { Link } from '@/i18n/routing';
import { readAudience, type Audience } from '@/components/AudienceNav';
import s from '@/components/home/sealed.module.css';

export type HeroCtaLabels = {
  getQuotes: string; joinSupplier: string; myPortal: string; supplierPortal: string;
  supplierTitle?: string; supplierBody?: string; supplierHow?: string;
};

// The primary is an island pill with its arrow nested in its own disc; hover moves the disc, not
// the pill. Transform/colour transitions only.
const primary = 'group press inline-flex items-center gap-3 rounded-full bg-teal py-2 pe-2 ps-6 text-[15px] font-bold text-[#04231F] shadow-[0_18px_44px_-18px_rgba(20,184,166,.85)] transition-colors duration-300 hover:bg-[#1ED0BC]';
const secondary = 'press inline-flex items-center rounded-full px-6 py-[13px] text-[15px] font-semibold text-paper shadow-[inset_0_0_0_1px_rgba(110,231,212,.22)] transition-[box-shadow,color] duration-300 hover:text-white hover:shadow-[inset_0_0_0_1px_rgba(110,231,212,.55)]';

export function Arrow() {
  return (
    <svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" className="rtl:-scale-x-100" aria-hidden>
      <path d="M3 8h10M9 4l4 4-4 4" />
    </svg>
  );
}

// `quiet`: every link takes the secondary style — used in the hero, where the job box is the one
// primary action and a second filled button would compete with it.
export function HeroCtas({ labels, align = 'start', note = false, quiet = false }: { labels: HeroCtaLabels; align?: 'start' | 'center'; note?: boolean; quiet?: boolean }) {
  const [who, setWho] = useState<Audience>('visitor');
  useEffect(() => { setWho(readAudience()); }, []);

  const buttons =
    who === 'supplier' ? [{ href: '/portal', label: labels.supplierPortal, main: true }]
    : who === 'customer' ? [{ href: '/me', label: labels.myPortal, main: true }, { href: '/supplier', label: labels.joinSupplier, main: false }]
    : [{ href: '/me', label: labels.getQuotes, main: true }, { href: '/supplier', label: labels.joinSupplier, main: false }];

  return (
    <div className={align === 'center' ? 'flex flex-col items-center' : 'flex flex-col items-start'}>
      <div className={`flex flex-wrap items-center gap-3 ${align === 'center' ? 'justify-center' : ''}`}>
        {buttons.map((b) =>
          b.main && !quiet ? (
            <Link key={b.href} href={b.href} className={primary}>
              {b.label}
              <span className={s.arrowDot}><Arrow /></span>
            </Link>
          ) : (
            <Link key={b.href} href={b.href} className={secondary}>{b.label}</Link>
          ),
        )}
      </div>
      {note && who === 'supplier' && labels.supplierTitle && (
        <div className="mt-5 max-w-[46ch] rounded-[14px] px-4 py-3 text-start shadow-[inset_0_0_0_1px_rgba(110,231,212,.2)]">
          <p className="text-[13.5px] font-semibold text-teal-light">{labels.supplierTitle}</p>
          <p className="mt-1 text-[13px] leading-relaxed text-muted">{labels.supplierBody}</p>
          <Link href="/supplier" className="mt-2 inline-block text-[13px] font-semibold text-teal-light underline-offset-4 hover:underline">
            {labels.supplierHow}
          </Link>
        </div>
      )}
    </div>
  );
}
