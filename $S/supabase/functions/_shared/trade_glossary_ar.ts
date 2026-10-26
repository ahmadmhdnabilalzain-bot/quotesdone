// trade_glossary_ar.ts — the Arabic of OUR OWN keys: counted nouns, units, trade codes, attribute keys.
//
// 23 Sep 2026, seat ceo, decision point trade_glossary_ar (founder_instruction 890: no word matching).
// Until today this file also carried a 1,500-line English → Arabic phrase glossary and `arTrade()`, which
// translated a supplier's or customer's own words by substituting known phrases longest-first. That is word
// matching deciding what text means, and it printed half-translated lines. It is gone: a person's words are now
// translated natively by reasoning (_shared/reasoned_governance.ts nativeArabic / arabicOf, cached in
// public.arabic_translation), and a document whose lines are not all translated is held, not sent.
// What stays here is keyed: a closed vocabulary of our own codes (a trade code, a unit key, an attribute key),
// looked up by exact key — plus the proper-noun lists the Arabic tests use to guard our own outgoing text.

// ── Arabic counted nouns (moved here from quote_documents.ts so both can use them) ──────────────
export type Unit = 'day' | 'week' | 'month' | 'year';
const FORMS: Record<Unit, [string, string, string, string]> = {
  day: ['يوم واحد', 'يومان', 'أيام', 'يومًا'], week: ['أسبوع واحد', 'أسبوعان', 'أسابيع', 'أسبوعًا'],
  month: ['شهر واحد', 'شهران', 'أشهر', 'شهرًا'], year: ['سنة واحدة', 'سنتان', 'سنوات', 'سنة'],
};
export const WORKING_FORMS: [string, string, string, string] = ['يوم عمل واحد', 'يوما عمل', 'أيام عمل', 'يوم عمل'];
export const UNIT_FORMS = FORMS;
/** Arabic counted noun: 1 and 2 have their own forms, 3-10 take the plural, 11+ the singular. */
export function arCount(n: number, unit: Unit, working = false): string {
  const f = working && unit === 'day' ? WORKING_FORMS : FORMS[unit];
  if (n === 1) return f[0]; if (n === 2) return f[1];
  return `${n} ${n >= 3 && n <= 10 ? f[2] : f[3]}`;
}

// ── Units of measure (a quantity column, and a number's unit inside a phrase) ────────────────────
export const UNITS: Record<string, string> = {
  'nos': 'عدد', 'no': 'عدد', 'no.': 'عدد', 'nr': 'عدد', 'each': 'عدد', 'ea': 'عدد', 'pcs': 'قطعة', 'pc': 'قطعة', 'piece': 'قطعة', 'pieces': 'قطعة',
  'set': 'طقم', 'sets': 'طقم', 'lot': 'مقطوعية', 'ls': 'مقطوعية', 'l.s.': 'مقطوعية', 'lump sum': 'مقطوعية', 'job': 'مقطوعية', 'item': 'بند',
  'm': 'م', 'mtr': 'م', 'meter': 'م', 'metre': 'م', 'lm': 'م.ط', 'rm': 'م.ط', 'rmt': 'م.ط', 'running meter': 'م.ط', 'running metre': 'م.ط',
  'm2': 'م²', 'm²': 'م²', 'sqm': 'م²', 'sq.m': 'م²', 'sq m': 'م²', 'sq.m.': 'م²', 'sqft': 'قدم²', 'sq ft': 'قدم²', 'm3': 'م³', 'm³': 'م³', 'cum': 'م³',
  'kg': 'كغ', 'ton': 'طن', 'tons': 'طن', 'mt': 'طن', 'tr': 'طن تبريد', 'unit': 'وحدة', 'units': 'وحدة', 'day': 'يوم', 'days': 'يوم',
  'hr': 'ساعة', 'hrs': 'ساعة', 'hour': 'ساعة', 'hours': 'ساعة', 'ltr': 'لتر', 'l': 'لتر', 'litre': 'لتر', 'liter': 'لتر', 'roll': 'لفة', 'rolls': 'لفة',
  'box': 'علبة', 'pair': 'زوج', 'pairs': 'زوج', 'point': 'نقطة', 'points': 'نقطة', 'pt': 'نقطة', 'sheet': 'لوح', 'sheets': 'لوح', 'panel': 'لوح',
  'bag': 'كيس', 'bags': 'كيس', 'drum': 'برميل', 'visit': 'زيارة', 'visits': 'زيارة', 'month': 'شهر', 'months': 'شهر', 'trip': 'رحلة', 'room': 'غرفة',
};
export function arUnit(s: unknown): string | null {
  if (/[؀-ۿ]/.test(String(s ?? ''))) return String(s);
  const n = String(s ?? '').toLowerCase().trim(); return n ? (UNITS[n] ?? null) : null;
}

