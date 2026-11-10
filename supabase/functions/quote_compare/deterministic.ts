// deterministic.ts — the model-free quote comparison.
//
// WHY THIS EXISTS. Until now, when every model attempt failed, quote_compare returned
// `{ok:false, error:'parse_failed'}` at HTTP 200 and the customer — standing at the decision
// step, having waited for suppliers to quote — was given NOTHING. The function's own log line
// says so: "the customer reached the decision step, was given nothing to compare, and this
// returns HTTP 200 so it is invisible to ordinary error monitoring."
//
// That is not a rare edge. OpenRouter is one shared balance for the whole company and it was
// $11.87 on 10 Aug 2026, falling ~$4.62/day. When it reaches zero EVERY model attempt fails,
// and the decision step — the one moment QuotesDone earns its reveal fee — breaks silently.
//
// The pack's own routing table says quote_comparison should be "Deterministic compliance score
// first ... Sonnet writes the final top-three explanation only", and its acceptance gate says
// "Quote comparison has a model-free fallback". This is that fallback.
//
// WHAT IT DELIBERATELY DOES NOT DO. It never invents a specification, a spec deviation, a line
// finding or a reason. Those need judgement and judgement is what the model was for. It ranks on
// facts the supplier actually stated — price, completeness, lead time, warranty, payment terms,
// itemisation, expiry — labels itself `degraded`, and says in its own text that it is a
// rules-only comparison. A customer must never be shown a thinner analysis dressed as the full
// one.

import { notesAsLists, reviewPenalty, type ReviewNote } from '../_shared/quote_review_notes.ts';

export type Labelled = {
  label: string; price: number | null; lead_time?: string | null; validity?: string | null;
  warranty?: string | null; payment_terms?: string | null; exclusions?: string | null;
  itemised?: boolean; expired?: boolean; source?: string;
  completeness?: { score: number | null; passed: boolean | null; missing_mandatory: number | null };
  /** Ruling 1207: the supplier's discount and VAT as stated. `price` is ALWAYS the price after the stated discount,
   * excluding VAT (ruling 1208) — the one basis this ranking and our fee both use. */
  gross_amount?: number | null; discount_amount?: number | null; vat_treatment?: string | null; vat_amount?: number | null;
  /** The sales engineer's notes against the request (_shared/quote_review_notes.ts, founder ledger 1588). */
  review_notes?: ReviewNote[];
};

export const RULES_DISCLAIMER_EN = "This is QuotesDone's impartial recommendation, prepared to make your decision easier. From all the quotes you received, we have shortlisted three, ranked on the price, completeness, lead time, warranty and payment terms each supplier stated, and compared those in detail. You remain completely free to reveal and choose any supplier from your full list of quotes.";
export const RULES_DISCLAIMER_AR = 'هذه توصية محايدة أعدّتها QuotesDone لتيسير قرارك: من بين جميع العروض التي تلقيتها، اخترنا ثلاثة عروض رُتّبت وفق السعر واكتمال العرض ومدة التنفيذ والضمان وشروط الدفع كما ذكرها كل مورّد، وقارنّا بينها بالتفصيل. ولك مطلق الحرية في الكشف عن أي مورّد من قائمة عروضك الكاملة واختياره.';

// The method sentence the rules ranking puts in its bottom line. Exported so the comparison report,
// which states its method in its own section, can take it out of the bottom line instead of saying
// it twice (quote_documents.ts compareDocument).
export const METHOD_NOTE_EN = 'Quotes are ranked on the figures each supplier stated: price, completeness, lead time, warranty and payment terms. Specifications are not assessed; check them before you pay.';
export const METHOD_NOTE_AR = 'رُتّبت العروض وفق الأرقام التي ذكرها كل مورّد: السعر، واكتمال العرض، ومدة التنفيذ، والضمان، وشروط الدفع. لم تُقيَّم المواصفات؛ يُرجى التحقق منها قبل الدفع.';

const clamp15 =(n: number) => Math.max(1, Math.min(5, Math.round(n)));

