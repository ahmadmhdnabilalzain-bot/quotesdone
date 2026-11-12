'use client';
// T3 QUOTE TEMPLATES (sales_engineer, 5 Oct 2026). Applies a saved template's STRUCTURE to the quote
// form — line headings with empty prices, terms, warranty, validity, inclusions, exclusions, payment
// terms — and saves the form's structure as a template. It never reads or sends a price: the founder
// removed reusable price lists, and supplier_api / the table refuse one anyway (quote_template.ts).
// Suppliers get English only.
import React, { useEffect, useState } from 'react';
import { call } from './api';
import { Button } from '@/components/ui/button';

export type TemplateFields = { line_headings: string[]; terms: string; warranty: string; validity: string; inclusions: string; exclusions: string; payment_terms: string };
type Tpl = TemplateFields & { id: number; name: string };

export function QuoteTemplateBar({ token, current, onApply }: { token: string; current: () => TemplateFields; onApply: (t: TemplateFields) => void }) {
  const [list, setList] = useState<Tpl[]>([]);
  const [off, setOff] = useState(false);
  const [name, setName] = useState('');
  const [msg, setMsg] = useState('');
  const [busy, setBusy] = useState(false);
  const load = async () => { const j = await call('supplier_api', { action: 'template_list' }, token); if (j?.ok) { setList(j.templates || []); setOff(!!j.unavailable); } };
  useEffect(() => { load(); }, []); // oxlint-disable-line react-hooks/exhaustive-deps
  if (off) return null;
  const save = async () => {
    setMsg(''); setBusy(true);
    try {
    const j = await call('supplier_api', { action: 'template_save', template: { name, ...current() } }, token);
    if (j?.ok) { setMsg('Template saved (no prices are kept).'); setName(''); load(); } else setMsg(j?.message || j?.error || 'Could not save the template.');
    } finally { setBusy(false); }
  };
  return (
    <div className="flex flex-wrap items-center gap-2 text-[13px]" dir="ltr" lang="en">
      <label className="flex items-center gap-2">
        <span className="font-semibold">Template</span>
        <select aria-label="Apply a saved template" className="h-9 rounded-md border border-input bg-background px-2 pointer-coarse:text-[16px] pointer-coarse:min-h-11" value=""
          onChange={(e) => { const t = list.find((x) => String(x.id) === e.target.value); if (t) { onApply(t); setMsg(`Applied “${t.name}”. Enter this inquiry’s prices.`); } }}>
          <option value="">{list.length ? 'Apply a saved template…' : 'No saved templates yet'}</option>
          {list.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
        </select>
      </label>
      <input aria-label="Template name" className="h-9 rounded-md border border-input bg-background px-2 pointer-coarse:text-[16px] pointer-coarse:min-h-11" placeholder="Save these terms as…" value={name} maxLength={80} onChange={(e) => setName(e.target.value)} />
      <Button size="sm" variant="outline" disabled={busy || name.trim().length < 2} aria-busy={busy} onClick={save}>{busy ? 'Saving…' : 'Save template'}</Button>
      {msg ? <span role="status" className="text-muted-foreground">{msg}</span> : null}
    </div>
  );
}
