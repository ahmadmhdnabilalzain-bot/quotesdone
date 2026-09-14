// line_specs/model.ts — what every line of a quotation must state, per trade, in English and Arabic.
//
// THE RULE (founder, 14 Sep 2026, verbatim in public.founder_instruction #78): "in fitout quotation
// for example, we need to make sure that exact specs of the material used, what type of wood, what
// thickness, etc. this is a rule, and if a supplier submits missing information, then the sales agent
// will notify him that the quotation will be on hold until he mentions the exact details".
//
// WHAT WAS THERE BEFORE (measured on production 14 Sep 2026):
//   * category_specs (56 rows) holds the CUSTOMER'S intake questions ("which flooring?", "area in
//     sqm?"), not what a supplier's line must state.
//   * category_quote_specs (141 rows, 44 spec groups) holds 3-5 regexes per group matched against the
//     WHOLE quote as one text blob, English only, no unit, no Arabic label. A quote that says "18mm"
//     once passes "thickness" for every line it has.
//   * fn_quote_structured_score asks only whether brand+model and a specification string exist.
//   None of the three can say "line 3, the wardrobe, does not state the board thickness".
//
// WHAT THIS IS. One catalogue, keyed by the SAME trade vocabulary fn_quote_spec_group already returns
// (so the database's spec groups and these trades are one set of names), of LINE-level attributes:
// code, EN and AR label, type and unit, mandatory or trade-specific extra, and a deterministic reader
// (regex + lexicon, English and Arabic) that fills what the supplier's own text states and returns
// null otherwise. Nothing here calls a model (the OpenRouter hold) and nothing here guesses: a value
// the text does not state is missing, and a vague value ("TBD", "as per drawing", "equivalent") is
// treated as not stated, because "exact" is the whole point of the rule.
//
// WHY IN CODE AND NOT IN category_specs. The readers are regular expressions with Arabic lexicons;
// the portal, the hold decision and the comparison all import them from here. A copy in a table would
// be a second source that drifts. The trade keys ARE the database's spec groups, and a test pins that
// every category in category_specs and src/content/categories.json resolves to a trade here.

export type AttrType = 'text' | 'number';
export type Attr = {
  code: string; en: string; ar: string; type: AttrType;
  unit?: string; unit_ar?: string; mandatory: boolean;
  /** Suggested values for the portal's list; any exact value is accepted. */
  options?: string[];
  /** The attribute is asked only of lines whose text matches (e.g. capacity only of AC units). */
  applies?: RegExp;
  /** ...and never of lines matching this (e.g. plank size is not asked of an epoxy floor). */
  except?: RegExp;
  find: (text: string) => string | null;
};
export type Trade = { code: string; en: string; ar: string; kw: RegExp; attrs: Attr[] };

// ---------------------------------------------------------------------------------------------
// Readers. Each returns the value as the supplier stated it (canonicalised where a lexicon exists).
// ---------------------------------------------------------------------------------------------
const AR_DIGITS = /[٠-٩]/g;
export const normText = (s: string) => String(s ?? '').replace(AR_DIGITS, (d) => String(d.charCodeAt(0) - 0x660)).replace(/[٫]/g, '.').replace(/\s+/g, ' ').trim();

/** A value that is not a specification. Refused from extraction and from the portal alike. */
export const VAGUE = /^(n\/?a|na|nil|none|tbd|tba|tbc|-+|\?+|x+|same|any|standard|std|equivalent|approved equivalent|or equivalent|equal|as per.*|as required|as approved|to be confirmed|to be advised|later|غير محدد|حسب.*|مماثل|ما يعادله|يحدد لاحقا|يحدد لاحقاً|لاحقا|لاحقاً)$/i;
const clean = (v: string | null | undefined) => {
  const s = normText(String(v ?? '')).replace(/^[\s:–\-=]+|[\s,;.]+$/g, '');
  return s && !VAGUE.test(s) && s.length <= 80 ? s : null;
};

/** First lexicon entry whose pattern matches wins; order entries most-specific first. */
const oneOf = (list: [string, RegExp][]) => (t: string) => { for (const [v, re] of list) if (re.test(t)) return v; return null; };
/** A number captured by the first group of the first matching pattern. */
const numFrom = (...res: RegExp[]) => (t: string) => { for (const re of res) { const m = t.match(re); const g = m && (m.slice(1).find((x) => x != null)); if (g && Number(g) > 0) return String(Number(g)); } return null; };
/** "Brand: X", "make - X", "الماركة: X". */
const labelled = (labels: string) => {
  const re = new RegExp(`(?:^|[\\s,;(|])(?:${labels})\\s*[:\\-–=]\\s*([^,;\\n|()]{2,60})`, 'i');
  return (t: string) => { const m = t.match(re); return m ? clean(m[1]) : null; };
};
const either = (...fs: ((t: string) => string | null)[]) => (t: string) => { for (const f of fs) { const v = f(t); if (v) return v; } return null; };
/** Arabic spellings suppliers write for common brands; the canonical (English) name is what is stored. */
const BRAND_AR: Record<string, string[]> = {
  Jotun: ['جوتن', 'جوتون'], Dulux: ['دولكس'], 'National Paints': ['ناشيونال للدهانات', 'الدهانات الوطنية'], Daikin: ['دايكن', 'دايكين'],
  Carrier: ['كاريير', 'كارير'], Gree: ['جري'], LG: ['إل جي', 'ال جي'], Samsung: ['سامسونج'], Knauf: ['كناوف'], Gyproc: ['جيبروك'],
  Ducab: ['دوكاب'], Schneider: ['شنايدر'], ABB: ['إيه بي بي'], Cosmoplast: ['كوزموبلاست'], Grohe: ['جروهي'], 'RAK Ceramics': ['رأس الخيمة للسيراميك', 'راك'],
  Sika: ['سيكا'], Hikvision: ['هيكفيجن'], Otis: ['أوتيس'], Hettich: ['هيتيش'], Blum: ['بلوم'], Egger: ['إيجر'],
};
/** A brand lexicon plus the explicit "Brand:" form, so an unlisted brand the supplier names is still read. */
const brand = (names: string[]) => either(
  labelled('brand|make|manufacturer|mfr|ماركة|الماركة|العلامة التجارية|الشركة المصنعة|صنع'),
  (t) => {
    for (const n of names) {
      const re = new RegExp(`(^|[^a-z])${n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^a-z]|$)`, 'i'); if (re.test(t)) return n;
      for (const a of BRAND_AR[n] ?? []) if (t.includes(a)) return n;
    }
    return null;
  },
);
const model = either(
  labelled('model(?:\\s*no\\.?)?|model number|موديل|الموديل|رقم الموديل'),
  (t) => { const m = t.match(/\bmodel\s+([A-Z0-9][A-Z0-9\-\/.]{2,30})/i) || t.match(/(?:موديل|الموديل)\s+([A-Z0-9][A-Z0-9\-\/.]{2,30})/i); return m ? clean(m[1]) : null; },
);
const product = labelled('product|range|series|المنتج|اسم المنتج|السلسلة');
const standard = (t: string) => { const m = t.match(/\b(BS\s?EN\s?[\d\-:]+|BS\s?\d{2,5}(?:[-:]\d+)?|EN\s?\d{2,5}(?:[-:]\d+)?|ASTM\s?[A-Z]?\d{1,5}|ISO\s?\d{3,5}|IEC\s?\d{3,5}(?:-\d+)?|UL\s?\d{2,4}|DIN\s?\d{2,5}|NFPA\s?\d{1,4}|TIA[-\s]?\d{3}[A-Z]?|ESMA|NADCA|DCD approved|civil defen[cs]e approved)\b/i); return m ? clean(m[1]) : null; };

// Thickness: an explicit "thk/thickness/سماكة" form first; otherwise a lone "18mm" that is not one
// side of a size ("600x600mm") and not a cross-section ("16mm2"). A size is read by `dims` instead.
const thickness = (t: string) => {
  const s = normText(t);
  const explicit = s.match(/(?:thk|thick(?:ness)?|سماكة|سمك|بسماكة|بسمك)\.?\s*[:\-=]?\s*(\d+(?:\.\d+)?)\s*(?:mm|ملم|مم|ملي)?/i)
    || s.match(/(\d+(?:\.\d+)?)\s*(?:mm|ملم|مم|ملي)\s*(?:thk|thick(?:ness)?|سماكة|سمك)/i);
  if (explicit) return String(Number(explicit[1]));
  const re = /(\d+(?:\.\d+)?)\s*(?:mm|ملم|مم|ملي)(?![²2a-z])/gi;
  for (const m of s.matchAll(re)) {
    const before = s.slice(Math.max(0, m.index! - 3), m.index!);
    const after = s.slice(m.index! + m[0].length, m.index! + m[0].length + 3);
    if (/[x×*]\s*$/i.test(before) || /^\s*[x×*]/i.test(after)) continue;
    if (Number(m[1]) > 0 && Number(m[1]) <= 300) return String(Number(m[1]));
  }
  return null;
};
const dims = (t: string) => { const m = normText(t).match(/(\d+(?:\.\d+)?)\s*(mm|cm|m)?\s*[x×*]\s*(\d+(?:\.\d+)?)\s*(mm|cm|m)?(?:\s*[x×*]\s*(\d+(?:\.\d+)?)\s*(mm|cm|m)?)?/i); if (!m) return null; const u = m[6] || m[4] || m[2] || ''; return clean(`${m[1]}x${m[3]}${m[5] ? 'x' + m[5] : ''}${u ? ' ' + u.toLowerCase() : ''}`); };
const coats = numFrom(/(\d)\s*(?:coats?|layers?|طبقات|طبقة)/i, /(?:coats?|layers?)\s*[:\-]?\s*(\d)/i);
const coatsWords = (t: string) => coats(normText(t)) ?? (/\b(two|double)\s+coats?\b|طبقتين|طبقتان/i.test(t) ? '2' : /\b(three)\s+coats?\b|ثلاث طبقات/i.test(t) ? '3' : /\b(one|single)\s+coat\b|طبقة واحدة/i.test(t) ? '1' : null);

