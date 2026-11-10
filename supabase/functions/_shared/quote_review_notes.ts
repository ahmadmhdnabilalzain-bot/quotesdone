// quote_review_notes.ts — THE SALES ENGINEER'S EXPERT NOTES ON EACH QUOTATION, FOR THE CUSTOMER, IN EN AND AR.
// Seat: sales_engineer. 10 Nov 2026, founder ledger 1588 and 1590.
//
// THE FOUNDER (1588): when quotations arrive, the sales engineer reviews them as an expert. It flags where a supplier
// ignored part of the requested scope or deviated from a requirement (the customer asked for Italian origin and the
// supplier quoted Chinese), and these appear as NOTES on the quotations shared with the customer. Customers are
// assumed technically weak; we guide them. (1590): from many quotations the sales engineer recommends the best three
// on cost-to-value — quote_compare ranks with these notes' penalties (deterministic.ts) and hands them to the model.
//
// WHAT EXISTED. The supplier-facing review (supplier_api/quote_review.ts) tells the SUPPLIER what is missing before
// they submit, and the hold gate (line_specs/assess.ts) holds a quote that leaves a mandatory detail out. Neither says
// anything to the CUSTOMER about a quote that is complete but is not what they asked for: a quote with every field
// filled that prices Chinese porcelain against an Italian request, 100 m2 against 120 m2, a 6-month warranty against
// 24, or excludes the installation they asked for, reached the customer with no word. deterministic.ts said so
// itself: "missing_from_request: [], spec_deviation: [] — never guessed".
//
// WHAT THIS IS. One pure function, reviewNotes(), comparing a quotation with the inquiry's requirements and writing
// one note per finding, in plain English and Arabic, naming no brand, model or supplier (the quoted brand is given
// as quote_generalise's "premium German brand"). It compares STRUCTURED values where they exist — the BOQ line's
// quantity and unit, the intake's required date and minimum warranty months, the line's country_of_origin and brand
// columns, the keyed terms_spec — and reads a stated value's SHAPE only where it must (a lead time "21 days", a
// period "2 years", a grade code "SS316", an origin word "Italian"). Scope lines are matched by the matcher the
// supplier-facing review already owns (supplier_api/quote_review/match.ts matchBoq), never a second copy.
//
//   scope_missing      a requested BOQ line no quotation line answers
//   scope_excluded     a stated exclusion / "supply only" that cuts something the customer asked for
//   origin_deviation   the quoted origin (or the quoted brand's origin) is not the origin asked for
//   origin_not_stated  an origin was asked for and the quote states none
//   brand_match        the customer named a brand "or equivalent" and the quote offers that brand (yes)
//   brand_alternative  ... and the quote offers another one: "alternative offered: premium German brand"
//   brand_tier_lower   ... and that alternative sits in a lower tier than the brand asked for
//   grade_lower        a lower grade / spec than asked (SS304 for SS316, C30 for C40, ceramic for porcelain, 10 mm for 12 mm)
//   quantity_mismatch  the priced quantity is short of (or differs from) the requested quantity
//   lead_time_late     the stated lead time / date lands after the customer's required date
//   warranty_short     the stated warranty is shorter than the minimum the customer asked for
//
// Each note carries a `penalty` (0..1 on the ranking's 1-5 scale): quote_compare's deterministic ranking subtracts
// them, so a cheap quote that is cheap because it leaves scope out or downgrades the spec does not win on price.
// prevented by: _shared/quote_review_notes.test.ts and the 24-trade corpus (scripts/e2e/quote_review_corpus.mjs).
import { matchBoq, normUnit } from '../supplier_api/quote_review/match.ts';
import { customerAnswer, deliveryOf, requirementsOf, warrantyPeriod, type Requirements } from './line_specs/assess.ts';
import { brandFact, genericBrand, originAdj, originLabel, originMeets, originOf, productWords, statedOriginOf, TIER_RANK, tierOf, type Tier, generaliseText } from './quote_generalise.ts';

export type NoteCode = 'scope_missing' | 'scope_excluded' | 'origin_deviation' | 'origin_not_stated' | 'brand_match' | 'brand_alternative'
  | 'brand_tier_lower' | 'grade_lower' | 'quantity_mismatch' | 'lead_time_late' | 'warranty_short';
