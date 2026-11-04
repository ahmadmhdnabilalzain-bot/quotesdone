// line_specs/assess.ts — the hold decision: is every detail this request needs stated, exactly?
//
// THE REQUIRED SET IS THE CUSTOMER'S INQUIRY, THEN THE TRADE'S STANDARD (founder, 14 Sep 2026,
// founder_instruction #142): "the automatic check is not fixed, its depending on the customer inquiry
// details taken by the sales agent along with the general standards for such inquiry." And #159:
// "for installation for example, we need to ask, cause maybe the customer will forget. we don't
// assume stuff."
//
//   * requirementsOf() reads the intake's stored object (customer_requirements; `requirements` as the
//     second place a newer intake may write).
//   * installation / warranty are required UNLESS the customer explicitly chose not needed (the intake's
//     keyed choice "supply_only" / "not_needed"). "yes", "not_sure" and no answer at all require it.
//   * every material or finish the customer named for a component is required on the line that names
//     that component (or on the quote, when no line names it) — "no preference" still requires the
//     supplier to state a value.
//   * the trade's own mandatory core (model.ts) is the general standard and always applies.
//
// Five things are checked: (1) material specification per line, (2) a concrete delivery date or lead
// time, (3) installation included or not, with scope or timeline, (4) warranty period and coverage,
// (5) the price excluding VAT. Missing any → HELD: never rejected, never shown to the customer.
//
// WHAT CHANGED, 23 Sep 2026 (founder_instruction 886-903, ledger 890; decision point 30 line_specs.assess).
// This file used to READ the supplier's words: a material lexicon, installation / warranty / delivery
// regexes, a token overlap deciding which line names a customer's component, an option-heading pattern and
// a vagueness pattern. It reads no words now. It decides only from:
//   * values the supplier STATED in keyed fields (quote_items.spec, quotes.terms_spec, source
//     'supplier_portal'), and figures in number columns (a priced installation);
//   * what REASONING read from his quotation (source 'reasoned', written by _shared/reasoned_matching.ts
//     readQuote: think() with his own words as verbatim evidence) — including which trade a line is,
//     that it carries no material, that a conditional attribute does not apply, and that it names a
//     customer's component (the READ keys below, honoured only when their source is 'reasoned');
//   * FORMAT: a lead time's number and unit, a date, a warranty's number of years or months.
// Under the model hold nothing is read, so every required detail is asked and the quote is HELD until the
// supplier states it — "exact specs or the quote is held", and never a guess.
// Pure: no I/O, no model, no clock.
import { attrsOf, COMPOSITE, normText, TRADES, tradeOfCategory, type Attr } from './model.ts';
import { componentLabel } from '../intake_requirements.ts';
// The word readers supplier_api/quote_review.ts still calls (decision point 31, another batch); nothing here uses them.
export { readDelivery, readInstallation, readWarranty } from './legacy_word_readers.ts';

export type Src = 'extracted' | 'supplier_portal' | 'reasoned';
export type Line = {
  line_no: number; description: string; brand?: string | null; model?: string | null; specification?: string | null;
  qty?: number | string | null; unit?: string | null; unit_price?: number | null; labour?: number | null; install?: number | null;
  amount?: number | null; notes?: string | null;
  spec?: Record<string, string> | null; spec_source?: Record<string, Src> | null;
};
export type Terms = {
  lead_time?: string | null; warranty?: string | null; scope?: string | null; exclusions?: string | null;
  conditions?: string | null; notes?: string | null; terms_spec?: TermsSpec | null;
  /** The figure compared and charged 3% on (vat.ts). Null when it could not be determined exactly. */
  price_ex_vat?: number | null;
};
export type TermsSpec = {
  delivery?: { value: string; source: Src } | null;
  installation?: { included: 'yes' | 'no'; detail?: string | null; source: Src } | null;
  warranty?: { period: string; coverage: string; source: Src } | null;
  /** A component the customer named that no line of the quote names, stated on the portal. */
  components?: Record<string, { value: string; source: Src }> | null;
};

/** The customer's intake answers — docs/contracts/intake_answers.md (version 1). Every field optional. */
export type Material = { component: string; label_en?: string | null; label_ar?: string | null; choice?: string | null; choice_en?: string | null; choice_ar?: string | null; note?: string | null };
export type Requirements = {
  version?: number; category?: string | null;
  installation?: { required?: string | null } | null;
  warranty?: { required?: string | boolean | null; min_months?: number | null } | null;
  materials?: Material[] | null;
  required_by?: { flexible?: boolean | null; date?: string | null; text?: string | null } | null;
} | null;

