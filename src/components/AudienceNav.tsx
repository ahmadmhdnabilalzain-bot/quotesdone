'use client';
import { useEffect, useId, useRef, useState } from 'react';
import {
  Building2, Camera, ChefHat, Droplets, Grid3x3, Hammer, Home, Layers, Paintbrush, Signpost, Snowflake,
  Sparkles, Sofa, Sun, Trees, Truck, Waves, Wind, Wrench, Zap, Bug, Square, LayoutGrid, ArrowRight, ChevronDown,
  type LucideIcon,
} from 'lucide-react';
import { Link, usePathname } from '@/i18n/routing';
import { MobileNav } from './MobileNav';
import { LangSwitch } from './LangSwitch';

/**
 * THE HEADER HAD NO CONCEPT OF AUDIENCE (13 Aug 2026): one static list offered the SUPPLIER portal
 * to a signed-in customer. The list is a function of who is reading it. The session lives in
 * localStorage (`qd-cust-token` / `qd-sup-token`), which the server cannot see, so shared items
 * render on the server and only the ONE audience slot waits for mount; `mounted` keeps server and
 * client markup identical on first paint (no hydration mismatch).
 *
 * 14 Sep 2026 (Sealed): "Services" opens a mega-menu over the same taxonomy as the homepage grid,
 * the current page's item is lit (aria-current), and the CTA is the lit, magnetic primary.
 */
