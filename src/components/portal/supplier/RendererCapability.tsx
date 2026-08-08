'use client';
// ROW #5 §5 §23 — WHAT CAN THIS DEVICE ACTUALLY DRAW?
//
// The 3D environment assumes a GPU. A supplier opening the portal on a locked-down site laptop, an
// old Android tablet in a fabrication shop, or a browser with hardware acceleration switched off
// gets a black rectangle and no explanation — and the honest reading of that is "the portal is
// broken", because nothing on screen says otherwise.
//
// This asks the browser directly and says what it found. It is the same rule the rest of row #5
// follows: absent is not empty, and an absent capability carries its reason.
//
//   WebGPU  — navigator.gpu, the modern path. Three r180 can drive it via WebGPURenderer.
//   WebGL2  — what <Canvas> actually uses today.
//   WebGL1  — degraded but drawable.
//   none    — hardware acceleration is off or blocked. Say so, and say what to do about it.
import React, { useEffect, useState } from 'react';

export type Renderer = 'webgpu' | 'webgl2' | 'webgl' | 'none' | 'checking';

// Probed once, on a throwaway canvas that is never attached to the document. Creating a context to
// test for one leaks it, so the extension that frees it is asked for explicitly — sixteen live
// contexts is the browser's usual ceiling and the 3D scene needs one of them.
export function detectRenderer(): Exclude<Renderer, 'checking' | 'webgpu'> {
  if (typeof document === 'undefined') return 'none';
  const canvas = document.createElement('canvas');
  for (const [kind, id] of [['webgl2', 'webgl2'], ['webgl', 'webgl']] as const) {
    let ctx: RenderingContext | null = null;
    try { ctx = canvas.getContext(id); } catch { ctx = null; }
    if (ctx) {
      try { (ctx as WebGLRenderingContext).getExtension('WEBGL_lose_context')?.loseContext(); } catch { /* nothing to free */ }
      return kind;
    }
  }
  return 'none';
}

export function useRenderer(): Renderer {
  const [r, setR] = useState<Renderer>('checking');
  useEffect(() => {
    let cancelled = false;
    // navigator.gpu can exist while requestAdapter() still returns null — a browser that knows the
    // WebGPU API and has no adapter to give. Presence of the object is not the capability.
    const gpu = (navigator as Navigator & { gpu?: { requestAdapter(): Promise<unknown> } }).gpu;
    if (gpu?.requestAdapter) {
      gpu.requestAdapter()
        .then((a) => { if (!cancelled) setR(a ? 'webgpu' : detectRenderer()); })
        .catch(() => { if (!cancelled) setR(detectRenderer()); });
    } else if (!cancelled) setR(detectRenderer());
    return () => { cancelled = true; };
  }, []);
  return r;
}

const COPY: Record<string, { en: string; ar: string }> = {
  webgpu: { en: 'WebGPU — full detail', ar: 'WebGPU — أعلى جودة' },
  webgl2: { en: 'WebGL 2', ar: 'WebGL 2' },
  webgl: { en: 'WebGL 1 — reduced detail on this device', ar: 'WebGL 1 — تفاصيل أقل على هذا الجهاز' },
  checking: { en: 'checking your device…', ar: 'جارٍ فحص جهازك…' },
  none: {
    en: 'This device cannot draw 3D. Turn on hardware acceleration in your browser settings, or open the portal on another device — every number here is also on the Insight Board and the Digital Twin.',
    ar: 'هذا الجهاز لا يدعم الرسم ثلاثي الأبعاد. فعّل تسريع العتاد في إعدادات المتصفح أو استخدم جهازًا آخر — كل الأرقام متاحة أيضًا في لوحة الرؤى والتوأم الرقمي.',
  },
};

export default function RendererCapability({ lang = 'en' }: { lang?: 'en' | 'ar' }) {
  const r = useRenderer();
  const c = COPY[r] || COPY.checking;
  if (r === 'none') {
    return (
      <p className="qd-panel p-4 text-[13px] leading-[1.7] text-muted-foreground" role="status">
        {c[lang] || c.en}
      </p>
    );
  }
  return <p className="text-[11px] text-muted-foreground" role="status">{c[lang] || c.en}</p>;
}
