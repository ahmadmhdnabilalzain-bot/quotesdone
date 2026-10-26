'use client';
// ROW #5 §11 §22 — THE AI QUOTE BUILDER. The supplier writes nothing; the AI proposes the terms.
//
// ── WHY THIS IS A SEPARATE SURFACE FROM EVERY OTHER QUOTING SCREEN ──────────────────────────────
// The portal already had two screens that live near the words "price" and "recommend", and neither
// of them is this. The quote form takes a price the supplier TYPES — which is precisely the thing
// §11 exists to replace. The upload path reads a price off a PDF the supplier already wrote. §11's
// premise is that nothing exists yet: the supplier names a project in their own words and the
// platform proposes what to charge, how long to take, what to guarantee and what could go wrong.
//
// ── EVERY FIGURE ON THIS SCREEN IS SERVED, NONE IS COMPUTED HERE ────────────────────────────────
// fn_supplier_quote_recommend produces all of it from the competing bids on the same enquiry. The
// component decides nothing about money. It does not round, it does not pick a default when the
// routine returns null, and when the routine says `available: false` it shows that reason instead
// of the last figure it happened to be holding — the failure mode where a stale number stays on
// screen looking current.
//
// ── AND ACCEPTING WRITES A REAL QUOTE THROUGH THE ORDINARY PATH ─────────────────────────────────
// "Use these terms" posts to supplier_api submit_quote, the same endpoint the form posts to, with
// the same approval gate, the same registration gate and the same identity scrubbing. A supplier
// cannot reach a quote the platform would otherwise refuse by coming through this door instead.
import React, { useEffect, useMemo, useState } from 'react';
import { call, callShared } from './api';
import { Button } from '@/components/ui/button';

type Lang = 'en' | 'ar';
// The field names are fn_supplier_opportunities', read off the live payload rather than guessed:
// the title key is `project_title`, and there is no `title` or `summary` at all. The first version
// of this component fell back through `title || summary || requirement` and would have listed every
// project by its full requirement paragraph.
type Opp = { inquiry_id?: string; project_title?: string; category?: string;
             emirate?: string; requirement?: string; match_pct?: number };
type Money = { value?: number | null; currency?: string; p25?: number | null; p75?: number | null;
               low?: number | null; high?: number | null; basis?: string };
type Pick = { value?: string | null; agreed_by?: number | null; consensus?: boolean;
              observed?: string[]; basis?: string };
type Rec = {
  available?: boolean; note?: string; basis?: string; population?: number; summary?: string;
  recommended_price?: Money;
  market_position?: { verdict?: string; your_index?: number | null; your_quotes_measured?: number | null; detail?: string };
  delivery_estimate?: Pick; warranty?: Pick; payment_terms?: Pick;
  risk_level?: { value?: string; count?: number; signals?: { signal: string; detail: string }[];
                 recommended_action?: string; basis?: string };
};

// The private copy of `call` this file carried is gone, for the reasons written at the head of
// SupplierOpportunities.tsx: ./api.ts owns the one helper, and it is the stronger one.

