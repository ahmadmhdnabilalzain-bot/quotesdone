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

export type Labelled = {
  label: string; price: number | null; lead_time?: string | null; validity?: string | null;
  warranty?: string | null; payment_terms?: string | null; exclusions?: string | null;
  itemised?: boolean; expired?: boolean; source?: string;
  completeness?: { score: number | null; passed: boolean | null; missing_mandatory: number | null };
};

const clamp15 = (n: number) => Math.max(1, Math.min(5, Math.round(n)));

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
function qualityScore(q: Labelled): { score: number; why: string } {
  const c = q.completeness?.score;
  if (typeof c === 'number' && Number.isFinite(c)) {
    const base = c >= 85 ? 5 : c >= 70 ? 4 : c >= 50 ? 3 : c >= 30 ? 2 : 1;
    const bump = (q.itemised && stated(q.warranty)) ? 1 : 0;
    return { score: clamp15(base + bump), why: `completeness ${c}/100${q.itemised ? ', itemised' : ', lump sum'}` };
  }
  const n = [q.warranty, q.lead_time, q.payment_terms, q.validity, q.exclusions].filter(stated).length;
  return { score: clamp15(1 + n * 0.8 + (q.itemised ? 1 : 0)), why: `${n} of 5 commercial terms stated${q.itemised ? ', itemised' : ', lump sum'}` };
}

