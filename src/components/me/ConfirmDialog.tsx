// @ts-nocheck
'use client';
// AN IN-PAGE CONFIRM IN THE CUSTOMER'S LANGUAGE.
//
// Cancel request, request refund and "I hired this supplier" used window.confirm() — an
// English-only browser box on an Arabic page, unstyled, and the one moment the portal asks a
// customer to commit money or end a job (website audit 14 Sep 2026). useConfirm() returns the
// dialog element to render and an ask(text) that resolves true/false, so each call site reads the
// same as the confirm() it replaces.
import { useEffect, useRef, useState } from 'react';
import * as m from 'motion/react-m';
import { AnimatePresence, useReducedMotion } from 'motion/react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { t } from './portalText';

export function useConfirm(lang) {
  const [req, setReq] = useState(null);
  // opts.reveal marks the ONE confirm that unseals a supplier (the 3% reveal): its button is gold.
  const ask = (body, opts = {}) => new Promise((resolve) => setReq({ body, title: opts.title || '', confirm: opts.confirm || t(lang, 'dlg_confirm'), danger: !!opts.danger, reveal: !!opts.reveal, children: opts.children || null, resolve }));
  const close = (v) => { if (req) req.resolve(v); setReq(null); };
  const el = <ConfirmDialog lang={lang} req={req} onClose={close} />;
  return [el, ask];
}

function ConfirmDialog({ lang, req, onClose }) {
  const okRef = useRef(null);
  const reduce = useReducedMotion();
  useEffect(() => {
    if (!req) return;
    const prev = document.activeElement;
    setTimeout(() => okRef.current && okRef.current.focus(), 30);
    const onKey = (e) => { if (e.key === 'Escape') onClose(false); };
    document.addEventListener('keydown', onKey);
    return () => { document.removeEventListener('keydown', onKey); try { prev && prev.focus && prev.focus(); } catch (_e) {} };
  }, [req]);
  return (
    <AnimatePresence>
      {req && (
        <m.div className="fixed inset-0 z-[70] grid place-items-center overflow-y-auto bg-background/80 p-4"
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: reduce ? 0 : 0.16 }}
          onClick={() => onClose(false)} dir={lang === 'ar' ? 'rtl' : 'ltr'}>
          <m.div role="alertdialog" aria-modal="true" aria-labelledby="qd-confirm-title" aria-describedby="qd-confirm-body"
            className="qd-panel qd-grain my-auto w-full max-w-[480px] overflow-hidden p-0 text-foreground shadow-e3"
            initial={reduce ? false : { opacity: 0, y: 12, scale: 0.98 }} animate={{ opacity: 1, y: 0, scale: 1 }} exit={reduce ? { opacity: 0 } : { opacity: 0, y: 8, scale: 0.98 }}
            transition={{ duration: reduce ? 0 : 0.2, ease: [0.2, 0.8, 0.2, 1] }}
            onClick={(e) => e.stopPropagation()}>
            <div className={cn('h-px w-full', req.reveal ? 'bg-gradient-to-r from-transparent via-accent/70 to-transparent' : req.danger ? 'bg-gradient-to-r from-transparent via-danger/70 to-transparent' : 'bg-gradient-to-r from-transparent via-primary/70 to-transparent')} aria-hidden />
            <div className="p-5 sm:p-6">
              <h2 id="qd-confirm-title" className="font-head text-[18px] font-semibold tracking-snug">{req.title || t(lang, 'dlg_confirm')}</h2>
              <p id="qd-confirm-body" className="mt-2 text-copy leading-relaxed text-muted-foreground">{req.body}</p>
              {req.children ? <div className="mt-4">{req.children}</div> : null}
            </div>
            <div className="flex flex-wrap justify-end gap-2 border-t border-border bg-secondary/25 px-5 py-3.5 sm:px-6">
              <Button variant="ghost" onClick={() => onClose(false)}>{t(lang, 'dlg_back')}</Button>
              <Button ref={okRef} variant={req.danger ? 'destructive' : req.reveal ? 'reveal' : 'default'} onClick={() => onClose(true)}>{req.confirm}</Button>
            </div>
          </m.div>
        </m.div>
      )}
    </AnimatePresence>
  );
}