const T = {
  en: {
    title: 'Quote Builder',
    // §11's entry, verbatim on screen. The supplier says what they want in their own words rather
    // than picking a row out of a table and then filling a form.
    intentLabel: 'I want to quote this project',
    intentHelp: 'Type a few words from the project — the trade, the place, the customer — and pick it below.',
    placeholder: 'e.g. the chiller replacement in Business Bay',
    build: 'Build me a quote', building: 'Reading the market…',
    noMatch: 'Nothing matches that yet. Try fewer words.',
    noOpen: 'There is no open request you can quote right now. New requests in your trades appear here.',
    recPrice: 'Suggested price', marketPos: 'Market position', delivery: 'Suggested delivery',
    warranty: 'Suggested warranty', risk: 'Risk level', terms: 'Suggested payment terms',
    middleHalf: 'middle half', range: 'range', theyAgreed: 'bids agreed', noConsensus: 'no two bids agreed',
    alsoSeen: 'also offered', useTerms: 'Use these terms', sending: 'Creating your quote…',
    created: 'Quote created from these terms.', pickOne: 'Choose a project above to get a recommendation.',
    whyThis: 'Why this figure', signalsTitle: 'What could go wrong',
    lowRisk: 'low', medRisk: 'medium', highRisk: 'high',
    demoBanner: 'Sample data. This recommendation is an illustration, not based on live market trading.',
  },
  ar: {
    title: 'إعداد عروض الأسعار',
    intentLabel: 'أريد تسعير هذا المشروع',
    intentHelp: 'اكتبوا بضع كلمات عن المشروع (النشاط، الموقع، العميل)، ثم اختاروه من القائمة أدناه.',
    placeholder: 'مثال: استبدال المبردات في الخليج التجاري',
    build: 'إعداد عرض السعر', building: 'جارٍ قراءة السوق…',
    noMatch: 'لا توجد نتائج مطابقة بعد. جرّبوا كلمات أقل.',
    noOpen: 'لا يوجد حاليًا طلب مفتوح يمكنكم تسعيره، وستظهر هنا الطلبات الجديدة في تخصصاتكم.',
    recPrice: 'السعر المقترح', marketPos: 'الموقع في السوق', delivery: 'مدة التسليم المقترحة',
    warranty: 'الضمان المقترح', risk: 'مستوى المخاطر', terms: 'شروط الدفع المقترحة',
    middleHalf: 'النصف الأوسط', range: 'المدى', theyAgreed: 'عروض متفقة', noConsensus: 'لا يوجد عرضان متفقان',
    alsoSeen: 'عروض أخرى', useTerms: 'اعتماد هذه الشروط', sending: 'جارٍ إعداد عرضكم…',
    created: 'أُعدّ العرض بهذه الشروط.', pickOne: 'اختاروا مشروعًا من الأعلى لعرض التوصية.',
    whyThis: 'سبب هذا الرقم', signalsTitle: 'ما الذي قد يحدث',
    lowRisk: 'منخفض', medRisk: 'متوسط', highRisk: 'مرتفع',
    demoBanner: 'بيانات تجريبية: هذه التوصية محسوبة من بيانات عرض توضيحي، لا من معاملات فعلية.',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

const aed = (n?: number | null, cur = 'AED') =>
  n === null || n === undefined ? '—' : cur + ' ' + Math.round(n).toLocaleString('en-US');

const RISK_TONE: Record<string, string> = {
  low: 'text-ok-fg border-ok/25 bg-ok/[0.06]',
  medium: 'text-warn-fg border-warn/25 bg-warn/[0.06]',
  high: 'text-danger-fg border-danger/25 bg-danger/[0.06]',
};

// One proposed term. Every card on this screen is a thing the AI SUGGESTS, so they share a shell
// and the word appears once rather than six times in six slightly different ways.
function Suggested({ label, children, foot }: { label: string; children: React.ReactNode; foot?: React.ReactNode }) {
  return (
    <div className="rounded-chip border border-border bg-background/40 px-3.5 py-3">
      <div className="mb-1.5 font-mono text-label uppercase tracking-caps text-muted-foreground">{label}</div>
      {children}
      {foot && <p className="mt-2 border-t border-border pt-2 text-[11px] leading-snug text-muted-foreground">{foot}</p>}
    </div>
  );
}

export default function SupplierQuoteBuilder({ token, lang = 'en' }: { token?: string | null; lang?: Lang }) {
  // null until the list has loaded: "nothing matches" before the answer arrives would be a guess.
  const [opps, setOpps] = useState<Opp[] | null>(null);
  const [intent, setIntent] = useState('');
  const [chosen, setChosen] = useState<string>('');
  const [rec, setRec] = useState<Rec | null>(null);
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState('');
  const [err, setErr] = useState('');
  const [demo, setDemo] = useState(false);

  useEffect(() => {
    let live = true;
    // Shares the one flight with SupplierOpportunities, which sits in the same Insights panel.
    // The catch is not decoration: the old private `call` used a bare r.json(), so a non-JSON
    // answer rejected here with nothing listening, and this panel simply stayed empty for ever
    // with no trace. ./api.ts's call resolves that case to { ok:false }; this covers the rest.
    callShared('supplier_portal', { action: 'opportunities' }, token).then((j) => {
      if (!live || !j) return;
      const list: Opp[] = j.opportunities || j.items || j.rows || [];
      setOpps(Array.isArray(list) ? list : []);
    }).catch(() => { if (live) setOpps([]); });
    // The demo banner is driven by the same routine that partitions the population, so the two can
    // never disagree about which market this supplier is being shown.
    call('supplier_portal', { action: 'market' }, token).then((j) => { if (live && j) setDemo(j.population === 'demo'); });
    return () => { live = false; };
  }, [token]);

  const oid = (o: Opp) => String(o.inquiry_id || '');
  const otitle = (o: Opp) => String(o.project_title || o.requirement || oid(o));

  // The free-text intent narrows the list; it does not guess. A builder that picked a project on
  // its own would be proposing a price for something the supplier never chose.
  const matches = useMemo(() => {
    const all = opps || [];
    const q = intent.trim().toLowerCase();
    if (!q) return all;
    const words = q.split(/\s+/).filter((w) => w.length > 2);
    if (!words.length) return all;
    return all.filter((o) => {
      const hay = (otitle(o) + ' ' + (o.category || '') + ' ' + (o.emirate || '') + ' ' + (o.requirement || '')).toLowerCase();
      return words.some((w) => hay.includes(w));
    });
  }, [intent, opps]);

  const build = async (inquiryId: string) => {
    if (!inquiryId) return;
    setBusy(true); setErr(''); setSent(''); setRec(null); setChosen(inquiryId);
    const j = await call('supplier_portal', { action: 'quote_recommend', inquiry_id: inquiryId }, token);
    setBusy(false);
    if (j && j.ok) setRec(j); else setErr((j && (j.error || j.hint)) || 'load_err');
  };

  // Accepting posts through supplier_api submit_quote — the same endpoint, gates and scrubbing the
  // form uses. If the account is not approved the platform refuses here exactly as it would there,
  // and that refusal is shown rather than swallowed.
  const accept = async () => {
    if (!rec?.available || !chosen) return;
    setBusy(true); setErr(''); setSent('');
    const j = await call('supplier_api', {
      action: 'submit_quote',
      inquiry_id: chosen,
      amount: rec.recommended_price?.value,
      lead_time: rec.delivery_estimate?.value || null,
      payment_terms: rec.payment_terms?.value || null,
      warranty: rec.warranty?.value || null,
      notes: 'Prepared with the QuotesDone Quote Builder from ' + (rec.population ?? 0) + ' comparable bid(s).',
      source: 'form',
    }, token);
    setBusy(false);
    if (j && j.ok) setSent(t(lang, 'created')); else setErr((j && (j.error || j.hint)) || 'submit_err');
  };

  const loaded = opps !== null;
  const hasOpen = (opps || []).length > 0;
  const hasQuery = intent.trim().length > 0;
  const price = rec?.recommended_price;
  const risk = rec?.risk_level;
  const riskWord = risk?.value === 'high' ? t(lang, 'highRisk') : risk?.value === 'medium' ? t(lang, 'medRisk') : t(lang, 'lowRisk');

  return (
    <div className="space-y-4">
      {demo && (
        <p className="rounded-xl border border-warn/25 bg-warn/[0.06] px-3 py-2 text-[11px] leading-snug text-warn-fg/80">
          {t(lang, 'demoBanner')}
        </p>
      )}

      {/* ── THE NATURAL-LANGUAGE ENTRY ────────────────────────────────────────────────────────── */}
      <section className="qd-panel p-5">
        <h3 className="qd-kicker mb-4">{t(lang, 'title')}</h3>
        <label className="mb-1 block font-head text-[15px] font-semibold text-foreground" htmlFor="qd-qb-intent">{t(lang, 'intentLabel')}</label>
        <p className="mb-2.5 text-[12px] text-muted-foreground">{t(lang, 'intentHelp')}</p>
        <input
          id="qd-qb-intent"
          className="h-10 w-full rounded-md border border-input bg-transparent px-3 text-sm text-foreground outline-none placeholder:text-muted-foreground focus-visible:ring-1 focus-visible:ring-ring"
          placeholder={t(lang, 'placeholder')}
          value={intent}
          onChange={(e) => setIntent(e.target.value)}
        />
        <div className="mt-3 space-y-1.5 max-h-64 overflow-y-auto">
          {/* Audit 21 Sep 2026, finding 38: "Nothing matches that yet" printed before anything was
              typed, beside "Choose a project above" with nothing above. Each line now needs its own
              condition: no open request at all, or a typed query that matched none. */}
          {loaded && !hasOpen && <p className="text-[11px] opacity-50">{t(lang, 'noOpen')}</p>}
          {hasOpen && hasQuery && matches.length === 0 && <p className="text-[11px] opacity-50">{t(lang, 'noMatch')}</p>}
          {matches.map((o) => (
            <button
              key={oid(o)}
              type="button"
              onClick={() => build(oid(o))}
              className={'w-full text-start rounded-chip border px-3 py-2.5 text-[13px] transition-colors '
                + (chosen === oid(o) ? 'border-primary/60 bg-primary/10 text-foreground' : 'border-border text-foreground hover:border-primary/40')}
            >
              <span className="block truncate font-medium">{otitle(o)}</span>
              <span className="mt-0.5 block font-mono text-[11px] text-muted-foreground">
                {[o.category, o.emirate].filter(Boolean).join(' · ')}
                {typeof o.match_pct === 'number' ? ' · ' + o.match_pct + '% match' : ''}
              </span>
            </button>
          ))}
        </div>
      </section>

      {busy && <p className="text-xs opacity-60 px-1">{t(lang, 'building')}</p>}
      {err && <p className="text-xs text-danger-fg/90 px-1">{err}</p>}
      {sent && <p className="text-xs text-ok-fg/90 px-1">{sent}</p>}
      {!chosen && !busy && matches.length > 0 && <p className="text-xs opacity-50 px-1">{t(lang, 'pickOne')}</p>}

      {/* A recommendation the routine refused to make, shown with the reason it gave. */}
      {rec && !rec.available && (
        <section className="qd-panel p-5">
          <div className="mb-1.5 font-mono text-label uppercase tracking-caps text-muted-foreground">{t(lang, 'recPrice')}</div>
          <p className="text-[13px] leading-snug text-muted-foreground">{rec.note}</p>
        </section>
      )}

      {/* ── THE PROPOSED TERMS ────────────────────────────────────────────────────────────────── */}
      {rec?.available && (
        <section className="qd-panel space-y-2.5 p-5">
          {/* The suggested price. The spread comes with it: a supplier deciding whether to sit
              under the middle needs to see how much room there is. */}
          <Suggested label={t(lang, 'recPrice')} foot={<>{t(lang, 'whyThis')}: {price?.basis}</>}>
            <div className="qd-figure font-head text-[clamp(30px,6vw,40px)] font-semibold">{aed(price?.value, price?.currency)}</div>
            <div className="mt-2 font-mono text-[11px] leading-relaxed text-muted-foreground">
              <div>{t(lang, 'middleHalf')}: <span className="tabular-nums">{aed(price?.p25, price?.currency)} – {aed(price?.p75, price?.currency)}</span></div>
              <div className="opacity-75">{t(lang, 'range')}: <span className="tabular-nums">{aed(price?.low, price?.currency)} – {aed(price?.high, price?.currency)}</span></div>
            </div>
          </Suggested>

          <Suggested label={t(lang, 'marketPos')}>
            <div className="text-sm font-medium capitalize">{rec.market_position?.verdict}</div>
            <p className="text-[11px] opacity-55 mt-1 leading-snug">{rec.market_position?.detail}</p>
          </Suggested>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
            <Suggested
              label={t(lang, 'delivery')}
              foot={rec.delivery_estimate?.consensus
                ? <>{rec.delivery_estimate?.agreed_by} {t(lang, 'theyAgreed')}</>
                : <>{t(lang, 'noConsensus')} · {t(lang, 'alsoSeen')}: {(rec.delivery_estimate?.observed || []).join(', ')}</>}
            >
              <div className="text-lg font-semibold">{rec.delivery_estimate?.value || '—'}</div>
            </Suggested>

            <Suggested
              label={t(lang, 'warranty')}
              foot={rec.warranty?.consensus
                ? <>{rec.warranty?.agreed_by} {t(lang, 'theyAgreed')}</>
                : <>{t(lang, 'noConsensus')}</>}
            >
              <div className="text-[13px] font-medium leading-snug">{rec.warranty?.value || '—'}</div>
            </Suggested>
          </div>

          <Suggested label={t(lang, 'terms')}>
            <div className="text-[13px] leading-snug">{rec.payment_terms?.value || '—'}</div>
          </Suggested>

          {/* Risk is a level AND its reasons. A level on its own is a number the supplier can
              neither check nor act on, so every signal the routine fired is listed with it. */}
          <div className={'rounded-xl border px-3 py-2.5 ' + (RISK_TONE[String(risk?.value)] || RISK_TONE.low)}>
            <div className="flex items-baseline justify-between gap-2">
              <span className="text-[11px] opacity-70">{t(lang, 'risk')}</span>
              <span className="text-sm font-semibold capitalize">{riskWord}</span>
            </div>
            {!!(risk?.signals || []).length && (
              <>
                <div className="text-[10px] uppercase tracking-wide opacity-60 mt-2 mb-1">{t(lang, 'signalsTitle')}</div>
                <ul className="space-y-1">
                  {(risk?.signals || []).map((s) => (
                    <li key={s.signal} className="text-[11px] leading-snug opacity-85 flex gap-1.5">
                      <span aria-hidden className="opacity-50">·</span><span>{s.detail}</span>
                    </li>
                  ))}
                </ul>
              </>
            )}
            {/* The level and its causes are diagnosis; this is the one move that most reduces it.
                Shown last and in full opacity, because it is the only line here that is an action. */}
            {risk?.recommended_action && (
              <p className="text-[11px] leading-snug mt-2 pt-2 border-t border-current/15">
                {risk.recommended_action}
              </p>
            )}
          </div>

          <Button type="button" onClick={accept} disabled={busy} className="w-full">
            {busy ? t(lang, 'sending') : t(lang, 'useTerms')}
          </Button>
        </section>
      )}
    </div>
  );
}
