'use client';
// Customer portal - spec §13 (Customer-Supplier Relationship Management) and §9 discovery surfacing.
//
// WHAT IS REAL HERE. Every value rendered below is served today by an endpoint that already
// returns it; nothing is derived into a metric the backend does not measure.
//
//   customer_api action=supplier_history  (supabase/functions/customer_api/index.ts:849)
//     - reveal-gated server-side: 403 "Reveal this supplier first to see their profile."
//       unless a transactions row exists for that quote_id AND belongs to the caller.
//     - returns supplier{company_name,emirate,description,capability_summary,founded_year,
//       company_type,rating_display{value,count,source}}, projects[{category,emirate,month,
//       value_band}] capped at 20, projects_count (== projects.length, so it is a FLOOR at 20).
//
//   customer_api action=my_inquiries      (index.ts:688)
//     - per quote: label, verified, rating, rating_count, years_active, jobs_won, revealed.
//       PRE-REVEAL rating/rating_count/years_active are BANDS ('4.5+', '10+', ...) and
//       rating_source/emirate/win_rate are omitted from the JSON entirely. This file never
//       renders a supplier name or contact before quote.revealed is true.
//     - per inquiry: matched_suppliers = how many suppliers the request actually reached.
//
// WHAT IS NOT REAL, AND SO IS NOT DRAWN. Spec §13 asks for Average Delivery %, Quality % and a
// Relationship Score. Those live in supplier_score (populated for all 20,464 leads) and NO
// customer-facing endpoint selects any of it. The `score` prop below is typed to that table and
// renders when supplied; until customer_api serves it the card SAYS the metrics are not measured
// yet rather than showing an encouraging blank. Same rule for §9: inquiry_matches.match_reason
// and .similarity exist and my_inquiries keeps only a COUNT of them, so DiscoveryReachPanel
// reports the count and says plainly that per-supplier reasons are not served yet.
import { useEffect, useState } from 'react';
import { Card } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { SUPA_ANON, SUPA_FN } from '@/lib/supaEnv';

/* ---------------------------------------------------------------- types --- */

/** A quote row exactly as customer_api action=my_inquiries emits it. */
export type PortalQuote = {
  id: string;
  /** 'Supplier A' - the anonymous label. The only name that exists before reveal. */
  label: string;
  revealed: boolean;
  revealed_at?: string | null;
  verified?: boolean;
  /** number once revealed; a band string ('4.5+') before. */
  rating?: number | string | null;
  /** number once revealed; a band string ('10+') before. */
  rating_count?: number | string | null;
  /** 'QuotesDone' | 'Google' - omitted by the API before reveal. */
  rating_source?: string | null;
  /** number once revealed; a band string before. */
  years_active?: number | string | null;
  jobs_won?: number | null;
  /** percent, omitted by the API before reveal. */
  win_rate?: number | null;
  /** omitted by the API before reveal. */
  emirate?: string | null;
};

/** An inquiry row as customer_api action=my_inquiries emits it (subset used here). */
export type PortalInquiry = {
  id: string;
  status?: string | null;
  /** count of inquiry_matches rows - how many suppliers this request reached. */
  matched_suppliers?: number | null;
  quotes?: { id: string }[];
};

/** public.supplier_score. NOT served to customers yet - see notBuilt in the handover. */
export type SupplierScore = {
  response_rate?: number | null;
  avg_response_hours?: number | null;
  quotes_submitted?: number | null;
  quotes_won?: number | null;
  price_index?: number | null;
  quality_rating?: number | null;
  reliability?: number | null;
};

type HistoryProject = {
  category?: string | null;
  emirate?: string | null;
  month?: string | null;
  value_band?: string | null;
};

type HistorySupplier = {
  company_name?: string | null;
  emirate?: string | null;
  description?: string | null;
  capability_summary?: string | null;
  founded_year?: number | null;
  company_type?: string | null;
  rating_display?: { value?: number | null; count?: number | null; source?: string | null } | null;
};

type HistoryResponse = {
  ok?: boolean;
  error?: string;
  supplier?: HistorySupplier | null;
  projects?: HistoryProject[];
  projects_count?: number;
  /** Not served today. Read opportunistically so the endpoint change alone lights this up. */
  score?: SupplierScore | null;
};

