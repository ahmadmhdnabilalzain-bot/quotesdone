// @ts-nocheck
'use client';
import { useRef, useState } from 'react';
import { QuoteTemplateBar } from '../QuoteTemplateBar';
import { srvMsg, srvText } from '../serverCopy';
import { call, REASONING_TIMEOUT_MS, tooBigToRead, sizeMb } from '../api';
import { aed } from '../money';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { STILL_WORKING_MS } from '@/lib/stillWorking';
import { lineCount, Lbl, missingLabel, QUOTE_ACCEPT, FilePick } from './helpers';
import { fileToImages } from './upload';
import { t } from './copy';
import { S } from './styles';

// Label above figure, not below: the eye lands on the number, and the label is
// already read by then. Figures are tabular so a row of KPIs aligns on the digit.
function QuoteForm({ inquiry, token, onDone, lang, initialItems = null, quote = null, newOption = false }) {
  // An existing quote (a held draft, or one already sent) reopens with what was sent, lines included.
  // `quote` names one option to edit; `newOption` starts another option, which is its own quotation.
  const q0 = quote || (newOption ? {} : inquiry.quote || {});
  const optionArgs = newOption ? { new_option: true } : (q0.option_no ? { option_no: q0.option_no } : {});
  // VAT (founder, 14 Sep 2026): the customer compares and pays on the price EXCLUDING VAT, and never
  // sees the supplier's VAT details. The supplier says how the total is stated; if it includes VAT,
  // they give the ex-VAT figure.
  const VAT_BASIS = ['exclusive', 'inclusive', 'not_registered'];
  // A quote sent with an ex-VAT figure is stored as 'confirmed_on_portal' (vat.ts), which is none of
  // the three choices, so the select reopened on "Choose…" (audit 21 Sep 2026, finding 35). The
  // stated amount above the ex-VAT figure says it was VAT-inclusive; equal, VAT-exclusive.
  const vat0 = VAT_BASIS.includes(q0.vat_treatment) ? q0.vat_treatment
    : q0.vat_treatment === 'confirmed_on_portal' && Number(q0.price_ex_vat) > 0
      ? (Number(q0.amount_as_stated) > Number(q0.price_ex_vat) + 0.5 ? 'inclusive' : 'exclusive') : '';
  const [vat, setVat] = useState(vat0);
  const [exVat, setExVat] = useState(vat0 === 'inclusive' && q0.price_ex_vat != null ? String(q0.price_ex_vat) : '');
  const lines0 = initialItems && initialItems.length ? initialItems
    : (Array.isArray(q0.items) && q0.items.length ? q0.items.map((r) => ({ description: r.description || '', qty: r.qty == null ? '' : String(r.qty), unit: r.unit || '', unit_price: r.unit_price == null ? '' : String(r.unit_price) })) : [{ description: '', qty: '', unit: '', unit_price: '' }]);
  const [amount, setAmount] = useState(vat0 === 'inclusive' && Number(q0.amount_as_stated) > 0 ? String(q0.amount_as_stated) : q0.quote_amount != null ? String(q0.quote_amount) : ''); const [lead, setLead] = useState(q0.lead_time || ''); const [notes, setNotes] = useState(q0.notes || ''); const [scope, setScope] = useState(q0.scope || ''); const [validity, setValidity] = useState(q0.validity || ''); const [payment, setPayment] = useState(q0.payment_terms || ''); const [warranty, setWarranty] = useState(q0.warranty || ''); const [items, setItems] = useState(lines0); const [msg, setMsg] = useState(''); const [busy, setBusy] = useState(false);
  const [reading, setReading] = useState(false); const [prop, setProp] = useState(null); const [orig, setOrig] = useState(null);
  // THE QUOTATION IS READ BEFORE THE ANSWER (28 Oct 2026, sales_engineer): extract_quote calls quote_extract synchronously,
  // whose model read measured p50 15.5 s / p90 20.7 s / max 24.7 s (ai_cost_log, 30 days, n=29), so the 20 s default cut
  // off more than half of all quotation uploads. It waits REASONING_TIMEOUT_MS, as the document uploads do (#1709).
  const onFile = async (file) => { if (!file) return; setMsg(''); if (tooBigToRead(file)) { setMsg(srvText(lang, 'file_too_large_read', { mb: sizeMb(file) })); return; } setReading(true); try { const { images, b64, mime } = await fileToImages(file); const j = await call('supplier_api', { action: 'extract_quote', inquiry_id: inquiry.id, images, original: { b64, filename: file.name, mime } }, token, { timeoutMs: REASONING_TIMEOUT_MS }); if (j && j.ok && j.proposal) { const pr = j.proposal; setProp(pr); setOrig({ path: j.original_file_path, name: j.original_file_name }); const amt = pr.total != null ? pr.total : (pr.amount != null ? pr.amount : (pr.grand_total != null ? pr.grand_total : '')); if (amt !== '' && amt != null) setAmount(String(amt)); if (pr.lead_time) setLead(pr.lead_time); if (pr.scope || pr.description_anonymized) setScope(pr.scope || pr.description_anonymized); if (VAT_BASIS.includes(pr.vat_treatment)) setVat(pr.vat_treatment); setMsg(t(lang, 'read_quote_pre') + (pr.line_items ? ' — ' + lineCount(lang, pr.line_items.length) : '') + t(lang, 'read_quote_post') + (pr.options && pr.options.length > 1 ? ' ' + srvText(lang, 'options_split', { count: pr.options.length }) : '')); } else setMsg(srvMsg(lang, j, t(lang, 'could_not_read'))); } catch (_e) { setMsg(t(lang, 'could_not_read')); } setReading(false); };
  const [chk, setChk] = useState(null); const [checking, setChecking] = useState(false);
  const vatArgs = { vat_treatment: vat || undefined, price_ex_vat: vat === 'inclusive' && Number(exVat) > 0 ? Number(exVat) : undefined };
  const buildPayload = () => prop ? { action: 'submit_quote', inquiry_id: inquiry.id, amount: Number(amount), lead_time: lead, notes, scope, conditions: prop.conditions || '', exclusions: prop.exclusions || '', validity: validity || prop.validity || '', payment_terms: payment || prop.payment_terms || '', warranty: warranty || prop.warranty || '', items: prop.line_items || [], masked_terms: prop.masked_terms || null, source: 'upload', original_file_path: orig && orig.path, original_file_name: orig && orig.name, subtotal: prop.subtotal ?? undefined, vat_amount: prop.vat_amount ?? undefined, trn: prop.trn ?? undefined, option_totals: prop.option_totals || undefined, ...vatArgs, ...optionArgs } : { action: 'submit_quote', inquiry_id: inquiry.id, amount: Number(amount), lead_time: lead, notes, scope, validity, payment_terms: payment, warranty, items: items.filter((x) => (x.description || '').trim()), source: 'form', ...vatArgs, ...optionArgs };
  // Preflight. submit_quote accepts dry_run: it runs the REAL scorer and the REAL accept rule,
  // then stops — no status change, no customer notification, and deliberately no coaching email,
  // because fn_quote_coach queues mail that must not fire while someone is mid-edit.
  //
  // This is the gap the product had. Feedback only ever arrived AFTER a quote was accepted, by
  // email, hours later. And "accepted" was never the whole story: every quote on the platform
  // today passes through the form_complete branch at a score of 65 while the structured scorer
  // says submittable=false — so they reach customers without per-item pricing or brand/model,
  // which is exactly what the comparison depends on. accept_via makes that visible here instead.
  const check = async () => {
    if (!(Number(amount) > 0)) { setMsg(t(lang, 'enter_valid_amount')); return; }
    setChecking(true); setMsg(''); setChk(null);
    // THE CHECK REASONS AT HIGH EFFORT AND IS WAITED FOR (it_engineer, 12 Nov 2026; ledger 1642; final audit H5). Measured on
    // the 11-12 Nov journey runs: 6 of 8 dry runs outlasted this call's 20 s default (up to 66.6 s), so a supplier read
    // "could not submit" for a check still working. It waits REASONING_TIMEOUT_MS (90 s), and after STILL_WORKING_MS the
    // supplier is told it is still checking. prevented by: scripts/checks/a_long_reasoning_call_is_waited_for_with_progress.test.mjs
    const slow = setTimeout(() => setMsg(t(lang, 'check_still')), STILL_WORKING_MS);
    const j = await call('supplier_api', { ...buildPayload(), dry_run: true }, token, { timeoutMs: REASONING_TIMEOUT_MS }).finally(() => clearTimeout(slow));
    setChecking(false); setMsg('');
    if (j && j.ok) setChk(j.options ? { ...j.options[0], options: j.options } : j); else setMsg(srvMsg(lang, j, t(lang, 'could_not_submit')));
  };
  // One submission at a time: `busy` disables the button only after the next render, so a fast double click
  // could send two (each a new option under new_option). The ref closes that window (#1563 review).
  const inFlight = useRef(false);
  const submit = async () => {
    if (inFlight.current || checking) return;
    if (!(Number(amount) > 0)) { setMsg(t(lang, 'enter_valid_amount')); return; }
    inFlight.current = true; setBusy(true); setMsg('');
    const j = await call('supplier_api', buildPayload(), token).finally(() => { inFlight.current = false; });
    setBusy(false);
    // Accepted, held by the sales engineer (the card then shows exactly what is missing and the two
    // ways out) or split into options: the card is the next thing the supplier needs to see.
    if (j && j.ok && (j.accepted || j.held || j.options)) onDone({ held: !!j.held && !j.accepted });
    else if (j && j.ok) setMsg(srvMsg(lang, j, t(lang, 'draft_saved')));
    else setMsg(srvMsg(lang, j, t(lang, 'could_not_submit')));
  };
  const ar = lang === 'ar';
  // Presentation only: the sum of what the supplier typed into priced lines, so the totals row can sit
  // beside the quoted total. It is never sent; `amount` stays the figure the supplier entered.
  const lineSum = items.reduce((acc, x) => { const q = Number(x.qty), p = Number(x.unit_price); return acc + (q > 0 && p > 0 ? q * p : 0); }, 0);
  const grp = 'font-mono text-label uppercase tracking-caps text-muted-foreground';
  return <div className="mt-5 flex flex-col gap-4 rounded-panel border border-border bg-background/40 p-4 sm:p-5">
    <div className="flex gap-2.5 flex-wrap items-center"><span className={cn(S.sub, 'font-semibold')}>{t(lang, 'upload_quote')}</span><FilePick lang={lang} accept={QUOTE_ACCEPT} onPick={(fl) => fl && onFile(fl)} />{reading && <span className={S.sub}>{t(lang, 'reading')}</span>}</div>
    {/* What the reader decided about his figures (a re-read total, a line whose quantity x rate is not its amount): HIS eyes
        only, never the notes for the customer (review of 12 Nov 2026). Suppliers are written in English (ruling 1008). */}
    {prop && Array.isArray(prop.warnings) && prop.warnings.length ? <div role="status" className="rounded-md border border-warn/40 bg-warn/10 px-3 py-2 text-[12.5px] text-warn-fg"><div className="font-semibold">Please check before you send</div><ul className="mt-1 list-disc ps-4">{prop.warnings.map((w, i) => <li key={i}>{w}</li>)}</ul></div> : null}
    {/* T3: a saved template fills structure only (headings with empty prices, terms); never a price. */}
    <QuoteTemplateBar token={token}
      current={() => { const m = /(?:^|\n)Exclusions: ([\s\S]*)$/.exec(notes || ''); return { line_headings: items.map((x) => x.description || '').filter(Boolean), terms: m ? notes.slice(0, m.index).trim() : notes, warranty, validity, inclusions: scope, exclusions: m ? m[1].trim() : ((prop && prop.exclusions) || ''), payment_terms: payment }; }}
      onApply={(tp) => { if (tp.validity) setValidity(tp.validity); if (tp.payment_terms) setPayment(tp.payment_terms); if (tp.warranty) setWarranty(tp.warranty); if (tp.inclusions) setScope(tp.inclusions); const n = [tp.terms, tp.exclusions ? 'Exclusions: ' + tp.exclusions : ''].filter(Boolean).join('\n'); if (n) setNotes(n); if (tp.line_headings.length && !items.some((x) => Number(x.unit_price) > 0)) setItems(tp.line_headings.map((d) => ({ description: d, qty: '', unit: '', unit_price: '' }))); }} />
    <div className={cn(grp, 'border-t border-border pt-4')}>{ar ? 'السعر والشروط' : 'Price and terms'}</div>
    <div className="flex gap-2.5 flex-wrap -mt-2"><Lbl className="flex-1" text={t(lang, 'total_aed')}><Input className="tabular font-mono text-[15px]" inputMode="decimal" placeholder={t(lang, 'total_aed')} value={amount} onChange={(e) => setAmount(e.target.value)} /></Lbl><Lbl className="flex-1" text={t(lang, 'lead_time')}><Input placeholder={t(lang, 'lead_time')} value={lead} onChange={(e) => setLead(e.target.value)} /></Lbl></div>
    <div className="flex gap-2.5 flex-wrap">
      <Lbl className="flex-1 min-w-[200px]" visible text={ar ? 'الإجمالي أعلاه' : 'The total above'}>
        <select className="h-9 w-full rounded-md border border-input bg-background px-2 text-[13px] pointer-coarse:text-[16px] pointer-coarse:min-h-11" value={vat} onChange={(e) => setVat(e.target.value)}>
          <option value="">{ar ? 'يُرجى الاختيار: هل يشمل ضريبة القيمة المضافة؟' : 'Choose: does it include VAT?'}</option>
          <option value="exclusive">{ar ? 'غير شامل ضريبة القيمة المضافة' : 'Excludes VAT'}</option>
          <option value="inclusive">{ar ? 'شامل ضريبة القيمة المضافة' : 'Includes VAT'}</option>
          <option value="not_registered">{ar ? 'لسنا مسجلين في ضريبة القيمة المضافة' : 'We are not VAT-registered'}</option>
        </select></Lbl>
      {vat === 'inclusive' ? <Lbl className="flex-1 min-w-[200px]" visible text={ar ? 'السعر غير شامل الضريبة (درهم)' : 'Price excluding VAT (AED)'}><Input className="tabular font-mono" inputMode="decimal" value={exVat} onChange={(e) => setExVat(e.target.value)} /></Lbl> : null}
    </div>
    <div className={S.sub}>{ar ? 'يقارن العميل ويدفع على السعر غير شامل الضريبة، ولا تُعرض عليه تفاصيل الضريبة ولا رقم تسجيلكم الضريبي.' : 'The customer compares and pays on the price excluding VAT; your VAT details and TRN are never shown to them.'}</div>
    <div className="flex gap-2.5 flex-wrap">{[[validity, setValidity, lang === 'ar' ? 'صلاحية العرض (مثلاً 30 يومًا)' : 'Quote validity (e.g. 30 days)'], [payment, setPayment, lang === 'ar' ? 'شروط الدفع (مثلاً 50% مقدمًا)' : 'Payment terms (e.g. 50% advance)'], [warranty, setWarranty, lang === 'ar' ? 'الضمان (مثلاً سنة واحدة)' : 'Warranty (e.g. 1 year)']].map(([v, sv, ph], k) => <Lbl key={k} className="flex-1 min-w-beat-l" text={ph}><Input placeholder={ph} value={v} onChange={(e) => sv(e.target.value)} /></Lbl>)}</div>
    <div className="border-t border-border pt-4">
      <div className={cn(grp, 'mb-1')}>{ar ? 'بنود العرض' : 'Line items'}</div>
      <div className={cn(S.sub, 'mb-2')}>{lang === 'ar' ? 'بنود العرض (الوصف والكمية والسعر)، وبها يصبح عرضكم جاهزًا للإرسال' : 'Quote items (description, qty, price) — makes your quote ready to send'}</div>
      <div className="overflow-x-auto"><div className="min-w-[460px]">
      {items.map((it, ix) => (<div key={ix} className="flex gap-1.5 mb-1.5 items-center">
        <Lbl className="flex-1" text={(lang === 'ar' ? 'الوصف، البند ' : 'Description, line ') + (ix + 1)}><Input placeholder={lang === 'ar' ? 'الوصف' : 'Description'} value={it.description} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, description: e.target.value } : r))} /></Lbl>
        <Lbl text={(lang === 'ar' ? 'الكمية، البند ' : 'Quantity, line ') + (ix + 1)}><Input className="tabular font-mono text-end" style={{ maxWidth: 72 }} inputMode="decimal" placeholder={lang === 'ar' ? 'كمية' : 'Qty'} value={it.qty} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, qty: e.target.value } : r))} /></Lbl>
        <Lbl text={(lang === 'ar' ? 'الوحدة، البند ' : 'Unit, line ') + (ix + 1)}><Input style={{ maxWidth: 72 }} placeholder={lang === 'ar' ? 'وحدة' : 'Unit'} value={it.unit} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, unit: e.target.value } : r))} /></Lbl>
        <Lbl text={(lang === 'ar' ? 'سعر الوحدة، البند ' : 'Unit price, line ') + (ix + 1)}><Input className="tabular font-mono text-end" style={{ maxWidth: 104 }} inputMode="decimal" placeholder={lang === 'ar' ? 'سعر الوحدة' : 'Unit price'} value={it.unit_price} onChange={(e) => setItems(items.map((r, i) => i === ix ? { ...r, unit_price: e.target.value } : r))} /></Lbl>
        <Button size="sm" variant="outline" aria-label={(lang === 'ar' ? 'حذف البند ' : 'Remove line ') + (ix + 1)} onClick={() => setItems(items.length > 1 ? items.filter((_, i) => i !== ix) : [{ description: '', qty: '', unit: '', unit_price: '' }])}>×</Button>
      </div>))}
      </div></div>
      <div className="mt-1 flex flex-wrap items-center justify-between gap-2">
        <Button size="sm" variant="outline" onClick={() => setItems([...items, { description: '', qty: '', unit: '', unit_price: '' }])}>{lang === 'ar' ? '+ إضافة بند' : '+ Add item'}</Button>
        {lineSum > 0 && <div className="flex items-baseline gap-3 rounded-chip border border-border px-3 py-1.5">
          <span className={grp}>{ar ? 'مجموع البنود المسعّرة' : 'Sum of priced lines'}</span>
          <span className="tabular font-mono text-[14px] font-semibold text-foreground">{aed(lang, lineSum)}</span>
        </div>}
      </div>
    </div>
    <div className={cn(grp, 'border-t border-border pt-4 -mb-2')}>{ar ? 'النطاق والملاحظات' : 'Scope and notes'}</div>
    <Lbl text={t(lang, 'scope_work')}><textarea className={S.area} placeholder={t(lang, 'scope_work')} value={scope} onChange={(e) => setScope(e.target.value)} rows={2} /></Lbl>
    <Lbl text={t(lang, 'notes_customer')}><textarea className={S.area} placeholder={t(lang, 'notes_customer')} value={notes} onChange={(e) => setNotes(e.target.value)} rows={2} /></Lbl>
    {chk && <QuoteCheck chk={chk} lang={lang} />}
    <div className="flex gap-2 items-center flex-wrap justify-end border-t border-border pt-4">
      <Button size="sm" variant="secondary" disabled={checking || busy || reading} onClick={check}>
        {checking ? (lang === 'ar' ? 'جارٍ الفحص…' : 'Checking…') : (lang === 'ar' ? 'الفحص قبل الإرسال' : 'Check before sending')}
      </Button>
      {/* Not while the check runs (up to 90 s): the dry run restores or deletes the quote row when it ends
          (supplier_api/actions/quotes.ts), which would undo a quote submitted meanwhile (review of 12 Nov 2026). */}
      <Button size="sm" disabled={checking || busy || reading} onClick={submit}>{busy ? t(lang, 'submitting') : t(lang, 'submit_quote')}</Button>
    </div>
    {msg && <div className={cn(S.sub, 'mt-1.5')}>{msg}</div>}
  </div>;
}
// Result of the dry_run preflight.
//
// Two things are shown that the product never surfaced before sending:
//   1. the structured score against the 70 pass mark, and
//   2. WHY the quote would be accepted — because passing via `form_complete` at 65 is not the
//      same as passing the quality bar, and telling a supplier only "this will send" hides that
//      their quote reaches the customer without per-item pricing or brand/model.
// Missing codes come straight from fn_quote_structured_score, so this panel and the email a
// supplier might receive later cannot disagree with each other.
function QuoteCheck({ chk, lang }) {
  const ar = lang === 'ar';
  const sc = chk.score || {}; const pts = sc.score ?? 0; const pass = 70;
  const missing = Array.isArray(sc.missing) ? sc.missing : [];
  const viaForm = chk.accept_via === 'form_complete' && !chk.submittable;
  return (
    <Card className="qd-panel p-4 mt-1">
      <div className="flex justify-between items-baseline gap-3 flex-wrap">
        <div className="text-[13.5px] font-bold text-foreground">{ar ? 'جاهزية العرض' : 'Quote readiness'}</div>
        <div className="text-[13px] font-bold tabular-nums text-foreground">{pts}<span className="text-muted-foreground font-semibold">/100</span></div>
      </div>
      <div className="mt-1.5 h-2 rounded-full bg-secondary/50 overflow-hidden relative">
        <div className={cn('h-full rounded-full transition-[width] duration-700 motion-reduce:transition-none', pts >= pass ? 'bg-primary' : 'bg-warn')}
             style={{ width: Math.max(2, Math.min(100, pts)) + '%' }} />
        {/* the 70 pass mark, shown so the number has meaning */}
        <div className="absolute top-0 bottom-0 w-px bg-foreground/40" style={{ left: pass + '%' }} aria-hidden="true" />
      </div>
      {/* A quote below 70 can still be sent (accept_via form_complete), so 70 is the QUALITY mark, not a
          pass mark: "Pass mark is 70" beside "This will be sent" read as a contradiction (audit 21 Sep 2026, finding 15). */}
      <div className={cn(S.sub, 'mt-1.5')}>{ar ? 'علامة الجودة 70 — العرض الأقوى للمقارنة' : 'Quality mark is 70 — the strongest quotes to compare'}</div>

      {chk.would_accept
        ? <div className="mt-2.5">
            <Badge variant={chk.submittable ? 'ok' : 'warn'}>{viaForm ? (ar ? 'سيُرسل إلى العميل — دون علامة الجودة' : 'This will be sent to the customer — below the quality mark') : (ar ? 'سيُرسل إلى العميل' : 'This will be sent to the customer')}</Badge>
            {viaForm && <div className={cn(S.sub, 'mt-1.5')}>{ar
              ? 'سيُقبل لأن الحقول الأساسية مكتملة، لكنه لم يبلغ علامة الجودة. وإضافة ما يلي تجعل عرضكم أسهل للمقارنة وأقوى أمام العميل.'
              : 'It is accepted because the essential fields are filled, but it has not reached the quality mark. Adding the items below makes your quote easier to compare and stronger against competing bids.'}</div>}
          </div>
        : <div className="mt-2.5">
            <Badge variant="destructive">{ar ? 'سيُحفظ كمسودة' : 'This will be saved as a draft'}</Badge>
            <div className={cn(S.sub, 'mt-1.5')}>{ar ? 'لن يصل إلى العميل حتى تُكملوا ما يلي.' : 'It will not reach the customer until the items below are added.'}</div>
          </div>}

      {!!missing.length && <ul className="mt-2.5 flex flex-col gap-1">
        {missing.map((m, i) => <li key={i} className="flex items-start gap-2">
          <span className="mt-[7px] h-1.5 w-1.5 rounded-full bg-warn shrink-0" />
          <span className="text-[13px] text-foreground">{missingLabel(lang, m)}</span>
        </li>)}
      </ul>}
      {!missing.length && !(chk.spec_missing && chk.spec_missing.length) && <div className={cn(S.sub, 'mt-2.5')}>{ar ? 'لا ينقص شيء. عرض مكتمل.' : 'Nothing missing — this is a complete quote.'}</div>}
      {Array.isArray(chk.spec_missing) && chk.spec_missing.length > 0 && <div className="mt-2.5 border-t border-border pt-2.5">
        <div className="text-[13px] font-semibold text-foreground">{ar ? 'سيُعلّق مهندس المبيعات العرض حتى تُذكر هذه التفاصيل الدقيقة:' : 'The sales engineer will hold this quote until these exact details are stated:'}</div>
        <ul className="mt-1.5 flex flex-col gap-1">{chk.spec_missing.map((m, i) => <li key={i} className="flex items-start gap-2 text-[13px] text-foreground"><span aria-hidden className="mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full bg-warn" />{m.scope === 'line' ? (ar ? `البند ${m.line_no}: ` : `Line ${m.line_no}: `) : ''}{ar ? m.label_ar : m.label_en}</li>)}</ul>
      </div>}
      {Array.isArray(chk.options) && chk.options.length > 1 && <div className={cn(S.sub, 'mt-2.5')}>{srvText(lang, 'options_split', { count: chk.options.length })}</div>}
      {chk.total_items != null && <div className={cn(S.sub, 'mt-2.5 pt-2.5 border-t border-border')}>
        {ar ? `${chk.priced_items} من ${chk.total_items} بند مُسعّر` : `${chk.priced_items} of ${chk.total_items} line items priced`}
      </div>}
    </Card>
  );
}
export { QuoteForm };
