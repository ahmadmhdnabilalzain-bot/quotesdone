// @ts-nocheck
'use client';
import { useEffect, useState, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { categoryLabel } from '@/lib/categoryLabel';
import { DiscoveryReachPanel } from '@/components/portal/suppliers/SupplierRelationship';
import { StatusPill } from '../PortalShell';
import { ChevronDown } from 'lucide-react';
import { Clarifications } from '../Clarifications';
import { MissingSpecs } from '../MissingSpecs';
import { SpecOffer } from '../SpecOffer';
import { useConfirm } from '../ConfirmDialog';
import { useReducedMotion } from 'motion/react';
import { t, tf, errText, emirateName } from '../portalText';
import { countPhrase } from '@/lib/countedNoun';
import { call } from '../api';
import { stateOf, ratingScoreOf, EMIRATES } from '../format';
import { S } from '../styles';
import { LevelledRows, Comparison } from './Comparison';
import { QuoteCard } from './QuoteCard';
import { Timeline, RequestTracker, QuoteSpread } from './Progress';
import { DetailFacts } from './DetailFacts';
import { SeparateQuotesAsk } from './SeparateQuotesAsk';

function InquiryCard({ inq, token, onChange, lang, terms, focusQuote, focusInq, linkQuote }) {
  if (inq.is_combined && Array.isArray(inq.children)) { return (<Card id={'inq-' + inq.id} className="p-4 mb-3.5 border-primary/30"><div className="flex items-center gap-2 flex-wrap mb-1"><span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-primary/10 text-primary">{lang === 'ar' ? 'مشروع متعدد التخصصات' : 'Combined project'}</span><span className={S.sub}>{lang === 'ar' ? ((inq.children.length === 2 ? 'طلبان منفصلان' : inq.children.length + (inq.children.length <= 10 ? ' طلبات منفصلة' : ' طلبًا منفصلًا')) + ' إلى موردين متخصصين') : (inq.children.length + ' separate requests to specialist suppliers')}</span></div>{inq.summary ? <div className={cn(S.sub, 'mb-2')}>{inq.summary}</div> : null}<div className="space-y-2.5">{inq.children.map((c) => <InquiryCard key={c.id} inq={c} token={token} onChange={onChange} lang={lang} terms={terms} focusQuote={focusQuote} focusInq={focusInq} linkQuote={linkQuote} />)}</div></Card>); }
  // Opened by the quote a payment was for (focusQuote) or by any control that asked to open THIS
  // request by id (focusInq — Dashboard's openRfq). The id is the same inquiries.id every caller holds.
  // linkQuote — the quote a /me?request=&quote= link named — scrolls to its own card (QuoteCard), so
  // this card does not scroll to its top over it.
  const linkHere = !!linkQuote && (inq.quotes || []).some((q) => q.id === linkQuote);
  const hasFocus = linkHere || (!!focusQuote && (inq.quotes || []).some((q) => q.id === focusQuote)) || (!!focusInq && String(inq.id) === String(focusInq));
  const [open, setOpen] = useState(hasFocus);
  const cardRef = useRef(null);
  const reduceMotion = useReducedMotion();
  useEffect(() => {
    if (!hasFocus) return;
    setOpen(true);
    if (linkHere) return;
    try { if (cardRef.current) cardRef.current.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'start' }); } catch (_e) {}
  }, [hasFocus]);
  const [canceling, setCanceling] = useState(false);
  const [editing, setEditing] = useState(false);
  const [eSummary, setESummary] = useState(inq.summary || '');
  const [eBudget, setEBudget] = useState(inq.budget || '');
  const [eEmirate, setEEmirate] = useState(inq.emirate || '');
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const [dialog, ask] = useConfirm(lang);
  const quotes = (inq.quotes || []).slice().sort((a, b) => (a.price || 0) - (b.price || 0));
  const concluded = ['completed', 'closed', 'cancelled'].includes(String(inq.status));
  const anyRevealed = quotes.some((qq) => qq.revealed);
  const vmap = (() => { const m = {}; if (!quotes.length) return m; const ps = quotes.map((q) => Number(q.price) || 0).filter((p) => p > 0); const minP = ps.length ? Math.min(...ps) : 0, maxP = ps.length ? Math.max(...ps) : 0; for (const q of quotes) { const p = Number(q.price) || 0; const priceScore = (!p || maxP === minP) ? 70 : Math.round(100 - ((p - minP) / (maxP - minP)) * 55); const ratingScore = ratingScoreOf(q.rating); const compScore = Math.min(100, 50 + (q.scope ? 20 : 0) + (q.warranty ? 10 : 0) + (q.lead_time ? 10 : 0) + (q.verified ? 10 : 0)); m[q.id] = ratingScore == null ? Math.round((priceScore * 0.5 + compScore * 0.2) / 0.7) : Math.round(priceScore * 0.5 + ratingScore * 0.3 + compScore * 0.2); } return m; })();
  // "Best value" is a comparison; with one quote there is nothing it beat (audit 21 Sep 2026, item 27).
  const bestId = quotes.length >= 2 ? quotes.slice().sort((a, b) => (vmap[b.id] || 0) - (vmap[a.id] || 0))[0].id : null;
  // window.confirm was an English-only browser box (audit 14 Sep 2026); useConfirm is in-page and bilingual.
  const doCancel = async (e) => { e.stopPropagation(); if (canceling) return; if (!(await ask(t(lang, 'rc_cancel_confirm'), { title: t(lang, 'rc_cancel'), confirm: t(lang, 'rc_cancel'), danger: true }))) return; setCanceling(true); setErr(''); try { const j = await call('customer_api', { action: 'cancel_inquiry', inquiry_id: inq.id }, token); if (j && j.ok) { onChange(); } else { setErr(errText(j, lang, 'rc_cancel_fail')); setCanceling(false); } } catch (_e) { setErr(t(lang, 'rc_cancel_fail')); setCanceling(false); } };
  const [repeating, setRepeating] = useState(false);
  const [repeated, setRepeated] = useState('');
  // REPEAT (founder_instruction 1028): one click opens the same specs as an editable copy; nothing is posted until
  // the customer presses Post. The server checks the copy can be posted before it shows it (preview).
  const [rDraft, setRDraft] = useState(null);
  const openRepeat = async (e) => { e.stopPropagation(); if (repeating) return; setRepeating(true); setErr(''); setRepeated(''); try { const j = await call('customer_api', { action: 'repeat_inquiry', inquiry_id: inq.id, preview: true }, token); if (j && j.ok && j.draft) { setRDraft({ summary: j.draft.summary || '', budget: j.draft.budget || '', emirate: j.draft.emirate || '', required_by: j.draft.required_by || '' }); } else { setErr(j && j.error === 'nothing_to_repeat' ? t(lang, 'rc_repeat_nothing') : errText(j, lang, 'rc_repeat_fail')); } } catch (_e) { setErr(t(lang, 'rc_repeat_fail')); } setRepeating(false); };
  // busy-exempt: setRepeating is the busy state; it disables the Post button and shows rc_repeating while it waits.
  const postRepeat = async () => { if (repeating || !rDraft) return; setRepeating(true); setErr(''); try { const j = await call('customer_api', { action: 'repeat_inquiry', inquiry_id: inq.id, edits: rDraft }, token); if (j && j.ok) { setRDraft(null); setRepeated(t(lang, 'rc_repeat_done')); onChange(); } else { setErr(j && j.error === 'nothing_to_repeat' ? t(lang, 'rc_repeat_nothing') : errText(j, lang, 'rc_repeat_fail')); } } catch (_e) { setErr(t(lang, 'rc_repeat_fail')); } setRepeating(false); };
  const saveEdit = async () => { setSaving(true); setErr(''); try { const j = await call('customer_api', { action: 'edit_inquiry', inquiry_id: inq.id, patch: { summary: eSummary, budget: eBudget || null, emirate: eEmirate || null } }, token); if (j && j.ok) { setEditing(false); onChange(); } else { setErr(errText(j, lang, 'rc_save_fail')); } } catch (_e) { setErr(t(lang, 'rc_save_fail')); } setSaving(false); };
  return (<Card ref={cardRef} id={'inq-' + inq.id} className={cn('scroll-mt-20 p-4 shadow-e1 transition-[border-color,box-shadow] duration-300 hover:border-primary/30 hover:shadow-e2 sm:p-5', open && 'border-primary/25 shadow-e2')}>{dialog}
    {/* A11Y (5 Aug 2026): role+tabIndex+onKeyDown rather than a <button>, because this wraps <div>
        children and <div> inside <button> is an invalid content model. */}
    <div className="flex justify-between items-center gap-2.5 cursor-pointer rounded-md focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring" onClick={() => setOpen(!open)}
      role="button" tabIndex={0} aria-expanded={open}
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setOpen(!open); } }}>
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-2">
          <StatusPill state={stateOf(inq, quotes)} t={(k) => t(lang, k)} />
          <b className="font-head text-[15px] font-semibold tracking-snug">{inq.category ? categoryLabel(inq.category, lang) : t(lang, 'rc_request')}</b>
          {inq.rfq_no ? <span className="tabular rounded-chip border border-border bg-secondary/40 px-1.5 py-0.5 font-mono text-label text-muted-foreground">{inq.rfq_no}</span> : null}
        </div>
        {/* Emirate and the quote count stay separate spans: the Row #4 blueprint asserts each. */}
        <div className={cn(S.sub, 'mt-1 flex flex-wrap items-center gap-x-1.5')}>
          {inq.emirate ? <span>{emirateName(inq.emirate, lang)}</span> : null}
          {inq.emirate ? <span aria-hidden className="text-muted-foreground/40">·</span> : null}
          <span>{quotes.length} {t(lang, quotes.length === 1 ? 'rc_quote_one' : 'rc_quote_many')}</span>
          {(inq.boq && inq.boq.boq) ? <><span aria-hidden className="text-muted-foreground/40">·</span><span>{countPhrase(lang, inq.boq.boq.length, 'line')}</span></> : null}
          {inq.editable ? <><span aria-hidden className="text-muted-foreground/40">·</span><span>{tf(lang, 'rc_editable', { m: inq.edit_minutes_left })}</span></> : null}
        </div>
      </div>
      <div className="flex shrink-0 items-center gap-1 text-primary font-semibold text-[13px]">
        <span className="hidden sm:inline">{open ? t(lang, 'rc_hide') : t(lang, 'rc_open')}</span>
        <ChevronDown className={cn('h-4 w-4 transition-transform duration-300', open && 'rotate-180')} aria-hidden />
      </div>
    </div>
    {inq.summary && !editing && <div className={cn(S.sub, 'mt-1.5')}>{inq.summary}</div>}
    {editing && <div className="mt-2">
      <label className="sr-only" htmlFor={'qd-edit-' + inq.id}>{t(lang, 'rc_describe')}</label>
      <textarea id={'qd-edit-' + inq.id} className={S.area} rows={3} value={eSummary} onChange={(e) => setESummary(e.target.value)} placeholder={t(lang, 'rc_describe')} />
      <div className={S.frow}>
        {/* Theme tokens, not the hard-coded navy this select carried into the light theme. */}
        <select className={cn(S.field, 'bg-background')} aria-label={t(lang, 'rc_emirate_opt')} value={eEmirate} onChange={(e) => setEEmirate(e.target.value)}><option value="">{t(lang, 'rc_emirate_opt')}</option>{EMIRATES.map((em) => <option key={em} value={em}>{emirateName(em, lang)}</option>)}</select>
        <Input aria-label={t(lang, 'rc_budget_opt')} placeholder={t(lang, 'rc_budget_opt')} value={eBudget} onChange={(e) => setEBudget(e.target.value)} />
      </div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5">
        <Button disabled={saving} onClick={(e) => { e.stopPropagation(); saveEdit(); }}>{saving ? t(lang, 'rc_saving') : t(lang, 'rc_save')}</Button>
        <Button variant="link" className="px-0 h-auto" onClick={(e) => { e.stopPropagation(); setEditing(false); setErr(''); }}>{t(lang, 'rc_cancel_edit')}</Button>
      </div>
    </div>}
    {!concluded && !anyRevealed && !editing && <div className="flex gap-2.5 flex-wrap items-center mt-2">
      {inq.editable && <Button variant="link" className="px-0 h-auto" onClick={(e) => { e.stopPropagation(); setESummary(inq.summary || ''); setEBudget(inq.budget || ''); setEEmirate(inq.emirate || ''); setEditing(true); }}>{t(lang, 'rc_edit')}</Button>}
      <Button variant="link" className="px-0 h-auto text-danger" disabled={canceling} onClick={doCancel}>{canceling ? t(lang, 'rc_cancelling') : t(lang, 'rc_cancel')}</Button>
    </div>}
    {/* REPEAT IN ONE CLICK (founder_instruction 1028): the same specs posted again as a new request, through the
        same posting door (customer_api repeat_inquiry -> create_inquiry). */}
    {!editing && !rDraft && <div className="flex gap-2.5 flex-wrap items-center mt-1">
      <Button variant="link" className="px-0 h-auto" disabled={repeating} onClick={openRepeat}>{repeating ? t(lang, 'rc_repeating') : t(lang, 'rc_repeat')}</Button>
      {repeated ? <span className={S.sub} role="status">{repeated}</span> : null}
    </div>}
    {rDraft && <div className="mt-2" onClick={(e) => e.stopPropagation()}>
      <div className={S.sub}>{t(lang, 'rc_repeat_confirm')}</div>
      <label className="sr-only" htmlFor={'qd-rep-' + inq.id}>{t(lang, 'rc_describe')}</label>
      <textarea id={'qd-rep-' + inq.id} className={S.area} rows={3} value={rDraft.summary} onChange={(e) => setRDraft({ ...rDraft, summary: e.target.value })} placeholder={t(lang, 'rc_describe')} />
      <div className={S.frow}>
        <select className={cn(S.field, 'bg-background')} aria-label={t(lang, 'rc_emirate_opt')} value={rDraft.emirate} onChange={(e) => setRDraft({ ...rDraft, emirate: e.target.value })}><option value="">{t(lang, 'rc_emirate_opt')}</option>{EMIRATES.map((em) => <option key={em} value={em}>{emirateName(em, lang)}</option>)}</select>
        <Input aria-label={t(lang, 'rc_budget_opt')} placeholder={t(lang, 'rc_budget_opt')} value={rDraft.budget} onChange={(e) => setRDraft({ ...rDraft, budget: e.target.value })} />
        <Input type="date" aria-label={t(lang, 'rc_repeat_date')} title={t(lang, 'rc_repeat_date')} value={rDraft.required_by} onChange={(e) => setRDraft({ ...rDraft, required_by: e.target.value })} />
      </div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5">
        <Button disabled={repeating || !rDraft.summary.trim()} onClick={postRepeat}>{repeating ? t(lang, 'rc_repeating') : t(lang, 'rc_repeat_post')}</Button>
        <Button variant="link" className="px-0 h-auto" onClick={() => { setRDraft(null); setErr(''); }}>{t(lang, 'rc_cancel_edit')}</Button>
      </div>
    </div>}
    {err && <div className={S.err} role="alert">{err}</div>}
    <RequestTracker inq={inq} quotes={quotes} lang={lang} />
    {/* No supplier could quote the exact spec (founder_instruction #321): the customer picks an
        alternative or says no. OUTSIDE the collapsible details on purpose — a question the customer
        has to open the card to find is a question that goes unanswered, and the reply window runs. */}
    {inq.spec_offers && inq.spec_offers.length ? <div className="mt-3"><SpecOffer inq={inq} token={token} lang={lang} call={call} onDone={onChange} /></div> : null}
    {/* Held for its specs (rfq_ready false on an open request): the missing fields, outside the collapsible for the
        same reason as the offer above. Asked only of a request the hold check has not passed. */}
    {inq.rfq_ready === false && !['cancelled', 'closed', 'completed'].includes(String(inq.status)) ? <div className="mt-3"><MissingSpecs inq={inq} token={token} lang={lang} call={call} onChange={onChange} /></div> : null}
    {open && <div className="mt-3 border-t border-border pt-3 flex flex-col gap-3">
      <Timeline inq={inq} quotes={quotes} anyRevealed={anyRevealed} lang={lang} />
      <QuoteSpread quotes={quotes} lang={lang} />
      {/* Questions and additions. The customer's follow-up reaches the RFQ (customer_api rfq_note)
          and suppliers' pre-reveal questions can be answered (messages_api clarify_*). Replaces
          RfqAssistant, whose inquiry_intake call ignored inquiry_id (audit 14 Sep 2026, BROKEN). */}
      <Clarifications inq={inq} token={token} lang={lang} call={call} />
      <DetailFacts inq={inq} lang={lang} />
      {quotes.length >= 2 && <Comparison inqId={inq.id} token={token} lang={lang} />}
      {/* reached===0 is its own outcome here, never encouragement: matched_suppliers says which. */}
      <DiscoveryReachPanel inquiry={inq} lang={lang === 'ar' ? 'ar' : 'en'} />
      {/* A request for one contractor that no single contractor matched: the customer is asked whether they want
          separate quotes per trade (finding c of 10 Nov 2026; rulings 1021, 1025). Never split without their answer. */}
      {inq.separate_quotes && !(Number(inq.matched_suppliers) > 0) ? <SeparateQuotesAsk inquiryId={inq.id} specialists={Number(inq.separate_quotes.specialists) || 0} lang={lang} token={token} call={call} onPosted={() => onChange()} /> : null}
      {quotes.length > 0
        // THE LEVELLED FRAME. Every quote the request received — not a shortlist — side by side on the
        // same columns, then each one in full with its own reveal. Identities stay sealed until paid.
        ? <section className="overflow-hidden rounded-card border border-border bg-card shadow-e1" aria-label={tf(lang, 'rc_quotes_received', { n: quotes.length })}>
            <div className="flex h-10 items-center gap-2.5 border-b border-border bg-secondary/40 px-3.5">
              <span className="hidden gap-1.5 sm:flex" aria-hidden><i className="h-2 w-2 rounded-full bg-primary/25" /><i className="h-2 w-2 rounded-full bg-primary/25" /><i className="h-2 w-2 rounded-full bg-primary/25" /></span>
              <div className="min-w-0 truncate font-mono text-label text-foreground">{tf(lang, 'rc_quotes_received', { n: quotes.length })}</div>
              <Badge variant={anyRevealed ? 'revealed' : 'sealed'} dot className={cn('ms-auto shrink-0', anyRevealed && 'text-accent!')}>{t(lang, anyRevealed ? 'lv_open' : 'lv_sealed')}</Badge>
            </div>
            <LevelledRows quotes={quotes} vmap={vmap} bestId={bestId} lang={lang} />
            {/* A quote withheld with no word said is its own defect: my_inquiries counts the ones
                on hold for missing details (audit CP-01) and the customer is told they exist. */}
            {Number(inq.on_hold) > 0 ? <div className={cn(S.sub, 'border-t border-border px-2.5 pt-2 text-muted-foreground sm:px-3')}>{tf(lang, 'rc_on_hold', { n: Number(inq.on_hold) })}</div> : null}
            <div className="flex flex-col gap-2.5 border-t border-border p-2.5 sm:p-3">{quotes.map((q) => <QuoteCard key={q.id} q={q} token={token} lang={lang} concluded={concluded} onChange={onChange} vscore={vmap[q.id]} best={q.id === bestId} hired={inq.hired_supplier_id} terms={terms} focus={q.id === focusQuote} highlight={q.id === linkQuote} />)}</div>
          </section>
        : null}
    </div>}
  </Card>);
}
export { InquiryCard };
