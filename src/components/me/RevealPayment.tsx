// @ts-nocheck
'use client';
// THE REVEAL PAYMENT, PRICED ON THE CARD ACTUALLY USED (14 Sep 2026, agent: accountant; the words
// are the sales engineer's voice). Founder: "maybe in the checkout its better to confirm with the
// customer so that we charge them correctly. or if it can be automated during deduction then its
// better." The Payment Element turns the card (or Apple Pay) into a ConfirmationToken; stripe_checkout
// reads the card's issuing country from it and prices the processing line for that card; the
// customer sees ONE final line, "Total AED X (3% + card processing)", and only then is anything
// charged. Stripe.js is loaded from js.stripe.com as Stripe requires, never bundled.
import { useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { t, tf, errText } from './portalText';

function loadStripeJs() {
  if (typeof window !== 'undefined' && window.Stripe) return Promise.resolve(window.Stripe);
  return new Promise((res, rej) => {
    const s = document.createElement('script');
    s.src = 'https://js.stripe.com/v3/'; s.async = true;
    s.onload = () => (window.Stripe ? res(window.Stripe) : rej(new Error('stripe_js')));
    s.onerror = () => rej(new Error('stripe_js'));
    document.head.appendChild(s);
  });
}
const aed = (n) => 'AED ' + Number(n || 0).toLocaleString('en-AE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export function RevealPayment({ q, token, lang, call, onPaid, onFallback, onCancel }) {
  const mount = useRef(null); const st = useRef({ stripe: null, elements: null, ct: '' });
  const [phase, setPhase] = useState('loading'); // loading | ready | quoting | confirm | paying
  const [quote, setQuote] = useState(null); const [msg, setMsg] = useState('');
  const returnUrl = location.origin + (lang === 'ar' ? '/ar/me' : '/me') + '?reveal=' + encodeURIComponent(q.id);

  useEffect(() => {
    let live = true;
    (async () => {
      const init = await call('stripe_checkout', { action: 'element_init', quote_id: q.id }, token).catch(() => null);
      if (!live) return;
      if (!init || !init.ok) { onFallback(init); return; }
      try {
        const Stripe = await loadStripeJs();
        if (!live) return;
        const stripe = Stripe(init.publishable_key, { locale: lang === 'ar' ? 'ar' : 'en' });
        const elements = stripe.elements({ mode: 'payment', amount: init.amount_fils, currency: 'aed', paymentMethodCreation: 'manual' });
        elements.create('payment', { layout: 'tabs' }).mount(mount.current);
        st.current = { stripe, elements, ct: '' };
        setPhase('ready');
      } catch (_e) { if (live) onFallback(null); }
    })();
    return () => { live = false; };
  }, [q.id]);

  const priceCard = async () => {
    setMsg(''); setPhase('quoting');
    const { stripe, elements } = st.current;
    const sub = await elements.submit();
    if (sub.error) { setMsg(sub.error.message || t(lang, 'pay_failed')); setPhase('ready'); return; }
    const { error, confirmationToken } = await stripe.createConfirmationToken({ elements, params: { return_url: returnUrl } });
    if (error) { setMsg(error.message || t(lang, 'pay_failed')); setPhase('ready'); return; }
    const qt = await call('stripe_checkout', { action: 'element_quote', quote_id: q.id, confirmation_token: confirmationToken.id }, token).catch(() => null);
    if (!qt || !qt.ok) { setMsg(errText(qt, lang, 'pay_failed')); setPhase('ready'); return; }
    st.current.ct = confirmationToken.id; setQuote(qt); setPhase('confirm');
  };

  const pay = async () => {
    setMsg(''); setPhase('paying');
    const r = await call('stripe_checkout', { action: 'element_pay', quote_id: q.id, confirmation_token: st.current.ct, expected_total_fils: quote.total_fils }, token).catch(() => null);
    if (r && r.ok && (r.status === 'succeeded' || r.status === 'processing')) { onPaid(); return; }
    if (r && r.ok && r.status === 'repriced') { setQuote(r); setMsg(t(lang, 'pay_repriced')); setPhase('confirm'); return; }
    if (r && r.ok && r.status === 'requires_action') {
      const na = await st.current.stripe.handleNextAction({ clientSecret: r.client_secret });
      if (na.error) { setMsg(na.error.message || t(lang, 'pay_failed')); setPhase('ready'); return; }
      const s = await call('stripe_checkout', { action: 'element_settle', quote_id: q.id, invoice: r.invoice }, token).catch(() => null);
      if (s && (s.ok || s.pending)) { onPaid(); return; }
    }
    setMsg(t(lang, 'pay_failed')); setPhase('ready');
  };

  const busy = phase === 'loading' || phase === 'quoting' || phase === 'paying';
  return (<div className="mt-3 rounded-lg border border-border bg-card p-3.5">
    <div className="mb-2 text-[13px] font-semibold text-foreground">{t(lang, 'pay_title')}</div>
    {phase === 'loading' ? <div className="text-[12.5px] text-muted-foreground">{t(lang, 'pay_loading')}</div> : null}
    <div ref={mount} hidden={phase === 'confirm' || phase === 'paying'} />
    {quote && (phase === 'confirm' || phase === 'paying') ? (
      <div className="rounded-md border border-primary/30 bg-primary/5 p-3">
        <div className="text-[15px] font-semibold text-foreground">{tf(lang, 'pay_final', { total: aed(quote.total_charged) })}</div>
        <div className="mt-1 text-[12px] text-muted-foreground">{tf(lang, 'pay_lines', { fee: aed(quote.base_fee) })}</div>
      </div>) : null}
    {msg ? <div className="mt-2 text-[12.5px] text-danger" role="alert">{msg}</div> : null}
    <div className="mt-3 flex flex-wrap gap-2">
      {phase === 'confirm' || phase === 'paying'
        ? <Button variant="reveal" disabled={busy} onClick={pay}>{phase === 'paying' ? t(lang, 'pay_paying') : tf(lang, 'pay_confirm', { total: aed(quote && quote.total_charged) })}</Button>
        : <Button disabled={busy} onClick={priceCard}>{phase === 'quoting' ? t(lang, 'q_wait') : t(lang, 'pay_continue')}</Button>}
      <Button variant="ghost" disabled={phase === 'paying'} onClick={onCancel}>{t(lang, 'pay_cancel')}</Button>
    </div>
  </div>);
}
