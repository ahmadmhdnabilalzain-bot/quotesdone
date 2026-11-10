// @ts-nocheck
'use client';
import { boqNote, confidenceWord } from '@/lib/boqNotes';
import { t, tf } from '../portalText';

// The BOQ the reader pulled off the drawing, before Send. The customer is the only person who can
// say it was read wrong, and they were shown a line count and nothing else.
export function BoqTable({ boq, lang }) {
  const rows = boq.boq.slice(0, 40);
  const conf = (c) => confidenceWord(c, lang);
  const list = (x) => (Array.isArray(x) ? x : x ? [x] : []).map((v) => (typeof v === 'string' ? v : v && (v.text || v.item || v.note || JSON.stringify(v)))).filter(Boolean);
  const assumptions = list(boq.assumptions).map((s) => boqNote(s, lang)), missing = list(boq.missing_info).map((s) => boqNote(s, lang));
  return (
    <div className="rounded-2xl border border-border bg-card/60 p-3.5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-[13px] font-bold text-foreground">{t(lang, 'nr_boq_title')}</h3>
        {boq.confidence != null ? <span className="text-[11.5px] text-muted-foreground">{tf(lang, 'nr_boq_overall', { c: conf(boq.confidence) })}</span> : null}
      </div>
      <div className="mt-2 max-h-[240px] overflow-auto rounded-lg border border-border">
        <table className="w-full text-[12px]">
          <thead className="sticky top-0 bg-secondary font-mono text-label uppercase tracking-caps text-muted-foreground"><tr>
            <th scope="col" className="px-2.5 py-1.5 text-start font-semibold">{t(lang, 'nr_boq_item')}</th>
            <th scope="col" className="px-2.5 py-1.5 text-end font-semibold">{t(lang, 'nr_boq_qty')}</th>
            <th scope="col" className="px-2.5 py-1.5 text-start font-semibold">{t(lang, 'nr_boq_unit')}</th>
            <th scope="col" className="px-2.5 py-1.5 text-end font-semibold">{t(lang, 'nr_boq_conf')}</th>
          </tr></thead>
          <tbody>{rows.map((r, i) => (
            <tr key={i} className="border-t border-border/60">
              <td className="px-2.5 py-1.5 text-foreground">{r.description || r.item || r.name || '—'}</td>
              <td className="tabular px-2.5 py-1.5 text-end font-mono text-foreground">{r.qty ?? r.quantity ?? '—'}</td>
              <td className="px-2.5 py-1.5 text-muted-foreground">{r.unit || '—'}</td>
              <td className="px-2.5 py-1.5 text-end tabular-nums text-muted-foreground">{conf(r.confidence)}</td>
            </tr>
          ))}</tbody>
        </table>
      </div>
      {assumptions.length ? <div className="mt-2 text-[12px] text-muted-foreground"><b className="text-foreground">{t(lang, 'nr_boq_assumptions')}: </b>{assumptions.join(' · ')}</div> : null}
      {missing.length ? <div className="mt-1 text-[12px] text-warn-fg"><b>{t(lang, 'nr_boq_missing')}: </b>{missing.join(' · ')}</div> : null}
    </div>
  );
}