// A number's unit inside running text: "18mm", "5 TR", "60 min", "2 coats". [singular, plural 3-10].
// ── Proper nouns: kept exactly as written, never translated ───────────────────────────────────────
// Brands (all trades), standards and authorities, and the trade codes an Arabic specification also
// writes in Latin letters. A Latin word in the Arabic document's primary text must be one of these
// or carry a digit (a model or grade code: R410A, FDYQ180LA, S355, IP65, E1) — the tests assert it.
export const BRANDS = [
  // HVAC
  'Daikin', 'Gree', 'Midea', 'Carrier', 'LG', 'Mitsubishi Electric', 'Mitsubishi Heavy', 'Mitsubishi', 'Samsung', 'Trane', 'York', 'Hitachi', 'Toshiba', 'Panasonic', 'Fujitsu',
  'O General', 'Haier', 'Hisense', 'TCL', 'Zamil', 'Petra', 'Blue Star', 'Voltas', 'Sharp', 'Super General', 'Westinghouse', 'McQuay', 'Lennox', 'Rheem', 'Systemair', 'Kruger',
  // joinery, boards, laminates, hardware
  'Blum', 'Hettich', 'Grass', 'Hafele', 'Häfele', 'Salice', 'Egger', 'Kronospan', 'Kastamonu', 'Finsa', 'Formica', 'Wilsonart', 'Greenlam', 'Merino', 'Arpa', 'Abet Laminati', 'Fenix',
  'Rehau', 'Dorma', 'Dormakaba', 'Assa Abloy', 'Yale', 'Sadolin', 'Hranipex', 'Sonae Arauco', 'Duropal', 'Polyrey', 'Senosan',
  // paints, chemicals, gypsum, ceilings
  'Jotun', 'Dulux', 'National Paints', 'Asian Paints', 'Berger', 'Caparol', 'Hempel', 'Sherwin-Williams', 'Sika', 'Fosroc', 'Henkel', 'Mapei', 'Laticrete', 'Ardex', 'Weber',
  'Knauf', 'Gyproc', 'USG', 'Saint-Gobain', 'Saint Gobain', 'Armstrong', 'Rockfon', 'Rockwool', 'Kingspan', 'Isover', 'Bostik', 'Pidilite', 'Fevicol', 'Kansai',
  // sanitary, plumbing, pumps
  'Grohe', 'Hansgrohe', 'Kohler', 'Duravit', 'Roca', 'Villeroy & Boch', 'Geberit', 'TOTO', 'RAK Ceramics', 'RAK', 'Ideal Standard', 'American Standard', 'Ariston', 'Grundfos', 'Wilo',
  'Pedrollo', 'Lowara', 'Pentair', 'Hayward', 'Astral', 'Aquatherm', 'Cosmoplast', 'Danfoss',
  // electrical, lighting, generators, solar, lifts
  'Schneider Electric', 'Schneider', 'ABB', 'Legrand', 'Siemens', 'Hager', 'MK', 'Philips', 'Osram', 'Signify', 'Ducab', 'Cummins', 'Perkins', 'Caterpillar', 'FG Wilson', 'Jinko',
  'LONGi', 'Trina', 'Huawei', 'SMA', 'Fronius', 'Growatt', 'Otis', 'Schindler', 'KONE', 'Thyssenkrupp', 'TK Elevator', 'Fuji',
  // security, networks, AV, smart home
  'Hikvision', 'Dahua', 'Axis', 'Bosch', 'Honeywell', 'Uniview', 'Hanwha', 'Hochiki', 'Notifier', 'Apollo', 'Tyco', 'Cisco', 'Ubiquiti', 'Aruba', 'TP-Link', 'Fortinet',
  'Crestron', 'Control4', 'Somfy', 'Bose', 'JBL', 'Sonos', 'Epson', 'BenQ', 'Yamaha', 'Shure', 'Lutron',
  // glass, aluminium, doors, flooring, tiles
  'Guardian', 'Emirates Glass', 'Technal', 'Schüco', 'Schuco', 'Reynaers', 'Alumil', 'Gulf Extrusions', 'Hörmann', 'Hormann', 'Tarkett', 'Forbo', 'Interface', 'Quick-Step',
  'Pergo', 'Kährs', 'Porcelanosa', 'Marazzi', 'Cersanit', 'Florim', 'Atlas Concorde',
];
export const STANDARDS = [
  'BS EN', 'BS', 'EN', 'ASHRAE', 'ISO', 'ASTM', 'DIN', 'UL', 'NFPA', 'IEC', 'SASO', 'ESMA', 'SIRA', 'DCD', 'DEWA', 'ADDC', 'SEWA', 'FEWA', 'ANSI', 'CE', 'SMACNA',
  'CIBSE', 'NEMA', 'LEED', 'Estidama', 'FSC', 'PEFC', 'CARB', 'BSI', 'EPA', 'NEBOSH', 'OSHA', 'IP', 'Trakhees', 'Nakheel', 'Emaar', 'TDRA', 'NOL', 'DET',
];
export const CODES = [
  'MDF', 'HDF', 'OSB', 'HPL', 'CPL', 'LVT', 'SPC', 'WPC', 'PVC', 'UPVC', 'uPVC', 'CPVC', 'PPR', 'HDPE', 'GI', 'SS', 'MS', 'LED', 'CCTV', 'HVAC', 'MEP', 'VRF', 'VRV', 'FCU', 'AHU',
  'BMS', 'NVR', 'DVR', 'POE', 'PoE', 'UPS', 'ATS', 'DB', 'MCB', 'MCCB', 'RCCB', 'RCBO', 'ELCB', 'SMDB', 'MDB', 'BOQ', 'AMC', 'ACP', 'GRC', 'GRP', 'FRP', 'EPDM', 'XPS', 'EPS', 'PIR',
  'PU', 'TPO', 'AV', 'HDMI', 'USB', 'KNX', 'DALI', 'WiFi', 'Wi-Fi', 'UV', 'RAL', 'NCS', 'ABS', 'SIRA', 'IPS', 'OLED', 'CAT', 'NOC', 'TR', 'AED', 'PPGI', 'RCC', 'PCC', 'ELV', 'QuotesDone', 'CNC',
];
const PROPER_PHRASES = [...BRANDS, ...STANDARDS, ...CODES].sort((a, b) => b.length - a.length);
const PROPER_WORDS = new Set(PROPER_PHRASES.flatMap((p) => p.toLowerCase().split(/[\s]+/)).concat(['&']));
/** May this Latin word stand in an Arabic document's primary text? A brand, standard, code, or a word
 * carrying a digit (a model/grade code). Everything else is English left untranslated. */
