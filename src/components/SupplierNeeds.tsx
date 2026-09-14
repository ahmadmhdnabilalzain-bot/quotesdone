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
    <section aria-labelledby="supplier-needs" className="glass depth relative mt-6 overflow-hidden rounded-[22px] p-6 text-start md:p-8">
      <span className="grid-tech grid-tech-sm opacity-40" aria-hidden />
      <h2 id="supplier-needs" className="relative font-head text-[20px] font-semibold tracking-[-0.02em] text-white rtl:tracking-normal">
        {t('serviceTitle')}
      </h2>
      <div className="relative mt-5 grid gap-6 md:grid-cols-2">
        {questions.length > 0 && (
          <div>
            <h3 className="text-[13px] font-semibold text-teal-light">{t('questions')}</h3>
            <ul className="mt-2 space-y-2">
              {questions.map((q) => (
                <li key={q.key} dir="auto" className="text-[14px] leading-relaxed text-paper/90">{q.question}</li>
              ))}
            </ul>
          </div>
        )}
        {documents.length > 0 && (
          <div>
            <h3 className="text-[13px] font-semibold text-teal-light">{t('docs')}</h3>
            <ul className="mt-2 space-y-2">
              {documents.map((d) => (
                <li key={d.item} className="text-[14px] leading-relaxed text-paper/90">
                  <span dir="auto">{d.item}</span>
                  {d.authority && <span dir="auto" className="ms-2 text-[12.5px] text-muted">({d.authority})</span>}
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </section>
  );
}
