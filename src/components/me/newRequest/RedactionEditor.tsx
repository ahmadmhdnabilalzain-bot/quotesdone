// @ts-nocheck
'use client';
import { useRef, useState } from 'react';
import * as M from 'motion/react-m';
import { ChevronLeft, ChevronRight, Eraser } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { t, tf } from '../portalText';
import { countPhrase } from '@/lib/countedNoun';

// THE CUSTOMER-DRAWN REDACTION. Boxes are stored normalised to the page (0..1), so they mean the
// same thing at the 1600px width drawing_redact works at as they do on this screen.
export function RedactionEditor({ lang, images, onApply, onSkip, reduce }) {
  const [page, setPage] = useState(0);
  const [boxes, setBoxes] = useState(() => images.map(() => []));
  const [drag, setDrag] = useState(null);
  const [busy, setBusy] = useState(false);
  const surf = useRef(null);
  const pt = (e) => { const r = surf.current.getBoundingClientRect(); return { x: Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)), y: Math.min(1, Math.max(0, (e.clientY - r.top) / r.height)) }; };
  const down = (e) => { e.preventDefault(); try { e.currentTarget.setPointerCapture(e.pointerId); } catch (_e) {} const p = pt(e); setDrag({ x0: p.x, y0: p.y, x1: p.x, y1: p.y }); };
  const move = (e) => { if (!drag) return; const p = pt(e); setDrag((d) => ({ ...d, x1: p.x, y1: p.y })); };
  const up = () => {
    if (!drag) return;
    const b = { x: Math.min(drag.x0, drag.x1), y: Math.min(drag.y0, drag.y1), w: Math.abs(drag.x1 - drag.x0), h: Math.abs(drag.y1 - drag.y0) };
    if (b.w > 0.005 && b.h > 0.005) setBoxes((all) => all.map((l, i) => (i === page ? [...l, b] : l)));
    setDrag(null);
  };
  const total = boxes.reduce((n, l) => n + l.length, 0);
  const apply = async () => { setBusy(true); await onApply(boxes); setBusy(false); };
  const live = drag ? { x: Math.min(drag.x0, drag.x1), y: Math.min(drag.y0, drag.y1), w: Math.abs(drag.x1 - drag.x0), h: Math.abs(drag.y1 - drag.y0) } : null;
  const pct = (v) => (v * 100) + '%';
  return (
    <M.div initial={reduce ? false : { opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} className="rounded-2xl border border-primary/35 bg-card/70 p-3.5">
      <h3 className="text-[13.5px] font-bold text-foreground">{t(lang, 'rd_title')}</h3>
      <p className="mt-0.5 text-[12.5px] leading-relaxed text-muted-foreground">{t(lang, 'rd_body')}</p>
      <div className="mt-2.5 flex items-center justify-between gap-2 text-[12px] text-muted-foreground" dir="ltr">
        <button type="button" className="grid h-8 w-8 place-items-center rounded-lg border border-border disabled:opacity-40" disabled={page === 0} onClick={() => setPage((p) => p - 1)} aria-label={t(lang, 'rd_prev')}><ChevronLeft className="h-4 w-4" aria-hidden /></button>
        <span>{tf(lang, 'rd_page', { n: page + 1, total: images.length })} · {tf(lang, 'rd_boxes', { n: total, c: countPhrase(lang, total, 'area') })}</span>
        <button type="button" className="grid h-8 w-8 place-items-center rounded-lg border border-border disabled:opacity-40" disabled={page >= images.length - 1} onClick={() => setPage((p) => p + 1)} aria-label={t(lang, 'rd_next')}><ChevronRight className="h-4 w-4" aria-hidden /></button>
      </div>
      <div ref={surf} className="relative mt-2 cursor-crosshair touch-none select-none overflow-hidden rounded-lg border border-border bg-white" dir="ltr"
        role="img" aria-label={tf(lang, 'rd_canvas', { n: page + 1 })}
        onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerLeave={up}>
        <img src={'data:' + images[page].mime + ';base64,' + images[page].data} alt="" draggable={false} className="block h-auto w-full" />
        {boxes[page].map((b, i) => <span key={i} className="redact absolute rounded-[1px]! bg-black/90!" style={{ left: pct(b.x), top: pct(b.y), width: pct(b.w), height: pct(b.h) }} />)}
        {live ? <span className="absolute border-2 border-dashed border-primary bg-primary/20" style={{ left: pct(live.x), top: pct(live.y), width: pct(live.w), height: pct(live.h) }} /> : null}
      </div>
      <div className="mt-2.5 flex flex-wrap items-center gap-2">
        <Button size="sm" disabled={busy || total === 0} onClick={apply}>{busy ? t(lang, 'rd_applying') : t(lang, 'rd_apply')}</Button>
        <Button size="sm" variant="outline" disabled={busy || !boxes[page].length} onClick={() => setBoxes((all) => all.map((l, i) => (i === page ? [] : l)))}><Eraser className="me-1 h-3.5 w-3.5" aria-hidden />{t(lang, 'rd_clear')}</Button>
        <Button size="sm" variant="link" className="h-auto px-0" disabled={busy} onClick={onSkip}>{t(lang, 'rd_skip')}</Button>
      </div>
    </M.div>
  );
}