// Score a lower-is-better value ACROSS THE RANGE THE QUOTES ACTUALLY OCCUPY, not as a ratio to
// the best one. Found by running this against four real staging quotes: prices 862,400-1,107,400
// are all within ~22% of the cheapest, so ratio scoring gave every single quote 5/5 and the
// ranking silently collapsed onto lead time alone. Spanning the range makes the cheapest 5, the
// dearest 1 and the middle land in between, which is what "relative to the other quotes on THIS
// job" has to mean. A genuine tie scores 3 for everyone — never 5 for everyone.
function spanScore(v: number | null, min: number | null, max: number | null): number {
  if (v === null || min === null || max === null) return 1;   // unstated is a risk, not an average
  if (max === min) return 3;
  return clamp15(5 - 4 * ((v - min) / (max - min)));
}
const stated = (v: unknown) => typeof v === 'string' && v.trim() !== '';

// "2 weeks", "10-14 days", "3 working days", "1 month". Takes the FIRST number and the unit that
// follows it. Unparseable or unstated stays null, which scores 1 — an unstated lead time is a
// risk, not an average one, and that is the same rule the model prompt is given.
export function leadTimeDays(s: unknown): number | null {
  if (!stated(s)) return null;
  const t = String(s).toLowerCase();
  const m = t.match(/(\d+(?:\.\d+)?)/);
  if (!m) return null;
  const n = Number(m[1]);
  if (!Number.isFinite(n) || n <= 0) return null;
  if (/week|أسبوع/.test(t)) return n * 7;
  if (/month|شهر/.test(t)) return n * 30;
  return n;                                   // days, or a bare number read as days
}

// Completeness comes from trg_quote_quality via fn_quote_score_json (0-100). When it is absent
// the score is rebuilt from the commercial terms the supplier actually stated, so a quote is
// never rewarded for missing data.
// whyAr: the Arabic score reason printed the English `why` inside Arabic text (instruction 586 review, 22 Sep 2026).
function qualityScore(q: Labelled): { score: number; why: string; whyAr: string } {
  const c = q.completeness?.score;
  const kindAr = q.itemised ? 'عرض مفصّل بالبنود' : 'سعر مقطوع';
  if (typeof c === 'number' && Number.isFinite(c)) {
    const base = c >= 85 ? 5 : c >= 70 ? 4 : c >= 50 ? 3 : c >= 30 ? 2 : 1;
    const bump = (q.itemised && stated(q.warranty)) ? 1 : 0;
    return { score: clamp15(base + bump), why: `completeness ${c}/100${q.itemised ? ', itemised' : ', lump sum'}`, whyAr: `نسبة الاكتمال ${c}/100، ${kindAr}` };
  }
  const n = [q.warranty, q.lead_time, q.payment_terms, q.validity, q.exclusions].filter(stated).length;
  return { score: clamp15(1 + n * 0.8 + (q.itemised ? 1 : 0)), why: `${n} of 5 commercial terms stated${q.itemised ? ', itemised' : ', lump sum'}`, whyAr: `ذُكر ${n} من أصل 5 شروط تجارية، ${kindAr}` };
}

