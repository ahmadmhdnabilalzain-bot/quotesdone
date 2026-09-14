'use client';
import { useEffect, useRef } from 'react';

/**
 * A hairline neon bar tracking page scroll. It was motion/react useScroll + useSpring, which put the
 * motion runtime in the first load of every page through SiteHeader. One passive scroll listener
 * writing a transform does the same job without a library; the spring's easing is replaced by a
 * short CSS transition. Hidden entirely under prefers-reduced-motion, as before.
 */
export function ScrollProgress() {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let raf = 0;
    const paint = () => {
      raf = 0;
      const max = document.documentElement.scrollHeight - window.innerHeight;
      el.style.transform = `scaleX(${max > 0 ? Math.min(1, window.scrollY / max) : 0})`;
    };
    const onScroll = () => { if (!raf) raf = requestAnimationFrame(paint); };
    paint();
    addEventListener('scroll', onScroll, { passive: true });
    addEventListener('resize', onScroll, { passive: true });
    return () => {
      cancelAnimationFrame(raf);
      removeEventListener('scroll', onScroll);
      removeEventListener('resize', onScroll);
    };
  }, []);
  return (
    <div
      ref={ref}
      aria-hidden
      className="absolute inset-x-0 bottom-[-1px] z-50 h-0.5 origin-left bg-gradient-to-r from-teal via-teal-light to-gold transition-transform duration-150 ease-out motion-reduce:hidden rtl:origin-right"
      style={{ transform: 'scaleX(0)', boxShadow: '0 0 16px rgba(110,231,212,.7)' }}
    />
  );
}
