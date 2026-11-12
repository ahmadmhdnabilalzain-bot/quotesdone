// @ts-nocheck
'use client';
import { useEffect, useRef, useState } from 'react';
import { Sheet, SheetContent, SheetTitle, SheetDescription } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';

// THE AGREEMENT OPENS OVER THE FORM, NOT IN PLACE OF IT (12 Nov 2026, customer_support; browser perfection walk M22, founder ruling
// 1645). Measured on production: the Supplier Agreement is 5,035 words, 24,108 px tall at 390 px (28 phone screens), and the link
// opened it in a new tab with no way back; on an iPhone the form's tab was then often reloaded and what he had typed was gone (H7).
// The page cannot be framed (next.config.mjs: frame-ancestors 'none'), so the published page is read and its clauses are shown in
// a sheet with its own scroll and one clear way back. The sheet shows exactly the page the link names (the same words, the same
// version); when it cannot be read, the sheet says so and offers the page in a new tab.
const cache = new Map();
async function readAgreement(href) {
  if (cache.has(href)) return cache.get(href);
  const r = await fetch(href, { credentials: 'same-origin' });
  if (!r.ok) throw new Error('http ' + r.status);
  const doc = new DOMParser().parseFromString(await r.text(), 'text/html');
  const art = doc.querySelector('main article');
  if (!art) throw new Error('no article');
  // Our own page, same origin; still, nothing that runs is carried over: no script, frame or form, no on* handler, no javascript: link.
  art.querySelectorAll('script,style,iframe,object,embed,form').forEach((n) => n.remove());
  art.querySelectorAll('*').forEach((el) => { for (const a of Array.from(el.attributes)) if (/^on/i.test(a.name) || (/^(href|src|xlink:href)$/i.test(a.name) && /^\s*javascript:/i.test(a.value))) el.removeAttribute(a.name); });
  const out = { title: (doc.querySelector('main h1')?.textContent || 'Supplier Agreement').trim(), meta: [...doc.querySelectorAll('main .font-mono')].map((n) => n.textContent.trim()).filter(Boolean).slice(0, 3), html: art.innerHTML };
  cache.set(href, out);
  return out;
}

export function AgreementSheet({ open, onClose, href }) {
  const [doc, setDoc] = useState(null); const [err, setErr] = useState(false);
  const back = useRef(null);
  useEffect(() => { if (!open || doc) return; setErr(false); readAgreement(href).then(setDoc).catch(() => setErr(true)); }, [open, href]);
  return (
    <Sheet open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <SheetContent side="end" onOpenAutoFocus={(e) => { e.preventDefault(); back.current?.focus(); }}
        className="w-full max-w-none sm:max-w-2xl gap-0 p-0 [&>button.absolute]:hidden" data-testid="agreement-sheet">
        <div className="sticky top-0 z-10 flex items-center gap-3 border-b border-line2 bg-popover px-4 py-3 sm:px-6">
          <Button ref={back} variant="outline" className="min-h-11" onClick={onClose}>← Back to registration</Button>
          <span className="sr-only">Your registration form is kept as it is.</span>
        </div>
        <div className="flex-1 overflow-y-auto overscroll-contain px-4 pb-10 pt-5 sm:px-6">
          <SheetTitle className="text-[22px]">{doc ? doc.title : 'Supplier Agreement'}</SheetTitle>
          <SheetDescription className="mt-1 text-[14px] pointer-coarse:text-[15px]">Read it here; your registration stays as you left it underneath.</SheetDescription>
          {doc && doc.meta.length ? <div className="mt-3 flex flex-col gap-1 border-s border-line2 ps-3">{doc.meta.map((m) => <span key={m} className="font-mono text-[12px] text-faint">{m}</span>)}</div> : null}
          {!doc && !err && <div role="status" className="mt-6 flex items-center gap-2 text-[15px] text-muted-foreground"><span aria-hidden="true" className="qd-spin" />Opening the agreement…</div>}
          {err && <div role="alert" className="mt-6 text-[15px] text-muted-foreground">We could not open the agreement here. <a href={href} target="_blank" rel="noopener" className="font-semibold text-primary underline">Open it in a new tab</a>; this form stays as it is.</div>}
          {doc && <div className="mt-6 text-[15px] leading-[1.7] text-foreground [&_.card]:mb-6 [&_h2]:mb-3 [&_h2]:mt-10 [&_h2]:border-t [&_h2]:border-line [&_h2]:pt-6 [&_h2]:text-[18px] [&_h2]:font-bold [&_li]:mb-1.5 [&_ol]:ms-5 [&_ol]:list-decimal [&_p]:mb-4 [&_ul]:ms-5 [&_ul]:list-disc"
            dangerouslySetInnerHTML={{ __html: doc.html }} />}
          {doc && <div className="mt-8"><Button className="w-full" onClick={onClose}>Back to registration</Button></div>}
        </div>
      </SheetContent>
    </Sheet>
  );
}