/** Where the intake stores the answers on an inquiry's spec. */
export function requirementsOf(spec: unknown): Requirements {
  // deno-lint-ignore no-explicit-any
  const s: any = spec && typeof spec === 'object' ? spec : null;
  const r = s?.customer_requirements ?? s?.requirements ?? null;
  return r && typeof r === 'object' ? (r as Requirements) : null;
}
// The intake's KEYED choices (docs/contracts/intake_answers.md): "yes" | "supply_only" | "not_needed" | "not_sure".
const NOT_NEEDED_CHOICES = new Set(['no', 'false', 'not_needed', 'supply_only']);
const choiceOf = (v: unknown) => String(v ?? '').trim().toLowerCase().replace(/[\s-]+/g, '_');
/** Installation / warranty: required unless the customer explicitly chose "not needed" / "supply only". */
export function customerRequires(req: Requirements, what: 'installation' | 'warranty'): boolean {
  const v = req?.[what]?.required;
  return !(v === false || NOT_NEEDED_CHOICES.has(choiceOf(v)));
}
/** What the customer actually asked for, as a baseline: 'yes' / 'no' / null (not sure or not asked). */
export function customerAnswer(req: Requirements, what: 'installation' | 'warranty'): 'yes' | 'no' | null {
  const v = req?.[what]?.required;
  if (v === true || choiceOf(v) === 'yes') return 'yes';
  if (!customerRequires(req, what)) return 'no';
  return null;
}

export type MissingItem = {
  scope: 'line' | 'quote'; line_no: number | null; description: string | null; attr: string;
  label_en: string; label_ar: string; type: 'text' | 'number' | 'choice'; unit?: string; unit_ar?: string; options?: string[];
};
export type LineResult = {
  line_no: number; description: string; trade: string | null; material: boolean;
  /** The heading this line sits under ("Option 1: standard system", "Ground floor"), or null. */
  group?: string | null;
  spec: Record<string, string>; source: Record<string, Src>; asked: string[]; missing: string[];
  /** The attributes asked of this line, the trade's plus the customer's (not serialised to clients). */
  defs: Attr[];
};
export type TermResult = {
  delivery: { applies: true; value: string | null; days: number | null; date: string | null; source: Src | null };
  installation: { applies: boolean; included: 'yes' | 'no' | null; detail: string | null; source: Src | null };
  warranty: { applies: boolean; period: string | null; months: number | null; coverage: string | null; source: Src | null };
  components: Record<string, string | null>;
};
export type Assessment = { trade: string; held: boolean; lines: LineResult[]; terms: TermResult; missing: MissingItem[] };

// ---------------------------------------------------------------------------------------------
// What reasoning read from a line, kept on the line's own spec under keys a supplier cannot type (the
// portal accepts only keys starting with a letter) and honoured only when their source is 'reasoned'.
// ---------------------------------------------------------------------------------------------
export const READ = {
  trade: '_trade',                          // composite quotes: the trade this line is, or 'none'
  notMaterial: '_not_material',             // the supplier's words that say the line carries no material
  na: (attr: string) => `_na:${attr}`,      // the words that show a conditional attribute does not apply
  names: (component: string) => `_names:${component}`, // the words that name the customer's component
} as const;
export function reasoned(l: Pick<Line, 'spec' | 'spec_source'>, key: string): string | null {
  return l.spec_source?.[key] === 'reasoned' && l.spec?.[key] ? String(l.spec[key]) : null;
}

// "NO MATERIAL" NEEDS MORE THAN THE SUPPLIER SAYING SO (it_engineer, 3 Nov 2026, release qualification). READ.notMaterial
// is the supplier's own words as reasoning read them, and it skipped every spec question on the line: "Wardrobe MDF
// carcass, labour only" and "Ceramic tiles 60x60 (labour only)" passed unasked. The words now count only when the line
// itself agrees: they are in its description; the line has no dimension, no brand or model and no stated value; and no
// other word of the line is a material or finish of its trade (the catalogue's own options: MDF, plywood, oak, HPL for
// joinery; porcelain, ceramic, marble for tiling), unless the line is priced as labour (a labour or install figure and no
// unit price). A service line of any length ("Delivery charges to Abu Dhabi site", "Removal and disposal of existing
// wardrobes", "Labour charges for installation of 3 wardrobes") still skips its specs (review of #1836: a one-other-word
// rule held them). The unit says nothing either way: labour per m2 is ordinary.
// ponytail: a material named in no catalogue option ("tiles", "gypsum board") passes on the words; extending the
// vocabulary is the upgrade if a measured case shows it.
const DIMENSION = /\d\s*(?:mm|cm|m²|m2|m3)\b|\d\s*[x×*]\s*\d/i;
const words = (s: string) => s.toLowerCase().replace(/[^\p{L}\p{N}&]+/gu, ' ').trim().split(' ').filter(Boolean);
// option words that name no material ("Standard gypsum board"): "Standard delivery and offloading" is a service line
const NOT_MATERIAL_WORDS = new Set(['standard', 'other', 'none']);
const optionWords = (codes: string[]) => new Set(codes.flatMap((c) => TRADES[c]?.attrs ?? [])
  .flatMap((a) => a.options ?? []).flatMap(words).filter((w) => w.length >= 3 && !/^\d/.test(w) && !NOT_MATERIAL_WORDS.has(w)));
