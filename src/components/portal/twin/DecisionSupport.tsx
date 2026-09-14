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
import { cn } from '@/lib/utils';
import { SUPA_ANON, SUPA_FN } from '@/lib/supaEnv';

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

// No onOpenRfq. The overview renders every InquiryCard inline directly below this panel, so there
// is no open-a-request-by-id target to navigate to - `navigate` here takes a MODULE id and an
// inquiry id would have fallen through it to the home view. A heading styled as a button that
// goes nowhere is worse than a heading, so these are headings.
export function DecisionSupport({ token, lang = 'en' }:
  { token: string; lang?: string }) {
  const [rec, setRec] = useState<Rec[]>([]);
  const [mkt, setMkt] = useState<Mkt[]>([]);
  const [chase, setChase] = useState<Chase[]>([]);
  const [minN, setMinN] = useState(5);
  const [state, setState] = useState<'loading' | 'ok' | 'failed'>('loading');

  useEffect(() => {
    let on = true;
    (async () => {
      try {
        const r = await fetch(`${SUPA_FN}/customer_portal`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token || SUPA_ANON}` },
          body: JSON.stringify({ action: 'decision_support', lang }),
        });
        const j = await r.json().catch(() => null);
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
  }, [token, lang]);

  // A panel that could only ever be empty is a dead end with a heading on it. With nothing to
  // recommend, nothing quiet and no category history, this renders nothing at all and the
  // overview keeps the space.
  const empty = !rec.length && !mkt.length && !chase.length;
  if (state === 'loading' || (state === 'ok' && empty)) return null;
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
            <div className={S.head}>{r.summary || r.category || L(lang, 'Your request', 'طلبك')}</div>
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
               `What ${m.category} jobs cost${m.emirate ? ' in ' + m.emirate : ' in the UAE'}`,
               `كم تكلّف أعمال ${m.category}${m.emirate ? ' في ' + m.emirate : ' في الإمارات'}`)}
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
            <div className={S.head}>{c.summary || c.category || L(lang, 'Your request', 'طلبك')}</div>
            <div className={cn(S.sub, 'mt-1')}>
              {L(lang, `Posted ${Math.round(Number(c.age_days))} days ago. `,
                       `نُشر قبل ${Math.round(Number(c.age_days))} يومًا. `)}
              {L(lang, copy[0], copy[1])}
            </div>
          </div>
        );
      })}
    </Card>
  );
}
