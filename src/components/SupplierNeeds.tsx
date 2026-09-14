// "WHAT SUPPLIERS WILL NEED FOR THIS JOB" on /services/[slug] (website audit SM2). The same answer the
// homepage BriefBox gives a visitor — the trade's required plain-language questions
// (category_specs.fields question_plain_en/ar) and its compliance documents — asked once per trade
// on the server through public_site route_brief and cached for a day. Anything but a recognised
// trade renders nothing: a failed call, a rate limit, or a trade the router does not place.
//
// BRIEF_TOPIC is the wording route_brief places on the right trade. It is not PriceGuide's
// SERVICE_TOPIC: the two actions route differently. Measured on production 14 Sep 2026 (route_brief,
// lang en): the 14 wordings below resolve to the category in the trailing comment. These did not
// resolve to any trade and are left out, so their pages show no section: pest-control, movers,
// interior-design, solar, plumbing, painting, signage, landscaping, handyman, facilities-management.
import { getTranslations } from 'next-intl/server';
import { SUPA_ANON, SUPA_FN } from '@/lib/supaEnv';

const BRIEF_TOPIC: Record<string, string> = {
  flooring: 'flooring', // flooring
  'tiling-marble': 'tiling marble', // flooring
  'false-ceiling': 'gypsum false ceiling installation', // gypsum
  'ac-maintenance': 'HVAC maintenance', // hvac
  'ac-duct-cleaning': 'AC duct cleaning', // cleaning
  cleaning: 'cleaning services', // cleaning
  'cctv-security': 'cctv security', // security
  waterproofing: 'waterproofing', // waterproofing
  electrical: 'electrical work', // electrical
  'smart-home': 'smart home automation', // smart-home
  'aluminium-glass': 'aluminium glass', // aluminium
  'curtains-blinds': 'curtains blinds', // fitout
  'swimming-pools': 'swimming pool construction', // swimming-pools
  'joinery-kitchens': 'kitchen cabinets joinery', // kitchens
};

type Brief = {
  ok?: boolean;
  recognised?: boolean;
  questions?: { key: string; question: string }[];
  documents?: { item: string; authority: string | null }[];
};

async function routeBrief(text: string, lang: 'en' | 'ar'): Promise<Brief | null> {
  if (!SUPA_FN.startsWith('http')) return null;
  try {
    const r = await fetch(`${SUPA_FN}/public_site`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: SUPA_ANON, Authorization: `Bearer ${SUPA_ANON}` },
      body: JSON.stringify({ action: 'route_brief', text, lang }),
      next: { revalidate: 86400 },
      signal: AbortSignal.timeout(8000),
    });
    if (r.status !== 200) return null;
    const j = (await r.json()) as Brief;
    return j && j.ok && j.recognised ? j : null;
  } catch {
    return null;
  }
}

export async function SupplierNeeds({ service, locale }: { service: string; locale: string }) {
  const topic = BRIEF_TOPIC[service];
  if (!topic) return null;
  const lang = locale === 'ar' ? 'ar' : 'en';
  const b = await routeBrief(topic, lang);
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