const VOCAB_OF = new Map<string, Set<string>>();
/** The material and finish words of a trade (every catalogue trade's, for a trade the catalogue does not hold). */
function materialWords(trade: string | null): Set<string> {
  const key = trade && TRADES[trade] ? trade : '*';
  if (!VOCAB_OF.has(key)) VOCAB_OF.set(key, optionWords(key === '*' ? Object.keys(TRADES) : [key]));
  return VOCAB_OF.get(key)!;
}
export function notMaterialHolds(l: Line, trade: string | null = null): boolean {
  const said = reasoned(l, READ.notMaterial);
  if (!said) return false;
  const desc = words(l.description ?? ''); const ev = words(said);
  if (!ev.length || !ev.every((w) => desc.includes(w))) return false;   // the words are not the line's own
  if (DIMENSION.test([l.description, l.specification].filter(Boolean).join(' ')) || l.brand || l.model) return false;
  if (Object.entries(l.spec ?? {}).some(([k, v]) => !k.startsWith('_') && String(v ?? '').trim())) return false;
  const pricedAsLabour = (Number(l.labour) > 0 || Number(l.install) > 0) && !(Number(l.unit_price) > 0);
  const vocab = materialWords(trade);
  return pricedAsLabour || !desc.some((w) => !ev.includes(w) && vocab.has(w));
}

// ---------------------------------------------------------------------------------------------
// The customer's components on the supplier's lines.
// ---------------------------------------------------------------------------------------------
// A component the intake asked about maps to the line attribute that states it: an explicit mapping
// where the vocabulary lines up, otherwise the line's own material-type attribute, otherwise a
// dedicated "Material — <component>" attribute.
const COMPONENT_ATTR: Record<string, string> = { board: 'material', finish: 'finish', pipes: 'pipe_material', floor_finish: 'material', ceiling: 'board_type', partitions: 'board_type', sheet: 'type' };
export const MATERIAL_ATTRS = ['material', 'board_type', 'pipe_material', 'glass_type', 'fabric', 'block_type', 'system', 'type', 'cable_type', 'protocol'];
// Keyed intake choices, compared exactly.
const isNoPref = (m: Material) => choiceOf(m.choice) === 'no_preference';
const isOther = (m: Material) => String(m.choice ?? '') === 'other';
/** The baseline value for comparison: the customer's choice in English, or their own words for "other". */
export function requestedValue(m: Material): string | null {
  if (isNoPref(m)) return null;
  if (isOther(m)) return m.note ? String(m.note) : null;
  return m.choice_en ? String(m.choice_en).replace(/^Other:\s*/i, '') : (m.choice ? String(m.choice).replace(/_/g, ' ') : null);
}
// A material's own labels first; a bare key ({component:'glass'}) takes the intake catalogue's names,
// never the key itself. Measured 14 Sep 2026: the Arabic comparison printed "المادة — glass".
export function materialNames(m: Material): { en: string; ar: string } {
  const cat = componentLabel(m.component);
  const en = String(m.label_en || cat?.en || m.component.replace(/_/g, ' '));
  return { en, ar: String(m.label_ar || cat?.ar || en) };
}
/**
 * The attribute that states component `m` on a line, forced mandatory. Only an explicit vocabulary
 * mapping (board → material, finish → finish, pipes → pipe_material …) or the generic "main material"
 * reuses a trade attribute; any other component — "legs or base", "top or main body" — gets its own.
 */
export function componentAttr(m: Material, _trade: string | null, base: Attr[]): Attr {
  const byCode = (c: string) => base.find((a) => a.code === c);
  const hit = (COMPONENT_ATTR[m.component] && byCode(COMPONENT_ATTR[m.component])) || (m.component === 'main' ? (MATERIAL_ATTRS.map(byCode).find(Boolean) || byCode('brand')) : undefined);
  if (hit) return { ...hit, mandatory: true };
  const { en, ar } = materialNames(m);
  return { code: `component_${m.component}`, en: `Material — ${en}`, ar: `المادة — ${ar}`, type: 'text', mandatory: true };
}
/** Does this line name the customer's component? Only what reasoning read says so ('main' is every line). */
export function componentOnLine(m: Material, l: Pick<Line, 'spec' | 'spec_source'>): boolean {
  return m.component === 'main' || !!reasoned(l, READ.names(m.component));
}

// A line of a composite quote whose trade has not been read (the model hold): its exact specification is
// asked as one detail, so the quote is held rather than passed unchecked.
export const SPEC_ATTR: Attr = {
  code: 'specification', en: 'Exact specification (what it is, material, size, make and model)',
  ar: 'المواصفة الدقيقة (النوع، المادة، المقاس، الشركة المصنّعة والموديل)', type: 'text', mandatory: true,
};

