// line_specs/assess.ts — the hold decision: is every detail this request needs stated, exactly?
//
// THE REQUIRED SET IS THE CUSTOMER'S INQUIRY, THEN THE TRADE'S STANDARD (founder, 14 Sep 2026,
// founder_instruction #142): "the automatic check is not fixed, its depending on the customer inquiry
// details taken by the sales agent along with the general standards for such inquiry." And #159:
// "for installation for example, we need to ask, cause maybe the customer will forget. we don't
// assume stuff."
//
// MEASURED BEFORE THIS (14 Sep 2026): #610 read the customer's answers from inquiries.spec.requirements
// in a shape nothing writes. The intake (#608, docs/contracts/intake_answers.md) stores them at
// inquiries.spec.customer_requirements, version 1. So no customer answer ever reached the check, and
// installation and warranty were decided by trade alone. Both are corrected here:
//   * requirementsOf() reads the intake's stored object (customer_requirements; `requirements` as the
//     second place a newer intake may write).
//   * installation / warranty are required UNLESS the customer explicitly said not needed ("no",
//     "not needed", "supply only"). "Yes", "not sure" and no answer at all (a legacy request) all
//     require it: we do not assume. Trade defaults are only the suggestion the intake shows.
//   * every material or finish the customer named for a component is required on the line that
//     names that component (or on the quote, when no line names it) — "no preference" still requires
//     the supplier to state a value.
//   * the trade's own mandatory core (model.ts) is the general standard and always applies.
//
// Five things are checked: (1) material specification per line, (2) a concrete delivery date or lead
// time, (3) installation included or not, with scope or timeline, (4) warranty period and coverage,
// (5) the price excluding VAT. Missing any → HELD: never rejected, never shown to the customer.
// Pure: no I/O, no model, no clock.
import { attrsForLine, COMPOSITE, NON_MATERIAL, normText, TRADES, tradeOfCategory, tradeOfLine, VAGUE, type Attr } from './model.ts';
import { OPTION_HEAD } from './options.ts';
import { componentLabel } from '../intake_requirements.ts';