// EVERY QUOTE, NOT ONLY THE SHORTLIST (14 Sep 2026, agent: ceo). The analysis — model or rules —
// details three quotes. The customer received seven, and the report said nothing about the other
// four, which reads as "only three quotes came in". The roster lists every live quote with its
// place: shortlisted (with its rank), received (not shortlisted, open to reveal like any other),
// or held (not shortlisted AND incomplete: no stated price, or our completeness check failed).
// "Held" is a description of the quote, not a claim that anyone was told: this module sends
// nothing. It never re-ranks — the shortlist is whatever the analysis chose.
export type RosterRow = {
  quote_id: string | null; label: string; price: number | null; lead_time: string | null;
  warranty: string | null; status: 'shortlisted' | 'received' | 'held'; rank: number | null;
  missing_mandatory: number | null; expired: boolean;
};
export function rosterOf(labelled: Array<Labelled & { quote_id?: string | null }>, top3: Array<{ label: string; rank?: number }>): RosterRow[] {
  const rankOf = new Map<string, number>();
  (top3 || []).forEach((t, i) => { if (t && t.label) rankOf.set(t.label, Number(t.rank) || i + 1); });
  return labelled.map((q) => {
    const price = typeof q.price === 'number' && q.price > 0 ? q.price : null;
    const rank = rankOf.get(q.label) ?? null;
    const incomplete = price === null || q.completeness?.passed === false;
    return {
      quote_id: q.quote_id ?? null, label: q.label, price, lead_time: q.lead_time ?? null, warranty: q.warranty ?? null,
      status: rank !== null ? 'shortlisted' : incomplete ? 'held' : 'received', rank,
      missing_mandatory: typeof q.completeness?.missing_mandatory === 'number' ? q.completeness.missing_mandatory : null,
      expired: !!q.expired,
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
    const { score: quality_score, why } = qualityScore(q);

    const flags: string[] = [];
    if (q.expired) flags.push(ar ? 'انتهت صلاحية عرض السعر' : 'This quote has expired — ask the supplier to reconfirm it.');
    if (!q.itemised) flags.push(ar ? 'سعر إجمالي بدون تفاصيل' : 'Lump sum with no line items — it cannot be checked item by item.');
    if (!stated(q.warranty)) flags.push(ar ? 'الضمان غير مذكور' : 'Warranty not stated — confirm before paying.');
    if (!stated(q.lead_time)) flags.push(ar ? 'مدة التسليم غير مذكورة' : 'Lead time not stated — confirm before paying.');
    if (!stated(q.payment_terms)) flags.push(ar ? 'شروط الدفع غير مذكورة' : 'Payment terms not stated — confirm before paying.');
    if (q.completeness?.passed === false) flags.push(ar ? 'لم يجتز فحص الاكتمال' : 'Failed our automated completeness check.');
    if (typeof q.completeness?.missing_mandatory === 'number' && q.completeness.missing_mandatory > 0) {
      flags.push(ar ? `${q.completeness.missing_mandatory} حقل إلزامي ناقص` : `${q.completeness.missing_mandatory} mandatory field(s) still missing for this trade.`);
    }

    return {
      label: q.label,
      price: p, lead_time: q.lead_time ?? null, validity: q.validity ?? null,
      warranty: q.warranty ?? null, payment_terms: q.payment_terms ?? null,
      getting: ar
        ? `${p === null ? 'سعر غير مذكور' : `${p.toLocaleString('en-US')} درهم`} — ${q.itemised ? 'عرض مفصل بالبنود' : 'سعر إجمالي'}.`
        : `${p === null ? 'No price stated' : `AED ${p.toLocaleString('en-US')}`} — ${q.itemised ? 'itemised quote' : 'lump sum'}.`,
      includes: [] as string[], excludes: stated(q.exclusions) ? [String(q.exclusions)] : [],
      // Never guessed. Judging a quote against the brief needs reading, which is the model's job.
      missing_from_request: [] as string[], spec_deviation: [] as string[],
      track_record_note: '',
      price_score, delivery_score, quality_score,
      score_reason: ar
        ? `الترتيب محسوب من الأرقام المذكورة فقط (${why}).`
        : `Scored from the stated figures only (${why}).`,
      flags,
      _composite: price_score * 0.4 + quality_score * 0.4 + delivery_score * 0.2,
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
      ? `أعلى مجموع نقاط على السعر والاكتمال والتسليم (${s.price_score}/${s.quality_score}/${s.delivery_score}).`
      : `Highest combined score on price, completeness and delivery (${s.price_score}/${s.quality_score}/${s.delivery_score}).`,
    tradeoff: s.flags.length ? s.flags[0] : '',
  }));

  const note = ar
    ? 'هذه مقارنة بالقواعد فقط: المساعد الذكي غير متاح الآن، لذلك رُتّبت العروض من الأرقام المذكورة فقط دون قراءة المواصفات. راجع المواصفات بنفسك قبل الدفع.'
    : 'This is a rules-only comparison. The AI adviser was unavailable, so these quotes are ranked on the figures the suppliers stated — price, completeness, lead time, warranty and payment terms — and NOT on a reading of the specifications. Check the specs yourself before paying.';

  return {
    degraded: true,
    engine: 'deterministic',
    // Declared here so the caller can stamp it. Without it the returned object literal's inferred
    // type has no such property and `analysis.disclaimer = ...` is a TS2339 — which the Supabase
    // CLI does not catch, because it bundles without typechecking, but CI does.
    disclaimer: '',
    trade: '',
    considered: labelled.length,
    shortlist_reason: ar
      ? `رُتّبت ${labelled.length} عروض بالنقاط وعُرضت أفضل ${short.length}.`
      : `All ${labelled.length} quotes were scored on stated figures and the strongest ${short.length} are shown.`,
    bottom_line: best
      ? (ar ? `${best} هو الأعلى نقاطاً. ${note}` : `${best} scores highest overall. ${note}`)
      : note,
    overview: [
      minPrice === null ? (ar ? 'لا يوجد سعر مذكور.' : 'No quote states a price.')
        : (ar ? `أرخص عرض ${minPrice.toLocaleString('en-US')} درهم.` : `Cheapest quote is AED ${minPrice.toLocaleString('en-US')}.`),
      spread !== null ? (ar ? `الفارق بين الأعلى والأدنى ${spread.toLocaleString('en-US')} درهم.` : `Spread between highest and lowest is AED ${spread.toLocaleString('en-US')}.`) : '',
    ].filter(Boolean).join(' '),
    quotes: short.map(({ _composite, _price, ...rest }) => rest),
    line_findings: [] as Array<{ item: string; finding: string }>,
    top3,
    cheapest_label: cheapest,
    best_value_label: best,
    best_value_reason: ar
      ? 'أعلى مجموع نقاط على السعر والاكتمال والتسليم من الأرقام المذكورة.'
      : 'Highest combined score on price, completeness and delivery, from the stated figures.',
    watch_outs: [
      ...(scored.some(s => s.flags.some(f => /expired|انتهت/.test(f)))
        ? [ar ? 'أحد العروض منتهي الصلاحية.' : 'At least one quote has expired — reconfirm before you rely on it.'] : []),
      ...(scored.some(s => !s.flags.length) ? [] : []),
      note,
    ],
    advice: ar
      ? 'راجع المواصفات والبنود الناقصة مع المورد قبل الدفع.'
      : 'Confirm the specification and any missing terms with the supplier before paying.',
  };
}