export const NOTE_CODES: readonly NoteCode[] = ['scope_missing', 'scope_excluded', 'origin_deviation', 'origin_not_stated', 'brand_match', 'brand_alternative',
  'brand_tier_lower', 'grade_lower', 'quantity_mismatch', 'lead_time_late', 'warranty_short'];
export type ReviewNote = {
  code: NoteCode; severity: 'high' | 'medium' | 'info';
  /** The customer's request line this note is about (1-based), or null for the whole quote. */
  line_no: number | null;
  en: string; ar: string;
  /** Subtracted from the ranking's composite (1-5 scale). 0 for an informational note. */
  penalty: number;
};
/** The deviations the founder named: every code but the two informational brand notes. */
export const DEVIATION_CODES: ReadonlySet<NoteCode> = new Set(['scope_missing', 'scope_excluded', 'origin_deviation', 'origin_not_stated', 'brand_tier_lower', 'grade_lower', 'quantity_mismatch', 'lead_time_late', 'warranty_short']);

export type RequestLine = { line_no?: number | null; description?: string | null; qty?: number | string | null; unit?: string | null; section?: string | null };
export type QuoteLineIn = {
  line_no?: number | null; description?: string | null; brand?: string | null; model?: string | null; specification?: string | null;
  qty?: number | string | null; unit?: string | null; unit_price?: number | null; amount?: number | null; notes?: string | null;
  country_of_origin?: string | null; spec?: Record<string, unknown> | null;
};
export type QuoteIn = {
  lead_time?: string | null; warranty?: string | null; scope?: string | null; exclusions?: string | null; conditions?: string | null; notes?: string | null;
  // deno-lint-ignore no-explicit-any
  terms_spec?: any;
};
export type ReviewInput = {
  /** The customer's request: BOQ lines, the intake answers (inquiries.spec), and the brief's own words. */
  request: { lines: RequestLine[]; spec?: unknown; requirements?: Requirements; summary?: string | null; raw_input?: string | null; now?: Date };
  quote: QuoteIn; lines: QuoteLineIn[];
  /** The supplier's own name(s), so a quoted line's words can be quoted back only after generalising. */
  supplierNames?: string[];
};

const S = (v: unknown) => String(v ?? '').trim();
const num = (v: unknown): number | null => { const n = typeof v === 'number' ? v : Number(S(v).replace(/,/g, '').match(/^-?\d+(?:\.\d+)?/)?.[0]); return Number.isFinite(n) ? n : null; };
const clip = (s: string, n = 70) => (s.length > n ? s.slice(0, n - 1).trimEnd() + '…' : s);
const lineText = (l: QuoteLineIn) => [l.description, l.brand, l.specification, l.notes, l.country_of_origin, ...Object.values(l.spec || {}).map(S)].filter(Boolean).join(' · ');
const fmtDate = (d: Date) => d.toISOString().slice(0, 10);

