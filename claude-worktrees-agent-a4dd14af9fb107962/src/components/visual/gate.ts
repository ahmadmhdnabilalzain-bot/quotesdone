'use client';
// Shared mount gate for every scene in src/components/visual/**. One place decides whether a
// scene may animate, so the five scenes cannot drift apart on the performance/a11y rules:
//   - mount only once the host has entered the viewport AND the browser is idle,
//   - pause while off-screen or while the tab is hidden,
//   - never animate under prefers-reduced-motion,
//   - WebGL scenes fall back to their poster when WebGL is missing or the device is low-power.
import { useEffect, useState, type RefObject } from 'react';

export type Locale = 'en' | 'ar';
export type SceneProps = { locale: Locale };

const idle = (cb: () => void) => {
  const w = window as Window & { requestIdleCallback?: (cb: () => void, o?: { timeout: number }) => number };
  if (w.requestIdleCallback) w.requestIdleCallback(cb, { timeout: 1500 });
  else setTimeout(cb, 200);
};

export function prefersReducedMotion() {
  return typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

/** WebGL available and the device is not low-power (≤4 logical cores or save-data). */
export function canRun3D() {
  if (typeof window === 'undefined') return false;
  const nav = navigator as Navigator & { connection?: { saveData?: boolean } };
  if ((nav.hardwareConcurrency ?? 8) <= 4 || nav.connection?.saveData) return false;
  try {
    const c = document.createElement('canvas');
    return !!(c.getContext('webgl2') || c.getContext('webgl'));
  } catch {
    return false;
  }
}

/**
 * `mounted`: the host has been seen and the browser went idle once — mount the heavy scene.
 * `active`:  it is visible right now and the tab is showing — animate; otherwise pause.
 * Both stay false forever under prefers-reduced-motion, so only the poster ever renders.
 */
export function useSceneGate(ref: RefObject<HTMLElement | null>) {
  const [mounted, setMounted] = useState(false);
  const [inView, setInView] = useState(false);
  const [tabVisible, setTabVisible] = useState(true);

  useEffect(() => {
    const el = ref.current;
    if (!el || prefersReducedMotion()) return;
    const io = new IntersectionObserver(
      ([e]) => {
        setInView(e.isIntersecting);
        if (e.isIntersecting) idle(() => setMounted(true));
      },
      { rootMargin: '200px 0px' },
    );
    io.observe(el);
    const onVis = () => setTabVisible(document.visibilityState === 'visible');
    document.addEventListener('visibilitychange', onVis);
    return () => {
      io.disconnect();
      document.removeEventListener('visibilitychange', onVis);
    };
  }, [ref]);

  return { mounted, active: mounted && inView && tabVisible };
}