// ---------------------------------------------------------------------------------------------
// FORMAT readers. A lead time is a number and a unit, or a date; a warranty period is a number of years or
// months. These parse the shape of a value already stated in its own field — they decide no meaning.
// ---------------------------------------------------------------------------------------------
const MONTHS = 'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|يناير|فبراير|مارس|أبريل|ابريل|مايو|يونيو|يوليو|أغسطس|اغسطس|سبتمبر|أكتوبر|اكتوبر|نوفمبر|ديسمبر';
const DATE_FMT = new RegExp(`\\b(\\d{4}-\\d{2}-\\d{2}|\\d{1,2}[\\/.\\-]\\d{1,2}[\\/.\\-]\\d{2,4}|\\d{1,2}\\s+(?:${MONTHS})\\s*,?\\s*\\d{0,4}|(?:${MONTHS})\\s+\\d{1,2}(?:,\\s*\\d{4})?)`, 'i');
const DURATION_FMT = /(\d+(?:\.\d+)?)\s*(?:-\s*\d+\s*)?(working\s*days?|business\s*days?|days?|weeks?|months?|wks?|يوم عمل|أيام عمل|يوم|أيام|يوما|يومًا|أسبوع|أسابيع|اسبوع|اسابيع|شهر|أشهر|شهور)/i;
/** A stated delivery value as days or a date; null when it has neither shape. */
export function deliveryOf(value: string): { value: string; days: number | null; date: string | null } | null {
  const s = normText(value); if (!s) return null;
  const d = s.match(DURATION_FMT);
  if (d) { const n = Number(d[1]); const u = d[2].toLowerCase(); const days = /week|wk|أسبوع|أسابيع|اسبوع|اسابيع/.test(u) ? n * 7 : /month|شهر|أشهر|شهور/.test(u) ? n * 30 : n; return { value: s.slice(0, 120), days, date: null }; }
  const dt = s.match(DATE_FMT); if (dt) return { value: s.slice(0, 120), days: null, date: dt[1] };
  return null;
}
const MONTH_NO: [RegExp, number][] = [[/^jan|^\u064a\u0646\u0627\u064a\u0631/, 1], [/^feb|^\u0641\u0628\u0631\u0627\u064a\u0631/, 2], [/^mar|^\u0645\u0627\u0631\u0633/, 3], [/^apr|^\u0623\u0628\u0631\u064a\u0644|^\u0627\u0628\u0631\u064a\u0644/, 4], [/^may|^\u0645\u0627\u064a\u0648/, 5], [/^jun|^\u064a\u0648\u0646\u064a\u0648/, 6],
  [/^jul|^\u064a\u0648\u0644\u064a\u0648/, 7], [/^aug|^\u0623\u063a\u0633\u0637\u0633|^\u0627\u063a\u0633\u0637\u0633/, 8], [/^sep|^\u0633\u0628\u062a\u0645\u0628\u0631/, 9], [/^oct|^\u0623\u0643\u062a\u0648\u0628\u0631|^\u0627\u0643\u062a\u0648\u0628\u0631/, 10], [/^nov|^\u0646\u0648\u0641\u0645\u0628\u0631/, 11], [/^dec|^\u062f\u064a\u0633\u0645\u0628\u0631/, 12]];
const monthNo = (m: string) => MONTH_NO.find(([r]) => r.test(m.toLowerCase()))?.[1] ?? 0;
/** A stated date as a UTC day (numeric dates are read day-first, as written in the UAE); null when it cannot be read. */
function dateOf(s: string, now: Date): Date | null {
  const y4 = (y: string | undefined) => !y ? now.getUTCFullYear() : y.length === 2 ? 2000 + Number(y) : Number(y);
  let m: RegExpMatchArray | null; let d = 0, mo = 0, y = 0;
  if ((m = s.match(/^(\d{4})-(\d{2})-(\d{2})$/))) [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  else if ((m = s.match(/^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2,4})$/))) [d, mo, y] = [Number(m[1]), Number(m[2]), y4(m[3])];
  else if ((m = s.match(/^(\d{1,2})\s+(\S+?)\s*,?\s*(\d{4})?$/))) [d, mo, y] = [Number(m[1]), monthNo(m[2]), y4(m[3])];
  else if ((m = s.match(/^(\S+)\s+(\d{1,2})(?:,\s*(\d{4}))?$/))) [d, mo, y] = [Number(m[2]), monthNo(m[1]), y4(m[3])];
  if (!(d >= 1 && d <= 31 && mo >= 1 && mo <= 12 && y >= 2000)) return null;
  const t = new Date(Date.UTC(y, mo - 1, d));
  return t.getUTCDate() === d ? t : null;
}
/**
 * A quote's validity: a positive number of days/weeks/months, or a date that has not passed. "0 days", a past date
 * or a date that cannot be read is not a validity (security review of #1371) — the prices would already have lapsed.
 */