// ---------------------------------------------------------------------------------------------
// Shared lexicons.
// ---------------------------------------------------------------------------------------------
const WOOD_SPECIES: [string, RegExp][] = [['Oak', /\boak\b|بلوط/i], ['Teak', /\bteak\b|ساج/i], ['Walnut', /\bwalnut\b|جوز/i], ['Beech', /\bbeech\b|زان/i], ['Ash', /\bash\b(?!\s*tray)|دردار/i], ['Mahogany', /mahogany|ماهوجني|ماهوغني/i], ['Pine', /\bpine\b|صنوبر/i], ['Maple', /\bmaple\b|قيقب/i], ['Zebrano', /zebrano|زيبرانو/i], ['Meranti', /meranti|ميرانتي/i]];
const BOARD: [string, RegExp][] = [
  ['Moisture-resistant MDF', /\bmr\s*-?\s*mdf\b|moisture\s*resist\w*\s*mdf|mdf\s*(?:mr|moisture)|mdf\s*مقاوم للرطوبة/i],
  ['Fire-rated MDF', /\bfr\s*-?\s*mdf\b|fire\s*-?\s*(?:rated|retardant)\s*mdf/i],
  ['HDF', /\bhdf\b|إتش دي إف/i], ['MDF', /\bmdf\b|ام دي اف|إم دي إف|خشب ام دي/i],
  ['Marine plywood', /marine\s*ply/i], ['Plywood', /\bply(?:wood)?\b|خشب رقائقي|خشب معاكس|بلاي\s*وود|بلايوود/i],
  ['Particle board', /particle\s*board|chip\s*board|خشب حبيبي|خشب مضغوط|حبيبي/i], ['Blockboard', /block\s*board|بلوك بورد/i],
  ['WPC', /\bwpc\b|wood\s*plastic/i], ['Solid wood', /solid\s*(?:wood|timber|oak|teak|walnut|beech|ash|mahogany|pine|maple)|hard\s*wood|خشب طبيعي|خشب صلب|خشب زان|خشب بلوط|خشب ساج|خشب جوز/i],
];
const JOIN_FINISH: [string, RegExp][] = [['HPL', /\bhpl\b|high\s*pressure\s*laminate|formica|فورمايكا|اتش بي ال/i], ['Veneer', /veneer|قشرة/i], ['Lacquer', /lacquer|duco|polyurethane\s*paint|\bpu\s*paint|ورنيش|دوكو|لكر|بولي يوريثان/i], ['Melamine', /melamine|ميلامين/i], ['Acrylic', /acrylic\s*(?:finish|sheet|panel|gloss)|أكريليك|اكريليك/i], ['Laminate', /laminate|لامينيت/i], ['Paint', /\bpainted\b|paint\s*finish|دهان/i]];
const FIRE = either((t: string) => { const m = normText(t).match(/(\d{2,3})\s*(?:min(?:ute)?s?|دقيقة)\s*(?:fire|rated|مقاوم)?|\bfr\s?(\d{2,3})\b|\bei\s?(\d{2,3})\b/i); const g = m && m.slice(1).find(Boolean); return g ? g + ' min' : null; }, oneOf([['Fire-rated', /fire\s*-?\s*(?:rated|retardant|resistant)|مقاوم للحريق|مقاوم للحرائق/i]]));

// ---------------------------------------------------------------------------------------------
// The catalogue. `*` in a comment = mandatory core; the rest are trade-specific extras.
// ---------------------------------------------------------------------------------------------
const A = (code: string, en: string, ar: string, mandatory: boolean, find: Attr['find'], more: Partial<Attr> = {}): Attr =>
  ({ code, en, ar, type: 'text', mandatory, find, ...more });
const N = (code: string, en: string, ar: string, unit: string, unit_ar: string, mandatory: boolean, find: Attr['find'], more: Partial<Attr> = {}): Attr =>
  ({ code, en, ar, type: 'number', unit, unit_ar, mandatory, find, ...more });
const BRAND = (names: string[], mandatory = true, more: Partial<Attr> = {}) => A('brand', 'Brand / manufacturer', 'الماركة / الشركة المصنّعة', mandatory, brand(names), more);
const MODEL = (mandatory = true, more: Partial<Attr> = {}) => A('model', 'Model / product code', 'الموديل / رمز المنتج', mandatory, model, more);
const STANDARD = A('standard', 'Standard / approval', 'المواصفة القياسية / الاعتماد', false, standard);
const THK = (mandatory = true, more: Partial<Attr> = {}) => N('thickness_mm', 'Thickness', 'السماكة', 'mm', 'ملم', mandatory, thickness, more);
const DIMS = (mandatory = true, more: Partial<Attr> = {}) => A('dimensions', 'Size (L × W)', 'المقاس (الطول × العرض)', mandatory, dims, { unit: 'mm', unit_ar: 'ملم', ...more });

const T = (code: string, en: string, ar: string, kw: RegExp, attrs: Attr[]): Trade => ({ code, en, ar, kw, attrs });

