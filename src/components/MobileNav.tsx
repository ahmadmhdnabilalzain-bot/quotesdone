'use client';
import { useEffect, useId, useRef, useState } from 'react';
import { Link } from '@/i18n/routing';

type Item = { href: string; label: string };

/**
 * Mobile navigation: a full-height sealed sheet under the header. Large type, items rise in order
 * (qd-stagger), the services taxonomy as a scrolling chip row, sign-in at the foot. Same
 * destinations and labels as the desktop nav, so the two can never drift apart.
 * Escape closes and returns focus to the trigger; focus is kept inside while open.
 */
export function MobileNav({ items, services, servicesLabel, cta, login, loginLabel, menuLabel, closeLabel }: {
  items: Item[];
  services?: { slug: string; title: string }[];
  servicesLabel?: string;
  /** The customer "Get quotes" door, for a reader whose header CTA points elsewhere (a supplier). */
  cta?: Item;
  login: string;
  loginLabel: string;
  menuLabel: string;
  closeLabel: string;
}) {
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const btnRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { setOpen(false); btnRef.current?.focus(); } };
    const onFocus = (e: FocusEvent) => {
      if (panelRef.current && !panelRef.current.contains(e.target as Node) && e.target !== btnRef.current) {
        panelRef.current.querySelector<HTMLElement>('a,button')?.focus();
      }
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('focusin', onFocus);
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    panelRef.current?.querySelector<HTMLElement>('a,button')?.focus();
    return () => {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('focusin', onFocus);
      document.body.style.overflow = prev;
    };
  }, [open]);

  const close = () => setOpen(false);
  return (
    <div className="lg:hidden">
      <button
        ref={btnRef}
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        aria-controls={panelId}
        aria-label={open ? closeLabel : menuLabel}
        className="grid h-9 w-9 place-items-center rounded-btn border border-line2 bg-surf/60 text-paper shadow-key transition-colors duration-base hover:border-line3 sm:h-10 sm:w-10"
      >
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" aria-hidden="true">
          {open ? <><path d="M18 6 6 18" /><path d="m6 6 12 12" /></> : <><path d="M4 8h16" /><path d="M4 16h10" /></>}
        </svg>
      </button>

      {open && (
        <div
          id={panelId}
          ref={panelRef}
          className="fixed inset-x-0 bottom-0 top-[68px] z-40 overflow-y-auto border-t border-line bg-navy-deep/[0.97] backdrop-blur-xl motion-safe:animate-in motion-safe:fade-in-0"
        >
          <div aria-hidden className="pointer-events-none absolute inset-x-0 top-0 h-72 bg-[radial-gradient(60%_100%_at_50%_0%,rgba(20,184,166,.14),transparent_70%)]" />
          <nav aria-label={menuLabel} className="container-x relative flex min-h-full flex-col pb-10 pt-4">
            <ul className="qd-stagger flex flex-col">
              {items.map((it, i) => (
                <li key={it.href}>
                  <Link href={it.href} onClick={close} className="group flex min-h-[60px] items-center gap-4 border-b border-line font-head text-[22px] font-medium tracking-snug text-paper transition-colors hover:text-teal-light">
                    <span className="w-6 font-mono text-label text-faint group-hover:text-teal-light">{String(i + 1).padStart(2, '0')}</span>
                    {it.label}
                  </Link>
                </li>
              ))}
            </ul>
            {services && services.length ? (
              <div className="mt-8">
                <span className="qd-kicker">{servicesLabel}</span>
                <div className="-mx-4 mt-4 flex gap-2 overflow-x-auto px-4 pb-2 [scrollbar-width:none]">
                  {services.map((s) => (
                    <Link key={s.slug} href={`/services/${s.slug}`} onClick={close} className="shrink-0 whitespace-nowrap rounded-pill border border-line2 bg-surf/70 px-4 py-2 text-small text-paper shadow-key hover:border-teal">
                      {s.title}
                    </Link>
                  ))}
                </div>
              </div>
            ) : null}
            <div className="mt-auto flex flex-col gap-3 pt-10">
              {cta && (
                <Link href={cta.href} onClick={close} className="flex min-h-[52px] items-center justify-center rounded-btn bg-teal text-[16px] font-semibold text-on-teal shadow-e1">
                  {cta.label}
                </Link>
              )}
              <Link href={login} onClick={close} className="flex min-h-[52px] items-center justify-center rounded-btn border border-line2 text-[16px] font-medium text-paper hover:border-teal">
                {loginLabel}
              </Link>
            </div>
          </nav>
        </div>
      )}
    </div>
  );
}
