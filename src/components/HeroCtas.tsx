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

export type HeroCtaLabels = {
  getQuotes: string; joinSupplier: string; myPortal: string; supplierPortal: string;
  supplierTitle?: string; supplierBody?: string; supplierHow?: string;
};

// Hover lift is CSS (transform on :hover), not a spring library — see LiveMatch on the bundle.
const lift = 'transition-[transform,background-color,border-color,color] duration-300 ease-expo hover:-translate-y-0.5 motion-reduce:hover:translate-y-0';
const primary = `btn-key press inline-flex rounded-full bg-teal px-7 py-3.5 text-[15px] font-bold text-[#04231F] shadow-[0_16px_44px_-16px_rgba(20,184,166,.8)] hover:bg-[#1ED0BC] ${lift}`;
const secondary = `press inline-flex rounded-full border border-[var(--line2)] bg-teal-light/[0.03] px-7 py-3.5 text-[15px] font-semibold text-paper hover:border-teal hover:bg-teal/[0.07] hover:text-white ${lift}`;

export function HeroCtas({ labels, align = 'start', note = false }: { labels: HeroCtaLabels; align?: 'start' | 'center'; note?: boolean }) {
  const [who, setWho] = useState<Audience>('visitor');
  useEffect(() => { setWho(readAudience()); }, []);

  const buttons =
    who === 'supplier' ? [{ href: '/portal', label: labels.supplierPortal, main: true }]
    : who === 'customer' ? [{ href: '/me', label: labels.myPortal, main: true }, { href: '/supplier', label: labels.joinSupplier, main: false }]
    : [{ href: '/me', label: labels.getQuotes, main: true }, { href: '/supplier', label: labels.joinSupplier, main: false }];

  return (
    <div className={align === 'center' ? 'flex flex-col items-center' : 'flex flex-col items-start'}>
      <div className={`flex flex-wrap items-center gap-3 ${align === 'center' ? 'justify-center' : ''}`}>
        {buttons.map((b) => (
          <Link key={b.href} href={b.href} className={b.main ? primary : secondary}>{b.label}</Link>
        ))}
      </div>
      {note && who === 'supplier' && labels.supplierTitle && (
        <div className="mt-5 max-w-[46ch] rounded-[14px] border border-gold/30 bg-gold/[0.05] px-4 py-3 text-start">
          <p className="text-[13.5px] font-semibold text-gold">{labels.supplierTitle}</p>
          <p className="mt-1 text-[13px] leading-relaxed text-muted">{labels.supplierBody}</p>
          <Link href="/supplier" className="mt-2 inline-block text-[13px] font-semibold text-teal-light underline-offset-4 hover:underline">
            {labels.supplierHow}
          </Link>
        </div>
      )}
    </div>
  );
}
