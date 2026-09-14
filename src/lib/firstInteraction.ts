/**
 * Run `cb` on the visitor's first scroll, touch, pointer move/press or key press — once per page
 * load, one shared set of listeners however many callers subscribe. Returns an unsubscribe.
 *
 * WHY THIS EXISTS (website audit 14 Sep 2026). Decoration that starts on mount — the 3D hero, the
 * NodeField canvas loop, the LiveMatch replay — does its work inside the first-load window, where it
 * blocks the main thread while the page is still becoming usable. Measured locally (next build +
 * Lighthouse 12 mobile, / ): with those three starting on mount or on viewport+idle, TBT was 580 ms
 * and the hero subtitle's LCP carried 3.3 s of render delay behind the hydration task. Each of them
 * already renders a complete static frame first (poster, one painted canvas frame, the ranked final
 * frame), so waiting for the first interaction changes what moves, never what is shown.
 */
const EVENTS = ['scroll', 'pointermove', 'pointerdown', 'touchstart', 'keydown'] as const;
let woken = false;
const waiting = new Set<() => void>();

function wake() {
  woken = true;
  // CSS hook: globals.css holds the ambient animations on their first frame until this class is set.
  // NodeField (root layout, every page) always subscribes, so the listeners exist on every page.
  document.documentElement.classList.add('qd-awake');
  EVENTS.forEach((e) => removeEventListener(e, wake));
  waiting.forEach((f) => f());
  waiting.clear();
}

export function onFirstInteraction(cb: () => void): () => void {
  if (woken) { cb(); return () => {}; }
  if (!waiting.size) EVENTS.forEach((e) => addEventListener(e, wake, { passive: true }));
  waiting.add(cb);
  return () => { waiting.delete(cb); };
}
