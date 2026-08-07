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

  const L = lang === 'ar'
    ? { hint: 'اضغط ⌘K للبحث', placeholder: 'انتقل إلى…', empty: 'لا نتائج', go: 'الانتقال' }
    : { hint: 'Press ⌘K to jump anywhere', placeholder: 'Go to…', empty: 'Nothing matches', go: 'Destinations' };

  return (
    <>
      <button type="button" onClick={() => setOpen(true)}
        className="qd-link hidden text-xs text-muted-foreground sm:inline">{L.hint}</button>

      {open && (
        <div className="fixed inset-0 z-[60] flex items-start justify-center bg-black/50 pt-[12vh] backdrop-blur-sm"
          onClick={() => setOpen(false)}>
          <Command
            label={L.placeholder}
            className="w-[min(34rem,92vw)] overflow-hidden rounded-xl bg-[#0b1220]/97 shadow-2xl ring-1 ring-cyan-400/25"
            onClick={(e) => e.stopPropagation()}
          >
            <Command.Input autoFocus placeholder={L.placeholder}
              className="w-full border-b border-white/10 bg-transparent px-4 py-3 text-[13.5px] text-white outline-none placeholder:text-muted-foreground" />
            <Command.List className="max-h-[18rem] overflow-y-auto p-1.5">
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
