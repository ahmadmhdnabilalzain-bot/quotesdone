'use client';
// ROW #5 §12 — THE NEGOTIATION ASSISTANT. Reads the discount request, shows the arithmetic, drafts
// the reply — and refuses to tell the supplier how low they can go.
//
// ── THE REFUSAL IS THE FEATURE ──────────────────────────────────────────────────────────────────
// A supplier facing "can you do better?" wants a number. QuotesDone knows the quote, its own 3% fee
// and the customer price; it does NOT know what the job costs to deliver. Without a cost there is
// no floor, and a "recommended discount" derived from the platform's own fee would read as advice
// about the supplier's profit while being nothing of the kind — a supplier could accept a cut that
// loses them money on the strength of it.
//
// So the panel shows scenarios and calls them arithmetic: "at -5% you receive X, the customer pays
// Y, you give up Z". The supplier supplies the one number only they have. The drafted reply is
// bound by the same rule — the prompt forbids proposing any discount, so the draft acknowledges the
// request, restates what is already in the quote, and asks what is driving the number.
//
// ── AND A FAILED ANALYSIS IS NOT "NO DISCOUNT REQUESTED" ────────────────────────────────────────
// price_pressure_detected is boolean OR NULL. Null means the model did not answer, and it renders
// as "could not be analysed" — never as the reassuring false negative, which is the one wrong
// answer here that costs money.
import React, { useEffect, useState } from 'react';
import { motion } from 'motion/react';
import { SUPA_FN, SUPA_ANON } from '@/lib/supaEnv';

type Lang = 'en' | 'ar';
type Scenario = { reduction_pct: number; you_receive: number; customer_pays: number; you_give_up: number };
type Payload = {
  quote_id?: string | null;
  inquiry_id?: string; supplier_id?: number;
  quote_amount?: number; customer_price?: number;
  margin?: { whose?: string; app_fee?: number; margin_rate?: number; note?: string };
  supplier_cost_known?: boolean;
  possible_reduction?: { available?: boolean; why?: string; scenarios?: Scenario[] };
  inbound_messages?: { id: number; body: string; created_at: string }[];
  population?: { customer_messages?: number; note?: string | null };
  terms?: { lead_time?: string | null; warranty?: string | null };
  analysis?: {
    price_pressure_detected?: boolean | null; detection?: string;
    signals?: string[]; recommended_response?: string | null;
  };
};

const FN = SUPA_FN;
const ANON = SUPA_ANON;

async function call(path: string, body: unknown, token?: string | null) {
  const r = await fetch(FN + '/' + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
    body: JSON.stringify(body),
  });
  return r.json();
}

