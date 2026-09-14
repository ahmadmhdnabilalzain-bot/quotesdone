'use client';
/**
 * The five visual slots of the public site. Each export is a next/dynamic wrapper (ssr:false), so
 * none of the scene code is in any page's First Load JS; the page ships only the static poster
 * from ./posters. Every scene sizes to its parent — give the parent a height (e.g. aspect-[16/10]).
 *
 *   HeroScene         3D (three/r3f): anonymous quote panels orbit, level, one is chosen and its
 *                     redaction bar slides away. Pointer parallax. Hero backdrop — mount it BEHIND
 *                     the headline (absolute inset-0, -z) so LCP stays the <h1>, never the canvas.
 *   EmiratesMap       2.5D dotted map of the seven emirates, decorative pulses, names in EN/AR.
 *   DrawingScan       an authored floor-plan sheet is scanned; the title block's contact fields
 *                     are blacked out; BOQ rows assemble beside it. Labelled as a demonstration.
 *   CompareLevelling  three anonymous quotes level into one table: missing-item flag, best-match
 *                     reason. Prices are redaction bars, never figures. Labelled a demonstration.
 *   AnonymityFlow     customer <-> platform <-> suppliers, identities masked until the reveal.
 *
 * All take { locale: 'en' | 'ar' }. Rules enforced in ./gate: mount on viewport + idle, pause
 * off-screen / hidden tab, prefers-reduced-motion = poster only, no WebGL or <=4 cores = poster
 * (HeroScene only; the SVG scenes are cheap). Decorative layers are aria-hidden and every scene
 * carries a visually-hidden text alternative.
 */
import dynamic from 'next/dynamic';
import { HeroPoster, MapPoster, SheetPoster } from './posters';

export const HeroScene = dynamic(() => import('./HeroScene'), { ssr: false, loading: () => <HeroPoster /> });
export const EmiratesMap = dynamic(() => import('./EmiratesMap'), { ssr: false, loading: () => <MapPoster locale="en" /> });
export const DrawingScan = dynamic(() => import('./DrawingScan'), { ssr: false, loading: () => <SheetPoster /> });
export const CompareLevelling = dynamic(() => import('./CompareLevelling'), { ssr: false, loading: () => <SheetPoster /> });
export const AnonymityFlow = dynamic(() => import('./AnonymityFlow'), { ssr: false, loading: () => <SheetPoster /> });