type Item = { href: string; label: string };
export type NavService = { slug: string; title: string; tag: string };
export type AudienceLabels = {
  how: string; why: string; blog: string; suppliers: string; services: string; categories: string;
  login: string; getQuotes: string; menu: string; closeMenu: string;
  myPortal: string; supplierPortal: string; servicesLead: string;
  about: string; allTrades: string; guides: string;
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

// Line icons, 1.5px stroke, muted; only the active/hovered state takes teal (brand icon rule).
const ICONS: Record<string, LucideIcon> = {
  solar: Sun, movers: Truck, signage: Signpost, cleaning: Sparkles, flooring: Layers, handyman: Hammer,
  painting: Paintbrush, plumbing: Wrench, electrical: Zap, 'smart-home': Home, landscaping: Trees,
  'pest-control': Bug, 'cctv-security': Camera, 'false-ceiling': Square, 'tiling-marble': Grid3x3,
  waterproofing: Droplets, 'ac-maintenance': Snowflake, 'swimming-pools': Waves, 'aluminium-glass': LayoutGrid,
  'curtains-blinds': Sofa, 'interior-design': Sofa, 'ac-duct-cleaning': Wind, 'joinery-kitchens': ChefHat,
  'facilities-management': Building2,
};

const linkBase = 'relative inline-flex h-9 items-center gap-1 whitespace-nowrap rounded-btn px-2.5 text-small font-medium transition-colors duration-base';
const linkIdle = 'text-muted hover:bg-teal-light/5 hover:text-white';
const linkOn = 'text-white after:absolute after:inset-x-3 after:-bottom-[15px] after:h-px after:bg-teal-light after:shadow-[0_0_10px_rgba(110,231,212,.9)]';

export function AudienceNav({ labels, services }: { labels: AudienceLabels; services: NavService[] }) {
  const [audience, setAudience] = useState<Audience>('visitor');
  const [mounted, setMounted] = useState(false);
  const [open, setOpen] = useState(false);
  const pathname = usePathname();
  const panelId = useId();
  const wrap = useRef<HTMLDivElement>(null);
  const closeT = useRef<ReturnType<typeof setTimeout> | null>(null);
  // Set when hovering opened the panel: the click that follows on the same trigger must keep it open,
  // not toggle it shut (a mouse user hovers, then clicks; measured by scripts/e2e/site_crawl.mjs).
  const byHover = useRef(false);

  useEffect(() => {
    setAudience(readAudience());
    setMounted(true);
    // A sign-out in the portal tab must not leave a stale "My portal" in another tab's header.
    const onStorage = () => setAudience(readAudience());
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);
  useEffect(() => setOpen(false), [pathname]);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false); };
    const onDown = (e: PointerEvent) => { if (!wrap.current?.contains(e.target as Node)) setOpen(false); };
    document.addEventListener('keydown', onKey);
    document.addEventListener('pointerdown', onDown);
    return () => { document.removeEventListener('keydown', onKey); document.removeEventListener('pointerdown', onDown); };
  }, [open]);

  const hoverOpen = () => { if (closeT.current) clearTimeout(closeT.current); if (!open) byHover.current = true; setOpen(true); };
  const onTrigger = () => { if (byHover.current) { byHover.current = false; return; } setOpen((v) => !v); };
  const hoverClose = () => { byHover.current = false; closeT.current = setTimeout(() => setOpen(false), 140); };

  // "How it works" opens its own page, "Categories" the homepage grid, "For suppliers" the supplier
  // landing page. Services is rendered separately as the mega-menu trigger.
  const shared: Item[] = [
    { href: '/how-it-works', label: labels.how },
    { href: '/#cats', label: labels.categories },
    { href: '/#why', label: labels.why },
    { href: '/blog/', label: labels.blog },
    { href: '/about', label: labels.about },
  ];
  const own: Item =
    !mounted || audience === 'visitor' ? { href: '/supplier', label: labels.suppliers }
    : audience === 'customer' ? { href: '/me', label: labels.myPortal }
    : { href: '/portal', label: labels.supplierPortal };
  const items: Item[] = (!mounted || audience === 'visitor') ? [...shared.slice(0, 3), own, ...shared.slice(3)] : [own, ...shared];
  const mobileItems: Item[] = [items[0], { href: '/services', label: labels.services }, ...items.slice(1)];
  const cta = audience === 'supplier' ? { href: '/portal', label: labels.supplierPortal }
    : audience === 'customer' ? { href: '/me', label: labels.myPortal }
    : { href: '/me', label: labels.getQuotes };
  const isOn = (href: string) => !href.includes('#') && (pathname === href || pathname === href.replace(/\/$/, '') || (href !== '/' && pathname.startsWith(href.replace(/\/$/, '') + '/')));
  const servicesOn = pathname.startsWith('/services');

  return (
    <>
      <nav className="hidden items-center gap-0.5 xl:flex" aria-label={labels.menu}>
        <Link href={items[0].href} aria-current={isOn(items[0].href) ? 'page' : undefined} className={`${linkBase} ${isOn(items[0].href) ? linkOn : linkIdle}`}>{items[0].label}</Link>
        <div ref={wrap} className="relative" onPointerEnter={hoverOpen} onPointerLeave={hoverClose}>
          <button
            type="button"
            aria-expanded={open}
            aria-controls={panelId}
            onClick={onTrigger}
            className={`${linkBase} ${servicesOn ? linkOn : linkIdle} ${open ? 'bg-teal-light/6 text-white' : ''}`}
          >
            {labels.services}
            <ChevronDown className={`h-3.5 w-3.5 transition-transform duration-base ${open ? 'rotate-180 text-teal-light' : ''}`} strokeWidth={1.75} aria-hidden />
          </button>
          <div
            id={panelId}
            hidden={!open}
            className="fixed inset-x-0 top-[68px] z-50 motion-safe:animate-in motion-safe:fade-in-0 motion-safe:slide-in-from-top-1"
          >
            <div className="container-x">
              <div className="qd-panel qd-grain grid overflow-hidden rounded-frame! border-line2 bg-navy/95! shadow-e3! lg:grid-cols-[1fr_300px]">
                <div className="p-6">
                  <div className="flex items-baseline justify-between gap-6">
                    <span className="qd-kicker">{labels.guides}</span>
                    <Link href="/services#all-trades" className="group inline-flex items-center gap-1.5 text-small font-medium text-teal-light hover:text-white">
                      {labels.allTrades}
                      <ArrowRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5 rtl:rotate-180 group-hover:rtl:-translate-x-0.5" aria-hidden />
                    </Link>
                  </div>
                  <ul className="mt-4 grid grid-cols-2 gap-1 xl:grid-cols-3">
                    {services.map((s) => {
                      const Icon = ICONS[s.slug] ?? LayoutGrid;
                      return (
                        <li key={s.slug}>
                          <Link href={`/services/${s.slug}`} className="qd-hoverlit group flex items-start gap-3 rounded-panel p-2.5 transition-colors hover:bg-teal-light/5">
                            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-btn border border-line2 bg-surf text-muted shadow-key transition-colors group-hover:border-teal/50 group-hover:text-teal-light">
                              <Icon className="h-[18px] w-[18px]" strokeWidth={1.5} aria-hidden />
                            </span>
                            <span className="min-w-0">
                              <span className="block truncate text-small font-medium text-paper group-hover:text-white">{s.title}</span>
                              {s.tag ? <span className="mt-0.5 block truncate text-label text-faint">{s.tag}</span> : null}
                            </span>
                          </Link>
                        </li>
                      );
                    })}
                  </ul>
                </div>
                {/* the promise, sealed: a quote card whose supplier stays hidden */}
                <aside className="relative hidden flex-col justify-between gap-6 border-s border-line bg-[radial-gradient(80%_60%_at_50%_0%,rgba(20,184,166,.14),transparent_70%)] p-6 lg:flex">
                  <p className="text-small text-muted">{labels.servicesLead}</p>
                  <div className="qd-panel p-4">
                    <div className="flex items-center justify-between"><span className="redact h-3 w-24" /><span className="font-mono text-label text-faint">Q-0412</span></div>
                    {[92, 70, 84].map((w) => <span key={w} className="mt-3 block h-[3px] rounded-full bg-(--line2)" style={{ width: `${w}%` }} />)}
                    <div className="mt-4 flex items-end justify-between"><span className="redact h-3 w-16" /><span className="h-2 w-12 rounded-full bg-teal/60" /></div>
                  </div>
                  <Link href={cta.href} className="qd-hoverlit inline-flex h-10 items-center justify-center rounded-btn bg-teal text-small font-semibold text-on-teal shadow-e1 hover:shadow-glow-teal">{labels.getQuotes}</Link>
                </aside>
              </div>
            </div>
          </div>
        </div>
        {items.slice(1).map((n) => (
          <Link key={n.href + n.label} href={n.href} aria-current={isOn(n.href) ? 'page' : undefined} className={`${linkBase} ${isOn(n.href) ? linkOn : linkIdle}`}>{n.label}</Link>
        ))}
      </nav>
      <div className="ms-auto flex items-center gap-1.5 sm:gap-2">
        {/* below sm the switch lives in the mobile sheet: the bar measured 398px in a 375px viewport */}
        <span className="hidden sm:contents"><LangSwitch /></span>
        {/* A signed-in person does not need a "Sign in" link; the CTA already goes to their portal. */}
        {audience === 'visitor' ? (
          <Link href="/supplier" className="hidden h-9 items-center whitespace-nowrap px-3 text-small font-medium text-muted transition-colors hover:text-white md:inline-flex xl:hidden">{labels.suppliers}</Link>
        ) : null}
        {/* below md both portal links sit in PortalRow, under the bar */}
        {audience === 'visitor' ? (
          <Link href="/me" className="hidden h-9 items-center whitespace-nowrap px-3 text-small font-medium text-muted transition-colors hover:text-white md:inline-flex">{labels.login}</Link>
        ) : null}
        {/* 44 px tall on a phone (website audit 10 Nov 2026: measured 93x36 at 390 px, under the 44 px
            tap minimum); the PortalRow buttons under it were already h-11. 40 px from sm up. */}
        <Link
          href={cta.href}
          className="btn-key qd-magnet inline-flex h-11 items-center whitespace-nowrap rounded-btn bg-teal px-3 text-small font-semibold text-on-teal shadow-[inset_0_1px_0_rgba(255,255,255,.35),0_10px_30px_-12px_rgba(20,184,166,.7)] transition-[background-color,box-shadow] duration-base hover:bg-[#1ED0BC] hover:shadow-glow-teal sm:h-10 sm:px-5 sm:text-copy"
        >
          {cta.label}
        </Link>
        <MobileNav
          items={mobileItems}
          services={services}
          servicesLabel={labels.services}
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

/**
 * 3 Nov 2026, the founder: "why there is no customer portal button on the website till now". Below
 * md the bar holds only the logo, the CTA and the menu button (it measured 398px in a 375px viewport
 * with more), so both portal links were hidden and a phone visitor saw neither without opening the
 * menu. They get their own row under the bar, equal width, 44px tall. Visitors only, like the bar's
 * own portal links: a signed-in person's CTA already opens their portal.
 */
export function PortalRow({ customer, supplier }: { customer: string; supplier: string }) {
  const [audience, setAudience] = useState<Audience>('visitor');
  useEffect(() => {
    setAudience(readAudience());
    const onStorage = () => setAudience(readAudience());
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);
  if (audience !== 'visitor') return null;
  const cls = 'inline-flex h-11 min-w-0 items-center justify-center whitespace-nowrap rounded-btn border border-line2 bg-surf/60 px-3 text-small font-medium text-paper shadow-key transition-colors duration-base hover:border-teal/50 hover:text-white';
  return (
    <div className="qd-portal-row container-x relative grid grid-cols-2 gap-2 pb-2.5 md:hidden">
      <Link href="/me" className={cls}>{customer}</Link>
      <Link href="/supplier" className={cls}>{supplier}</Link>
    </div>
  );
}
