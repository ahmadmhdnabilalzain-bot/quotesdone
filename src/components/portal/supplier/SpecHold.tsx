'use client';
// A QUOTE ON HOLD, AND THE TWO WAYS OUT (founder, 14 Sep 2026).
//
// "if a supplier submits missing information, then the sales agent will notify him that the
// quotation will be on hold until he mentions the exact details, and those can be either filled on
// the portal and the sales agent will regenerate the quote after the supplier approval that its
// correct, or the supplier can resubmit a new revised quote."
//
// This panel is that sentence. It lists exactly which line and which detail the sales engineer is
// holding the quote for (supplier_api spec_hold), and offers (a) a per-line form of just those details
// — labels, units and suggested values from the spec model, validated server-side by the same readers
// the hold gate uses — after which the sales engineer regenerates the standardised quotation and the
// supplier confirms it (spec_fill, spec_approve); or (b) "Upload a revised quote", which reopens the
// quote form (a resubmission supersedes the hold and is checked again).
import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { call } from './api';
import { srvMsg } from './serverCopy';
// Amounts, units and codes are left-to-right runs inside Arabic text; src/lib/Ltr.tsx holds the rule.
import { Ltr } from '@/lib/Ltr';

type Lang = 'en' | 'ar' | string;
const COPY = {
  en: {
    held: 'On hold — the QuotesDone sales engineer needs these exact details before this quote can reach the customer:',
    line: (n: number) => `Line ${n}`, fill: 'Fill in the missing details', resubmit: 'Upload a revised quote', cancel: 'Close',
    save: 'Save and regenerate my quotation', saving: 'Saving…', yes: 'Yes', no: 'No', choose: 'Choose…',
    still: 'Saved. These details are still missing:', regenerated: 'Your quotation has been regenerated. Check it below and confirm it is correct.',
    review: 'Your regenerated quotation — check every line', total: 'Total excluding VAT', pdf: 'Open the regenerated quotation (PDF)',
    confirm: 'I confirm this regenerated quotation is correct.', approve: 'Approve and send to the customer', approving: 'Sending…', change: 'Change a detail',
    released: 'Approved. Your quote is released to the customer.', releasedWaiting: 'Approved. The hold is released; the quote still needs its commercial terms before it is sent.',
    loading: 'Loading…', err: 'Something went wrong. Please try again.', terms: 'Quote terms', ex: 'e.g.',
    errs: { vague: 'State the exact value', not_a_number: 'Enter a number', not_concrete: 'State a date or a number of days, weeks or months', choose_yes_or_no: 'Choose yes or no', unknown_attribute: 'Not asked for this line', too_long: 'Too long' } as Record<string, string>,
  },
  ar: {
    held: 'معلّق — يحتاج مهندس المبيعات في QuotesDone إلى هذه التفاصيل الدقيقة قبل أن يصل هذا العرض إلى العميل:',
    line: (n: number) => `البند ${n}`, fill: 'أكمل التفاصيل الناقصة', resubmit: 'ارفع عرضًا معدّلًا', cancel: 'إغلاق',
    save: 'احفظ وأعد إعداد عرضي', saving: 'جارٍ الحفظ…', yes: 'نعم', no: 'لا', choose: 'اختر…',
    still: 'حُفظ. ما زالت هذه التفاصيل ناقصة:', regenerated: 'أُعيد إعداد عرضك. راجعه أدناه وأكّد أنه صحيح.',
    review: 'عرضك بعد إعادة الإعداد — راجع كل بند', total: 'الإجمالي غير شامل الضريبة', pdf: 'افتح العرض المُعاد إعداده (PDF)',
    confirm: 'أؤكد أن هذا العرض المُعاد إعداده صحيح.', approve: 'اعتمده وأرسله إلى العميل', approving: 'جارٍ الإرسال…', change: 'عدّل تفصيلًا',
    released: 'تم الاعتماد. أُرسل عرضك إلى العميل.', releasedWaiting: 'تم الاعتماد وأُلغي التعليق؛ ما زال العرض يحتاج شروطه التجارية قبل إرساله.',
    loading: 'جارٍ التحميل…', err: 'حدث خطأ. يُرجى المحاولة مرة أخرى.', terms: 'شروط العرض', ex: 'مثال:',
    errs: { vague: 'اذكر القيمة الدقيقة', not_a_number: 'أدخل رقمًا', not_concrete: 'اذكر تاريخًا أو عددًا من الأيام أو الأسابيع أو الأشهر', choose_yes_or_no: 'اختر نعم أو لا', unknown_attribute: 'غير مطلوب لهذا البند', too_long: 'طويل جدًا' } as Record<string, string>,
  },
};
type Field = { attr: string; label_en: string; label_ar: string; type: string; unit?: string | null; unit_ar?: string | null; options?: string[] | null; missing?: boolean; value?: string | null };
type Missing = { scope: 'line' | 'quote'; line_no: number | null; description: string | null; attr: string; label_en: string; label_ar: string; type: string; unit?: string; unit_ar?: string; options?: string[] };
const TERM_PLACEHOLDER: Record<string, [string, string]> = {
  delivery: ['21 days from approval', '21 يومًا من الاعتماد'], installation_detail: ['Installation in 5 working days on site', 'التركيب خلال 5 أيام عمل في الموقع'],
  warranty_period: ['2 years', 'سنتان'], warranty_coverage: ['Parts, labour and workmanship', 'قطع الغيار والعمالة والمصنعية'], price_ex_vat: ['10500', '10500'],
};

