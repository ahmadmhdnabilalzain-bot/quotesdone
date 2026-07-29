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
 *  · Desktop ~36fps with a constellation + a radial falloff painted INTO the
 *    canvas — a CSS mask on a fixed full-viewport layer re-blends every frame,
 *    so the falloff is a single destination-in composite instead.
 *  · The pointer is a first-class light: nearby nodes brighten and thread
 *    connection lines to the cursor, so the field reacts to the visitor.
 *  · MOBILE is a different budget. That per-frame destination-in fillRect reads
 *    back and re-blends the WHOLE surface every frame, and the O(n²) constellation
 *    stroke adds hundreds of path ops — together they make phones stutter. On
 *    phones we drop BOTH: no lines, no composite. The same radial falloff is baked
 *    into each dot's alpha (O(n), not O(pixels)), the loop runs at ~24fps. Touch
 *    gently steers the light source (one cheap lerp), but there is no per-node
 *    pointer math, and resize ignores height-only changes so the address bar
 *    collapsing mid-scroll can't re-init the canvas.
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
    const minDelta = mob ? 42 : 28;            // ~24fps on phones, ~36fps on desktop
    let W = 0, H = 0, live = true, last = 0, raf = 0, lastW = 0;
    let mx = 0, my = 0, tmx = 0, tmy = 0, sk = 0;
    // Pointer in pixel space (for the interactive light). -1 => no pointer yet.
    let ptx = -1, pty = -1, cptx = -1, cpty = -1, pOn = 0, tpOn = 0;
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
      ptx = e.clientX; pty = e.clientY; tpOn = 1;
      if (queued) return; queued = true;
      requestAnimationFrame(() => { queued = false; });
    };
    const onLeave = () => { tpOn = 0; };
    // Touch: steer the light source on phones (cheap — just updates targets).
    const onTouch = (e: TouchEvent) => {
      const t = e.touches[0]; if (!t) return;
      tmx = t.clientX / window.innerWidth - 0.5;
      tmy = t.clientY / window.innerHeight - 0.5;
      ptx = t.clientX; pty = t.clientY; tpOn = 1;
    };
    addEventListener('resize', onResize, { passive: true });
    addEventListener('scroll', onScroll, { passive: true });
    if (!mob) {
      addEventListener('pointermove', onMove, { passive: true });
      addEventListener('pointerleave', onLeave, { passive: true });
    } else {
      addEventListener('touchmove', onTouch, { passive: true });
      addEventListener('touchstart', onTouch, { passive: true });
    }
    const onVis = () => { live = !document.hidden; };
    document.addEventListener('visibilitychange', onVis);

    const frame = (ts: number) => {
      raf = requestAnimationFrame(frame);
      if (!live) return;
      if (ts - last < minDelta) return;
      last = ts;

      if (!mob) { mx += (tmx - mx) * 0.045; my += (tmy - my) * 0.045; }
      // Smooth the interactive light toward the pointer and fade its influence.
      pOn += (tpOn - pOn) * 0.06;
      if (cptx < 0 && ptx >= 0) { cptx = ptx; cpty = pty; }
      if (ptx >= 0) { cptx += (ptx - cptx) * 0.12; cpty += (pty - cpty) * 0.12; }
      ctx.clearRect(0, 0, W, H);

      const cx = rtl ? W * 0.42 : W * 0.58, cy = H * 0.48;
      const dim = 1 - sk * 0.82;
      // On mobile, the light source itself drifts toward the last touch.
      const baseGx = rtl ? W * 0.24 : W * 0.76, baseGy = H * 0.14;
      const gx = mob && cptx >= 0 ? baseGx + (cptx - baseGx) * 0.5 * pOn : baseGx;
      const gy = mob && cpty >= 0 ? baseGy + (cpty - baseGy) * 0.5 * pOn : baseGy;
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

      // ── Desktop: constellation + dots + cursor light + one composite falloff. ──
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

      // ── Cursor light: thread bright teal lines to nearby nodes and pull them ──
      // toward the pointer, so the field visibly reacts to the visitor.
      const infl = pOn * dim;
      if (cptx >= 0 && infl > 0.02) {
        const RR = 168, RR2 = RR * RR;
        ctx.lineWidth = 0.85;
        for (const q of pts) {
          const dx = q.x - cptx, dy = q.y - cpty;
          const d2 = dx * dx + dy * dy;
          if (d2 > RR2) continue;
          const t = 1 - Math.sqrt(d2) / RR;             // 0..1, nearer = stronger
          ctx.strokeStyle = `rgba(110,231,212,${(0.5 * t * t * infl).toFixed(3)})`;
          ctx.beginPath(); ctx.moveTo(cptx, cpty); ctx.lineTo(q.x, q.y); ctx.stroke();
          // brighten the node itself
          ctx.fillStyle = `rgba(180,245,235,${(0.7 * t * infl).toFixed(3)})`;
          ctx.beginPath(); ctx.arc(q.x, q.y, q.r + t * 1.3, 0, 6.283); ctx.fill();
        }
        // a soft glow core at the pointer
        const cg = ctx.createRadialGradient(cptx, cpty, 0, cptx, cpty, 90);
        cg.addColorStop(0, `rgba(110,231,212,${(0.16 * infl).toFixed(3)})`);
        cg.addColorStop(1, 'rgba(110,231,212,0)');
        ctx.fillStyle = cg;
        ctx.beginPath(); ctx.arc(cptx, cpty, 90, 0, 6.283); ctx.fill();
      }

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
      if (!mob) {
        removeEventListener('pointermove', onMove);
        removeEventListener('pointerleave', onLeave);
      } else {
        removeEventListener('touchmove', onTouch);
        removeEventListener('touchstart', onTouch);
      }
      document.removeEventListener('visibilitychange', onVis);
    };
  }, []);

  return <canvas ref={ref} id="qd-field" aria-hidden="true" />;
}
