'use client';
// ROW #5 §3 §4 §6 §13 — THE SUPPLIER DIGITAL TWIN, SUPPLIER HEALTH AND PROFILE INTELLIGENCE.
//
// ── WHY THIS IS A NEW FILE AND NOT MORE OF SupplierPortal.tsx ───────────────────────────────────
// SupplierPortal.tsx is 81,811 stripped characters holding the settings form, the registration
// uploader, the help desk, the catalog uploader, the RFQ inbox AND the command centre. Three
// separate refutation rounds of verify_supplier_blueprint were caused by that: a scan asking "does
// this FILE contain both X and Y" is nearly vacuous when the file is the whole product, and the
// support chat inside it certified an "AI assistant" that does not exist.
//
// Every new row #5 module therefore lands in its own file. That is not tidiness — it makes the
// measurement honest, because a check can then name the component that satisfied it.
//
// ── WHAT IT RENDERS, AND WHAT IT REFUSES TO ────────────────────────────────────────────────────
// One call: supplier_portal { action:'twin' } → fn_supplier_twin. Every number on screen is a
// column the database already computes. supplier_score carries reliability and response_rate for
// 20,464 of 20,464 companies on production and, until this component existed, the supplier could
// see NEITHER — the portal rendered a Response-rate tile guarded by `s.response_rate != null` whose
// guard could never be true because no endpoint returned the field.
//
// NULL IS NOT ZERO, and this is the component's most important rule. price_index is null on every
// production row. A bar that renders null as 0% tells a supplier their pricing is rated zero, which
// is a false statement about a real business. Null renders as an explicit "not rated yet" with no
// bar at all.
import React, { useEffect, useState } from 'react';
import { SUPA_ANON, fnUrl } from '@/lib/supaEnv';
import { emirateLabel } from './serverCopy';

// The twin payload as fn_supplier_twin actually returns it. Every numeric field is nullable on
// purpose: price_index is null on all 20,464 production rows, and a type that pretended otherwise
// would push the component toward rendering 0% for 'not rated', which is a false claim about a
// real business.
type Doc = { kind: string; expiry: string | null; doc_status: string };
type Twin = {
  company_name?: string; verified?: boolean; is_demo?: boolean; matchable?: boolean;
  intelligence_score?: number | null; star_rating?: number | null; company_strength?: number | null;
  product_count?: number | null; established_year?: number | null; employee_count?: number | null;
  ai_confidence?: number | null; risk_level?: string | null; risk_basis?: string | null;
  health?: { quality?: number | null; delivery?: number | null; response?: number | null;
             pricing?: number | null; overall?: number | null };
  capabilities?: { name: string; has: boolean }[];
  certifications?: string[]; best_opportunities?: string[];
  // `emirates` since 21 Sep 2026. `countries` is the same value under the old key, read only as a
  // fallback for a server not yet redeployed; the label on screen is Emirates either way.
  emirates?: string[]; countries?: string[];
  production_capacity?: { estimated?: number | null; is_estimate?: boolean };
  capability_map?: CapMapShape; documents?: Doc[];
};
type CapMapShape = { root?: string; children?: { name: string }[] } | null;

const ANON = SUPA_ANON;

async function call(path: string, body: unknown, token?: string | null) {
  const r = await fetch(fnUrl(path), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
    body: JSON.stringify(body),
  });
  return r.json();
}