export function isProperToken(w: string): boolean {
  const t = String(w || '').replace(/^[^\w&]+|[^\w&]+$/g, '');
  if (!t) return true;
  if (/\d/.test(t)) return true;
  return PROPER_WORDS.has(t.toLowerCase());
}

// ── Trades: every code in src/content/categories.json (56 rows read 14 Sep 2026) ─────────────────
// The Arabic names are the ones categories.json carries; the test reads that file and asserts every
// code is here, so a trade added to the site without an Arabic name fails CI.
export const CATEGORY_AR: Record<string, string> = {
  'acrylic': 'الأكريليك', 'aluminium': 'أعمال الألمنيوم', 'av-systems': 'الأنظمة السمعية والبصرية', 'blinds-curtains': 'الستائر والبلايند',
  'carpentry-joinery': 'النجارة وأعمال الخشب', 'carpets': 'السجاد والموكيت', 'cleaning': 'التنظيف',
  'combined-mep': 'الأعمال الكهروميكانيكية المتكاملة', 'commercial-retail-fitout': 'تجهيز المحلات والمساحات التجارية',
  'custom-furniture': 'تصنيع الأثاث حسب الطلب', 'demolition': 'الهدم', 'electrical': 'الكهرباء', 'elevators': 'المصاعد',
  'engineering-and-architectural-consultancies': 'الاستشارات الهندسية والمعمارية', 'epoxy-flooring': 'أرضيات الإيبوكسي والراتنج',
  'facade-cleaning': 'تنظيف الواجهات والأبراج', 'fitout': 'التشطيبات الداخلية', 'flooring': 'الأرضيات', 'garage-doors': 'أبواب المرائب والشتر',
  'general-building-contracting': 'المقاولات العامة للمباني', 'general-services-other': 'الخدمات العامة والحرف الأخرى', 'generators': 'المولدات الكهربائية',
  'glass': 'الزجاج والتزجيج', 'gypsum': 'الجبس والأسقف', 'hvac': 'التكييف والتبريد', 'insulation': 'العزل الحراري', 'interior-design': 'التصميم الداخلي',
  'it-networking': 'تقنية المعلومات والشبكات', 'job-shop-manufacturing': 'التصنيع حسب الطلب', 'kitchens': 'المطابخ', 'landscaping': 'تنسيق الحدائق',
  'marble-granite': 'الرخام والجرانيت', 'masonry': 'أعمال البناء والأعمال المدنية', 'mep': 'الأعمال الكهروميكانيكية', 'movers': 'نقل الأثاث والانتقال',
  'painting': 'الدهانات', 'pest': 'مكافحة الحشرات', 'plumbing': 'السباكة والأدوات الصحية', 'roofing': 'الأسطح', 'safety': 'السلامة من الحريق ومكافحته',
  'scaffolding': 'السقالات', 'security': 'كاميرات المراقبة والأنظمة الأمنية', 'signage': 'اللافتات', 'smart-home': 'المنزل الذكي والأتمتة',
  'solar': 'الطاقة الشمسية', 'steel': 'الحديد والأعمال المعدنية', 'structural-steel-fabrication': 'الهياكل الفولاذية والتصنيع', 'swimming-pools': 'المسابح',
  'tents-and-shade-structures': 'الخيام والمظلات', 'tiling': 'التبليط', 'upholstery': 'التنجيد والستائر', 'wallpaper': 'ورق الجدران',
  'water-tank-cleaning': 'تنظيف خزانات المياه', 'waterproofing': 'العزل المائي',
};