type Lang = 'en' | 'ar';

/* --------------------------------------------------------------- helpers --- */

const S = {
  h2: 'text-[15px] font-bold text-foreground',
  sub: 'text-[13px] leading-relaxed text-muted-foreground',
  note: 'text-[11.5px] leading-relaxed text-muted-foreground/80',
};

const ar = (lang: Lang, arabic: string, english: string) => (lang === 'ar' ? arabic : english);

async function call(path: string, body: unknown, token: string): Promise<HistoryResponse> {
  const r = await fetch(`${SUPA_FN}/${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token || SUPA_ANON}` },
    body: JSON.stringify(body),
  });
  return (await r.json()) as HistoryResponse;
}

/** A stat with no measured value must read as unmeasured, never as zero. */
function Stat({ label, value, hint }: { label: string; value: string | null; hint?: string }) {
  return (
    <div className="rounded-lg border border-border bg-white/[0.02] px-3 py-2.5">
      <div className={cn('text-[17px] font-extrabold', value == null ? 'text-muted-foreground/50' : 'text-foreground')}>
        {value ?? '—'}
      </div>
      <div className="text-[11.5px] text-muted-foreground mt-0.5">{label}</div>
      {hint ? <div className={cn(S.note, 'mt-0.5')}>{hint}</div> : null}
    </div>
  );
}

/** Percentage bar. The number is the accessible content; the bar is decoration. */
function Meter({ label, pct, hint }: { label: string; pct: number; hint?: string }) {
  const w = Math.max(0, Math.min(100, Math.round(pct)));
  return (
    <div className="rounded-lg border border-border bg-white/[0.02] px-3 py-2.5">
      <div className="flex items-baseline justify-between gap-2">
        <span className="text-[11.5px] text-muted-foreground">{label}</span>
        <span className="text-[15px] font-extrabold text-foreground">{w}%</span>
      </div>
      <div aria-hidden className="mt-1.5 h-1.5 w-full rounded-full bg-secondary/60">
        <div className="h-1.5 rounded-full bg-primary" style={{ width: `${w}%` }} />
      </div>
      {hint ? <div className={cn(S.note, 'mt-1')}>{hint}</div> : null}
    </div>
  );
}

/* ------------------------------------------- SupplierRelationshipCard --- */

export type SupplierRelationshipCardProps = {
  /** A quote row from my_inquiries. Drives identity gating: nothing is named until revealed. */
  quote: PortalQuote;
  /** Customer access token. Only used if the history panel is expanded. */
  token: string;
  lang?: Lang;
  /** public.supplier_score, once customer_api serves it. Omit until then. */
  score?: SupplierScore | null;
  /** false hides the "View full history" disclosure entirely. Default true. */
  allowHistory?: boolean;
};

/**
 * Spec §13 relationship card for ONE supplier on ONE quote.
 * Pre-reveal it shows the anonymous label plus the coarse bands the API serves and nothing else.
 * Post-reveal it shows exact figures and can expand the full history panel.
 */