// ---------------------------------------------------------------------------------------------
// Grades: values a customer can be sold short on, each read from a CODE or a named material.
// ---------------------------------------------------------------------------------------------
type Grade = { family: string; rank: number; shown: string };
const MATERIAL_LADDERS: { family: string; ar: string; rungs: [RegExp, number, string][] }[] = [
  { family: 'tile body', ar: 'نوع البلاط', rungs: [[/\bporcelain\b|بورسلين/i, 2, 'porcelain'], [/\bceramic\b|سيراميك/i, 1, 'ceramic']] },
  { family: 'board / wood', ar: 'نوع الخشب', rungs: [[/\bsolid\s+(?:wood|oak|teak|walnut|beech|ash|hardwood)\b|خشب\s*طبيعي|خشب\s*صلب/i, 3, 'solid wood'], [/\b(?:plywood|marine\s+ply|veneer(?:ed)?)\b/i, 2, 'plywood / veneer'], [/\b(?:mdf|hdf|particle\s*board|chipboard)\b/i, 1, 'MDF / particle board']] },
  { family: 'conductor', ar: 'مادة الموصل', rungs: [[/\b[Cc]opper\b|\bCOPPER\b|\bCu\b|نحاس/, 2, 'copper'], [/\b[Aa]lumin(?:i)?um\b|\bALUMIN(?:I)?UM\b|ألمنيوم|ألومنيوم/, 1, 'aluminium']] },
  { family: 'glass', ar: 'نوع الزجاج', rungs: [[/\b(?:laminated|tempered|toughened)\b|مقسى|مزدوج\s*التصفيح/i, 2, 'tempered / laminated'], [/\b(?:annealed|float)\s+glass\b|\bclear\s+float\b/i, 1, 'annealed / float']] },
  { family: 'fitting body', ar: 'مادة القطعة', rungs: [[/\b(?:solid\s+)?brass\b|نحاس\s*أصفر/i, 2, 'brass'], [/\b(?:zinc|zamak|plastic|abs)\s*(?:body|alloy)?\b/i, 1, 'zinc / plastic']] },
];
const CODE_GRADES: { family: string; ar: string; re: RegExp; rank: (m: RegExpMatchArray) => number; shown: (m: RegExpMatchArray) => string }[] = [
  { family: 'stainless steel grade', ar: 'درجة الفولاذ المقاوم للصدأ', re: /\b(?:SS|AISI|SUS|stainless(?:\s+steel)?(?:\s+grade)?)\s*-?\s*(201|304L?|316L?|430)\b|\b(201|304L?|316L?|430)\s*(?:grade\s*)?stainless/i,
    rank: (m) => ({ '430': 1, '201': 1, '304': 2, '304L': 2, '316': 3, '316L': 3 } as Record<string, number>)[(m[1] || m[2]).toUpperCase()] ?? 0, shown: (m) => 'SS' + (m[1] || m[2]).toUpperCase() },
  { family: 'concrete grade', ar: 'رتبة الخرسانة', re: /\bC\s?(\d{2})(?:\/\d{2})?\b/, rank: (m) => Number(m[1]), shown: (m) => 'C' + m[1] },
  { family: 'structural steel grade', ar: 'رتبة الحديد الإنشائي', re: /\bS\s?(235|275|355|420|460)\b/, rank: (m) => Number(m[1]), shown: (m) => 'S' + m[1] },
  { family: 'ingress protection', ar: 'درجة الحماية', re: /\bIP\s?(\d)(\d)\b/i, rank: (m) => Number(m[1]) * 10 + Number(m[2]), shown: (m) => 'IP' + m[1] + m[2] },
  { family: 'camera resolution', ar: 'دقة الكاميرا', re: /\b(\d{1,2}(?:\.\d)?)\s?MP\b/i, rank: (m) => Number(m[1]), shown: (m) => m[1] + 'MP' },
  { family: 'fire rating', ar: 'تصنيف مقاومة الحريق', re: /\b(?:E?I|F|REI)\s?(30|60|90|120|180|240)\b|\b(30|60|90|120|180|240)\s?(?:min(?:ute)?s?)\s+fire|\bfire[- ]rated\s+(\d)\s?(?:hr|hour)s?\b/i,
    rank: (m) => (m[3] ? Number(m[3]) * 60 : Number(m[1] || m[2])), shown: (m) => (m[3] ? m[3] + ' h fire rated' : (m[1] || m[2]) + ' min fire rated') },
  { family: 'thickness', ar: 'السماكة', re: /(?<![\d.])(\d{1,3}(?:\.\d)?)\s?mm\b/i, rank: (m) => Number(m[1]), shown: (m) => m[1] + ' mm' },
];
// "600x600 mm" and "120 x 60 cm" are sizes, never a thickness: taken out before a single millimetre value is read.
const DIMENSIONS = /\d+(?:\.\d+)?\s*[x×*]\s*\d+(?:\.\d+)?(?:\s*[x×*]\s*\d+(?:\.\d+)?)?\s*(?:mm|cm|m)?\b/gi;
function gradesOf(raw: string): Map<string, Grade> {
  const out = new Map<string, Grade>();
  const text = raw.replace(DIMENSIONS, ' ');
  for (const f of MATERIAL_LADDERS) for (const [re, rank, shown] of f.rungs) if (re.test(text)) { const cur = out.get(f.family); if (!cur || rank > cur.rank) out.set(f.family, { family: f.family, rank, shown }); }
  for (const g of CODE_GRADES) {
    const ms = [...text.matchAll(new RegExp(g.re.source, g.re.flags.includes('g') ? g.re.flags : g.re.flags + 'g'))];
    // A thickness is compared only when the text states exactly one millimetre value that is not a dimension.
    if (g.family === 'thickness' && new Set(ms.map((m) => m[1])).size !== 1) continue;
    if (!ms.length) continue;
    const best = ms.map((m) => ({ rank: g.rank(m), shown: g.shown(m) })).sort((a, b) => b.rank - a.rank)[0];
    if (best.rank > 0) out.set(g.family, { family: g.family, rank: best.rank, shown: best.shown });
  }
  return out;
}
const familyAr = (family: string) => (MATERIAL_LADDERS.find((f) => f.family === family)?.ar ?? CODE_GRADES.find((g) => g.family === family)?.ar ?? family);