const T = {
  en: {
    twin: 'Supplier Digital Twin', health: 'Supplier Health', profile: 'Company Intelligence',
    strength: 'Company Strength', capabilities: 'Capabilities', products: 'Products',
    certifications: 'Certifications', capacity: 'Production Capacity', opportunities: 'Best Opportunities',
    risk: 'Risk Level', quality: 'Quality', delivery: 'Delivery', response: 'Response',
    pricing: 'Pricing', overall: 'Overall', score: 'Supplier Intelligence Score',
    established: 'Established', employees: 'Employees', emirates: 'Emirates',
    confidence: 'AI Confidence', map: 'Capability Map', documents: 'Documents',
    notRated: 'not rated yet', estimate: 'estimated', perYear: 'units/year',
    verified: 'Verified Supplier', unverified: 'Not yet verified', demo: 'DEMO FIXTURE — not a real company',
    loading: 'Reading your company intelligence…', none: 'none on file', unknown: 'unknown',
    notAssessed: 'Not rated yet — no measurement',
    riskLOW: 'Low', riskMEDIUM: 'Medium', riskHIGH: 'High', riskCRITICAL: 'Critical',
  },
  ar: {
    twin: 'التوأم الرقمي للمورد', health: 'صحة المورد', profile: 'ذكاء الشركة',
    strength: 'قوة الشركة', capabilities: 'القدرات', products: 'المنتجات',
    certifications: 'الشهادات', capacity: 'الطاقة الإنتاجية', opportunities: 'أفضل الفرص',
    risk: 'مستوى المخاطر', quality: 'الجودة', delivery: 'التسليم', response: 'الاستجابة',
    pricing: 'التسعير', overall: 'الإجمالي', score: 'مؤشر ذكاء المورد',
    established: 'تأسست', employees: 'الموظفون', emirates: 'الإمارات',
    confidence: 'ثقة الذكاء الاصطناعي', map: 'خريطة القدرات', documents: 'المستندات',
    notRated: 'لم يتم التقييم بعد', estimate: 'تقديري', perYear: 'وحدة/سنة',
    verified: 'مورد موثّق', unverified: 'غير موثّق بعد', demo: 'نموذج تجريبي — ليست شركة حقيقية',
    loading: 'جارٍ قراءة ذكاء شركتك…', none: 'لا يوجد', unknown: 'غير معروف',
    notAssessed: 'لم يُقيَّم بعد — لا يوجد قياس',
    riskLOW: 'منخفض', riskMEDIUM: 'متوسط', riskHIGH: 'مرتفع', riskCRITICAL: 'حرج',
  },
};
type Lang = 'en' | 'ar';
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

// No measurement, no verdict: a NULL risk_level reads "not rated yet", never a default grade
// (audit 21 Sep 2026: a supplier with no licence and no history was shown as low risk).
function riskText(level: string | null | undefined, lang: Lang): string {
  if (!level) return t(lang, 'notAssessed');
  const k = ('risk' + String(level).toUpperCase()) as keyof typeof T.en;
  return k in T.en ? t(lang, k) : String(level);
}

// §13's bars. THE NULL BRANCH IS THE POINT: a metric with no data renders as "not rated yet" and
// draws no bar, because a 0%-wide bar is a claim that the supplier scored zero.
function Bar({ label, value, lang }: { label: string; value: number | null | undefined; lang: Lang }) {
  const known = value !== null && value !== undefined;
  return (
    <div className="mb-2.5">
      <div className="flex justify-between text-[11px] mb-1 opacity-70">
        <span>{label}</span>
        <span>{known ? Math.round(value) + '%' : t(lang, 'notRated')}</span>
      </div>
      <div className="h-1.5 rounded-full bg-white/10 overflow-hidden">
        {known && (
          <div
            className="h-full rounded-full bg-gradient-to-r from-sky-400 to-emerald-400 transition-all duration-700"
            style={{ width: Math.max(2, Math.min(100, Number(value))) + '%' }}
          />
        )}
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <div className="text-[10px] uppercase tracking-wide opacity-50">{label}</div>
      <div className="text-sm font-medium truncate">{value}</div>
    </div>
  );
}

