// quote_generalise.ts — A QUOTATION THE CUSTOMER READS BEFORE THE REVEAL NAMES NO BRAND, MODEL OR PRODUCT LINE.
// Seat: sales_engineer. 10 Nov 2026, founder ledger 1588-1590.
//
// THE FOUNDER'S RULE (1589): a quotation shown to the customer before the reveal must not let the customer identify
// the supplier from its description. A brand, a model number, a proprietary product line or distinctive wording
// that points to one or two suppliers is replaced with a FACTUALLY CORRECT generic description that keeps origin
// and tier: a named German premium mixer becomes "premium German brand mixer". (His own example said Grohe ->
// "premium Italian brand"; Grohe is German, so the replacement must stay true — the origin comes from the table,
// never from a guess.)
//
// WHAT WAS THERE (measured 10 Nov 2026):
//   * quote_extract's model prompt replaced brands with "premium branded mixer": the ORIGIN was lost, so a customer
//     who asked for Italian porcelain could not see that the supplier quoted Chinese.
//   * quote_from_document (no model) removed the supplier's own company name and contact shapes only; a brand, a
//     model number and a product line went through untouched.
//   * quote_items.brand / .model were served raw before the reveal: on the customer's quotation PDF as "Brand: X /
//     Model: Y" (quote_documents/kit.ts specText), in quote_compare's technical table, roster and model input, and
//     the free-text fields (scope, notes, exclusions...) in my_inquiries.
//
// WHAT THIS IS. One module, used on EVERY path (the model path's output, the deterministic path, and every pre-reveal
// surface), for every trade:
//   1. contact shapes and firm names — the shared list (_shared/identity_text.ts), never a copy of it;
//   2. the supplier's OWN name anywhere in a description -> "the supplier";
//   3. a KNOWN brand (brand_facts.generated.ts, derived from the 219 packs' uae_market_brands + the explicit table)
//      -> "<tier> <origin> brand", with the product-line words and model code that follow it taken with it;
//   4. the quote's OWN brand / model column values, wherever they recur in its text (catches a brand no table knows);
//   5. a model number / SKU / catalogue code, labelled or not, -> "model stated (shown after reveal)"; a specification
//      code (SS316, DN50, IP65, C40, 120x60, R410A, BS EN 1092-1) is never one;
//   6. a proprietary product line (a word with (TM)/(R), a "<Name> series/range/collection", a quoted 'Name') ->
//      "proprietary".
// An unknown brand becomes "branded" plus the tier the quotation itself states; an origin is NEVER guessed.
//
// WHAT IT DOES NOT DO. It does not decide whether a deviation matters (quote_review_notes.ts does) and it never
// touches a price, a quantity, a unit, a dimension or a grade. country_of_origin is kept: "made in Italy" is what the
// customer needs and names no supplier. prevented by: _shared/quote_generalise.test.ts and the 24-trade corpus
// (scripts/e2e/quote_review_corpus.mjs).
import { BRAND_ROWS } from './brand_facts.generated.ts';
import { knownNameRe, scrubIdentityText } from './identity_text.ts';
import { tradeWord } from './drawing_vocabulary.ts';

export type Tier = 'premium' | 'mid-range' | 'economy';
export type Replacement = { term: string; generic: string; kind: 'brand' | 'model' | 'product_line' | 'supplier_name' | 'contact' };
export type GeneraliseCtx = {
  /** The supplier's own company name(s); a match anywhere becomes "the supplier". */
  supplierNames?: (string | null | undefined)[];
  /** The quote's own brand-column / spec.brand values: a recurrence anywhere in its text is a brand. */
  brands?: (string | null | undefined)[];
  /** The quote's own model-column / spec.model values: a recurrence anywhere is a model. */
  models?: (string | null | undefined)[];
};

// ---------------------------------------------------------------------------------------------
// Origins: the country a brand comes from, as an adjective in both languages (Arabic agrees with علامة, feminine).
// ---------------------------------------------------------------------------------------------
export const ORIGIN: Readonly<Record<string, { en: string; country: string; ar: string; ar_country: string }>> = {
  DE: { en: 'German', country: 'Germany', ar: 'ألمانية', ar_country: 'ألمانيا' }, IT: { en: 'Italian', country: 'Italy', ar: 'إيطالية', ar_country: 'إيطاليا' },
  ES: { en: 'Spanish', country: 'Spain', ar: 'إسبانية', ar_country: 'إسبانيا' }, FR: { en: 'French', country: 'France', ar: 'فرنسية', ar_country: 'فرنسا' },
  JP: { en: 'Japanese', country: 'Japan', ar: 'يابانية', ar_country: 'اليابان' }, CN: { en: 'Chinese', country: 'China', ar: 'صينية', ar_country: 'الصين' },
  IN: { en: 'Indian', country: 'India', ar: 'هندية', ar_country: 'الهند' }, US: { en: 'American', country: 'USA', ar: 'أمريكية', ar_country: 'الولايات المتحدة' },
  GB: { en: 'British', country: 'UK', ar: 'بريطانية', ar_country: 'المملكة المتحدة' }, TR: { en: 'Turkish', country: 'Turkey', ar: 'تركية', ar_country: 'تركيا' },
  KR: { en: 'Korean', country: 'South Korea', ar: 'كورية', ar_country: 'كوريا الجنوبية' }, AE: { en: 'UAE', country: 'UAE', ar: 'إماراتية', ar_country: 'الإمارات' },
  SA: { en: 'Saudi', country: 'Saudi Arabia', ar: 'سعودية', ar_country: 'السعودية' }, CH: { en: 'Swiss', country: 'Switzerland', ar: 'سويسرية', ar_country: 'سويسرا' },
  SE: { en: 'Swedish', country: 'Sweden', ar: 'سويدية', ar_country: 'السويد' }, DK: { en: 'Danish', country: 'Denmark', ar: 'دنماركية', ar_country: 'الدنمارك' },
  NO: { en: 'Norwegian', country: 'Norway', ar: 'نرويجية', ar_country: 'النرويج' }, FI: { en: 'Finnish', country: 'Finland', ar: 'فنلندية', ar_country: 'فنلندا' },
  NL: { en: 'Dutch', country: 'Netherlands', ar: 'هولندية', ar_country: 'هولندا' }, BE: { en: 'Belgian', country: 'Belgium', ar: 'بلجيكية', ar_country: 'بلجيكا' },
  AT: { en: 'Austrian', country: 'Austria', ar: 'نمساوية', ar_country: 'النمسا' }, TW: { en: 'Taiwanese', country: 'Taiwan', ar: 'تايوانية', ar_country: 'تايوان' },
  CA: { en: 'Canadian', country: 'Canada', ar: 'كندية', ar_country: 'كندا' }, AU: { en: 'Australian', country: 'Australia', ar: 'أسترالية', ar_country: 'أستراليا' },
  IE: { en: 'Irish', country: 'Ireland', ar: 'أيرلندية', ar_country: 'أيرلندا' }, EG: { en: 'Egyptian', country: 'Egypt', ar: 'مصرية', ar_country: 'مصر' },
  JO: { en: 'Jordanian', country: 'Jordan', ar: 'أردنية', ar_country: 'الأردن' }, OM: { en: 'Omani', country: 'Oman', ar: 'عُمانية', ar_country: 'عُمان' },
  TH: { en: 'Thai', country: 'Thailand', ar: 'تايلندية', ar_country: 'تايلند' }, VN: { en: 'Vietnamese', country: 'Vietnam', ar: 'فيتنامية', ar_country: 'فيتنام' },
  MY: { en: 'Malaysian', country: 'Malaysia', ar: 'ماليزية', ar_country: 'ماليزيا' }, ID: { en: 'Indonesian', country: 'Indonesia', ar: 'إندونيسية', ar_country: 'إندونيسيا' },
  PL: { en: 'Polish', country: 'Poland', ar: 'بولندية', ar_country: 'بولندا' }, PT: { en: 'Portuguese', country: 'Portugal', ar: 'برتغالية', ar_country: 'البرتغال' },
  CZ: { en: 'Czech', country: 'Czech Republic', ar: 'تشيكية', ar_country: 'التشيك' }, IL: { en: 'Israeli', country: 'Israel', ar: 'إسرائيلية', ar_country: 'إسرائيل' },
  BR: { en: 'Brazilian', country: 'Brazil', ar: 'برازيلية', ar_country: 'البرازيل' }, MX: { en: 'Mexican', country: 'Mexico', ar: 'مكسيكية', ar_country: 'المكسيك' },
  SG: { en: 'Singaporean', country: 'Singapore', ar: 'سنغافورية', ar_country: 'سنغافورة' }, PK: { en: 'Pakistani', country: 'Pakistan', ar: 'باكستانية', ar_country: 'باكستان' },
  NZ: { en: 'New Zealand', country: 'New Zealand', ar: 'نيوزيلندية', ar_country: 'نيوزيلندا' }, LI: { en: 'Liechtenstein', country: 'Liechtenstein', ar: 'ليختنشتاينية', ar_country: 'ليختنشتاين' },
};
// "European" is a region a customer may ask for; it is matched by origin code membership, never a country itself.
export const EU = new Set(['DE', 'IT', 'ES', 'FR', 'SE', 'DK', 'NO', 'FI', 'NL', 'BE', 'AT', 'IE', 'PL', 'PT', 'CZ', 'CH', 'GB', 'LI']);