export function SupplierRelationshipCard({
  quote,
  token,
  lang = 'en',
  score = null,
  allowHistory = true,
}: SupplierRelationshipCardProps) {
  const [open, setOpen] = useState(false);
  const revealed = !!quote.revealed;
  const panelId = `supplier-history-${quote.id}`;

  const ratingText =
    quote.rating == null || quote.rating === ''
      ? null
      : typeof quote.rating === 'number'
        ? `★ ${quote.rating.toFixed(1)}`
        : `★ ${quote.rating}`;
  const ratingHint =
    quote.rating_count == null || quote.rating_count === ''
      ? undefined
      : `${quote.rating_count} ${ar(lang, 'تقييم', 'reviews')}${quote.rating_source ? ` · ${quote.rating_source}` : ''}`;

  const yearsText = quote.years_active == null || quote.years_active === '' ? null : String(quote.years_active);
  const jobsWon = typeof quote.jobs_won === 'number' ? quote.jobs_won : null;

  return (
    <Card className="p-3.5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div className={S.h2}>
          {quote.label}
          {quote.verified ? (
            <span className="text-primary text-[11px] font-bold"> ✓ {ar(lang, 'موثّق', 'verified')}</span>
          ) : null}
        </div>
        <div className={S.note}>
          {revealed
            ? ar(lang, 'الملف الكامل مفتوح', 'Full profile unlocked')
            : ar(lang, 'الهوية مخفية حتى تكشف المورّد', 'Identity hidden until you reveal')}
        </div>
      </div>

      <div className="mt-2.5 grid gap-2 sm:grid-cols-3">
        <Stat label={ar(lang, 'التقييم', 'Rating')} value={ratingText} hint={ratingHint} />
        <Stat
          label={ar(lang, 'وظائف فاز بها عبر QuotesDone', 'Jobs won via QuotesDone')}
          value={jobsWon == null ? null : String(jobsWon)}
        />
        <Stat label={ar(lang, 'سنوات النشاط', 'Years active')} value={yearsText} />
      </div>

      {revealed && typeof quote.win_rate === 'number' ? (
        <div className="mt-2">
          <Meter
            label={ar(lang, 'نسبة الفوز بالعروض', 'Quote win rate')}
            pct={quote.win_rate}
            hint={ar(
              lang,
              'حصة عروض هذا المورّد التي انتهت بتعاقد على QuotesDone.',
              'Share of this supplier’s quotes that ended in a hire on QuotesDone.',
            )}
          />
        </div>
      ) : null}

      {/* Spec §13 asks for delivery, quality and a relationship score. supplier_score holds the
          nearest real measures and no customer endpoint serves them yet, so say that instead of
          drawing an empty gauge. quality_rating is deliberately NOT drawn: fn_supplier_score_refresh
          sets it to leads.rating, the same number already shown as ★ above - a second gauge over
          one number would read as two independent measurements. */}
      {score ? (
        <div className="mt-2 grid gap-2 sm:grid-cols-2">
          {typeof score.response_rate === 'number' ? (
            <Meter
              label={ar(lang, 'معدّل الاستجابة', 'Response rate')}
              pct={score.response_rate}
              hint={
                typeof score.avg_response_hours === 'number'
                  ? ar(
                      lang,
                      `متوسط الردّ ${Math.round(score.avg_response_hours)} ساعة`,
                      `Replies in ~${Math.round(score.avg_response_hours)}h on average`,
                    )
                  : undefined
              }
            />
          ) : null}
          {typeof score.reliability === 'number' ? (
            <Meter
              label={ar(lang, 'درجة الموثوقية', 'Reliability score')}
              pct={score.reliability}
              hint={ar(
                lang,
                'يجمع سرعة الردّ ونسبة الفوز والتوثيق، وتُخصم منه الرفض واسترداد عدم الاستجابة.',
                'Blends response speed, win rate and verification; rejections and non-response refunds subtract.',
              )}
            />
          ) : null}
        </div>
      ) : (
        <div className={cn(S.note, 'mt-2')}>
          {ar(
            lang,
            'لا نعرض بعد معدّل التسليم أو درجة العلاقة: هذه المقاييس محسوبة لدينا لكن لم تُتَح بعد لواجهة العميل.',
            'Delivery rate, quality score and relationship score are not shown yet — we compute them internally but they are not served to the customer portal.',
          )}
        </div>
      )}

      {allowHistory && revealed ? (
        <div className="mt-2.5">
          <button
            type="button"
            aria-expanded={open}
            aria-controls={panelId}
            onClick={() => setOpen((v) => !v)}
            className="rounded-md border border-border bg-transparent px-2.5 py-1.5 text-[12.5px] font-semibold text-primary hover:bg-primary/10 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          >
            {open ? ar(lang, 'إخفاء السجل الكامل', 'Hide full history') : ar(lang, 'عرض السجل الكامل', 'View full history')}
          </button>
          {open ? (
            <div id={panelId} className="mt-2.5">
              <SupplierHistoryPanel quoteId={quote.id} token={token} lang={lang} revealed score={score} />
            </div>
          ) : null}
        </div>
      ) : null}

      {allowHistory && !revealed ? (
        <div className={cn(S.note, 'mt-2.5')}>
          {ar(
            lang,
            'سجل مشاريع هذا المورّد ومعلومات التواصل تظهر بعد كشفه.',
            'This supplier’s project history and contact details appear after you reveal them.',
          )}
        </div>
      ) : null}
    </Card>
  );
}

