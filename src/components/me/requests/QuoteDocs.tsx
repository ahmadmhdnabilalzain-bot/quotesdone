// @ts-nocheck
'use client';
import { useState } from 'react';
import { cn } from '@/lib/utils';
import { t, errText } from '../portalText';
// A window opened after an await is a popup: see src/lib/openDocument.ts (shared with the supplier portal).
import { openDocument } from '@/lib/openDocument';
import { call } from '../api';
import { S } from '../styles';

// THIS quote's own PDF, by id, in the customer's language — and the other language one click away:
// the English document always exists and the Arabic one is always offered (founder, 14 Sep 2026).
function QuotePdfLink({ q, token, lang }) {
  const [busy, setBusy] = useState(''); const [msg, setMsg] = useState('');
  const mine = lang === 'ar' ? 'ar' : 'en'; const other = mine === 'ar' ? 'en' : 'ar';
  const open = (docLang) => async (e) => {
    e.stopPropagation(); setBusy(docLang); setMsg(''); let j = null;
    const ok = await openDocument(lang, async () => { j = await call('customer_api', { action: 'quote_pdf', quote_id: q.id, lang: docLang }, token); return j && j.ok && j.url ? j.url : null; });
    setBusy(''); if (!ok) setMsg(errText(j, lang, 'q_pdf_fail'));
  };
  const prep = lang === 'ar' ? 'جارٍ التحضير…' : 'Preparing…';
  return (<span className="inline-flex flex-wrap items-center gap-x-3 gap-y-1">
    <button type="button" className="text-primary font-semibold text-[12.5px]" disabled={!!busy} onClick={open(mine)}>{busy === mine ? prep : (mine === 'ar' ? '📄 عرض السعر (PDF)' : '📄 View quote (PDF)')}</button>
    <button type="button" lang={other} className="text-muted-foreground underline underline-offset-2 text-[11.5px]" disabled={!!busy} onClick={open(other)}>{busy === other ? prep : (other === 'ar' ? 'النسخة العربية' : 'English version')}</button>
    {msg ? <span className={cn(S.sub, 'text-danger')}>{msg}</span> : null}
  </span>);
}
// THE REVEAL INVOICE AND RECEIPT (21 Sep 2026, agent: accountant). Both are QuotesDone template
// documents rendered by reveal_invoice (founder, 21 Sep: no PDF reaches a person unless it is on our
// template); reveal_invoice refuses any quote that is not this customer's own paid reveal. The
// customer's language first, the other language one click away, as for the quotation.
function InvoicePdfLink({ q, token, lang }) {
  const [busy, setBusy] = useState(''); const [msg, setMsg] = useState('');
  const mine = lang === 'ar' ? 'ar' : 'en'; const other = mine === 'ar' ? 'en' : 'ar';
  const open = (doc, docLang) => async (e) => {
    e.stopPropagation(); setBusy(doc + docLang); setMsg(''); let j = null;
    const ok = await openDocument(lang, async () => { j = await call('reveal_invoice', { quote_id: q.id, doc, lang: docLang }, token); return j && j.ok && j.url ? j.url : null; });
    setBusy(''); if (!ok) setMsg(errText(j, lang, 'q_inv_fail'));
  };
  const btn = (doc, key) => (<button type="button" className="text-primary font-semibold text-[12.5px]" disabled={!!busy} onClick={open(doc, mine)}>{busy === doc + mine ? t(lang, 'q_pdf_busy') : '🧾 ' + t(lang, key)}</button>);
  return (<span className="inline-flex flex-wrap items-center gap-x-3 gap-y-1">
    {btn('invoice', 'q_inv_pdf')}{btn('receipt', 'q_rcpt_pdf')}
    <button type="button" lang={other} className="text-muted-foreground underline underline-offset-2 text-[11.5px]" disabled={!!busy} onClick={open('invoice', other)}>{busy === 'invoice' + other ? t(lang, 'q_pdf_busy') : (other === 'ar' ? 'الفاتورة بالعربية' : 'Invoice in English')}</button>
    <button type="button" lang={other} className="text-muted-foreground underline underline-offset-2 text-[11.5px]" disabled={!!busy} onClick={open('receipt', other)}>{busy === 'receipt' + other ? t(lang, 'q_pdf_busy') : (other === 'ar' ? 'الإيصال بالعربية' : 'Receipt in English')}</button>
    {msg ? <span className={cn(S.sub, 'text-danger')}>{msg}</span> : null}
  </span>);
}
export { QuotePdfLink, InvoicePdfLink };
