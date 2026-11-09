// @ts-nocheck
'use client';
import { useState } from 'react';
import { cn } from '@/lib/utils';
import { t } from '../portalText';

export const Fact = ({ k, v }) => <div className="flex gap-1.5"><dt className="text-muted-foreground">{k}:</dt><dd className="text-foreground">{v}</dd></div>;

// WHAT THE CUSTOMER TOLD THE SALES ENGINEER, editable before Send: one row per question (materials,
// installation, warranty, the date). "Change" offers the same options the question did; the tapped
// label goes to create_inquiry as requirement_edits and the server reads it again
// (_shared/intake_requirements.ts applyEdits), so nothing the browser sends is trusted as parsed.
export function RequirementsCard({ items, edits, onEdit, lang }) {
  const [open, setOpen] = useState(null);
  return (
    <div className="mt-3 rounded-xl border border-border bg-card/60 p-3">
      <div className="text-[12.5px] font-semibold text-foreground">{t(lang, 'nr_req_title')}</div>
      <dl className="mt-1 space-y-1.5">
        {items.map((it) => {
          const shown = edits[it.key] || it.answer;
          return (
            <div key={it.key}>
              <div className="flex flex-wrap items-baseline gap-x-1.5 text-[12.5px]">
                <dt className="text-muted-foreground">{it.label}:</dt>
                <dd className="text-foreground">{shown}</dd>
                <button type="button" className="ms-auto text-[12px] font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring"
                  aria-expanded={open === it.key} onClick={() => setOpen(open === it.key ? null : it.key)}>{t(lang, open === it.key ? 'nr_req_keep' : 'nr_req_change')}</button>
              </div>
              {open === it.key ? (
                <div className="mt-1 flex flex-wrap gap-1.5" role="group" aria-label={it.question}>
                  {it.options.map((o) => (
                    <button key={o} type="button" onClick={() => { onEdit(it.key, o); setOpen(null); }}
                      className={cn('rounded-full border px-2.5 py-1 text-[12px] focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring', shown === o ? 'border-primary/55 bg-primary/15 font-semibold text-primary' : 'border-border bg-card/60 text-foreground hover:border-primary/40')}>{o}</button>
                  ))}
                </div>
              ) : null}
            </div>
          );
        })}
      </dl>
    </div>
  );
}