export function validityOf(value: string, now: Date = new Date()): { value: string; days: number | null; date: string | null } | null {
  const v = deliveryOf(value);
  if (!v) return null;
  if (v.days != null) return v.days > 0 ? v : null;
  const t = v.date ? dateOf(v.date.trim(), now) : null;
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  return t && t.getTime() >= today ? v : null;
}
const PERIOD_FMT = /(\d+(?:\.\d+)?)\s*(years?|yrs?|months?|mos?|سنة|سنوات|سنه|عام|أعوام|اعوام|شهر|أشهر|شهور)|\b(one|two|three|five|ten)\s+years?\b|(سنتين|سنتان|عامين)/i;
const WORDNUM: Record<string, number> = { one: 1, two: 2, three: 3, five: 5, ten: 10 };
/** A stated warranty period as months; null when it has no number-and-unit shape. */
export function warrantyPeriod(value: string): { period: string | null; months: number | null } {
  const m = normText(value).match(PERIOD_FMT);
  if (!m) return { period: null, months: null };
  if (m[1]) { const n = Number(m[1]); const isMonth = /month|mo|شهر|أشهر|شهور/.test(m[2].toLowerCase()); return { months: isMonth ? n : n * 12, period: `${n} ${isMonth ? (n === 1 ? 'month' : 'months') : (n === 1 ? 'year' : 'years')}` }; }
  if (m[3]) { const months = WORDNUM[m[3].toLowerCase()] * 12; return { months, period: `${months / 12} years` }; }
  return { months: 24, period: '2 years' };
}

const TERM_LABEL: Record<string, [string, string, MissingItem['type']]> = {
  line_items: ['Itemised lines, each with its material specification', 'بنود مفصّلة تتضمن مواصفات المادة لكل بند', 'text'],
  delivery: ['Delivery date or lead time (e.g. 21 days, or 30 Oct 2026)', 'تاريخ التسليم أو مدة التنفيذ (مثل 21 يومًا أو 30 أكتوبر 2026)', 'text'],
  installation_included: ['Is installation included?', 'هل التركيب مشمول؟', 'choice'],
  installation_detail: ['Installation scope or timeline', 'نطاق التركيب أو مدته', 'text'],
  warranty_period: ['Warranty period', 'مدة الضمان', 'text'],
  warranty_coverage: ['What the warranty covers', 'ما يغطيه الضمان', 'text'],
  // Asked by the hold desk (workflow.ts deskAssess), because the release review (quote_review.ts rule 7) asks it.
  validity: ['How long your prices are valid (e.g. 30 days, or 30 Nov 2026)', 'مدة صلاحية أسعاركم (مثل 30 يومًا أو 30 نوفمبر 2026)', 'text'],
  price_ex_vat: ['Total price excluding VAT', 'السعر الإجمالي غير شامل ضريبة القيمة المضافة', 'number'],
};
export const termItem = (attr: string, label?: [string, string]): MissingItem => {
  const [en, ar, type] = label ? [label[0], label[1], 'text' as const] : TERM_LABEL[attr];
  return { scope: 'quote', line_no: null, description: null, attr, label_en: en, label_ar: ar, type, ...(type === 'choice' ? { options: ['yes', 'no'] } : {}), ...(attr === 'price_ex_vat' ? { unit: 'AED', unit_ar: 'درهم' } : {}) };
};
const lineItem = (l: Line, a: Attr): MissingItem => ({
  scope: 'line', line_no: l.line_no, description: l.description, attr: a.code, label_en: a.en, label_ar: a.ar, type: a.type,
  ...(a.unit ? { unit: a.unit, unit_ar: a.unit_ar } : {}), ...(a.options ? { options: a.options } : {}),
});

export const lineText = (l: Line) => [l.description, l.brand, l.model, l.specification, l.notes].filter((x) => x != null && String(x).trim() !== '').join(' · ');

/** The trade one line is: the quote's own, or for a composite what reasoning read ('none' = no trade material). */
export function lineTradeOf(quoteTrade: string, l: Pick<Line, 'spec' | 'spec_source'>): string | null {
  if (!COMPOSITE.has(quoteTrade)) return TRADES[quoteTrade] ? quoteTrade : null;
  const t = reasoned(l, READ.trade);
  return t && TRADES[t] ? t : null;
}

/** The attributes one line is asked for: the trade's (less the conditional ones reasoning found do not apply), plus every component the customer named on it. */
export function lineDefs(trade: string | null, l: Pick<Line, 'spec' | 'spec_source'>, req: Requirements): Attr[] {
  const base = attrsOf(trade).filter((a) => !(a.conditional && reasoned(l, READ.na(a.code))));
  let defs = [...base];
  for (const m of req?.materials ?? []) {
    if (!m?.component || !componentOnLine(m, l)) continue;
    const a = componentAttr(m, trade, base);
    const i = defs.findIndex((d) => d.code === a.code);
    if (i >= 0) { defs[i] = { ...defs[i], mandatory: true }; continue; }
    // The customer's component says what "material" means on this line; the trade's own
    // material-type attribute would ask the wrong question of it (a board type of a steel leg).
    if (a.code.startsWith('component_')) defs = defs.filter((d) => !MATERIAL_ATTRS.includes(d.code));
    defs.push(a);
  }
  return defs;
}

const blank = (v: unknown) => v == null || String(v).trim() === '' || Number(v) === 0;
/** No quantity, no unit price, no amount, no install or labour figure: the line prices nothing. */
const pricesNothing = (l: Line) => blank(l.qty) && blank(l.unit_price) && blank(l.amount) && blank(l.install) && blank(l.labour);
/** A heading: it prices nothing and a line after it does, so it labels what follows. Shape only, no words. */
export const isGroupHeading = (l: Line, after: Line[]) => pricesNothing(l) && after.some((x) => !pricesNothing(x));

