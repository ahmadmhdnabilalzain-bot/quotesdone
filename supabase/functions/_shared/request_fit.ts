// request_fit.ts — EACH QUOTE MEASURED AGAINST WHAT THE CUSTOMER ASKED FOR. Seat: sales_engineer. 15 Nov 2026.
//
// THE EVIDENCE (journey A of 15 Nov 2026, run 8288bec3, the comparison report the customer downloaded). He asked by chat for
// inverter wall splits (two 1.5 TR, two 2.0 TR), "Daikin, Mitsubishi Electric or Gree", R32 or R410A, supply and install,
// the old units removed, copper reused or up to 5 m new per unit, connection to his existing isolators, a service of the
// three 3 TR ducted units, done by 15 December 2026, and "at least 2 years on the installation and 5 years on the
// compressors". The report's "You asked for" column was "—" on every line; Supplier A was recommended first with
// "Completeness 5" and "All 30 match" while it gave 1 year of warranty; the brand the supplier quoted was generalised before
// anything compared it with his list, so the report could not say whether it was one he named; the reasons were generic
// and the scores rank-relative (5/3/1); service and removal lines showed a brand, a capacity "1" and a refrigerant.
//
// WHAT THIS IS. Pure functions, no I/O and no model:
//   requestRequirements(inquiry)  the customer's requirements from what the intake RECORDED (inquiries.spec: the four
//                                 keyed answers in customer_requirements, docs/contracts/intake_answers.md, and the trade
//                                 checklist's keyed answers), each with its label and "You asked for" in EN and AR;
//   fitQuote(reqs, quote)         one quote, from its RAW lines, against each requirement: meets / differs / not stated,
//                                 the hard requirements it fails, and what to clarify before the reveal. The brand is
//                                 compared with the customer's listed brands HERE, before anything is generalised, and
//                                 only "one of your listed brands: yes / no" and the brand's tier and origin leave;
//   annotateTechnical(...)        the report's line-by-line table: "You asked for" filled where the request states a
//                                 value, product attributes dropped from service / removal / piping lines, capacities in
//                                 one unit;
//   enforceFit(analysis, ...)     on ANY ranking (the model's or a cached one): a quote that fails a hard requirement is
//                                 never first while a quote that meets them all is shortlisted, and says plainly that it
//                                 fails.
//
// What the customer said is read from the keyed answers the intake model recorded (ledger 1663/1664: the model understands,
// code only checks). The one exception is raw_input, read only for the items of a service the customer listed (coils,
// filters, drain, gas), to check a quote's service line names them.
//
// Nothing here names a brand, a model or a supplier: the customer's listed brands are counted ("one of the 3 brands you
// named"), never printed, so the column beside "yes — premium Japanese brand" cannot narrow a quote to one make.
// Prevented by: _shared/request_fit.test.ts (journey A's three quotations, failing on main) and its PDF text snapshot.
import { brandFact, genericBrand, ORIGIN, TIER_RANK, tierOf, type Tier } from './quote_generalise.ts';
import { deliveryOf, warrantyPeriod } from './line_specs/assess.ts';
import { tradeOfCategory } from './line_specs/model.ts';
import { arDuration } from './quote_documents/arabic.ts';
import { isClosedRequest } from './request_closed.ts';
import { POINT_CODE } from './comparison_points.ts';

export type Bi = { en: string; ar: string };
export type FitStatus = 'meets' | 'differs' | 'not_stated';
export type Requirement = {
  code: string; hard: boolean; label: Bi; asked: Bi;
  brands?: string[]; tier?: Tier | null; refrigerants?: string[]; capacities?: { tr: number; qty: number }[];
  units?: number | null; tr?: number | null; subitems?: string[]; metres?: number | null; date?: string; months?: number; words?: string[];
  /** "Schneider or ABB or equivalent": a brand he did not name passes when it is an equivalent (same tier or better). */
  equivalent?: boolean;
  /** LEDGER 1588, DECIDED PER REQUEST (final review of 15 Nov 2026, FIX 2a): when the tier and origin of any brand on his
   *  list would name it (a list of one, or a tier and origin only one listed brand has), EVERY listed match says only "as
   *  you asked", so the hidden one cannot be found by elimination from the others. */
  hide_listed?: boolean;
};
/** A point the quote leaves open: what the customer reads (en / ar), and the same point put to the supplier, in English.
 *  `key` names it in the supplier's quotation conversation (quote_review_request.key); once the supplier has answered,
 *  `state` is 'answered' and `answer` carries his words as the customer may read them (pointAnswers). A point still open
 *  when the customer revealed a supplier or the request ended is 'closed': it was superseded and is asked no more. */
export type Ask = Bi & { supplier: string; key?: string; state?: 'asked' | 'answered' | 'closed'; answer?: string | null };
export type FitCell = { status: FitStatus; shown: Bi };
export type FitFail = { code: string; noun: Bi; detail: Bi };
export type QuoteFit = {
  cells: Record<string, FitCell>; met: number; total: number; score: number | null;
  hard_fails: FitFail[]; hard_open: { code: string; label: Bi }[]; asks: Ask[];
  /** hidden: the brand is one he named and saying its tier and origin would name it (ledger 1588), so generic is null. */
  brand: { listed: boolean | null; generic: Bi | null; hidden?: boolean }; meets_date: boolean | null;
};
export type RequestIn = { category?: string | null; summary?: string | null; raw_input?: unknown; spec?: unknown };
export type FitLine = { line_no?: number | null; line?: number | null; description?: string | null; brand?: string | null; model?: string | null; specification?: string | null; qty?: number | string | null; unit?: string | null; notes?: string | null; spec?: Record<string, unknown> | null };
export type FitQuote = { lead_time?: string | null; /** the lead time as the customer may read it (generalised), for the date cell */ lead_time_shown?: string | null; warranty?: string | null; scope?: string | null; exclusions?: string | null; conditions?: string | null; notes?: string | null;
  // deno-lint-ignore no-explicit-any
  terms_spec?: any };

const S = (v: unknown) => String(v ?? '').trim();
const num = (v: unknown): number | null => { const n = typeof v === 'number' ? v : Number(S(v).replace(/,/g, '').match(/-?\d+(?:\.\d+)?/)?.[0]); return Number.isFinite(n) ? n : null; };
const bi = (en: string, ar: string): Bi => ({ en, ar });
const trFmt = (n: number, ar = false) => `${Number.isInteger(n) ? n.toFixed(1) : String(Math.round(n * 100) / 100)} ${ar ? 'طن' : 'TR'}`;
const yearsEn = (m: number) => (m % 12 === 0 ? `${m / 12} year${m === 12 ? '' : 's'}` : `${m} month${m === 1 ? '' : 's'}`);
const yearsAr = (m: number) => { if (m % 12 !== 0) return `${m} ${m === 1 ? 'شهر' : m === 2 ? 'شهران' : m <= 10 ? 'أشهر' : 'شهرًا'}`; const y = m / 12; return y === 1 ? 'سنة واحدة' : y === 2 ? 'سنتان' : y <= 10 ? `${y} سنوات` : `${y} سنة`; };
const dateEn = (iso: string) => new Date(iso.slice(0, 10) + 'T00:00:00Z').toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
const dateAr = (iso: string) => new Date(iso.slice(0, 10) + 'T00:00:00Z').toLocaleDateString('ar-AE-u-nu-latn', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });

// ---------------------------------------------------------------------------------------------
// Lines: a product line carries product attributes; a service, removal, piping or testing line does not.
// ---------------------------------------------------------------------------------------------
const SERVICE_LINE = /\b(?:remov\w*|dispos\w*|dismantl\w*|demoli\w*|servic\w*|maintenance|clean\w*|testing|tests?\b|commission\w*|labou?r\s+only|transport\w*|mobili[sz]ation|survey\w*|inspection)\b|إزالة|فك\s|صيانة|تنظيف|اختبار|تشغيل\s+تجريبي/i;
const HVAC_UNIT = /\b(?:units?|split|splits|cassette|ducted|package|chiller|fahu|ahu|fcu|vrf|vrv|condens\w*|indoor|outdoor|air[- ]?condition\w*|a\/c|ac)\b|وحدة|مكيف|سبليت/i;
const NOT_A_UNIT = /\b(?:pipe|piping|copper|cable|cabling|ductwork|insulation|drain\s+line|bracket|stand)\b/i;
/** Does a line carry product attributes (brand, model, capacity, refrigerant)? A service or removal line never does. */
export function isProductLine(text: unknown, trade: string | null): boolean {
  const t = S(text);
  // "Supply, install, testing and commissioning of a 1.5 TR split" is still the product line; "Testing and commissioning" is not.
  if (!t || (SERVICE_LINE.test(t) && !/\bsupply\b|توريد/i.test(t))) return false;
  if (trade === 'hvac') return HVAC_UNIT.test(t) && !NOT_A_UNIT.test(t);
  return true;
}
/** The brands a quote's product lines name, RAW (compared with his list, then only their generic words leave). */
const quotedBrandsOf = (product: FitLine[]) => [...new Set(product.map((l) => { const raw = S(l.brand) || S((l.spec || {}).brand); return raw ? (brandFact(raw)?.name ?? raw) : brandsIn([l.description, l.specification].map(S).join(' '))[0] ?? ''; }).filter(Boolean))];
const lineText = (l: FitLine) => [l.description, l.brand, l.specification, l.notes, ...Object.entries(l.spec || {}).filter(([k]) => !k.startsWith('_')).map(([, v]) => S(v))].filter(Boolean).join(' · ');
/** The TR a text names ("1.5 TR", "2 ton", "24000 BTU"), or null. */
export function trOf(text: unknown): number | null {
  const t = S(text);
  const m = t.match(/(\d+(?:\.\d+)?)\s*(?:tr\b|tons?\b|طن)/i); if (m) return Number(m[1]);
  const b = t.match(/(\d{4,6})\s*btu/i); if (b) return Math.round((Number(b[1]) / 12000) * 2) / 2;
  return null;
}

