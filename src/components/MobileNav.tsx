'use client';
import { useEffect, useId, useRef, useState } from 'react';
import { Link } from '@/i18n/routing';

type Item = { href: string; label: string };

/**
 * Mobile navigation.
 *
 * The header hides its nav below `md`, which previously left phone users with
 * no way to reach How it works / Why anonymous / For suppliers / Blog except
 * through the footer. This restores those exact destinations — it adds no new
 * routes and no new labels; both come from the same translation keys the
 * desktop nav uses, so the two can never drift apart.
 */
export function MobileNav({ items, login, loginLabel, menuLabel, closeLabel }: {
  items: Item[];
  login: string;
  loginLabel: string;
  menuLabel: string;
  closeLabel: string;
}) {
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const btnRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);

  // Escape closes; focus returns to the trigger so keyboard users aren't stranded.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { setOpen(false); btnRef.current?.focus(); }
    };
    // keep focus inside the panel while it is open
    const onFocus = (e: FocusEvent) => {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)
          && e.target !== btnRef.current) {
        panelRef.current.querySelector<HTMLElement>('a,button')?.focus();
      }
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('focusin', onFocus);
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';           // no scroll behind the sheet
    panelRef.current?.querySelector<HTMLElement>('a,button')?.focus();
    return () => {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('focusin', onFocus);
      document.body.style.overflow = prev;
    };
  }, [open]);

  return (
    <div className="md:hidden">
      <button
        ref={btnRef}
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        aria-controls={panelId}
        aria-label={open ? closeLabel : menuLabel}
        className="grid h-9 w-9 place-items-center sm:h-10 sm:w-10 rounded-xl border border-[var(--line2)] bg-teal-light/[0.04] text-paper transition-colors duration-200 hover:border-teal hover:text-white"
      >
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"
             strokeWidth="2" strokeLinecap="round" aria-hidden="true">
          {open
            ? <><path d="M18 6 6 18" /><path d="m6 6 12 12" /></>
            : <><path d="M3 6h18" /><path d="M3 12h18" /><path d="M3 18h18" /></>}
        </svg>
      </button>

      {open && (
        <>
          <div
            className="fixed inset-0 top-16 z-30 bg-navy-deep/70 backdrop-blur-sm"
            onClick={() => setOpen(false)}
            aria-hidden="true"
          />
          <div
            id={panelId}
            ref={panelRef}
            className="fixed inset-x-0 top-16 z-40 border-b border-[var(--line2)] bg-navy-deep/[0.98] px-6 pb-6 pt-2 shadow-[0_30px_60px_-30px_rgba(3,12,18,.9)]"
          >
            <nav aria-label={menuLabel}>
              <ul className="flex flex-col">
                {items.map((it) => (
                  <li key={it.href}>
                    <Link
                      href={it.href}
                      onClick={() => setOpen(false)}
                      className="flex min-h-[52px] items-center border-b border-[var(--line)] text-[16px] font-medium text-paper transition-colors duration-200 hover:text-teal-light"
                    >
                      {it.label}
                    </Link>
                  </li>
                ))}
                <li>
                  <Link
                    href={login}
                    onClick={() => setOpen(false)}
                    className="flex min-h-[52px] items-center text-[16px] font-medium text-muted transition-colors duration-200 hover:text-white"
                  >
                    {loginLabel}
                  </Link>
                </li>
              </ul>
            </nav>
          </div>
        </>
      )}
    </div>
  );
}
