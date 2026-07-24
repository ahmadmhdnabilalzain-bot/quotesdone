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

/* ── Reveal: organic fade + rise + de-blur when scrolled into view ───────── */
export function Reveal({
  children,
  className,
  delay = 0,
  y = 24,
  once = true,
  style,
}: {
  children: ReactNode;
  className?: string;
  delay?: number;
  y?: number;
  once?: boolean;
  style?: CSSProperties;
}) {
  const reduce = useReducedMotion();
  return (
    <motion.div
      className={className}
      style={style}
      initial={reduce ? false : { opacity: 0, y, filter: 'blur(6px)' }}
      whileInView={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
      viewport={{ once, margin: '-12% 0px -8% 0px' }}
      transition={{ duration: 0.8, ease: EASE, delay }}
    >
      {children}
    </motion.div>
  );
}

/* ── Stagger: a container that cascades its direct StaggerItem children ───── */
const containerV: Variants = {
  hidden: {},
  show: { transition: { staggerChildren: 0.09, delayChildren: 0.05 } },
};
const itemV: Variants = {
  hidden: { opacity: 0, y: 22, filter: 'blur(6px)' },
  show: { opacity: 1, y: 0, filter: 'blur(0px)', transition: { duration: 0.75, ease: EASE } },
};

export function Stagger({
  children,
  className,
  once = true,
  style,
}: {
  children: ReactNode;
  className?: string;
  once?: boolean;
  style?: CSSProperties;
}) {
  const reduce = useReducedMotion();
  return (
    <motion.div
      className={className}
      style={style}
      variants={containerV}
      initial={reduce ? false : 'hidden'}
      whileInView="show"
      viewport={{ once, margin: '-10% 0px' }}
    >
      {children}
    </motion.div>
  );
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
  return (
    <motion.div className={className} style={style} variants={itemV}>
      {children}
    </motion.div>
  );
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
      `radial-gradient(340px circle at ${x} ${y}, rgba(110,231,212,.16), transparent 60%)`,
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

/* ── ScrollProgress: a hairline neon bar tracking page scroll ─────────────── */
export function ScrollProgress() {
  const reduce = useReducedMotion();
  const { scrollYProgress } = useScroll();
  const scaleX = useSpring(scrollYProgress, { stiffness: 120, damping: 30, mass: 0.4 });
  if (reduce) return null;
  return (
    <motion.div
      aria-hidden
      className="absolute inset-x-0 bottom-0 z-50 h-px origin-left bg-gradient-to-r from-teal via-teal-light to-gold"
      style={{ scaleX, boxShadow: '0 0 12px rgba(110,231,212,.55)' }}
    />
  );
}
