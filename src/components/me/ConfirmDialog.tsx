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
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { Button } from '@/components/ui/button';
import { t } from './portalText';

export function useConfirm(lang) {
  const [req, setReq] = useState(null);
  const ask = (body, opts = {}) => new Promise((resolve) => setReq({ body, title: opts.title || '', confirm: opts.confirm || t(lang, 'dlg_confirm'), danger: !!opts.danger, children: opts.children || null, resolve }));
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
        <motion.div className="fixed inset-0 z-[70] grid place-items-center bg-background/70 p-4 backdrop-blur-sm"
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: reduce ? 0 : 0.16 }}
          onClick={() => onClose(false)} dir={lang === 'ar' ? 'rtl' : 'ltr'}>
          <motion.div role="alertdialog" aria-modal="true" aria-labelledby="qd-confirm-title" aria-describedby="qd-confirm-body"
            className="qd-panel w-full max-w-[460px] p-5 text-foreground"
            initial={reduce ? false : { opacity: 0, y: 12, scale: 0.98 }} animate={{ opacity: 1, y: 0, scale: 1 }} exit={reduce ? { opacity: 0 } : { opacity: 0, y: 8, scale: 0.98 }}
            transition={{ duration: reduce ? 0 : 0.2, ease: [0.2, 0.8, 0.2, 1] }}
            onClick={(e) => e.stopPropagation()}>
            <h2 id="qd-confirm-title" className="font-head text-[16px] font-bold">{req.title || t(lang, 'dlg_confirm')}</h2>
            <p id="qd-confirm-body" className="mt-2 text-[13.5px] leading-relaxed text-muted-foreground">{req.body}</p>
            {req.children ? <div className="mt-3">{req.children}</div> : null}
            <div className="mt-5 flex flex-wrap justify-end gap-2">
              <Button variant="outline" onClick={() => onClose(false)}>{t(lang, 'dlg_back')}</Button>
              <Button ref={okRef} variant={req.danger ? 'destructive' : 'default'} onClick={() => onClose(true)}>{req.confirm}</Button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