export function assessQuote(input: { category: string | null; lines: Line[]; terms: Terms; requirements?: Requirements; checklist?: Attr[] }): Assessment {
  const trade = tradeOfCategory(input.category);
  const req = input.requirements ?? null;
  const lines: LineResult[] = [];
  const missing: MissingItem[] = [];
  const lineTrades = new Set<string>();
  const named = new Set<string>();
  let group: string | null = null;
  input.lines.forEach((l, i) => {
    // A GROUP HEADING IS NOT AN ITEM (2 Nov 2026, journey run 41441003027: "Option 1: standard system" was asked its
    // glass type and held a genuine two-option quotation). By SHAPE, never by its words: a line with no quantity and
    // no price, with a priced line after it, labels the lines under it. It is asked nothing; its items are asked all.
    if (isGroupHeading(l, input.lines.slice(i + 1))) {
      group = String(l.description ?? '').trim() || null;
      lines.push({ line_no: l.line_no, description: l.description, trade: null, material: false, group: null, spec: {}, source: {}, asked: [], missing: [], defs: [] });
      return;
    }
    // A line carries no material only when reasoning read the supplier's words saying so AND the line's shape agrees
    // (notMaterialHolds), or read a composite line as no trade. Unread, every line is a material line: asking is safe,
    // passing it unchecked is not.
    const material = !notMaterialHolds(l, reasoned(l, READ.trade) ?? trade) && reasoned(l, READ.trade) !== 'none';
    const lt = material ? lineTradeOf(trade, l) : null;
    const unreadComposite = material && !lt && COMPOSITE.has(trade);
    const namesComponent = material && (req?.materials ?? []).some((m) => m?.component && m.component !== 'main' && componentOnLine(m, l));
    // A trade with no catalogue entry asks each material line its knowledge pack's required specs (reasoned_specs.ts).
    const packOnly = material && !TRADES[trade] && !(COMPOSITE.has(trade) && trade !== 'general') && input.checklist?.length ? input.checklist : [];
    const defs = lt || namesComponent ? lineDefs(lt, l, req) : packOnly.length ? packOnly : unreadComposite ? [SPEC_ATTR, ...lineDefs(null, l, req)] : [];
    for (const m of req?.materials ?? []) if (m?.component && material && m.component !== 'main' && componentOnLine(m, l)) named.add(m.component);
    const spec: Record<string, string> = {}; const source: Record<string, Src> = {};
    for (const a of defs) {
      const v = l.spec?.[a.code];
      if (v && String(v).trim()) { spec[a.code] = String(v); source[a.code] = l.spec_source?.[a.code] ?? 'extracted'; }
    }
    // What reasoning read about the line itself travels with it, so persisting the specs never drops it.
    for (const [k, v] of Object.entries(l.spec ?? {})) if (k.startsWith('_') && l.spec_source?.[k] === 'reasoned') { spec[k] = v; source[k] = 'reasoned'; }
    const miss = defs.filter((a) => a.mandatory && !spec[a.code]);
    if (lt) lineTrades.add(lt);
    for (const a of miss) missing.push(lineItem(l, a));
    lines.push({ line_no: l.line_no, description: l.description, trade: lt, material, group, spec, source, asked: defs.map((a) => a.code), missing: miss.map((a) => a.code), defs });
  });
  if (!lineTrades.size && !lines.some((x) => x.defs.length) && (TRADES[trade] || COMPOSITE.has(trade))) missing.unshift(termItem('line_items'));

  const ts = input.terms.terms_spec ?? {};
  // (1b) A component the customer named that no line names: asked of the quote as a whole.
  const components: Record<string, string | null> = {};
  for (const m of req?.materials ?? []) {
    if (!m?.component || m.component === 'main' || named.has(m.component)) continue;
    const v = ts.components?.[m.component]?.value ?? null;
    components[m.component] = v && String(v).trim() ? v : null;
    if (!components[m.component]) { const n = materialNames(m); missing.push(termItem(`component:${m.component}`, [`Material — ${n.en}`, `المادة — ${n.ar}`])); }
  }

  // (2) Delivery — every quote: the stated (or reasoned) value, else the lead-time field, each by its format.
  const dStated = ts.delivery?.value ? deliveryOf(ts.delivery.value) : null;
  const d = dStated ?? deliveryOf(input.terms.lead_time ?? '');
  const delivery: TermResult['delivery'] = { applies: true, value: d?.value ?? null, days: d?.days ?? null, date: d?.date ?? null, source: d ? (dStated ? ts.delivery!.source ?? 'supplier_portal' : 'extracted') : null };
  if (!d) missing.push(termItem('delivery'));

  // (3) Installation — required unless the customer explicitly said it is not needed. Stated or reasoned,
  // else a priced installation or labour figure on a line (a number, not a word).
  const instApplies = customerRequires(req, 'installation');
  const iStated = ts.installation?.included ? ts.installation : null;
  const pricedInstall = input.lines.some((l) => (Number(l.install) || 0) > 0 || (Number(l.labour) || 0) > 0);
  const iRead: { included: 'yes' | 'no' | null; detail: string | null } = iStated ? { included: iStated.included, detail: iStated.detail ?? null }
    : pricedInstall ? { included: 'yes', detail: 'Installation priced per line' } : { included: null, detail: null };
  const installation: TermResult['installation'] = { applies: instApplies, included: instApplies ? iRead.included : null, detail: instApplies ? iRead.detail : null,
    source: instApplies && iRead.included ? (iStated ? iStated.source ?? 'supplier_portal' : 'extracted') : null };
  if (instApplies) {
    if (!iRead.included) missing.push(termItem('installation_included'));
    else if (iRead.included === 'yes' && !(iRead.detail && iRead.detail.trim())) missing.push(termItem('installation_detail'));
  }

  // (4) Warranty — required unless the customer explicitly said it is not needed. The period by its format
  // (stated, reasoned, or the warranty field); what it covers only as stated or reasoned.
  const wApplies = customerRequires(req, 'warranty');
  const wStated = ts.warranty?.period ? ts.warranty : null;
  const wp = warrantyPeriod(wStated ? wStated.period : (input.terms.warranty ?? ''));
  const coverage = wStated?.coverage && String(wStated.coverage).trim() ? String(wStated.coverage) : null;
  const warranty: TermResult['warranty'] = { applies: wApplies, period: wApplies ? wp.period : null, months: wApplies ? wp.months : null, coverage: wApplies ? coverage : null,
    source: wApplies && wp.period ? (wStated ? wStated.source ?? 'supplier_portal' : 'extracted') : null };
  if (wApplies) {
    if (!wp.period) missing.push(termItem('warranty_period'));
    if (!coverage) missing.push(termItem('warranty_coverage'));
  }

  // (5) The price excluding VAT. Missing or ambiguous is held.
  if (!(Number(input.terms.price_ex_vat) > 0)) missing.push(termItem('price_ex_vat'));

  return { trade, held: missing.length > 0, lines, terms: { delivery, installation, warranty, components }, missing };
}