export type Line = {
  line_no: number; description: string; brand?: string | null; model?: string | null; specification?: string | null;
  qty?: number | string | null; unit?: string | null; unit_price?: number | null; labour?: number | null; install?: number | null;
  amount?: number | null; notes?: string | null;
  spec?: Record<string, string> | null; spec_source?: Record<string, 'extracted' | 'supplier_portal' | 'reasoned'> | null;
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
type Src = 'extracted' | 'supplier_portal' | 'reasoned';

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
const NOT_NEEDED = /^(no|false|not[\s_-]?needed|not[\s_-]?required|supply[\s_-]?only|none|لا|غير مطلوب|توريد فقط)$/i;
/** Installation / warranty: required unless the customer explicitly said it is not needed. */
export function customerRequires(req: Requirements, what: 'installation' | 'warranty'): boolean {
  const v = req?.[what]?.required;
  return !(v === false || (typeof v === 'string' && NOT_NEEDED.test(v.trim())));
}
/** What the customer actually asked for, as a baseline: 'yes' / 'no' / null (not sure or not asked). */
export function customerAnswer(req: Requirements, what: 'installation' | 'warranty'): 'yes' | 'no' | null {
  const v = req?.[what]?.required;
  if (v === true || (typeof v === 'string' && /^yes$/i.test(v.trim()))) return 'yes';
  if (!customerRequires(req, what)) return 'no';
  return null;
}

export type MissingItem = {
  scope: 'line' | 'quote'; line_no: number | null; description: string | null; attr: string;
  label_en: string; label_ar: string; type: 'text' | 'number' | 'choice'; unit?: string; unit_ar?: string; options?: string[];
};
export type LineResult = {
  line_no: number; description: string; trade: string | null; material: boolean;
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
// The customer's components on the supplier's lines.
// ---------------------------------------------------------------------------------------------
// A component the intake asked about maps to the line attribute that states it: an explicit mapping
// where the vocabulary lines up, otherwise the line's own material-type attribute, otherwise a
// dedicated "Material — <component>" attribute read from the line's words.
const COMPONENT_ATTR: Record<string, string> = { board: 'material', finish: 'finish', pipes: 'pipe_material', floor_finish: 'material', ceiling: 'board_type', partitions: 'board_type', sheet: 'type' };
export const MATERIAL_ATTRS = ['material', 'board_type', 'pipe_material', 'glass_type', 'fabric', 'block_type', 'system', 'type', 'cable_type', 'protocol'];
const STOP = new Set(['and', 'the', 'main', 'for', 'with', 'material', 'brand', 'type']);
const MATERIAL_LEXICON: [string, RegExp][] = [
  ['Stainless steel', /stainless\s*steel|ستانلس|ستانلس ستيل/i], ['Steel', /\bsteel\b|\bms\b|mild\s*steel|حديد|ستيل/i], ['Aluminium', /alumin|ألمنيوم|المنيوم|ألومنيوم/i],
  ['Brass', /brass|نحاس أصفر/i], ['Copper', /copper|نحاس/i], ['Glass', /\bglass\b|زجاج/i], ['Marble', /marble|رخام/i], ['Granite', /granite|جرانيت|غرانيت/i],
  ['Quartz', /quartz|كوارتز/i], ['Solid wood', /solid\s*wood|خشب طبيعي|خشب صلب/i], ['MDF', /\bmdf\b|ام دي اف/i], ['Plywood', /plywood|خشب رقائقي/i],
  ['Wood', /\bwood(?:en)?\b|\boak\b|\bteak\b|\bwalnut\b|خشب/i], ['Leather', /leather|جلد/i], ['Fabric', /fabric|upholster|قماش/i], ['PVC', /\bpvc\b/i],
  ['Acrylic', /acrylic|أكريليك|اكريليك/i], ['Ceramic', /ceramic|سيراميك/i], ['Porcelain', /porcelain|بورسلين|بورسلان/i], ['Concrete', /concrete|خرسان/i],
];
const tokensOf = (s: string) => normText(s).toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((w) => w.length >= 3 && !STOP.has(w)).map((w) => w.replace(/s$/, ''));
export function componentOnLine(m: Material, text: string): boolean {
  const words = new Set(tokensOf(text));
  const keys = [...tokensOf(String(m.label_en ?? '')), ...tokensOf(String(m.label_ar ?? '')), ...String(m.component).split('_').filter((w) => w.length >= 3 && !STOP.has(w)).map((w) => w.replace(/s$/, ''))];
  return keys.some((k) => words.has(k));
}
const isNoPref = (m: Material) => /^no[_\s-]?preference$/i.test(String(m.choice ?? ''));
const isOther = (m: Material) => String(m.choice ?? '') === 'other';
/** The baseline value for comparison: the customer's choice in English, or their own words for "other". */
export function requestedValue(m: Material): string | null {
  if (isNoPref(m)) return null;
  if (isOther(m)) return m.note ? String(m.note) : null;
  return m.choice_en ? String(m.choice_en).replace(/^Other:\s*/i, '') : (m.choice ? String(m.choice).replace(/_/g, ' ') : null);
}
function materialReader(m: Material) {
  const want = requestedValue(m);
  const wantTokens = want ? tokensOf(want) : [];
  return (t: string) => {
    if (wantTokens.length) { const w = new Set(tokensOf(t)); if (wantTokens.every((x) => w.has(x))) return want; }
    for (const [v, re] of MATERIAL_LEXICON) if (re.test(t)) return v;
    return null;
  };
}
/**
 * The attribute that states component `m` on a line of trade `trade`, forced mandatory. Only an
 * explicit vocabulary match (board → material, finish → finish, pipes → pipe_material …) or the
 * generic "main material" reuses a trade attribute; any other component — "legs or base", "top or
 * main body" — gets its own attribute read from the customer's own vocabulary, because the trade's
 * board-type reader cannot read "steel legs".
 */
// A material's own labels first; a bare key ({component:'glass'}) takes the intake catalogue's names,
// never the key itself. Measured 14 Sep 2026: the Arabic comparison printed "المادة — glass".
// The key survives only for a component no trade defines.
export function materialNames(m: Material): { en: string; ar: string } {
  const cat = componentLabel(m.component);
  const en = String(m.label_en || cat?.en || m.component.replace(/_/g, ' '));
  return { en, ar: String(m.label_ar || cat?.ar || en) };
}
export function componentAttr(m: Material, _trade: string | null, base: Attr[]): Attr {
  const byCode = (c: string) => base.find((a) => a.code === c);
  const hit = (COMPONENT_ATTR[m.component] && byCode(COMPONENT_ATTR[m.component])) || (m.component === 'main' ? (MATERIAL_ATTRS.map(byCode).find(Boolean) || byCode('brand')) : undefined);
  if (hit) return { ...hit, mandatory: true };
  const { en, ar } = materialNames(m);
  return { code: `component_${m.component}`, en: `Material — ${en}`, ar: `المادة — ${ar}`, type: 'text', mandatory: true, find: materialReader(m) };
}

// ---------------------------------------------------------------------------------------------
// Quote-level readers. Each returns null for what is not stated, and for what is stated vaguely.
// ---------------------------------------------------------------------------------------------
const MONTHS = 'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|يناير|فبراير|مارس|أبريل|ابريل|مايو|يونيو|يوليو|أغسطس|اغسطس|سبتمبر|أكتوبر|اكتوبر|نوفمبر|ديسمبر';
const DATE_RE = new RegExp(`\\b(\\d{4}-\\d{2}-\\d{2}|\\d{1,2}[\\/.\\-]\\d{1,2}[\\/.\\-]\\d{2,4}|\\d{1,2}\\s+(?:${MONTHS})\\s*,?\\s*\\d{0,4}|(?:${MONTHS})\\s+\\d{1,2}(?:,\\s*\\d{4})?)`, 'i');
const DUR_RE = /(\d+(?:\.\d+)?)\s*(?:-\s*\d+\s*)?(working\s*days?|business\s*days?|days?|weeks?|months?|wks?|يوم عمل|أيام عمل|يوم|أيام|يوما|يومًا|أسبوع|أسابيع|اسبوع|اسابيع|شهر|أشهر|شهور)/i;
const IMMEDIATE = /\b(ex[\s-]?stock|from\s*stock|immediate(?:ly)?|same\s*day|next\s*day)\b|من المخزون|فوري|فورا|فوراً/i;

export function readDelivery(text: string): { value: string; days: number | null; date: string | null } | null {
  const s = normText(text); if (!s || VAGUE.test(s)) return null;
  const d = s.match(DUR_RE);
  if (d) { const n = Number(d[1]); const u = d[2].toLowerCase(); const days = /week|wk|أسبوع|أسابيع|اسبوع|اسابيع/.test(u) ? n * 7 : /month|شهر|أشهر|شهور/.test(u) ? n * 30 : n; return { value: s.slice(0, 120), days, date: null }; }
  const dt = s.match(DATE_RE); if (dt) return { value: s.slice(0, 120), days: null, date: dt[1] };
  if (IMMEDIATE.test(s)) return { value: s.slice(0, 120), days: 0, date: null };
  return null;
}

const INSTALL_YES = /supply\s*(?:&|and|\+|,)\s*(?:install|fix|apply|lay|erect)|s\s*[&\/]\s*i\b|supply,?\s*install|includ(?:es|ing|ed)?\s*(?:the\s*)?(?:install|fixing)|install(?:ation)?\s*(?:is\s*)?includ|incl\.?\s*install|install(?:ation)?\s*(?:&|and)\s*commission|توريد وتركيب|شامل التركيب|يشمل التركيب|مع التركيب|التركيب مشمول/i;
const INSTALL_NO = /supply\s*only|install(?:ation)?\s*(?:is\s*)?(?:not\s*included|excluded|by\s*others|extra)|exclud(?:es|ing|ed)?\s*(?:the\s*)?install|without\s*install|توريد فقط|بدون تركيب|التركيب غير مشمول|لا يشمل التركيب|غير شامل التركيب/i;
const INSTALL_LINE = /^(?:\d+[.)]\s*)?(?:install|fix|fixing|erect|lay(?:ing)?|تركيب)|\binstall(?:ation)?\s*(?:of|labou?r|charges?)|تركيب/i;
// "Installation included 4 weeks" / "installation included, 5 working days on site" state the timeline
// (audit 21 Sep 2026: the auditor's CSV said the first and was asked the timeline again).
const INSTALL_TIME = /install\w*\s*(?:is\s*)?(?:included\s*|مشمول\s*)?[,:\-]?\s*(?:period|time|duration|within|in)?\s*[:\-]?\s*(\d+\s*(?:working\s*)?(?:days?|weeks?|يوم|أيام|أسبوع|أسابيع))|(\d+\s*(?:working\s*)?(?:days?|weeks?|يوم|أيام|أسبوع|أسابيع))\s*(?:for\s*)?(?:install|تركيب)|(?:مدة التركيب)\s*[:\-]?\s*([^,;.]{2,30})/i;

export function readInstallation(lines: Line[], t: Terms): { included: 'yes' | 'no' | null; detail: string | null } {
  const lineText = lines.map((l) => `${l.description} ${l.specification ?? ''} ${l.notes ?? ''}`).join(' \n ');
  const all = `${lineText}\n${t.scope ?? ''}\n${t.conditions ?? ''}\n${t.notes ?? ''}`;
  const pricedInstall = lines.some((l) => (Number(l.install) || 0) > 0 || (Number(l.labour) || 0) > 0);
  const installLine = lines.find((l) => INSTALL_LINE.test(l.description) || INSTALL_YES.test(l.description));
  const timeM = normText(all).match(INSTALL_TIME);
  const time = timeM ? (timeM[1] || timeM[2] || timeM[3] || '').trim() : '';
  const detail = time ? `Installation in ${time}` : installLine ? `Scope: ${installLine.description.slice(0, 100)}` : pricedInstall ? 'Installation priced per line' : null;
  if (pricedInstall || installLine) return { included: 'yes', detail };
  if (INSTALL_NO.test(all) || INSTALL_NO.test(t.exclusions ?? '')) return { included: 'no', detail: null };
  if (INSTALL_YES.test(all)) {
    // "Supply and installation of the complete joinery package" in the scope IS the installation
    // scope; a bare "installation included" in the notes names no scope and no timeline.
    const src = [t.scope, t.conditions, t.notes].find((x) => x && INSTALL_YES.test(x) && normText(x).length > 25);
    return { included: 'yes', detail: detail ?? (src ? `Scope: ${normText(src).slice(0, 100)}` : null) };
  }
  return { included: null, detail: null };
}

const W_PERIOD = /(\d+(?:\.\d+)?)\s*(years?|yrs?|months?|mos?|سنة|سنوات|سنه|عام|أعوام|اعوام|شهر|أشهر|شهور)|\b(one|two|three|five|ten)\s+years?\b|(سنتين|سنتان|عامين)/i;
const W_COVER = /(manufactur\w*|parts?|spare\s*parts|labou?r|workmanship|compressor|motor|leak\w*|defects?|materials?|installation|panels?|inverters?|performance|replacement|on\s*-?\s*site|structural|finish|mechanical|electrical|hardware|hinges?|مصنعية|المصنعية|الصناعة|قطع(?:\s*الغيار)?|العمالة|عمالة|تسريب|التسريب|العيوب|عيوب|المواد|الضاغط|الكمبروسر|المحرك|التركيب|الأداء|الاستبدال|شامل)/gi;
const WORDNUM: Record<string, number> = { one: 1, two: 2, three: 3, five: 5, ten: 10 };
export function readWarranty(text: string): { period: string | null; months: number | null; coverage: string | null } {
  const s = normText(text);
  if (!s || VAGUE.test(s)) return { period: null, months: null, coverage: null };
  let period: string | null = null, months: number | null = null;
  const m = s.match(W_PERIOD);
  if (m) {
    if (m[1]) { const n = Number(m[1]); const u = m[2].toLowerCase(); const isMonth = /month|mo|شهر|أشهر|شهور/.test(u); months = isMonth ? n : n * 12; period = `${n} ${isMonth ? (n === 1 ? 'month' : 'months') : (n === 1 ? 'year' : 'years')}`; }
    else if (m[3]) { months = WORDNUM[m[3].toLowerCase()] * 12; period = `${months / 12} years`; }
    else if (m[4]) { months = 24; period = '2 years'; }
  }
  const cov = [...new Set([...s.matchAll(W_COVER)].map((x) => x[1].toLowerCase()))];
  return { period, months, coverage: cov.length ? cov.join(', ') : null };
}

const TERM_LABEL: Record<string, [string, string, MissingItem['type']]> = {
  line_items: ['Itemised lines, each with its material specification', 'بنود مفصّلة تتضمن مواصفات المادة لكل بند', 'text'],
  delivery: ['Delivery date or lead time (e.g. 21 days, or 30 Oct 2026)', 'تاريخ التسليم أو مدة التنفيذ (مثل 21 يومًا أو 30 أكتوبر 2026)', 'text'],
  installation_included: ['Is installation included?', 'هل التركيب مشمول؟', 'choice'],
  installation_detail: ['Installation scope or timeline', 'نطاق التركيب أو مدته', 'text'],
  warranty_period: ['Warranty period', 'مدة الضمان', 'text'],
  warranty_coverage: ['What the warranty covers', 'ما يغطيه الضمان', 'text'],
  price_ex_vat: ['Total price excluding VAT', 'السعر الإجمالي غير شامل ضريبة القيمة المضافة', 'number'],
};
const termItem = (attr: string, label?: [string, string]): MissingItem => {
  const [en, ar, type] = label ? [label[0], label[1], 'text' as const] : TERM_LABEL[attr];
  return { scope: 'quote', line_no: null, description: null, attr, label_en: en, label_ar: ar, type, ...(type === 'choice' ? { options: ['yes', 'no'] } : {}), ...(attr === 'price_ex_vat' ? { unit: 'AED', unit_ar: 'درهم' } : {}) };
};
const lineItem = (l: Line, a: Attr): MissingItem => ({
  scope: 'line', line_no: l.line_no, description: l.description, attr: a.code, label_en: a.en, label_ar: a.ar, type: a.type,
  ...(a.unit ? { unit: a.unit, unit_ar: a.unit_ar } : {}), ...(a.options ? { options: a.options } : {}),
});

export const lineText = (l: Line) => [l.description, l.brand, l.model, l.specification, l.notes].filter((x) => x != null && String(x).trim() !== '').join(' · ');

/** The attributes one line is asked for: the trade's standard, plus every component the customer named on it. */
export function lineDefs(trade: string | null, text: string, req: Requirements): Attr[] {
  const base = trade ? attrsForLine(trade, text) : [];
  let defs = [...base];
  for (const m of req?.materials ?? []) {
    if (!m?.component) continue;
    if (m.component !== 'main' && !componentOnLine(m, text)) continue;
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

export function assessQuote(input: { category: string | null; lines: Line[]; terms: Terms; requirements?: Requirements; checklist?: Attr[] }): Assessment {
  const trade = tradeOfCategory(input.category);
  const req = input.requirements ?? null;
  const lines: LineResult[] = [];
  const missing: MissingItem[] = [];
  const lineTrades = new Set<string>();
  const named = new Set<string>();
  for (const l of input.lines) {
    const text = lineText(l);
    const heading = OPTION_HEAD.test(l.description) && !(Number(l.amount) > 0) && !(Number(l.unit_price) > 0);
    const material = !heading && !NON_MATERIAL.test(l.description.trim());
    const lt = material ? tradeOfLine(trade, text) : null;
    // A line that names a customer's component is a material line even when no trade keyword fits.
    const namesComponent = material && (req?.materials ?? []).some((m) => m?.component && m.component !== 'main' && componentOnLine(m, text));
    // A trade with no line reader asks each material line its knowledge pack's required specs (reasoned_specs.ts).
    const defs = lt || namesComponent ? lineDefs(lt, text, req) : (material && !TRADES[trade] && input.checklist?.length ? input.checklist : []);
    for (const m of req?.materials ?? []) if (m?.component && material && componentOnLine(m, text)) named.add(m.component);
    const spec: Record<string, string> = {}; const source: Record<string, Src> = {};
    for (const a of defs) {
      const prior = l.spec?.[a.code];
      if (prior && !VAGUE.test(normText(prior))) { spec[a.code] = prior; source[a.code] = l.spec_source?.[a.code] ?? 'extracted'; continue; }
      const v = a.find(text);
      if (v) { spec[a.code] = v; source[a.code] = 'extracted'; }
    }
    const miss = defs.filter((a) => a.mandatory && !spec[a.code]);
    if (lt) lineTrades.add(lt);
    for (const a of miss) missing.push(lineItem(l, a));
    lines.push({ line_no: l.line_no, description: l.description, trade: lt, material, spec, source, asked: defs.map((a) => a.code), missing: miss.map((a) => a.code), defs });
  }
  if (!lineTrades.size && !lines.some((x) => x.defs.length) && (TRADES[trade] || COMPOSITE.has(trade))) missing.unshift(termItem('line_items'));

  const ts = input.terms.terms_spec ?? {};
  // (1b) A component the customer named that no line names: asked of the quote as a whole.
  const components: Record<string, string | null> = {};
  for (const m of req?.materials ?? []) {
    if (!m?.component || m.component === 'main' || named.has(m.component)) continue;
    const v = ts.components?.[m.component]?.value ?? null;
    components[m.component] = v && !VAGUE.test(normText(v)) ? v : null;
    if (!components[m.component]) { const n = materialNames(m); missing.push(termItem(`component:${m.component}`, [`Material — ${n.en}`, `المادة — ${n.ar}`])); }
  }

  // (2) Delivery — every quote; the customer's required-by date is checked against it in the comparison.
  const dPortal = ts.delivery?.value ? readDelivery(ts.delivery.value) : null;
  const d = dPortal ?? readDelivery(input.terms.lead_time ?? '');
  const delivery: TermResult['delivery'] = { applies: true, value: d?.value ?? null, days: d?.days ?? null, date: d?.date ?? null, source: d ? (dPortal ? 'supplier_portal' : 'extracted') : null };
  if (!d) missing.push(termItem('delivery'));

  // (3) Installation — required unless the customer explicitly said it is not needed.
  const instApplies = customerRequires(req, 'installation');
  const iPortal = ts.installation?.included ? ts.installation : null;
  const iRead = iPortal ? { included: iPortal.included, detail: iPortal.detail ?? null } : readInstallation(input.lines, input.terms);
  const installation: TermResult['installation'] = { applies: instApplies, included: instApplies ? iRead.included : null, detail: instApplies ? iRead.detail : null, source: instApplies && iRead.included ? (iPortal ? 'supplier_portal' : 'extracted') : null };
  if (instApplies) {
    if (!iRead.included) missing.push(termItem('installation_included'));
    else if (iRead.included === 'yes' && !(iRead.detail && !VAGUE.test(normText(iRead.detail)))) missing.push(termItem('installation_detail'));
  }

  // (4) Warranty — required unless the customer explicitly said it is not needed.
  const warrantyText = `${input.terms.warranty ?? ''} ${input.lines.filter((l) => /warrant|guarant|ضمان/i.test(lineText(l))).map(lineText).join(' ')}`;
  const wApplies = customerRequires(req, 'warranty');
  const wPortal = ts.warranty?.period ? ts.warranty : null;
  const wRead = wPortal ? { ...readWarranty(wPortal.period), coverage: wPortal.coverage } : readWarranty(warrantyText);
  const warranty: TermResult['warranty'] = { applies: wApplies, period: wApplies ? wRead.period : null, months: wApplies ? wRead.months : null, coverage: wApplies ? wRead.coverage : null, source: wApplies && wRead.period ? (wPortal ? 'supplier_portal' : 'extracted') : null };
  if (wApplies) {
    if (!wRead.period) missing.push(termItem('warranty_period'));
    if (!(wRead.coverage && !VAGUE.test(normText(wRead.coverage)))) missing.push(termItem('warranty_coverage'));
  }

  // (5) The price excluding VAT. Missing or ambiguous is held.
  if (!(Number(input.terms.price_ex_vat) > 0)) missing.push(termItem('price_ex_vat'));

  return { trade, held: missing.length > 0, lines, terms: { delivery, installation, warranty, components }, missing };
}

// ---------------------------------------------------------------------------------------------
// Portal fill-in validation. The same readers decide, so a value the portal accepts is a value the
// hold gate accepts.
// ---------------------------------------------------------------------------------------------
export type FillError = { scope: 'line' | 'quote'; line_no: number | null; attr: string; code: 'vague' | 'not_a_number' | 'not_concrete' | 'choose_yes_or_no' | 'unknown_attribute' | 'too_long' };
export function validateLineValue(a: Attr, raw: unknown): { ok: true; value: string } | { ok: false; code: FillError['code'] } {
  const v = normText(String(raw ?? ''));
  if (!v || VAGUE.test(v) || v.length < 1) return { ok: false, code: 'vague' };
  if (v.length > 120) return { ok: false, code: 'too_long' };
  if (a.type === 'number') { const n = Number(v.replace(/[^\d.]/g, '')); if (!(n > 0) || !/\d/.test(v)) return { ok: false, code: 'not_a_number' }; return { ok: true, value: String(n) }; }
  if (v.length < 2) return { ok: false, code: 'vague' };
  return { ok: true, value: v };
}
export function validateTerm(attr: string, raw: unknown): { ok: true; value: string } | { ok: false; code: FillError['code'] } {
  const v = normText(String(raw ?? ''));
  if (attr === 'installation_included') return v === 'yes' || v === 'no' ? { ok: true, value: v } : { ok: false, code: 'choose_yes_or_no' };
  if (!v || VAGUE.test(v)) return { ok: false, code: 'vague' };
  if (v.length > 200) return { ok: false, code: 'too_long' };
  if (attr === 'price_ex_vat') { const n = Number(v.replace(/[^\d.]/g, '')); return n > 0 && /\d/.test(v) ? { ok: true, value: String(Math.round(n * 100) / 100) } : { ok: false, code: 'not_a_number' }; }
  if (attr === 'delivery') return readDelivery(v) ? { ok: true, value: v } : { ok: false, code: 'not_concrete' };
  if (attr === 'warranty_period') return readWarranty(v).period ? { ok: true, value: v } : { ok: false, code: 'not_concrete' };
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