// ---------------------------------------------------------------------------------------------
// Brands named in a text: every make the brand table knows, longest names first ("Mitsubishi Electric" before "Mitsubishi").
// ---------------------------------------------------------------------------------------------
export function brandsIn(text: unknown): string[] {
  const words = S(text).split(/[^A-Za-z0-9&+.'À-ÿ-]+/).filter(Boolean);
  const out: string[] = []; const used = new Set<number>();
  for (let n = 3; n >= 1; n--) for (let i = 0; i + n <= words.length; i++) {
    if ([...Array(n).keys()].some((k) => used.has(i + k))) continue;
    const cand = words.slice(i, i + n).join(' ');
    if (!/^[A-Z0-9]/.test(cand)) continue;
    const f = brandFact(cand);
    if (f && !f.plain && f.name.toLowerCase() === cand.toLowerCase()) { if (!out.includes(f.name)) out.push(f.name); for (let k = 0; k < n; k++) used.add(i + k); }
  }
  return out;
}
const refrigerantsIn = (text: unknown) => [...new Set([...S(text).matchAll(/\bR[- ]?(\d{2,3}[A-Z]?)\b/gi)].map((m) => 'R' + m[1].toUpperCase()))];

// ---------------------------------------------------------------------------------------------
// The request.
// ---------------------------------------------------------------------------------------------
const INTERNAL = new Set(['customer_requirements', 'boq_check', 'site_location', 'old_supplier_terms', 'site_keys', 'service_keys', 'trade_codes', 'checklist_topics', 'provenance', 'spec_evidence']);
// WHAT IS NOT HIS REQUIREMENT FOR WHAT THE SUPPLIER SUPPLIES (independent review of 15 Nov 2026, item 3, against the live
// trade_spec_checklist keys): "spec_existing_make: Otis" is the lift he has, "spec_vehicle_make_model_and_year: Toyota" the car
// a part is for, "existing_warranty: ended 3 years ago" a fact about the old installation, and a survey key what a visit found.
// None is read as a requirement. Nor is an answer that puts a thing out of scope ("Inverter not in scope", "No").
const NOT_A_REQUEST_KEY = /(?:^|_)(?:existing|current|present|previous|vehicle|survey|surveyed)(?:_|$)/i;
const NEGATED = /\b(?:not\s+(?:in\s+(?:the\s+)?scope|needed|required|included|wanted|applicable|part\s+of)|out\s+of\s+scope|excluded|by\s+others|n\/a)\b|^\s*(?:no|none|nil)\b|غير\s+مطلوب|خارج\s+النطاق|لا\s+يلزم/i;
function specValues(spec: unknown): [string, string][] {
  if (!spec || typeof spec !== 'object') return [];
  return Object.entries(spec as Record<string, unknown>).filter(([k, v]) => !INTERNAL.has(k) && !NOT_A_REQUEST_KEY.test(k) && (typeof v === 'string' || typeof v === 'number')).map(([k, v]) => [k, S(v)] as [string, string]).filter(([, v]) => v !== '' && !NEGATED.test(v));
}
const keyed = (vals: [string, string][], re: RegExp) => vals.filter(([k]) => re.test(k)).map(([, v]) => v);
// snake_case keys: a word is delimited by "_" or the ends, never matched inside another word ("makeup", "unmake").
const BRAND_KEY = /(?:^|_)(?:brands?|makes?|manufacturers?)(?:_|$)/i;
const OR_EQUIVALENT = /\bor\s+(?:an?\s+)?(?:approved\s+)?(?:equivalent|equal|similar)\b|\bor\s+equiv\b|أو\s+(?:ما\s+)?(?:يعادل|يعادلها|مكافئ)/i;
const SUBITEMS: { key: string; re: RegExp; en: string; ar: string }[] = [
  { key: 'coil', re: /\bcoils?\b/i, en: 'coils', ar: 'الملفات' },
  { key: 'filter', re: /\bfilters?\b/i, en: 'filters', ar: 'الفلاتر' },
  { key: 'drain', re: /\bdrain/i, en: 'drain', ar: 'خط التصريف' },
  { key: 'gas', re: /\bgas\b|\bpressure\b|refrigerant\s+(?:level|charge|check)/i, en: 'gas check', ar: 'فحص الغاز' },
];

/** The customer's requirements, from what the intake recorded on the inquiry. Empty when nothing was recorded. */
export function requestRequirements(inq: RequestIn): Requirement[] {
  const spec = (inq?.spec && typeof inq.spec === 'object' ? inq.spec : {}) as Record<string, unknown>;
  // deno-lint-ignore no-explicit-any
  const cr: any = spec.customer_requirements && typeof spec.customer_requirements === 'object' ? spec.customer_requirements : {};
  const vals = specValues(spec);
  // The HVAC readers (inverter, refrigerant, TR capacities, removal of the old units, the ducted service, copper, isolators)
  // read HVAC checklist keys. In another trade the same words name something else ("waste removal" on a demolition, the pipe
  // material of a fire-fighting job, "capacity: 200 Ah" of a battery), so they run on an HVAC request only.
  const hvac = tradeOfCategory(inq?.category ?? null) === 'hvac';
  const out: Requirement[] = [];

  // BRANDS: every make the customer named (the trade checklist's brand answer, or a material answer in his own words).
  const brandVals = [...keyed(vals, BRAND_KEY), ...((cr.materials || []) as { component?: string; choice?: string; note?: string }[])
    .filter((m) => /brand/i.test(S(m?.component)) && m?.choice === 'other' && !NEGATED.test(S(m.note))).map((m) => S(m.note))];
  const brandText = brandVals.join(' · ');
  const brands = brandsIn(brandText);
  // "Schneider or ABB or equivalent": a list he is open to beyond, so an equivalent brand passes and none fails hard.
  const equivalent = OR_EQUIVALENT.test(brandText);
  // deno-lint-ignore no-explicit-any
  const tierAnswer: any = ((cr.materials || []) as any[]).find((m) => /brand/i.test(S(m?.component)) && ['premium', 'mid', 'economy'].includes(S(m?.choice)));
  if (brands.length) {
    // Would a listed brand's tier and origin name it? Then no listed match says its tier or origin (hide_listed).
    const gen = (b: string) => genericBrand(b).en;
    const hide_listed = brands.length === 1 || brands.some((b) => brands.filter((x) => gen(x) === gen(b)).length === 1);
    out.push({ code: 'brand_list', hard: !equivalent, equivalent, hide_listed, label: bi('Brand', 'العلامة التجارية'), brands,
      asked: equivalent
        ? (brands.length === 1 ? bi('The brand you named, or an equivalent', 'العلامة التي سمّيتها أو ما يعادلها') : bi(`One of the ${brands.length} brands you named, or an equivalent`, `إحدى العلامات الـ${brands.length} التي سمّيتها أو ما يعادلها`))
        : (brands.length === 1 ? bi('The brand you named', 'العلامة التي سمّيتها') : bi(`One of the ${brands.length} brands you named`, `إحدى العلامات الـ${brands.length} التي سمّيتها`)) });
  } else if (tierAnswer) {
    const tier: Tier = tierAnswer.choice === 'mid' ? 'mid-range' : tierAnswer.choice;
    out.push({ code: 'brand_tier', hard: false, label: bi('Brand tier', 'فئة العلامة التجارية'), tier, asked: bi(S(tierAnswer.choice_en) || tier, S(tierAnswer.choice_ar) || tier) });
  }

  // PRODUCT (HVAC): inverter, refrigerant, units and capacity.
  const capacities: { tr: number; qty: number }[] = []; let serviceTr: number | null = null;
  if (hvac) {
    const inv = keyed(vals, /inverter/i).join(' ');
    if (/inverter|إنفرتر|انفرتر/i.test(inv) && !/fixed|non[- ]?inverter|ثابت/i.test(inv)) out.push({ code: 'inverter', hard: true, label: bi('Inverter units', 'وحدات إنفرتر'), asked: bi('Inverter', 'إنفرتر') });
    const refrigerants = refrigerantsIn(keyed(vals, /refrigerant/i).join(' '));
    if (refrigerants.length) out.push({ code: 'refrigerant', hard: true, label: bi('Refrigerant', 'غاز التبريد'), refrigerants, asked: bi(refrigerants.join(' or '), refrigerants.join(' أو ')) });
    const capText = keyed(vals, /capacity/i).join(' ; ');
    for (const seg of capText.split(/[;\n]+/)) {
      const service = /duct|servic|صيانة/i.test(seg);
      for (const m of seg.matchAll(/(\d+)\s*[x×]\s*(\d+(?:\.\d+)?)\s*(?:tr|tons?|طن)/gi)) {
        if (service) { serviceTr = Number(m[2]); continue; }
        const tr = Number(m[2]); const c = capacities.find((x) => x.tr === tr); if (c) c.qty += Number(m[1]); else capacities.push({ tr, qty: Number(m[1]) });
      }
    }
    if (capacities.length) {
      out.push({ code: 'capacity', hard: true, label: bi('Units and capacity', 'عدد الوحدات وقدرتها'), capacities,
        asked: bi(capacities.map((c) => `${c.qty} × ${trFmt(c.tr)}`).join(' and '), capacities.map((c) => `${c.qty} × ${trFmt(c.tr, true)}`).join(' و')) });
    }
  }
  const splitUnits = capacities.length ? capacities.reduce((s, c) => s + c.qty, 0) : hvac ? num(keyed(vals, /split_unit_count/i)[0]) : null;

  // SCOPE: supply and installation (any trade, from the keyed answer); for HVAC the removal of the old units, the service
  // of existing units, copper and isolators.
  if (S(cr.installation?.required) === 'yes' || cr.installation?.required === true) out.push({ code: 'installation', hard: true, label: bi('Supply and installation', 'التوريد والتركيب'), asked: bi('Supply and install', 'توريد وتركيب') });
  if (hvac) {
    // The old units he replaces, never "waste removal" or debris (a key about waste is not about his old units).
    const removal = vals.filter(([k]) => /removal|remove|dispos/i.test(k) && !/waste|debris|rubble|garbage|trash/i.test(k)).map(([, v]) => v).join(' ');
    if (removal) {
      out.push({ code: 'removal', hard: true, label: bi('Remove and dispose of the old units', 'فك الوحدات القديمة والتخلص منها'), units: splitUnits ?? null,
        asked: splitUnits ? bi(`All ${splitUnits} old units`, `جميع الوحدات القديمة (${splitUnits})`) : bi('Yes', 'نعم') });
    }
    const ductedCount = num(keyed(vals, /ducted_unit_count/i)[0]);
    const serviceAsked = [inq?.summary, ...vals.map(([, v]) => v)].map(S).some((t) => /duct/i.test(t) && /servic/i.test(t));
    if (serviceAsked) {
      const own = [inq?.summary, typeof inq?.raw_input === 'string' ? inq.raw_input : '', ...vals.map(([, v]) => v)].map(S).join(' ');
      const subitems = SUBITEMS.filter((s) => s.re.test(own)).map((s) => s.key);
      const items = SUBITEMS.filter((s) => subitems.includes(s.key));
      const head = (ar: boolean) => [ductedCount ? (ar ? `${ductedCount} وحدات` : `${ductedCount} units`) : '', serviceTr ? `(${trFmt(serviceTr, ar)})` : ''].filter(Boolean).join(' ');
      out.push({ code: 'ducted_service', hard: true, label: bi('Service of the ducted units', 'صيانة وحدات الدكت'), units: ductedCount, tr: serviceTr, subitems,
        asked: bi([head(false), items.map((s) => s.en).join(', ')].filter(Boolean).join(': ') || 'Yes', [head(true), items.map((s) => s.ar).join('، ')].filter(Boolean).join(': ') || 'نعم') });
    }
    const copper = keyed(vals, /copper/i).join(' ');
    if (copper) {
      const per = num(copper.match(/(\d+(?:\.\d+)?)\s*(?:m\b|metres?|meters?|م\b)/i)?.[1]);
      const total = per && splitUnits ? per * splitUnits : null;
      out.push({ code: 'copper', hard: false, label: bi('New copper pipe allowance', 'بدل أنابيب النحاس الجديدة'), metres: total,
        asked: per ? bi(`Reuse the existing, or up to ${per} m new per unit${total ? ` (${total} m)` : ''}`, `إعادة استخدام الحالية، أو حتى ${per} م جديدة لكل وحدة${total ? ` (${total} م)` : ''}`) : bi('As stated in your request', 'كما ورد في طلبك') });
    }
    const iso = keyed(vals, /isolator/i).join(' ');
    if (/isolator|power point|connect/i.test(iso)) out.push({ code: 'isolator', hard: false, label: bi('Connection to your existing isolators', 'التوصيل بمفاتيح العزل الموجودة'), asked: bi('Connect only; the isolators are in place', 'توصيل فقط؛ المفاتيح موجودة') });
  }

  // DATE and WARRANTY.
  const rb = cr.required_by;
  if (rb && !rb.flexible && /^\d{4}-\d{2}-\d{2}/.test(S(rb.date))) out.push({ code: 'date', hard: true, label: bi('Done by your date', 'الإنجاز بحلول موعدك'), date: S(rb.date).slice(0, 10), asked: bi(`By ${dateEn(S(rb.date))}`, `بحلول ${dateAr(S(rb.date))}`) });
  const wSpec = warrantyParts(keyed(vals, /warrant/i).join(' ; '));
  const minM = Number(cr.warranty?.min_months) > 0 ? Number(cr.warranty.min_months) : null;
  const instM = wSpec.install ?? (S(cr.warranty?.required) === 'yes' ? minM : null);
  if (instM) out.push({ code: 'warranty_installation', hard: true, label: bi(wSpec.compressor ? 'Installation warranty' : 'Warranty', wSpec.compressor ? 'ضمان التركيب' : 'الضمان'), months: instM, asked: bi(`At least ${yearsEn(instM)}`, `${yearsAr(instM)} على الأقل`) });
  if (wSpec.compressor) out.push({ code: 'warranty_compressor', hard: true, label: bi('Compressor warranty', 'ضمان الضاغط'), months: wSpec.compressor, asked: bi(`At least ${yearsEn(wSpec.compressor)}`, `${yearsAr(wSpec.compressor)} على الأقل`) });

  // MATERIALS the customer chose (other than the brand tier, above): shown beside what each quote states.
  for (const m of (cr.materials || []) as { component?: string; label_en?: string; label_ar?: string; choice?: string; choice_en?: string; choice_ar?: string; note?: string }[]) {
    const choice = S(m?.choice);
    if (!m?.component || /brand/i.test(S(m.component)) || !choice || choice === 'no_preference' || choice === 'not_needed') continue;
    const en = choice === 'other' ? S(m.note) : S(m.choice_en) || choice;
    const words = [...en.matchAll(/\(([A-Z]{2,})\)|\b([A-Za-z]{5,})\b/g)].map((x) => (x[1] || x[2]).toLowerCase()).filter((w) => !['other', 'steel', 'panel'].includes(w));
    if (!en || !words.length) continue;
    out.push({ code: `material.${m.component}`, hard: false, label: bi(S(m.label_en) || m.component, S(m.label_ar) || S(m.label_en) || m.component), words, asked: bi(en, S(m.choice_ar) || en) });
  }
  return out;
}

/** "2 years installation, 5 years compressor" / "5 years on compressors; 2 years on the installation" / "1 year". */
export function warrantyParts(text: unknown): { install: number | null; compressor: number | null; general: number | null } {
  let install: number | null = null, compressor: number | null = null, general: number | null = null;
  for (const seg of S(text).split(/[;,\n—]+|\band\b/i).map((x) => x.trim()).filter(Boolean)) {
    const w = warrantyPeriod(seg); if (w.months == null) continue;
    if (/compressor|ضاغط|كمبروسر/i.test(seg)) compressor = Math.max(compressor ?? 0, w.months);
    else if (/install|workmanship|labou?r|complete|تركيب|مصنعية/i.test(seg)) install = install == null ? w.months : Math.min(install, w.months);
    else general = general == null ? w.months : Math.min(general, w.months);
  }
  // A bare period with nothing qualified ("2 years") is the whole job's warranty.
  if (install == null && compressor == null && general != null) install = general;
  return { install, compressor, general };
}

// ---------------------------------------------------------------------------------------------
// One quote against the requirements.
// ---------------------------------------------------------------------------------------------
const BRAND_AS_ASKED = bi('As you asked; the brand is shown after the reveal', 'كما طلبت؛ تظهر العلامة بعد الكشف');
const YES = bi('Yes', 'نعم'), NOT_STATED = bi('Not stated', 'غير مذكور'), NOT_IN = bi('Not in this quote', 'غير مشمول في هذا العرض');
const SUBJECT_TO_VISIT = /subject\s+to\s+(?:a\s+|the\s+)?site\s+(?:visit|survey|inspection)|after\s+(?:a\s+)?site\s+(?:visit|survey)|حسب\s+المعاينة|بعد\s+المعاينة/i;
const FIRM_PRICE = /\b(?:fixed|firm|final)\s+(?:lump[- ]sum\s+)?price\b|\bno\s+site\s+visit\s+(?:needed|required)\b|site\s+visit\s+(?:done|completed|carried\s+out)/i;

export function fitQuote(reqs: Requirement[], input: { quote: FitQuote; lines: FitLine[]; now: Date; trade?: string | null; site_visit?: boolean }): QuoteFit {
  const q = input.quote || {};
  const trade = input.trade ?? null;
  const lines = (input.lines || []).filter((l) => S(l.description) || S(l.brand) || S(l.specification));
  const product = lines.filter((l) => isProductLine(S(l.description) || S(l.specification), trade));
  const others = lines.filter((l) => !product.includes(l));
  const terms = [q.scope, q.notes, q.conditions].map(S).join(' ');
  const excl = S(q.exclusions);
  const all = [...lines.map(lineText), terms].join(' · ');
  const itemised = lines.length > 0;
  const cells: Record<string, FitCell> = {}; const asks: Ask[] = []; const fails: FitFail[] = [];
  const ask = (en: string, ar: string, supplier: string): Ask => ({ en, ar, supplier, key: pointKey(supplier) });
  let brand: QuoteFit['brand'] = { listed: null, generic: null }; let meetsDate: boolean | null = null;
  const set = (r: Requirement, status: FitStatus, shown: Bi, fail?: Bi) => { cells[r.code] = { status, shown }; if (status === 'differs' && r.hard) fails.push({ code: r.code, noun: lower(r.label), detail: fail ?? bi(`${shown.en}, against ${r.asked.en.toLowerCase()} you asked for`, `${shown.ar}، والمطلوب: ${r.asked.ar}`) }); };

  // The quoted brands, RAW, from the product lines: compared now, and only their generic words leave this function.
  const quotedBrands = quotedBrandsOf(product);
  if (quotedBrands.length) {
    const gens = quotedBrands.map((b) => genericBrand(b));
    brand.generic = bi([...new Set(gens.map((g) => g.en))].join(', '), [...new Set(gens.map((g) => g.ar))].join('، '));
  }
  for (const r of reqs) {
    switch (r.code) {
      case 'brand_list': {
        if (!quotedBrands.length) { set(r, 'not_stated', NOT_STATED); break; }
        const named = (b: string) => (r.brands || []).some((x) => x.toLowerCase() === b.toLowerCase());
        const listed = quotedBrands.every(named);
        if (listed) {
          // LEDGER 1588: NO BRAND REACHES THE CUSTOMER BEFORE THE REVEAL. "One of yours" plus the tier and origin names the make
          // whenever his list has only one brand, or only one listed brand of that tier and origin (journey A: Gree is his only
          // economy Chinese brand). Decided for the REQUEST, not this quote (final review, FIX 2a): when B and C read "premium
          // Japanese" and A reads "as you asked", A is Gree. So every listed match says only that the brand is as he asked.
          const identifies = !!r.hide_listed;
          if (identifies) brand.generic = null;
          brand = { ...brand, listed: true, hidden: identifies };
          set(r, 'meets', identifies ? BRAND_AS_ASKED : bi(`Yes: ${brand.generic!.en}`, `نعم: ${brand.generic!.ar}`));
          break;
        }
        brand = { ...brand, listed: false };
        if (r.equivalent) {
          // "or equivalent": a brand of the same tier as the least of those he named (or better) is an equivalent and passes;
          // one of a lower tier differs, softly (an "or equivalent" list is never a hard requirement).
          const floor = (r.brands || []).map((b) => genericBrand(b).tier).filter(Boolean).map((t) => TIER_RANK[t as Tier]);
          const tiers = quotedBrands.map((b) => genericBrand(b).tier);
          const lower = floor.length && tiers.some((t) => t != null && TIER_RANK[t] < Math.min(...floor));
          set(r, lower ? 'differs' : 'meets', bi(`${lower ? 'Lower tier' : 'An equivalent'}: ${brand.generic!.en}`, `${lower ? 'فئة أدنى' : 'ما يعادلها'}: ${brand.generic!.ar}`));
          break;
        }
        set(r, 'differs', bi(`No: ${brand.generic!.en}`, `لا: ${brand.generic!.ar}`),
          bi(`its brand (${brand.generic!.en}) is not one of those you named`, `علامته (${brand.generic!.ar}) ليست من العلامات التي سمّيتها`));
        break;
      }
      case 'brand_tier': {
        const tiers = quotedBrands.map((b) => genericBrand(b).tier).filter(Boolean) as Tier[];
        const t = tiers.length ? tiers.sort((a, b) => TIER_RANK[a] - TIER_RANK[b])[0] : tierOf(product.map(lineText).join(' '));
        if (!t || !r.tier) { set(r, 'not_stated', NOT_STATED); break; }
        set(r, TIER_RANK[t] >= TIER_RANK[r.tier] ? 'meets' : 'differs', brand.generic ?? bi(t, t));
        break;
      }
      case 'inverter': {
        const t = product.map(lineText).join(' ');
        if (/fixed[- ]speed|non[- ]?inverter|on\/off/i.test(t)) set(r, 'differs', bi('Fixed speed', 'سرعة ثابتة'), bi('it offers fixed-speed units', 'يعرض وحدات بسرعة ثابتة'));
        else if (/inverter|إنفرتر|انفرتر/i.test(t)) set(r, 'meets', YES);
        else set(r, 'not_stated', NOT_STATED);
        break;
      }
      case 'refrigerant': {
        const got = [...new Set(product.flatMap((l) => refrigerantsIn([S((l.spec || {}).refrigerant), lineText(l)].join(' '))))];
        if (!got.length) { set(r, 'not_stated', NOT_STATED); break; }
        const ok = got.every((g) => (r.refrigerants || []).includes(g));
        set(r, ok ? 'meets' : 'differs', bi(got.join(', '), got.join('، ')), bi(`it uses ${got.join(', ')}, not ${r.asked.en}`, `يستخدم ${got.join('، ')} وليس ${r.asked.ar}`));
        break;
      }
      case 'capacity': {
        const byTr = new Map<number, number>();
        for (const l of product) { const tr = num((l.spec || {}).capacity_tr) ?? trOf([l.description, l.specification, S((l.spec || {}).capacity)].map(S).join(' ')); if (tr == null) continue; byTr.set(tr, (byTr.get(tr) ?? 0) + (num(l.qty) ?? 1)); }
        if (!byTr.size) { set(r, 'not_stated', NOT_STATED); break; }
        const shown = bi([...byTr].sort((a, b) => a[0] - b[0]).map(([tr, n]) => `${n} × ${trFmt(tr)}`).join(', '), [...byTr].sort((a, b) => a[0] - b[0]).map(([tr, n]) => `${n} × ${trFmt(tr, true)}`).join('، '));
        const ok = (r.capacities || []).every((c) => (byTr.get(c.tr) ?? 0) >= c.qty);
        set(r, ok ? 'meets' : 'differs', shown, bi(`it prices ${shown.en}; you asked for ${r.asked.en}`, `يسعّر ${shown.ar}؛ وطلبت ${r.asked.ar}`));
        break;
      }
      case 'installation': {
        const k = S(q.terms_spec?.installation?.included);
        if (k === 'no' || /\bsupply\s+only\b|توريد\s+فقط/i.test(terms) || /install(?:ation)?\s*(?:is\s*)?(?:not\s+included|excluded|by\s+others)/i.test(excl)) set(r, 'differs', bi('Supply only', 'توريد فقط'), bi('it is for supply only', 'هو للتوريد فقط'));
        else if (k === 'yes' || product.some((l) => /install|تركيب/i.test(lineText(l))) || /install|تركيب/i.test(terms)) set(r, 'meets', YES);
        else set(r, 'not_stated', NOT_STATED);
        break;
      }
      case 'removal': {
        const l = others.find((x) => /remov|dispos|dismantl|take\s+away|إزالة|فك/i.test(lineText(x)));
        if (l) { const n = num(l.qty); if (r.units && n != null && n < r.units) set(r, 'differs', bi(`${n} of ${r.units} units`, `${n} من ${r.units} وحدات`), bi(`it removes ${n} of the ${r.units} old units`, `يزيل ${n} من أصل ${r.units} وحدات قديمة`)); else set(r, 'meets', bi(`Yes${n != null ? `: ${n} units` : ''}`, `نعم${n != null ? `: ${n} وحدات` : ''}`)); }
        else if (/remov|dispos/i.test(excl)) set(r, 'differs', bi('Excluded', 'مستثنى'), bi('it excludes the removal of the old units', 'يستثني فك الوحدات القديمة'));
        else if (/remov|dispos/i.test(terms)) set(r, 'meets', YES);
        else set(r, itemised ? 'differs' : 'not_stated', itemised ? NOT_IN : NOT_STATED, bi('it does not price the removal of the old units', 'لا يسعّر فك الوحدات القديمة'));
        break;
      }
      case 'ducted_service': {
        const l = others.find((x) => /duct/i.test(lineText(x)) && /servic|maint|clean|صيانة|تنظيف/i.test(lineText(x)));
        if (!l) { set(r, itemised ? 'differs' : 'not_stated', itemised ? NOT_IN : NOT_STATED, bi('it does not price the service of your ducted units', 'لا يسعّر صيانة وحدات الدكت')); break; }
        const n = num(l.qty);
        if (r.units && n != null && n < r.units) { set(r, 'differs', bi(`${n} of ${r.units} units`, `${n} من ${r.units} وحدات`), bi(`it services ${n} of your ${r.units} ducted units`, `يشمل صيانة ${n} من أصل ${r.units} وحدات دكت`)); break; }
        const missing = SUBITEMS.filter((s) => (r.subitems || []).includes(s.key) && !s.re.test(lineText(l)));
        if (missing.length) {
          set(r, 'not_stated', bi(`Priced; it does not mention the ${missing.map((s) => s.en).join(', ')}`, `مسعّرة؛ لا تذكر ${missing.map((s) => s.ar).join('، ')}`));
          asks.push(ask(`Does the service of the ducted units include the ${missing.map((s) => s.en).join(' and ')}? You asked for them; the quote does not name them.`, `هل تشمل صيانة وحدات الدكت ${missing.map((s) => s.ar).join(' و')}؟ طلبتها ولا يذكرها العرض.`,
            `The customer asked for the service of the ducted units to include the ${missing.map((s) => s.en).join(' and ')}. Please confirm whether your price includes them.`));
        } else set(r, 'meets', bi(`Yes${n != null ? `: ${n} units` : ''}${r.subitems?.length ? ', every item you listed' : ''}`, `نعم${n != null ? `: ${n} وحدات` : ''}${r.subitems?.length ? '، وكل ما ذكرته' : ''}`));
        break;
      }
      case 'copper': {
        const l = others.find((x) => /copper|pipe|piping|نحاس|أنابيب/i.test(lineText(x)));
        const m = l ? num(l.qty) : null;
        if (!l) { set(r, 'not_stated', NOT_STATED); asks.push(ask(`Is new copper pipe included if the existing pipe cannot be reused? You allowed ${r.metres ? `up to ${r.metres} m` : 'for it'}.`, `هل تشمل الأسعار أنابيب نحاس جديدة إذا تعذّر استخدام الحالية؟ سمحت ${r.metres ? `بحتى ${r.metres} م` : 'بذلك'}.`,
          `The customer allows new copper pipe where the existing cannot be reused${r.metres ? ` (up to ${r.metres} m)` : ''}. Please confirm whether your price includes it, and the rate per further metre.`)); }
        else if (r.metres && m != null && m < r.metres) { set(r, 'differs', bi(`${m} m priced`, `${m} م مسعّرة`)); asks.push(ask(`It prices ${m} m of new copper pipe; you allowed up to ${r.metres} m. What does each further metre cost?`, `يسعّر ${m} م من أنابيب النحاس الجديدة، وسمحت بحتى ${r.metres} م. ما تكلفة كل متر إضافي؟`,
          `Your quotation prices ${m} m of new copper pipe; the customer allows up to ${r.metres} m. Please state the rate per further metre.`)); }
        else set(r, 'meets', bi(m != null ? `${m} m priced` : 'Priced', m != null ? `${m} م مسعّرة` : 'مسعّرة'));
        break;
      }
      case 'isolator': {
        if (/isolator|existing\s+power|connect\w*\s+to/i.test(all)) set(r, 'meets', YES);
        else if (/electric/i.test(excl)) { set(r, 'not_stated', bi('Unclear: it excludes electrical works', 'غير واضح: يستثني الأعمال الكهربائية')); asks.push(ask('It excludes electrical works. Is connecting the new units to your existing isolators included?', 'يستثني العرض الأعمال الكهربائية. هل يشمل توصيل الوحدات الجديدة بمفاتيح العزل الموجودة؟',
          'Your quotation excludes electrical works. The customer\'s isolators are in place; please confirm whether connecting the new units to them is included.')); }
        else set(r, 'not_stated', NOT_STATED);
        break;
      }
      case 'date': {
        const lead = S(q.terms_spec?.delivery?.value) || S(q.lead_time);
        const d = lead ? deliveryOf(lead) : null;
        const at = d?.days != null ? new Date(input.now.getTime() + d.days * 864e5) : d?.date ? new Date(d.date) : null;
        if (!at || isNaN(at.getTime())) { set(r, 'not_stated', NOT_STATED); meetsDate = null; asks.push(ask(`When will the work be done? You need it by ${dateEn(r.date!)}.`, `متى يُنجز العمل؟ تحتاجه بحلول ${dateAr(r.date!)}.`,
          `The customer needs the work done by ${dateEn(r.date!)}. Please state your lead time.`)); break; }
        meetsDate = at.getTime() <= new Date(r.date! + 'T00:00:00Z').getTime() + 864e5;
        // THE CELL CARRIES THE GENERALISED LEAD TIME (review item 8): the raw text can name a brand, a stock location or the
        // supplier ("10 days, Daikin stock at ... warehouse"), and this cell reaches the model's payload. With no generalised
        // text the cell says only the days; in Arabic it is Arabic ("5 أيام"), never the English words.
        const shownEn = S(q.lead_time_shown) || (d?.days != null ? `${d.days} day${d.days === 1 ? '' : 's'}` : d?.date ? dateEn(d.date) : '');
        const shownAr = arDuration(S(q.lead_time_shown)) ?? (d?.days != null ? arDuration(`${d.days} days`) : d?.date ? dateAr(d.date) : null) ?? '';
        set(r, meetsDate ? 'meets' : 'differs', bi(`${meetsDate ? 'Yes' : 'No'}${shownEn ? `: ${shownEn}` : ''}`, `${meetsDate ? 'نعم' : 'لا'}${shownAr ? `: ${shownAr}` : ''}`), bi(`it would finish around ${dateEn(at.toISOString())}, after your date of ${dateEn(r.date!)}`, `سينتهي نحو ${dateAr(at.toISOString())}، بعد موعدك ${dateAr(r.date!)}`));
        break;
      }
      case 'warranty_installation':
      case 'warranty_compressor': {
        const w = warrantyParts([S(q.terms_spec?.warranty?.period), S(q.terms_spec?.warranty?.coverage), S(q.warranty)].filter(Boolean).join(' ; '));
        const got = r.code === 'warranty_compressor' ? w.compressor : w.install;
        if (got == null) { set(r, 'not_stated', NOT_STATED); if (r.code === 'warranty_compressor') asks.push(ask(`What warranty does it give on the compressors? You asked for at least ${yearsEn(r.months!)}; the quote does not say.`, `ما مدة ضمان الضواغط؟ طلبت ${yearsAr(r.months!)} على الأقل، ولا يذكرها العرض.`,
          `The customer asked for at least ${yearsEn(r.months!)} of warranty on the compressors. Please state your compressor warranty.`)); break; }
        const ok = got >= r.months!;
        set(r, ok ? 'meets' : 'differs', bi(yearsEn(got), yearsAr(got)), bi(`${yearsEn(got)} against the ${yearsEn(r.months!)} you asked for`, `${yearsAr(got)}، والمطلوب ${yearsAr(r.months!)} على الأقل`));
        break;
      }
      default: {
        if (r.code.startsWith('material.')) { const hit = (r.words || []).some((w) => new RegExp(`\\b${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i').test(all)); set(r, hit ? 'meets' : 'not_stated', hit ? YES : NOT_STATED); }
      }
    }
  }
  // WHAT THE QUOTE LEAVES OPEN ON PRICE: a site visit the request names, or one the quote makes its price subject to.
  if (SUBJECT_TO_VISIT.test([terms, excl].join(' '))) asks.unshift(ask('The price is subject to a site visit. What could change it after the visit?', 'السعر مشروط بمعاينة الموقع. ما الذي قد يغيّره بعد المعاينة؟',
    'Your price is subject to a site visit. Please state what could change it after the visit.'));
  else if (input.site_visit && !FIRM_PRICE.test(terms)) asks.unshift(ask('Is this price final, or subject to the site visit your request mentions?', 'هل هذا السعر نهائي، أم مشروط بمعاينة الموقع التي ذكرها طلبك؟',
    'The request names a site visit before a final price. Please confirm whether your price is final or subject to that visit.'));

  const total = Object.keys(cells).length;
  const met = Object.values(cells).filter((c) => c.status === 'meets').length;
  const credit = Object.values(cells).reduce((s, c) => s + (c.status === 'meets' ? 1 : c.status === 'not_stated' ? 0.5 : 0), 0);
  const hardOpen = reqs.filter((r) => r.hard && cells[r.code]?.status === 'not_stated').map((r) => ({ code: r.code, label: r.label }));
  return { cells, met, total, score: total ? Math.round((5 * credit / total) * 10) / 10 : null, hard_fails: fails, hard_open: hardOpen, asks: asks.slice(0, 5), brand, meets_date: meetsDate };
}
const lower = (b: Bi): Bi => ({ en: b.en.charAt(0).toLowerCase() + b.en.slice(1), ar: b.ar });
/** Whether the request names a site visit before a final price (the trade checklist's site-visit answer). */
export function siteVisitAsked(spec: unknown): boolean {
  // The checklist's site-visit answer only, and only when it says a visit is needed (a survey key is what a visit found).
  return specValues(spec).some(([k, v]) => /(?:^|_)site_visits?(?:_|$)/i.test(k) && /need|requir|\byes\b|before|must|مطلوب|يلزم|نعم/i.test(v));
}

// ---------------------------------------------------------------------------------------------
// The sentences the ranking writes with a fit.
// ---------------------------------------------------------------------------------------------
const aedEn = (n: number) => `AED ${n.toLocaleString('en-US', { maximumFractionDigits: 2 })}`;
const aedAr = (n: number) => `${n.toLocaleString('en-US', { maximumFractionDigits: 2 })} درهم`;
/** "fails your installation warranty: 1 year against the 2 years you asked for" (and the others, joined). */
export function failText(f: QuoteFit, lang: 'en' | 'ar'): string {
  const ar = lang === 'ar';
  return f.hard_fails.map((x) => (ar ? `${x.noun.ar}: ${x.detail.ar}` : `your ${x.noun.en}: ${x.detail.en}`)).join(ar ? '؛ ' : '; ');
}
export function metText(f: QuoteFit, lang: 'en' | 'ar'): string {
  if (lang === 'ar') return f.met === f.total ? `يستوفي جميع متطلباتك الـ${f.total}` : `يستوفي ${f.met} من متطلباتك الـ${f.total}`;
  return f.met === f.total ? `it meets all ${f.total} of your requirements` : `it meets ${f.met} of your ${f.total} requirements`;
}
/** The recommendation, in one plain sentence of value and one of the trade-off with its price difference. */
export function recommendation(best: { label: string; price: number | null; fit: QuoteFit }, others: { label: string; price: number | null; fit: QuoteFit }[], lang: 'en' | 'ar'): { why: string; trade: string; bottom: string } {
  const ar = lang === 'ar'; const f = best.fit;
  if (f.hard_fails.length) {
    const why = ar ? `لا يستوفي أي عرض كل ما طلبته، وهذا أقربها: لا يستوفي ${failText(f, 'ar')}.` : `No quote meets everything you asked for; this one comes closest. It fails ${failText(f, 'en')}.`;
    return { why, trade: '', bottom: ar ? `لا يستوفي أي عرض كل ما طلبته. أقربها ${best.label}: لا يستوفي ${failText(f, 'ar')}.` : `No quote meets everything you asked for. ${best.label} comes closest: it fails ${failText(f, 'en')}.` };
  }
  const cheaper = others.filter((o) => o.price != null && best.price != null && o.price < best.price).sort((a, b) => a.price! - b.price!);
  const failing = cheaper.find((o) => o.fit.hard_fails.length);
  // A hidden listed brand (ledger 1588) is still one of his: said without its tier and origin.
  const brandPart = f.brand.listed && f.brand.generic ? (ar ? `إحدى العلامات التي سمّيتها (${f.brand.generic.ar})، و` : `one of your listed brands (${f.brand.generic.en}), and `)
    : f.brand.listed && f.brand.hidden ? (ar ? 'إحدى العلامات التي سمّيتها، و' : 'one of your listed brands, and ') : '';
  // What the cheaper quote fails and this one meets is the reason to pay more: named as a strength.
  const strengths = failing ? failing.fit.hard_fails.filter((x) => f.cells[x.code]?.status === 'meets').map((x) => x.noun) : [];
  const incl = strengths.length ? (ar ? `، بما في ذلك ${strengths.map((x) => x.ar).join(' و')} كما طلبت` : `, including the ${strengths.map((x) => x.en).join(' and ')} you asked for`) : '';
  const value = ar ? `${brandPart}${metText(f, 'ar')}${incl}` : `${brandPart}${metText(f, 'en')}${incl}`;
  let trade = '';
  if (failing) {
    const d = Math.round((best.price! - failing.price!) * 100) / 100;
    trade = ar ? `سعره أعلى بمبلغ ${aedAr(d)} من ${failing.label}، الذي لا يستوفي ${failText(failing.fit, 'ar')}.` : `It costs ${aedEn(d)} more than ${failing.label}, which fails ${failText(failing.fit, 'en')}.`;
  } else if (cheaper.length) {
    const c = cheaper[0]; const d = Math.round((best.price! - c.price!) * 100) / 100;
    const open = c.fit.total - c.fit.met;
    trade = ar ? `سعره أعلى بمبلغ ${aedAr(d)} من ${c.label}، الذي يترك ${open} من متطلباتك دون تأكيد.` : `It costs ${aedEn(d)} more than ${c.label}, which leaves ${open} of your requirements unconfirmed.`;
  } else if (best.price != null) trade = ar ? 'وهو أيضًا الأقل سعرًا.' : 'It is also the lowest price.';
  const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
  // why: the value, in the recommendation's own row; trade: what it costs against the cheaper quote, shown as its catch.
  return { why: `${ar ? value : cap(value)}.`, trade, bottom: (ar ? `نوصي بـ${best.label}: ${value}. ${trade}` : `We recommend ${best.label}: ${value}. ${trade}`).trim() };
}

// ---------------------------------------------------------------------------------------------
// The report's technical table, with the request beside each quote.
// ---------------------------------------------------------------------------------------------
type RCell = { value?: string | null; flag: string; note?: string | null };
type RTech = { suppliers: string[]; lines: { line_no?: number | null; item: string; qty?: unknown; unit?: unknown; attributes: { key: string; label?: string | null; unit?: string | null; requested?: string | null; values: Record<string, RCell> }[] }[];
  terms?: Record<string, { applicable?: boolean | null; requested?: string | null; values: Record<string, RCell> } | null> | null; scope_lines_dropped?: number };
// Product attributes (brand, model, capacity, refrigerant, efficiency, origin) say what a PRODUCT is. On a service, removal,
// piping or testing line they do not apply; every other attribute of such a line (a cleaning method, the products used, the
// crew, a disposal route) is that line's specification and stays (review item 2: a cleaning job lost its whole table).
const PRODUCT_ATTR = /^(?:brand|make|model|capacity(?:_\w+)?|\w*_capacity|refrigerant|efficiency|esma\w*|origin|country(?:_of_origin)?|inverter)$/i;
export function annotateTechnical<T extends RTech>(t: T, reqs: Requirement[], fits: Record<string, QuoteFit>, trade: string | null, lang: 'en' | 'ar'): T {
  const ar = lang === 'ar';
  const hvac = trade === 'hvac';
  const by = new Map(reqs.map((r) => [r.code, r]));
  const brandReq = by.get('brand_list') ?? by.get('brand_tier'); const cap = by.get('capacity'); const ref = by.get('refrigerant');
  let dropped = 0;
  const lines = t.lines.map((l) => {
    const product = isProductLine(l.item, trade);
    // A capacity in tons of refrigeration is an HVAC reading only (review item 1: "20 litres" and "48 V, 200 Ah" printed as TR).
    const lineTr = hvac ? trOf(l.item) : null;
    // With no BOQ the row's title is the first quote's own line ("…; economy Chinese brand, made in China"), which reads as
    // what was asked. Where the request names this capacity, the row is titled by the request instead.
    const asked = product && cap && lineTr != null && l.line_no == null ? (cap.capacities || []).find((c) => c.tr === lineTr) : null;
    const item = asked ? (ar ? `وحدات ${trFmt(asked.tr, true)}: طلبت ${asked.qty}` : `${trFmt(asked.tr)} units: you asked for ${asked.qty}`) : l.item;
    const attributes = l.attributes
      // On a line that is not a product, a product attribute does not apply: dropped in HVAC always (his brand, capacity and
      // refrigerant are those of the new units), elsewhere unless his request states a value for it.
      .filter((at) => product || !PRODUCT_ATTR.test(at.key) || (!hvac && !!at.requested))
      .map((at) => {
        const values: Record<string, RCell> = { ...at.values }; let requested = at.requested ?? null;
        if (at.key === 'brand' && brandReq) {
          requested = brandReq.asked[lang];
          for (const s of Object.keys(values)) {
            const c = values[s]; const f = fits[s]; const ok = f?.cells[brandReq.code]?.status; if (c.flag === 'na' || !c.value) continue;
            // Ledger 1588: where the tier and origin would name the make he listed, the cell says only that it is as he asked.
            if (f?.brand.hidden) { values[s] = { ...c, value: BRAND_AS_ASKED[lang], flag: 'match', note: null }; continue; }
            values[s] = { ...c, flag: ok === 'meets' ? 'match' : ok === 'differs' ? 'differs' : c.flag, note: brandReq.code === 'brand_list' && ok ? (ok === 'meets' ? (brandReq.equivalent && f?.brand.listed === false ? (ar ? 'ما يعادل علاماتك' : 'an equivalent') : (ar ? 'من علاماتك' : 'one you named')) : (ar ? 'ليست من علاماتك' : 'not one you named')) : c.note ?? null };
          }
        }
        if (/^(?:origin|country(?:_of_origin)?)$/i.test(at.key)) {
          for (const s of Object.keys(values)) { const c = values[s]; if (fits[s]?.brand.hidden && c.flag !== 'na' && c.value) values[s] = { ...c, value: ar ? 'تظهر بعد الكشف' : 'Shown after the reveal', note: null }; }
        }
        if (hvac && (at.key === 'capacity_tr' || /capacity/i.test(at.key))) {
          const want = cap && lineTr != null && (cap.capacities || []).some((c) => c.tr === lineTr) ? lineTr : null;
          if (want != null) requested = trFmt(want, ar);
          // The value is read as TR only where it says so ("24000 BTU" is 2.0 TR, never "24000.0 TR"); a bare number is TR only
          // under the TR key itself. Anything else is left exactly as the supplier wrote it.
          for (const s of Object.keys(values)) { const c = values[s]; if (c.flag === 'na') continue; const n = trOf(c.value) ?? (at.key === 'capacity_tr' && /^\s*\d+(?:\.\d+)?\s*$/.test(S(c.value)) ? num(c.value) : null); if (n == null) continue; values[s] = { ...c, value: trFmt(n, ar), flag: want != null ? (n === want ? 'match' : 'differs') : c.flag }; }
        }
        if (at.key === 'refrigerant' && ref) {
          requested = ref.asked[lang];
          for (const s of Object.keys(values)) { const c = values[s]; const got = refrigerantsIn(c.value); if (c.flag === 'na' || !got.length) continue; values[s] = { ...c, flag: got.every((g) => (ref.refrigerants || []).includes(g)) ? 'match' : 'differs' }; }
        }
        return { ...at, requested, values };
      }).filter((at) => Object.values(at.values).some((c) => c.flag !== 'na'));
    if (!product && !attributes.length) { dropped++; return null; }
    return { ...l, item, attributes };
  }).filter((l): l is NonNullable<typeof l> => l !== null);
  const terms = t.terms ? { ...t.terms } : t.terms;
  if (terms?.warranty) { const ws = ['warranty_installation', 'warranty_compressor'].map((c) => by.get(c)).filter(Boolean) as Requirement[]; if (ws.length) terms.warranty = { ...terms.warranty, requested: ws.map((w) => (ws.length > 1 ? `${w.label[lang]}: ` : '') + w.asked[lang]).join(ar ? '؛ ' : '; ') }; }
  if (terms?.lead_time && by.get('date')) terms.lead_time = { ...terms.lead_time, requested: by.get('date')!.asked[lang] };
  return { ...t, lines, terms, scope_lines_dropped: dropped };
}

/** The request side as the analysis carries it: what was asked, quote by quote, with no raw brand anywhere. */
export function fitView(reqs: Requirement[], rows: { label: string; quote_id: string | null; fit: QuoteFit }[]) {
  return {
    requirements: reqs.map((r) => ({ code: r.code, hard: r.hard, label: r.label, asked: r.asked })),
    // the supplier's copy of each open point stays on the server (it goes to the sales engineer, who asks that supplier); the
    // customer reads his copy, whether it is still asked, and the supplier's answer once it came (pointAnswers)
    quotes: rows.map((x) => ({ label: x.label, quote_id: x.quote_id, ...x.fit, asks: x.fit.asks.map(({ en, ar, state, answer }) => ({ en, ar, state: state ?? 'asked', answer: answer ?? null })) })),
  };
}

/**
 * WHERE A QUOTE STANDS AGAINST WHAT HE ASKED FOR: 0 states that it meets every hard requirement; 1 fails none but leaves one or
 * more unstated (a lump sum that says nothing never outranks a quote that states it meets them); 2 fails one. The rules ranking
 * and enforceFit both order by it before anything else.
 */
export function fitTier(f: QuoteFit | null | undefined): number {
  if (!f) return 1;
  return f.hard_fails.length ? 2 : f.hard_open.length ? 1 : 0;
}
/** "Supplier A", "A", "supplier a", "Supplier A – Option 1", "المورّد A": one key, so a label the model wrote loosely still matches. */
export function labelKey(l: unknown): string {
  return S(l).toLowerCase().replace(/\bsupplier\b|المورّد|المورد/g, ' ').replace(/[^a-z0-9\u0600-\u06ff]+/g, ' ').trim();
}
type Ranked = { rank?: number; label: string; why?: string; tradeoff?: string };
/**
 * ON ANY RANKING (the model's, a cached one, the rules'): a shortlisted quote that fails a hard requirement says so in its
 * catch, and the first place goes to the best quote of the best tier (fitTier) among ALL the quotes measured, shortlisted by
 * the model or not (review item 5a). Labels are matched loosely (5b). When the first place changes, the model's prose that
 * named the old first (bottom line, best-value reason, advice, the first row's why) is replaced from the enforced order, never
 * prefixed (5c). `rules` is the rules ranking of the same quotes (deterministicCompare): it says which quote is best within a
 * tier and gives a pulled-in quote its row; `prices` gives the recommendation its price difference.
 */
// deno-lint-ignore no-explicit-any
export function enforceFit(a: any, fits: Record<string, QuoteFit>, lang: 'en' | 'ar', opts: { rules?: { top3?: Ranked[]; quotes?: { label: string }[] } | null; prices?: Record<string, number | null>; expired?: Record<string, boolean> } = {}): void {
  if (!a || !Array.isArray(a.top3) || !a.top3.length || !Object.keys(fits).length) return;
  const ar = lang === 'ar';
  const byKey = new Map(Object.keys(fits).map((l) => [labelKey(l), l]));
  // The model's labels, written back as ours ("A" -> "Supplier A"), so every later reader matches them exactly.
  for (const t of a.top3 as Ranked[]) { const l = t && byKey.get(labelKey(t.label)); if (l) t.label = l; }
  if (a.best_value_label != null) { const l = byKey.get(labelKey(a.best_value_label)); if (l) a.best_value_label = l; }
  for (const t of a.top3 as Ranked[]) {
    const f = t && fits[String(t.label)]; if (!f || !f.hard_fails.length) continue;
    const s = ar ? `لا يستوفي طلبك: ${failText(f, 'ar')}.` : `Fails ${failText(f, 'en')}.`;
    if (!String(t.tradeoff || '').includes(s)) t.tradeoff = [s, String(t.tradeoff || '').trim()].filter(Boolean).join(' ');
  }
  const first: Ranked = a.top3[0];
  // WHERE A QUOTE STANDS, in the rules ranking's own order of keys: priced before unpriced, live before expired, then fitTier.
  // A label we did not measure (a held quote, a label the model invented) stands as "not stated".
  const unpriced = (l: string) => (opts.prices && !(Number(opts.prices[l]) > 0) ? 1 : 0);
  const expired = (l: string) => (opts.expired?.[l] ? 1 : 0);
  const tierAt = (l: string) => (fits[l] ? fitTier(fits[l]) : 1);
  const standing = (l: string) => [unpriced(l), expired(l), tierAt(l)];
  const cmp = (x: string, y: string) => { const p = standing(x), q = standing(y); return p[0] - q[0] || p[1] - q[1] || p[2] - q[2]; };
  // Best within the same standing: the rules ranking's order (price and fit), then the model's own order, then the label.
  const rulesOrder = [...(opts.rules?.top3 || []).map((t) => t.label), ...(opts.rules?.quotes || []).map((q) => q.label)];
  const modelOrder = (a.top3 as Ranked[]).map((t) => t.label);
  const place = (l: string) => { const r = rulesOrder.indexOf(l); const m = modelOrder.indexOf(l); return [r < 0 ? 1e6 : r, m < 0 ? 1e6 : m]; };
  const candidates = Object.keys(fits).sort((x, y) => cmp(x, y) || place(x)[0] - place(y)[0] || place(x)[1] - place(y)[1] || x.localeCompare(y));
  const best = candidates[0];
  if (!best || cmp(best, String(first?.label)) >= 0) {
    // The first place stands; within the shortlist a better-standing quote still goes above a worse one (a stable sort).
    a.top3 = [...(a.top3 as Ranked[])].sort((x, y) => cmp(x.label, y.label)).map((t, i) => ({ ...t, rank: i + 1 }));
    return;
  }
  // The new order: the best quote first (its own row, or the rules ranking's row for it), then the rest by tier, keeping three.
  const rulesRow = (l: string) => (opts.rules?.top3 || []).find((t) => t.label === l);
  const head: Ranked = (a.top3 as Ranked[]).find((t) => t.label === best) ?? { ...(rulesRow(best) ?? { label: best, why: '', tradeoff: '' }) };
  const rest = (a.top3 as Ranked[]).filter((t) => t.label !== best).sort((x, y) => cmp(x.label, y.label));
  a.top3 = [head, ...rest].slice(0, 3).map((t, i) => ({ ...t, rank: i + 1 }));
  a.best_value_label = best;
  // THE PROSE FOLLOWS THE ORDER. The recommendation is written from the fits and prices; the old first is named by what it fails.
  const price = (l: string) => (opts.prices && opts.prices[l] != null ? Number(opts.prices[l]) : null);
  const rec = recommendation({ label: best, price: price(best), fit: fits[best] }, Object.keys(fits).filter((l) => l !== best).map((l) => ({ label: l, price: price(l), fit: fits[l] })), lang);
  const old = fits[String(first?.label)];
  const fl = String(first?.label ?? '');
  const why = old && old.hard_fails.length
    ? (ar ? `نضع ${best} أولًا: ${first.label} لا يستوفي ${failText(old, 'ar')}.` : `We place ${best} first: ${first.label} fails ${failText(old, 'en')}.`)
    : unpriced(fl) ? (ar ? `نضع ${best} أولًا: لا يذكر ${fl} سعرًا.` : `We place ${best} first: ${fl} states no price.`)
    : expired(fl) ? (ar ? `نضع ${best} أولًا: انتهت صلاحية عرض ${fl}.` : `We place ${best} first: ${fl}'s quote has expired.`)
    : (ar ? `نضع ${best} أولًا: يذكر كل ما طلبته بوضوح، و${first?.label} لا يذكر ${old ? old.hard_open.map((x) => x.label.ar).join('، ') : 'كل ما طلبته'}.` : `We place ${best} first: it states everything you asked for, and ${first?.label} does not state ${old ? old.hard_open.map((x) => x.label.en.toLowerCase()).join(', ') : 'all of it'}.`);
  a.bottom_line = `${why} ${rec.bottom}`.trim();
  a.top3[0] = { ...a.top3[0], why: rec.why, tradeoff: [rec.trade, ...(fits[best]?.hard_fails.length ? [ar ? `لا يستوفي طلبك: ${failText(fits[best], 'ar')}.` : `Fails ${failText(fits[best], 'en')}.`] : [])].filter(Boolean).join(' ') };
  a.best_value_reason = rec.why;
  // Once the customer revealed a supplier or the request ended, every open point was superseded (state 'closed'): nothing is
  // asked any more, so the page stops saying that it is (COMPARE4 gap 2).
  const allAsks = Object.values(fits).flatMap((f) => f?.asks ?? []);
  const stillAsking = !allAsks.length || allAsks.some((x) => x.state !== 'closed');
  a.advice = ar
    ? `رتّبنا العروض وفق ما طلبته: ${best} أولًا. تبقى العروض جميعها مدرجة، ولك أن تكشف أيًّا منها.` + (stillAsking ? ` تطلب QuotesDone من المورّد تأكيد النقاط التي يتركها عرضه مفتوحة، وتظهر إجابته هنا عند وصولها.` : '')
    : `We ranked the quotes on what you asked for: ${best} first. Every quote stays listed and you can reveal any of them.` + (stillAsking ? ` QuotesDone asks the supplier to confirm the points its quote leaves open, and shows the answer here once it arrives.` : '');
}


// ---------------------------------------------------------------------------------------------
// The open points, put to the supplier by QuotesDone, and his answers back.
// ---------------------------------------------------------------------------------------------
/** A point's key in the supplier's quotation conversation: one key per point, the same on every view. */
export function pointKey(supplier: string): string {
  return 'comparison:' + S(supplier).toLowerCase().replace(/[^a-z0-9]+/g, '_').slice(0, 80);
}
/** The code of a comparison point in quote_review_request; supplier_api keeps these out of its auto-close. */
export { POINT_CODE };
/** The hand-over kind (scripts/sql/the_comparison_hands_its_open_points_to_the_sales_engineer.sql). */
export const POINTS_HANDOFF = 'comparison.points';
/**
 * WHETHER THE POINTS MAY BE RAISED AT ALL (final review of 15 Nov 2026, FIX 1 iv): never once the customer has revealed a
 * supplier on this request, nor once the request is at an end (request_closed.ts) or a live deal ('revealed'). A customer or
 * an admin who opens the comparison afterwards raises nothing with the suppliers who lost.
 */
export function mayRaisePoints(inq: { status?: unknown } | null | undefined, revealed: boolean): boolean {
  const st = S(inq?.status);
  return !revealed && st !== 'revealed' && !isClosedRequest(st);
}
/**
 * THE OPEN POINTS GO TO THE SALES ENGINEER, NOT INTO THE SUPPLIER'S CONVERSATION (CEO, under founder ruling 1696; final
 * review FIX 1). Code never writes an engineer message (rulings 1195-1197, 1339): quote_compare files ONE hand-over per quote
 * through the estate's one door, public.fn_seat_handoff, which opens one per kind and subject (the quote) and never again.
 * Its handler records the points in the supplier's quotation conversation, in the same transaction, where the sales
 * engineer's model turns raise them and the supplier answers; a quote with no conversation stays on the seat's desk.
 * The payload carries the customer's copy of each point and the supplier's copy, in English (ruling 1008), and nothing that
 * names the customer. Returns the fn_seat_handoff arguments, or null when the quote leaves nothing open.
 */
export function pointsHandoff(fit: QuoteFit | null | undefined, q: { inquiry_id: string; quote_id: string; label: string }) {
  const points = [...new Map((fit?.asks || []).map((x) => [x.key ?? pointKey(x.supplier), x])).entries()]
    .map(([key, x]) => ({ key, supplier: x.supplier, en: x.en, ar: x.ar }));
  if (!points.length || !S(q?.quote_id) || !S(q?.inquiry_id)) return null;
  return {
    p_from: 'sales_engineer', p_to: 'sales_engineer', p_type: POINTS_HANDOFF, p_subject_table: 'quotes', p_subject_id: S(q.quote_id),
    p_payload: {
      inquiry_id: S(q.inquiry_id), quote_id: S(q.quote_id), label: S(q.label), points,
      summary: `${points.length} point(s) ${S(q.label)}'s quotation leaves open against the customer's request: ${points.map((p) => p.supplier).join(' ')}`.slice(0, 900),
      waiting_for: 'the supplier to answer these points in the quotation conversation; with no conversation, the sales engineer asks the supplier',
    },
  };
}
/**
 * HIS ANSWER COMES BACK INTO THE COMPARISON. `answers` is what the supplier's quotation conversation holds for each point
 * (quote_compare reads quote_review_request and the answering message on every view): an answered point carries the
 * supplier's answer as the customer may read it (generalised and scrubbed by the caller). A point not recorded yet is asked.
 */
export function withAnswers(fit: QuoteFit, answers: Record<string, { state: 'asked' | 'answered' | 'closed'; answer: string | null }>): QuoteFit {
  if (!fit?.asks?.length) return fit;
  return { ...fit, asks: fit.asks.map((x) => {
    const a = answers[x.key ?? pointKey(x.supplier)];
    if (a?.state === 'answered') return { ...x, state: 'answered' as const, answer: a.answer };
    // superseded at the decision (COMPARE4 gap 2): nothing is asked after the reveal or the end, and the page does not say it is
    if (a?.state === 'closed') return { ...x, state: 'closed' as const, answer: null };
    return { ...x, state: 'asked' as const, answer: null };
  }) };
}

// ---------------------------------------------------------------------------------------------
// Ledger 1588: a hidden listed brand is said nowhere, not to the model and not to the customer.
// ---------------------------------------------------------------------------------------------
export type HiddenPhrases = { en: string[]; ar: string[]; countries: { code: string | null; en: string; ar: string; adj: string; ar_adj: string }[] };
/** Other names a country goes by in a model's prose. */
const COUNTRY_ALIASES: Record<string, string[]> = { CN: ['PRC', "People's Republic of China", 'mainland China'], US: ['United States', 'America', 'U.S.A.', 'U.S.'], GB: ['United Kingdom', 'Britain', 'England'], KR: ['Korea'], AE: [], JP: ['Nippon'] };
/**
 * The words that would name a hidden listed brand: its generic phrase, and its country and nationality in both languages.
 * With per-request hiding every listed match is hidden, so the others' origins are here too ("non-Japanese" names Gree).
 */
export function hiddenBrandPhrases(fit: QuoteFit | null | undefined, lines: FitLine[], trade: string | null): HiddenPhrases {
  const out: HiddenPhrases = { en: [], ar: [], countries: [] };
  if (!fit?.brand.hidden) return out;
  const product = (lines || []).filter((l) => isProductLine(S(l.description) || S(l.specification), trade));
  for (const b of quotedBrandsOf(product)) {
    const g = genericBrand(b); out.en.push(g.en); out.ar.push(g.ar);
    const o = g.origin ? ORIGIN[g.origin] : null; if (o) out.countries.push({ code: g.origin, en: o.country, ar: o.ar_country, adj: o.en, ar_adj: o.ar });
  }
  return out;
}
const esc = (x: string) => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+');
const alt = (xs: string[]) => [...new Set(xs.filter(Boolean))].sort((x, y) => y.length - x.length).map(esc).join('|');
const AS_ASKED_EN = 'a brand as you asked (shown after the reveal)';
const AS_ASKED_AR = 'علامة كما طلبت (تظهر بعد الكشف)';
const ORIGIN_EN = 'origin shown after the reveal';
const ORIGIN_AR = 'المنشأ يظهر بعد الكشف';
const TIER_EN = '(?:premium|high[- ]end|top[- ]tier|luxury|mid[- ]?range|mid[- ]tier|middle[- ]tier|economy|economical|budget|entry[- ]level|low[- ]cost)';
const NOUN_EN = '(?:brands?|makes?|manufacturers?|units?|products?|equipment|compressors?|options?|choices?|systems?|models?)';
const LEAD_EN = '(?:\\b(?:an?|the)\\s+)?(?:(?:only|cheaper|cheapest|lower[- ]cost|dearer|other|same)\\s+)?';
const TIER_AR = '(?:ال)?(?:فاخرة|فاخر|متوسطة\\s+الفئة|متوسط\\s+الفئة|اقتصادية|اقتصادي)';
const AR_B = '(?<![\\u0600-\\u06FF])'; const AR_E = '(?![\\u0600-\\u06FF])';
/**
 * LEDGER 1588, EVERYWHERE THE ANALYSIS SAYS IT — THE BACKSTOP (review item 9; final review FIX 2b). The model no longer reads a
 * hidden brand's tier or origin (hideBrandForModel), so this only catches what is left: the generic phrase in any spacing or
 * case, any brand phrase built from the hidden nationalities ("Chinese economy brand", "economy-tier Chinese units", "a
 * Chinese brand", "non-Japanese brand"), a tier word on a brand noun ("the only economy option"), every way of stating the
 * origin ("Chinese-made", "China-made", "origin: China", "country of origin: China", "from China", "made in the PRC"), and
 * the Arabic forms ("علامة صينية اقتصادية", "منشأ صيني", "مصنوع في الصين", "بلد المنشأ: الصين"). Hiding more is safe.
 */
// deno-lint-ignore no-explicit-any
export function hideBrandPhrases(a: any, phrases: HiddenPhrases[]): any {
  const en = phrases.flatMap((p) => p.en); const arr = phrases.flatMap((p) => p.ar); const cs = phrases.flatMap((p) => p.countries || []);
  if (!en.length && !arr.length && !cs.length) return a;
  const adj = alt(cs.map((c) => c.adj)); const ctry = alt(cs.flatMap((c) => [c.en, ...(COUNTRY_ALIASES[c.code ?? ''] ?? [])]));
  // A bare "UAE" is the market every quote is in, never a brand's tell on its own: only its phrased forms are taken out.
  const bare = alt(cs.filter((c) => c.code !== 'AE').flatMap((c) => [c.adj, c.en, ...(COUNTRY_ALIASES[c.code ?? ''] ?? [])]));
  const adjAr = alt(cs.flatMap((c) => [c.ar_adj, c.ar_adj.replace(/ة$/, '')]));
  const ctryAr = alt(cs.map((c) => c.ar));
  const bareAr = alt(cs.filter((c) => c.code !== 'AE').flatMap((c) => [c.ar_adj, c.ar_adj.replace(/ة$/, ''), c.ar]));
  const rules: [RegExp, string][] = [];
  if (en.length) rules.push([new RegExp(`${LEAD_EN}(?:${alt(en)})\\b`, 'gi'), AS_ASKED_EN]);
  if (adj) {
    const A = `(?:non-)?(?:${adj})`;
    rules.push([new RegExp(`${LEAD_EN}(?:${TIER_EN}(?:[\\s-]+tier)?[\\s-]+)?${A}(?:[\\s-]+${TIER_EN}(?:[\\s-]+tier)?)?[\\s-]+${NOUN_EN}\\b`, 'gi'), AS_ASKED_EN]);
    rules.push([new RegExp(`\\b(?:${adj})[\\s-]+(?:made|manufactured|built|origin)\\b`, 'gi'), ORIGIN_EN]);
  }
  if (ctry) {
    rules.push([new RegExp(`${LEAD_EN}${TIER_EN}(?:[\\s-]+tier)?[\\s-]+${NOUN_EN}\\s+(?:from|made\\s+in)\\s+(?:the\\s+)?(?:${ctry})(?![A-Za-z])`, 'gi'), AS_ASKED_EN]);
    rules.push([new RegExp(`\\b(?:country\\s+of\\s+)?origin\\s*(?:is\\s*)?[:\\-–]?\\s*(?:the\\s+)?(?:${ctry}${adj ? '|' + adj : ''})(?![A-Za-z])`, 'gi'), ORIGIN_EN]);
    rules.push([new RegExp(`\\b(?:made|manufactured|produced|built|assembled|sourced|imported)\\s+(?:in|from)\\s+(?:the\\s+)?(?:${ctry})(?![A-Za-z])`, 'gi'), ORIGIN_EN]);
    rules.push([new RegExp(`(?<![A-Za-z])(?:${ctry})[\\s-]+(?:made|manufactured|built)\\b`, 'gi'), ORIGIN_EN]);
    rules.push([new RegExp(`\\bfrom\\s+(?:the\\s+)?(?:${ctry})(?![A-Za-z])`, 'gi'), `from an ${ORIGIN_EN}`]);
  }
  rules.push([new RegExp(`${LEAD_EN}${TIER_EN}(?:[\\s-]+tier)?[\\s-]+${NOUN_EN}\\b`, 'gi'), AS_ASKED_EN]);
  if (bare) rules.push([new RegExp(`(?<![A-Za-z])(?:non-)?(?:${bare})(?![A-Za-z])`, 'gi'), `(${ORIGIN_EN})`]);
  if (arr.length) rules.push([new RegExp(`(?:${alt(arr)})`, 'g'), AS_ASKED_AR]);
  if (adjAr) {
    rules.push([new RegExp(`${AR_B}(?:ال)?(?:علامة|علامات|ماركة|وحدات|خيار)(?:\\s+(?:ال)?تجارية)?\\s+(?:${TIER_AR}\\s+)?(?:ال)?(?:${adjAr})(?:\\s+${TIER_AR})?${AR_E}`, 'g'), AS_ASKED_AR]);
    rules.push([new RegExp(`${AR_B}(?:بلد\\s+)?(?:ال)?منشأ\\s*[:：]?\\s*(?:ال)?(?:${adjAr}${ctryAr ? '|' + ctryAr : ''})${AR_E}`, 'g'), ORIGIN_AR]);
  }
  if (ctryAr) {
    rules.push([new RegExp(`${AR_B}(?:صنع|صُنع|صُنعت|مصنوع|مصنوعة|مصنّع|مصنّعة|مصنع|مصنعة|منتج|منتجة)\\s+في\\s+(?:${ctryAr})${AR_E}`, 'g'), ORIGIN_AR]);
    rules.push([new RegExp(`${AR_B}من\\s+(?:${ctryAr})${AR_E}`, 'g'), 'من منشأ يظهر بعد الكشف']);
  }
  rules.push([new RegExp(`${AR_B}(?:ال)?(?:علامة|ماركة|وحدات|خيار)(?:\\s+(?:ال)?تجارية)?\\s+${TIER_AR}${AR_E}`, 'g'), AS_ASKED_AR]);
  if (bareAr) rules.push([new RegExp(`${AR_B}[وبلف]?(?:ال)?(?:${bareAr})${AR_E}`, 'g'), `(${ORIGIN_AR})`]);
  const fix = (t: string) => {
    let s = t;
    for (const [re, to] of rules) s = s.replace(re, to);
    // "an brand as you asked" (the review's own catch) and a doubled article read as one article.
    return s.replace(/\b([Aa])n?\s+(?:an?\s+)?(?=brand as you asked)/g, '$1 ').replace(/\b(?:[Tt]he)\s+a brand as you asked/g, 'a brand as you asked');
  };
  // deno-lint-ignore no-explicit-any
  const walk = (o: any): any => typeof o === 'string' ? fix(o) : Array.isArray(o) ? o.map(walk) : o && typeof o === 'object' ? Object.fromEntries(Object.entries(o).map(([k, v]) => [k, walk(v)])) : o;
  return walk(a);
}
const BRAND_FIELD = /^(?:brand|brand_name|make|manufacturer)$/i;
const ORIGIN_FIELD = /^(?:country_of_origin|origin|country|made_in)$/i;
/**
 * WHAT THE MODEL READS OF A HIDDEN QUOTE (final review FIX 2b): its brand fields say only that the brand is as the customer
 * asked, its origin fields are left out, and every phrase hideBrandPhrases knows is taken out of the rest (descriptions,
 * terms, review notes) before the payload is built. The model cannot write what it never read.
 */
export function hideBrandForModel<T>(q: T, phrases: HiddenPhrases | null | undefined): T {
  if (!phrases || (!phrases.en.length && !phrases.ar.length && !phrases.countries.length)) return q;
  // deno-lint-ignore no-explicit-any
  const walk = (o: any): any => Array.isArray(o) ? o.map(walk) : o && typeof o === 'object'
    ? Object.fromEntries(Object.entries(o).filter(([k]) => !ORIGIN_FIELD.test(k)).map(([k, v]) => [k, BRAND_FIELD.test(k) && typeof v === 'string' && v.trim() ? 'as the customer asked (shown after the reveal)' : walk(v)]))
    : o;
  return hideBrandPhrases(walk(q), [phrases]);
}
