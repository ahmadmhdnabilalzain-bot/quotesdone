// "WHAT SUPPLIERS WILL NEED FOR THIS JOB" on /services/[slug] (website audit SM2): the trade's required
// plain-language questions (category_specs.fields question_plain_en/ar) and its compliance documents,
// read once per trade on the server through public_site trade_needs and cached for a day.
//
// The page already knows its trade, so it names the category instead of asking the router. Measured
// 14 Sep 2026: routing a trade NAME through route_brief placed only 14 of the 24 services, and one call
// per page per locale spent most of the visitor rate limit during a build. SERVICE_CATEGORY is the
// direct map; a failed call renders nothing.
import { getTranslations } from 'next-intl/server';
import { SUPA_ANON, SUPA_FN } from '@/lib/supaEnv';

export const SERVICE_CATEGORY: Record<string, string> = {
  'false-ceiling': 'gypsum', 'pest-control': 'pest', movers: 'movers', flooring: 'flooring',
  'interior-design': 'interior-design', 'ac-maintenance': 'hvac', 'ac-duct-cleaning': 'hvac',
  'swimming-pools': 'swimming-pools', solar: 'solar', 'cctv-security': 'security',
  'joinery-kitchens': 'kitchens', waterproofing: 'waterproofing', electrical: 'electrical',
  plumbing: 'plumbing', 'smart-home': 'smart-home', 'aluminium-glass': 'aluminium',
  'curtains-blinds': 'blinds-curtains', 'tiling-marble': 'tiling', painting: 'painting',
  signage: 'signage', landscaping: 'landscaping', cleaning: 'cleaning',
  handyman: 'general-services-other', 'facilities-management': 'general-services-other',
};

type Needs = {
  ok?: boolean;
  questions?: { key: string; question: string }[];
  documents?: { item: string; authority: string | null }[];
};

async function tradeNeeds(category: string, lang: 'en' | 'ar'): Promise<Needs | null> {
  if (!SUPA_FN.startsWith('http')) return null;
  try {
    const r = await fetch(`${SUPA_FN}/public_site`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: SUPA_ANON, Authorization: `Bearer ${SUPA_ANON}` },
      body: JSON.stringify({ action: 'trade_needs', category, lang }),
      next: { revalidate: 86400 },
      signal: AbortSignal.timeout(8000),
    });
    if (r.status !== 200) return null;
    const j = (await r.json()) as Needs;
    return j && j.ok ? j : null;
  } catch {
    return null;
  }
}

export async function SupplierNeeds({ service, locale }: { service: string; locale: string }) {
  const category = SERVICE_CATEGORY[service];
  if (!category) return null;
  const lang = locale === 'ar' ? 'ar' : 'en';
  const b = await tradeNeeds(category, lang);
  const questions = b?.questions ?? [];
  const documents = b?.documents ?? [];
  if (!questions.length && !documents.length) return null;
  const t = await getTranslations({ locale, namespace: 'brief' });
  return (
    <section aria-labelledby="supplier-needs" className="qd-frame qd-grain relative mt-8 overflow-hidden text-start">
      <div className="qd-frame-bar"><i /><i /><i />
        <h2 id="supplier-needs" className="ms-2 truncate font-mono text-label text-muted">{t('serviceTitle')}</h2>
      </div>
      <div className="grid md:grid-cols-2 md:divide-x md:divide-[var(--line)] rtl:md:divide-x-reverse">
        {questions.length > 0 && (
          <div className="p-6 md:p-7">
            <h3 className="font-mono text-label uppercase tracking-caps text-teal-light">{t('questions')}</h3>
            <ol className="mt-4 flex flex-col divide-y divide-[var(--line)]">
              {questions.map((q, i) => (
                <li key={q.key} className="flex gap-3 py-3 first:pt-0">
                  <span className="tabular shrink-0 font-mono text-label text-faint">{String(i + 1).padStart(2, '0')}</span>
                  <span dir="auto" className="text-body text-paper/90">{q.question}</span>
                </li>
              ))}
            </ol>
          </div>
        )}
        {documents.length > 0 && (
          <div className="border-t border-line p-6 md:border-t-0 md:p-7">
            <h3 className="font-mono text-label uppercase tracking-caps text-teal-light">{t('docs')}</h3>
            <ul className="mt-4 flex flex-col divide-y divide-[var(--line)]">
              {documents.map((d) => (
                <li key={d.item} className="flex flex-col gap-1 py-3 first:pt-0">
                  <span dir="auto" className="text-body text-paper/90">{d.item}</span>
                  {d.authority && <span dir="auto" className="font-mono text-label text-faint">{d.authority}</span>}
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </section>
  );
}
