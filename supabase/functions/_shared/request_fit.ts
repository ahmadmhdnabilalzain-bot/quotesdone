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
import { brandFact, genericBrand, TIER_RANK, tierOf, type Tier } from './quote_generalise.ts';
import { deliveryOf, warrantyPeriod } from './line_specs/assess.ts';

export type Bi = { en: string; ar: string };
export type FitStatus = 'meets' | 'differs' | 'not_stated';
export type Requirement = {
  code: string; hard: boolean; label: Bi; asked: Bi;
  brands?: string[]; tier?: Tier | null; refrigerants?: string[]; capacities?: { tr: number; qty: number }[];
  units?: number | null; tr?: number | null; subitems?: string[]; metres?: number | null; date?: string; months?: number; words?: string[];
};
export type FitCell = { status: FitStatus; shown: Bi };
export type FitFail = { code: string; noun: Bi; detail: Bi };
export type QuoteFit = {
  cells: Record<string, FitCell>; met: number; total: number; score: number | null;
  hard_fails: FitFail[]; hard_open: { code: string; label: Bi }[]; asks: Bi[];
  brand: { listed: boolean | null; generic: Bi | null }; meets_date: boolean | null;
};
export type RequestIn = { category?: string | null; summary?: string | null; raw_input?: unknown; spec?: unknown };
export type FitLine = { line_no?: number | null; line?: number | null; description?: string | null; brand?: string | null; model?: string | null; specification?: string | null; qty?: number | string | null; unit?: string | null; notes?: string | null; spec?: Record<string, unknown> | null };
export type FitQuote = { lead_time?: string | null; warranty?: string | null; scope?: string | null; exclusions?: string | null; conditions?: string | null; notes?: string | null;
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
function specValues(spec: unknown): [string, string][] {
  if (!spec || typeof spec !== 'object') return [];
  return Object.entries(spec as Record<string, unknown>).filter(([k, v]) => !INTERNAL.has(k) && (typeof v === 'string' || typeof v === 'number')).map(([k, v]) => [k, S(v)] as [string, string]).filter(([, v]) => v !== '');
}
const keyed = (vals: [string, string][], re: RegExp) => vals.filter(([k]) => re.test(k)).map(([, v]) => v);
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
  const out: Requirement[] = [];

  // BRANDS: every make the customer named (the trade checklist's brand answer, or a material answer in his own words).
  const brandText = [...keyed(vals, /brand|make|manufacturer/i), ...((cr.materials || []) as { component?: string; choice?: string; note?: string }[])
    .filter((m) => /brand/i.test(S(m?.component)) && m?.choice === 'other').map((m) => S(m.note))].join(' · ');
  const brands = brandsIn(brandText);
  // deno-lint-ignore no-explicit-any
  const tierAnswer: any = ((cr.materials || []) as any[]).find((m) => /brand/i.test(S(m?.component)) && ['premium', 'mid', 'economy'].includes(S(m?.choice)));
  if (brands.length) {
    out.push({ code: 'brand_list', hard: true, label: bi('Brand', 'العلامة التجارية'), brands,
      asked: brands.length === 1 ? bi('The brand you named', 'العلامة التي سمّيتها') : bi(`One of the ${brands.length} brands you named`, `إحدى العلامات الـ${brands.length} التي سمّيتها`) });
  } else if (tierAnswer) {
    const tier: Tier = tierAnswer.choice === 'mid' ? 'mid-range' : tierAnswer.choice;
    out.push({ code: 'brand_tier', hard: false, label: bi('Brand tier', 'فئة العلامة التجارية'), tier, asked: bi(S(tierAnswer.choice_en) || tier, S(tierAnswer.choice_ar) || tier) });
  }

  // PRODUCT: inverter, refrigerant, units and capacity.
  const inv = keyed(vals, /inverter/i).join(' ');
  if (/inverter|إنفرتر|انفرتر/i.test(inv) && !/fixed|non[- ]?inverter|ثابت/i.test(inv)) out.push({ code: 'inverter', hard: true, label: bi('Inverter units', 'وحدات إنفرتر'), asked: bi('Inverter', 'إنفرتر') });
  const refrigerants = refrigerantsIn(keyed(vals, /refrigerant/i).join(' '));
  if (refrigerants.length) out.push({ code: 'refrigerant', hard: true, label: bi('Refrigerant', 'غاز التبريد'), refrigerants, asked: bi(refrigerants.join(' or '), refrigerants.join(' أو ')) });
  const capText = keyed(vals, /capacity/i).join(' ; ');
  const capacities: { tr: number; qty: number }[] = []; let serviceTr: number | null = null;
  for (const seg of capText.split(/[;\n]+/)) {
    const service = /duct|servic|صيانة/i.test(seg);
    for (const m of seg.matchAll(/(\d+)\s*[x×]\s*(\d+(?:\.\d+)?)\s*(?:tr|tons?|طن)/gi)) {
      if (service) { serviceTr = Number(m[2]); continue; }
      const tr = Number(m[2]); const c = capacities.find((x) => x.tr === tr); if (c) c.qty += Number(m[1]); else capacities.push({ tr, qty: Number(m[1]) });
    }
  }
  const splitUnits = capacities.length ? capacities.reduce((s, c) => s + c.qty, 0) : num(keyed(vals, /split_unit_count/i)[0]);
  if (capacities.length) {
    out.push({ code: 'capacity', hard: true, label: bi('Units and capacity', 'عدد الوحدات وقدرتها'), capacities,
      asked: bi(capacities.map((c) => `${c.qty} × ${trFmt(c.tr)}`).join(' and '), capacities.map((c) => `${c.qty} × ${trFmt(c.tr, true)}`).join(' و')) });
  }

  // SCOPE: supply and installation, removal of the old units, the service of existing units, copper, isolators.
  if (S(cr.installation?.required) === 'yes' || cr.installation?.required === true) out.push({ code: 'installation', hard: true, label: bi('Supply and installation', 'التوريد والتركيب'), asked: bi('Supply and install', 'توريد وتركيب') });
  const removal = keyed(vals, /removal|remove|dispos/i).join(' ');
  if (removal && !/^(?:no|none|not needed|keep)\b/i.test(removal)) {
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
  const copper = keyed(vals, /copper|pipe/i).join(' ');
  if (copper) {
    const per = num(copper.match(/(\d+(?:\.\d+)?)\s*(?:m\b|metres?|meters?|م\b)/i)?.[1]);
    const total = per && splitUnits ? per * splitUnits : null;
    out.push({ code: 'copper', hard: false, label: bi('New copper pipe allowance', 'بدل أنابيب النحاس الجديدة'), metres: total,
      asked: per ? bi(`Reuse the existing, or up to ${per} m new per unit${total ? ` (${total} m)` : ''}`, `إعادة استخدام الحالية، أو حتى ${per} م جديدة لكل وحدة${total ? ` (${total} م)` : ''}`) : bi('As stated in your request', 'كما ورد في طلبك') });
  }
  const iso = keyed(vals, /isolator|electrical/i).join(' ');
  if (/isolator|power point|connect/i.test(iso)) out.push({ code: 'isolator', hard: false, label: bi('Connection to your existing isolators', 'التوصيل بمفاتيح العزل الموجودة'), asked: bi('Connect only; the isolators are in place', 'توصيل فقط؛ المفاتيح موجودة') });

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
const YES = bi('Yes', 'نعم'), NO = bi('No', 'لا'), NOT_STATED = bi('Not stated', 'غير مذكور'), NOT_IN = bi('Not in this quote', 'غير مشمول في هذا العرض');
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
  const cells: Record<string, FitCell> = {}; const asks: Bi[] = []; const fails: FitFail[] = [];
  let brand: QuoteFit['brand'] = { listed: null, generic: null }; let meetsDate: boolean | null = null;
  const set = (r: Requirement, status: FitStatus, shown: Bi, fail?: Bi) => { cells[r.code] = { status, shown }; if (status === 'differs' && r.hard) fails.push({ code: r.code, noun: lower(r.label), detail: fail ?? bi(`${shown.en}, against ${r.asked.en.toLowerCase()} you asked for`, `${shown.ar}، والمطلوب: ${r.asked.ar}`) }); };

  // The quoted brands, RAW, from the product lines: compared now, and only their generic words leave this function.
  const quotedBrands = [...new Set(product.map((l) => { const raw = S(l.brand) || S((l.spec || {}).brand); return raw ? (brandFact(raw)?.name ?? raw) : brandsIn([l.description, l.specification].map(S).join(' '))[0] ?? ''; }).filter(Boolean))];
  if (quotedBrands.length) {
    const gens = quotedBrands.map((b) => genericBrand(b));
    brand.generic = bi([...new Set(gens.map((g) => g.en))].join(', '), [...new Set(gens.map((g) => g.ar))].join('، '));
  }
  for (const r of reqs) {
    switch (r.code) {
      case 'brand_list': {
        if (!quotedBrands.length) { set(r, 'not_stated', NOT_STATED); break; }
        const listed = quotedBrands.every((b) => (r.brands || []).some((x) => x.toLowerCase() === b.toLowerCase()));
        brand = { ...brand, listed };
        set(r, listed ? 'meets' : 'differs', bi(`${listed ? 'Yes' : 'No'}: ${brand.generic!.en}`, `${listed ? 'نعم' : 'لا'}: ${brand.generic!.ar}`),
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
        if (r.units && n != null && n < r.units) { set(r, 'differs', bi(`${n} of ${r.units} units`, `${n} من ${r.units} وحدات`), bi(`it services ${n} of your ${r.units} ducted units`, `يصون ${n} من أصل ${r.units} وحدات دكت`)); break; }
        const missing = SUBITEMS.filter((s) => (r.subitems || []).includes(s.key) && !s.re.test(lineText(l)));
        if (missing.length) {
          set(r, 'not_stated', bi(`Priced; it does not mention the ${missing.map((s) => s.en).join(', ')}`, `مسعّرة؛ لا تذكر ${missing.map((s) => s.ar).join('، ')}`));
          asks.push(bi(`Does the service of the ducted units include the ${missing.map((s) => s.en).join(' and ')}? You asked for them; the quote does not name them.`, `هل تشمل صيانة وحدات الدكت ${missing.map((s) => s.ar).join(' و')}؟ طلبتها ولا يذكرها العرض.`));
        } else set(r, 'meets', bi(`Yes${n != null ? `: ${n} units` : ''}${r.subitems?.length ? ', every item you listed' : ''}`, `نعم${n != null ? `: ${n} وحدات` : ''}${r.subitems?.length ? '، وكل ما ذكرته' : ''}`));
        break;
      }
      case 'copper': {
        const l = others.find((x) => /copper|pipe|piping|نحاس|أنابيب/i.test(lineText(x)));
        const m = l ? num(l.qty) : null;
        if (!l) { set(r, 'not_stated', NOT_STATED); asks.push(bi(`Is new copper pipe included if the existing pipe cannot be reused? You allowed ${r.metres ? `up to ${r.metres} m` : 'for it'}.`, `هل تشمل الأسعار أنابيب نحاس جديدة إذا تعذّر استخدام الحالية؟ سمحت ${r.metres ? `بحتى ${r.metres} م` : 'بذلك'}.`)); }
        else if (r.metres && m != null && m < r.metres) { set(r, 'differs', bi(`${m} m priced`, `${m} م مسعّرة`)); asks.push(bi(`It prices ${m} m of new copper pipe; you allowed up to ${r.metres} m. What does each further metre cost?`, `يسعّر ${m} م من أنابيب النحاس الجديدة، وسمحت بحتى ${r.metres} م. ما تكلفة كل متر إضافي؟`)); }
        else set(r, 'meets', bi(m != null ? `${m} m priced` : 'Priced', m != null ? `${m} م مسعّرة` : 'مسعّرة'));
        break;
      }
      case 'isolator': {
        if (/isolator|existing\s+power|connect\w*\s+to/i.test(all)) set(r, 'meets', YES);
        else if (/electric/i.test(excl)) { set(r, 'not_stated', bi('Unclear: it excludes electrical works', 'غير واضح: يستثني الأعمال الكهربائية')); asks.push(bi('It excludes electrical works. Is connecting the new units to your existing isolators included?', 'يستثني العرض الأعمال الكهربائية. هل يشمل توصيل الوحدات الجديدة بمفاتيح العزل الموجودة؟')); }
        else set(r, 'not_stated', NOT_STATED);
        break;
      }
      case 'date': {
        const lead = S(q.terms_spec?.delivery?.value) || S(q.lead_time);
        const d = lead ? deliveryOf(lead) : null;
        const at = d?.days != null ? new Date(input.now.getTime() + d.days * 864e5) : d?.date ? new Date(d.date) : null;
        if (!at || isNaN(at.getTime())) { set(r, 'not_stated', NOT_STATED); meetsDate = null; asks.push(bi(`When will the work be done? You need it by ${dateEn(r.date!)}.`, `متى يُنجز العمل؟ تحتاجه بحلول ${dateAr(r.date!)}.`)); break; }
        meetsDate = at.getTime() <= new Date(r.date! + 'T00:00:00Z').getTime() + 864e5;
        set(r, meetsDate ? 'meets' : 'differs', bi(`${meetsDate ? 'Yes' : 'No'}: ${lead}`, `${meetsDate ? 'نعم' : 'لا'}: ${lead}`), bi(`it would finish around ${dateEn(at.toISOString())}, after your date of ${dateEn(r.date!)}`, `سينتهي نحو ${dateAr(at.toISOString())}، بعد موعدك ${dateAr(r.date!)}`));
        break;
      }
      case 'warranty_installation':
      case 'warranty_compressor': {
        const w = warrantyParts([S(q.terms_spec?.warranty?.period), S(q.terms_spec?.warranty?.coverage), S(q.warranty)].filter(Boolean).join(' ; '));
        const got = r.code === 'warranty_compressor' ? w.compressor : w.install;
        if (got == null) { set(r, 'not_stated', NOT_STATED); if (r.code === 'warranty_compressor') asks.push(bi(`What warranty does it give on the compressors? You asked for at least ${yearsEn(r.months!)}; the quote does not say.`, `ما مدة ضمان الضواغط؟ طلبت ${yearsAr(r.months!)} على الأقل، ولا يذكرها العرض.`)); break; }
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
  if (SUBJECT_TO_VISIT.test([terms, excl].join(' '))) asks.unshift(bi('The price is subject to a site visit. What could change it after the visit?', 'السعر مشروط بمعاينة الموقع. ما الذي قد يغيّره بعد المعاينة؟'));
  else if (input.site_visit && !FIRM_PRICE.test(terms)) asks.unshift(bi('Is this price final, or subject to the site visit your request mentions?', 'هل هذا السعر نهائي، أم مشروط بمعاينة الموقع التي ذكرها طلبك؟'));

  const total = Object.keys(cells).length;
  const met = Object.values(cells).filter((c) => c.status === 'meets').length;
  const credit = Object.values(cells).reduce((s, c) => s + (c.status === 'meets' ? 1 : c.status === 'not_stated' ? 0.5 : 0), 0);
  const hardOpen = reqs.filter((r) => r.hard && cells[r.code]?.status === 'not_stated').map((r) => ({ code: r.code, label: r.label }));
  return { cells, met, total, score: total ? Math.round((5 * credit / total) * 10) / 10 : null, hard_fails: fails, hard_open: hardOpen, asks: asks.slice(0, 5), brand, meets_date: meetsDate };
}
const lower = (b: Bi): Bi => ({ en: b.en.charAt(0).toLowerCase() + b.en.slice(1), ar: b.ar });
/** Whether the request names a site visit before a final price (the trade checklist's site-visit answer). */
export function siteVisitAsked(spec: unknown): boolean {
  return specValues(spec).some(([k, v]) => /site_visit|survey/i.test(k) && !/^(?:no|not needed|none)\b/i.test(v));
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
  const brandPart = f.brand.listed && f.brand.generic ? (ar ? `إحدى العلامات التي سمّيتها (${f.brand.generic.ar})، و` : `one of your listed brands (${f.brand.generic.en}), and `) : '';
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
export function annotateTechnical<T extends RTech>(t: T, reqs: Requirement[], fits: Record<string, QuoteFit>, trade: string | null, lang: 'en' | 'ar'): T {
  const ar = lang === 'ar';
  const by = new Map(reqs.map((r) => [r.code, r]));
  const brandReq = by.get('brand_list') ?? by.get('brand_tier'); const cap = by.get('capacity'); const ref = by.get('refrigerant');
  const kept = t.lines.filter((l) => isProductLine(l.item, trade));
  const lines = kept.map((l) => {
    const lineTr = trOf(l.item);
    // With no BOQ the row's title is the first quote's own line ("…; economy Chinese brand, made in China"), which reads as
    // what was asked. Where the request names this capacity, the row is titled by the request instead.
    const asked = cap && lineTr != null && l.line_no == null ? (cap.capacities || []).find((c) => c.tr === lineTr) : null;
    const item = asked ? (ar ? `وحدات ${trFmt(asked.tr, true)}: طلبت ${asked.qty}` : `${trFmt(asked.tr)} units: you asked for ${asked.qty}`) : l.item;
    const attributes = l.attributes.map((at) => {
      const values: Record<string, RCell> = { ...at.values }; let requested = at.requested ?? null;
      if (at.key === 'brand' && brandReq) {
        requested = brandReq.asked[lang];
        for (const s of Object.keys(values)) { const c = values[s]; const ok = fits[s]?.cells[brandReq.code]?.status; if (c.flag === 'na' || !c.value) continue; values[s] = { ...c, flag: ok === 'meets' ? 'match' : ok === 'differs' ? 'differs' : c.flag, note: brandReq.code === 'brand_list' && ok ? (ok === 'meets' ? (ar ? 'من علاماتك' : 'one you named') : (ar ? 'ليست من علاماتك' : 'not one you named')) : c.note ?? null }; }
      }
      if (at.key === 'capacity_tr' || /capacity/i.test(at.key)) {
        const want = cap && lineTr != null && (cap.capacities || []).some((c) => c.tr === lineTr) ? lineTr : null;
        if (want != null) requested = trFmt(want, ar);
        for (const s of Object.keys(values)) { const c = values[s]; const n = num(c.value); if (c.flag === 'na' || n == null) continue; values[s] = { ...c, value: trFmt(n, ar), flag: want != null ? (n === want ? 'match' : 'differs') : c.flag }; }
      }
      if (at.key === 'refrigerant' && ref) {
        requested = ref.asked[lang];
        for (const s of Object.keys(values)) { const c = values[s]; const got = refrigerantsIn(c.value); if (c.flag === 'na' || !got.length) continue; values[s] = { ...c, flag: got.every((g) => (ref.refrigerants || []).includes(g)) ? 'match' : 'differs' }; }
      }
      return { ...at, requested, values };
    }).filter((at) => Object.values(at.values).some((c) => c.flag !== 'na'));
    return { ...l, item, attributes };
  });
  const terms = t.terms ? { ...t.terms } : t.terms;
  if (terms?.warranty) { const ws = ['warranty_installation', 'warranty_compressor'].map((c) => by.get(c)).filter(Boolean) as Requirement[]; if (ws.length) terms.warranty = { ...terms.warranty, requested: ws.map((w) => (ws.length > 1 ? `${w.label[lang]}: ` : '') + w.asked[lang]).join(ar ? '؛ ' : '; ') }; }
  if (terms?.lead_time && by.get('date')) terms.lead_time = { ...terms.lead_time, requested: by.get('date')!.asked[lang] };
  return { ...t, lines, terms, scope_lines_dropped: t.lines.length - kept.length };
}

/** The request side as the analysis carries it: what was asked, quote by quote, with no raw brand anywhere. */
export function fitView(reqs: Requirement[], rows: { label: string; quote_id: string | null; fit: QuoteFit }[]) {
  return {
    requirements: reqs.map((r) => ({ code: r.code, hard: r.hard, label: r.label, asked: r.asked })),
    quotes: rows.map((x) => ({ label: x.label, quote_id: x.quote_id, ...x.fit })),
  };
}

/**
 * ON ANY RANKING (the model's, a cached one, the rules'): a shortlisted quote that fails a hard requirement says so in its
 * catch, and is never first while a shortlisted quote meets every hard requirement. The rules ranking already orders this
 * way; this is the guarantee for the model's answer and for an analysis cached before this rule.
 */
// deno-lint-ignore no-explicit-any
export function enforceFit(a: any, fits: Record<string, QuoteFit>, lang: 'en' | 'ar'): void {
  if (!a || !Array.isArray(a.top3) || !a.top3.length) return;
  const ar = lang === 'ar';
  for (const t of a.top3) {
    const f = t && fits[String(t.label)]; if (!f || !f.hard_fails.length) continue;
    const s = ar ? `لا يستوفي طلبك: ${failText(f, 'ar')}.` : `Fails ${failText(f, 'en')}.`;
    if (!String(t.tradeoff || '').includes(s)) t.tradeoff = [s, String(t.tradeoff || '').trim()].filter(Boolean).join(' ');
  }
  const first = a.top3[0]; const ff = fits[String(first?.label)];
  if (!ff || !ff.hard_fails.length) return;
  const passing = a.top3.filter((t: { label: string }) => fits[String(t.label)] && !fits[String(t.label)].hard_fails.length);
  if (!passing.length) return;
  const failing = a.top3.filter((t: { label: string }) => !passing.includes(t));
  a.top3 = [...passing, ...failing].map((t: Record<string, unknown>, i: number) => ({ ...t, rank: i + 1 }));
  a.best_value_label = a.top3[0].label;
  const note = ar ? `نضع ${a.top3[0].label} أولًا: ${first.label} لا يستوفي ${failText(ff, 'ar')}.` : `We place ${a.top3[0].label} first: ${first.label} fails ${failText(ff, 'en')}.`;
  a.bottom_line = [note, String(a.bottom_line || '')].filter(Boolean).join(' ');
}