/** The English trade names, as categories.json spells them. */
export const CATEGORY_EN: Record<string, string> = {
  "acrylic": "Acrylic",
  "aluminium": "Aluminium Works",
  "av-systems": "AV Systems",
  "blinds-curtains": "Curtains & Blinds",
  "carpentry-joinery": "Carpentry & Joinery",
  "carpets": "Carpets",
  "cleaning": "Cleaning",
  "combined-mep": "Combined MEP (Mechanical, Electrical & Plumbing)",
  "commercial-retail-fitout": "Commercial & Retail Fit-Out",
  "custom-furniture": "Custom Furniture Manufacturing",
  "demolition": "Demolition",
  "electrical": "Electrical",
  "elevators": "Elevators & Lifts",
  "engineering-and-architectural-consultancies": "Engineering & Architectural Consultancies",
  "epoxy-flooring": "Epoxy & Resin Flooring",
  "facade-cleaning": "Facade / High-Rise Cleaning",
  "fitout": "Fit-out / Interior",
  "flooring": "Flooring",
  "garage-doors": "Garage Doors & Shutters",
  "general-building-contracting": "General Building Contracting",
  "general-services-other": "General Services & Other Trades",
  "generators": "Generators",
  "glass": "Glass & Glazing",
  "gypsum": "Gypsum / Ceiling",
  "hvac": "HVAC / Air Conditioning",
  "insulation": "Thermal Insulation",
  "interior-design": "Interior Design",
  "it-networking": "IT & Networking",
  "job-shop-manufacturing": "Job-Shop Manufacturing",
  "kitchens": "Kitchens",
  "landscaping": "Landscaping",
  "marble-granite": "Marble & Granite",
  "masonry": "Masonry / Civil",
  "mep": "MEP (Mechanical, Electrical, Plumbing)",
  "movers": "Movers & Relocation",
  "painting": "Painting",
  "pest": "Pest Control",
  "plumbing": "Plumbing & Sanitary",
  "roofing": "Roofing",
  "safety": "Fire Safety & Fire Fighting",
  "scaffolding": "Scaffolding",
  "security": "CCTV & Security Systems",
  "signage": "Signage",
  "smart-home": "Smart Home & Automation",
  "solar": "Solar Energy",
  "steel": "Steel / Metal",
  "structural-steel-fabrication": "Structural Steel & Fabrication",
  "swimming-pools": "Swimming Pools",
  "tents-and-shade-structures": "Tents & Shade Structures",
  "tiling": "Tiling",
  "upholstery": "Upholstery / Curtains",
  "wallpaper": "Wallpaper",
  "water-tank-cleaning": "Water Tank Cleaning",
  "waterproofing": "Waterproofing",
};

