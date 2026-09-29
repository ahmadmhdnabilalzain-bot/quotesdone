'use client';
// Portal cold-load cut (28 Sep 2026): the /me components animate through `m.*` instead of `motion.*`,
// so the first-load bundle carries only motion's thin render shell; the animation features arrive in a
// separate chunk after the portal is on screen (motion's documented LazyMotion pattern). An `m.*`
// element outside a MotionRoot renders without animating, so every tree that uses `m` sits inside one.
import { LazyMotion } from 'motion/react';
import type { ReactNode } from 'react';
const loadFeatures = () => import('./motionFeatures').then((mod) => mod.default);
export function MotionRoot({ children }: { children: ReactNode }) {
  return <LazyMotion features={loadFeatures}>{children}</LazyMotion>;
}