const T = {
  en: {
    title: 'Negotiation assistant', loading: 'Reading the conversation…',
    pressure: 'Discount request detected', noPressure: 'No price pressure in this conversation',
    unknown: 'Could not be analysed', signals: 'What the customer wrote',
    margin: 'Current margin', reduction: 'Possible reduction', scenarios: 'If you reduce',
    receive: 'You receive', pays: 'Customer pays', giveUp: 'You give up',
    draft: 'Recommended response', send: 'Send this reply', sending: 'Sending…', sent: 'Sent',
    editFirst: 'Edit before sending — it is your quote.', noQuote: 'No quote to analyse yet.',
  },
  ar: {
    title: 'مساعد التفاوض', loading: 'جارٍ قراءة المحادثة…',
    pressure: 'تم رصد طلب خصم', noPressure: 'لا يوجد ضغط سعري في هذه المحادثة',
    unknown: 'تعذّر التحليل', signals: 'ما كتبه العميل',
    margin: 'الهامش الحالي', reduction: 'التخفيض الممكن', scenarios: 'إذا خفّضت',
    receive: 'تستلم', pays: 'يدفع العميل', giveUp: 'تتنازل عن',
    draft: 'الرد المقترح', send: 'أرسل هذا الرد', sending: 'جارٍ الإرسال…', sent: 'تم الإرسال',
    editFirst: 'عدّل قبل الإرسال — إنه عرضك.', noQuote: 'لا يوجد عرض للتحليل بعد.',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

export default function SupplierNegotiation({ token, lang = 'en', quoteId }:
  { token?: string | null; lang?: Lang; quoteId?: string | null }) {
  const [d, setD] = useState<Payload | null>(null);
  const [err, setErr] = useState('');
  const [reply, setReply] = useState('');
  const [sendState, setSendState] = useState<'' | 'sending' | 'sent'>('');

  useEffect(() => {
    let live = true;
    call('supplier_portal', { action: 'negotiation', quote_id: quoteId }, token).then((j) => {
      if (!live) return;
      if (j && j.ok) { setD(j); setReply(String(j.analysis?.recommended_response || '')); }
      else setErr((j && (j.error || j.hint)) || 'load_err');
    }).catch(() => { if (live) setErr('load_err'); });
    return () => { live = false; };
  }, [token, quoteId]);

  if (err) return <div className="p-4 text-xs opacity-60">{err}</div>;
  if (!d) return <div className="p-4 text-xs opacity-60">{t(lang, 'loading')}</div>;
  // No quote yet is a state, not an error: the panel says so instead of rendering empty analysis.
  if (!d.quote_id) return <p className="qd-panel p-4 text-xs text-muted-foreground">{d.population?.note || t(lang, 'noQuote')}</p>;

  const a = d.analysis || {};
  const detected = a.price_pressure_detected;
  const scenarios = d.possible_reduction?.scenarios || [];

  return (
    <div className="flex flex-col gap-3" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <h2 className="text-[15px] font-semibold text-white">{t(lang, 'title')}</h2>

      {/* Detection. Null renders as "could not be analysed", never as a comfortable no. */}
      <motion.section
        initial={{ opacity: 0, y: 5 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.22 }}
        className="qd-panel p-4"
      >
        <p className={'text-[13.5px] font-semibold '
          + (detected === true ? 'text-warn-fg' : detected === false ? 'text-white/85' : 'text-muted-foreground italic')}>
          {detected === true ? t(lang, 'pressure') : detected === false ? t(lang, 'noPressure') : t(lang, 'unknown')}
        </p>
        {a.detection && <p className="mt-1 text-xs leading-[1.7] text-muted-foreground">{a.detection}</p>}
        {!!(a.signals || []).length && (
          <>
            <h3 className="mt-2.5 text-[10px] uppercase tracking-wide text-muted-foreground">{t(lang, 'signals')}</h3>
            <ul className="mt-1 flex flex-col gap-1">
              {(a.signals || []).map((s, i) => (
                <li key={i} className="text-[12px] italic text-white/80">“{s}”</li>
              ))}
            </ul>
          </>
        )}
        {d.population?.note && <p className="mt-2 text-[11px] text-muted-foreground/70">{d.population.note}</p>}
      </motion.section>

      {/* Margin — the PLATFORM's, said so in the label and again in the note. */}
      <section className="qd-panel p-4">
        <h3 className="text-[10px] uppercase tracking-wide text-muted-foreground">{t(lang, 'margin')}</h3>
        <p className="mt-0.5 text-[13.5px] text-white">
          {d.margin?.app_fee != null ? `${d.margin.app_fee} (${((d.margin.margin_rate || 0) * 100).toFixed(1)}%)` : '—'}
        </p>
        <p className="mt-1 text-[11.5px] leading-[1.7] text-muted-foreground">{d.margin?.note}</p>
      </section>

      {/* Possible reduction — explicitly unavailable, with the scenarios as arithmetic. */}
      <section className="qd-panel p-4">
        <h3 className="text-[10px] uppercase tracking-wide text-muted-foreground">{t(lang, 'reduction')}</h3>
        <p className="mt-1 text-[11.5px] leading-[1.7] text-muted-foreground">{d.possible_reduction?.why}</p>
        {!!scenarios.length && (
          <div className="mt-2.5 overflow-x-auto">
            <table className="w-full min-w-[22rem] text-[12px]">
              <thead>
                <tr className="text-[10px] uppercase tracking-wide text-muted-foreground">
                  <th className="pb-1 text-start font-normal">{t(lang, 'scenarios')}</th>
                  <th className="pb-1 text-end font-normal">{t(lang, 'receive')}</th>
                  <th className="pb-1 text-end font-normal">{t(lang, 'pays')}</th>
                  <th className="pb-1 text-end font-normal">{t(lang, 'giveUp')}</th>
                </tr>
              </thead>
              <tbody className="tabular-nums text-white/90">
                {scenarios.map((s) => (
                  <tr key={s.reduction_pct} className="border-t border-white/10">
                    <td className="py-1.5">−{s.reduction_pct}%</td>
                    <td className="py-1.5 text-end">{s.you_receive}</td>
                    <td className="py-1.5 text-end">{s.customer_pays}</td>
                    <td className="py-1.5 text-end text-warn-fg/90">{s.you_give_up}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* The drafted reply, editable, and sendable through the same messages_api the thread uses. */}
      <section className="qd-panel p-4">
        <h3 className="text-[10px] uppercase tracking-wide text-muted-foreground">{t(lang, 'draft')}</h3>
        <textarea
          value={reply} onChange={(e) => setReply(e.target.value)} rows={4}
          className="mt-1.5 w-full resize-y rounded-lg border border-white/15 bg-white/[0.04] px-2.5 py-2 text-[12.5px] leading-[1.7] outline-none focus:border-white/30"
        />
        <p className="mt-1 text-[11px] text-muted-foreground">{t(lang, 'editFirst')}</p>
        <button
          type="button" className="qd-btn mt-2" disabled={!reply.trim() || sendState !== ''}
          onClick={async () => {
            setSendState('sending');
            const j = await call('messages_api', {
              action: 'send', inquiry_id: d.inquiry_id, supplier_id: d.supplier_id, body: reply.trim(),
            }, token).catch(() => null);
            setSendState(j && j.ok ? 'sent' : '');
          }}
        >
          {sendState === 'sending' ? t(lang, 'sending') : sendState === 'sent' ? t(lang, 'sent') : t(lang, 'send')}
        </button>
      </section>
    </div>
  );
}
