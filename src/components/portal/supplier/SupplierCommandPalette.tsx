'use client';
// ROW #5 §22 — THE COMMAND PALETTE. ⌘K / Ctrl-K anywhere in the supplier portal.
//
// The portal now has fifteen tabs. A tab strip that long stops being navigation and starts being a
// list you read, so the spec's command palette is not garnish here — it is how a supplier who knows
// where they are going gets there in two keystrokes. cmdk was already a dependency and unused.
//
// Destinations come from the caller rather than being restated here: the portal owns TABS, and a
// second hard-coded copy of that list is how "2 destinations seen, 10 real" happens.
import React, { useEffect, useState } from 'react';
import { Command } from 'cmdk';

type Lang = 'en' | 'ar';

export default function SupplierCommandPalette({ tabs, labels, onGo, lang = 'en' }:
  { tabs: string[]; labels: Record<string, string>; onGo: (tab: string) => void; lang?: Lang }) {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key.toLowerCase() === 'k' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); setOpen((o) => !o); }
      if (e.key === 'Escape') setOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  // THE RIGHT KEY, AND ONLY WHERE THERE IS A KEYBOARD (12 Nov 2026, customer_support; founder ruling 1645, browser walk finding L11).
  // "Press ⌘K" was shown on Windows, where the key is Ctrl, and on touch screens with no keyboard at all. The key named is the one
  // this device uses (Apple: ⌘, everything else: Ctrl), and the hint is hidden on a coarse pointer (a phone or a tablet).
  // Read once on the client: the supplier portal renders nothing on the server (SupplierPortal returns null until mounted).
  const [mac] = useState(() => { try { const nav = navigator as Navigator & { userAgentData?: { platform?: string } }; return /mac|iphone|ipad|ipod/i.test(nav.userAgentData?.platform || nav.platform || nav.userAgent || ''); } catch (_e) { return false; } });
  const key = mac ? '⌘K' : 'Ctrl+K';
  const L = lang === 'ar'
    ? { hint: 'اضغطوا ⌘K للبحث', placeholder: 'الانتقال إلى…', empty: 'لا توجد نتائج', go: 'الانتقال' }
    : { hint: `Press ${key} to jump anywhere`, placeholder: 'Go to…', empty: 'Nothing matches', go: 'Destinations' };

  return (
    <>
      <button type="button" onClick={() => setOpen(true)}
        className="qd-link hidden min-h-11 min-w-11 items-center text-xs text-muted-foreground pointer-fine:sm:inline-flex">{L.hint}</button>

      {open && (
        <div className="fixed inset-0 z-60 flex items-start justify-center bg-black/50 pt-[12vh] backdrop-blur-xs"
          onClick={() => setOpen(false)}>
          <Command
            label={L.placeholder}
            className="w-[min(34rem,92vw)] overflow-hidden rounded-xl bg-[#0b1220]/97 shadow-2xl ring-1 ring-cyan-400/25"
            onClick={(e) => e.stopPropagation()}
          >
            <Command.Input autoFocus placeholder={L.placeholder}
              className="w-full border-b border-white/10 bg-transparent px-4 py-3 text-[13.5px] text-white outline-hidden placeholder:text-muted-foreground" />
            <Command.List className="max-h-72 overflow-y-auto p-1.5">
              <Command.Empty className="px-3 py-6 text-center text-xs text-muted-foreground">{L.empty}</Command.Empty>
              <Command.Group heading={L.go} className="px-1 text-[11px] uppercase tracking-wide text-muted-foreground">
                {tabs.map((k) => (
                  <Command.Item
                    key={k} value={`${k} ${labels[k] || ''}`}
                    onSelect={() => { onGo(k); setOpen(false); }}
                    className="cursor-pointer rounded-md px-3 py-2 text-[13px] text-white data-[selected=true]:bg-white/10"
                  >
                    {labels[k] || k}
                  </Command.Item>
                ))}
              </Command.Group>
            </Command.List>
          </Command>
        </div>
      )}
    </>
  );
}
