'use client';
import { useEffect, useState } from 'react';
import { Link } from '@/i18n/routing';
import { MobileNav } from './MobileNav';
import { LangSwitch } from './LangSwitch';
import { SpringHover } from '@/components/motion/primitives';

/**
 * THE HEADER HAD NO CONCEPT OF AUDIENCE.
 *
 * `SiteHeader` carried one static array rendered identically to everyone:
 *
 *   /#how · /#why · /portal (For suppliers) · /blog/
 *
 * and a "Get quotes" button. A signed-in CUSTOMER was therefore invited into the SUPPLIER portal
 * by the site's main navigation, and offered a "Get quotes" call to action for a thing they had
 * already signed up for. The founder saw the supplier item while logged in as a customer on
 * 13 Aug 2026 and it is the same defect class the portal itself had: a surface that does not know
 * who is looking at it.
 *
 * THE FIX IS NOT DELETING THE SUPPLIER LINK. It is that the list is now a function of who is
 * reading it. A supplier still needs their portal in the nav; a customer needs theirs; a visitor
 * who is neither needs both doors offered.
 *
 * WHY THE CLIENT DECIDES. The session lives in localStorage (`qd-cust-token` / `qd-sup-token`),
 * which the server rendering this header cannot see. So the SHARED items render on the server and
 * are never delayed, and only the ONE audience-specific slot waits for mount — a signed-in
 * customer sees their portal link a frame later rather than seeing the wrong link forever.
 * `mounted` also keeps the server and client markup identical on first paint, so there is no
 * hydration mismatch.
 */
type Item = { href: string; label: string };
export type AudienceLabels = {
  how: string; why: string; blog: string; suppliers: string; services: string; categories: string;
  login: string; getQuotes: string; menu: string; closeMenu: string;
  myPortal: string; supplierPortal: string;
};
export type Audience = 'customer' | 'supplier' | 'visitor';

// Exported: the hero and the closing band read the same tokens (HeroCtas).
export function readAudience(): Audience {
  try {
    if (localStorage.getItem('qd-cust-token')) return 'customer';
    if (localStorage.getItem('qd-sup-token')) return 'supplier';
  } catch (_e) { /* private mode: treat as a visitor */ }
  return 'visitor';
}

export function AudienceNav({ labels, linkClass }: { labels: AudienceLabels; linkClass: string }) {
  const [audience, setAudience] = useState<'customer' | 'supplier' | 'visitor'>('visitor');
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setAudience(readAudience());
    setMounted(true);
    // A sign-out in the portal tab must not leave a stale "My portal" in another tab's header.
    const onStorage = () => setAudience(readAudience());
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

  // The marketing anchors point at sections of the HOME page. They are absolute (`/#how`), so from
  // any other page they navigate home and then scroll — which is why they are kept for every
  // audience rather than hidden off the home page.
  // 14 Sep 2026: "How it works" now opens its own page, "Services" and "Categories" join the header
  // (192 service pages were reachable only from the footer), and "For suppliers" opens the supplier
  // landing page rather than the portal's login box.
  const shared: Item[] = [
    { href: '/how-it-works', label: labels.how },
    { href: '/services', label: labels.services },
    { href: '/#cats', label: labels.categories },
    { href: '/#why', label: labels.why },
    { href: '/blog/', label: labels.blog },
  ];
  const own: Item =
    !mounted || audience === 'visitor' ? { href: '/supplier', label: labels.suppliers }
    : audience === 'customer' ? { href: '/me', label: labels.myPortal }
    : { href: '/portal', label: labels.supplierPortal };
  // Visitors get the marketing order (how · services · categories · why · suppliers · blog). A
  // signed-in person gets their own destination first, because it is the reason they came back.
  const items: Item[] = (!mounted || audience === 'visitor')
    ? [...shared.slice(0, 4), own, shared[4]]
    : [own, ...shared];

  const cta = audience === 'supplier'
    ? { href: '/portal', label: labels.supplierPortal }
    : audience === 'customer'
    ? { href: '/me', label: labels.myPortal }
    : { href: '/me', label: labels.getQuotes };

  return (
    <>
      <nav className="ms-2 hidden items-center gap-0.5 lg:flex">
        {items.map((n) => (
          <Link key={n.href + n.label} href={n.href} className={linkClass}>{n.label}</Link>
        ))}
      </nav>
      <div className="ms-auto flex items-center gap-1 sm:gap-2">
        <LangSwitch />
        {/* A signed-in person does not need a "Sign in" link; the CTA already goes to their portal. */}
        {audience === 'visitor' ? (
          <Link href="/me" className="hidden px-3 py-2 text-[13.5px] font-medium text-muted transition-colors hover:text-white sm:block">
            {labels.login}
          </Link>
        ) : null}
        <SpringHover className="rounded-full">
          <Link
            href={cta.href}
            className="btn-key whitespace-nowrap rounded-full bg-teal px-2.5 py-2.5 text-[12.5px] font-bold leading-none text-[#04231F] shadow-[0_10px_30px_-14px_rgba(20,184,166,.55)] transition-colors duration-200 hover:bg-[#1ED0BC] sm:px-5 sm:text-[14px]"
          >
            {cta.label}
          </Link>
        </SpringHover>
        <MobileNav
          items={items}
          cta={audience === 'supplier' ? { href: '/me', label: labels.getQuotes } : undefined}
          login="/me"
          loginLabel={labels.login}
          menuLabel={labels.menu}
          closeLabel={labels.closeMenu}
        />
      </div>
    </>
  );
}
