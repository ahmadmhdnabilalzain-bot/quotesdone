import { useTranslations } from 'next-intl';

// Anonymous quote-card badges (website audit ADOPT 7, the Houzz pattern without the identity).
// Every badge renders only from a real value; a missing fact is absent, never "0" or a guess.
// Response is shown as the measured share of reveals answered (leads.rv_response_rate), because
// "responds within X h" would need a timing the estate does not record per supplier.
export type BadgeFacts = {
  licence_verified?: boolean | null; response_rate?: number | null;
  jobs_completed?: number | null; rating?: number | null;
};

export function QuoteBadges({ f }: { f: BadgeFacts }) {
  const t = useTranslations('badges');
  const out: string[] = [];
  if (f.licence_verified) out.push(t('licence'));
  if (typeof f.response_rate === 'number' && f.response_rate > 0) out.push(t('response', { p: Math.round(f.response_rate <= 1 ? f.response_rate * 100 : f.response_rate) }));
  if (typeof f.jobs_completed === 'number' && f.jobs_completed > 0) out.push(t('jobs', { n: f.jobs_completed }));
  if (typeof f.rating === 'number' && f.rating > 0) out.push(t('rating', { r: f.rating.toFixed(1) }));
  if (!out.length) return null;
  return (
    <ul className="flex flex-wrap gap-1.5">
      {out.map((b) => (
        <li key={b} className="rounded-full border border-teal/30 bg-teal/[0.06] px-2.5 py-0.5 text-[12px] text-teal-light">{b}</li>
      ))}
    </ul>
  );
}
