import { useTranslations } from 'next-intl';

// Anonymous quote-card badges (website audit ADOPT 7, the Houzz pattern without the identity).
// Every badge renders only from a real value; a missing fact is absent, never "0" or a guess.
// Response is shown as the measured share of reveals answered (leads.rv_response_rate), because
// "responds within X h" would need a timing the estate does not record per supplier.
export type BadgeFacts = {
  licence_verified?: boolean | null; documents_complete?: boolean | null; response_rate?: number | null;
  jobs_completed?: number | null; rating?: number | null;
};

// THE PORTAL'S LANGUAGE IS STATE, NOT THE URL (customer-portal audit 21 Sep 2026, item 23). next-intl
// binds useTranslations to the locale the page was SERVED in, so a customer who switched to Arabic
// inside /me kept "Licence verified" and "Rated 4.0/5" in English. The portal passes its own `lang`
// and these strings are read from here — the same words as messages/{en,ar}.json "badges",
// which the public WorkedCase still reads through next-intl.
const WORDS = {
  en: { licence: 'Licence verified', docs: 'Documents complete', response: (p: number) => `Responds to ${p}% of reveals`, jobs: (n: number) => `${n} jobs completed on QuotesDone`, rating: (r: string) => `Rated ${r}/5` },
  ar: { licence: 'رخصة موثّقة', docs: 'مستندات مكتملة', response: (p: number) => `يردّ على ${p}% من طلبات الكشف`, jobs: (n: number) => `${n} مشروعاً مكتملاً عبر QuotesDone`, rating: (r: string) => `التقييم ${r}/5` },
};

export function QuoteBadges({ f, lang }: { f: BadgeFacts; lang?: 'en' | 'ar' }) {
  const t = useTranslations('badges');
  const w = lang ? WORDS[lang] : null;
  const out: string[] = [];
  if (f.licence_verified) out.push(w ? w.licence : t('licence'));
  if (f.documents_complete) out.push(w ? w.docs : t('docs'));
  if (typeof f.response_rate === 'number' && f.response_rate > 0) { const p = Math.round(f.response_rate <= 1 ? f.response_rate * 100 : f.response_rate); out.push(w ? w.response(p) : t('response', { p })); }
  if (typeof f.jobs_completed === 'number' && f.jobs_completed > 0) out.push(w ? w.jobs(f.jobs_completed) : t('jobs', { n: f.jobs_completed }));
  if (typeof f.rating === 'number' && f.rating > 0) { const r = f.rating.toFixed(1); out.push(w ? w.rating(r) : t('rating', { r })); }
  if (!out.length) return null;
  return (
    <ul className="flex flex-wrap gap-1.5">
      {out.map((b) => (
        <li key={b} className="rounded-full border border-teal/30 bg-teal/[0.06] px-2.5 py-0.5 text-[12px] text-teal-light">{b}</li>
      ))}
    </ul>
  );
}
