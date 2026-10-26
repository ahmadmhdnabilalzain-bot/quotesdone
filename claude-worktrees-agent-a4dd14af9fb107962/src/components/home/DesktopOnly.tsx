'use client';

// Mounts `children` only on a desktop-width viewport; everywhere else, and on the server, renders
// `fallback`. The hero's scene slot probes WebGL and registers its gate on mount even when its
// container is display:none, so on a phone — where the scene can never show — that work sat in the
// hydration window (Lighthouse mobile, 14 Sep 2026: TBT 510–640 ms on /). The server-rendered
// fallback is the scene's own poster, so desktop still paints the slabs at first paint.
import { useEffect, useState, type ReactNode } from 'react';

const DESKTOP = '(min-width: 1024px)';

export function DesktopOnly({ children, fallback }: { children: ReactNode; fallback: ReactNode }) {
  const [desktop, setDesktop] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia(DESKTOP);
    const on = () => setDesktop(mq.matches);
    on();
    mq.addEventListener('change', on);
    return () => mq.removeEventListener('change', on);
  }, []);
  return <>{desktop ? children : fallback}</>;
}
