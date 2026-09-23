// interview — the intake interview's state machine (14 Sep 2026; answers REASONED since 23 Sep 2026).
// No model, no network, no env IN THIS FILE: what the customer's words mean arrives as an argument.
//
// WHY THIS EXISTS. inquiry_intake's fallback derived its "missing" list from category_specs required fields
// and NEVER READ THE ANSWERS: the customer answered, the next turn asked the same questions again, and
// create_inquiry was unreachable for every category with a required field — 47 of 56 categories, 252 of
// 396 fields (measured on production category_specs, 14 Sep 2026). Posting a job has to work.
//
// WHAT IT DOES. One question at a time, in the category's own order, state kept in brief.details under
// the canonical keys (category_specs.fields[].key — the keys fn_rfq_required_check scores). A field is
// filled from exactly two sources, and nothing else:
//   1. the option the customer TAPPED for the question just asked (a structured choice the portal sends
//      as body.choice {key, option}; accepted only when it is one of that field's own options);
//   2. what think() reasoned the customer has already stated, with their own words as evidence
//      (_shared/reasoned_intake.ts interviewAnswers — decision point interview.answers).
// WHY NOT WORDS (founder_instruction 886-903, no word matching anywhere). The yes/no, "not sure", option,
// emirate and date readers that stood here decided meaning by spotting words: "Not sure" once read as Yes
// ("sure"), and an Arabic answer could only name an option through a 40-term glossary. They are gone.
// UNDER THE HOLD (stated === null). A typed reply to a question with no options is kept VERBATIM as the
// answer to the question just asked — the customer's own words, nothing inferred (a supplier quotes against
// them); a typed reply to a question WITH options is not guessed into one: the question stays open with
// its options to tap. Numbers and money stay format-parsed (parseMeasures / parseBudget) for the brief.

export type SpecField = {
  key?: string; question?: string; required?: boolean; type?: string; options?: string[];
  question_plain_en?: string; question_plain_ar?: string;
};
export type Lang = 'en' | 'ar';
export type NextQuestion = { key: string; text: string; options: string[] | null };

// 38 of the 396 fields (every field of 9 categories: epoxy-flooring, interior-design, it-networking,
// kitchens, marble-granite, roofing, smart-home, solar, swimming-pools) carry NO key. The canonical
// ready gate in index.ts skips keyless fields (it filters on f.key), so a derived key is only this
// interview's own handle — it lands in brief.details and never collides with a canonical one.
export const fieldKey = (f: SpecField, i: number) => (f.key && String(f.key)) || `field_${i + 1}`;

const AR_DIGITS = '٠١٢٣٤٥٦٧٨٩';
export function normDigits(s: string): string {
  return String(s || '').replace(/[٠-٩]/g, (d) => String(AR_DIGITS.indexOf(d))).replace(/[٫]/g, '.').replace(/[٬،](?=\d{3}\b)/g, ',');
}

// ── NUMBERS WITH UNITS ──────────────────────────────────────────────────────────────────────────
// Order matters: square units before linear metres, or "120 m2" would read as 120 m.
const UNITS: [string, RegExp][] = [
  ['sqm', /^(?:sqm|sq\.?\s*m(?:tr|eters?|etres?)?|m2|m²|square\s*met(?:er|re)s?|متر\s*مربع|م2|م²|مترمربع)/i],
  ['sqft', /^(?:sq\.?\s*ft|sqft|square\s*f(?:ee|oo)t|ft2|ft²|قدم\s*مربع)/i],
  ['lm', /^(?:lm|l\.m\.?|rm|linear\s*met(?:er|re)s?|running\s*met(?:er|re)s?|متر\s*طولي)/i],
  ['m3', /^(?:m3|m³|cu\.?\s*m|cubic\s*met(?:er|re)s?|متر\s*مكعب)/i],
  ['mm', /^(?:mm|millimet(?:er|re)s?|مم|ملم)/i],
  ['m', /^(?:m|met(?:er|re)s?|mtrs?|متر|أمتار|م)(?![a-z])/i],
  ['kva', /^kva/i], ['kw', /^kw(?!h)/i], ['tr', /^(?:tr|tons?\s*of\s*refrigeration)\b/i],
  ['kg', /^(?:kg|kgs|kilos?|كغ|كيلو)/i], ['ton', /^(?:tons?|tonnes?|طن)/i],
  ['litre', /^(?:l|ltrs?|lit(?:er|re)s?|لتر)(?![a-z])/i], ['gallon', /^(?:gal|gallons?|جالون|غالون)/i],
  ['pcs', /^(?:pcs|pieces?|units?|nos\.?|no\.|numbers?|items?|sets?|قطع|قطعة|وحدات|وحدة|حبة|حبات)/i],
  ['rooms', /^(?:rooms?|bedrooms?|br\b|bhk|غرف|غرفة)/i],
  ['floors', /^(?:floors?|storeys?|stories|levels?|طوابق|طابق|أدوار|دور)/i],
  ['windows', /^(?:windows?|نوافذ|نافذة|شبابيك|شباك)/i],
  ['doors', /^(?:doors?|أبواب|باب)/i],
  ['cameras', /^(?:cameras?|كاميرات|كاميرا)/i],
];
export type Measure = { value: number; unit: string | null; text: string };
export function parseMeasures(text: string): Measure[] {
  const t = normDigits(text);
  const out: Measure[] = [];
  const re = /(\d+(?:[.,]\d+)*)\s*(k\b|thousand|ألف|الف)?\s*/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(t)) !== null) {
    const rawNum = m[1].replace(/,(?=\d{3}(?:\D|$))/g, '').replace(',', '.');
    let value = Number(rawNum);
    if (!Number.isFinite(value)) continue;
    if (m[2]) value *= 1000;
    const rest = t.slice(m.index + m[0].length);
    let unit: string | null = null;
    for (const [u, ure] of UNITS) if (ure.test(rest)) { unit = u; break; }
    // "1200 x 1500" is a dimension pair: keep it whole rather than two bare numbers.
    const dim = t.slice(m.index).match(/^(\d+(?:\.\d+)?)\s*[x×\*]\s*(\d+(?:\.\d+)?)(?:\s*[x×\*]\s*(\d+(?:\.\d+)?))?\s*(mm|cm|m)?/i);
    if (dim && dim[2]) {
      out.push({ value, unit: dim[4] ? dim[4].toLowerCase() : null, text: dim[0].trim() });
      re.lastIndex = m.index + dim[0].length;
      continue;
    }
    out.push({ value, unit, text: unit ? `${value} ${unit}` : String(value) });
  }
  return out;
}

