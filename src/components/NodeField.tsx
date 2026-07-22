'use client';
import { useEffect, useRef } from 'react';

/**
 * THE NODE FIELD — the signature background primitive.
 * Suppliers as anonymous points of light: the engine does not list them,
 * it illuminates them. Purely decorative, aria-hidden, fully gated on
 * prefers-reduced-motion.
 *
 * Perf notes (learned the hard way):
 *  · DPR pinned to 1: this is decoration, retina is indistinguishable here.
 *  · Desktop ~30fps with a constellation + a radial falloff painted INTO the
 *    canvas — a CSS mask on a fixed full-viewport layer re-blends every frame,
 *    so the falloff is a single destination-in composite instead.
 *  · MOBILE is a different budget. That per-frame destination-in fillRect reads
 *    back and re-blends the WHOLE surface every frame, and the O(n²) constellation
 *    stroke adds hundreds of path ops — together they make phones stutter. On
 *    phones we drop BOTH: no lines, no composite. The same radial falloff is baked
 *    into each dot's alpha (O(n), not O(pixels)), the loop runs at ~24fps, there is
 *    no pointer-parallax (phones have no hover), and resize ignores height-only
 *    changes so the address bar collapsing mid-scroll can't re-init the canvas.
 */
export function NodeField() {
  const ref = useRef<HTMLCanvasElement | null>(null);
  useEffect(() => {
    const c = ref.current;
    if (!c || !c.getContext) return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const ctx = c.getContext('2d');
    if (!ctx) return;

    const rtl = document.documentElement.dir === 'rtl';
    const mob = window.innerWidth < 760;
    const minDelta = mob ? 42 : 32;            // ~24fps on phones, ~30fps on desktop
    let W = 0, H = 0, live = true, last = 0, raf = 0, lastW = 0;
    let mx = 0, my = 0, tmx = 0, tmy = 0, sk = 0;
    const N = mob ? 40 : 130;
    type Node = { x: number; y: number; z: number; vx: number; vy: number };
    let nodes: Node[] = [];
    let fade: CanvasGradient | null = null, fw = 0, fh = 0;

    const size = () => {
      W = c.clientWidth; H = c.clientHeight;
      c.width = W; c.height = H; fade = null; lastW = window.innerWidth;
    };
    const make = () => {
      nodes = Array.from({ length: N }, () => ({
        x: Math.random() * 2 - 1, y: Math.random() * 2 - 1,
        z: 0.18 + Math.random() * 0.82,
        vx: (Math.random() - 0.5) * 3e-4, vy: (Math.random() - 0.5) * 2.2e-4,
      }));
    };
    size(); make();

    // On phones the address bar collapsing during scroll fires resize with only a
    // height change; re-initialising the canvas mid-scroll is a visible stutter.
    // Re-size only when the WIDTH actually changes (orientation / a real resize).
    const onResize = () => { if (!mob || window.innerWidth !== lastW) size(); };
    const onScroll = () => { sk = Math.min(1, window.scrollY / (window.innerHeight * 0.9)); };
    let queued = false;
    const onMove = (e: PointerEvent) => {
      tmx = e.clientX / window.innerWidth - 0.5;
      tmy = e.clientY / window.innerHeight - 0.5;
      if (queued) return; queued = true;
      requestAnimationFrame(() => { queued = false; });
    };
    addEventListener('resize', onResize, { passive: true });
    addEventListener('scroll', onScroll, { passive: true });
    if (!mob) addEventListener('pointermove', onMove, { passive: true });
    const onVis = () => { live = !document.hidden; };
    document.addEventListener('visibilitychange', onVis);

    const frame = (ts: number) => {
      raf = requestAnimationFrame(frame);
      if (!live) return;
      if (ts - last < minDelta) return;
      last = ts;

      if (!mob) { mx += (tmx - mx) * 0.045; my += (tmy - my) * 0.045; }
      ctx.clearRect(0, 0, W, H);

      const cx = rtl ? W * 0.42 : W * 0.58, cy = H * 0.48;
      const dim = 1 - sk * 0.82;
      const gx = rtl ? W * 0.24 : W * 0.76, gy = H * 0.14;   // the light source
      const pts: { x: number; y: number; r: number; z: number }[] = [];
      for (const n of nodes) {
        n.x += n.vx; n.y += n.vy;
        if (n.x > 1.1) n.x = -1.1; if (n.x < -1.1) n.x = 1.1;
        if (n.y > 1.1) n.y = -1.1; if (n.y < -1.1) n.y = 1.1;
        const par = 1.15 - n.z;
        pts.push({
          x: cx + n.x * W * 0.6 + mx * 58 * par,
          y: cy + n.y * H * 0.64 + my * 44 * par - sk * 130 * par,
          r: par * 3.1 + 1.35, z: n.z,
        });
      }

      // ── Mobile: dots only, falloff baked per-dot. No lines, no composite. ──
      if (mob) {
        const R = Math.max(W, H) * 1.05 * 0.84;   // 0 alpha at the gradient's .84 stop
        for (const q of pts) {
          const d = Math.hypot(q.x - gx, q.y - gy) / R;
          if (d >= 1) continue;                    // outside the light — skip entirely
          const fo = (1 - d) * (1 - d);            // soft, matches the radial curve
          ctx.fillStyle = `rgba(150,201,214,${((0.2 + (1.15 - q.z) * 0.55) * dim * fo).toFixed(3)})`;
          ctx.beginPath(); ctx.arc(q.x, q.y, q.r, 0, 6.283); ctx.fill();
        }
        return;
      }

      // ── Desktop: constellation + dots + one composite falloff. ──
      if (!fade || fw !== W || fh !== H) {
        const g = ctx.createRadialGradient(gx, gy, 0, gx, gy, Math.max(W, H) * 1.05);
        g.addColorStop(0, 'rgba(255,255,255,1)');
        g.addColorStop(0.34, 'rgba(255,255,255,.72)');
        g.addColorStop(0.62, 'rgba(255,255,255,.24)');
        g.addColorStop(0.84, 'rgba(255,255,255,0)');
        fade = g; fw = W; fh = H;
      }

      // constellation: what makes it read as a connected field, not dust
      ctx.lineWidth = 0.5;
      ctx.strokeStyle = `rgba(126,186,201,${(0.085 * dim).toFixed(3)})`;
      ctx.beginPath();
      for (let a = 0; a < pts.length; a++) {
        for (let b = a + 1; b < pts.length; b++) {
          const dx = pts[a].x - pts[b].x; if (dx > 132 || dx < -132) continue;
          const dy = pts[a].y - pts[b].y; if (dy > 132 || dy < -132) continue;
          if (dx * dx + dy * dy > 17400) continue;
          ctx.moveTo(pts[a].x, pts[a].y); ctx.lineTo(pts[b].x, pts[b].y);
        }
      }
      ctx.stroke();

      for (const q of pts) {
        ctx.fillStyle = `rgba(150,201,214,${((0.2 + (1.15 - q.z) * 0.55) * dim).toFixed(3)})`;
        ctx.beginPath(); ctx.arc(q.x, q.y, q.r, 0, 6.283); ctx.fill();
      }

      // one composite applies the falloff a CSS mask used to do
      ctx.globalCompositeOperation = 'destination-in';
      ctx.fillStyle = fade;
      ctx.fillRect(0, 0, W, H);
      ctx.globalCompositeOperation = 'source-over';
    };
    // Paint one frame synchronously before handing off to rAF. A throttled or
    // backgrounded tab never runs rAF, so without this the field can ship blank
    // — and it also makes the canvas verifiable in a headless/hidden context.
    frame(performance.now() + 1000);
    raf = requestAnimationFrame(frame);

    return () => {
      cancelAnimationFrame(raf);
      removeEventListener('resize', onResize);
      removeEventListener('scroll', onScroll);
      if (!mob) removeEventListener('pointermove', onMove);
      document.removeEventListener('visibilitychange', onVis);
    };
  }, []);

  return <canvas ref={ref} id="qd-field" aria-hidden="true" />;
}
