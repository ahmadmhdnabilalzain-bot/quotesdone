'use client';
// THE PORTAL TOLD A CUSTOMER WHAT HAPPENED AND NEVER HELPED THEM DECIDE.
//
// 13 Aug 2026, the founder's own words for the gap: "the comparison exists but nothing tells them
// which quote to take and why, in their own terms; nothing shows them what a job like theirs
// normally costs in the UAE before they get quotes; nothing follows up: a request goes quiet and
// the portal never says what to do about it."
//
// Three answers, one call - customer_portal action='decision_support', which is
// public.fn_customer_decision_support run server-side. This component fetches nothing else and
// computes no figure of its own beyond formatting.
//
// NOTHING HERE IS INVENTED, AND THAT IS THE HARD PART. On the day this shipped the estate held 0
// inquiries and 0 quotes, so every branch had to have an empty state that is a real statement:
//
//   - No price range is printed until a category has at least min_price_n quoted jobs behind it.
//     A median over two quotes is an anecdote dressed as a statistic, and the founder's standing
//     rule is that we never state what we have not measured. The panel says so out loud and fills
//     in on its own when the quotes exist.
//   - No quote is crowned "best". A single score would hide the trade-off the customer is actually
//     making. We name the cheapest and the fastest and, when they differ, say what choosing one
//     costs in dirhams and in days. That is the decision, in their terms.
//   - A quote whose lead time we could not parse never wins the speed comparison, and the count of
//     stated lead times is shown, so "fastest" is never a guess presented as a fact.
import { useEffect, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { useDelayedFlag } from '@/components/ui/busy';
import { cn } from '@/lib/utils';
import { categoryLabel } from '@/lib/categoryLabel';
import { SUPA_ANON, SUPA_FN } from '@/lib/supaEnv';
import { take } from '@/components/me/prefetch';

const L = (lang: string, en: string, ar: string) => (lang === 'ar' ? ar : en);
const S = {
  label: 'text-[11px] uppercase tracking-wide text-muted-foreground',
  sub: 'text-[12.5px] text-muted-foreground',
  head: 'text-[13.5px] font-bold text-foreground',
};
const aed = (n: unknown) => {
  const v = Number(n);
  return Number.isFinite(v) ? 'AED ' + Math.round(v).toLocaleString('en-US') : null;
};
const days = (n: unknown, lang: string) => {
  const v = Number(n);
  return Number.isFinite(v) ? v + ' ' + L(lang, v === 1 ? 'day' : 'days', 'يوم') : null;
};

type Rec = {
  inquiry_id: string; summary?: string; category?: string; quotes?: number;
  cheapest_price?: number; saving_vs_next?: number | null;
  fastest_days?: number | null; same_quote_wins?: boolean;
  days_sooner?: number | null; spread?: number | null; lead_times_stated?: number;
};
type Mkt = {
  category?: string; emirate?: string | null; price_known?: boolean; price_n?: number;
  median?: number | null; p25?: number | null; p75?: number | null;
  suppliers_covering?: number; suppliers_confirmed?: number; avg_days_to_quote?: number | null;
};
type Chase = {
  inquiry_id: string; summary?: string; category?: string;
  age_days?: number; invited?: number; quotes?: number; state?: string;
};

// One sentence per state, each ending in the thing the customer can actually do. Written as
// statements about THEIR request, not about our pipeline: "no supplier has replied" is their
// situation; "0 inquiry_matches rows" is ours.
// A request's name: a button to that request when the portal can open one, a heading when not.
function Head({ id, onOpen, children }: { id: string; onOpen?: (id: string) => void; children: React.ReactNode }) {
  if (!onOpen || !id) return <div className={S.head}>{children}</div>;
  return (
    <button type="button" onClick={() => onOpen(String(id))}
      className={cn(S.head, 'text-start underline-offset-2 hover:text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring')}>
      {children}
    </button>
  );
}

const CHASE_COPY: Record<string, [string, string]> = {
  not_yet_sent: [
    'This has not reached any supplier yet. Open it and check the trade is right — that is what we match on.',
    'لم يصل هذا إلى أي مورّد بعد. افتحه وتأكد من صحة النشاط، فهو أساس المطابقة.',
  ],
  no_replies: [
    'Suppliers have it and none has quoted yet. Adding a drawing or a target date is what usually unblocks this.',
    'وصل الطلب إلى الموردين ولم يسعّر أحد بعد. إضافة مخطط أو تاريخ مستهدف هو ما يحرّك هذا عادةً.',
  ],
  only_one: [
    'One quote is not a comparison. Widening the trade or the emirate is the quickest way to a second.',
    'عرض واحد ليس مقارنة. توسيع المهنة أو الإمارة هو أسرع طريق للحصول على عرض ثانٍ.',
  ],
  undecided: [
    'You have quotes waiting and have not chosen. Comparing them is free; you only pay to reveal the one you want.',
    'لديك عروض تنتظر ولم تختر بعد. المقارنة مجانية، وتدفع فقط للكشف عن العرض الذي تختاره.',
  ],
};

// onOpenRfq (14 Sep 2026). There was no open-a-request-by-id target, so these were headings; the
// copy under them says "Open it" and nothing could be opened. The portal now has one (Dashboard's
// openRfq: My requests, that card opened and scrolled to), so each recommendation and each quiet
// request is a button to the request it is about. Without the prop they stay headings.
export function DecisionSupport({ token, lang = 'en', onOpenRfq }:
  { token: string; lang?: string; onOpenRfq?: (inquiryId: string) => void }) {
  const [rec, setRec] = useState<Rec[]>([]);
  const [mkt, setMkt] = useState<Mkt[]>([]);
  const [chase, setChase] = useState<Chase[]>([]);
  const [minN, setMinN] = useState(5);
  const [state, setState] = useState<'loading' | 'ok' | 'failed'>('loading');
  const slow = useDelayedFlag(state === 'loading');

  useEffect(() => {
    let on = true;
    (async () => {
      try {
        // First render takes the request CustomerPortal started beside the kyc gate (prefetch.ts).
        const j: any = await take(token, 'decision_support', async () => {
          const r = await fetch(`${SUPA_FN}/customer_portal`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token || SUPA_ANON}` },
            body: JSON.stringify({ action: 'decision_support', lang }),
          });
          return r.json().catch(() => null);
        }).catch(() => null);
        if (!on) return;
        if (!j || !j.ok) { setState('failed'); return; }
        setRec(Array.isArray(j.recommend) ? j.recommend : []);
        setMkt(Array.isArray(j.market) ? j.market : []);
        setChase(Array.isArray(j.chase) ? j.chase : []);
        if (Number.isFinite(Number(j.min_price_n))) setMinN(Number(j.min_price_n));
        setState('ok');
      } catch { if (on) setState('failed'); }
    })();
    return () => { on = false; };
    // NOT [token, lang]. `lang` starts at the URL's guess and is corrected to the REGISTERED locale
    // when customer_api my_inquiries answers (CustomerPortal onServedLocale), so on /ar it changed
    // once per load and re-ran this effect — a second customer_portal:decision_support round trip
    // that returns byte-identical data, because customer_portal deliberately reads customers.locale
    // and IGNORES the `lang` in the body (see its header). Measured 18 Sep 2026: every /ar portal
    // load made 7 function calls where /en made 6, in all 16 runs of
    // scripts/e2e/portal_local_shell_hydration.mjs, and /ar settled ~300 ms later for it.
    // `lang` is still used for this panel's own rendering; only the refetch is dropped.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  // A panel that could only ever be empty is a dead end with a heading on it. With nothing to
  // recommend, nothing quiet and no category history, this renders nothing at all and the
  // overview keeps the space.
  const empty = !rec.length && !mkt.length && !chase.length;
  // Below 150ms this panel stays absent rather than flashing bars it is about to replace — and a
  // load that resolves to "nothing to say" was showing a heading over an empty card. See busy.tsx.
  if (state === 'loading') {
    if (!slow) return null;
    return (
      <Card className="p-3.5" aria-busy="true" aria-label={L(lang, 'Working out what to recommend…', 'جارٍ تحديد ما نوصي به…')}>
        <div className={S.label}>{L(lang, 'Help me decide', 'ساعدني في القرار')}</div>
        <div className="mt-2 space-y-1.5">
          <Skeleton className="h-3.5 w-2/5" />
          <Skeleton className="h-3 w-full" />
          <Skeleton className="h-3 w-4/5" />
        </div>
      </Card>
    );
  }
  if (state === 'ok' && empty) return null;
  if (state === 'failed') {
    return (
      <Card className="p-3.5">
        <div className={S.label}>{L(lang, 'Help me decide', 'ساعدني في القرار')}</div>
        <div className={cn(S.sub, 'mt-1')}>
          {L(lang, 'We could not work this out just now. Your requests and quotes are unaffected.',
                   'تعذّر حساب هذا الآن. طلباتك وعروضك غير متأثرة.')}
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-3.5">
      <div className={S.label}>{L(lang, 'Help me decide', 'ساعدني في القرار')}</div>

      {/* 1. WHICH QUOTE, AND WHAT IT COSTS TO CHOOSE IT */}
      {rec.map((r) => {
        const save = aed(r.saving_vs_next);
        const sooner = days(r.days_sooner, lang);
        return (
          <div key={r.inquiry_id} className="mt-2.5 border-t border-border/60 pt-2.5 first:border-0 first:pt-0">
            <Head id={r.inquiry_id} onOpen={onOpenRfq}>{r.summary || (r.category && categoryLabel(r.category, lang)) || L(lang, 'Your request', 'طلبك')}</Head>
            <div className={cn(S.sub, 'mt-1')}>
              {r.same_quote_wins
                ? L(lang,
                    `One quote is both the cheapest and the fastest, at ${aed(r.cheapest_price)}. There is no trade-off to weigh here.`,
                    `أحد العروض هو الأرخص والأسرع معًا بقيمة ${aed(r.cheapest_price)}. لا توجد مفاضلة هنا.`)
                : (save && sooner)
                  ? L(lang,
                      `The cheapest is ${aed(r.cheapest_price)} and saves you ${save}. The fastest arrives ${sooner} sooner but costs more. Which matters more on this job is your call — those are the only two things separating them.`,
                      `الأرخص ${aed(r.cheapest_price)} ويوفّر عليك ${save}. والأسرع يصل قبله بـ ${sooner} لكنه أعلى سعرًا. أيّهما أهم في هذا العمل قرارك أنت — وهذان هما الفارقان الوحيدان بينهما.`)
                  : save
                    ? L(lang,
                        `The cheapest is ${aed(r.cheapest_price)}, ${save} below the next one.`,
                        `الأرخص ${aed(r.cheapest_price)}، أي أقل بـ ${save} من العرض التالي.`)
                    : L(lang,
                        `You have ${r.quotes} quotes, the lowest at ${aed(r.cheapest_price)}.`,
                        `لديك ${r.quotes} عروض، أدناها ${aed(r.cheapest_price)}.`)}
            </div>
            {/* Said plainly rather than hidden: we cannot rank on speed what nobody stated a
                lead time for. */}
            {!r.same_quote_wins && Number(r.lead_times_stated) < Number(r.quotes) ? (
              <div className={cn(S.sub, 'mt-0.5 text-muted-foreground/70')}>
                {L(lang,
                  `${r.lead_times_stated} of ${r.quotes} quotes gave a lead time, so speed is compared only across those.`,
                  `${r.lead_times_stated} من ${r.quotes} عروض ذكرت مدة التنفيذ، لذا تُقارن السرعة بينها فقط.`)}
              </div>
            ) : null}
          </div>
        );
      })}

      {/* 2. WHAT A JOB LIKE THIS IS RUNNING AT, AND WHO CAN ACTUALLY QUOTE IT */}
      {mkt.map((m) => (
        <div key={(m.category || '') + (m.emirate || '')} className="mt-2.5 border-t border-border/60 pt-2.5">
          {/* Built as one interpolated string rather than three fragments around a <span>. The
              fragment version read "What Marble jobs are running at in Dubai" in English and left
              the Arabic half of one L() call empty, which is not a translation. */}
          <div className={cn(S.head, 'first-letter:uppercase')}>
            {L(lang,
               `What ${categoryLabel(m.category || '', 'en')} jobs cost${m.emirate ? ' in ' + m.emirate : ' in the UAE'}`,
               `كم تكلّف أعمال ${categoryLabel(m.category || '', 'ar')}${m.emirate ? ' في ' + m.emirate : ' في الإمارات'}`)}
          </div>
          <div className={cn(S.sub, 'mt-1')}>
            {m.price_known
              ? L(lang,
                  `Half of these jobs came in between ${aed(m.p25)} and ${aed(m.p75)}, with ${aed(m.median)} in the middle — from ${m.price_n} quoted jobs on QuotesDone.`,
                  `نصف هذه الأعمال جاءت بين ${aed(m.p25)} و${aed(m.p75)}، ووسطها ${aed(m.median)} — من ${m.price_n} عملًا مسعّرًا على QuotesDone.`)
              : L(lang,
                  `No QuotesDone job in this trade has been quoted yet, so we will not print a price — a range from ${m.price_n} quote${m.price_n === 1 ? '' : 's'} would be a guess with a decimal point on it. This fills in on its own once ${minN} are in.`,
                  `لم يُسعَّر أي عمل في هذه المهنة على QuotesDone بعد، لذا لن نعرض سعرًا — نطاق مبني على ${m.price_n} عرض هو تخمين بصيغة رقمية. سيظهر تلقائيًا عند اكتمال ${minN}.`)}
          </div>
          {Number(m.suppliers_covering) > 0 ? (
            <div className={cn(S.sub, 'mt-0.5')}>
              {L(lang,
                `${m.suppliers_covering} UAE suppliers on our list cover this trade${m.emirate ? ' in ' + m.emirate : ''}.`,
                `${m.suppliers_covering} مورّدًا في الإمارات ضمن قائمتنا يغطون هذه المهنة${m.emirate ? ' في ' + m.emirate : ''}.`)}
              {m.avg_days_to_quote != null
                ? L(lang, ` First quotes have taken about ${m.avg_days_to_quote} days.`,
                          ` استغرق أول عرض نحو ${m.avg_days_to_quote} يومًا.`)
                : ''}
            </div>
          ) : null}
        </div>
      ))}

      {/* 3. WHAT HAS GONE QUIET, AND THE THING THAT MOVES IT */}
      {chase.map((c) => {
        const copy = CHASE_COPY[String(c.state)];
        if (!copy) return null;
        return (
          <div key={c.inquiry_id} className="mt-2.5 border-t border-border/60 pt-2.5">
            <Head id={c.inquiry_id} onOpen={onOpenRfq}>{c.summary || (c.category && categoryLabel(c.category, lang)) || L(lang, 'Your request', 'طلبك')}</Head>
            <div className={cn(S.sub, 'mt-1')}>
              {Math.round(Number(c.age_days)) < 1
                ? L(lang, 'Posted today. ', 'نُشر اليوم. ')
                : L(lang, `Posted ${Math.round(Number(c.age_days))} days ago. `,
                         `نُشر قبل ${Math.round(Number(c.age_days))} يومًا. `)}
              {L(lang, copy[0], copy[1])}
            </div>
          </div>
        );
      })}
    </Card>
  );
}
