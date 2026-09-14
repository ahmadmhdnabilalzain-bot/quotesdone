'use client';

// "WHAT DOES IT COST IN THE UAE?" — published guide bands, answered with no model.
//
// Backed by public_site price_guidance → fn_price_guidance over price_benchmark, the same routine
// and the same refusal rules site_assistant uses: a trade with a recorded gap says so, a word the
// guide has nothing for is named out loud, and a band is never averaged into one figure.
//
// Two uses. On the homepage it is a question box with example chips. On a service page pass
// `slug` — it asks for that trade on mount. SERVICE_TOPIC maps each /services/[slug] to wording the
// router resolves to the right trade (checked on production 14 Sep 2026: "ac maintenance" routed to
// swimming pools and "CCTV installation" to flooring, so those two carry reworded topics). A slug
// with no honest match (handyman, facilities-management) renders nothing rather than a wrong trade.
import { useEffect, useId, useState } from 'react';
import { useLocale, useTranslations } from 'next-intl';
import { useRouter } from '@/i18n/routing';
import { publicSite, saveDraft, fmtNum } from '@/lib/publicSite';
import s from '@/components/home/sealed.module.css';

export const SERVICE_TOPIC: Record<string, string | null> = {
  'false-ceiling': 'false ceiling', 'pest-control': 'pest control', movers: 'movers', flooring: 'flooring',
  'interior-design': 'interior design', 'ac-maintenance': 'HVAC maintenance', 'swimming-pools': 'swimming pools',
  solar: 'solar', 'cctv-security': 'cctv security', 'joinery-kitchens': 'joinery kitchens',
  'ac-duct-cleaning': 'AC duct cleaning', waterproofing: 'waterproofing', electrical: 'electrical work',
  plumbing: 'plumbing', 'smart-home': 'smart home automation', 'aluminium-glass': 'aluminium glass',
  'curtains-blinds': 'curtains blinds', 'tiling-marble': 'tiling marble', painting: 'painting',
  signage: 'signage', landscaping: 'landscaping', cleaning: 'cleaning services',
  handyman: null, 'facilities-management': null,
};

type Band = { item: string; low: number; high: number; unit: string | null; as_of: string | null };
type Res = { ok: boolean; reason?: string; trade?: string; bands?: Band[]; as_of?: string | null; unmatched_terms?: string[]; rate_limited?: boolean };