// ---------------------------------------------------------------------------------------------
// A requested brand: a known make named in the request, and whether "or equivalent" was allowed.
// ---------------------------------------------------------------------------------------------
const OR_EQUAL = /\bor\s+(?:approved\s+)?(?:equivalent|equal|similar)\b|\bequivalent\b|\bor\s+eq\.?|أو\s*(?:ما\s*)?(?:يعادله|مماثل|ما\s*يماثله)/i;
function requestedBrand(text: string): { name: string; origin: string | null; tier: Tier | null; equivalent: boolean } | null {
  // Words of the request, longest names first, one make per line (a BOQ line asks for one make).
  const words = text.split(/[^A-Za-z0-9&+.'À-ÿ-]+/).filter(Boolean);
  for (let n = 3; n >= 1; n--) for (let i = 0; i + n <= words.length; i++) {
    const cand = words.slice(i, i + n).join(' ');
    if (!/^[A-Z0-9]/.test(cand)) continue;
    const f = brandFact(cand);
    if (f && f.name.toLowerCase() === cand.toLowerCase() && !f.plain) return { name: f.name, origin: f.origin, tier: f.tier, equivalent: OR_EQUAL.test(text) };
  }
  return null;
}
function quotedBrand(l: QuoteLineIn): { name: string; origin: string | null; tier: Tier | null } | null {
  const raw = S(l.brand) || S((l.spec || {} as Record<string, unknown>).brand);
  if (raw) { const f = brandFact(raw); return { name: f?.name ?? raw, origin: f?.origin ?? null, tier: f?.tier ?? tierOf(lineText(l)) }; }
  const r = requestedBrand(lineText(l)); return r ? { name: r.name, origin: r.origin, tier: r.tier } : null;
}

// ---------------------------------------------------------------------------------------------
// Exclusions: a stated exclusion that names something the customer asked for.
// ---------------------------------------------------------------------------------------------
const STOP = new Set(['and', 'the', 'for', 'with', 'all', 'any', 'per', 'including', 'incl', 'supply', 'item', 'items', 'work', 'works', 'provide', 'nos', 'each', 'type', 'not', 'included', 'excluded', 'exclusions', 'excludes', 'excluding', 'by', 'others', 'client', 'scope', 'our', 'from', 'are', 'is', 'of', 'to', 'in', 'on', 'be', 'will', 'shall']);
const words = (s: string) => S(s).toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((w) => w.length >= 3 && !STOP.has(w) && !/^\d+$/.test(w)).map((w) => w.replace(/ies$/, 'y').replace(/s$/, ''));
// Words too general to say an exclusion names a requested item on their own.
const GENERIC_SCOPE = new Set(['material', 'delivery', 'transport', 'labour', 'charge', 'permit', 'approval', 'authority', 'civil', 'additional', 'variation', 'drawing', 'removal', 'disposal', 'testing', 'commissioning', 'electrical', 'mechanical', 'plumbing', 'painting', 'finishing', 'cleaning', 'protection', 'installation', 'insurance', 'storage', 'handling', 'packing', 'mobilisation', 'mobilization']);
const INSTALL_WORD = /\binstall(?:ation|ing)?\b|\bfixing\b|\berection\b|تركيب/i;
const SUPPLY_ONLY = /\bsupply\s+only\b|توريد\s+فقط/i;
const EXCLUDE_INSTALL = /install(?:ation)?\s*(?:is\s*)?(?:not\s+included|excluded|by\s+others|extra)|exclud\w*\s+(?:the\s+)?install|without\s+install|بدون\s+تركيب|التركيب\s+غير\s+مشمول/i;

/** The review: one note per finding, ordered by severity. Pure — no I/O, no clock beyond `request.now`, no model. */
export function reviewNotes(input: ReviewInput): ReviewNote[] {
  const notes: ReviewNote[] = [];
  const req = input.request.requirements ?? requirementsOf(input.request.spec);
  const now = input.request.now ?? new Date();
  const q = input.quote || {};
  const qLines = (input.lines || []).filter((l) => S(l.description) || S(l.brand));
  const reqLines = (input.request.lines || []).filter((r) => S(r.description));
  const add = (n: ReviewNote) => { if (!notes.some((x) => x.code === n.code && x.line_no === n.line_no && x.en === n.en)) notes.push(n); };
  const brief = [input.request.summary, input.request.raw_input].map(S).join(' ');
  const materials = (req?.materials || []).filter(Boolean);
  const materialText = materials.map((m) => [m.choice_en, m.note, m.choice && m.choice !== 'other' && m.choice !== 'no_preference' ? m.choice : ''].map(S).join(' ')).join(' ');
  // The customer's own request line, quoted back with any make it names generalised: a note never names a brand.
  const reqWords = (t: string) => clip(generaliseText(t).text);
  const quoteWords = (l: QuoteLineIn) => clip(generaliseText(S(l.description), { supplierNames: input.supplierNames, brands: [l.brand], models: [l.model] }).text);

  // 1. SCOPE AND QUANTITY: each requested BOQ line against the quotation lines (the supplier review's own matcher).
  // Matched on PRODUCT words (productWords): "Solar PV panels 550 W, European origin" and "<brand> <line> 550 W panels"
  // share too few words while the origin phrase and the make are counted (measured on the corpus, 10 Nov 2026).
  const wl = qLines.map((l) => ({ description: productWords(S(l.description)), qty: S(l.qty), unit: S(l.unit), unit_price: num(l.unit_price), amount: num(l.amount) }));
  const pairs = matchBoq(reqLines.map((r) => ({ description: productWords(r.description), qty: r.qty, unit: r.unit })), wl);
  const exclText = [q.exclusions, q.conditions].map(S).join(' ');
  reqLines.forEach((r, i) => {
    const no = Number(r.line_no ?? i + 1); const desc = reqWords(S(r.description));
    const j = pairs.get(i);
    // An exclusion naming this line's words cuts it, priced or not.
    const rw = words(S(r.description)); const ew = new Set(words(exclText));
    const shared = rw.filter((w) => ew.has(w));
    // Half the line's words, two words, or one distinctive word ("waterproofing", "scaffolding") the exclusion names.
    if (rw.length && shared.length && (shared.length / rw.length >= 0.5 || shared.length >= 2 || shared.some((w) => w.length >= 7 && !GENERIC_SCOPE.has(w)))) {
      add({ code: 'scope_excluded', severity: 'high', line_no: no, penalty: 0.8,
        en: `This quote lists "${desc}" under its exclusions, but it is part of what you asked for. The price does not cover it.`,
        ar: `يذكر هذا العرض البند "${desc}" ضمن الاستثناءات، مع أنه جزء مما طلبته. السعر لا يشمله.` });
      return;
    }
    if (j == null) {
      add({ code: 'scope_missing', severity: 'high', line_no: no, penalty: 0.8,
        en: `You asked for "${desc}", and this quote does not price it. A lower total can simply mean this item is left out.`,
        ar: `طلبت "${desc}"، ولا يتضمن هذا العرض سعرًا له. وقد يكون انخفاض الإجمالي ناتجًا عن إغفال هذا البند فقط.` });
      return;
    }
    const ql = qLines[j];
    const rq = num(r.qty), qq = num(ql.qty);
    const ru = normUnit(r.unit), qu = normUnit(ql.unit || S(ql.qty).replace(/^[\d.,\s]+/, ''));
    if (rq != null && qq != null && rq > 0 && (!ru || !qu || ru === qu) && Math.abs(qq - rq) / rq > 0.02) {
      const short = qq < rq; const u = S(r.unit);
      add({ code: 'quantity_mismatch', severity: short ? 'high' : 'medium', line_no: no, penalty: short ? 0.6 : 0.2,
        en: short ? `You asked for ${rq} ${u} of "${desc}"; this quote prices only ${qq} ${u}. Its total covers less than you need.`
          : `You asked for ${rq} ${u} of "${desc}"; this quote prices ${qq} ${u}, more than you asked for, which raises its total.`,
        ar: short ? `طلبت ${rq} ${u} من "${desc}"، بينما يسعّر هذا العرض ${qq} ${u} فقط. إجماليه يغطي أقل مما تحتاج.`
          : `طلبت ${rq} ${u} من "${desc}"، بينما يسعّر هذا العرض ${qq} ${u}، أي أكثر مما طلبت، وهذا يرفع إجماليه.` });
    } else if (rq != null && qq != null && ru && qu && ru !== qu) {
      add({ code: 'quantity_mismatch', severity: 'medium', line_no: no, penalty: 0.2,
        en: `You asked for "${desc}" in ${S(r.unit)}; this quote prices it per ${S(ql.unit) || qu}, so the quantities cannot be compared directly.`,
        ar: `طلبت "${desc}" بوحدة ${S(r.unit)}، بينما يسعّره هذا العرض بوحدة ${S(ql.unit) || qu}، فلا يمكن مقارنة الكميات مباشرة.` });
    }
  });

  // 2. INSTALLATION THE CUSTOMER ASKED FOR, CUT BY "SUPPLY ONLY" OR AN EXCLUSION.
  const keyedInstall = q.terms_spec?.installation?.included;
  const saysNoInstall = keyedInstall === 'no' || (keyedInstall !== 'yes' && (SUPPLY_ONLY.test([q.scope, q.notes, q.conditions].map(S).join(' ')) || EXCLUDE_INSTALL.test(exclText) || (INSTALL_WORD.test(S(q.exclusions)))));
  if (customerAnswer(req, 'installation') === 'yes' && saysNoInstall) {
    add({ code: 'scope_excluded', severity: 'high', line_no: null, penalty: 0.8,
      en: 'You asked for installation, and this quote is for supply only: installation is not included in its price.',
      ar: 'طلبت التركيب، وهذا العرض للتوريد فقط: التركيب غير مشمول في سعره.' });
  }

  // 3. ORIGIN, BRAND AND GRADE, line by line (a line with no request line is compared with the brief alone).
  const globalOrigin = statedOriginOf(materialText) ?? statedOriginOf(brief) ?? originOf(S((input.request.spec as Record<string, unknown> | null)?.origin)) ?? null;
  const rows: { no: number | null; reqText: string; ql: QuoteLineIn }[] = [];
  reqLines.forEach((r, i) => { const j = pairs.get(i); if (j != null) rows.push({ no: Number(r.line_no ?? i + 1), reqText: S(r.description), ql: qLines[j] }); });
  if (!reqLines.length) for (const ql of qLines) rows.push({ no: null, reqText: '', ql });
  const brandSeen = new Set<string>();
  for (const { no, reqText, ql } of rows) {
    const desc = reqText ? reqWords(reqText) : quoteWords(ql);
    const text = lineText(ql);
    // ORIGIN: the line's own country_of_origin, an origin it states, or (named as such) its brand's origin.
    const asked = statedOriginOf(reqText) ?? globalOrigin;
    if (asked) {
      const stated = originOf(ql.country_of_origin) ?? statedOriginOf([ql.description, ql.specification, ql.notes, S((ql.spec || {} as Record<string, unknown>).origin), S((ql.spec || {} as Record<string, unknown>).country_of_origin)].map(S).join(' '));
      const qb = quotedBrand(ql);
      const viaBrand = !stated && qb?.origin ? qb.origin : null;
      const got = stated ?? viaBrand;
      if (got && !originMeets(asked, got)) {
        add({ code: 'origin_deviation', severity: 'high', line_no: no, penalty: 0.9,
          en: viaBrand ? `You asked for ${originAdj(asked)} origin for "${desc}"; this quote offers a ${genericBrand(qb!.name).en} and states no country of manufacture. It is not the origin you asked for.`
            : `You asked for ${originAdj(asked)} origin for "${desc}"; this quote states ${originAdj(got)} origin. It is not the product you asked for.`,
          ar: viaBrand ? `طلبت منشأً من ${originLabel(asked, 'ar')} للبند "${desc}"، بينما يعرض هذا العرض ${genericBrand(qb!.name).ar} دون ذكر بلد التصنيع. هذا ليس المنشأ الذي طلبته.`
            : `طلبت منشأً من ${originLabel(asked, 'ar')} للبند "${desc}"، بينما يذكر هذا العرض أن المنشأ ${originLabel(got, 'ar')}. هذا ليس المنتج الذي طلبته.` });
      } else if (!got) {
        add({ code: 'origin_not_stated', severity: 'medium', line_no: no, penalty: 0.2,
          en: `You asked for ${originAdj(asked)} origin for "${desc}"; this quote does not state the origin, so it cannot be confirmed.`,
          ar: `طلبت منشأً من ${originLabel(asked, 'ar')} للبند "${desc}"، ولا يذكر هذا العرض بلد المنشأ، فلا يمكن التأكد منه.` });
      }
    }
    // BRAND: the make the customer named, against the make quoted — named only generically before the reveal.
    const rb = requestedBrand(reqText) ?? (reqLines.length ? null : requestedBrand(materialText));
    const qb = quotedBrand(ql);
    if (rb && qb) {
      const same = rb.name.toLowerCase() === qb.name.toLowerCase();
      const k = `${no}|${same}`; if (brandSeen.has(k)) continue; brandSeen.add(k);
      if (same) {
        add({ code: 'brand_match', severity: 'info', line_no: no, penalty: 0,
          en: `Matches the requested brand for "${desc}": yes.`, ar: `مطابق للعلامة التجارية المطلوبة للبند "${desc}": نعم.` });
      } else {
        const g = genericBrand(qb.name, qb.tier);
        const lower = rb.tier && g.tier && TIER_RANK[g.tier] < TIER_RANK[rb.tier];
        add({ code: 'brand_alternative', severity: rb.equivalent ? 'info' : 'medium', line_no: no, penalty: rb.equivalent ? 0 : 0.4,
          en: `Matches the requested brand for "${desc}": no. Alternative offered: ${g.en}.${rb.equivalent ? ' You allowed an equivalent.' : ' You did not ask for an alternative.'}`,
          ar: `مطابق للعلامة التجارية المطلوبة للبند "${desc}": لا. البديل المعروض: ${g.ar}.${rb.equivalent ? ' وقد سمحت ببديل مكافئ.' : ' ولم تطلب بديلًا.'}` });
        if (lower) {
          add({ code: 'brand_tier_lower', severity: 'high', line_no: no, penalty: 0.7,
            en: `The alternative offered for "${desc}" is a ${g.tier} brand, a lower tier than the ${rb.tier} brand you asked for.`,
            ar: `البديل المعروض للبند "${desc}" علامة من فئة أدنى من الفئة التي طلبتها.` });
        }
      }
    }
    // GRADE: every family the request states, against the same family in the quoted line.
    const want = gradesOf(`${reqText} ${reqLines.length ? '' : materialText}`), have = gradesOf(text);
    for (const [fam, w] of want) {
      const h = have.get(fam); if (!h || h.rank >= w.rank) continue;
      add({ code: 'grade_lower', severity: 'high', line_no: no, penalty: 0.7,
        en: `Lower ${fam} than you asked for on "${desc}": you asked for ${w.shown}, this quote states ${h.shown}. A lower price here usually means a lower specification.`,
        ar: `${familyAr(fam)} أدنى مما طلبت في البند "${desc}": طلبت ${w.shown}، بينما يذكر هذا العرض ${h.shown}. انخفاض السعر هنا يعني غالبًا مواصفة أدنى.` });
    }
    // A requested tier word ("premium") against a quoted economy make.
    const askedTier = tierOf(reqText); const qTier = qb?.tier ?? tierOf(text);
    if (askedTier && qTier && TIER_RANK[qTier] < TIER_RANK[askedTier] && !(rb && qb)) {
      add({ code: 'brand_tier_lower', severity: 'high', line_no: no, penalty: 0.7,
        en: `You asked for a ${askedTier} product for "${desc}"; this quote offers a ${qTier} one.`,
        ar: `طلبت منتجًا من الفئة ${askedTier === 'premium' ? 'الفاخرة' : 'المتوسطة'} للبند "${desc}"، بينما يعرض هذا العرض منتجًا من فئة أدنى.` });
    }
  }

  // 4. LEAD TIME against the customer's required date (a flexible date accepts any).
  const rb = req?.required_by;
  const due = rb && !rb.flexible && rb.date ? new Date(String(rb.date)) : null;
  const leadValue = S(q.terms_spec?.delivery?.value) || S(q.lead_time);
  if (due && !isNaN(due.getTime()) && leadValue) {
    const d = deliveryOf(leadValue);
    const at = d?.days != null ? new Date(now.getTime() + d.days * 864e5) : d?.date ? new Date(d.date) : null;
    if (at && !isNaN(at.getTime()) && at.getTime() > due.getTime() + 864e5) {
      add({ code: 'lead_time_late', severity: 'high', line_no: null, penalty: 0.5,
        en: `You need this by ${fmtDate(due)}. With a lead time of "${clip(leadValue, 40)}" this quote would deliver around ${fmtDate(at)}, after your date.`,
        ar: `تحتاج هذا قبل ${fmtDate(due)}. وبمدة تسليم "${clip(leadValue, 40)}" سيكون التسليم في هذا العرض نحو ${fmtDate(at)}، أي بعد موعدك.` });
    }
  }

  // 5. WARRANTY against the customer's minimum months.
  const minM = Number(req?.warranty?.min_months) > 0 ? Number(req!.warranty!.min_months) : null;
  const wValue = S(q.terms_spec?.warranty?.period) || S(q.warranty);
  if (minM && wValue && customerAnswer(req, 'warranty') !== 'no') {
    const w = warrantyPeriod(wValue);
    if (w.months != null && w.months < minM) {
      add({ code: 'warranty_short', severity: 'high', line_no: null, penalty: 0.5,
        en: `You asked for at least ${minM} months of warranty; this quote gives ${w.period}.`,
        ar: `طلبت ضمانًا لا يقل عن ${minM} شهرًا، بينما يقدّم هذا العرض ضمانًا لمدة ${w.months} ${w.months === 1 ? 'شهر' : 'شهرًا'}.` });
    }
  }
  const order = { high: 0, medium: 1, info: 2 } as const;
  return notes.sort((a, b) => order[a.severity] - order[b.severity] || (a.line_no ?? 0) - (b.line_no ?? 0));
}

/** The ranking's penalty for a quote: the sum of its notes' penalties, capped so a quote is never scored below 1. */
export function reviewPenalty(notes: ReviewNote[] | null | undefined): number {
  return Math.min(3, (notes || []).reduce((s, n) => s + (Number(n.penalty) || 0), 0));
}
/** The notes as the comparison's two lists: what the request has that the quote lacks, and where it deviates. */
export function notesAsLists(notes: ReviewNote[] | null | undefined, lang: 'en' | 'ar'): { missing_from_request: string[]; spec_deviation: string[] } {
  const t = (n: ReviewNote) => (lang === 'ar' ? n.ar : n.en);
  const ns = notes || [];
  return {
    missing_from_request: ns.filter((n) => n.code === 'scope_missing' || n.code === 'scope_excluded').map(t),
    spec_deviation: ns.filter((n) => DEVIATION_CODES.has(n.code) && n.code !== 'scope_missing' && n.code !== 'scope_excluded').map(t),
  };
}

/** The request side of reviewNotes, read from an inquiries row (boq, spec, summary, raw_input). */
// deno-lint-ignore no-explicit-any
export function requestOf(inq: any, now?: Date): ReviewInput['request'] {
  const boq = inq?.boq && Array.isArray(inq.boq.boq) ? inq.boq.boq : Array.isArray(inq?.boq) ? inq.boq : [];
  // deno-lint-ignore no-explicit-any
  const lines = boq.map((b: any, i: number) => ({ line_no: i + 1, description: S(b?.description), qty: b?.qty ?? null, unit: b?.unit ?? null, section: b?.section ?? null }))
    // a section heading with no quantity is not an item
    .filter((b: RequestLine) => S(b.description) && !(b.qty == null && /^(?:section|part|zone|area|floor|level)\b/i.test(S(b.description))));
  return { lines, spec: inq?.spec ?? null, summary: inq?.summary ?? null, raw_input: typeof inq?.raw_input === 'string' ? inq.raw_input : null, now };
}
