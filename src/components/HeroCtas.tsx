'use client';

// THE HOMEPAGE'S CALLS TO ACTION KNOW WHO IS READING, THE WAY THE HEADER ALREADY DID.
//
// A signed-in supplier used to be offered "Get quotes" into the customer portal and "Join as a
// supplier" (website audit, IA section). Both components reuse the header's token read
// (readAudience). SSR and the first client frame render the visitor set, so there is no hydration
// mismatch and the text is on screen before hydration.
import { useEffect, useState } from 'react';
import { Link } from '@/i18n/routing';
import { readAudience, type Audience } from '@/components/AudienceNav';
import s from '@/components/home/sealed.module.css';

function useAudience() {
  const [who, setWho] = useState<Audience>('visitor');
  useEffect(() => { setWho(readAudience()); }, []);
  return who;
}

export type HeroCtaLabels = { getQuotes: string; joinSupplier: string; myPortal: string; supplierPortal: string };

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

/** The closing band's buttons: one primary for the reader's side, one secondary. */
export function HeroCtas({ labels, align = 'start' }: { labels: HeroCtaLabels; align?: 'start' | 'center' }) {
  const who = useAudience();
  const buttons =
    who === 'supplier' ? [{ href: '/portal', label: labels.supplierPortal, main: true }]
    : who === 'customer' ? [{ href: '/me', label: labels.myPortal, main: true }, { href: '/supplier', label: labels.joinSupplier, main: false }]
    : [{ href: '/me', label: labels.getQuotes, main: true }, { href: '/supplier', label: labels.joinSupplier, main: false }];

  return (
    <div className={`flex flex-wrap items-center gap-3 ${align === 'center' ? 'justify-center' : ''}`}>
      {buttons.map((b) =>
        b.main ? (
          <Link key={b.href} href={b.href} className={primary}>
            {b.label}
            <span className={s.arrowDot}><Arrow /></span>
          </Link>
        ) : (
          <Link key={b.href} href={b.href} className={secondary}>{b.label}</Link>
        ),
      )}
    </div>
  );
}

/**
 * The hero's only other action: a quiet text link, so nothing competes with the job box.
 * A visitor or customer is asked "Are you a supplier?"; a signed-in supplier gets their portal.
 */
export function SupplierLink({ ask, how, portal }: { ask: string; how: string; portal: string }) {
  const who = useAudience();
  const link = 'font-semibold text-teal-light underline-offset-4 hover:underline';
  if (who === 'supplier') {
    return (
      <Link href="/portal" className={`text-[14px] ${link}`}>
        {portal} <span aria-hidden className="inline-block rtl:rotate-180">&rarr;</span>
      </Link>
    );
  }
  return (
    <p className="text-[14px] text-muted">
      {ask}{' '}
      <Link href="/supplier" className={link}>
        {how} <span aria-hidden className="inline-block rtl:rotate-180">&rarr;</span>
      </Link>
    </p>
  );
}
