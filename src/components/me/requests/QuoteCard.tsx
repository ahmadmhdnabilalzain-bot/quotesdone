// @ts-nocheck
'use client';
import { useEffect, useState, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { Seal } from '@/components/ui/sealed';
import { useDelayedFlag, Spinner } from '@/components/ui/busy';
import { cn } from '@/lib/utils';
import { durationLabel } from '@/lib/durationLabel';
import { SupplierRelationshipCard } from '@/components/portal/suppliers/SupplierRelationship';
import { RevealPayment } from '../RevealPayment';
import { Lock } from 'lucide-react';
// expires_at / expired were served on every quote and never shown. The branch that phrases them
// decides whether a customer pays a reveal fee on a lapsed price, so it lives in a file that can be
// executed — see quoteExpiry.test.mjs — rather than inline in this one.
import { expiryOf } from '../quoteExpiry';
import { RevealGuarantee } from '../RevealGuarantee';
import { QuoteBadges } from '@/components/QuoteBadges';
import { useConfirm } from '../ConfirmDialog';
import * as M from 'motion/react-m';
import { useReducedMotion } from 'motion/react';
import { t, tf, errText } from '../portalText';
import { call } from '../api';
import { aed, supLabel } from '../format';
import { S } from '../styles';
import { Contact } from './Contact';
import { QuotePdfLink, InvoicePdfLink } from './QuoteDocs';

// The three lines the invoice prints, shown before the customer pays.
function FeeBreakdown({ r, price, lang }) {
  if (!r || r.total_charged == null) return null;
  const row = (k, v, strong = false) => (<div className={cn('flex justify-between gap-4', strong && 'font-semibold text-foreground border-t border-border pt-1')}><span>{k}</span><span className="tabular font-mono">{v}</span></div>);
  return (<div className="mb-3 rounded-md border border-border bg-secondary/20 p-3 text-[12.5px] text-muted-foreground">
    {row(tf(lang, 'q_bd_fee', { price }), aed(r.reveal_fee))}
    {row(t(lang, 'q_bd_proc'), aed(0))}
    {row(t(lang, 'q_bd_total'), aed(r.total_charged), true)}
    <div className="mt-1.5 text-[11.5px]">{t(lang, 'q_bd_refund')}</div>
  </div>);
}
function QuoteCard({ q, token, concluded, onChange, vscore, best, lang, hired, terms, focus, highlight }) {
  const [state, setState] = useState(q.revealed ? 'revealed' : 'idle'); const [contact, setContact] = useState(null); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const [dialog, ask] = useConfirm(lang);
  const [paying, setPaying] = useState(false);
  // The Stripe redirect is a navigation, not a request that comes back: `leaving` only changes what
  // the (still busy) button says, so the last thing the customer sees is "Taking you to payment…".
  const [leaving, setLeaving] = useState(false);
  const revealSpin = useDelayedFlag(busy);
  const reduce = useReducedMotion();
  // THE REVEAL MOMENT: the redaction bar lifts off the supplier the first time the customer sees
  // them — in this session, or on the return from Stripe (focus). Once; a later visit is plain.
  const [justRevealed, setJustRevealed] = useState(!!focus && !!q.revealed);
  // The quote a deep link named: scrolled to the middle of the screen and ringed for a moment, so
  // the eye lands on it. With reduced motion the jump is instant and the ring does not animate.
  const hlRef = useRef(null); const [lit, setLit] = useState(false);
  useEffect(() => {
    if (!highlight) return;
    try { if (hlRef.current) hlRef.current.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'center' }); } catch (_e) {}
    setLit(true); const id = setTimeout(() => setLit(false), 2600); return () => clearTimeout(id);
  }, [highlight]);
  // Warn, do not block: an expired price is still a supplier worth contacting.
  const exp = expiryOf(q, lang);
  const w = terms && terms.window_days, c = terms && terms.chase_after_days;
  const revealedFacts = (r) => !!(r && r.already_revealed && r.supplier);
  const unlock = (r) => {
    if (!revealedFacts(r)) { setState('settling'); return false; }
    setContact({ supplier: r.supplier }); setState('revealed'); setJustRevealed(true); return true;
  };
  // The settling card's own button: one more ask, no reload, no second payment.
  const [recheckBusy, setRecheckBusy] = useState(false);
  const checkReveal = async () => {
    setRecheckBusy(true);
    unlock(await call('customer_api', { action: 'reveal', quote_id: q.id }, token));
    setRecheckBusy(false);
  };
  const reveal = async () => {
    setBusy(true); setMsg('');
    const r = await call('customer_api', { action: 'reveal', quote_id: q.id }, token).catch(() => null);
    if (!r || r.error) { setBusy(false); setMsg(errText(r, lang)); return; }
    if (r.already_revealed) { unlock(r); setBusy(false); return; }
    setBusy(false);
    const fee = aed(r.reveal_fee ?? q.reveal_fee);
    // The Reveal Guarantee is shown at the moment of payment, not only as a line under the button.
    // 3% plus card processing (founder, 14 Sep 2026): the breakdown is customer_api's, computed by
    // the same _shared/reveal_fee.ts stripe_checkout charges, so the dialog and Stripe cannot differ.
    const total = aed(r.total_charged ?? r.reveal_fee ?? q.reveal_fee);
    const go = await ask(tf(lang, 'q_confirm_body', { fee, total, price: aed(q.price) }), { title: t(lang, 'q_confirm_title'), confirm: t(lang, 'q_confirm_pay'), reveal: true, children: <><FeeBreakdown r={r} price={aed(q.price)} lang={lang} /><RevealGuarantee lang={lang} fee={total} terms={terms} compact /></> });
    if (!go) return;
    // The Payment Element prices the card actually used (RevealPayment). The Checkout Session below
    // is its fallback when the element cannot load, charged at the safest rate.
    setPaying(true);
  };
  const checkoutFallback = async () => {
    setPaying(false); setBusy(true);
    // /ar/me for an Arabic customer, so the Stripe return lands in their language; stripe_checkout
    // keeps any path that already ends in /me.
    const cr = await call('stripe_checkout', { quote_id: q.id, return_url: location.origin + (lang === 'ar' ? '/ar/me' : '/me') }, token).catch(() => null);
    if (cr && cr.already_revealed) { unlock(await call('customer_api', { action: 'reveal', quote_id: q.id }, token).catch(() => null)); setBusy(false); return; }
    // NOT setBusy(false): the browser is leaving this page. Clearing it here would put the button
    // back to "Reveal & contact" for the seconds Stripe takes to load, inviting a second press.
    if (cr && cr.url) { setLeaving(true); location.href = cr.url; return; }
    // stripe_checkout answers {error:'stripe_not_configured'} at HTTP 200; errText says it in words.
    setBusy(false); setMsg(errText(cr, lang, 'q_checkout_fail'));
  };
  // A revealed quote whose contact the server will not hand over yet (the payment is still
  // settling) used to leave the redaction bar and "loading contact" spinning with no way forward.
  // It falls back to the settling card, which says why and carries the Check again button.
  const showContactData = async () => {
    const r = await call('customer_api', { action: 'reveal', quote_id: q.id }, token).catch(() => null);
    if (r && r.supplier) setContact({ supplier: r.supplier });
    else setState('settling');
  };
  const settling = state === 'settling';
  useEffect(() => { if (state === 'revealed' && !contact) showContactData(); }, [state]);
  // THE SERVER IS THE ONE THAT KNOWS. `state` is seeded from q.revealed on mount and was never
  // re-read, so a reveal confirmed by the minute poll (my_inquiries flips q.revealed) left the card
  // sitting on 'settling' until the customer reloaded — the copy promises it opens by itself.
  useEffect(() => { if (q.revealed && state !== 'revealed') setState('revealed'); }, [q.revealed]);
  const revealed = state === 'revealed';
  return (<div ref={hlRef} id={'quote-' + q.id} className={cn('scroll-mt-24 rounded-card border p-3.5 transition-colors duration-500 sm:p-4', lit && 'ring-2 ring-primary ring-offset-2 ring-offset-background', revealed ? 'border-accent/40 bg-accent/4' : best ? 'border-primary/35 bg-primary/3' : 'border-border bg-secondary/15')}>{dialog}
    <div className="flex items-center justify-between gap-3">
      <div className="min-w-0"><b className="font-head font-semibold tracking-snug">{supLabel(q.label, lang)}</b>{!revealed ? <span aria-hidden className="ms-2 inline-block align-middle leading-none"><Seal className="text-[11px]">{'••••••••••'}</Seal></span> : null}{best ? <span className="ms-1.5 rounded-chip border border-primary/30 bg-primary/12 px-1.5 py-0.5 align-middle font-mono text-[10px] font-semibold text-primary">{t(lang, 'q_best')}</span> : null}{q.verified ? <span className="text-[11px] font-bold text-primary"> ✓ {t(lang, 'q_verified')}</span> : null}{q.rating != null ? <span className="text-[12px] font-semibold text-accent"> ★ {q.rating}{q.rating_count != null ? ' (' + q.rating_count + ')' : ''}</span> : <span className="text-[11px] text-muted-foreground" title={t(lang, 'q_unrated_tip')}> {t(lang, 'q_unrated')}</span>}</div>
      <div className="shrink-0 text-end"><div className="tabular font-mono text-[18px] font-semibold text-foreground">{aed(q.price)}</div>{vscore != null ? <div className="tabular font-mono text-[10.5px] text-muted-foreground" title={t(lang, 'q_value_tip')}>{t(lang, 'q_value')} {vscore}/100</div> : null}</div>
    </div>
    <div className="mt-0.5 text-[11.5px] text-muted-foreground">{[q.lead_time ? t(lang, 'q_lead') + ': ' + q.lead_time : '', q.warranty ? t(lang, 'q_warranty') + ': ' + durationLabel(q.warranty, lang) : '', q.payment_terms ? t(lang, 'q_terms') + ': ' + q.payment_terms : '', q.win_rate != null ? t(lang, 'q_win') + ' ' + Math.round(q.win_rate) + '%' : ''].filter(Boolean).join(' · ')}</div>
    {/* W9: anonymous facts about the supplier, served per quote; each badge hides when its value is absent. */}
    {/* Rulings 1207/1208: the supplier's price exactly as stated ("AED 2,000, after discount AED 1,700") and its VAT as
        stated, served by my_inquiries from _shared/stated_price.ts; QuotesDone is not responsible for those details. */}
    {q.discount_amount ? <div className={cn(S.sub, 'mt-1 font-medium text-foreground')}>{lang === 'ar' ? q.price_stated_ar : q.price_stated}</div> : null}
    {q.vat_stated ? <div className={cn(S.sub, 'mt-0.5')}>{lang === 'ar' ? q.vat_stated_ar : q.vat_stated}</div> : null}
    <div className={cn(S.sub, 'mt-0.5 italic')}>{t(lang, 'q_not_responsible')}</div>
    {q.badges ? <div className="mt-1.5"><QuoteBadges f={q.badges} lang={lang === 'ar' ? 'ar' : 'en'} /></div> : null}
    {q.scope && <div className={cn(S.sub, 'mt-1')}>{q.scope}</div>}
    {q.notes &&<div className={cn(S.sub, 'mt-1')}>{t(lang, 'q_note') + q.notes}</div>}
    {/* What the price does NOT cover is the part that turns a cheap quote into an expensive job. */}
    {q.exclusions && <div className={cn(S.sub, 'mt-1 text-warn-fg')}>{t(lang, 'q_excl') + q.exclusions}</div>}
    {q.conditions && <div className={cn(S.sub, 'mt-1')}>{t(lang, 'q_cond') + q.conditions}</div>}
    {/* Founder ledger 1588 (10 Nov 2026): the sales engineer's review of this quote against the request, in plain words
        and naming no brand — scope left out, another origin, a lower grade, a short quantity, late delivery, a short warranty. */}
    {Array.isArray(q.review_notes) && q.review_notes.length ? <div className="mt-1.5 rounded-md border border-warn/30 bg-warn/5 px-3 py-2 text-[11.5px] leading-relaxed">
      <div className="font-semibold text-foreground">{t(lang, 'q_review')}</div>
      <ul className="mt-0.5 list-disc ps-4">{q.review_notes.map((n, i) => <li key={i} className={n.severity === 'high' ? 'text-warn-fg' : 'text-muted-foreground'}>{lang === 'ar' ? n.ar : n.en}</li>)}</ul>
    </div> : null}
    {exp && (exp.tone === 'ok'
      ? <div className={cn(S.sub, 'mt-1')}>{exp.text}{q.validity ? (' · ' + t(lang, 'q_validity') + q.validity) : ''}</div>
      : <div className={cn('mt-1.5 rounded-md border px-3 py-2 text-[11.5px]', exp.tone === 'expired' ? 'border-danger/30 bg-danger/10 text-danger-fg' : 'border-warn/30 bg-warn/10 text-warn-fg')} role={exp.tone === 'expired' ? 'alert' : undefined}>{exp.text}</div>)}
    {!exp && q.validity && <div className={cn(S.sub, 'mt-1')}>{t(lang, 'q_validity') + q.validity}</div>}
    {/* match_reason is omitted by the API until reveal, because it can name the company. */}
    {q.match_reason && <div className={cn(S.sub, 'mt-1')}>{t(lang, 'q_why') + q.match_reason}</div>}
    <div className="mt-1.5 flex flex-wrap items-center gap-x-4 gap-y-1"><QuotePdfLink q={q} token={token} lang={lang} />{revealed ? <InvoicePdfLink q={q} token={token} lang={lang} /> : null}</div>
    <div className="mt-2"><SupplierRelationshipCard quote={q} token={token} lang={lang === 'ar' ? 'ar' : 'en'} /></div>
    {revealed ? (contact
        ? <RevealMoment play={justRevealed && !reduce}><Contact play={justRevealed && !reduce} c={contact} q={q} token={token} onChange={onChange} lang={lang} terms={terms} won={hired != null && q.supplier_ref != null && Number(hired) === Number(q.supplier_ref)} /></RevealMoment>
        : <div className={cn(S.sub, 'mt-2 flex items-center gap-2')}><span className="redact redact-bar" aria-hidden />{t(lang, 'q_loading_contact')}</div>)
      : (<div className="mt-3 flex flex-col items-stretch gap-2.5 border-t border-border pt-3 sm:flex-row sm:items-center sm:justify-between">
          {/* Stacked below sm: beside the button the fee sentence was squeezed to 1-2 words a line at 375px. */}
          <div className={cn(S.sub, 'min-w-0 sm:flex-1')}>{w && c ? tf(lang, 'q_fee_line', { fee: aed(q.reveal_fee), w, c }) : aed(q.reveal_fee)}{q.fee_basis ? <div className="mt-0.5">{lang === 'ar' ? q.fee_basis_ar : q.fee_basis}</div> : null}</div>
          {/* Gold: the one action in the product that unseals an identity. */}
          <Button variant="reveal" aria-busy={revealSpin || undefined} disabled={busy || concluded} onClick={reveal}>{revealSpin ? <Spinner /> : <Lock aria-hidden />}{busy ? t(lang, leaving ? 'q_redirecting' : 'q_wait') : t(lang, 'q_reveal')}</Button>
        </div>)}
    {settling ? (<div className="mt-3 rounded-card border border-primary/30 bg-primary/5 p-3.5">
      <div className="text-[12.5px] leading-relaxed text-foreground">{t(lang, 'pay_settling')}</div>
      <Button size="sm" variant="outline" className="mt-2.5" disabled={recheckBusy} onClick={checkReveal}>{recheckBusy ? t(lang, 'pay_checking') : t(lang, 'pay_check_again')}</Button>
    </div>) : null}
    {paying && !revealed ? <RevealPayment q={q} token={token} lang={lang} call={call}
      onPaid={async () => { setPaying(false); unlock(await call('customer_api', { action: 'reveal', quote_id: q.id }, token).catch(() => null)); if (onChange) onChange(); }}
      onFallback={checkoutFallback} onCancel={() => setPaying(false)} /> : null}
    {msg && <div className={S.err} role="alert">{msg}</div>}
  </div>);
}
// The redaction bar is the brand's mark for withheld data, so the reveal is that bar lifting away.
function RevealMoment({ play, children }) {
  if (!play) return children;
  return (<div className="relative">
    <M.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.55, ease: [0.2, 0.8, 0.2, 1] }}>{children}</M.div>
    <M.span aria-hidden className="redact pointer-events-none absolute inset-x-3 top-5 block! h-5" style={{ transformOrigin: 'right center' }}
      initial={{ scaleX: 1, opacity: 1 }} animate={{ scaleX: 0, opacity: 0 }} transition={{ duration: 0.75, delay: 0.1, ease: [0.7, 0, 0.3, 1] }} />
  </div>);
}
export { QuoteCard };
