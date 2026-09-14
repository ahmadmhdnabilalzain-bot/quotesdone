'use client';

/**
 * PREMIUM MOTION LAYER
 * Reusable client-side wrappers so the section components can stay server
 * components. Every wrapper is purely presentational — it only wraps existing
 * markup, never alters props, state, handlers or data flow. All effects are
 * fully gated on prefers-reduced-motion.
 */

import {
  motion,
  useReducedMotion,
  useMotionValue,
  useSpring,
  useTransform,
  useScroll,
  type Variants,
} from 'motion/react';
import { useRef, type ReactNode, type CSSProperties } from 'react';

const EASE = [0.16, 1, 0.3, 1] as const;

/* ── Reveal: ONE reveal system, the CSS one (website audit 14 Sep 2026) ─────────────────────
   This was a motion/react whileInView wrapper whose SSR state was opacity:0 + blur(6px). Measured
   on the live homepage: 29 elements shipped at opacity:0, the hero headline and CTAs among them,
   and LCP was 7,648 ms of which 7,604 ms was render delay waiting for ~850 KB of JS to hydrate.
   It now renders the CSS scroll-driven `.reveal` (globals.css), which has no failure path: without
   JS, without scroll-timeline support (Safari/Firefox today) or with reduced motion, the content is
   simply visible. `delay`, `y` and `once` are accepted and ignored so no call site has to change. */
export function Reveal({
  children,
  className,
  style,
}: {
  children: ReactNode;
  className?: string;
  delay?: number;
  y?: number;
  once?: boolean;
  style?: CSSProperties;
}) {
  return <div className={className ? `reveal ${className}` : 'reveal'} style={style}>{children}</div>;
}

/* ── Stagger / StaggerItem: same collapse as Reveal — the container is a plain div and each item
   takes the CSS scroll-driven .reveal, so items still cascade as they scroll into view. ───── */
export function Stagger({
  children,
  className,
  style,
}: {
  children: ReactNode;
  className?: string;
  once?: boolean;
  style?: CSSProperties;
}) {
  return <div className={className} style={style}>{children}</div>;
}

export function StaggerItem({
  children,
  className,
  style,
}: {
  children: ReactNode;
  className?: string;
  style?: CSSProperties;
}) {
  return <div className={className ? `reveal ${className}` : 'reveal'} style={style}>{children}</div>;
}

/* ── TiltCard: 3D parallax tilt + radial cursor-tracking glow ─────────────── */
export function TiltCard({
  children,
  className,
  style,
  max = 8,
  glow = true,
}: {
  children: ReactNode;
  className?: string;
  style?: CSSProperties;
  max?: number;
  glow?: boolean;
}) {
  const reduce = useReducedMotion();
  const ref = useRef<HTMLDivElement | null>(null);

  const px = useMotionValue(0.5);
  const py = useMotionValue(0.5);
  const sx = useSpring(px, { stiffness: 150, damping: 18, mass: 0.4 });
  const sy = useSpring(py, { stiffness: 150, damping: 18, mass: 0.4 });

  const rotateY = useTransform(sx, [0, 1], [-max, max]);
  const rotateX = useTransform(sy, [0, 1], [max, -max]);
  const glowX = useTransform(sx, [0, 1], ['0%', '100%']);
  const glowY = useTransform(sy, [0, 1], ['0%', '100%']);
  const glowBg = useTransform(
    [glowX, glowY],
    ([x, y]: string[]) =>
      `radial-gradient(380px circle at ${x} ${y}, rgba(110,231,212,.24), transparent 60%)`,
  );

  function onMove(e: React.PointerEvent<HTMLDivElement>) {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    px.set((e.clientX - r.left) / r.width);
    py.set((e.clientY - r.top) / r.height);
  }
  function onLeave() {
    px.set(0.5);
    py.set(0.5);
  }

  if (reduce) {
    return (
      <div className={className} style={style}>
        {children}
      </div>
    );
  }

  return (
    <motion.div
      ref={ref}
      onPointerMove={onMove}
      onPointerLeave={onLeave}
      className={className}
      style={{
        ...style,
        rotateX,
        rotateY,
        transformStyle: 'preserve-3d',
        transformPerspective: 1100,
      }}
    >
      {glow && (
        <motion.span
          aria-hidden
          className="pointer-events-none absolute inset-0 z-10 rounded-[inherit]"
          style={{ background: glowBg }}
        />
      )}
      <div style={{ transform: 'translateZ(0.01px)' }}>{children}</div>
    </motion.div>
  );
}

/* ── SpringHover: spring-physics scale/lift for CTAs and interactive tiles ─── */
export function SpringHover({
  children,
  className,
  scale = 1.035,
  lift = -2,
  style,
}: {
  children: ReactNode;
  className?: string;
  scale?: number;
  lift?: number;
  style?: CSSProperties;
}) {
  const reduce = useReducedMotion();
  if (reduce) {
    return (
      <span className={className} style={style}>
        {children}
      </span>
    );
  }
  return (
    <motion.span
      className={className}
      style={{ display: 'inline-flex', ...style }}
      whileHover={{ scale, y: lift }}
      whileTap={{ scale: 0.97 }}
      transition={{ type: 'spring', stiffness: 380, damping: 22, mass: 0.5 }}
    >
      {children}
    </motion.span>
  );
}

/* ── Spotlight: a radial glow that tracks the cursor across a section ─────── */
export function Spotlight({
  children,
  className,
  size = 520,
  style,
}: {
  children: ReactNode;
  className?: string;
  size?: number;
  style?: CSSProperties;
}) {
  const reduce = useReducedMotion();
  const ref = useRef<HTMLDivElement | null>(null);
  const mx = useMotionValue(-1);
  const my = useMotionValue(-1);
  const sx = useSpring(mx, { stiffness: 220, damping: 30, mass: 0.5 });
  const sy = useSpring(my, { stiffness: 220, damping: 30, mass: 0.5 });
  const bg = useTransform([sx, sy], ([x, y]: number[]) =>
    x < 0
      ? 'radial-gradient(0px circle at 50% 50%, transparent, transparent)'
      : `radial-gradient(${size}px circle at ${x}px ${y}px, rgba(110,231,212,.12), transparent 68%)`,
  );

  function onMove(e: React.PointerEvent<HTMLDivElement>) {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    mx.set(e.clientX - r.left);
    my.set(e.clientY - r.top);
  }
  function onLeave() {
    mx.set(-1);
    my.set(-1);
  }

  if (reduce) {
    return (
      <div className={className} style={style}>
        {children}
      </div>
    );
  }

  return (
    <div
      ref={ref}
      onPointerMove={onMove}
      onPointerLeave={onLeave}
      className={className}
      style={{ position: 'relative', ...style }}
    >
      <motion.div
        aria-hidden
        className="pointer-events-none absolute inset-0 z-0"
        style={{ background: bg }}
      />
      <div className="relative z-10">{children}</div>
    </div>
  );
}

/* ── ScrollProgress: a hairline neon bar tracking page scroll ─────────────── */
export function ScrollProgress() {
  const reduce = useReducedMotion();
  const { scrollYProgress } = useScroll();
  const scaleX = useSpring(scrollYProgress, { stiffness: 120, damping: 30, mass: 0.4 });
  if (reduce) return null;
  return (
    <motion.div
      aria-hidden
      className="absolute inset-x-0 bottom-[-1px] z-50 h-0.5 origin-left bg-gradient-to-r from-teal via-teal-light to-gold"
      style={{ scaleX, boxShadow: '0 0 16px rgba(110,231,212,.7)' }}
    />
  );
}
