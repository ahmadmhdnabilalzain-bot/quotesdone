'use client';
import { useEffect } from 'react';

// THE ONLY CLIENT CODE ON /faq (WEB-12). Measured 22 Sep 2026 (Lighthouse 12 mobile, /ar/faq): the
// whole page was one client component, so all 150 answers — 312 KB of markup — were serialised into
// the RSC payload AND re-created as React elements in the browser: 2,020 ms total blocking time. The
// answers are plain <details> and need no JavaScript at all; only the filter box does. This component
// renders nothing and attaches that filter to the ids the content already carries (#q, #nm).
export function FaqSearch() {
  useEffect(() => {
    const q = document.getElementById('q') as HTMLInputElement | null;
    const nm = document.getElementById('nm') as HTMLElement | null;
    if (!q) return;
    const items = Array.from(document.querySelectorAll('details.qa')) as HTMLElement[];
    const secs = Array.from(document.querySelectorAll('.sec')) as HTMLElement[];
    const run = () => {
      const t = q.value.trim().toLowerCase();
      let any = false;
      items.forEach((el) => {
        const show = !t || (el.textContent || '').toLowerCase().includes(t);
        el.style.display = show ? '' : 'none';
        if (show) any = true;
        (el as HTMLDetailsElement).open = !!(t && show);
      });
      secs.forEach((s) => { const vis = Array.from(s.querySelectorAll('details.qa')).some((el: any) => el.style.display !== 'none'); s.style.display = vis ? '' : 'none'; });
      if (nm) nm.style.display = any ? 'none' : 'block';
    };
    q.addEventListener('input', run); run();
    return () => q.removeEventListener('input', run);
  }, []);
  return null;
}