// ---------------------------------------------------------------------------------------------
// Portal fill-in validation: the SHAPE of what the supplier types into a keyed field. A value with no
// letter or digit is not a value; a number field needs a number; a delivery needs days or a date; a
// warranty period needs years or months. Whether a typed text value is exact is the supplier's own
// statement in that field, and the regenerated quotation he approves shows it back to him.
// ---------------------------------------------------------------------------------------------
export type FillError = { scope: 'line' | 'quote'; line_no: number | null; attr: string; code: 'vague' | 'not_a_number' | 'not_concrete' | 'choose_yes_or_no' | 'unknown_attribute' | 'too_long' };
const hasSubstance = (v: string) => /[\p{L}\p{N}]/u.test(v);
export function validateLineValue(a: Attr, raw: unknown): { ok: true; value: string } | { ok: false; code: FillError['code'] } {
  const v = normText(String(raw ?? ''));
  if (!v || !hasSubstance(v)) return { ok: false, code: 'vague' };
  if (v.length > 120) return { ok: false, code: 'too_long' };
  if (a.type === 'number') { const n = Number(v.replace(/[^\d.]/g, '')); if (!(n > 0) || !/\d/.test(v)) return { ok: false, code: 'not_a_number' }; return { ok: true, value: String(n) }; }
  if (v.length < 2) return { ok: false, code: 'vague' };
  return { ok: true, value: v };
}
export function validateTerm(attr: string, raw: unknown, now: Date = new Date()): { ok: true; value: string } | { ok: false; code: FillError['code'] } {
  const v = normText(String(raw ?? ''));
  if (attr === 'installation_included') return v === 'yes' || v === 'no' ? { ok: true, value: v } : { ok: false, code: 'choose_yes_or_no' };
  if (!v || !hasSubstance(v)) return { ok: false, code: 'vague' };
  if (v.length > 200) return { ok: false, code: 'too_long' };
  if (attr === 'price_ex_vat') { const n = Number(v.replace(/[^\d.]/g, '')); return n > 0 && /\d/.test(v) ? { ok: true, value: String(Math.round(n * 100) / 100) } : { ok: false, code: 'not_a_number' }; }
  if (attr === 'validity') return validityOf(v, now) ? { ok: true, value: v } : { ok: false, code: 'not_concrete' };
  if (attr === 'delivery') return deliveryOf(v) ? { ok: true, value: v } : { ok: false, code: 'not_concrete' };
  if (attr === 'warranty_period') return warrantyPeriod(v).period ? { ok: true, value: v } : { ok: false, code: 'not_concrete' };
  if (attr === 'installation_detail' || attr === 'warranty_coverage' || attr.startsWith('component:')) return v.length >= 2 ? { ok: true, value: v } : { ok: false, code: 'vague' };
  return { ok: false, code: 'unknown_attribute' };
}

