// @ts-nocheck
'use client';
// BILL TO A COMPANY, AT THE REVEAL (16 Nov 2026, scratchpad holes/CUSTOMER.md item 9). Optional and folded away: a company buyer
// opens it and gives the company, its UAE TRN and his PO reference; the reveal invoice and receipt are made out to the company
// (customer_api reveal_bill_to -> public.fn_reveal_bill_to_record) and the supplier is told whom to address only after the
// reveal. Nothing is asked at sign-up: companies buy like individuals.
import { useState } from 'react';
import { Input } from '@/components/ui/input';
import { t } from '../portalText';

export function BillToFields({ lang, initial, onChange }) {
  const [open, setOpen] = useState(!!(initial && initial.company));
  const [v, setV] = useState({ company: (initial && initial.company) || '', trn: (initial && initial.trn) || '', po_ref: (initial && initial.po_ref) || '' });
  const set = (k, x) => { const n = { ...v, [k]: x }; setV(n); onChange(n); };
  return (
    <div className="mt-3 rounded-md border border-border px-3 py-2.5 text-start">
      <label className="flex cursor-pointer items-center gap-2 text-[13px] font-medium text-foreground">
        <input type="checkbox" checked={open} onChange={(e) => { setOpen(e.target.checked); if (!e.target.checked) { const n = { company: '', trn: '', po_ref: '' }; setV(n); onChange(n); } }} />
        {t(lang, 'q_bill_toggle')}
      </label>
      {open ? <div className="mt-2 flex flex-col gap-2">
        <Input aria-label={t(lang, 'q_bill_company')} placeholder={t(lang, 'q_bill_company')} maxLength={120} value={v.company} onChange={(e) => set('company', e.target.value)} />
        <Input aria-label={t(lang, 'q_bill_trn')} placeholder={t(lang, 'q_bill_trn')} inputMode="numeric" maxLength={24} value={v.trn} onChange={(e) => set('trn', e.target.value)} />
        <Input aria-label={t(lang, 'q_bill_po')} placeholder={t(lang, 'q_bill_po')} maxLength={60} value={v.po_ref} onChange={(e) => set('po_ref', e.target.value)} />
        <p className="text-[11.5px] text-muted-foreground">{t(lang, 'q_bill_hint')}</p>
      </div> : null}
    </div>
  );
}