export function PriceGuide({ slug }: { slug?: string }) {
  const t = useTranslations('price');
  const locale = useLocale();
  const router = useRouter();
  const id = useId();
  const topic = slug ? SERVICE_TOPIC[slug] : undefined;
  const [q, setQ] = useState('');
  const [asked, setAsked] = useState('');
  const [busy, setBusy] = useState(false);
  const [res, setRes] = useState<Res | null>(null);
  const units = t.raw('units') as Record<string, string>;
  const chips = t.raw('chips') as string[];

  async function ask(payload: { question?: string; topic?: string }, label: string) {
    setBusy(true); setRes(null); setAsked(label);
    try { setRes(await publicSite<Res>('price_guidance', { ...payload, lang: locale })); }
    catch (_e) { setRes({ ok: false, reason: 'error' }); }
    finally { setBusy(false); }
  }
  useEffect(() => { if (topic) ask({ topic }, topic); }, [topic]); // eslint-disable-line react-hooks/exhaustive-deps

  if (slug && !topic) return null;
  // On a service page, a failed lookup or a question the guide cannot place shows nothing.
  if (slug && res && !res.ok && res.reason !== 'gap') return null;

  const money = (b: Band) => {
    const lo = Number.isFinite(b.low) ? fmtNum(b.low, locale) : null;
    const hi = Number.isFinite(b.high) ? fmtNum(b.high, locale) : null;
    const span = lo && hi && lo !== hi ? `${lo}–${hi}` : (lo || hi || '');
    return locale === 'ar' ? `${span} درهم` : `AED ${span}`;
  };

  return (
    <div className={`qd-panel qd-panel-hover relative overflow-hidden p-6 text-start md:p-8`}>

      {slug && <h2 className="relative font-head text-[20px] font-semibold tracking-[-0.02em] text-white">{t('titleService')}</h2>}
      {/* method="post": the form is handled in JS (preventDefault); the attribute only stops a
          no-JS submit from putting the question in a GET query string. */}
      {!slug && (
        <form method="post" className="relative" onSubmit={(e) => { e.preventDefault(); if (q.trim().length > 2) ask({ question: q.trim() }, q.trim()); }}>
          <label htmlFor={id} className="text-[13px] font-semibold text-teal-light">{t('label')}</label>
          <div className="mt-2 flex flex-col gap-2 sm:flex-row">
            <input
              id={id} name="question" type="text" inputMode="text" autoComplete="off" enterKeyHint="search"
              dir="auto" value={q} maxLength={300} onChange={(e) => setQ(e.target.value)} placeholder={t('ph')}
              className="min-w-0 flex-1 rounded-full border border-[var(--line2)] bg-navy-deep/60 px-5 py-3 text-[14.5px] text-paper shadow-[var(--key)] outline-none placeholder:text-faint focus-visible:border-teal focus-visible:ring-2 focus-visible:ring-teal/30"
            />
            <button type="submit" disabled={busy} className="btn-key press rounded-full bg-teal px-6 py-3 text-[14px] font-bold text-[#04231F] hover:bg-[#1ED0BC] disabled:opacity-50">
              {busy ? t('busy') : t('submit')}
            </button>
          </div>
          <div className="mt-3 flex flex-wrap gap-2">
            {chips.map((c) => (
              <button key={c} type="button" dir="auto" onClick={() => { setQ(c); ask({ question: c }, c); }}
                className="rounded-full border border-[var(--line)] px-3 py-1.5 text-[12px] text-muted transition-colors hover:border-teal/50 hover:text-white">
                {c}
              </button>
            ))}
          </div>
        </form>
      )}

      <div aria-live="polite" className="relative mt-5">
        {busy && slug && <p className="text-[13px] text-faint">{t('busy')}</p>}
        {res && res.ok && res.bands && (
          <>
            <ul className="divide-y divide-[var(--line)] overflow-hidden rounded-[14px] border border-[var(--line2)]">
              {res.bands.map((b) => (
                <li key={b.item + b.low} className="flex flex-col gap-1 bg-navy-deep/50 px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
                  <span dir="ltr" className="text-start text-[13.5px] text-paper/90 rtl:text-end">{b.item}</span>
                  <span className="shrink-0 font-mono text-[14px] font-semibold text-white">
                    <span dir="ltr">{money(b)}</span>
                    {b.unit && <span className="ms-1.5 font-sans text-[12px] font-normal text-muted">{t('per', { unit: units[b.unit] || b.unit })}</span>}
                  </span>
                </li>
              ))}
            </ul>
            <p className="mt-3 text-[12.5px] text-faint">
              {res.as_of ? t('reviewed', { date: res.as_of }) : t('guide')} {t('filed')}
            </p>
            {!!res.unmatched_terms?.length && (
              <p className="mt-1.5 text-[12.5px] text-gold">{t('unmatched', { terms: res.unmatched_terms.join(', ') })}</p>
            )}
          </>
        )}
        {res && !res.ok && res.reason === 'gap' && <p className="text-[14px] leading-relaxed text-muted">{t('gap')}</p>}
        {res && !res.ok && res.reason === 'not_a_price_question' && <p className="text-[13.5px] text-muted">{t('none')}</p>}
        {res && !res.ok && !['gap', 'not_a_price_question'].includes(res.reason || '') && !slug && (
          <p className="text-[13.5px] text-muted">{res.reason === 'error' || res.rate_limited ? t('error') : t('none')}</p>
        )}
        {res && (res.ok || res.reason === 'gap') && (
          <button
            type="button"
            onClick={() => { saveDraft({ text: asked, category: null, emirate: null }); router.push('/me?draft=1'); }}
            className="press mt-4 rounded-full border border-teal/50 px-5 py-2.5 text-[13.5px] font-semibold text-teal-light transition-colors hover:bg-teal/[0.08]"
          >
            {t('cta')}
          </button>
        )}
      </div>
    </div>
  );
}