// ---------------------------------------------------------------------------------------------
// The supplier's notices, in the supplier's language, signed by the seat that owns the supplier
// portal (founder, 14 Sep 2026: "its always the sales agent") and delivered by customer_support.
// ---------------------------------------------------------------------------------------------
export const SEAT = 'sales_engineer' as const;
export const SEAT_LABEL = { en: 'QuotesDone sales engineer', ar: 'مهندس المبيعات في QuotesDone' } as const;

export function holdLines(a: Assessment, lang: 'en' | 'ar'): string[] {
  const ar = lang === 'ar';
  return a.missing.map((m) => {
    const label = ar ? m.label_ar : m.label_en;
    if (m.scope === 'quote') return `• ${label}`;
    return ar ? `• البند ${m.line_no} (${(m.description ?? '').slice(0, 70)}): ${label}` : `• Line ${m.line_no} (${(m.description ?? '').slice(0, 70)}): ${label}`;
  });
}
export function holdNotice(a: Assessment, lang: 'en' | 'ar', ref: string, optionLabel?: string | null): { subject: string; body: string } {
  const ar = lang === 'ar';
  const opt = optionLabel ? ` — ${optionLabel}` : '';
  const subject = ar ? `عرضكم معلّق لحين استكمال التفاصيل الدقيقة — الطلب ${ref}${opt}` : `Your quote is on hold until the exact details are stated — RFQ ${ref}${opt}`;
  const lines = holdLines(a, lang).join('\n');
  const body = ar
    ? `السادة الكرام،\n\nتحية طيبة وبعد،\n\nنودّ إفادتكم بأن عرضكم للطلب ${ref}${opt} معلّق، ولن يُعرض على العميل إلى أن تُستكمل التفاصيل الدقيقة التالية:\n\n${lines}\n\nولرفع التعليق يمكنكم اتباع إحدى الطريقتين:\n1) استكمال التفاصيل الناقصة عبر بوابة المورّدين، وسنعيد إعداد عرضكم بالصيغة الموحّدة لتراجعوه وتؤكدوا صحته، ثم يُرسل إلى العميل.\n2) أو رفع عرض معدّل جديد يتضمن هذه التفاصيل.\n\nيبقى العرض محفوظًا، ويمكنكم استكماله في أي وقت إلى أن يختار العميل أحد العروض.\n\nوتفضلوا بقبول فائق الاحترام والتقدير،\n${SEAT_LABEL.ar}`
    : `Hello,\n\nYour quote for RFQ ${ref}${opt} is on hold and will not be shown to the customer until the following exact details are stated:\n\n${lines}\n\nYou have two ways to release it:\n1) Fill in the missing details on the supplier portal. We will regenerate your quotation in the standard format for you to check and confirm it is correct, and it is then sent to the customer.\n2) Or upload a new revised quote that states these details.\n\nThe quote stays saved and you can complete it at any time until the customer chooses a quote.\n\n${SEAT_LABEL.en}`;
  return { subject, body };
}
export function approvalNotice(lang: 'en' | 'ar', ref: string): { subject: string; body: string } {
  return lang === 'ar'
    ? { subject: `عرضكم المُعاد إعداده جاهز لاعتمادكم — الطلب ${ref}`, body: `السادة الكرام،\n\nتحية طيبة وبعد،\n\nنشكركم على استكمال التفاصيل. أعدنا إعداد عرضكم للطلب ${ref} بالصيغة الموحّدة، ونرجو مراجعته عبر بوابة المورّدين وتأكيد صحته، ليُرسل بعد ذلك إلى العميل.\n\nوتفضلوا بقبول فائق الاحترام والتقدير،\n${SEAT_LABEL.ar}` }
    : { subject: `Your regenerated quotation is ready for your approval — RFQ ${ref}`, body: `Hello,\n\nThank you for completing the details. We have regenerated your quotation for RFQ ${ref} in the standard format. Please review it on the supplier portal and confirm it is correct, and it will then be sent to the customer.\n\n${SEAT_LABEL.en}` };
}
export function releasedNotice(lang: 'en' | 'ar', ref: string, live: boolean): { subject: string; body: string } {
  return lang === 'ar'
    ? { subject: `اعتُمد عرضكم — الطلب ${ref}`, body: `السادة الكرام،\n\nتحية طيبة وبعد،\n\nنشكركم على التأكيد. ${live ? 'وقد أُرسل عرضكم إلى العميل.' : 'وقد رُفع التعليق عن عرضكم، غير أنه لا يزال بحاجة إلى استكمال شروطه التجارية قبل إرساله إلى العميل.'}\n\nوتفضلوا بقبول فائق الاحترام والتقدير،\n${SEAT_LABEL.ar}` }
    : { subject: `Your quote is approved — RFQ ${ref}`, body: `Hello,\n\nThank you for confirming. ${live ? 'Your quote is now with the customer.' : 'Your quote is no longer on hold; it still needs its commercial terms before it is sent to the customer.'}\n\n${SEAT_LABEL.en}` };
}
