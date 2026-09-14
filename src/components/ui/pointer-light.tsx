'use client';
import { useEffect } from 'react';

/**
 * One delegated pointer listener for the whole page (not one per control). It writes the pointer
 * position into the element under it so CSS can light and lean it:
 *   .qd-hoverlit / .qd-lit  →  --mx / --my  (px inside the element: the light follows the pointer)
 *   .qd-magnet              →  --px / --py  (-1..1 from centre: the control leans 3px toward it)
 * No React state and no re-render: a rAF-throttled style write. Nothing runs on touch-only devices
 * (no hover) and the lean is skipped under prefers-reduced-motion. Mount once per page tree.
 */
export function PointerLight() {
  useEffect(() => {
    if (!window.matchMedia('(hover: hover)').matches) return;
    const still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    let frame = 0;
    let last: PointerEvent | null = null;
    let magnet: HTMLElement | null = null;
    const apply = () => {
      frame = 0;
      const e = last;
      if (!e) return;
      const t = e.target as Element | null;
      const lit = t?.closest?.<HTMLElement>('.qd-hoverlit,.qd-lit');
      if (lit) {
        const r = lit.getBoundingClientRect();
        lit.style.setProperty('--mx', `${e.clientX - r.left}px`);
        lit.style.setProperty('--my', `${e.clientY - r.top}px`);
      }
      const m = still ? null : t?.closest?.<HTMLElement>('.qd-magnet') ?? null;
      if (magnet && magnet !== m) { magnet.style.setProperty('--px', '0'); magnet.style.setProperty('--py', '0'); }
      magnet = m;
      if (m) {
        const r = m.getBoundingClientRect();
        m.style.setProperty('--px', (((e.clientX - r.left) / r.width) * 2 - 1).toFixed(3));
        m.style.setProperty('--py', (((e.clientY - r.top) / r.height) * 2 - 1).toFixed(3));
      }
    };
    const onMove = (e: PointerEvent) => { last = e; if (!frame) frame = requestAnimationFrame(apply); };
    document.addEventListener('pointermove', onMove, { passive: true });
    return () => { document.removeEventListener('pointermove', onMove); cancelAnimationFrame(frame); };
  }, []);
  return null;
}