// ── MONEY ───────────────────────────────────────────────────────────────────────────────────────
export function parseBudget(text: string): string | null {
  const t = normDigits(text);
  if (!/aed|dhs?\b|dirhams?|درهم|دراهم|د\.إ|budget|ميزانية|\d\s*(?:k|m)\b/i.test(t)) return null;
  // A NUMBER IS A BUDGET ONLY WHEN IT CARRIES A MONEY MARKER ITSELF. Measured 22 Sep 2026 on production
  // (scripts/e2e/drawing_reaches_suppliers.mjs): "...26x18 supply duct... Budget is open." became budget
  // "AED 26" - the word "budget" let the text in and the first number anywhere was taken - and 26 fell
  // below every HVAC supplier's minimum job, so the request matched nobody. Review of #821: the first fix
  // still read "Budget: not sure, maybe use 26x18 duct" as AED 26. So each number is judged on its own:
  //  * never when it is part of a dimension: NxN / N×N, or N followed by mm, cm, m, in, inch, ", ', ft;
  //  * yes when it carries a multiplier (k, thousand, ألف, M, million, مليون), a currency right after it
  //    (AED, Dhs, dirhams, درهم, د.إ), a currency or "budget" right before it (a few characters, no other
  //    words), or a thousands separator (250,000).
  const re = /\d+(?:[.,]\d+)*/g;
  for (let m: RegExpExecArray | null; (m = re.exec(t)); ) {
    const raw = m[0], before = t.slice(Math.max(0, m.index - 24), m.index), after = t.slice(m.index + raw.length, m.index + raw.length + 16);
    if (/[x×*]\s*$/i.test(before) || /^\s*[x×*]\s*\d/i.test(after)) continue;                         // 26x18
    const mult = after.match(/^\s*(k\b|thousand|ألف|الف|M\b|mn\b|million|مليون)/);
    if (!mult && /^\s*(?:mm|cm|m|in|inch(?:es)?|ft|feet|metres?|meters?|["'″′])(?![a-z])/i.test(after)) continue;   // 12 m, 8"
    const curAfter = /^\s*(?:aed|dhs?|dirhams?|درهم|دراهم|د\.إ)(?![a-z])/i.test(after);
    const curBefore = /(?:aed|dhs?|dirhams?|درهم|دراهم|د\.إ|budget|ميزانية)[\s:~]*(?:(?:is|of|around|about|approx(?:imately|\.)?|roughly|حوالي|تقريبا|تقريبًا)[\s:~]*)?$/i.test(before);
    const grouped = /^\d{1,3}(?:,\d{3})+(?:\.\d+)?$/.test(raw);
    if (!mult && !curAfter && !curBefore && !grouped) continue;
    let v = Number(raw.replace(/,/g, ''));
    if (!Number.isFinite(v) || v <= 0) continue;
    if (mult) v *= /M\b|mn|million|مليون/.test(mult[1]) ? 1_000_000 : 1000;
    return `AED ${Math.round(v)}`;
  }
  return null;
}

/** Required first, then fn_category_questions' ask_order where the key matches, then spec order. */
export function orderFields(fields: SpecField[], askOrder: Record<string, number> = {}) {
  return fields
    .map((f, i) => ({ f, i, key: fieldKey(f, i) }))
    .filter(({ f }) => f && (f.question || f.key))
    .sort((a, b) => (Number(!!b.f.required) - Number(!!a.f.required))
      || ((askOrder[a.key] ?? 999) - (askOrder[b.key] ?? 999))
      || (a.i - b.i));
}

export function questionText(f: SpecField, lang: Lang): string {
  if (lang === 'ar') return String(f.question_plain_ar || f.question_plain_en || f.question || f.key || '').trim();
  return String(f.question_plain_en || f.question || f.key || '').trim();
}

export type InterviewState = { details: Record<string, string>; asked_key: string | null };
export type InterviewStep = {
  details: Record<string, string>;
  filled_now: string[];
  next: NextQuestion | null;
  readiness: { filled: number; required: number };
  complete: boolean;
};

export type Choice = { key: string; option: string } | null;
export type Stated = Record<string, { value: string; evidence: string }>;
/**
 * One turn. `choice` is the option the customer tapped; `stated` is the reasoned reading of the whole
 * conversation (null = held); `answer` is this turn's typed message, used only under the hold, verbatim.
 */
export function interviewStep(fields: SpecField[], state: InterviewState, input: { choice?: Choice; stated: Stated | null; answer?: string }, lang: Lang, askOrder: Record<string, number> = {}): InterviewStep & { held: boolean } {
  const details: Record<string, string> = { ...(state.details || {}) };
  const ordered = orderFields(fields, askOrder);
  const filledNow: string[] = [];
  const has = (k: string) => details[k] !== undefined && String(details[k]).trim() !== '';
  const asked = state.asked_key ? ordered.find((o) => o.key === state.asked_key) : undefined;
  const opts = (f: SpecField) => (Array.isArray(f.options) ? f.options.filter((o) => typeof o === 'string' && o) : []);
  // 1. A tapped option, for the question it was offered with: exact, or nothing.
  const c = input.choice;
  if (c && asked && c.key === asked.key && !has(asked.key) && opts(asked.f).includes(c.option)) { details[asked.key] = c.option; filledNow.push(asked.key); }
  // 2. What the customer has stated, reasoned, in their own words.
  if (input.stated) {
    for (const o of ordered) {
      const v = input.stated[o.key];
      if (!has(o.key) && v && String(v.value).trim()) { details[o.key] = String(v.value).trim().slice(0, 300); filledNow.push(o.key); }
    }
  } else if (asked && !has(asked.key) && !opts(asked.f).length && String(input.answer || '').trim()) {
    // Held: the reply to an open question, kept in the customer's own words.
    details[asked.key] = String(input.answer).trim().slice(0, 300); filledNow.push(asked.key);
  }
  const req = ordered.filter((o) => o.f.required);
  const filled = req.filter((o) => has(o.key)).length;
  const nextField = req.find((o) => !has(o.key));
  const next = nextField
    ? { key: nextField.key, text: questionText(nextField.f, lang), options: opts(nextField.f).length ? opts(nextField.f) : null }
    : null;
  return { details, filled_now: filledNow, next, readiness: { filled, required: req.length }, complete: !nextField, held: input.stated === null };
}

/** The brief, in the shape the model path returns (inquiry_intake sys prompt, "brief"). */
export function buildBrief(category: string, details: Record<string, string>, allText: string, emirate: string | null, firstUserText: string) {
  const pick = (re: RegExp) => { const k = Object.keys(details).find((x) => re.test(x)); return k ? String(details[k]) : ''; };
  const location = pick(/location|emirate/);
  // The emirate is REASONED by the caller (classify.urgency_emirate); the location stays in their words.
  const em = emirate || '';
  // Quantity is a measure ("450 sqm", "40 windows, 1200 x 1500 mm") or empty; the customer's prose
  // stays in details under its own key and in the summary. Measured 21 Sep 2026 (customer audit,
  // finding 8): a whole reply about brands and warranty was printed as "Quantity: It is a 4-bedroom
  // villa...". The summary is the customer's description in full: the 160-character cut of the old
  // shape truncated the audit request at "3 x 12-way D" and lost the cable, boards and sockets.
  const qtyText = pick(/area|qty|quantity|size|dimensions|count|stops|capacity|windows|rooms|coverage|scale|building/);
  const qtyMeasures = parseMeasures(qtyText);
  const quantity = /^\d/.test(qtyText.trim()) && qtyText.length <= 80 ? qtyText : (qtyMeasures.find((m) => m.unit)?.text || '');
  return {
    summary: String(firstUserText || allText).replace(/\s+/g, ' ').trim().slice(0, 4000),
    category,
    scope: pick(/^scope|supply_install|scope_mode|installation|engagement|work_type|service/),
    quantity,
    location: location || em,
    emirate: em,
    timeline: pick(/timeline|timing|date|deadline|duration/),
    budget: pick(/budget/) || parseBudget(allText) || '',
    details,
  };
}