const ORIGIN_WORDS: [RegExp, string][] = (() => {
  const out: [RegExp, string][] = [];
  const extra: Record<string, string[]> = { US: ['usa', 'u\\.s\\.a\\.?', 'united states', 'america'], GB: ['uk', 'u\\.k\\.', 'england', 'english', 'united kingdom', 'britain'],
    CN: ['prc', 'p\\.r\\.c\\.', 'china'], AE: ['uae', 'u\\.a\\.e\\.?', 'emirati', 'local(?:ly)? made'], KR: ['korea', 'south korea'], TR: ['türkiye', 'turkiye'], CZ: ['czechia'] };
  const AR: Record<string, string[]> = { DE: ['ألماني', 'المانيا', 'ألمانيا'], IT: ['إيطالي', 'ايطالي', 'إيطاليا', 'ايطاليا'], ES: ['إسباني', 'اسباني', 'إسبانيا', 'اسبانيا'],
    FR: ['فرنسي', 'فرنسا'], JP: ['ياباني', 'اليابان'], CN: ['صيني', 'الصين'], IN: ['هندي', 'الهند'], US: ['أمريكي', 'امريكي', 'أمريكا'], GB: ['بريطاني', 'بريطانيا'],
    TR: ['تركي', 'تركيا'], KR: ['كوري', 'كوريا'], AE: ['إماراتي', 'اماراتي', 'الإمارات', 'محلي الصنع'], SA: ['سعودي', 'السعودية'] };
  for (const [code, o] of Object.entries(ORIGIN)) {
    const words = [o.en.toLowerCase(), o.country.toLowerCase(), ...(extra[code] || [])].filter((w, i, a) => a.indexOf(w) === i);
    out.push([new RegExp(`(?<![A-Za-z])(?:${words.map((w) => w.replace(/\s+/g, '\\s+')).join('|')})(?![A-Za-z])`, 'i'), code]);
    if (AR[code]) out.push([new RegExp(`(?:${AR[code].join('|')})`), code]);
  }
  return out;
})();
const EUROPEAN = /(?<![A-Za-z])(?:european|europe|eu(?:-made)?)(?![A-Za-z])|أوروبي|اوروبي|أوروبا/i;

/** The origin a text states: "Italian", "made in Italy", "origin: PRC", "صيني". 'EU' for "European". Null if none. */
export function originOf(text: unknown): string | null {
  const s = String(text ?? ''); if (!s.trim()) return null;
  let best: { code: string; at: number } | null = null;
  for (const [re, code] of ORIGIN_WORDS) { const m = s.match(re); if (m && (best == null || (m.index ?? 0) < best.at)) best = { code, at: m.index ?? 0 }; }
  if (best) return best.code;
  return EUROPEAN.test(s) ? 'EU' : null;
}
// An origin STATED AS ONE in running text: "Italian porcelain", "made in China", "origin: Spain", "Turkish-made".
// A bare place name is not ("delivery anywhere in the UAE", "Dubai villa"): a country NAME counts only after an origin
// cue, while a nationality ADJECTIVE counts wherever it is written (no place is called "Italian").
const ORIGIN_CUE = /(?:country\s+of\s+origin|origin|made\s+in|manufactured\s+in|produced\s+in|imported\s+from|sourced\s+from|منشأ|المنشأ|صنع\s+في|بلد\s+المنشأ)\s*[:\-]?\s*([A-Za-z\u0600-\u06FF.]+(?:\s+[A-Za-z\u0600-\u06FF.]+)?)/i;
const ADJ_FORM = new RegExp(`(?<![A-Za-z])(${Object.entries(ORIGIN).filter(([c, o]) => o.en !== o.country && c !== 'AE' && c !== 'NZ' && c !== 'LI').map(([, o]) => o.en).join('|')}|European)(?:[- ]made)?(?![A-Za-z])`);
const AR_ADJ = /(?:^|\s)(ألماني|إيطالي|ايطالي|إسباني|اسباني|فرنسي|ياباني|صيني|هندي|أمريكي|امريكي|بريطاني|تركي|كوري|أوروبي|اوروبي)(?:ة|ه)?(?:\s|$)/;
/** The origin a text states AS AN ORIGIN (see above); null when it names none. */
export function statedOriginOf(text: unknown): string | null {
  // A brand's own name is not an origin ("American Standard WC", "Swiss Military"): brand names are taken out first.
  const s = String(text ?? '').replace(BRAND_RE, ' '); if (!s.trim()) return null;
  const cue = s.match(ORIGIN_CUE); if (cue) { const o = originOf(cue[1]); if (o) return o; }
  // "UAE origin", "China-made", "Japanese make": the country or nationality written BEFORE the cue.
  const pre = s.match(/(?<![A-Za-z])([A-Z][A-Za-z.]+(?:\s[A-Z][A-Za-z.]+)?)\s*[- ]?\s*(?:origin|made|make|manufactured)\b/); if (pre) { const o = originOf(pre[1]); if (o) return o; }
  const adj = s.match(ADJ_FORM); if (adj) return originOf(adj[1]);
  const ar = s.match(AR_ADJ); if (ar) return originOf(ar[1]);
  return null;
}
/** Does a stated origin satisfy the one asked for ('EU' accepts any European country)? */
export function originMeets(asked: string, quoted: string): boolean {
  return asked === quoted || (asked === 'EU' && EU.has(quoted));
}
/** "Italian" / "European" — the adjective, for "Italian origin". */
export function originAdj(code: string | null): string {
  if (!code) return 'unstated';
  if (code === 'EU') return 'European';
  return ORIGIN[code]?.en ?? code;
}
export function originLabel(code: string | null, lang: 'en' | 'ar' = 'en'): string {
  if (!code) return lang === 'ar' ? 'غير مذكور' : 'not stated';
  if (code === 'EU') return lang === 'ar' ? 'أوروبي' : 'European';
  const o = ORIGIN[code]; return o ? (lang === 'ar' ? o.ar_country : o.country) : code;
}

const TIER_WORDS: [RegExp, Tier][] = [
  [/(?<![A-Za-z])(?:premium|high[- ]end|luxury|top[- ](?:tier|end|quality)|first[- ]class|grade\s*a\b)(?![A-Za-z])|فاخر|ممتاز/i, 'premium'],
  [/(?<![A-Za-z])(?:mid[- ]?range|mid[- ]tier|standard grade|commercial grade)(?![A-Za-z])|متوسط/i, 'mid-range'],
  [/(?<![A-Za-z])(?:economy|economical|budget|entry[- ]level|basic grade|low[- ]cost)(?![A-Za-z])|اقتصادي/i, 'economy'],
];
export const TIER_RANK: Readonly<Record<Tier, number>> = { economy: 1, 'mid-range': 2, premium: 3 };
/** The tier a text states, or null. */
export function tierOf(text: unknown): Tier | null {
  const s = String(text ?? ''); for (const [re, t] of TIER_WORDS) if (re.test(s)) return t; return null;
}
const TIER_AR: Record<Tier, string> = { premium: 'فاخرة', 'mid-range': 'متوسطة الفئة', economy: 'اقتصادية' };