export function SpecHoldPanel({ quoteId, lang, token, onChanged, onResubmit, title }: { quoteId: string; lang: Lang; token: string; onChanged?: () => void; onResubmit?: () => void; title?: string | null }) {
  const ar = lang === 'ar'; const t = ar ? COPY.ar : COPY.en;
  const [data, setData] = useState<any>(null);
  const [lines, setLines] = useState<Record<string, Record<string, string>>>({});
  const [terms, setTerms] = useState<Record<string, string>>({});
  const [open, setOpen] = useState(false); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const [errs, setErrs] = useState<Record<string, string>>({}); const [confirm, setConfirm] = useState(false);
  const load = () => call('supplier_api', { action: 'spec_hold', quote_id: quoteId }, token).then(setData);
  useEffect(() => { load(); }, [quoteId, token]);
  if (!data) return <div className="mt-3 text-[13px] text-muted-foreground" aria-busy="true">{t.loading}</div>;
  if (data.error) return <div className="mt-3 text-[13px] text-muted-foreground">{srvMsg(String(lang), data, t.err)}</div>;
  const hold = data.hold; const schema = data.schema || { lines: [], terms: [] };
  if (!hold || !['open', 'awaiting_approval'].includes(hold.state)) return null;
  const awaiting = hold.state === 'awaiting_approval';
  const missing: Missing[] = Array.isArray(hold.missing) ? hold.missing : [];
  const label = (x: { label_en: string; label_ar: string }) => (ar ? x.label_ar : x.label_en);
  const unit = (x: { unit?: string | null; unit_ar?: string | null }) => (x.unit ? (ar ? x.unit_ar || x.unit : x.unit) : '');
  const errKey = (scope: string, ln: number | null, attr: string) => `${scope}:${ln ?? ''}:${attr}`;

  const save = async () => {
    setBusy(true); setMsg(''); setErrs({});
    const j = await call('supplier_api', { action: 'spec_fill', quote_id: quoteId, values: { lines, terms } }, token);
    setBusy(false);
    if (!j || !j.ok) {
      const e: Record<string, string> = {};
      for (const x of (j?.errors || [])) e[errKey(x.scope, x.line_no, x.attr)] = t.errs[x.code] || t.err;
      setErrs(e); setMsg(Object.keys(e).length ? '' : srvMsg(String(lang), j, t.err)); return;
    }
    setMsg(j.complete ? t.regenerated : t.still); setOpen(!j.complete); setLines({}); setTerms({});
    await load();
  };
  const approve = async () => {
    setBusy(true); setMsg('');
    const j = await call('supplier_api', { action: 'spec_approve', quote_id: quoteId, confirm }, token);
    setBusy(false);
    if (!j || !j.ok) { setMsg(srvMsg(String(lang), j, t.err)); return; }
    setMsg(j.live ? t.released : t.releasedWaiting); onChanged && onChanged();
  };

  const input = (f: Field | Missing, value: string, set: (v: string) => void, key: string, placeholder?: string) => {
    const id = 'qd-spec-' + quoteId.slice(0, 8) + '-' + key.replace(/[^\w-]/g, '_');
    const list = f.options && f.options.length && f.type !== 'choice' ? id + '-opts' : undefined;
    return (
      <label key={key} className="flex min-w-[180px] flex-1 flex-col gap-1">
        <span className="text-[12px] font-semibold text-muted-foreground">{label(f)}{unit(f) ? <> (<Ltr>{unit(f)}</Ltr>)</> : null}</span>
        {f.type === 'choice'
          ? <select className="h-9 rounded-md border border-input bg-background px-2 text-[13px]" value={value} onChange={(e) => set(e.target.value)} aria-invalid={!!errs[key]}>
              <option value="">{t.choose}</option><option value="yes">{t.yes}</option><option value="no">{t.no}</option>
            </select>
          : <Input inputMode={f.type === 'number' ? 'decimal' : undefined} list={list} value={value} placeholder={placeholder} onChange={(e) => set(e.target.value)} aria-invalid={!!errs[key]} className={f.type === 'number' ? 'tabular font-mono' : undefined} />}
        {list ? <datalist id={list}>{(f.options || []).map((o) => <option key={o} value={o} />)}</datalist> : null}
        {errs[key] ? <span role="alert" className="text-[12px] text-destructive">{errs[key]}</span> : null}
      </label>
    );
  };
  const reg = hold.regenerated;

  return (
    <div role="note" className="mt-3 rounded-md border border-warn/40 bg-warn/10 px-3.5 py-3">
      {title ? <div className="mb-1 font-mono text-[11px] uppercase tracking-caps text-muted-foreground">{title}</div> : null}
      {!awaiting && <>
        <div className="text-[13px] font-semibold text-foreground">{t.held}</div>
        <ul className="mt-1.5 flex flex-col gap-1">{missing.map((m, i) => (
          <li key={i} className="flex items-start gap-2 text-[13px] text-foreground"><span aria-hidden className="mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full bg-warn" />
            <span>{m.scope === 'line' ? <><strong>{t.line(Number(m.line_no))}</strong>{m.description ? <span className="text-muted-foreground"> ({String(m.description).slice(0, 70)})</span> : null}: </> : null}{label(m)}</span></li>))}
        </ul>
        {!open && <div className="mt-2.5 flex flex-wrap gap-2">
          <Button size="sm" onClick={() => { setOpen(true); setMsg(''); }}>{t.fill}</Button>
          {onResubmit ? <Button size="sm" variant="outline" onClick={onResubmit}>{t.resubmit}</Button> : null}
        </div>}
      </>}

      {open && !awaiting && <div className="mt-3 flex flex-col gap-3 rounded-md border border-border bg-background/60 p-3">
        {schema.lines.filter((l: any) => l.fields.some((f: Field) => f.missing)).map((l: any) => (
          <fieldset key={l.line_no} className="flex flex-col gap-2">
            <legend className="text-[13px] font-semibold text-foreground">{t.line(l.line_no)} · <span className="font-normal text-muted-foreground">{String(l.description).slice(0, 90)}</span></legend>
            <div className="flex flex-wrap gap-2.5">{l.fields.filter((f: Field) => f.missing).map((f: Field) => {
              const key = errKey('line', l.line_no, f.attr);
              return input(f, lines[l.line_no]?.[f.attr] ?? '', (v) => setLines((s) => ({ ...s, [l.line_no]: { ...(s[l.line_no] || {}), [f.attr]: v } })), key, f.options?.[0] ? `${t.ex} ${f.options[0]}` : undefined);
            })}</div>
          </fieldset>))}
        {schema.terms.length > 0 && <fieldset className="flex flex-col gap-2">
          <legend className="text-[13px] font-semibold text-foreground">{t.terms}</legend>
          <div className="flex flex-wrap gap-2.5">{schema.terms.map((m: Missing) => input(m, terms[m.attr] ?? '', (v) => setTerms((s) => ({ ...s, [m.attr]: v })), errKey('quote', null, m.attr), TERM_PLACEHOLDER[m.attr] ? `${t.ex} ${TERM_PLACEHOLDER[m.attr][ar ? 1 : 0]}` : undefined))}</div>
        </fieldset>}
        <div className="flex flex-wrap justify-end gap-2">
          <Button size="sm" variant="outline" onClick={() => setOpen(false)}>{t.cancel}</Button>
          <Button size="sm" disabled={busy} onClick={save}>{busy ? t.saving : t.save}</Button>
        </div>
      </div>}

      {awaiting && reg && <div className="flex flex-col gap-2.5">
        <div className="text-[13px] font-semibold text-foreground">{t.review}</div>
        <div className="overflow-x-auto"><table className="w-full min-w-[420px] text-[12.5px]">
          <tbody>{(reg.lines || []).map((l: any) => (
            <tr key={l.line_no} className="border-t border-border align-top">
              <td className="py-1.5 pe-2 font-mono text-muted-foreground">{l.line_no}</td>
              <td className="py-1.5 pe-2 text-foreground">{l.description}
                <div className="mt-1 flex flex-wrap gap-1">{(l.spec || []).map((s: any) => <span key={s.code} className={cn('rounded-chip border px-1.5 py-0.5 text-[11.5px]', s.source === 'supplier_portal' ? 'border-primary/40 bg-primary/10' : 'border-border')}>{ar ? s.label_ar : s.label_en}: <Ltr>{s.value}{s.unit ? ' ' + (ar ? s.unit_ar || s.unit : s.unit) : ''}</Ltr></span>)}</div></td>
              <td className="py-1.5 text-end font-mono tabular-nums"><Ltr>{l.qty ?? ''} {l.unit ?? ''}</Ltr></td>
            </tr>))}</tbody>
        </table></div>
        <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-[12.5px]">
          {(['delivery', 'installation', 'warranty', 'validity', 'payment_terms'] as const).filter((k) => reg.terms?.[k]).map((k) => (
            <div key={k} className="contents"><dt className="text-muted-foreground">{({ delivery: ar ? 'التسليم' : 'Delivery', installation: ar ? 'التركيب' : 'Installation', warranty: ar ? 'الضمان' : 'Warranty', validity: ar ? 'صلاحية العرض' : 'Validity', payment_terms: ar ? 'شروط الدفع' : 'Payment terms' } as Record<string, string>)[k]}</dt><dd className="text-foreground">{reg.terms[k]}</dd></div>))}
          <dt className="font-semibold text-foreground">{t.total}</dt><dd className="font-mono font-semibold tabular-nums text-foreground"><Ltr>AED {Number(reg.total || 0).toLocaleString('en-AE', { maximumFractionDigits: 2 })}</Ltr></dd>
        </dl>
        {hold.pdf_url ? <a className="text-[13px] font-semibold text-primary underline-offset-2 hover:underline" href={hold.pdf_url} target="_blank" rel="noopener noreferrer">{t.pdf}</a> : null}
        <label className="flex items-start gap-2 text-[13px] text-foreground"><input type="checkbox" className="mt-0.5" checked={confirm} onChange={(e) => setConfirm(e.target.checked)} />{t.confirm}</label>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" disabled={!confirm || busy} onClick={approve}>{busy ? t.approving : t.approve}</Button>
          <Button size="sm" variant="outline" onClick={() => { setOpen(true); load(); }}>{t.change}</Button>
          {onResubmit ? <Button size="sm" variant="outline" onClick={onResubmit}>{t.resubmit}</Button> : null}
        </div>
      </div>}
      {msg ? <div role="status" className="mt-2 text-[13px] text-foreground">{msg}</div> : null}
    </div>
  );
}