export const TRADES: Record<string, Trade> = Object.fromEntries([
  T('joinery', 'Joinery & carpentry', 'النجارة والأعمال الخشبية',
    /joinery|carpentr|wardrobe|cabinet|kitchen|vanity|cupboard|shelv|counter\s*top|reception\s*desk|panell?ing|wooden|timber|\bdoor\s*leaf|\bmdf\b|\bhdf\b|plywood|veneer|نجار|خزان(?:ة|ات)|دولاب|مطبخ|خشب|باب خشب/i, [
      A('material', 'Board / wood type', 'نوع الخشب / اللوح', true, oneOf(BOARD), { options: BOARD.map(([v]) => v) }),
      A('species', 'Wood species', 'نوع الخشب الطبيعي', false, oneOf(WOOD_SPECIES), { options: WOOD_SPECIES.map(([v]) => v) }),
      THK(),
      A('finish', 'Finish', 'التشطيب', true, oneOf(JOIN_FINISH), { options: JOIN_FINISH.map(([v]) => v) }),
      A('edge_band', 'Edge band', 'شريط الحافة', false, (t) => { const m = normText(t).match(/((?:pvc|abs|wood|veneer|aluminium|acrylic)\s*edge\s*-?\s*band(?:ing)?(?:\s*\d+(?:\.\d+)?\s*mm)?)|edge\s*-?\s*band(?:ing)?\s*[:\-]?\s*([\w .]{2,30})|شريط حافة\s*([^\s,;]{2,30})/i); return m ? clean(m[1] || m[2] || m[3]) : null; }),
      A('fire_rating', 'Fire rating', 'تصنيف مقاومة الحريق', false, FIRE),
      BRAND(['Egger', 'Kronospan', 'Formica', 'Greenlam', 'Merino', 'Wilsonart', 'Arpa', 'Abet', 'Blum', 'Hettich', 'Hafele', 'Grass', 'Duropal', 'Finsa', 'Sonae'], false),
      STANDARD,
    ]),
  T('gypsum', 'Gypsum & ceilings', 'الجبس والأسقف', /gypsum|false\s*ceiling|ceiling|partition|drywall|plaster\s*board|bulkhead|جبس|سقف معلق|أسقف|قواطع|قاطع/i, [
      A('board_type', 'Board type', 'نوع اللوح', true, oneOf([
        ['Moisture-resistant board', /moisture\s*-?\s*resist|water\s*-?\s*resist|\bmr\s*board|green\s*board|مقاوم للرطوبة|مقاوم للماء/i],
        ['Fire-rated board', /fire\s*-?\s*(?:rated|resist)|\bfr\s*board|type\s*x\b|مقاوم للحريق/i],
        ['Acoustic board', /acoustic|perforated|عازل للصوت|صوتي/i], ['Cement board', /cement\s*board|لوح أسمنتي/i],
        ['Mineral fibre tile', /mineral\s*fib(?:er|re)|armstrong|ceiling\s*tile|بلاط سقف/i], ['Calcium silicate', /calcium\s*silicate/i],
        ['Standard gypsum board', /(?:standard|regular|normal|plain)\s*(?:gypsum|board)|gypsum\s*board|plaster\s*board|لوح جبس|ألواح جبس|جبس بورد/i],
      ]), { options: ['Standard gypsum board', 'Moisture-resistant board', 'Fire-rated board', 'Acoustic board', 'Cement board', 'Mineral fibre tile', 'Calcium silicate'] }),
      THK(),
      A('frame', 'Frame / stud system & gauge', 'نظام الهيكل / القطاعات وسماكتها', true, (t) => { const s = normText(t); const m = s.match(/(\d+(?:\.\d+)?\s*mm\s*(?:gi|galv\w*)?\s*(?:studs?|channels?|frames?|framing|profiles?|runners?))|((?:studs?|channels?|framing|profiles?)\s*[:\-]?\s*\d+(?:\.\d+)?\s*mm)|(\d{2}\s*(?:gauge|ga)\b)|((?:knauf|gyproc|usg|siniat)\s*(?:system|frame|grid|\w+\s*system))|(furring\s*channel[\w .]{0,20})|(قطاعات\s*[^,;]{2,30})|(هيكل\s*مجلفن[^,;]{0,30})/i); return m ? clean(m.slice(1).find(Boolean)!) : null; }),
      A('insulation', 'Insulation', 'العزل', false, (t) => { const m = normText(t).match(/((?:rock|glass|mineral)\s*wool(?:\s*\d+\s*(?:kg\/m3|kg\/m³|mm))*)|(صوف صخري[^,;]{0,20})|(صوف زجاجي[^,;]{0,20})/i); return m ? clean(m.slice(1).find(Boolean)!) : null; }),
      BRAND(['Knauf', 'Gyproc', 'USG Boral', 'USG', 'Saint-Gobain', 'Armstrong', 'Siniat', 'Rigips'], false),
    ]),
  T('flooring', 'Flooring', 'الأرضيات', /floor|spc|\blvt\b|vinyl|laminate|parquet|epoxy|skirting|أرضي|باركيه|فينيل|إيبوكسي|ايبوكسي|لامينيت/i, [
      A('material', 'Floor material', 'نوع الأرضية', true, oneOf([['SPC', /\bspc\b/i], ['LVT / vinyl', /\blvt\b|vinyl|فينيل/i], ['Engineered wood', /engineered\s*(?:wood|parquet|oak)|خشب هندسي/i], ['Solid parquet', /solid\s*(?:wood|parquet)|باركيه طبيعي/i], ['Laminate', /laminate|لامينيت/i], ['Epoxy', /epoxy|إيبوكسي|ايبوكسي/i], ['Carpet tile', /carpet\s*tile|بلاط موكيت/i], ['Rubber', /rubber|مطاط/i], ['Parquet', /parquet|باركيه/i]]), { options: ['SPC', 'LVT / vinyl', 'Laminate', 'Engineered wood', 'Solid parquet', 'Epoxy', 'Carpet tile', 'Rubber'] }),
      A('grade', 'Grade / class (AC, use class)', 'الدرجة / فئة الاستخدام', false, (t) => { const m = normText(t).match(/\b(AC\s?[1-6])\b|\bclass\s*(2[1-3]|3[1-4]|4[1-3])\b/i); return m ? clean(m[1] || 'Class ' + m[2]) : null; }),
      DIMS(true, { except: /epoxy|إيبوكسي|ايبوكسي|self\s*-?\s*level|screed/i }),
      THK(),
      N('wear_layer_mm', 'Wear layer', 'طبقة الاحتكاك', 'mm', 'ملم', false, numFrom(/wear\s*-?\s*layer\s*[:\-]?\s*(\d+(?:\.\d+)?)\s*(?:mm)?/i, /(\d+(?:\.\d+)?)\s*mm\s*wear/i, /(0\.\d+)\s*(?:mm)?\s*(?:طبقة احتكاك)/i), { applies: /spc|lvt|vinyl|laminate|فينيل|لامينيت/i }),
      BRAND(['Tarkett', 'Quick-Step', 'Pergo', 'Kaindl', 'Egger', 'Krono', 'Gerflor', 'Forbo', 'Armstrong', 'Mohawk', 'Kahrs', 'Boen', 'Sika', 'Flowcrete', 'BASF', 'Fosroc', 'Mapei']),
    ]),
  T('tiling', 'Tiling & stone', 'البلاط والحجر', /tile|tiling|porcelain|ceramic|marble|granite|mosaic|terrazzo|quartz|بلاط|سيراميك|بورسلين|رخام|جرانيت|غرانيت|موزاييك/i, [
      A('material', 'Tile / stone type', 'نوع البلاط / الحجر', true, oneOf([['Porcelain', /porcelain|بورسلين/i], ['Ceramic', /ceramic|سيراميك/i], ['Marble', /marble|رخام/i], ['Granite', /granite|جرانيت|غرانيت/i], ['Quartz', /quartz|كوارتز/i], ['Mosaic', /mosaic|موزاييك|فسيفساء/i], ['Terrazzo', /terrazzo|تيرازو/i]]), { options: ['Porcelain', 'Ceramic', 'Marble', 'Granite', 'Quartz', 'Mosaic', 'Terrazzo'] }),
      DIMS(), THK(),
      A('finish', 'Surface finish', 'تشطيب السطح', false, oneOf([['Polished', /polish|لامع|مصقول/i], ['Matt', /\bmatt?e?\b|مطفي/i], ['Honed', /honed/i], ['Anti-slip', /anti\s*-?\s*slip|\br1[0-3]\b|مانع للانزلاق/i], ['Glazed', /glazed|مزجج/i]])),
      BRAND(['RAK Ceramics', 'RAK', 'Porcelanosa', 'Marazzi', 'Florim', 'Atlas Concorde', 'Kajaria', 'Cleopatra', 'Saudi Ceramics', 'Pamesa', 'Keraben'], false),
    ]),
  T('painting', 'Painting', 'الدهانات', /paint|emulsion|primer|coat\b|coats\b|enamel|دهان|طلاء|بوية|برايمر/i, [
      BRAND(['Jotun', 'Dulux', 'National Paints', 'Asian Paints', 'Sherwin-Williams', 'Berger', 'Caparol', 'Hempel', 'Nippon', 'Terraco', 'Ritver', 'Oasis', 'Al Jazeera', 'Sigma', 'Benjamin Moore']),
      A('product', 'Product name', 'اسم المنتج', true, either(product, oneOf([['Fenomastic', /fenomastic|فينوماستك|فينوماستيك/i], ['Jotashield', /jotashield|جوتاشيلد/i], ['Majestic', /majestic/i], ['Weathershield', /weather\s*shield/i], ['Super Acrylic Emulsion', /super\s*acrylic/i], ['Silk Emulsion', /silk\s*emulsion/i], ['Vinyl Matt Emulsion', /vinyl\s*matt/i], ['Acrylic emulsion', /acrylic\s*emulsion|امولشن اكريليك/i], ['Enamel', /\benamel\b|مينا/i], ['Texture coat', /texture|تكسشر/i]]))),
      N('coats', 'Number of coats', 'عدد الطبقات', 'coats', 'طبقات', true, coatsWords),
      A('sheen', 'Sheen', 'درجة اللمعان', false, oneOf([['Semi-gloss', /semi\s*-?\s*gloss|نصف لامع/i], ['Gloss', /\bgloss\b|لامع/i], ['Satin', /satin|ساتان/i], ['Silk', /\bsilk\b|حريري/i], ['Eggshell', /eggshell/i], ['Matt', /\bmatt?e?\b|مطفي/i]])),
    ]),
  T('wallpaper', 'Wallpaper & wall covering', 'ورق الجدران', /wallpaper|wall\s*covering|ورق جدران|ورق حائط/i, [
      A('material', 'Wallpaper type', 'نوع ورق الجدران', true, oneOf([['Vinyl', /vinyl|فينيل/i], ['Non-woven', /non\s*-?\s*woven/i], ['Fabric', /fabric|قماش/i], ['Grasscloth', /grass\s*cloth/i], ['Paper', /\bpaper\b/i]])),
      A('roll_size', 'Roll size / weight', 'مقاس / وزن اللفة', false, either(dims, (t) => { const m = normText(t).match(/(\d{2,4})\s*(?:gsm|g\/m2)/i); return m ? m[1] + ' gsm' : null; })),
      BRAND(['Sirpi', 'Arte', 'Omexco', 'Casamance', 'Graham & Brown', 'Vescom', 'Muraspec', 'Architects Paper']),
    ]),
  T('carpet', 'Carpets', 'السجاد والموكيت', /carpet|rug|موكيت|سجاد/i, [
      A('material', 'Yarn', 'نوع الخيط', true, oneOf([['Nylon', /nylon|نايلون/i], ['Polypropylene', /polypropylene|\bpp\b/i], ['Wool', /wool|صوف/i], ['Polyester', /polyester|بوليستر/i]])),
      A('construction', 'Type (broadloom / tiles)', 'النوع (رول / بلاط)', true, oneOf([['Carpet tiles', /tiles?|بلاط/i], ['Broadloom', /broadloom|wall\s*-?\s*to\s*-?\s*wall|roll|رول/i]])),
      N('pile_weight', 'Pile weight', 'وزن الوبر', 'g/m²', 'غ/م²', false, numFrom(/(\d{3,4})\s*(?:g\/m2|g\/m²|gsm|oz)/i)),
      BRAND(['Interface', 'Balsan', 'Desso', 'Milliken', 'Tarkett', 'Shaw', 'Ege', 'Forbo']),
    ]),
  T('glazing', 'Glass & aluminium', 'الزجاج والألمنيوم', /glass|glazing|alumin|window|curtain\s*wall|shop\s*front|balustrad|skylight|زجاج|ألمنيوم|المنيوم|ألومنيوم|نافذة|شباك|واجهة زجاجية/i, [
      A('glass_type', 'Glass type', 'نوع الزجاج', true, oneOf([['Double-glazed unit', /double\s*-?\s*glaz|\bdgu\b|insulated\s*glass|مزدوج/i], ['Laminated', /laminat|مصفح/i], ['Tempered', /temper|toughen|سيكوريت|مقسى|مقوى/i], ['Low-E', /low\s*-?\s*e\b/i], ['Reflective', /reflective|عاكس/i], ['Frosted', /frost|sandblast|مصنفر/i], ['Clear float', /clear\s*(?:float|glass)|float\s*glass|شفاف/i]]), { applies: /glass|glaz|window|skylight|shop\s*front|curtain|زجاج|نافذة|شباك/i }),
      A('glass_thickness', 'Glass thickness / build-up', 'سماكة الزجاج / تركيبه', true, (t) => { const s = normText(t); const m = s.match(/(\d{1,2}\s*(?:mm)?\s*\+\s*\d{1,2}\s*(?:mm)?\s*(?:air|argon)?\s*\+\s*\d{1,2}\s*mm)/i); return m ? clean(m[1]) : (thickness(s) ? thickness(s) + ' mm' : null); }, { applies: /glass|glaz|window|skylight|shop\s*front|curtain|زجاج|نافذة|شباك/i }),
      A('profile_system', 'Aluminium system / series', 'نظام / سلسلة الألمنيوم', true, (t) => { const m = normText(t).match(/((?:schuco|schüco|technal|reynaers|gulf\s*extrusions|alumil|kawneer|aluprof|elumatec|wicona|metra)[\w .\-]{0,25})|(series\s*\d{2,4}[a-z]?)|(thermal\s*break[\w ]{0,15})|(سلسلة\s*\d{2,4})/i); return m ? clean(m.slice(1).find(Boolean)!) : null; }, { applies: /alumin|frame|window|door|curtain|shop\s*front|ألمنيوم|المنيوم|ألومنيوم|شباك|باب/i }),
      A('finish', 'Frame finish (RAL / anodised)', 'تشطيب الإطار', false, (t) => { const m = normText(t).match(/(ral\s*\d{4})|(powder\s*-?\s*coat\w*)|(anodi[sz]\w*)|(pvdf)|(دهان حراري)/i); return m ? clean(m.slice(1).find(Boolean)!) : null; }, { applies: /alumin|frame|ألمنيوم|المنيوم/i }),
      STANDARD,
    ]),
  T('electrical', 'Electrical', 'الكهرباء', /cable|wire|wiring|\bdb\b|distribution\s*board|socket|switch|light|luminaire|down\s*light|\bmcb\b|\bmccb\b|breaker|conduit|isolator|كابل|كيبل|سلك|أسلاك|مفتاح|مقبس|إنارة|لوحة توزيع|قاطع/i, [
      A('cable_type', 'Cable type / insulation', 'نوع الكابل / العزل', true, oneOf([['XLPE/SWA/PVC armoured', /xlpe.*swa|swa.*xlpe|armou?red|مسلح/i], ['XLPE', /xlpe/i], ['LSZH / LSF', /lszh|lsoh|\blsf\b|low\s*smoke/i], ['Fire-resistant (FP)', /fire\s*-?\s*(?:resistant|proof)|\bfp\s*\d+|مقاوم للحريق/i], ['PVC single core', /pvc|single\s*core|6491/i], ['Flexible', /flex(?:ible)?/i]]), { applies: /cable|wire|wiring|كابل|كيبل|سلك|أسلاك/i }),
      N('size_mm2', 'Conductor size', 'مقطع الموصل', 'mm²', 'مم²', true, (t) => { const s = normText(t); const m = s.match(/(\d+(?:\.\d+)?)\s*(?:mm2|mm²|sq\.?\s*mm|sqmm|ملم مربع|مم2|مم²)/i) || s.match(/\d\s*c(?:ore)?\s*[x×]\s*(\d+(?:\.\d+)?)/i); return m ? String(Number(m[1])) : null; }, { applies: /cable|wire|wiring|كابل|كيبل|سلك|أسلاك/i }),
      BRAND(['Ducab', 'Riyadh Cables', 'Oman Cables', 'Nexans', 'Prysmian', 'Elsewedy', 'National Cables', 'RAK Cables', 'Schneider', 'ABB', 'Legrand', 'Hager', 'Siemens', 'MK', 'Eaton', 'Philips', 'Signify', 'Osram', 'Havells', 'Clipsal']),
      A('rating', 'Rating (A / W / IP)', 'التصنيف (أمبير / واط / IP)', false, (t) => { const m = normText(t).match(/(\d+(?:\.\d+)?\s*(?:a|amp|w|watt|kw)\b(?:\s*,?\s*ip\s*\d{2})?)|(ip\s*\d{2})/i); return m ? clean(m[1] || m[2]) : null; }, { except: /cable|wire|كابل|سلك/i }),
      STANDARD,
    ]),
  T('hvac', 'HVAC', 'التكييف والتهوية', /split|ducted|cassette|\bvrf\b|\bvrv\b|chiller|package\s*unit|\bfcu\b|\bahu\b|\bfahu\b|air\s*-?\s*condition|\bac\s*unit|مكيف|تكييف|سبليت|كاسيت|تشلر/i, [
      BRAND(['Daikin', 'Carrier', 'Gree', 'Midea', 'LG', 'Samsung', 'Trane', 'York', 'Mitsubishi Electric', 'Mitsubishi Heavy', 'Mitsubishi', 'Hitachi', 'O General', 'Toshiba', 'Panasonic', 'Haier', 'Fujitsu', 'Zamil', 'Petra', 'Johnson Controls', 'Blue Star', 'Voltas'], true, { applies: /split|ducted|cassette|vrf|vrv|chiller|package|fcu|ahu|fahu|unit|air\s*-?\s*condition|مكيف|وحدة|سبليت|كاسيت|تشلر/i }),
      MODEL(true, { applies: /split|ducted|cassette|vrf|vrv|chiller|package|fcu|ahu|fahu|unit|air\s*-?\s*condition|مكيف|وحدة|سبليت|كاسيت|تشلر/i }),
      N('capacity_tr', 'Cooling capacity', 'قدرة التبريد', 'TR', 'طن', true, (t) => { const s = normText(t); const m = s.match(/(\d+(?:\.\d+)?)\s*(?:tr\b|tons?\b|tonne?s?\b|طن)/i); if (m) return String(Number(m[1])); const b = s.match(/(\d{1,3}(?:,\d{3})+|\d{4,6})\s*btu/i); if (b) { const v = Number(b[1].replace(/,/g, '')) / 12000; return v > 0 ? String(Math.round(v * 100) / 100) : null; } const k = s.match(/(\d+(?:\.\d+)?)\s*kw\s*(?:cooling|تبريد)/i); return k ? String(Math.round(Number(k[1]) / 3.517 * 100) / 100) : null; }, { applies: /split|ducted|cassette|vrf|vrv|chiller|package|fcu|ahu|unit|air\s*-?\s*condition|مكيف|وحدة|سبليت|كاسيت|تشلر/i }),
      A('refrigerant', 'Refrigerant', 'غاز التبريد', true, (t) => { const m = normText(t).match(/\b(R\s?-?\s?(?:410A|32|134a|407C|22|290|454B|513A|1234ze|1234yf))\b/i); return m ? m[1].toUpperCase().replace(/\s|-/g, '').replace(/^R/, 'R-') : null; }, { applies: /split|ducted|cassette|vrf|vrv|chiller|package|unit|air\s*-?\s*condition|مكيف|وحدة|سبليت|كاسيت|تشلر/i, except: /\bahu\b|\bfahu\b|\bfcu\b/i }),
      A('efficiency', 'Efficiency (SEER / EER / ESMA stars)', 'الكفاءة (SEER / EER / نجوم ESMA)', false, (t) => { const m = normText(t).match(/((?:seer|eer|cop|iplv)\s*[:=]?\s*\d+(?:\.\d+)?)|(\d\s*(?:star|stars|نجوم|نجمة)(?:\s*esma)?)/i); return m ? clean(m[1] || m[2]) : null; }),
    ]),
  T('plumbing', 'Plumbing', 'السباكة', /pipe|piping|ppr|upvc|cpvc|\bpex\b|hdpe|valve|mixer|\bwc\b|water\s*closet|basin|sink|heater|pump|drain|أنبوب|أنابيب|مواسير|خلاط|سخان|مضخة|مغسلة|صرف|محبس/i, [
      A('pipe_material', 'Pipe material', 'مادة الأنابيب', true, oneOf([['PPR', /\bppr\b/i], ['CPVC', /\bcpvc\b/i], ['uPVC', /\bu\s*-?\s*pvc\b/i], ['PEX', /\bpex\b/i], ['HDPE', /\bhdpe\b/i], ['Copper', /copper|نحاس/i], ['GI', /\bg\.?i\.?\b|galvani[sz]ed\s*(?:iron|steel)|مجلفن/i], ['Ductile iron', /ductile\s*iron|\bdi\b\s*pipe/i], ['PVC', /\bpvc\b/i]]), { applies: /pipe|piping|ppr|upvc|cpvc|pex|hdpe|copper\s*(?:pipe|tube)|أنبوب|أنابيب|مواسير/i }),
      A('pipe_class', 'Pressure class (PN / SDR / SCH)', 'فئة الضغط (PN / SDR / SCH)', true, (t) => { const m = normText(t).match(/\b(PN\s?\d{1,2}(?:\.\d)?)\b|\b(SDR\s?\d{1,2})\b|\b(SCH(?:EDULE)?\s?\d{2,3})\b|\b(class\s*[A-E])\b|\b(type\s*[KLM])\b/i); return m ? clean(m.slice(1).find(Boolean)!.toUpperCase().replace(/\s+/, ' ')) : null; }, { applies: /pipe|piping|ppr|upvc|cpvc|pex|hdpe|copper\s*(?:pipe|tube)|أنبوب|أنابيب|مواسير/i }),
      A('size', 'Pipe size', 'مقاس الأنبوب', true, (t) => { const s = normText(t); const m = s.match(/\b(dn\s?\d{2,4})\b|(ø\s?\d{2,4}\s*(?:mm)?)|(\d{2,4}\s*mm\s*(?:dia|od|nb|ø|diameter|قطر))|((?:\d\s)?\d\/\d\s*(?:"|inch|in\b|بوصة))|(\d(?:\.\d+)?\s*(?:"|inch|بوصة))|(\d{2,3}\s*(?:mm|ملم|مم))/i); return m ? clean(m.slice(1).find(Boolean)!) : null; }, { applies: /pipe|piping|ppr|upvc|cpvc|pex|hdpe|copper\s*(?:pipe|tube)|أنبوب|أنابيب|مواسير/i }),
      BRAND(['Cosmoplast', 'Hepworth', 'Aquatherm', 'Wavin', 'Georg Fischer', 'GF', 'Pipelife', 'Kitz', 'Grohe', 'Hansgrohe', 'Kohler', 'Duravit', 'Ideal Standard', 'Roca', 'RAK Ceramics', 'Grundfos', 'Ariston', 'Rheem', 'Wilo', 'Danube', 'Dura']),
      MODEL(false, { except: /pipe|piping|أنبوب|أنابيب|مواسير/i }),
      STANDARD,
    ]),
  T('fire', 'Fire & life safety', 'الإطفاء والسلامة', /fire|sprinkler|extinguisher|smoke\s*detector|alarm|hose\s*reel|fm\s*200|حريق|إطفاء|رشاش|طفاية|كاشف دخان|إنذار/i, [
      BRAND(['Tyco', 'Viking', 'Reliable', 'Honeywell', 'Notifier', 'Siemens', 'Bosch', 'Apollo', 'Hochiki', 'Kidde', 'Firex', 'Naffco', 'Nitin', 'Chemguard', 'Minimax']),
      A('approval', 'Approval / listing', 'الاعتماد / التسجيل', true, (t) => { const m = normText(t).match(/\b(UL(?:\s*listed)?|FM(?:\s*approved)?|LPCB|VdS|EN\s?54|DCD(?:\s*approved)?|civil\s*defen[cs]e\s*approved)\b|(معتمد من الدفاع المدني)/i); return m ? clean(m[1] || m[2]) : null; }),
      MODEL(false), A('capacity', 'Size / capacity', 'المقاس / السعة', false, (t) => { const m = normText(t).match(/(\d+(?:\.\d+)?\s*(?:kg|ltr|l|litre|gpm|k-?factor\s*\d+|mm))\b/i); return m ? clean(m[1]) : null; }),
    ]),
  T('security', 'CCTV & security', 'المراقبة والأمن', /cctv|camera|nvr|dvr|access\s*control|intercom|alarm\s*panel|turnstile|كاميرا|مراقبة|تحكم بالدخول|انتركم/i, [
      BRAND(['Hikvision', 'Dahua', 'Axis', 'Bosch', 'Hanwha', 'Uniview', 'Honeywell', 'Avigilon', 'Pelco', 'HID', 'ZKTeco', 'Suprema', 'Commax', 'Aiphone', 'Paxton']),
      MODEL(),
      A('resolution', 'Camera resolution', 'دقة الكاميرا', true, (t) => { const m = normText(t).match(/(\d{1,2}\s*mp)\b|\b(4k|8k|1080p|720p)\b/i); return m ? clean((m[1] || m[2]).toUpperCase().replace(/\s/g, '')) : null; }, { applies: /camera|كاميرا/i }),
      A('storage', 'Storage / retention', 'التخزين / مدة الحفظ', false, (t) => { const m = normText(t).match(/(\d+\s*tb)|(\d+\s*days?)/i); return m ? clean(m[1] || m[2]) : null; }, { applies: /nvr|dvr|recorder|hdd|storage|تسجيل/i }),
    ]),
  T('networking', 'IT & networking', 'الشبكات', /network|data\s*point|cat\s*-?\s*[5-8]|fib(?:er|re)|patch\s*panel|rack|switch\s*\d+\s*port|access\s*point|wifi|شبكة|كابل بيانات|ألياف/i, [
      A('cable_category', 'Cable category / fibre type', 'فئة الكابل / نوع الألياف', true, (t) => { const m = normText(t).match(/\b(cat\s*-?\s*(?:5e|6a|6|7a|7|8))\b|\b(om[1-5]|os[12])\b/i); return m ? clean((m[1] || m[2]).toUpperCase().replace(/\s|-/g, '')) : null; }, { applies: /cable|cabling|data\s*point|fib(?:er|re)|patch\s*cord|كابل|ألياف/i }),
      BRAND(['Cisco', 'Aruba', 'Ubiquiti', 'Fortinet', 'Juniper', 'HPE', 'Commscope', 'Panduit', 'Legrand', 'Nexans', 'Siemon', 'Belden', 'Molex', 'TP-Link', 'Ruckus', 'Mikrotik']),
      MODEL(false, { except: /cable|cabling|كابل/i }), STANDARD,
    ]),
  T('avsystems', 'Audio-visual', 'الأنظمة الصوتية والمرئية', /speaker|amplifier|projector|display|screen|video\s*wall|\bav\b|audio|microphone|سماعة|مكبر|بروجكتور|شاشة/i, [
      BRAND(['Bose', 'JBL', 'Sonos', 'Crestron', 'Extron', 'Samsung', 'LG', 'Sony', 'Epson', 'BenQ', 'Yamaha', 'Shure', 'QSC', 'Biamp', 'Polycom', 'Barco']), MODEL(),
      A('size_power', 'Size / power', 'المقاس / القدرة', false, (t) => { const m = normText(t).match(/(\d{2,3}\s*(?:"|inch|بوصة))|(\d+\s*w(?:att)?)\b|(\d{3,5}\s*lumens?)/i); return m ? clean(m.slice(1).find(Boolean)!) : null; }),
    ]),
  T('smarthome', 'Smart home & automation', 'المنزل الذكي والأتمتة', /smart|automation|\bknx\b|zigbee|z-?wave|dali|scene|keypad|thermostat|ذكي|أتمتة/i, [
      A('protocol', 'Protocol', 'البروتوكول', true, oneOf([['KNX', /\bknx\b/i], ['Zigbee', /zigbee/i], ['Z-Wave', /z-?wave/i], ['DALI', /\bdali\b/i], ['Matter', /\bmatter\b/i], ['Wi-Fi', /wi-?fi/i], ['Bluetooth mesh', /bluetooth/i]])),
      BRAND(['Schneider', 'ABB', 'Siemens', 'Crestron', 'Control4', 'Savant', 'Lutron', 'Legrand', 'Gira', 'Jung', 'Basalte', 'Loxone', 'Somfy', 'Aqara', 'Orvibo']),
      MODEL(false),
    ]),
  T('solar', 'Solar PV', 'الطاقة الشمسية', /solar|photovolt|\bpv\b|inverter|panel|module|battery|شمسي|ألواح شمسية|عاكس/i, [
      BRAND(['Jinko', 'LONGi', 'Trina', 'Canadian Solar', 'JA Solar', 'Risen', 'SunPower', 'Huawei', 'SMA', 'Fronius', 'Growatt', 'Sungrow', 'Solis', 'GoodWe', 'Tesla', 'BYD', 'Pylontech']),
      N('panel_wp', 'Panel rating', 'قدرة اللوح', 'Wp', 'واط ذروة', true, numFrom(/(\d{3})\s*(?:wp|w)\b/i, /(\d{3})\s*واط/i), { applies: /panel|module|pv|لوح|ألواح/i, except: /inverter|عاكس/i }),
      A('panel_type', 'Cell type', 'نوع الخلايا', false, oneOf([['Mono PERC', /mono\s*perc/i], ['Bifacial', /bifacial/i], ['N-type TOPCon', /topcon|n-?type/i], ['Monocrystalline', /mono/i], ['Polycrystalline', /poly/i]]), { applies: /panel|module|pv|لوح|ألواح/i }),
      N('inverter_kw', 'Inverter capacity', 'قدرة العاكس', 'kW', 'كيلوواط', true, numFrom(/(\d+(?:\.\d+)?)\s*kw\b/i), { applies: /inverter|عاكس|انفرتر/i }),
    ]),
  T('generators', 'Generators', 'المولدات', /generator|genset|\bkva\b|مولد/i, [
      BRAND(['Caterpillar', 'Cummins', 'Perkins', 'FG Wilson', 'Kohler', 'SDMO', 'Aksa', 'Himoinsa', 'Volvo Penta', 'MTU', 'Doosan', 'Atlas Copco']),
      N('capacity_kva', 'Rated output', 'القدرة المقننة', 'kVA', 'ك.ف.أ', true, numFrom(/(\d+(?:\.\d+)?)\s*kva/i, /(\d+(?:\.\d+)?)\s*ك\.?ف\.?أ/i)),
      A('fuel', 'Fuel / engine', 'الوقود / المحرك', false, either(oneOf([['Diesel', /diesel|ديزل/i], ['Gas', /\bgas\b|غاز/i]]), labelled('engine|المحرك'))),
      A('enclosure', 'Enclosure', 'الغلاف', false, oneOf([['Silent / canopy', /silent|sound\s*proof|canopy|acoustic|كاتم/i], ['Open', /open\s*(?:type|frame)/i]])),
    ]),
  T('elevators', 'Elevators & escalators', 'المصاعد والسلالم المتحركة', /elevator|lift|escalator|travelator|مصعد|سلم متحرك/i, [
      BRAND(['Otis', 'Schindler', 'KONE', 'TK Elevator', 'Thyssenkrupp', 'Mitsubishi', 'Hyundai', 'Fujitec', 'Hitachi', 'Sigma', 'Orona']),
      N('capacity_kg', 'Rated load', 'الحمولة المقننة', 'kg', 'كغ', true, (t) => { const s = normText(t); const k = s.match(/(\d{3,4})\s*(?:kg|كغ|كيلو)/i); if (k) return String(Number(k[1])); const p = s.match(/(\d{1,2})\s*(?:persons?|pax|passengers?|أشخاص|شخص|راكب)/i); return p ? String(Number(p[1]) * 75) : null; }, { applies: /elevator|lift|مصعد/i }),
      N('speed_ms', 'Speed', 'السرعة', 'm/s', 'م/ث', true, numFrom(/(\d(?:\.\d+)?)\s*(?:m\/s|mps|م\/ث)/i)),
      N('stops', 'Stops', 'عدد الوقفات', 'stops', 'وقفات', false, numFrom(/(\d{1,3})\s*(?:stops?|floors?|landings?|وقفات|وقفة|طوابق)/i), { applies: /elevator|lift|مصعد/i }),
    ]),
  T('shutters', 'Garage doors & shutters', 'أبواب الكراجات والشترات', /shutter|garage\s*door|roller|sectional|high\s*speed\s*door|شتر|باب كراج|باب جراج|رول/i, [
      A('type', 'Door type', 'نوع الباب', true, oneOf([['Sectional', /sectional|مقطعي/i], ['Roller shutter', /roll(?:er|ing)|رول|شتر/i], ['High-speed', /high\s*-?\s*speed|سريع/i], ['Swing', /swing|مفصلي/i], ['Sliding', /sliding|منزلق|سحاب/i]])),
      A('material', 'Curtain / panel material', 'مادة الباب', true, oneOf([['Insulated panel', /insulated|pu\s*foam|معزول/i], ['Galvanised steel', /galvani[sz]|g\.?i\.?\b|مجلفن/i], ['Aluminium', /alumin|ألمنيوم|المنيوم/i], ['Stainless steel', /stainless|ستانلس/i], ['PVC', /\bpvc\b/i]])),
      THK(false), A('motor', 'Motor / operator', 'المحرك', false, either(labelled('motor|operator|المحرك'), oneOf([['Somfy', /somfy/i], ['Nice', /\bnice\b/i], ['FAAC', /faac/i], ['Came', /\bcame\b/i], ['Hormann', /h[oö]rmann/i]]))),
    ]),
  T('pools', 'Swimming pools', 'المسابح', /pool|spa|jacuzzi|مسبح|حوض سباحة|جاكوزي/i, [
      A('finish', 'Pool finish', 'تشطيب المسبح', true, oneOf([['Glass mosaic', /glass\s*mosaic|موزاييك زجاجي/i], ['Porcelain tile', /porcelain|بورسلين/i], ['Mosaic', /mosaic|موزاييك/i], ['Plaster / marbelite', /plaster|marbelite|pebble/i], ['Fibreglass', /fib(?:er|re)\s*glass|فايبر/i], ['Liner', /liner/i]])),
      BRAND(['Hayward', 'Pentair', 'Astral', 'Fluidra', 'Zodiac', 'Emaux', 'Speck', 'Bisazza', 'Ezarri']),
      A('filtration', 'Filtration / pump', 'الفلترة / المضخة', false, (t) => { const m = normText(t).match(/((?:sand|cartridge|glass\s*media)\s*filter[\w .]{0,20})|(\d+(?:\.\d+)?\s*hp\s*pump)/i); return m ? clean(m[1] || m[2]) : null; }),
      DIMS(false),
    ]),
  T('shade', 'Shades & tents', 'المظلات والخيام', /shade|tent|pergola|awning|canopy|gazebo|car\s*park\s*shade|مظل|خيم|برجولا/i, [
      A('fabric', 'Fabric / membrane', 'القماش / الغشاء', true, oneOf([['PVDF-coated PVC', /pvdf/i], ['PTFE', /ptfe/i], ['HDPE shade net', /hdpe|shade\s*net|شبك/i], ['PVC', /\bpvc\b/i], ['Polyester', /polyester|بوليستر/i]])),
      A('structure', 'Structure (section & finish)', 'الهيكل (القطاع والتشطيب)', true, (t) => { const m = normText(t).match(/((?:ms|mild\s*steel|gi|galvani[sz]ed|steel|alumin\w*)\s*(?:pipe|tube|section|column|structure|frame)[\w .×x\-]{0,30})|(\d+\s*[x×]\s*\d+\s*mm\s*(?:shs|rhs|pipe|tube))|(هيكل\s*[^,;]{2,30})/i); return m ? clean(m.slice(1).find(Boolean)!) : null; }),
      BRAND(['Serge Ferrari', 'Mehler', 'Heytex', 'Sattler', 'Gale Pacific', 'Coolaroo'], false),
    ]),
  T('landscaping', 'Landscaping', 'تنسيق الحدائق', /landscap|garden|turf|grass|plant|tree|palm|shrub|paver|interlock|irrigation|kerb|حديق|عشب|نجيل|شجر|نخيل|انترلوك|ري/i, [
      A('material', 'Species / material', 'النوع / المادة', true, oneOf([['Paspalum', /paspalum|باسبالم/i], ['Bermuda grass', /bermuda|برمودا/i], ['Artificial turf', /artificial|synthetic|صناعي/i], ['Interlock paver', /interlock|انترلوك/i], ['Natural stone', /natural\s*stone|حجر طبيعي/i], ['Date palm', /date\s*palm|نخل/i], ['Ghaf', /\bghaf\b|غاف/i], ['Bougainvillea', /bougainvillea|جهنمية/i], ['Drip irrigation', /drip|تنقيط/i], ['Pop-up sprinkler', /pop\s*-?\s*up|sprinkler|رشاش/i]])),
      A('size', 'Size / grade (height, pot, thickness)', 'المقاس / الدرجة', true, (t) => { const s = normText(t); const m = s.match(/(\d+(?:\.\d+)?\s*(?:m|cm|mm)\s*(?:height|high|tall|ht|girth|trunk|ارتفاع)?)\b|(\d+\s*(?:ltr|l|gallon|gal)\s*(?:pot|bag)?)|((?:height|ارتفاع)\s*[:\-]?\s*\d+(?:\.\d+)?\s*(?:m|cm))/i); return m ? clean(m.slice(1).find(Boolean)!) : null; }),
    ]),
  T('steel', 'Steel & fabrication', 'الحديد والتصنيع', /steel|beam|column|\bub\b|\buc\b|\bipe\b|\bhea\b|\bheb\b|\bshs\b|\brhs\b|\bchs\b|angle|channel|plate|purlin|stair|railing|handrail|fabricat|حديد|فولاذ|صلب|كمرة|درابزين|سلم معدني/i, [
      A('grade', 'Steel grade', 'درجة الفولاذ', true, (t) => { const m = normText(t).match(/\b(S\s?(?:235|275|355|460)(?:\s?J[0R2])?|A\s?(?:36|572|992|500)|SS\s?(?:304L?|316L?)|ST\s?(?:37|44|52)|grade\s*(?:43|50|60)|B500[ABC]?)\b|(ستانلس\s*(?:304|316))/i); return m ? clean((m[1] || m[2]).toUpperCase().replace(/\s+/g, '')) : null; }),
      A('section', 'Section / size', 'القطاع / المقاس', true, (t) => { const m = normText(t).match(/\b((?:ub|uc|ipe|ipn|hea|heb|shs|rhs|chs|upn|pfc)\s*[\d x×.]+(?:mm)?)|((?:angle|channel|plate|pipe|tube|flat\s*bar|chequer(?:ed)?\s*plate)\s*[\d x×.]+\s*(?:mm)?)|(\d+\s*[x×]\s*\d+(?:\s*[x×]\s*\d+(?:\.\d+)?)?\s*mm)/i); return m ? clean(m.slice(1).find(Boolean)!.replace(/\s+/g, ' ')) : null; }),
      A('finish', 'Protective finish', 'التشطيب الواقي', true, oneOf([['Hot-dip galvanised', /hot\s*-?\s*dip|\bhdg\b|galvani[sz]|مجلفن/i], ['Intumescent (fire) paint', /intumescent|fire\s*paint|دهان مقاوم للحريق/i], ['Powder coated', /powder\s*-?\s*coat|دهان بودرة/i], ['Epoxy paint system', /epoxy|zinc\s*rich|primer.*(?:finish|top)\s*coat|إيبوكسي/i], ['Stainless (no coating)', /stainless|ستانلس/i], ['Primer only', /primer|red\s*oxide|برايمر|أحمر مؤكسد/i]])),
      STANDARD,
    ]),
  T('masonry', 'Masonry & blockwork', 'البناء والطابوق', /block|brick|masonry|plaster|render|طابوق|بلوك|طوب|لياسة|بناء/i, [
      A('block_type', 'Block type', 'نوع الطابوق', true, oneOf([['AAC / lightweight', /\baac\b|autoclaved|light\s*weight|siporex|thermal\s*block|خفيف|حراري/i], ['Hollow concrete block', /hollow|مفرغ/i], ['Solid concrete block', /solid|مصمت/i], ['Clay brick', /clay|red\s*brick|طوب أحمر|فخار/i]]), { applies: /block|brick|masonry|طابوق|بلوك|طوب/i }),
      A('block_size', 'Block size', 'مقاس الطابوق', true, either(dims, (t) => { const m = normText(t).match(/(\d{2,3})\s*(?:mm|cm)\s*(?:thick|wide|block|wall)?/i); return m ? clean(m[0]) : null; }), { applies: /block|brick|masonry|طابوق|بلوك|طوب/i }),
      A('strength', 'Compressive strength', 'مقاومة الضغط', false, (t) => { const m = normText(t).match(/(\d+(?:\.\d+)?\s*(?:n\/mm2|n\/mm²|mpa|نيوتن))/i); return m ? clean(m[1]) : null; }),
      A('plaster_mix', 'Plaster / render system', 'نظام اللياسة', true, either(labelled('plaster|render|لياسة'), (t) => { const m = normText(t).match(/((?:cement|gypsum|pre\s*-?\s*mix\w*|ready\s*mix)\s*plaster[\w .]{0,20})|(\d+\s*mm\s*(?:thick\s*)?(?:plaster|render|لياسة))|(1\s*:\s*[3-6])/i); return m ? clean(m.slice(1).find(Boolean)!) : null; }), { applies: /plaster|render|لياسة/i }),
    ]),
  T('concrete', 'Concrete works', 'الأعمال الخرسانية', /concrete|\brcc\b|footing|slab|screed|raft|pile|خرسان|قواعد|سقف خرساني|صبة/i, [
      A('grade', 'Concrete grade', 'درجة الخرسانة', true, (t) => { const m = normText(t).match(/\b(C\s?\d{2}(?:\s?\/\s?\d{2})?)\b|(\d{2}\s*(?:n\/mm2|n\/mm²|mpa))/i); return m ? clean((m[1] || m[2]).toUpperCase().replace(/\s/g, '')) : null; }),
      A('cement', 'Cement type', 'نوع الأسمنت', false, oneOf([['SRC (sulphate resisting)', /\bsrc\b|sulphate\s*resist|مقاوم للكبريتات/i], ['OPC', /\bopc\b|ordinary\s*portland|بورتلاندي/i], ['GGBS blend', /ggbs|slag/i]])),
      A('rebar', 'Reinforcement grade', 'درجة حديد التسليح', false, (t) => { const m = normText(t).match(/\b(B500[ABC]?|grade\s*(?:60|460)|fy\s*=?\s*\d{3})\b/i); return m ? clean(m[1]) : null; }),
    ]),
  T('waterproofing', 'Waterproofing', 'العزل المائي', /waterproof|membrane|bitumen|torch|crystalline|تسريب|عزل مائي|ممبرين|بيتومين/i, [
      A('system', 'System', 'النظام', true, oneOf([['Torch-on bituminous membrane (SBS/APP)', /torch|sbs|app\b|bitumin\w*\s*membrane|ممبرين|بيتومين/i], ['Polyurethane liquid', /polyurethane|\bpu\b|بولي يوريثان/i], ['Cementitious', /cementitious|أسمنتي/i], ['Crystalline', /crystalline|بلوري/i], ['Polyurea', /polyurea/i], ['PVC / TPO sheet', /\bpvc\b|\btpo\b/i], ['Liquid-applied', /liquid|سائل/i]])),
      THK(),
      BRAND(['Sika', 'Fosroc', 'BASF', 'Master Builders', 'Mapei', 'Henkel', 'Bitumat', 'Polyglass', 'Soprema', 'Index', 'Tremco', 'Xypex', 'Penetron']),
    ]),
  T('insulation', 'Insulation', 'العزل الحراري', /insulation|rock\s*wool|glass\s*wool|\bxps\b|\beps\b|\bpir\b|elastomeric|عزل حراري|صوف صخري|فوم/i, [
      A('material', 'Insulation material', 'مادة العزل', true, oneOf([['Rock wool', /rock\s*wool|mineral\s*wool|صوف صخري/i], ['Glass wool', /glass\s*wool|fib(?:er|re)\s*glass|صوف زجاجي/i], ['XPS', /\bxps\b/i], ['EPS', /\beps\b|polystyrene|فلين/i], ['PIR / PU', /\bpir\b|\bpu\b|polyurethane|بولي يوريثان/i], ['Elastomeric (nitrile)', /elastomeric|nitrile|armaflex|kaiflex/i], ['Spray foam', /spray\s*foam|رش فوم/i]])),
      THK(), N('density', 'Density', 'الكثافة', 'kg/m³', 'كغ/م³', false, numFrom(/(\d{2,3})\s*(?:kg\/m3|kg\/m³|kg\/cum|كغ\/م)/i)),
      BRAND(['Rockwool', 'Knauf Insulation', 'Isover', 'Owens Corning', 'Kingspan', 'Armacell', 'Kaimann', 'Dow', 'Ursa'], false),
    ]),
  T('roofing', 'Roofing', 'الأسقف والتسقيف', /roof|sandwich\s*panel|metal\s*sheet|cladding|سقف|أسقف|ساندويتش|صاج/i, [
      A('system', 'Roof system', 'نظام السقف', true, oneOf([['Sandwich panel', /sandwich|ساندويتش/i], ['Profiled metal sheet', /profil\w*\s*sheet|metal\s*sheet|corrugat|صاج/i], ['Membrane', /membrane|ممبرين/i], ['Clay / concrete tiles', /\btiles?\b|قرميد/i], ['Standing seam', /standing\s*seam/i]])),
      THK(), A('insulation_core', 'Core / insulation', 'اللب / العزل', false, oneOf([['PIR', /\bpir\b/i], ['PU', /\bpu\b|polyurethane/i], ['Rock wool', /rock\s*wool/i], ['EPS', /\beps\b/i]])),
      BRAND(['Kingspan', 'Tata', 'Zamil', 'Brucha', 'Balex', 'Isopan', 'Metecno'], false),
    ]),
  T('signage', 'Signage', 'اللافتات', /sign|letter|logo|light\s*box|pylon|totem|لافت|يافط|حروف|شعار/i, [
      A('material', 'Face / letter material', 'مادة الواجهة / الحروف', true, oneOf([['Acrylic', /acrylic|أكريليك|اكريليك/i], ['ACP (aluminium composite)', /\bacp\b|aluminium\s*composite|alucobond|كلادينج/i], ['Stainless steel', /stainless|ستانلس/i], ['Brass', /brass|نحاس/i], ['Aluminium', /alumin|ألمنيوم|المنيوم/i], ['PVC foam / forex', /forex|pvc\s*foam|فوركس/i], ['Vinyl', /vinyl|فينيل/i]])),
      A('size', 'Size / letter height', 'المقاس / ارتفاع الحروف', true, either(dims, (t) => { const m = normText(t).match(/(\d+(?:\.\d+)?\s*(?:cm|mm|m)\s*(?:high|height|tall|ارتفاع)?)/i); return m ? clean(m[1]) : null; })),
      A('illumination', 'Illumination', 'الإضاءة', true, oneOf([['Halo-lit', /halo|back\s*-?\s*lit|backlit|إضاءة خلفية/i], ['Front-lit LED', /front\s*-?\s*lit|face\s*-?\s*lit|led|إضاءة أمامية/i], ['Non-illuminated', /non\s*-?\s*(?:illuminat|lit)|without\s*light|بدون إضاءة/i]])),
    ]),
  T('acrylic', 'Acrylic works', 'أعمال الأكريليك', /acrylic|perspex|plexi|أكريليك|اكريليك|بيرسبكس/i, [
      THK(), A('type', 'Sheet type', 'نوع اللوح', true, oneOf([['Cast acrylic', /\bcast\b|مصبوب/i], ['Extruded acrylic', /extruded|مبثوق/i], ['Opal', /opal|حليبي/i], ['Clear', /clear|شفاف/i], ['Coloured', /colou?r|ملون/i], ['Mirror', /mirror|مرآة/i]])),
      BRAND(['Plexiglas', 'Perspex', 'Altuglas', 'Lucite', 'Chi Mei', 'Plaskolite'], false),
    ]),
  T('upholstery', 'Upholstery, curtains & blinds', 'التنجيد والستائر', /curtain|blind|drape|sheer|upholster|sofa|cushion|fabric|ستار|ستائر|تنجيد|كنب|قماش/i, [
      A('fabric', 'Fabric', 'القماش', true, either(labelled('fabric|material|القماش'), oneOf([['Blackout', /blackout|تعتيم/i], ['Sheer / voile', /sheer|voile|شيفون|فوال/i], ['Velvet', /velvet|مخمل/i], ['Linen', /linen|كتان/i], ['Leather', /leather|جلد/i], ['Polyester', /polyester|بوليستر/i], ['Screen fabric', /screen|سكرين/i]]))),
      A('mechanism', 'Track / mechanism', 'المجرى / آلية التشغيل', true, oneOf([['Motorised (Somfy)', /somfy/i], ['Motorised', /motori[sz]|electric|محرك|كهربائي/i], ['Manual', /manual|chain|cord|يدوي/i]]), { applies: /curtain|blind|drape|ستار|ستائر|رول/i }),
      BRAND(['Somfy', 'Hunter Douglas', 'Silent Gliss', 'Kvadrat', 'Romo', 'Casamance', 'Zimmer'], false),
    ]),
  T('interiordesign', 'Interior design services', 'خدمات التصميم الداخلي', /design|concept|render|3d|drawing|visuali[sz]|تصميم|مخططات|رسومات/i, [
      A('stage', 'Design stage', 'مرحلة التصميم', true, oneOf([['Concept', /concept|مفهوم|مبدئي/i], ['Design development', /design\s*development|schematic|تطوير/i], ['Detailed / IFC', /\bifc\b|detail|construction\s*drawings|shop\s*drawings|تفصيلي|تنفيذي/i], ['Authority approval', /authority|municipality|approval|بلدية|اعتماد/i]])),
      A('deliverable', 'Deliverables', 'المخرجات', true, either(labelled('deliverables?|المخرجات'), oneOf([['3D renders', /3d|render|تصاميم ثلاثية/i], ['Drawings set', /drawings?|layout|مخطط/i], ['Material board / FF&E', /material\s*board|ff&e|mood\s*board|عينات/i], ['BOQ / specification', /boq|specification|جدول كميات/i]]))),
      N('revisions', 'Revisions included', 'عدد التعديلات', 'rounds', 'مرات', false, numFrom(/(\d)\s*(?:revisions?|rounds?|تعديل)/i)),
    ]),
  T('consultancy', 'Engineering & architectural consultancy', 'الاستشارات الهندسية والمعمارية', /design|drawing|supervision|consult|approval|study|survey|تصميم|إشراف|استشار|دراسة|مسح/i, [
      A('stage', 'Stage / service', 'المرحلة / الخدمة', true, oneOf([['Concept design', /concept|مبدئي/i], ['Schematic / DD', /schematic|design\s*development/i], ['Detailed design / IFC', /\bifc\b|detailed|تفصيلي/i], ['Authority approvals', /authority|approval|permit|بلدية|ترخيص|اعتماد/i], ['Site supervision', /supervision|إشراف/i], ['Survey / study', /survey|study|مسح|دراسة/i]])),
      A('deliverable', 'Deliverables', 'المخرجات', true, either(labelled('deliverables?|المخرجات'), oneOf([['Drawings set', /drawings?|مخطط/i], ['Report', /report|تقرير/i], ['BOQ / specification', /boq|specification|جدول كميات/i], ['Calculations', /calculation|حسابات/i]]))),
      A('authority', 'Authority', 'الجهة', false, oneOf([['Dubai Municipality', /dubai\s*municipality|\bdm\b|بلدية دبي/i], ['Dubai Development Authority', /\bdda\b|development\s*authority/i], ['Trakhees', /trakhees|تراخيص/i], ['Civil Defence', /civil\s*defen[cs]e|الدفاع المدني/i], ['DEWA', /dewa|ديوا/i]])),
    ]),
  T('manufacturing', 'Job-shop manufacturing', 'التصنيع حسب الطلب', /fabricat|machin|cnc|laser|bend|weld|cast|mould|تصنيع|خراطة|ليزر|لحام|قص/i, [
      A('material', 'Material', 'المادة', true, either(labelled('material|المادة'), oneOf([['Stainless steel', /stainless|ستانلس/i], ['Mild steel', /mild\s*steel|\bms\b|حديد/i], ['Aluminium', /alumin|ألمنيوم|المنيوم/i], ['Brass', /brass|نحاس أصفر/i], ['Copper', /copper|نحاس/i], ['Acrylic', /acrylic|أكريليك/i], ['HDPE / nylon', /hdpe|nylon|نايلون/i]]))),
      A('grade', 'Grade', 'الدرجة', true, (t) => { const m = normText(t).match(/\b(SS\s?(?:304L?|316L?|430)|(?:AL\s?)?(?:6061|6063|5083|1050)(?:-T\d)?|S\s?(?:235|275|355)|ST\s?37|C\s?45|EN\s?\d{1,3})\b/i); return m ? clean(m[1].toUpperCase()) : null; }),
      THK(), A('finish', 'Finish / tolerance', 'التشطيب / التفاوت', false, either(labelled('finish|tolerance|التشطيب'), (t) => { const m = normText(t).match(/(±\s*\d+(?:\.\d+)?\s*mm)|(powder\s*coat\w*|anodi[sz]\w*|brushed|mirror\s*polish\w*|galvani[sz]\w*)/i); return m ? clean(m[1] || m[2]) : null; })),
    ]),
  T('cleaning', 'Cleaning', 'التنظيف', /clean|housekeep|deep\s*clean|polish|sanitis|تنظيف|تعقيم/i, [
      A('method', 'Method / scope', 'الطريقة / النطاق', true, either(labelled('method|scope|الطريقة'), oneOf([['Deep cleaning', /deep|عميق/i], ['Post-construction cleaning', /post\s*-?\s*construction|after\s*construction|بعد البناء/i], ['Steam cleaning', /steam|بخار/i], ['Floor scrubbing & polishing', /scrub|polish|تلميع/i], ['Regular / periodic', /regular|daily|weekly|monthly|دوري|يومي|أسبوعي/i]]))),
      A('products', 'Chemicals / products', 'المواد والمنظفات', true, either(labelled('chemicals?|products?|detergents?|المواد|المنظفات'), oneOf([['Diversey', /diversey|taski/i], ['Ecolab', /ecolab/i], ['Kärcher', /k[aä]rcher/i], ['Eco-certified products', /eco\s*-?\s*(?:friendly|certified)|green\s*seal|صديق للبيئة/i]]))),
      N('crew', 'Crew size', 'عدد العمال', 'persons', 'عمال', false, numFrom(/(\d{1,3})\s*(?:cleaners?|staff|persons?|workers?|عامل|عمال)/i)),
    ]),
  T('facade', 'Facade cleaning', 'تنظيف الواجهات', /facade|window\s*clean|glass\s*clean|واجه/i, [
      A('access', 'Access method', 'طريقة الوصول', true, oneOf([['BMU / gondola', /\bbmu\b|gondola|cradle|جندول/i], ['Rope access', /rope|حبال/i], ['Boom lift / MEWP', /boom|mewp|cherry\s*picker|scissor|رافعة/i], ['Water-fed pole', /water\s*-?\s*fed|pole/i]])),
      A('products', 'Chemicals / products', 'المواد والمنظفات', true, either(labelled('chemicals?|products?|detergents?|المواد|المنظفات'), oneOf([['Neutral pH detergent', /neutral|ph\s*neutral|متعادل/i], ['Deionised water', /deioni[sz]ed|pure\s*water|ماء مقطر/i]]))),
      N('frequency', 'Cleans per year', 'مرات التنظيف سنويًا', 'per year', 'سنويًا', false, numFrom(/(\d{1,2})\s*(?:times|cleans?|visits?)\s*(?:per|a|\/)\s*year/i)),
    ]),
  T('watertank', 'Water tank cleaning', 'تنظيف خزانات المياه', /tank|خزان/i, [
      A('method', 'Method', 'الطريقة', true, either(labelled('method|الطريقة'), oneOf([['Drain, scrub, disinfect & rinse', /disinfect|chlorinat|تعقيم|كلور/i], ['Drain & scrub', /scrub|drain|تفريغ/i]]))),
      A('disinfectant', 'Disinfectant & dose', 'المعقم والتركيز', true, (t) => { const m = normText(t).match(/((?:chlorine|sodium\s*hypochlorite|hydrogen\s*peroxide|silver)[\w .]{0,15}(?:\d+\s*ppm)?)|(\d+\s*ppm)|(كلور[^,;]{0,15})/i); return m ? clean(m.slice(1).find(Boolean)!) : null; }),
      A('certificate', 'Lab report / approval', 'تقرير المختبر / الاعتماد', false, oneOf([['DM-approved lab report', /lab|report|certificate|dm\s*approved|municipality|مختبر|شهادة|بلدية/i]])),
    ]),
  T('acduct', 'AC duct cleaning', 'تنظيف مجاري التكييف', /duct|ahu|fcu|diffuser|grille|مجاري|دكت/i, [
      A('method', 'Method', 'الطريقة', true, oneOf([['Robotic brushing + HEPA vacuum', /robot|روبوت/i], ['Rotary brushing + vacuum', /brush|فرشاة/i], ['HEPA vacuum', /hepa|vacuum|شفط/i], ['NADCA ACR', /nadca/i]])),
      A('sanitiser', 'Sanitiser / product', 'المعقم / المنتج', true, either(labelled('sanitis\\w*|sanitiz\\w*|disinfectant|chemical|المعقم'), oneOf([['Sanitiser applied (product named)', /sanitis|sanitiz|disinfect|fogging|تعقيم/i]]))),
      STANDARD,
    ]),
  T('pestcontrol', 'Pest control', 'مكافحة الحشرات', /pest|termite|cockroach|rodent|rat|mosquito|bed\s*bug|fumigat|حشرات|نمل أبيض|صراصير|قوارض|تبخير/i, [
      A('target', 'Target pest', 'الآفة المستهدفة', true, oneOf([['Termites', /termite|نمل أبيض|أرضة/i], ['Cockroaches', /cockroach|صراصير/i], ['Rodents', /rodent|rat|mice|mouse|قوارض|فئران/i], ['Bed bugs', /bed\s*bug|بق/i], ['Mosquitoes / flies', /mosquito|fl(?:y|ies)|بعوض|ذباب/i], ['General pests', /general|all\s*pests|عام/i]])),
      A('chemical', 'Chemical / active ingredient (DM-approved)', 'المبيد / المادة الفعالة (معتمد)', true, either(labelled('chemical|product|active\\s*ingredient|المبيد|المادة الفعالة'), (t) => { const m = normText(t).match(/\b(fipronil|imidacloprid|bifenthrin|cypermethrin|deltamethrin|permethrin|brodifacoum|bromadiolone|hydramethylnon|termidor|premise|gel\s*bait|phosphine)\b/i); return m ? clean(m[1]) : null; })),
      N('visits', 'Visits', 'عدد الزيارات', 'visits', 'زيارات', false, numFrom(/(\d{1,2})\s*(?:visits?|treatments?|services?|زيارات|زيارة)/i)),
    ]),
  T('movers', 'Movers', 'نقل الأثاث', /mov(?:e|ing|ers)|relocat|packing|truck|transport|نقل|تغليف|شاحنة/i, [
      A('vehicle', 'Vehicle / volume', 'المركبة / الحجم', true, (t) => { const m = normText(t).match(/(\d+(?:\.\d+)?\s*(?:ton|t)\s*(?:truck|lorry|pickup)?)\b|(\d+\s*(?:cbm|m3|m³))|(\d+\s*(?:ft|feet)\s*(?:truck|container))|(شاحنة\s*[^,;]{1,20})/i); return m ? clean(m.slice(1).find(Boolean)!) : null; }),
      A('packing', 'Packing materials', 'مواد التغليف', true, either(labelled('packing|مواد التغليف'), oneOf([['Boxes + bubble wrap + stretch film', /bubble|stretch|فقاعات/i], ['Wooden crates', /crate|صناديق خشب/i], ['Cartons', /carton|box|كرتون/i]]))),
      A('insurance', 'Insurance cover', 'التأمين', false, (t) => { const m = normText(t).match(/(insur\w*[\w .]{0,25})|(تأمين[^,;]{0,20})/i); return m ? clean(m[1] || m[2]) : null; }),
    ]),
  T('scaffolding', 'Scaffolding', 'السقالات', /scaffold|cup\s*-?\s*lock|ring\s*-?\s*lock|mobile\s*tower|سقال/i, [
      A('system', 'System', 'النظام', true, oneOf([['Cup-lock', /cup\s*-?\s*lock/i], ['Ring-lock', /ring\s*-?\s*lock|layher/i], ['Tube & clamp', /tube\s*(?:&|and)\s*(?:clamp|coupler|fitting)/i], ['Mobile tower', /mobile|tower|برج متحرك/i], ['Frame', /frame|إطار/i]])),
      N('height_m', 'Height', 'الارتفاع', 'm', 'م', true, numFrom(/(\d+(?:\.\d+)?)\s*(?:m|meters?|metres?|متر)\s*(?:high|height|tall|ارتفاع)?/i)),
      A('inspection', 'Third-party inspection', 'الفحص من جهة ثالثة', false, oneOf([['Third-party inspected & tagged', /third\s*-?\s*party|inspect|scaff\s*tag|tagged|فحص/i]])),
    ]),
  T('demolition', 'Demolition & strip-out', 'الهدم والإزالة', /demoli|strip\s*-?\s*out|dismantl|removal|breaking|هدم|إزالة|تكسير|فك/i, [
      A('method', 'Method', 'الطريقة', true, oneOf([['Mechanical (excavator / breaker)', /mechanical|excavator|breaker|jcb|آلي|حفار/i], ['Manual', /manual|hand|يدوي/i], ['Controlled / diamond cutting', /controlled|diamond|wire\s*saw|core|قص/i]])),
      A('disposal', 'Debris disposal', 'التخلص من المخلفات', true, (t) => { const m = normText(t).match(/((?:debris|waste|rubble)\s*(?:disposal|removal)[\w .,]{0,30})|((?:municipality|dm)\s*-?\s*approved\s*(?:dump|landfill|site))|(approved\s*(?:dump|landfill|disposal)\s*site)|(ترحيل المخلفات[^,;]{0,20})|(مكب معتمد)/i); return m ? clean(m.slice(1).find(Boolean)!) : null; }),
    ]),
].map((t) => [t.code, t]));

// Trades whose quotes mix many kinds of line. Each LINE of such a quote is read as the trade its own
// words name (a fit-out's wardrobe line is joinery, its ceiling line is gypsum). A line naming none of
// them is a preliminary or a lump sum with no material, and no mandatory specification applies.
export const COMPOSITE = new Set(['fitout', 'mep', 'general', 'interiordesign', 'handyman']);
const LINE_ORDER = ['hvac', 'elevators', 'generators', 'solar', 'fire', 'security', 'networking', 'avsystems', 'smarthome', 'electrical', 'plumbing',
  'glazing', 'joinery', 'gypsum', 'tiling', 'flooring', 'carpet', 'wallpaper', 'painting', 'waterproofing', 'insulation', 'roofing', 'concrete',
  'masonry', 'steel', 'signage', 'acrylic', 'upholstery', 'shutters', 'shade', 'landscaping', 'pools'];
const MEP_ORDER = ['hvac', 'fire', 'electrical', 'plumbing', 'generators', 'networking', 'security', 'insulation'];

// Lines that carry no material: labour, logistics and money lines. Never held for a specification.
export const NON_MATERIAL = /^(?:\d+[.)]\s*)?(?:labou?r(?:\s*charges?)?|installation\s*(?:charges?|labou?r|only)|fixing\s*only|testing|commissioning|t\s*&\s*c|transport(?:ation)?|delivery(?:\s*charges?)?|mobili[sz]ation|demobili[sz]ation|preliminar(?:y|ies)|site\s*(?:clean|set\s*-?\s*up|supervision)|supervision|management\s*fee|overheads?|profit|contingenc\w*|discount|vat|tax|insurance|permits?|authority\s*fees?|design\s*fee|as\s*-?\s*built|handover|أجور|أجرة|نقل|توصيل|تركيب فقط|فحص|تشغيل تجريبي|خصم|ضريبة|رسوم)(?:\b|\s|$)/i;

/** The trade of a quote, from its category — the same vocabulary as fn_quote_spec_group. */
export function tradeOfCategory(category: string | null | undefined): string {
  const c = String(category ?? '').toLowerCase();
  const rules: [RegExp, string][] = [
    [/duct.?clean|ac.?duct/, 'acduct'], [/facade.?clean/, 'facade'], [/water.?tank/, 'watertank'],
    [/cctv|surveillance|security|access.?control|intercom|alarm/, 'security'], [/fire|safety|sprinkler|extinguisher|civil.?defen/, 'fire'],
    [/scaffold/, 'scaffolding'], [/demolition|strip.?out/, 'demolition'], [/garage.?door|shutter|rolling/, 'shutters'],
    [/elevator|escalator|^lift|lifts/, 'elevators'], [/generator/, 'generators'], [/solar|photovolt|shams/, 'solar'], [/swimming|pool/, 'pools'],
    [/tent|shade|pergola|awning|gazebo/, 'shade'], [/landscap|garden|softscape|hardscape|irrigation/, 'landscaping'], [/pest/, 'pestcontrol'],
    [/mover|moving|relocation|packing/, 'movers'], [/upholstery|curtain|blind|sofa/, 'upholstery'], [/wallpaper|wall covering/, 'wallpaper'],
    [/carpet/, 'carpet'], [/tiling|tile|marble|granite/, 'tiling'], [/floor|spc|vinyl|lvt|epoxy.?floor|parquet|laminate/, 'flooring'],
    [/paint/, 'painting'], [/gypsum|false.?ceiling|ceiling|drywall|plasterboard|partition/, 'gypsum'], [/waterproof/, 'waterproofing'],
    [/insulation/, 'insulation'], [/roofing|^roof|roof /, 'roofing'], [/job.?shop|manufactur/, 'manufacturing'], [/steel|fabrication/, 'steel'],
    [/masonry|block|^plaster/, 'masonry'], [/smart.?home|home.?automation|automation|knx/, 'smarthome'], [/av.?system|audio.?visual|audio visual/, 'avsystems'],
    [/network|structured.?cabl/, 'networking'], [/signage|sign.?board|3d letter/, 'signage'], [/acrylic|perspex|plexiglass/, 'acrylic'],
    [/interior.?design/, 'interiordesign'], [/engineering|architect|consultanc/, 'consultancy'], [/fit.?out/, 'fitout'], [/combined.?mep|^mep$|mep/, 'mep'],
    [/glass|glaz|alumin|curtain.?wall|shopfront|balustrad/, 'glazing'], [/joinery|kitchen|furniture|carpentr|cabinet|wardrobe|cupboard/, 'joinery'],
    [/hvac|^ac-|air.?con|duct|chiller|cooling|ac.?maintenance/, 'hvac'], [/electric|wiring|dewa/, 'electrical'], [/plumb|sanitary|drainage/, 'plumbing'],
    [/clean/, 'cleaning'], [/concrete/, 'concrete'],
  ];
  for (const [re, g] of rules) if (re.test(c)) return g;
  return 'general';
}

/** The trade one LINE is read as. */
export function tradeOfLine(quoteTrade: string, text: string): string | null {
  if (!COMPOSITE.has(quoteTrade)) return TRADES[quoteTrade] ? quoteTrade : null;
  const order = quoteTrade === 'mep' ? MEP_ORDER : LINE_ORDER;
  for (const code of order) if (TRADES[code].kw.test(text)) return code;
  return null;
}

// ---------------------------------------------------------------------------------------------
// THE THREE QUOTE-LEVEL TERMS (founder, 14 Sep 2026: "by details missing from supplier i literally
// mean all these": material specs per line, a concrete delivery date or lead time, installation if
// applicable, warranty if applicable). Delivery applies to every quote. Installation and warranty
// apply per trade, decided here and nowhere else, so applicability is never a guess:
//   * installation does NOT apply where the work itself is the installation or there is nothing to
//     install (services, painting, waterproofing, blockwork, concrete, planting, scaffolding), and
//     does not apply when the customer asked for supply only (request.requirements.installation);
//   * warranty does NOT apply to services with no lasting product (cleaning, movers, scaffold hire,
//     demolition, design and consultancy), and applies to pest control only for termite work.
// ---------------------------------------------------------------------------------------------
const NO_INSTALL = new Set(['cleaning', 'facade', 'watertank', 'acduct', 'pestcontrol', 'movers', 'demolition', 'consultancy', 'interiordesign',
  'painting', 'waterproofing', 'masonry', 'concrete', 'landscaping', 'scaffolding']);
const NO_WARRANTY = new Set(['cleaning', 'facade', 'watertank', 'acduct', 'movers', 'scaffolding', 'demolition', 'consultancy', 'interiordesign']);
const WARRANTY_ONLY_IF: Record<string, RegExp> = { pestcontrol: /termite|نمل أبيض|أرضة/i };

export function installApplies(trade: string): boolean { return !!TRADES[trade] && !NO_INSTALL.has(trade); }
export function warrantyApplies(trade: string, text: string): boolean {
  if (!TRADES[trade] || NO_WARRANTY.has(trade)) return false;
  const only = WARRANTY_ONLY_IF[trade];
  return only ? only.test(text) : true;
}

/** The attributes asked of one line of a given trade. */
export function attrsForLine(trade: string, text: string): Attr[] {
  const t = TRADES[trade]; if (!t) return [];
  return t.attrs.filter((a) => (!a.applies || a.applies.test(text)) && (!a.except || !a.except.test(text)));
}
