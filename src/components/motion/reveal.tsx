/**
 * REVEAL — the CSS scroll-driven entrance (globals.css `.reveal`). Deliberately NOT a client module.
 *
 * These three lived in motion/primitives.tsx, a 'use client' file that imported motion/react at
 * module top. Every homepage section imported Reveal from it, so the whole motion runtime was in
 * the first load of / and /ar even though Reveal itself is a plain <div>. Measured on a local
 * `next build` + Lighthouse 12 mobile, 14 Sep 2026: two first-load chunks (45 KB + 44 KB) carried
 * motion's LayoutGroup/AnimatePresence code. With no 'use client' here, the sections stay server
 * components and ship no JS for this.
 *
 * Without JS, without scroll-timeline support (Safari/Firefox today) or with reduced motion, the
 * content is simply visible: there is no code path in which it can fail to appear.
 * `delay`, `y` and `once` are accepted and ignored so no call site has to change.
 */
import type { CSSProperties, ReactNode } from 'react';

type Props = { children: ReactNode; className?: string; style?: CSSProperties };

export function Reveal({ children, className, style }: Props & { delay?: number; y?: number; once?: boolean }) {
  return <div className={className ? `reveal ${className}` : 'reveal'} style={style}>{children}</div>;
}

/** The container is a plain div; each StaggerItem takes .reveal, so items cascade on scroll. */
export function Stagger({ children, className, style }: Props & { once?: boolean }) {
  return <div className={className} style={style}>{children}</div>;
}

export function StaggerItem({ children, className, style }: Props) {
  return <div className={className ? `reveal ${className}` : 'reveal'} style={style}>{children}</div>;
}