// EVERY QUOTE, NOT ONLY THE SHORTLIST (14 Sep 2026, agent: ceo). The analysis — model or rules —
// details three quotes. The customer received seven, and the report said nothing about the other
// four, which reads as "only three quotes came in". The roster lists every live quote with its
// place: shortlisted (with its rank), received (not shortlisted, open to reveal like any other),
// or held (not shortlisted, and on hold by the hold desk's own verdict).
// "Held" is a description of the quote, not a claim that anyone was told: this module sends
// nothing. It never re-ranks — the shortlist is whatever the analysis chose.
//
// ONE DEFINITION OF HELD (10 Nov 2026, sales_engineer; evidence run ea40c830, journey 2 Q2 72b94ebd). The hold desk released
// a quote (supplier_api spec_approve: released:true) and this roster still listed it "held" with no rank. Two definitions
// disagreed: the desk, the ranking and the reveal guard decide with line_specs assessQuote (reveal_guard.heldQuoteIds and
// workflow.deskAssess both call it, since #1898), while this read `completeness.passed === false` - quotes.quality.pass,
// written by trg_quote_quality from the quote as it was submitted, which nothing re-reads after the desk's fill-in. A
// released quote failed the stale check and was shown held beside its own release. Now `held` is the caller's set from
// heldQuoteIds - the same verdict the desk released on - plus a quote with no stated price, which assessQuote never
// ranks either. quotes.quality still informs the analysis as a completeness note; it no longer decides a quote's place.
// Prevented by: quote_compare/held_is_the_hold_desks_verdict.test.ts
export type RosterRow = {
  quote_id: string | null; label: string; price: number | null; lead_time: string | null;
  warranty: string | null; status: 'shortlisted' | 'received' | 'held'; rank: number | null;
  missing_mandatory: number | null; expired: boolean;
  gross_amount?: number | null; discount_amount?: number | null; vat_treatment?: string | null; vat_amount?: number | null;
};
export function rosterOf(labelled: Array<Labelled & { quote_id?: string | null }>, top3: Array<{ label: string; rank?: number }>, held: ReadonlySet<string> = new Set()): RosterRow[] {
  const rankOf = new Map<string, number>();
  (top3 || []).forEach((t, i) => { if (t && t.label) rankOf.set(t.label, Number(t.rank) || i + 1); });
  return labelled.map((q) => {
    const price = typeof q.price === 'number' && q.price > 0 ? q.price : null;
    const rank = rankOf.get(q.label) ?? null;
    const incomplete = price === null || (q.quote_id != null && held.has(String(q.quote_id)));
    return {
      quote_id: q.quote_id ?? null, label: q.label, price, lead_time: q.lead_time ?? null, warranty: q.warranty ?? null,
      status: rank !== null ? 'shortlisted' : incomplete ? 'held' : 'received', rank,
      missing_mandatory: typeof q.completeness?.missing_mandatory === 'number' ? q.completeness.missing_mandatory : null,
      expired: !!q.expired,
      gross_amount: q.gross_amount ?? null, discount_amount: q.discount_amount ?? null, vat_treatment: q.vat_treatment ?? null, vat_amount: q.vat_amount ?? null,
    };
  });
}