// ---------------------------------------------------------------------------------------------
// The brand table.
// ---------------------------------------------------------------------------------------------
export type BrandFact = { name: string; origin: string | null; tier: Tier | null; plain: boolean };
const FACTS: Map<string, BrandFact> = new Map(Object.entries(BRAND_ROWS).map(([name, r]) => [name.toLowerCase(), { name, origin: r.o, tier: r.t, plain: r.w === 1 }]));
const norm = (s: string) => s.toLowerCase().replace(/[’']/g, "'").replace(/\s+/g, ' ').trim();
/** The brand table's fact for a name ("GROHE", "Grohe Eurosmart" -> Grohe), or null when the table does not know it. */
export function brandFact(name: unknown): BrandFact | null {
  const s = norm(String(name ?? '')); if (!s) return null;
  const direct = FACTS.get(s); if (direct) return direct;
  // "Grohe Eurosmart" / "Grohe GmbH": the longest leading run of words the table knows.
  const w = s.split(' ');
  for (let n = Math.min(w.length - 1, 4); n >= 1; n--) { const f = FACTS.get(w.slice(0, n).join(' ')); if (f) return f; }
  return null;
}

/** The generic words for a brand: "premium German brand" / "علامة ألمانية فاخرة"; unknown -> "branded" (+ a stated tier). */
export function genericBrand(name: unknown, statedTier: Tier | null = null): { en: string; ar: string; origin: string | null; tier: Tier | null; known: boolean } {
  const f = brandFact(name);
  const origin = f?.origin ?? null; const tier = f?.tier ?? statedTier ?? null;
  const o = origin ? ORIGIN[origin] : null;
  const en = o ? `${tier ? tier + ' ' : ''}${o.en} brand` : `${tier ? tier + ' ' : ''}branded`;
  const ar = o ? `علامة ${o.ar}${tier ? ' ' + TIER_AR[tier] : ''}` : `ذات علامة تجارية${tier ? ' ' + TIER_AR[tier] : ''}`;
  return { en, ar, origin, tier, known: !!f };
}
export const MODEL_HIDDEN = { en: 'model stated (shown after reveal)', ar: 'الطراز مذكور (يظهر بعد الكشف)' } as const;
export const SUPPLIER_WORD = { en: 'the supplier', ar: 'المورّد' } as const;

// ---------------------------------------------------------------------------------------------
// Codes: a model / SKU is a code that is NOT a specification.
// ---------------------------------------------------------------------------------------------
const UNIT = '(?:mm2?|cm|m[23²³]?|km|kg|g|t|l|ltr|ml|w|kw|kwh|kva|kvar|va|v|vac|vdc|a|ma|mah|ah|hp|bar|psi|mpa|kpa|pa|n|kn|nm|mp|k|p|fps|gb|tb|mb|ghz|mhz|hz|rpm|btu|tr|°c|c|%|pcs|nos|sqm|sqft|ft|in|inch|"|gsm|micron|mic|dpi|ppm|lm|lux|cd|db|dba|m3h|m3\\/h|lpm|gpm|m\\/s|kva\\b)';
const SPEC_CODE: RegExp[] = [
  new RegExp(`^\\d+(?:[.,]\\d+)?\\s*${UNIT}$`, 'i'),                                   // 12mm, 2.5kW, 4MP, 65%
  new RegExp(`^\\d+(?:\\.\\d+)?(?:\\s*[x×*]\\s*\\d+(?:\\.\\d+)?){1,2}\\s*${UNIT}?$`, 'i'),    // 120x60, 600x600x10mm
  /^(?:SS|AISI|SUS)?[- ]?\d{3}[LH]?$/i,                                                  // 304, SS316L, AISI-304
  // Standards and ratings: a body or a rating prefix with its number (EN397, BS 1092-1, DN50, PN16, IP65, CAT6A, SDR11).
  /^(?:EN|BS|ISO|DIN|ASTM|IEC|UL|NFPA|ANSI|API|ASME|JIS|GB|SASO|ESMA|AS|IS|GSO|BSEN|ENISO)[- .]?\d+(?:[-:.\/]\d+)*$/i,
  /^(?:DN|PN|IP|IK|SDR|SCH|CAT|AWG|NEMA|EI|REI|HB|HRC|GU|MR|PE|PP|PPR|CL|CLASS|GRADE|GR|TYPE|SIZE|NO|BSP|NPT|SRF)[- .]?\d+(?:[.,\/x-]\d+)*[A-Z]?\+?$/i,
  // One-letter grade codes, each in its own shape: concrete C40/C40/50, steel S355, bolts M20, gauge / class G90, tubes T8,
  // lamp caps E27, fire F90, refrigerants R410A / R32, respirators N95 / P3. A letter with a long number and a suffix
  // ("M751dn") is a model, not one of these.
  /^C\d{2}(?:\/\d{2})?$/i, /^S\d{3}(?:[A-Z]{1,2}\d?)?$/, /^M\d{1,2}(?:x\d+(?:\.\d+)?)?$/i, /^G\d{1,3}$/i, /^T\d{1,2}$/i, /^E\d{2}$/i, /^F\d{2,3}$/i, /^R-?\d{2,4}[A-Za-z]{0,2}$/i, /^[NP]\d{1,3}$/i,
  /^(?:LT|P)?\d{3}\/\d{2}\s?Z?R\d{2}(?:\.\d)?$/i, /^R\d{2}(?:\.\d)?$/i,                                     // tyre sizes: 315/80R22.5, R22.5
  // Measured 10 Nov 2026 on the packs' own expert prose (13,820 sentences, none naming a model): these specification
  // shapes were read as model numbers in 493 sentences. Each is a class a customer compares on, not a seller's code.
  /^ER?\d{2,4}[A-Z]?\d?[A-Z]?(?:-\d{1,2}[A-Z]?)?$/,                                        // AWS welding classes: E6013, E71T-1, ER70S-6, E308L
  /^[A-F](?:15|125|250|400|600|900)$/,                                                     // BS EN 124 load classes: A15 ... F900
  /^A\d{3}[A-Z]?$/, /^B\d{2,3}(?:\.\d+)?$/,                                               // ASTM / ASME grades: A182, A536, B16.5
  /^\d+(?:\/\d+)?G?BASE-[A-Z0-9]+$/i, /^\d+-(?:QAM|PSK|PIN|CORE|WAY|POLE|GANG|BTU|KVA|KW|HP)$/i, // 10GBASE-T, 4096-QAM
  /^\d{4,5}-?(?:2RS1?|2RSH|2Z|ZZ|RS|Z)(?:\/C3)?$/i,                                        // ISO bearing designations: 6205-2RS
  /^ePM\d+(?:\.\d)?$/, /^(?:OM|OS)\d$/i, /^Cat\s?\d[A-Z]?$/i, /^Wi-?Fi\s?\d[A-Z]?$/i,     // filter classes, fibre and cable grades
  /^(?:TIA|EIA|IEEE|ANSI|ISO|IEC|ASME|AWS|AHRI|ASHRAE)(?:\/(?:TIA|EIA|IEC|ISO))?-?\d+(?:\.\d+)*(?:-[A-Z0-9]+)?$/i, // TIA-568.2-D, ANSI/TIA-1152-A
  /^\d+(?:st|nd|rd|th|s)$/i, /^\d+x+$/i,                                                   // 18th (edition), 2010s, 03xx (a style range)
  /^K\d+(?:\.\d+)?$/i, /^PH\d{2,3}$/i, /^\d{1,2}W-\d{2}$/i, /^(?:HFC|HFO|HCFC|FK|IG)-[\d-]+[a-z]*$/i, // sprinkler K-factors, fire cable PH120, SAE 15W-40, clean agents
  /^H\d{2,3}$/i, /^B\d{3}[A-C]$/, /^L\d{2}(?:B\d{2})?$/i, /^\d{4}(?:-\d{4})?K$/i, /^\d{1,2}U(?:-\d{1,2}U)?$/i, // tempers, rebar B500B, LED L70B50, 3000-3500K, 42U
  /^[A-G]\d{3,4}(?:\.\d+)?$/, /^(?:CW|EW|W|TG|SN|Z)\d+(?:\.\d+)?$/, /^[ADEF]H\d{2}$/, /^PE\d{2,3}(?:-RC)?$/i, /^DNV-[A-Z]{2}-[A-Z]\d+$/, // ASTM C1288 / D1785, EN wind and ring-stiffness classes, ship steel AH36, PE100-RC
  /^[A-Z][a-z]{2,}-\d{1,2}$/, /^[DY][yd]n?\d{1,2}$/i, /^(?:AC|DC)-\d{1,2}[A-Z]?$/i, /^RJ\d{2}$/i, /^[A-F]\d?-s[1-3]$/i, // Rated-1, Dyn11, AC-3, RJ45, Euroclass B-s1
  /^(?:\d{1,2}(?:G|K|MP|P))$/i, /^(?:[A-Z]\d)$/i, /^A[0-6]$/i,                                // 5G, 4K, 8MP, 1080P, A4
  /^(?:19|20)\d{2}$/,                                                                    // a year
  /^\d+[- ]?(?:seater|seat|seats|passengers?|pax|doors?|way|pin|core|pole|gang|port|ply|layer|coats?|tier|star|bay|zone|channel|burner|tray|shelf|drawer|step|speed|phase|piece|pcs)$/i, // 30-seater, 3-way, 4-core
  /^(?:K?N9[59]|FFP[123]|P[123]|KN95|EN149|EN166|EN388|EN397|EN20345|S[1-5]P?|SB|SRC)$/i,                                    // respirator / PPE classes
  /^(?:MDF|HDF|OSB|UPVC|CPVC|HDPE|LDPE|XLPE|LSZH|PVC|GRP|FRP|GRC|SWA|NYY|PPR|PEX|ABS|PU|EPDM|TPO|PIR|XPS|EPS|LED|RGB|RGBW|USB|HDMI|POE|PoE|SFP|UTP|FTP|STP|AC|DC|UPS|VRF|VRV|FCU|AHU|FAHU|DX|BTU|IPS|OLED|QLED|LCD|SSD|HDD|NVMe|DDR\d?|E0|E1|E2|F4|EI\d+)$/i,
];
const STANDARD_BODY = /(?:^|\s)(?:BS|EN|ISO|DIN|ASTM|IEC|UL|NFPA|ANSI|API|ASME|JIS|SASO|ESMA|AS|NZS|IS|GSO|BS\s+EN|EN\s+ISO|class|grade|type|size|no\.?)\s*$/i;
/** Is this token a SPECIFICATION (a grade, a size, a standard, a unit-bearing value), not a model? */
export function specCode(tok: string): boolean { const t = tok.replace(/[.,;:)]+$/, ''); return SPEC_CODE.some((re) => re.test(t)); }
// A model-like token: letters and digits together, or a long digit run (a catalogue number). Hyphen / slash segments.
const CODE_TOKEN = /(?<![\w./-])(?=[A-Za-z0-9./-]*\d)(?:[A-Za-z]{1,6}[- ]?\d{2,}[A-Za-z0-9]*(?:[-/.][A-Za-z0-9]+)*|\d{2,}[A-Za-z]{1,4}[A-Za-z0-9]*(?:[-/.][A-Za-z0-9]+)*|[A-Za-z0-9]{1,8}(?:[-/][A-Za-z0-9]{1,8}){1,4}|\d{6,12})(?![\w-])/g;
const MODEL_LABEL = /\b(?:model(?:\s*(?:no\.?|number|#))?|type\s*no\.?|art(?:icle)?\.?\s*(?:no\.?|#)?|item\s*code|product\s*code|part\s*(?:no\.?|number|#)|p\/n|sku|cat(?:alogue|alog)?\.?\s*(?:no\.?|#)|ref(?:erence)?\.?\s*(?:no\.?|#)|code\s*(?:no\.?)?|series)\s*[:#.\-]?\s*$/i;
// WHEN IS A TOKEN A MODEL CODE AND NOT A SPECIFICATION (12 Nov 2026, sales_engineer; review rounds 1-2 of the quoting fix).
// THE RULE, used by the hider and by identitiesLeft alike:
//   A. a token joined by - _ . / or a typographic hyphen that has a segment the brand table names (not a plain-word brand such
//      as "Crown" or "National", which needs a make cue) is the brand and its product: "jotun-fenomastic-5", "daikin_fxsq_100",
//      "daikin.fxsq.100". A bare brand-table name is matched in ANY case ("grohe basin mixer"); an Arabic spelling the
//      knowledge packs use is matched in Arabic script ("مكيف دايكن 3 طن").
//   B. after a type / range / series / model / item-no. label, a token is a model when it has a segment mixing two or more
//      letters with two or more digits ("XR450"), or a digit segment beside a letter segment that is NOT an ordinary word
//      ("xr-450", "eco-smart-12", "5000-pro"). An ordinary word is one the estate's vocabulary knows (GENERIC, the trade
//      words, origins, tiers, the units and SPEC_WORDS below), so "type fire-rated-60", "type double-glazed-24" and "series
//      stainless-steel-304" stay. A spec code (IP65, R32, SS304) is never a model.
// NOT SEPARABLE BY RULE, so left as they are (reported): a made-up name with no digit after a label ("type: aura-pro" reads
// like "type non-return"), a model split by spaces ("type eco smart 12", "daikin - fxsq - 100"), and brands with no Arabic
// spelling in the packs (Grohe). Hiding them would hide every hyphenated specification word after "type".
const SPEC_WORDS = new Set(`heavy duty light medium extra anti slip non moisture resistant resistance water oil solvent based voc gloss matt matte satin
  semi fire rated proof retardant flame acoustic thermal sound waterproof weatherproof uv impact low high voltage pressure grade
  return way phase core coat coats pack ply layer side sided piece tier zone stage step point mounted standing built fixed
  ton tons tr kw hp watt w mm cm m micron hour hours day days week weeks month months year years min minute minutes inch amp
  non as per spec like equivalent approved or and to
  tempered toughened laminated frosted clear reflective tinted plywood marine acrylic emulsion solid hollow flush roller shutter
  insulated galvanised galvanized anodised anodized powder coated painted primed treated finished`.split(/\s+/).filter(Boolean));
const ordinaryWord = (w: string) => w.length <= 1 || SPEC_WORDS.has(w.toLowerCase()) || isGeneric(w);
const BRAND_TOKEN = /(?<![\w./‐-―-])[A-Za-z0-9]+(?:[-_./‐-―][A-Za-z0-9]+)+(?![\w‐-―-])/g;
const HYPHEN_TOKEN = /(?<![\w./-])[A-Za-z0-9]+(?:[-_][A-Za-z0-9]+)+(?![\w-])/g;
const TYPE_LABEL = /\b(?:type|range|series|model|item\s*no\.?)\s*[:#.\-]?\s*$/i;
export function hyphenBrand(tok: string): BrandFact | null {
  const digits = /\d/.test(tok);
  for (const seg of tok.split(/[-_./‐-―]/)) {
    if (!/[A-Za-z]{2,}/.test(seg) || (seg === seg.toLowerCase() && LOWER_STOP.has(seg))) continue;
    // a short lower-case name ("lg") is a brand only beside a model code in the same token
    if (seg === seg.toLowerCase() && seg.replace(/[^a-z]/g, '').length < 5 && !digits) continue;
    const f = brandFact(seg); if (f && !f.plain) return f;
  }
  return null;
}
export const modelShaped = (tok: string) => {
  if (specCode(tok)) return false;
  const segs = tok.split(/[-_]/);
  if (segs.some((g) => /[A-Za-z]{2,}\d{2,}|\d{2,}[A-Za-z]{2,}/.test(g) && !specCode(g))) return true;
  return segs.length > 1 && segs.some((g) => /^\d+[A-Za-z]?$/.test(g)) && segs.some((g) => /^[A-Za-z]{2,}$/.test(g) && !ordinaryWord(g));
};
// Arabic spellings of brand-table names, as the knowledge packs write them (knowledge/packs/hvac.json, paints and coatings,
// waterproofing, gypsum, UPS and CCTV packs, read 12 Nov 2026). Left out because they are also ordinary Arabic words:
// جري (Gree; "running"), ميديا (Midea; "media"), ترين (Trane; inside other words).
const AR_BRANDS: Readonly<Record<string, string>> = {
  'دايكن': 'Daikin', 'ميتسوبيشي إلكتريك': 'Mitsubishi Electric', 'ميتسوبيشي الكتريك': 'Mitsubishi Electric', 'ميتسوبيشي': 'Mitsubishi', 'توشيبا': 'Toshiba',
  'هيتاشي': 'Hitachi', 'باناسونيك': 'Panasonic', 'إل جي': 'LG', 'ال جي': 'LG', 'سامسونج': 'Samsung', 'هاير': 'Haier', 'الزامل': 'Zamil',
  'جوتن': 'Jotun', 'ناشونال بينتس': 'National Paints', 'سيكا': 'Sika', 'فوسروك': 'Fosroc', 'مابي': 'Mapei', 'كناوف': 'Knauf', 'جيبروك': 'Gyproc',
  'هيكفيجن': 'Hikvision', 'شنايدر إلكتريك': 'Schneider Electric', 'شنايدر': 'Schneider Electric', 'إيشيان بينتس': 'Asian Paints',
  // also in the hvac pack, left out of round 2 because Carrier and York are plain-word brands in Latin script; in Arabic script
  // neither is an ordinary word
  'كاريير': 'Carrier', 'يورك': 'York',
  // common UAE spellings the packs do not use (review round 3), not taken from the packs
  'سامسونغ': 'Samsung', 'ناشيونال': 'National Paints', 'جروهي': 'Grohe', 'هانز جروهي': 'Hansgrohe',
};
const AR_BRAND_RE = new RegExp(`(?<![\\u0600-\\u06FF])(?:و|ب|ل|ف|ك)?(?:ال)?(${Object.keys(AR_BRANDS).sort((a, b) => b.length - a.length).map((k) => k.replace(/\s+/g, '[\\s\\u200c.]*')).join('|')})(?![\\u0600-\\u06FF])`, 'g');
/** Is `tok` (found at `at` in `text`) a model / SKU and not a spec? */
function isModel(tok: string, before: string, after: string): boolean {
  if (specCode(tok)) return false;
  // A compound adjective is a description, not a code: "90-minute", "12-month", "T3-designed", "CO2-based", "non-RJ45".
  if (/^[A-Za-z0-9.]+-[a-z]{3,}$/.test(tok) || /^[a-z]{2,}-[A-Za-z0-9]+$/.test(tok)) return false;
  // A list or range of short codes: "6E/7", "40/100G", "Cat5e/6/6A/8", "CO/NO2", "G1-G4", "M5-M6", "EN 1822/ISO".
  if (tok.includes('/') && tok.split('/').every((p) => p.length <= 5 || specCode(p))) return false;
  if (/^([A-Za-z]+)\d+-\1\d+$/.test(tok) || tok.split(/[-/]/).every((p) => specCode(p))) return false;
  if (TYPE_LABEL.test(before) && modelShaped(tok)) return true;                         // "unit type eco-smart-12"
  // "range low-voltage-24": every letter segment an ordinary word of two letters or more is a specification ("series E-200" is not)
  if (TYPE_LABEL.test(before) && /[-_]/.test(tok) && tok.split(/[-_]/).filter((g) => /[A-Za-z]/.test(g)).every((g) => /^[A-Za-z]{2,}$/.test(g) && ordinaryWord(g))) return false;
  if (/^(?:ASTM|BS|EN|ISO|DIN|IEC|UL|NFPA|ANSI|ASME|SASO|ESMA|GSO)-[A-Z]?\d/.test(tok)) return false; // "ASTM-E84": a standard
  if (STANDARD_BODY.test(before)) return false;                                         // "BS EN 1092-1", "ISO 9001"
  // A TIME AND A PHRASE ARE NOT MODELS (final audit 12 Nov 2026, M3). The comparison the customer read carried
  // generated_at "model stated (shown after reveal):44:05.271Z" (the ISO date "2026-11-11T23" taken for a code) and "priced
  // model stated (shown after reveal) working" four times for "after-6-pm working". Both exemptions are narrow (review of
  // 12 Nov 2026: a wider first draft showed "daikin-fxsq-100" and "Part no: 2211-15-00"):
  //   - a real calendar date (month 01-12, day 01-31), optionally with its hour, and never after a model label;
  //   - two or more lowercase words joined by hyphens round a short number, ending in a WORD (never a number), with no
  //     segment a brand-table name and no model label before it ("after-6-pm" yes; "grohe-euro-33", "lg-dual-inverter-18" no).
  const labelled = MODEL_LABEL.test(before);
  if (!labelled && /^\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])(?:T(?:[01]\d|2[0-3]))?$/.test(tok)) return false;
  if (!labelled && /^(?:[a-z]{2,}|\d{1,3})(?:-(?:[a-z]{2,}|\d{1,3}))+$/.test(tok) && /-[a-z]{2,}$/.test(tok)
    && (tok.match(/(?:^|-)[a-z]{2,}(?=-|$)/g) || []).length >= 2 && !tok.split('-').some((p) => brandFact(p))) return false;
  if (/^\d+$/.test(tok)) {                                                               // a bare number is a model only when long and not a figure
    if (tok.length < 6) return false;
    if (/(?:AED|Dhs?|USD|\$|qty|quantity|x)\s*$/i.test(before) || /^\s*(?:AED|Dhs?|nos|pcs|units?|m2|sqm|kg|%)/i.test(after)) return false;
    return true;
  }
  if (/^\d+(?:[-/]\d+)+$/.test(tok)) return MODEL_LABEL.test(before);                    // 10-14 (days), 1/2 (inch), dates: only when labelled
  if (/^\d{1,3}[-/][A-Za-z]{1,4}$|^[A-Za-z]{1,4}[-/]\d{1,3}$/.test(tok) && !MODEL_LABEL.test(before)) return false; // "3-way", "G-90"
  return true;
}

// ---------------------------------------------------------------------------------------------
// Generic product words: where a brand's product-line run ends ("Grohe Eurosmart | basin mixer").
// ---------------------------------------------------------------------------------------------
const GENERIC = new Set(`mixer mixers tap taps faucet faucets basin basins shower showers toilet wc closet cistern bidet urinal sink sinks valve valves pump pumps
  motor motors cable cables wire wires panel panels board boards sheet sheets tile tiles porcelain ceramic granite marble stone paint paints primer coating
  door doors window windows glass glazing frame frames profile profiles system systems unit units split ducted cassette chiller chillers fan fans heater
  heaters inverter inverters battery batteries module modules charger chargers generator generators engine engines tyre tyres tire tires bus buses coach
  van vans truck trucks car cars vehicle vehicles laptop laptops desktop printer printers copier copiers monitor monitors phone phones camera cameras
  recorder switch switches router routers server servers licence licences license licenses software subscription chair chairs desk desks table tables
  sofa sofas cabinet cabinets shelf shelving rack racks fitting fittings fixture fixtures luminaire luminaires lamp lamps light lights lighting downlight
  spotlight driver drivers sensor sensors detector detectors alarm alarms helmet helmets glove gloves boot boots shoe shoes vest vests mask masks
  respirator goggles harness drill drills grinder grinders saw saws tool tools kit kits set sets oven ovens fryer dishwasher refrigerator fridge freezer
  machine machines dispenser dispensers compressor compressors filter filters membrane membranes sealant adhesive grout mortar plaster gypsum insulation
  pipe pipes tube tubes hose hoses box boxes carton cartons bag bags bottle bottles film roll rolls label labels pallet pallets drum drums container
  chemical chemicals detergent cleaner cleaners solution series range collection line edition version model type grade class standard premium
  economy original genuine new white black grey gray silver chrome matt matte gloss glossy satin brushed polished stainless steel aluminium aluminum
  wooden wood oak walnut teak mdf laminate vinyl carpet rug curtain blind blinds fabric leather wall floor ceiling roof indoor outdoor single double
  triple wall-mounted floor-standing mounted concealed exposed thermostatic manual automatic electric electronic digital smart wireless solar led
  with and for of in the a an to by from including incl complete supply installation install installed delivery fixing accessories spare spares part parts`.split(/\s+/).filter(Boolean));
const isGeneric = (w: string) => { const l = w.toLowerCase().replace(/[^a-z0-9-]/g, ''); return !l || GENERIC.has(l) || GENERIC.has(l.replace(/s$/, '')) || tradeWord(l) || originOf(w) != null || tierOf(w) != null; };

// ---------------------------------------------------------------------------------------------
// The brand matcher: every name in the table, longest first, as written / Title Case / UPPER CASE.
// ---------------------------------------------------------------------------------------------
const rx = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const variants = (name: string) => [...new Set([name, name.toUpperCase(), name.replace(/\b([a-z])/g, (c) => c.toUpperCase())])];
const W = "[A-Za-z0-9À-ÿ]";
const BRAND_RE: RegExp = (() => {
  const alts = [...FACTS.values()].sort((a, b) => b.name.length - a.name.length).flatMap((f) => variants(f.name)).map((v) => rx(v).replace(/\s+/g, '\\s+'));
  return new RegExp(`(?<!${W})(?:${alts.join('|')})(?!${W})`, 'g');
})();
// A BRAND IN ANOTHER CASE (review rounds 2-3 of 12 Nov 2026). Round 2 matched every name in any case and rewrote ordinary
// words that are also brand-table names ("PVC union 2 inch", "ups system 10 kVA", "20 pax": 108 strings). Now:
//   - an odd mixed case ("dAiKiN", "gRoHe") is a brand as written: nobody writes an ordinary word that way;
//   - ALL LOWER CASE is a brand only when the name has five letters or more and is not an ordinary word: not on LOWER_STOP
//     and not a word the hider's own vocabulary knows (GENERIC, trade words, SPEC_WORDS). LOWER_STOP is data: the 42 names
//     the repository's prose writes in lower case (knowledge/, docs/, messages/, src/, supabase/functions, scripts; tests and
//     fixtures excluded; harvested 12 Nov 2026) and every collision the corpus showed (quote_generalise.corpus.json).
//     Of 1,466 non-plain names of five letters or more, LOWER_STOP excludes the ones listed below.
//   Plain-word brands keep needing their make cue in every case.
const LOWER_STOP = new Set(`adidas apollo armstrong berry canny canon century collins domino edwards emerge fender genie giant google grove
  honor hunter linkedin mercury microsoft mobil monarch naffco navigator norton notifier oasis paradox parrot peninsula sabre scott sigma
  speck supreme thorn tiktok union weber wilson zodiac stanley fisher`.split(/\s+/).filter(Boolean));
const ANY_CASE_RE: RegExp = (() => {
  const alts = [...FACTS.values()].filter((f) => !f.plain).sort((a, b) => b.name.length - a.name.length).map((f) => rx(f.name).replace(/\s+/g, '\\s+'));
  return new RegExp(`(?<!${W})(?:${alts.join('|')})(?!${W})`, 'gi');
})();
/** Brand names in `text` the way the hider reads them (BRAND_RE as written; ANY_CASE_RE under the rule above). */
function brandMatches(text: string): { at: number; s: string }[] {
  const out: { at: number; s: string }[] = [];
  for (const m of text.matchAll(BRAND_RE)) out.push({ at: m.index ?? 0, s: m[0] });
  for (const m of text.matchAll(ANY_CASE_RE)) {
    const at = m.index ?? 0, w = m[0];
    if (out.some((o) => o.at === at)) continue;
    // lower case, or a capitalised word ("Sqm" for the acronym SQM): the ordinary-word rule; ALL CAPS or an odd case: as written
    const lower = w === w.toLowerCase() || (w[0] === w[0].toUpperCase() && w.slice(1) === w.slice(1).toLowerCase());
    if (lower && (w.replace(/[^a-z]/g, '').length < 5 || LOWER_STOP.has(w) || w.split(/\s+/).every((x) => ordinaryWord(x)))) continue;
    out.push({ at, s: w });
  }
  return out;
}
// A plain-word brand ("Carrier", "Continental") is a make only beside a make cue or a model code.
const MAKE_CUE_BEFORE = /(?:\b(?:brand|make|manufacturer|mfr|maker|made\s+by|by|from|approved)\s*[:\-]?\s*|[(/]\s*)$/i;
const MAKE_CUE_AFTER = /^\s*(?:brand|make|®|™|\(|[A-Z0-9]{0,4}-?\d)/;

type Hit = { start: number; end: number; generic: string; kind: Replacement['kind']; term: string };

/** The product-line words and model codes that follow a brand: "Grohe| Eurosmart Cosmopolitan 33265003| basin mixer". */
function lineRunAfter(text: string, from: number): number {
  let end = from; let words = 0;
  const re = /\s*([A-Za-z0-9][A-Za-z0-9+./-]*[™®]?|[™®])/y;
  for (;;) {
    re.lastIndex = end; const m = re.exec(text); if (!m) break;
    const tok = m[1].replace(/[.,;:]+$/, '');
    if (/^[™®]$/.test(tok)) { end = re.lastIndex; continue; }
    if (specCode(tok)) break;                                                            // a grade or a size ends the product line
    // A code with letters and digits, or a catalogue number of four digits or more; a short bare number ("5 TR",
    // "2 coats") is a quantity or a capacity and ends the run.
    const code = /\d/.test(tok) && /^[A-Za-z0-9./-]+$/.test(tok) && (/[A-Za-z]/.test(tok) || /^\d{4,}$/.test(tok) || /^\d{2,}(?:[-/]\d{2,})+$/.test(tok)) && !specCode(tok);
    const name = /^[A-Z]/.test(tok) && !isGeneric(tok) && words < 3;
    if (!code && !name) break;
    if (name) words++;
    end = end + m[0].length - (m[1].length - tok.length);
  }
  return end;
}

function brandHits(text: string, ctx: GeneraliseCtx): Hit[] {
  const hits: Hit[] = [];
  for (const m of brandMatches(text).map((x) => Object.assign([x.s], { index: x.at }))) {
    const at = m.index ?? 0; const f = brandFact(m[0]); if (!f) continue;
    const before = text.slice(Math.max(0, at - 30), at), after = text.slice(at + m[0].length, at + m[0].length + 20);
    if (f.plain && !MAKE_CUE_BEFORE.test(before) && !MAKE_CUE_AFTER.test(after)) continue;
    const end = lineRunAfter(text, at + m[0].length);
    const stated = tierOf(text.slice(Math.max(0, at - 25), end + 25));
    const g = genericBrand(f.name, stated);
    hits.push({ start: at, end, generic: g.en, kind: 'brand', term: text.slice(at, end) });
  }
  // A hyphenated token naming a brand ("jotun-fenomastic-5", "Daikin-FXSQ-100"): the brand's generic, and its model withheld.
  for (const m of text.matchAll(AR_BRAND_RE)) {
    const at = (m.index ?? 0) + m[0].length - m[1].length;
    hits.push({ start: at, end: at + m[1].length, generic: genericBrand(AR_BRANDS[m[1].replace(/[\s\u200c.]+/g, ' ')] ?? Object.entries(AR_BRANDS).find(([k]) => k.replace(/\s+/g, '') === m[1].replace(/[\s\u200c.]+/g, ''))?.[1] ?? m[1]).ar, kind: 'brand', term: m[1] });
  }
  for (const m of text.matchAll(BRAND_TOKEN)) {
    const f = hyphenBrand(m[0]); if (!f) continue;
    const at = m.index ?? 0;
    const g0 = genericBrand(f.name, tierOf(text.slice(Math.max(0, at - 25), at + m[0].length + 25))).en;
    // A brand inside ordinary wording keeps the wording ("non-daikin equivalent" -> "non-premium Japanese brand equivalent");
    // a brand with a model beside it becomes the brand's generic and the model is withheld ("daikin-fxsq-100").
    const parts = m[0].split(/([-_./‐-―])/);
    const wordsOnly = parts.every((x, k) => k % 2 === 1 || brandFact(x)?.name === f.name || ordinaryWord(x));
    const g = wordsOnly ? parts.map((x, k) => (k % 2 === 0 && brandFact(x)?.name === f.name ? g0 : x)).join('') : g0 + (/\d|[A-Za-z]{2,}/.test(parts.filter((x, k) => k % 2 === 0 && brandFact(x)?.name !== f.name).join('')) ? ', ' + MODEL_HIDDEN.en : '');
    hits.push({ start: at, end: at + m[0].length, generic: g, kind: 'brand', term: m[0] });
  }
  // The quote's OWN brand / model values (a make no table knows, a model with spaces: "CR 10-5").
  for (const [vals, kind] of [[ctx.brands, 'brand'], [ctx.models, 'model']] as const) {
    for (const v of (vals || []).map((x) => String(x ?? '').trim()).filter((x) => x.length >= 2 && !/^(?:n\/?a|none|-+|generic|unbranded|local|standard|equivalent|approved equivalent)$/i.test(x))) {
      if (kind === 'brand' && v.length < 3) continue;
      const re = new RegExp(`(?<!${W})${rx(v).replace(/\s+/g, '\\s+')}(?!${W})`, 'gi');
      for (const m of text.matchAll(re)) {
        const at = m.index ?? 0;
        const end = kind === 'brand' ? lineRunAfter(text, at + m[0].length) : at + m[0].length;
        const g = kind === 'brand' ? genericBrand(v, tierOf(text)).en : MODEL_HIDDEN.en;
        hits.push({ start: at, end, generic: g, kind, term: text.slice(at, end) });
      }
    }
  }
  return hits;
}

function productLineHits(text: string): Hit[] {
  const hits: Hit[] = [];
  // Name(TM) / Name(R): a registered product name is a product line by its own declaration.
  for (const m of text.matchAll(/(?<![A-Za-z0-9])([A-Z][A-Za-z0-9+-]{1,24}(?:\s[A-Z][A-Za-z0-9+-]{1,24}){0,2})\s?(?:™|®|\(TM\)|\(R\))/g)) {
    hits.push({ start: m.index ?? 0, end: (m.index ?? 0) + m[0].length, generic: 'proprietary', kind: 'product_line', term: m[0] });
  }
  // "<Name> series / range / collection": the name is the product line ("Eurosmart series"). Not "line": "compare BOQs
  // line by line" read "BOQs" as a product line on the packs' own prose.
  for (const m of text.matchAll(/(?<![A-Za-z0-9])((?:[A-Z][A-Za-z0-9+-]{2,24}\s){1,2})(?=(?:series|range|collection|edition|family)\b)/g)) {
    const name = m[1].trim(); if (name.split(/\s+/).every((w) => isGeneric(w) || specCode(w))) continue;
    hits.push({ start: m.index ?? 0, end: (m.index ?? 0) + m[1].trimEnd().length, generic: 'proprietary', kind: 'product_line', term: name });
  }
  // A quoted name ('AquaPro', "Silverline"): distinctive wording put in quotes is a name.
  // Every word capitalised, at most three: a product name, not a quoted phrase ("AC for a 4-bedroom villa", "T3 rated").
  for (const m of text.matchAll(/(['"‘“])([A-Z][A-Za-z0-9+-]{2,20}(?: [A-Z][A-Za-z0-9+-]{1,20}){0,2})(['"’”])/g)) {
    if (m[2].split(/\s+/).every((w) => isGeneric(w) || specCode(w)) || /^(?:Tax|Invoice|Class|Civil|Defence|Options|All-inclusive|Drones|Low-E|Supply|Supplier)\b/.test(m[2])) continue;
    hits.push({ start: m.index ?? 0, end: (m.index ?? 0) + m[0].length, generic: 'proprietary', kind: 'product_line', term: m[2] });
  }
  return hits;
}

function modelHits(text: string): Hit[] {
  const hits: Hit[] = [];
  CODE_TOKEN.lastIndex = 0;
  for (const m of text.matchAll(CODE_TOKEN)) {
    const at = m.index ?? 0; const tok = m[0]; const before = text.slice(Math.max(0, at - 24), at); const after = text.slice(at + tok.length, at + tok.length + 10);
    if (!isModel(tok, before, after)) continue;
    // A labelled model keeps its label: "Model: XR-450" -> "Model: model stated (shown after reveal)" reads twice, so the label goes with it.
    const lab = before.match(MODEL_LABEL); const start = lab ? at - lab[0].length : at;
    hits.push({ start, end: at + tok.length, generic: MODEL_HIDDEN.en, kind: 'model', term: text.slice(start, at + tok.length).trim() });
  }
  // A model-shaped token after a type / range / series / model label, whatever its segment lengths ("type aquaflowmax-12").
  for (const m of text.matchAll(HYPHEN_TOKEN)) {
    const at = m.index ?? 0; if (!TYPE_LABEL.test(text.slice(Math.max(0, at - 24), at)) || !modelShaped(m[0])) continue;
    hits.push({ start: at, end: at + m[0].length, generic: MODEL_HIDDEN.en, kind: 'model', term: m[0] });
  }
  // "model JUMPER3", "ref DR-2190", "item code BX-4402": a labelled token with a digit, whatever its shape.
  for (const m of text.matchAll(/\b(?:model|type\s*no\.?|ref(?:erence)?|item\s*code|product\s*code|code|art\.|article\s*(?:no\.?|#)|sku|part\s*(?:no\.?|number)|p\/n|cat(?:alogue)?\.?\s*no\.?)\s*(?:no\.?|number|#)?\s*[:#]?\s*([A-Za-z0-9][A-Za-z0-9./-]*\d[A-Za-z0-9./-]*)/gi)) {
    if (specCode(m[1])) continue;
    hits.push({ start: m.index ?? 0, end: (m.index ?? 0) + m[0].length, generic: MODEL_HIDDEN.en, kind: 'model', term: m[0] });
  }
  // A long code mixing letters and digits with no separator ("AER1B23DW", "21ML0035AD"): a catalogue number.
  for (const m of text.matchAll(/(?<![\w./-])(?=(?:[A-Za-z]*\d){2})(?=(?:\d*[A-Za-z]){2})[A-Za-z0-9]{6,16}(?![\w-])/g)) {
    if (specCode(m[0])) continue;
    hits.push({ start: m.index ?? 0, end: (m.index ?? 0) + m[0].length, generic: MODEL_HIDDEN.en, kind: 'model', term: m[0] });
  }
  // "Model: Aquaflo Pro" (a model with no digit) after an explicit model label.
  for (const m of text.matchAll(/\b(?:model(?:\s*(?:no\.?|number))?|sku|part\s*no\.?|p\/n|item\s*code|product\s*code)\s*[:#]\s*([A-Z][A-Za-z0-9+-]{2,}(?:\s[A-Z0-9][A-Za-z0-9+-]+){0,2})/gi)) {
    // The label is read in any case; the model it names starts with a capital or a digit ("model: not stated" is not one).
    if (!/^[A-Z0-9]/.test(m[1]) || /^(?:The|Not|None|As|To|TBC|TBA|N\/A)\b/.test(m[1])) continue;
    hits.push({ start: m.index ?? 0, end: (m.index ?? 0) + m[0].length, generic: MODEL_HIDDEN.en, kind: 'model', term: m[0] });
  }
  return hits;
}

// THE SUPPLIER'S NAME AS IT WRITES ITSELF IN A DESCRIPTION: "Cedar Line signature profile" for "Cedar Line Joinery LLC".
// knownNameRe needs every word of the registered name; a supplier's own text usually drops the trade words that follow
// the distinctive part. The core is the leading run of words before the first trade / generic word, kept only when it
// carries a distinctive word (four letters or more, not a place or a common business word).
const NOT_DISTINCTIVE = new Set(['zz', 'demo', 'al', 'el', 'the', 'and', 'bin', 'abu', 'gulf', 'emirates', 'emirati', 'dubai', 'sharjah', 'abu', 'dhabi', 'arabian', 'arabia', 'middle', 'east',
  'national', 'international', 'global', 'united', 'royal', 'golden', 'star', 'new', 'modern', 'first', 'best', 'smart', 'prime', 'premium', 'general', 'total', 'city', 'world', 'group']);
const BUSINESS_WORD = /^(?:trading|trdg|contracting|joinery|tiles|air|conditioning|pumps|solar|energy|packaging|industries|industry|engineering|engineers|consultants|consultancy|advertising|security|services|service|cleaning|events|event|management|furniture|kitchen|equipment|medical|ppe|auto|parts|office|systems|it|solutions|passenger|transport|power|generators|chem|chemicals|accounting|guard|sanitary|establishment|est|company|co|llc|fze|fzco|fzc|dmcc|factory|industrial|technical|technologies|technology|electromechanical|electrical|mechanical|steel|aluminium|glass|marble|stone|wood|metal|plastic|paints|interiors|decor|design|projects|enterprises|supplies|supply|distribution|logistics|shipping|cargo|marine|oilfield|building|materials|tools|hardware|lighting|electronics|computers|printing|press|media)$/i;
function coreNameRe(name: unknown): RegExp | null {
  const words = String(name ?? '').replace(/[—–-]+/g, ' ').replace(/[^A-Za-z0-9&' ]+/g, ' ').split(/\s+/).filter(Boolean);
  const core: string[] = [];
  for (const w of words) { if (BUSINESS_WORD.test(w)) break; core.push(w); }
  if (!core.length || core.length === words.length) return null;                       // the full name: knownNameRe has it
  if (!core.some((w) => w.length >= 4 && !NOT_DISTINCTIVE.has(w.toLowerCase()))) return null;
  return new RegExp(`(?<!${W})${core.map(rx).join('[\\s.,_-]*')}(?!${W})`, 'gi');
}

/** Apply non-overlapping hits, the earliest and then the longest first. */
function apply(text: string, hits: Hit[], out: Replacement[]): string {
  hits.sort((a, b) => a.start - b.start || b.end - a.end);
  let res = ''; let at = 0;
  for (const h of hits) {
    if (h.start < at) continue;
    let g = h.generic;
    // Do not say a tier or an origin twice: "premium Grohe mixer" -> "premium German brand mixer".
    const prev = res + text.slice(at, h.start);
    const lastWord = (prev.match(/([A-Za-z-]+)\s*$/) || [])[1];
    if (lastWord && g.toLowerCase().startsWith(lastWord.toLowerCase() + ' ')) g = g.slice(lastWord.length + 1);
    // ...nor before it: "Aquaflo premium shower set" -> "premium branded shower set", not "premium branded premium ...".
    const nextWord = (text.slice(h.end).match(/^\s*([A-Za-z-]+)/) || [])[1];
    if (nextWord && g.toLowerCase().startsWith(nextWord.toLowerCase() + ' ')) { g = g.slice(nextWord.length + 1); res = prev + nextWord + ' ' + g; at = h.end + (text.slice(h.end).match(/^\s*[A-Za-z-]+/) || [''])[0].length; if (!out.some((r) => r.term === h.term)) out.push({ term: h.term, generic: h.generic, kind: h.kind }); continue; }
    res = prev + g; at = h.end;
    if (!out.some((r) => r.term === h.term)) out.push({ term: h.term, generic: h.generic, kind: h.kind });
  }
  return (res + text.slice(at)).replace(/[ \t]{2,}/g, ' ');
}

/**
 * The text a customer may read before the reveal: identity shapes out, the supplier's name -> "the supplier",
 * every brand -> "<tier> <origin> brand", every model / SKU -> "model stated (shown after reveal)", every
 * proprietary product line -> "proprietary". `replaced` lists what was taken out (for the supplier's own review).
 */
export function generaliseText(text: unknown, ctx: GeneraliseCtx = {}): { text: string; replaced: Replacement[] } {
  const replaced: Replacement[] = [];
  let s = String(text ?? ''); if (!s.trim()) return { text: s, replaced };
  const before = s;
  // The supplier's own name first, so "Al Noor Trading premium range" reads "the supplier's premium range" rather
  // than a removal mark; then every other identity shape the shared list knows.
  for (const n of (ctx.supplierNames || [])) {
    for (const re of [knownNameRe(n, { fragments: true }), coreNameRe(n)]) {
      if (!re) continue;
      s = s.replace(re, (m) => { replaced.push({ term: m, generic: SUPPLIER_WORD.en, kind: 'supplier_name' }); return SUPPLIER_WORD.en; });
    }
  }
  s = scrubIdentityText(s, (m: string) => { if (String(m).trim().length >= 3) replaced.push({ term: String(m).trim(), generic: '[removed]', kind: 'contact' }); return '[removed]'; });
  s = apply(s, [...brandHits(s, ctx), ...productLineHits(s), ...modelHits(s)], replaced);
  return { text: s === before ? before : s.trim(), replaced };
}

/** A request or quote line's PRODUCT words: origin phrases, "or equivalent" and brand names taken out, so two lines are
 *  matched on what they are ("Solar PV panels 550 W") and not diluted by where they come from or whose they are. */
export function productWords(text: unknown): string {
  return String(text ?? '').replace(BRAND_RE, ' ').replace(new RegExp(ORIGIN_CUE.source, 'gi'), ' ')
    .replace(/(?<![A-Za-z])[A-Z][A-Za-z.]+\s*[- ]?\s*(?:origin|made|make)\b/g, ' ').replace(new RegExp(ADJ_FORM.source, 'g'), ' ')
    .replace(/\bor\s+(?:approved\s+)?(?:equivalent|equal|similar)\b/gi, ' ').replace(/\s{2,}/g, ' ').trim();
}

const BRAND_KEYS = /^(?:brand|make|manufacturer|brand_name|make_brand)$/i;
const MODEL_KEYS = /^(?:model|model_no|model_number|product_code|part_no|part_number|sku|item_code|catalogue_no|cat_no)$/i;
/** A brand value as the customer reads it before the reveal. */
export function generaliseBrandValue(v: unknown, statedTier: Tier | null = null, lang: 'en' | 'ar' = 'en'): string | null {
  const s = String(v ?? '').trim(); if (!s) return v == null ? null : s;
  if (/^(?:n\/?a|none|-+|generic|unbranded|no brand|local(?:ly made)?|standard)$/i.test(s)) return s;
  const g = genericBrand(s, statedTier ?? tierOf(s)); return lang === 'ar' ? g.ar : g.en;
}
export function generaliseModelValue(v: unknown, lang: 'en' | 'ar' = 'en'): string | null {
  const s = String(v ?? '').trim(); if (!s) return v == null ? null : s;
  if (/^(?:n\/?a|none|-+|not stated)$/i.test(s)) return s;
  return lang === 'ar' ? MODEL_HIDDEN.ar : MODEL_HIDDEN.en;
}

/** The brand / model values a quote carries (columns and keyed specs), for the context of its own text. */
// deno-lint-ignore no-explicit-any
export function ctxOfQuote(items: any[] | null | undefined, supplierNames: (string | null | undefined)[] = []): GeneraliseCtx {
  const brands: string[] = [], models: string[] = [];
  for (const it of items || []) {
    if (!it || typeof it !== 'object') continue;
    if (it.brand) brands.push(String(it.brand));
    if (it.model) models.push(String(it.model));
    const sp = it.spec && typeof it.spec === 'object' ? it.spec : {};
    for (const [k, v] of Object.entries(sp)) { if (typeof v !== 'string') continue; if (BRAND_KEYS.test(k)) brands.push(v); else if (MODEL_KEYS.test(k)) models.push(v); }
  }
  return { supplierNames, brands, models };
}
export function mergeCtx(...cs: GeneraliseCtx[]): GeneraliseCtx {
  return { supplierNames: cs.flatMap((c) => c.supplierNames || []), brands: cs.flatMap((c) => c.brands || []), models: cs.flatMap((c) => c.models || []) };
}

/** A line's country of origin as the customer may read it: the COUNTRY only, from this file's ORIGIN list, or '' (review of
 *  12 Nov 2026: "Country of origin: Grohe Germany" reached the customer as written). A brand next to the country never passes. */
export function countryOnly(v: unknown): string {
  const code = originOf(String(v ?? '').replace(BRAND_RE, ' '));
  return code === 'EU' ? 'Europe' : code ? (ORIGIN[code]?.country ?? '') : '';
}
/** One quote line as the customer reads it before the reveal. country_of_origin is kept as its country only (countryOnly). */
// deno-lint-ignore no-explicit-any
export function generaliseLine<T extends Record<string, any>>(line: T, ctx: GeneraliseCtx = {}, replaced: Replacement[] = []): T {
  const out: Record<string, unknown> = { ...line };
  const own = mergeCtx(ctx, ctxOfQuote([line]));
  const statedTier = tierOf([line.description, line.specification, line.notes].join(' '));
  for (const k of Object.keys(out)) {
    const v = out[k];
    if (BRAND_KEYS.test(k) && typeof v === 'string') { const g = generaliseBrandValue(v, statedTier); if (g !== v) replaced.push({ term: v, generic: String(g), kind: 'brand' }); out[k] = g; }
    else if (MODEL_KEYS.test(k) && typeof v === 'string') { const g = generaliseModelValue(v); if (g !== v) replaced.push({ term: v, generic: String(g), kind: 'model' }); out[k] = g; }
    else if (/^(?:description|desc|specification|notes|customer_description|item)$/.test(k) && typeof v === 'string') { const r = generaliseText(v, own); replaced.push(...r.replaced); out[k] = r.text; }
    else if ((k === 'spec' || k === 'specs') && v && typeof v === 'object') out[k] = generaliseDeep(v, own, {}, replaced);
    else if (k === 'country_of_origin' && typeof v === 'string') { const c = countryOnly(v); if (c !== v) replaced.push({ term: v, generic: c, kind: 'brand' }); out[k] = c; }
  }
  return out as T;
}

const QUOTE_TEXT = ['notes', 'lead_time', 'validity', 'payment_terms', 'warranty', 'scope', 'conditions', 'exclusions', 'description_anonymized'];
/** A quote row's free-text terms as the customer reads them before the reveal. */
// deno-lint-ignore no-explicit-any
export function generaliseQuoteTerms<T extends Record<string, any>>(q: T, ctx: GeneraliseCtx = {}, replaced: Replacement[] = []): T {
  const out: Record<string, unknown> = { ...q };
  for (const k of QUOTE_TEXT) if (typeof out[k] === 'string') { const r = generaliseText(out[k], ctx); replaced.push(...r.replaced); out[k] = r.text; }
  if (out.terms_spec && typeof out.terms_spec === 'object') out.terms_spec = generaliseDeep(out.terms_spec, ctx, {}, replaced);
  return out as T;
}

// Keys whose values are ours (codes, flags, labels, ids) or the customer's own request: never rewritten.
const KEEP_KEYS = new Set(['quote_id', 'id', 'label', 'label_en', 'label_ar', 'supplier_letter', 'marker', 'flag', 'code', 'key', 'attr', 'source', 'requested',
  'requested_source', 'request_line', 'requested_items', 'status', 'engine', 'unit', 'unit_ar', 'lang', 'currency', 'vat_treatment', 'option_no', 'trade', 'trade_en', 'trade_ar',
  'deliberation_id', 'state', 'kind', 'type', 'country_of_origin', 'origin', 'tier', 'review_notes_codes', 'quote_ref', 'rfq_no', 'disclaimer', 'review_note']);
/**
 * Walk any JSON the customer receives (a comparison, a technical table, a roster) and generalise every string the
 * supplier's words can reach. An attribute row for brand / model (code or key 'brand' / 'model') has its cells'
 * values generalised as values of that kind, so "Grohe" becomes "premium German brand" and "33265003" is withheld.
 */
export function generaliseDeep<T>(v: T, ctx: GeneraliseCtx = {}, opts: { keep?: Set<string> } = {}, replaced: Replacement[] = []): T {
  const keep = opts.keep ?? KEEP_KEYS;
  // deno-lint-ignore no-explicit-any
  const walk = (x: any, key: string | null, as: 'brand' | 'model' | null): any => {
    if (typeof x === 'string') {
      if (key === 'country_of_origin') return countryOnly(x);   // a country, never the words beside it
      if (key && keep.has(key)) return x;
      if (as === 'brand' || (key && BRAND_KEYS.test(key))) { const g = generaliseBrandValue(x); if (g !== x) replaced.push({ term: x, generic: String(g), kind: 'brand' }); return g; }
      if (as === 'model' || (key && MODEL_KEYS.test(key))) { const g = generaliseModelValue(x); if (g !== x) replaced.push({ term: x, generic: String(g), kind: 'model' }); return g; }
      const r = generaliseText(x, ctx); replaced.push(...r.replaced); return r.text;
    }
    if (Array.isArray(x)) return x.map((y) => walk(y, key, as));
    if (x && typeof x === 'object') {
      const attr = String(x.code ?? x.key ?? x.attr ?? '');
      const kind: 'brand' | 'model' | null = BRAND_KEYS.test(attr) ? 'brand' : MODEL_KEYS.test(attr) ? 'model' : null;
      const o: Record<string, unknown> = {};
      for (const [k, y] of Object.entries(x)) {
        // the cells / values of a brand or model attribute row carry that attribute's values
        const cellAs = kind && (k === 'cells' || k === 'values') ? kind : (k === 'value' ? as : null);
        o[k] = walk(y, k, cellAs ?? (k === 'value' ? as : null));
      }
      return o;
    }
    return x;
  };
  return walk(v, null, null) as T;
}

/** Every identity a text still carries after generalisation, for the corpus measurement: brand names the table knows,
 *  the given own terms, and identity shapes. Empty means nothing identifying is left. */
export function identitiesLeft(text: unknown, ownTerms: string[] = []): string[] {
  // ONE RULE (review round 3): what is left is exactly what the hider would still replace: its brand, product-line and model
  // hits on this text (brandHits, productLineHits, modelHits, with no quote context), plus the given own terms. The customer-
  // door check and the hider therefore cannot disagree. A plain-word brand ("Crown") counts only where the hider takes it.
  const s = String(text ?? ''); const left: string[] = [];
  scrubIdentityText(s, (m: string) => { if (String(m).trim().length >= 3) left.push(String(m).trim()); return ''; });   // contact shapes: e-mail, URL, phone
  for (const h of [...brandHits(s, {}), ...productLineHits(s), ...modelHits(s)]) left.push(s.slice(h.start, h.end).trim());
  for (const m of s.matchAll(AR_BRAND_RE)) left.push(m[1]);
  for (const t of ownTerms) if (t && t.length >= 3 && s.toLowerCase().includes(t.toLowerCase())) left.push(t);
  return [...new Set(left.filter(Boolean))];
}