// §6's capability map is drawn as a GRAPH, not a list: a root category with edges to its children.
// The spec draws exactly that, and a bulleted list is §3's checklist, which is rendered separately.
type CapMap = CapMapShape | undefined;
function CapabilityMap({ map, lang }: { map: CapMap; lang: Lang }) {
  const children = (map && map.children) || [];
  if (!children.length) return null;
  const W = 300, H = 34 + children.length * 26;
  return (
    <div className="mt-3">
      <div className="text-[10px] uppercase tracking-wide opacity-50 mb-1">{t(lang, 'map')}</div>
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full max-w-[320px]" role="img" aria-label={t(lang, 'map')}>
        <text x="8" y="16" className="fill-current text-[11px]" fontSize="11">{map?.root}</text>
        {children.map((c, i) => {
          const y = 34 + i * 26;
          return (
            <g key={c.name}>
              <line x1="14" y1="22" x2="14" y2={y} stroke="currentColor" strokeOpacity="0.25" />
              <line x1="14" y1={y} x2="34" y2={y} stroke="currentColor" strokeOpacity="0.25" />
              <circle cx="34" cy={y} r="3" fill="currentColor" fillOpacity="0.5" />
              <text x="44" y={y + 4} fontSize="11" className="fill-current">{c.name}</text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}

export default function SupplierTwin({ token, lang = 'en' }: { token?: string | null; lang?: Lang }) {
  const [twin, setTwin] = useState<Twin | null>(null);
  const [err, setErr] = useState('');

  useEffect(() => {
    let live = true;
    call('supplier_portal', { action: 'twin' }, token).then((j) => {
      if (!live) return;
      if (j && j.ok && j.twin) setTwin(j.twin);
      else setErr((j && (j.error || j.hint)) || 'load_err');
    });
    return () => { live = false; };
  }, [token]);

  if (err) return <div className="text-xs opacity-60 p-4">{err}</div>;
  if (!twin) return <div className="text-xs opacity-60 p-4">{t(lang, 'loading')}</div>;

  const h = twin.health || {};
  const caps = (twin.capabilities || []).filter((c) => c.has);
  const certs = twin.certifications || [];
  const cap = twin.production_capacity || {};
  const opps = twin.best_opportunities || [];
  const emirates = twin.emirates ?? twin.countries ?? [];

  return (
    <div className="space-y-4" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      {/* A fixture must never be presentable as a live account. is_demo comes from the fence itself
          (matching_blocked AND a 'demo' tag), so this banner cannot drift from what it describes. */}
      {twin.is_demo && (
        <div className="rounded-lg border border-warn/40 bg-warn/10 px-3 py-2 text-[11px] text-warn-fg">
          {t(lang, 'demo')}
        </div>
      )}

      {/* §4 — the command-centre header: company, verified badge, stars, intelligence score. */}
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <div className="text-base font-medium truncate">{twin.company_name}</div>
            <div className="text-[11px] mt-0.5 opacity-70">
              {twin.verified ? t(lang, 'verified') : t(lang, 'unverified')}
              {twin.star_rating != null && (
                <span className="ms-2" aria-label={`${twin.star_rating} / 5`}>
                  {'★'.repeat(twin.star_rating)}{'☆'.repeat(5 - twin.star_rating)}
                </span>
              )}
            </div>
          </div>
          <div className="text-end shrink-0">
            <div className="text-[10px] uppercase tracking-wide opacity-50">{t(lang, 'score')}</div>
            <div className="text-3xl font-semibold tabular-nums">
              {twin.intelligence_score != null ? twin.intelligence_score : '—'}
            </div>
          </div>
        </div>
      </section>

      {/* §13 — SUPPLIER HEALTH. Five metrics, bars, null handled honestly. */}
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <div className="flex justify-between items-baseline mb-3">
          <h3 className="text-xs uppercase tracking-wide opacity-60">{t(lang, 'health')}</h3>
          <div className="text-sm tabular-nums">
            {h.overall != null ? `${h.overall}/100` : t(lang, 'notRated')}
          </div>
        </div>
        <Bar label={t(lang, 'quality')} value={h.quality} lang={lang} />
        <Bar label={t(lang, 'delivery')} value={h.delivery} lang={lang} />
        <Bar label={t(lang, 'response')} value={h.response} lang={lang} />
        <Bar label={t(lang, 'pricing')} value={h.pricing} lang={lang} />
        <Bar label={t(lang, 'overall')} value={h.overall} lang={lang} />
      </section>

      {/* §3 — THE DIGITAL TWIN. */}
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <h3 className="text-xs uppercase tracking-wide opacity-60 mb-3">{t(lang, 'twin')}</h3>
        <Bar label={t(lang, 'strength')} value={twin.company_strength} lang={lang} />
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 mt-3">
          <Stat label={t(lang, 'products')} value={twin.product_count ?? 0} />
          <Stat
            label={t(lang, 'risk')}
            value={riskText(twin.risk_level, lang)}
          />
          <Stat
            label={t(lang, 'capacity')}
            value={cap.estimated != null
              ? `${Number(cap.estimated).toLocaleString()} ${t(lang, 'perYear')} (${t(lang, 'estimate')})`
              : t(lang, 'unknown')}
          />
          <Stat label={t(lang, 'certifications')} value={certs.length ? certs.join(', ') : t(lang, 'none')} />
        </div>
        <div className="mt-3">
          <div className="text-[10px] uppercase tracking-wide opacity-50 mb-1">{t(lang, 'capabilities')}</div>
          <div className="flex flex-wrap gap-1.5">
            {caps.length
              ? caps.map((c) => (
                  <span key={c.name} className="rounded-full border border-ok/30 bg-ok/10 px-2 py-0.5 text-[11px]">
                    {c.name}
                  </span>
                ))
              : <span className="text-[11px] opacity-50">{t(lang, 'none')}</span>}
          </div>
        </div>
        {opps.length > 0 && (
          <div className="mt-3">
            <div className="text-[10px] uppercase tracking-wide opacity-50 mb-1">{t(lang, 'opportunities')}</div>
            <div className="flex flex-wrap gap-1.5">
              {opps.map((o) => (
                <span key={o} className="rounded-full border border-white/15 px-2 py-0.5 text-[11px]">{o}</span>
              ))}
            </div>
          </div>
        )}
      </section>

      {/* §6 — COMPANY INTELLIGENCE: the living profile, plus §16's per-document status. */}
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <h3 className="text-xs uppercase tracking-wide opacity-60 mb-3">{t(lang, 'profile')}</h3>
        <div className="grid grid-cols-2 gap-x-4 gap-y-3">
          <Stat label={t(lang, 'established')} value={twin.established_year ?? t(lang, 'unknown')} />
          <Stat label={t(lang, 'employees')} value={twin.employee_count ?? t(lang, 'unknown')} />
          <Stat
            label={t(lang, 'emirates')}
            value={emirates.length
              ? emirates.map((e) => emirateLabel(lang, e)).join(lang === 'ar' ? '، ' : ', ')
              : t(lang, 'unknown')}
          />
          <Stat
            label={t(lang, 'confidence')}
            value={twin.ai_confidence != null ? twin.ai_confidence + '%' : t(lang, 'unknown')}
          />
        </div>
        <CapabilityMap map={twin.capability_map} lang={lang} />
        {(twin.documents || []).length > 0 && (
          <div className="mt-4">
            <div className="text-[10px] uppercase tracking-wide opacity-50 mb-1">{t(lang, 'documents')}</div>
            <div className="space-y-1">
              {(twin.documents || []).map((d) => (
                <div key={d.kind} className="flex justify-between text-[11px]">
                  <span className="opacity-70">{d.kind}</span>
                  <span className={
                    d.doc_status === 'VALID' ? 'text-ok-fg'
                      : d.doc_status === 'EXPIRED' ? 'text-danger-fg' : 'opacity-50'
                  }>
                    {d.doc_status}{d.expiry ? ' · ' + String(d.expiry).slice(0, 10) : ''}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}
      </section>
    </div>
  );
}
