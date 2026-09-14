'use client';
/**
 * The five visual slots of the public site. Every scene sizes to its parent — give the parent a
 * height (e.g. aspect-[16/10]).
 *
 *   HeroScene         3D (three/r3f): anonymous quote panels orbit, level, one is chosen and its
 *                     redaction bar slides away. Pointer parallax. Hero backdrop — mount it BEHIND
 *                     the headline (absolute inset-0, -z) so LCP stays text, never the canvas.
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
 *
 * THE IMPORT WAITS FOR THE GATE (website audit 14 Sep 2026). These were bare next/dynamic wrappers.
 * next/dynamic starts the import() the moment the wrapper renders on the client, so the gate inside
 * each scene decided when the canvas MOUNTED but not when its code DOWNLOADED and EVALUATED. Measured
 * on a local `next build` + Lighthouse 12 mobile: three.js arrived in the first load of / in two
 * chunks (174 KB + 51 KB, ~1.0 s of script evaluation), plus a 100 KB scene chunk nothing had yet
 * used. Each slot now renders its poster and runs the same useSceneGate itself; only when the gate
 * opens (in viewport + browser idle) does it render the dynamic component, which is when the chunk
 * is requested. HeroScene also checks canRun3D() first, so a device that would only ever show the
 * poster never downloads three at all.
 */
import dynamic from 'next/dynamic';
import { useRef, useState, useEffect, type ComponentType } from 'react';
import { HeroPoster, MapPoster, SheetPoster } from './posters';
import { canRun3D, useSceneGate, type SceneProps } from './gate';
import { onFirstInteraction } from '@/lib/firstInteraction';

// Viewport + idle alone was not enough: the hero is always in view and a loading page goes idle
// within ~1.5 s, so the gate still opened inside the first-load window. Measured locally with
// Lighthouse 12 mobile once the import waited for the gate: three + r3f (~390 KB across six chunks)
// were requested at 1.3–2.6 s and TBT on / was 2,630 ms. The scene now also waits for the visitor's
// first scroll, touch, pointer move or key press (src/lib/firstInteraction.ts); until then the
// poster (the scene's final frame) is what shows.
function gated(Scene: ComponentType<SceneProps>, Poster: ComponentType<SceneProps>, needs3D = false) {
  return function Slot(props: SceneProps) {
    const ref = useRef<HTMLDivElement>(null);
    const { mounted } = useSceneGate(ref);
    const [capable, setCapable] = useState(!needs3D);
    const [awake, setAwake] = useState(false);
    useEffect(() => { if (needs3D) setCapable(canRun3D()); }, []);
    useEffect(() => onFirstInteraction(() => setAwake(true)), []);
    if (mounted && capable && awake) return <Scene {...props} />;
    return <div ref={ref} className="h-full w-full"><Poster {...props} /></div>;
  };
}

const hero = () => <HeroPoster />;
const sheet = () => <SheetPoster />;
const map = ({ locale }: SceneProps) => <MapPoster locale={locale} />;

export const HeroScene = gated(dynamic(() => import('./HeroScene'), { ssr: false, loading: hero }), hero, true);
export const EmiratesMap = gated(dynamic(() => import('./EmiratesMap'), { ssr: false, loading: () => <MapPoster locale="en" /> }), map);
export const DrawingScan = gated(dynamic(() => import('./DrawingScan'), { ssr: false, loading: sheet }), sheet);
export const CompareLevelling = gated(dynamic(() => import('./CompareLevelling'), { ssr: false, loading: sheet }), sheet);
export const AnonymityFlow = gated(dynamic(() => import('./AnonymityFlow'), { ssr: false, loading: sheet }), sheet);