// ── Specification attributes (the technical-comparison rows) ─────────────────────────────────────
export const ATTRIBUTES_AR: Record<string, string> = {
  material: 'المادة', board: 'نوع اللوح', board_type: 'نوع اللوح', core: 'مادة القلب', substrate: 'المادة الأساسية', carcass: 'هيكل الخزانة', carcass_material: 'مادة الهيكل', door_finish: 'تشطيب الأبواب',
  species: 'نوع الخشب', wood: 'نوع الخشب', wood_species: 'نوع الخشب', thickness: 'السماكة', finish: 'التشطيب', surface_finish: 'تشطيب السطح',
  face: 'الوجه', facing: 'الكسوة', edge: 'الحواف', edge_band: 'شريط الحواف', edging: 'الحواف', fire_rating: 'مقاومة الحريق', fire: 'مقاومة الحريق',
  brand: 'العلامة التجارية', make: 'الصنع', model: 'الطراز', hardware: 'الإكسسوارات', hinges: 'المفصلات', runners: 'مجاري الأدراج', colour: 'اللون', color: 'اللون',
  size: 'المقاس', dimensions: 'الأبعاد', capacity: 'القدرة', cooling_capacity: 'قدرة التبريد', grade: 'الدرجة', standard: 'المعيار', coating: 'الطلاء',
  glass: 'الزجاج', frame: 'الإطار', origin: 'بلد المنشأ', country_of_origin: 'بلد المنشأ', type: 'النوع', refrigerant: 'غاز التبريد', compressor: 'الضاغط',
  efficiency: 'الكفاءة', voltage: 'الجهد', power: 'القدرة', insulation: 'العزل', insulation_thickness: 'سماكة العزل', worktop: 'سطح العمل', leaf: 'درفة الباب',
  gauge: 'السماكة (المقياس)', density: 'الكثافة', warranty: 'الضمان', installation: 'التركيب', lead_time: 'مدة التنفيذ', quantity: 'الكمية', control: 'التحكم',
};
/** An attribute key or its English label → Arabic, or null. */
export function arAttr(keyOrLabel: unknown): string | null {
  const k = String(keyOrLabel ?? '').toLowerCase().trim().replace(/[\s-]+/g, '_');
  // An attribute that is not one of our keys is free text: the document reasons it (quote_documents loc).
  return ATTRIBUTES_AR[k] ?? null;
}