export function deterministicCompare(labelled: Labelled[], lang: 'en' | 'ar' = 'en') {
  const ar = lang === 'ar';
  const prices = labelled.map(q => (typeof q.price === 'number' && q.price > 0 ? q.price : null));
  const valid = prices.filter((p): p is number => p !== null);
  const minPrice = valid.length ? Math.min(...valid) : null;
  const maxPrice = valid.length ? Math.max(...valid) : null;
  const days = labelled.map(q => leadTimeDays(q.lead_time));
  const validDays = days.filter((d): d is number => d !== null);
  const minDays = validDays.length ? Math.min(...validDays) : null;
  const maxDays = validDays.length ? Math.max(...validDays) : null;

  const scored = labelled.map((q, i) => {
    const p = prices[i];
    // Both are relative to the other quotes on THIS job, not to an absolute market.
    const price_score = spanScore(p, minPrice, maxPrice);
    const d = days[i];
    const delivery_score = spanScore(d, minDays, maxDays);
    const { score: quality_score, why, whyAr } = qualityScore(q);

    const flags: string[] = [];
    // Facts only. Before the reveal the customer cannot reach a supplier (founder, 14 Sep 2026), so
    // no flag tells them to ask, confirm with or contact one.
    if (q.expired) flags.push(ar ? 'انتهت صلاحية عرض السعر' : 'This quote has expired.');
    if (!q.itemised) flags.push(ar ? 'سعر مقطوع دون تفصيل للبنود، فلا يمكن التحقق منه بندًا بندًا.' : 'Lump sum with no line items — it cannot be checked item by item.');
    if (!stated(q.warranty)) flags.push(ar ? 'الضمان غير مذكور' : 'Warranty not stated.');
    if (!stated(q.lead_time)) flags.push(ar ? 'مدة التسليم غير مذكورة' : 'Lead time not stated.');
    if (!stated(q.payment_terms)) flags.push(ar ? 'شروط الدفع غير مذكورة' : 'Payment terms not stated.');
    if (q.completeness?.passed === false) flags.push(ar ? 'لم يجتز الفحص الآلي لاكتمال العرض.' : 'Failed our automated completeness check.');
    if (typeof q.completeness?.missing_mandatory === 'number' && q.completeness.missing_mandatory > 0) {
      flags.push(ar ? `حقول إلزامية لا تزال ناقصة لهذا التخصص: ${q.completeness.missing_mandatory}` : `${q.completeness.missing_mandatory} mandatory field(s) still missing for this trade.`);
    }
    // COST-TO-VALUE (founder ledger 1590, 10 Nov 2026). These were "never guessed" and always empty: the ranking could
    // put first a quote that is cheapest BECAUSE it leaves requested scope out, quotes Chinese against an Italian
    // request, or gives half the warranty asked for. The sales engineer's notes are facts read against the request
    // (quote_review_notes.ts), so they fill the two lists and their penalties come off the composite score.
    const lists = notesAsLists(q.review_notes, lang);
    const penalty = reviewPenalty(q.review_notes);
    const firstHigh = (q.review_notes || []).find((n) => n.severity === 'high');

    return {
      label: q.label,
      price: p, lead_time: q.lead_time ?? null, validity: q.validity ?? null,
      warranty: q.warranty ?? null, payment_terms: q.payment_terms ?? null,
      getting: ar
        ? `${p === null ? 'لم يُذكر السعر' : `${p.toLocaleString('en-US')} درهم`} — ${q.itemised ? 'عرض مفصّل بالبنود' : 'سعر مقطوع'}.`
        : `${p === null ? 'No price stated' : `AED ${p.toLocaleString('en-US')}`} — ${q.itemised ? 'itemised quote' : 'lump sum'}.`,
      includes: [] as string[], excludes: stated(q.exclusions) ? [String(q.exclusions)] : [],
      // Never guessed. Judging a quote against the brief needs reading, which is the model's job.
      missing_from_request: lists.missing_from_request, spec_deviation: lists.spec_deviation,
      track_record_note: '',
      price_score, delivery_score, quality_score,
      score_reason: ar
        ? `احتُسبت النقاط من الأرقام المذكورة وحدها (${whyAr})${penalty ? `، مع خصم لمتطلبات طلبك غير المستوفاة (${lists.missing_from_request.length + lists.spec_deviation.length})` : ''}.`
        : `Scored from the stated figures only (${why})${penalty ? `, less ${penalty.toFixed(1)} for ${lists.missing_from_request.length + lists.spec_deviation.length} unmet requirement(s) of your request` : ''}.`,
      flags,
      requirement_penalty: penalty,
      _tradeoff: firstHigh ? (ar ? firstHigh.ar : firstHigh.en) : '',
      _composite: price_score * 0.4 + quality_score * 0.4 + delivery_score * 0.2 - penalty,
      _price: p,
    };
  });

  // Best composite first; a tie goes to the cheaper quote, and a quote with no price never wins
  // a tie against one that has a price.
  const ranked = [...scored].sort((a, b) =>
    b._composite - a._composite ||
    (a._price ?? Number.POSITIVE_INFINITY) - (b._price ?? Number.POSITIVE_INFINITY) ||
    a.label.localeCompare(b.label));
  const short = ranked.slice(0, 3);

  const cheapest = minPrice === null ? null : (scored.find(s => s._price === minPrice)?.label ?? null);
  const best = short.length ? short[0].label : null;
  const spread = (valid.length >= 2) ? Math.max(...valid) - Math.min(...valid) : null;

  const top3 = short.map((s, i) => ({
    rank: i + 1, label: s.label,
    why: ar
      ? `أعلى مجموع نقاط في السعر والاكتمال ومدة التسليم (${s.price_score}/${s.quality_score}/${s.delivery_score})${s.requirement_penalty ? '، بعد خصم ما لم يستوفِه من طلبك' : ''}.`
      : `Highest combined score on price, completeness and delivery (${s.price_score}/${s.quality_score}/${s.delivery_score})${s.requirement_penalty ? ', after the deduction for what it does not meet of your request' : ''}.`,
    tradeoff: s._tradeoff || (s.flags.length ? s.flags[0] : ''),
  }));

  // THE METHOD, NEVER THE MACHINERY (coordinator review of the #600 samples, 14 Sep 2026). This
  // said the "AI adviser was unavailable". A customer must never read that something of ours is
  // down; they need to know how the ranking was made and what it did not look at. Same facts.
  const note = ar ? METHOD_NOTE_AR : METHOD_NOTE_EN;

  return {
    degraded: true,
    engine: 'deterministic',
    // Declared here so the caller can stamp it. Without it the returned object literal's inferred
    // type has no such property and `analysis.disclaimer = ...` is a TS2339 — which the Supabase
    // CLI does not catch, because it bundles without typechecking, but CI does.
    // The rules ranking carries its own closing paragraph. The model's one says the shortlist
    // matches "on specification, value and terms", which is untrue here: specs are not assessed.
    disclaimer: ar ? RULES_DISCLAIMER_AR : RULES_DISCLAIMER_EN,
    trade: '',
    considered: labelled.length,
    shortlist_reason: ar
      // Founder's standing rule: never imply only the shortlist is shown. Every quote is listed.
      ? `أُدرجت العروض جميعها (${labelled.length}) في هذا التقرير، وتُقارن أفضل ${short.length} منها بالتفصيل.`
      : `All ${labelled.length} quotes are listed in this report; the top ${short.length} are compared in detail.`,
    bottom_line: best
      ? (ar ? `حصل ${best} على أعلى مجموع نقاط. ${note}` : `${best} scores highest overall. ${note}`)
      : note,
    overview: [
      minPrice === null ? (ar ? 'لم يذكر أي عرض سعرًا.' : 'No quote states a price.')
        : (ar ? `أدنى سعر معروض ${minPrice.toLocaleString('en-US')} درهم.` : `Cheapest quote is AED ${minPrice.toLocaleString('en-US')}.`),
      spread !== null ? (ar ? `الفارق بين أعلى سعر وأدناه ${spread.toLocaleString('en-US')} درهم.` : `Spread between highest and lowest is AED ${spread.toLocaleString('en-US')}.`) : '',
    ].filter(Boolean).join(' '),
    quotes: short.map(({ _composite, _price, _tradeoff, ...rest }) => rest),
    line_findings: [] as Array<{ item: string; finding: string }>,
    top3,
    cheapest_label: cheapest,
    best_value_label: best,
    best_value_reason: ar
      ? 'أعلى مجموع نقاط في السعر والاكتمال ومدة التسليم، استنادًا إلى الأرقام المذكورة.'
      : 'Highest combined score on price, completeness and delivery, from the stated figures.',
    watch_outs: [
      // From the data, not from a flag's wording: rewording the expired flag on 14 Sep 2026 silently
      // switched this watch-out off (deterministic.test.mjs caught it).
      ...(labelled.some((x) => x.expired)
        ? [ar ? 'انتهت صلاحية عرض واحد على الأقل.' : 'At least one quote has expired.'] : []),
      // The method line is said once, in the bottom line; repeating it here read as a warning.
    ],
    // What actually happens, never "confirm it with the supplier": before the reveal the customer
    // cannot reach one (founder, 14 Sep 2026). A quote missing a required detail is held and the
    // sales engineer asks the supplier for it through customer_support until it is filled.
    advice: ar
      ? 'تُقارن العروض استنادًا إلى ما ذكره كل مورّد كتابةً. وأي عرض ينقصه تفصيل إلزامي يبقى معلّقًا إلى أن نستوفيه من المورّد، ثم يُضاف إلى هذه المقارنة فور ردّه.'
      : 'Quotes are compared on what each supplier stated in writing. A quote missing a required detail is held and we request it from the supplier; it joins this comparison once they answer.',
  };
}