/* ----------------------------------------------- SupplierHistoryPanel --- */

export type SupplierHistoryPanelProps = {
  /** quotes.id. The endpoint resolves the supplier from it and checks YOUR transaction. */
  quoteId: string;
  token: string;
  lang?: Lang;
  /**
   * quote.revealed. When false the panel renders the locked state and issues NO request -
   * the server would answer 403 anyway. Defaults to true so a caller that already gated it
   * upstream does not have to thread the flag.
   */
  revealed?: boolean;
  /** public.supplier_score, once customer_api serves it. Omit until then. */
  score?: SupplierScore | null;
};

/**
 * Spec §13 full history: supplier profile plus up to 20 past QuotesDone projects
 * (category / emirate / month / value band). Reveal-gated on the server and here.
 */
export function SupplierHistoryPanel({
  quoteId,
  token,
  lang = 'en',
  revealed = true,
  score: scoreProp = null,
}: SupplierHistoryPanelProps) {
  const [data, setData] = useState<HistoryResponse | null>(null);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(true);

  useEffect(() => {
    if (!revealed) {
      setBusy(false);
      return;
    }
    let on = true;
    setBusy(true);
    setErr('');
    call('customer_api', { action: 'supplier_history', quote_id: quoteId }, token)
      .then((j) => {
        if (!on) return;
        setBusy(false);
        if (j && j.ok) setData(j);
        else setErr((j && j.error) || 'Could not load this supplier’s history.');
      })
      .catch(() => {
        if (!on) return;
        setBusy(false);
        setErr(ar(lang, 'تعذّر تحميل سجل المورّد.', 'Could not load this supplier’s history.'));
      });
    return () => {
      on = false;
    };
  }, [quoteId, token, revealed, lang]);

  if (!revealed) {
    return (
      <Card className="p-3.5">
        <div className={S.h2}>{ar(lang, 'السجل مقفل', 'History locked')}</div>
        <div className={cn(S.sub, 'mt-1')}>
          {ar(
            lang,
            'اكشف هذا المورّد أولاً لرؤية ملفه وسجل مشاريعه.',
            'Reveal this supplier first to see their profile and project history.',
          )}
        </div>
      </Card>
    );
  }

  if (busy) {
    return (
      <Card className="p-3.5">
        <div className={S.sub}>{ar(lang, 'جارٍ تحميل سجل المورّد…', 'Loading supplier history…')}</div>
      </Card>
    );
  }

  if (err) {
    return (
      <Card className="p-3.5">
        <div className={cn(S.sub, 'text-red-300')}>{err}</div>
      </Card>
    );
  }

  const sup = data?.supplier ?? null;
  const projects = data?.projects ?? [];
  const count = typeof data?.projects_count === 'number' ? data.projects_count : projects.length;
  // The endpoint caps at 20 and reports projects.length, so 20 means "at least 20", not "20".
  const capped = count >= 20;
  const rd = sup?.rating_display ?? null;
  // Prefer whatever the endpoint sends once it sends it; the prop is the integrator's override.
  const score = scoreProp ?? data?.score ?? null;

  const byCategory = projects.reduce<Record<string, number>>((acc, p) => {
    const k = (p.category || '').trim();
    if (k) acc[k] = (acc[k] || 0) + 1;
    return acc;
  }, {});
  const categories = Object.entries(byCategory).sort((a, b) => b[1] - a[1]);

  if (!sup) {
    return (
      <Card className="p-3.5">
        <div className={S.h2}>{ar(lang, 'لا يوجد ملف لهذا المورّد', 'No profile for this supplier')}</div>
        <div className={cn(S.sub, 'mt-1')}>
          {ar(
            lang,
            'سجل هذا المورّد غير متاح. تفاصيل التواصل ما زالت في بطاقة العرض.',
            'This supplier has no profile record. Their contact details are still on the quote card.',
          )}
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-3.5">
      <div className={S.h2}>{sup.company_name || ar(lang, 'مورّد', 'Supplier')}</div>
      <div className={cn(S.sub, 'mt-0.5')}>
        {[
          sup.company_type,
          sup.emirate,
          sup.founded_year ? ar(lang, `تأسست ${sup.founded_year}`, `Founded ${sup.founded_year}`) : null,
        ]
          .filter(Boolean)
          .join(' · ')}
      </div>

      {rd && rd.value != null ? (
        <div className={cn(S.sub, 'mt-1')}>
          <span className="text-accent font-semibold">★ {Number(rd.value).toFixed(1)}</span>
          {` · ${rd.count ?? 0} ${ar(lang, 'تقييم', 'reviews')}${rd.source ? ` (${rd.source})` : ''}`}
        </div>
      ) : (
        <div className={cn(S.note, 'mt-1')}>{ar(lang, 'لا توجد تقييمات لهذا المورّد بعد.', 'No reviews for this supplier yet.')}</div>
      )}

      {sup.capability_summary || sup.description ? (
        <div className={cn(S.sub, 'mt-1.5')}>{sup.capability_summary || sup.description}</div>
      ) : null}

      {score && typeof score.quotes_submitted === 'number' ? (
        <div className="mt-2.5 grid gap-2 sm:grid-cols-2">
          <Stat label={ar(lang, 'عروض مقدَّمة', 'Quotes submitted')} value={String(score.quotes_submitted)} />
          <Stat
            label={ar(lang, 'عروض فائزة', 'Quotes won')}
            value={typeof score.quotes_won === 'number' ? String(score.quotes_won) : null}
          />
        </div>
      ) : null}

      <div className="mt-3 border-t border-border/60 pt-2.5">
        <div className={S.h2}>{ar(lang, 'مشاريع سابقة على QuotesDone', 'Past projects on QuotesDone')}</div>

        {count === 0 ? (
          // PRODUCTION HAS ZERO TRANSACTIONS. This must read as "none recorded", never as reassurance.
          <div className={cn(S.sub, 'mt-1')}>
            {ar(
              lang,
              'لم يُسجَّل لهذا المورّد أي مشروع عبر QuotesDone حتى الآن. هذا لا يعني أنه بلا خبرة — يعني فقط أننا لم نسجّل له عملاً هنا بعد.',
              'No projects recorded for this supplier through QuotesDone yet. That is not a judgement on their experience — it only means we have not recorded work for them here.',
            )}
          </div>
        ) : (
          <>
            <div className={cn(S.sub, 'mt-1')}>
              {capped
                ? ar(
                    lang,
                    'نعرض آخر 20 مشروعاً؛ قد يكون هناك المزيد.',
                    'Showing the 20 most recent — there may be more.',
                  )
                : ar(lang, `${count} مشروعاً مسجّلاً.`, `${count} recorded ${count === 1 ? 'project' : 'projects'}.`)}
            </div>

            {categories.length ? (
              <div className="mt-1.5 flex flex-wrap gap-1.5">
                {categories.map(([c, n]) => (
                  <span
                    key={c}
                    className="rounded-full bg-secondary/50 px-2 py-0.5 text-[11.5px] font-semibold text-secondary-foreground"
                  >
                    {c} · {n}
                  </span>
                ))}
              </div>
            ) : null}

            <div className="mt-2 overflow-x-auto">
              <table className="w-full min-w-[380px] border-collapse text-[12.5px]">
                <caption className="sr-only">
                  {ar(lang, 'مشاريع سابقة لهذا المورّد', 'Past projects for this supplier')}
                </caption>
                <thead>
                  <tr className="text-muted-foreground">
                    <th scope="col" className="py-1 text-start font-semibold">
                      {ar(lang, 'الفئة', 'Category')}
                    </th>
                    <th scope="col" className="py-1 text-start font-semibold">
                      {ar(lang, 'الإمارة', 'Emirate')}
                    </th>
                    <th scope="col" className="py-1 text-start font-semibold">
                      {ar(lang, 'الشهر', 'Month')}
                    </th>
                    <th scope="col" className="py-1 text-end font-semibold">
                      {ar(lang, 'نطاق القيمة', 'Value band')}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {projects.map((p, i) => (
                    <tr key={i} className="border-t border-border/50 text-foreground">
                      <td className="py-1.5 pe-2">{p.category || '—'}</td>
                      <td className="py-1.5 pe-2">{p.emirate || '—'}</td>
                      <td className="py-1.5 pe-2">{p.month || '—'}</td>
                      <td className="py-1.5 text-end">{p.value_band || '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className={cn(S.note, 'mt-1.5')}>
              {ar(
                lang,
                'قيم المشاريع معروضة كنطاقات، وأسماء العملاء لا تُعرض أبداً.',
                'Project values are shown as bands, and other customers are never named.',
              )}
            </div>
          </>
        )}
      </div>
    </Card>
  );
}

/* ---------------------------------------------- DiscoveryReachPanel --- */

export type DiscoveryReachPanelProps = {
  /** An inquiry row from my_inquiries. matched_suppliers is the only reach figure served. */
  inquiry: PortalInquiry;
  lang?: Lang;
};

/**
 * Spec §9 surfacing. my_inquiries serves matched_suppliers - how many suppliers the request
 * actually reached. Telling "waiting for quotes" apart from "this reached nobody" is the entire
 * point; it must never read as encouragement when the count is zero.
 */
export function DiscoveryReachPanel({ inquiry, lang = 'en' }: DiscoveryReachPanelProps) {
  const reached = typeof inquiry.matched_suppliers === 'number' ? inquiry.matched_suppliers : null;
  const quotes = inquiry.quotes?.length ?? 0;

  if (reached == null) {
    return null;
  }

  if (reached === 0) {
    return (
      <Card className="p-3.5 border-accent/40">
        <div className={S.h2}>{ar(lang, 'لم يصل هذا الطلب إلى أي مورّد بعد', 'This request has not reached any supplier yet')}</div>
        <div className={cn(S.sub, 'mt-1')}>
          {ar(
            lang,
            'لم نطابق طلبك مع أي مورّد حتى الآن، لذلك لا تتوقع عروضاً بعد. سنتواصل معك إذا احتجنا تفاصيل إضافية لتوسيع المطابقة.',
            'We have not matched your request to any supplier yet, so no quotes are on their way. We will contact you if we need more detail to widen the match.',
          )}
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-3.5">
      <div className={S.h2}>
        {ar(lang, `وصل طلبك إلى ${reached} مورّداً`, `Your request reached ${reached} supplier${reached === 1 ? '' : 's'}`)}
      </div>
      <div className={cn(S.sub, 'mt-1')}>
        {quotes === 0
          ? ar(
              lang,
              'لم يصل أي عرض بعد. المورّدون الذين طُوبقوا لم يردّوا حتى الآن.',
              'No quotes back yet — the matched suppliers have not responded so far.',
            )
          : ar(
              lang,
              `${quotes} من ${reached} ردّوا بعرض سعر.`,
              `${quotes} of ${reached} have replied with a quote.`,
            )}
      </div>
      {/* match_reason IS served now (customer_api my_inquiries), but only on a revealed quote: the
          adjudicator that writes it is handed each candidate as "#id — Company Name" and answers in
          free text, so a reason can name the supplier. Saying that plainly beats implying the
          reason is missing. similarity stays unserved because every row of it is null. */}
      <div className={cn(S.note, 'mt-1.5')}>
        {ar(
          lang,
          'نسجّل سبب مطابقة كل مورّد، ويظهر لك سبب أي مورّد بعد كشفه — فقد يذكر السبب اسم الشركة. أما درجة التطابق الرقمية فغير مُسجّلة لأي مورّد حتى الآن.',
          'We record why each supplier was matched, and you can read that reason for any supplier once you reveal them — the reason can name the company, so it stays hidden until then. A numeric match score is not recorded for any supplier yet.',
        )}
      </div>
    </Card>
  );
}
