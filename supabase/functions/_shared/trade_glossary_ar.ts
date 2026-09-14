// trade_glossary_ar.ts — construction-trade English → Arabic, with no model.
//
// 14 Sep 2026, agent: ceo. The founder, on the Arabic quotation and comparison report: "what is
// arabic is not fully in arabic, many english words here and there". Until now the Arabic documents
// translated only what the platform itself knows (labels, emirates, durations, a few payment terms)
// and printed every supplier-written line — the item descriptions, the specs, the exclusions — in
// English. OpenRouter is on hold, so the translation has to be deterministic: this file is it.
//
// WHAT IT IS. One glossary for every trade in src/content/categories.json (54 trades — HVAC,
// joinery, fit-out, flooring, glass, steel, MEP, fire, security, landscaping …): materials, wood
// species, board types, finishes, units, standards, common item phrases. `arTrade(text)` turns a
// supplier's phrase into Arabic word-group by word-group:
//   • longest phrase first ("ducted split unit" before "unit");
//   • a noun group is re-ordered head-first, the way Arabic reads ("solid oak veneer" → "قشرة
//     البلوط الصلب"); verbs, prepositions and punctuation hold their place;
//   • numbers with units become Arabic units ("18mm" → "18 مم", "5 TR" → "5 طن تبريد");
//   • brands, standards and codes (Gree, ASHRAE, BS EN, MDF, R410A) stay as written: proper nouns.
// A word the glossary does not know is NOT guessed. The result says `complete: false`, the Arabic of
// the known parts is still the primary text, and the document keeps the supplier's original wording
// on a small secondary line labelled "النص الأصلي من المورد". Bare English is never the primary text.

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
const MEASURE: Record<string, [string, string?]> = {
  'mm': ['مم'], 'cm': ['سم'], 'm': ['م'], 'mtr': ['م'], 'mtrs': ['م'], 'km': ['كم'], 'm2': ['م²'], 'm²': ['م²'], 'sqm': ['م²'], 'sq.m': ['م²'], 'sqft': ['قدم²'],
  'm3': ['م³'], 'm³': ['م³'], 'cum': ['م³'], 'lm': ['م.ط'], 'rm': ['م.ط'], 'rmt': ['م.ط'], 'kg': ['كغ'], 'kgs': ['كغ'], 'g': ['غ'], 'gsm': ['غ/م²'], 'ton': ['طن'], 'tons': ['طن'],
  'tr': ['طن تبريد'], 'kw': ['كيلوواط'], 'kva': ['كيلوفولت أمبير'], 'kwp': ['كيلوواط ذروة'], 'w': ['واط'], 'watt': ['واط'], 'watts': ['واط'], 'v': ['فولت'], 'a': ['أمبير'], 'amp': ['أمبير'], 'amps': ['أمبير'],
  'hp': ['حصان'], 'btu': ['وحدة حرارية بريطانية'], 'btu/hr': ['وحدة حرارية/ساعة'], 'ltr': ['لتر'], 'l': ['لتر'], 'ltrs': ['لتر'], 'gal': ['غالون'], 'gallon': ['غالون'], 'gallons': ['غالون'],
  'mpa': ['ميغاباسكال'], 'bar': ['بار'], 'psi': ['رطل/بوصة²'], 'micron': ['ميكرون'], 'microns': ['ميكرون'], 'mic': ['ميكرون'], 'mp': ['ميغابكسل'], 'inch': ['بوصة'], 'inches': ['بوصة'], 'in': ['بوصة'], '"': ['بوصة'],
  'ft': ['قدم'], 'feet': ['قدم'], '°c': ['°م'], 'c': ['°م'], '%': ['%'], 'hrs': ['ساعة'], 'hr': ['ساعة'], 'hours': ['ساعة', 'ساعات'], 'min': ['دقيقة'], 'mins': ['دقيقة', 'دقائق'], 'minutes': ['دقيقة', 'دقائق'],
  'nos': ['عدد'], 'no': ['عدد'], 'no.': ['عدد'], 'pcs': ['قطعة', 'قطع'], 'pc': ['قطعة'], 'sets': ['طقم', 'أطقم'], 'set': ['طقم'], 'units': ['وحدة', 'وحدات'], 'unit': ['وحدة'],
  'coats': ['طبقة', 'طبقات'], 'coat': ['طبقة'], 'layers': ['طبقة', 'طبقات'], 'layer': ['طبقة'], 'ply': ['طبقة'], 'bedroom': ['غرفة نوم', 'غرف نوم'], 'bedrooms': ['غرفة نوم', 'غرف نوم'],
  'bed': ['غرفة نوم', 'غرف نوم'], 'br': ['غرفة نوم', 'غرف نوم'], 'bhk': ['غرفة نوم', 'غرف نوم'], 'rooms': ['غرفة', 'غرف'], 'room': ['غرفة'], 'floors': ['طابق', 'طوابق'], 'storey': ['طابق'], 'doors': ['باب', 'أبواب'],
  'channel': ['قناة'], 'ch': ['قناة'], 'channels': ['قناة', 'قنوات'], 'port': ['منفذ'], 'ports': ['منفذ', 'منافذ'], 'tb': ['تيرابايت'], 'gb': ['غيغابايت'], 'k': ['K'],
  'years': ['سنة', 'سنوات'], 'year': ['سنة'], 'yrs': ['سنة', 'سنوات'], 'months': ['شهر', 'أشهر'], 'month': ['شهر'], 'days': ['يوم', 'أيام'], 'day': ['يوم'], 'weeks': ['أسبوع', 'أسابيع'], 'week': ['أسبوع'],
  'visits': ['زيارة', 'زيارات'], 'lux': ['لوكس'], 'rpm': ['دورة/دقيقة'], 'db': ['ديسيبل'], 'kn': ['كيلونيوتن'], 'x': ['×'],
};
const TIME_UNIT: Record<string, Unit> = { day: 'day', days: 'day', week: 'week', weeks: 'week', month: 'month', months: 'month', year: 'year', years: 'year', yrs: 'year' };
function measureAr(n: string, u: string): string | null {
  const f = MEASURE[u.toLowerCase()]; if (!f) return null;
  const v = Number(n.replace(/,/g, ''));
  // A duration inside a phrase takes the counted form: 2 years → سنتان, 12 months → 12 شهرًا.
  const tu = TIME_UNIT[u.toLowerCase()]; if (tu && Number.isInteger(v) && /^\d+$/.test(n)) return arCount(v, tu);
  const word = f[1] && v >= 3 && v <= 10 ? f[1] : f[0];
  return word === '%' ? `${n}%` : `${n} ${word}`;
}

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

// ── The glossary ─────────────────────────────────────────────────────────────────────────────────
// One entry per line: `english = arabic`. A leading `!` marks a word that holds its place (a verb,
// preposition or connector); every other entry is part of a noun group and is re-ordered head-first.
// `=` with an empty right side means "drop" (articles). Lower case on the left; plural forms that are
// irregular or common are listed, the rest fall back to the singular.
const RAW = `
# ── connectors, verbs, glue ──
!supply = توريد
!supplying = توريد
!install = تركيب
!installing = تركيب
!supply and install = توريد وتركيب
!supply & install = توريد وتركيب
!supply and fix = توريد وتثبيت
!supply, install = توريد وتركيب
!supply, installation = توريد وتركيب
!full supply = توريد كامل
!supply only = توريد فقط
!installation only = تركيب فقط
!fix = تثبيت
!fixing = تثبيت
!provide = توفير
!providing = توفير
!remove = إزالة
!removing = إزالة
!dismantle = فك
!replace = استبدال
!repair = إصلاح
!test = اختبار
!apply = تطبيق
!paint = دهان
!clean = تنظيف
!offered = مقدّم
!offered as option = مقدّم كخيار
!as option = كخيار
!as an option = كخيار
!on request = عند الطلب
!upon request = عند الطلب
!including = شاملًا
!includes = يشمل
!include = يشمل
!incl = شاملًا
!incl. = شاملًا
!inclusive of = شاملًا
!excluding = باستثناء
!excludes = لا يشمل
!excl = باستثناء
!excl. = باستثناء
!with = مع
!without = بدون
!w/ = مع
!w/o = بدون
!or = أو
!of = من
!in = في
!on = على
!at = في
!to = إلى
!from = من
!by = بواسطة
!per = حسب
!as per = حسب
!according to = وفق
!in accordance with = وفق
!complying with = مطابق لـ
!compliant with = مطابق لـ
!up to = حتى
!above = فوق
!below = أسفل
!under = تحت
!over = فوق
!between = بين
!into = داخل
!within = خلال
!after = بعد
!before = قبل
!during = أثناء
!only = فقط
!all = جميع
!any = أي
!each = لكل
!every = كل
!approx = تقريبًا
!approx. = تقريبًا
!approximately = تقريبًا
!total = إجمالي
!is =
!are =
!will be =
!shall be =
!be =
!to be =
!a =
!an =
!the =
!valid = ساري
!not = غير
!no = لا
!required = مطلوب
!if required = عند الحاجة
!where required = حيثما يلزم
!as required = حسب الحاجة
!if any = إن وجد
!by client = على العميل
!by others = على جهات أخرى
!by customer = على العميل
!by the client = على العميل
!client scope = ضمن نطاق العميل
!per client = حسب طلب العميل
!per client request = حسب طلب العميل
!per approved sample = حسب العينة المعتمدة
!as per approved sample = حسب العينة المعتمدة
!as per boq = حسب جدول الكميات
!as per drawings = حسب المخططات
!as per drawing = حسب المخطط
!as per specification = حسب المواصفات
!as per specifications = حسب المواصفات
!as per site = حسب الموقع
!as per site condition = حسب ظروف الموقع
!as per design = حسب التصميم
!as per standard = حسب المعايير
!etc = وغيرها
!etc. = وغيرها
!e.g. = مثل
!i.e. = أي
!vs = مقابل
!plus = بالإضافة إلى
!also = أيضًا
!both = كلا
!then = ثم
# ── general scope nouns ──
installation = تركيب
installations = تركيبات
supply = توريد
testing = اختبار
commissioning = تشغيل تجريبي
testing and commissioning = الاختبار والتشغيل التجريبي
testing & commissioning = الاختبار والتشغيل التجريبي
t&c = الاختبار والتشغيل التجريبي
removal = إزالة
disposal = التخلص من المخلفات
dismantling = فك
delivery = توصيل
delivery to site = التوصيل إلى الموقع
transport = نقل
transportation = نقل
handover = تسليم نهائي
maintenance = صيانة
preventive maintenance = صيانة وقائية
repair = إصلاح
repairs = إصلاحات
replacement = استبدال
service = خدمة
servicing = صيانة دورية
labour = أعمال اليد العاملة
labor = أعمال اليد العاملة
manpower = العمالة
material = مواد
materials = مواد
consumables = مستهلكات
accessories = ملحقات
fittings = تجهيزات
fixtures = تجهيزات
works = أعمال
work = أعمال
scope = نطاق العمل
scope of work = نطاق العمل
site = الموقع
site access = الوصول إلى الموقع
site visit = زيارة الموقع
site survey = مسح الموقع
site measurement = قياسات الموقع
site measurements = قياسات الموقع
boq = جدول الكميات
bill of quantities = جدول الكميات
drawings = المخططات
drawing = المخطط
shop drawings = المخططات التنفيذية
as-built drawings = المخططات النهائية
samples = عينات
sample = عينة
approval = اعتماد
approvals = الموافقات
authority approval = موافقة الجهات الرسمية
authority approvals = موافقات الجهات الرسمية
permit = تصريح
permits = تصاريح
warranty = ضمان
guarantee = كفالة
price = السعر
prices = الأسعار
rate = السعر
rates = الأسعار
cost = التكلفة
quantities = الكميات
quantity = الكمية
listed quantities = الكميات المذكورة
listed items = البنود المذكورة
items = البنود
item = بند
option = خيار
alternative = بديل
optional = اختياري
premium = فاخر
standard = قياسي
basic = أساسي
complete = كامل
full = كامل
turnkey = بنظام تسليم المفتاح
turnkey installation = تركيب متكامل بنظام تسليم المفتاح
turnkey project = مشروع بنظام تسليم المفتاح
heavy duty = للاستخدام الشاق
high quality = عالي الجودة
good quality = جيد الجودة
new = جديد
existing = قائم
temporary = مؤقت
permanent = دائم
approved = معتمد
certified = معتمد
original = أصلي
genuine = أصلي
imported = مستورد
local = محلي
locally made = مصنوع محليًا
made in uae = صنع في الإمارات
custom = حسب الطلب
custom made = مصنوع حسب الطلب
custom-made = مصنوع حسب الطلب
bespoke = حسب الطلب
brand = العلامة التجارية
model = الطراز
grade = درجة
class = فئة
type = نوع
size = المقاس
sizes = المقاسات
dimension = البعد
dimensions = الأبعاد
thickness = السماكة
thick = سماكة
width = العرض
wide = عرض
height = الارتفاع
high = ارتفاع
length = الطول
long = طول
depth = العمق
deep = عمق
diameter = القطر
dia = قطر
capacity = السعة
weight = الوزن
colour = اللون
color = اللون
finish = تشطيب
finishes = تشطيبات
finishing = تشطيب
finished = مشطّب
specification = المواصفات
specifications = المواصفات
spec = المواصفات
country of origin = بلد المنشأ
origin = المنشأ
quality = الجودة
safety = السلامة
hse = الصحة والسلامة والبيئة
insurance = التأمين
cleaning = تنظيف
final cleaning = التنظيف النهائي
protection = حماية
mobilisation = التجهيز والتعبئة
mobilization = التجهيز والتعبئة
supervision = إشراف
design = تصميم
coordination = تنسيق
documentation = المستندات
training = تدريب
support = دعم
spare parts = قطع غيار
spares = قطع غيار
parts = قطع
tools = أدوات
equipment = معدات
machinery = آلات
scaffolding = سقالات
access = وصول
working hours = ساعات العمل
normal working hours = ساعات العمل الاعتيادية
night work = العمل الليلي
overtime = العمل الإضافي
fridays = أيام الجمعة
public holidays = العطل الرسمية
power = كهرباء
water = مياه
power and water = الكهرباء والمياه
electricity = الكهرباء
parking = مواقف السيارات
storage = تخزين
vat = ضريبة القيمة المضافة
payment = الدفع
advance = دفعة مقدمة
invoice = الفاتورة
# ── places, rooms, building types ──
villa = فيلا
villas = فلل
apartment = شقة
apartments = شقق
flat = شقة
office = مكتب
offices = مكاتب
shop = محل
shops = محلات
showroom = صالة عرض
restaurant = مطعم
cafe = مقهى
hotel = فندق
warehouse = مستودع
factory = مصنع
building = مبنى
tower = برج
school = مدرسة
clinic = عيادة
hospital = مستشفى
mall = مركز تجاري
retail = تجاري
commercial = تجاري
residential = سكني
industrial = صناعي
bedroom = غرفة نوم
bedrooms = غرف نوم
master bedroom = غرفة النوم الرئيسية
kitchen = مطبخ
bathroom = حمام
bathrooms = حمامات
toilet = حمام
washroom = دورة مياه
living room = غرفة المعيشة
dining room = غرفة الطعام
majlis = مجلس
hall = صالة
lobby = ردهة
reception = استقبال
corridor = ممر
staircase = درج
stairs = درج
roof = سطح
terrace = شرفة
balcony = شرفة
garden = حديقة
backyard = فناء خلفي
basement = قبو
ground floor = الطابق الأرضي
first floor = الطابق الأول
mezzanine = ميزانين
room = غرفة
rooms = غرف
area = المساحة
areas = المساحات
unit = وحدة
units = وحدات
dubai = دبي
abu dhabi = أبوظبي
sharjah = الشارقة
ajman = عجمان
ras al khaimah = رأس الخيمة
fujairah = الفجيرة
umm al quwain = أم القيوين
al ain = العين
al barsha = البرشاء
jumeirah = جميرا
palm jumeirah = نخلة جميرا
business bay = الخليج التجاري
downtown = وسط المدينة
downtown dubai = وسط مدينة دبي
dubai marina = دبي مارينا
marina = المارينا
jlt = أبراج بحيرات جميرا
jvc = قرية جميرا الدائرية
deira = ديرة
bur dubai = بر دبي
al quoz = القوز
mirdif = مردف
arabian ranches = المرابع العربية
dubai hills = دبي هيلز
jebel ali = جبل علي
al nahda = النهدة
al karama = الكرامة
satwa = السطوة
silicon oasis = واحة دبي للسيليكون
motor city = موتور سيتي
sports city = مدينة دبي الرياضية
international city = المدينة العالمية
al qusais = القصيص
al warqa = الورقاء
khalifa city = مدينة خليفة
musaffah = مصفح
yas island = جزيرة ياس
saadiyat = السعديات
# ── HVAC ──
air conditioning = تكييف الهواء
air conditioner = مكيف هواء
air conditioners = مكيفات هواء
ac = مكيف
a/c = مكيف
ac unit = وحدة تكييف
ac units = وحدات تكييف
split ac = مكيف سبليت
split unit = وحدة سبليت
split units = وحدات سبليت
split = سبليت
wall mounted split = سبليت جداري
wall mounted = مثبت على الجدار
ducted split = سبليت مخفي بمجاري هواء
ducted split ac = مكيف سبليت مخفي بمجاري هواء
ducted split unit = وحدة سبليت مخفية بمجاري هواء
ducted split units = وحدات سبليت مخفية بمجاري هواء
ducted = مخفي بمجاري هواء
concealed = مخفي
cassette = كاسيت
cassette unit = وحدة كاسيت
floor standing = أرضي
package unit = وحدة مجمّعة
packaged unit = وحدة مجمّعة
vrf = نظام VRF
vrf system = نظام VRF
vrv = نظام VRV
chiller = مبرّد مياه (تشيلر)
chillers = مبرّدات مياه
fcu = وحدة ملف ومروحة (FCU)
fan coil unit = وحدة ملف ومروحة
fan coil = ملف ومروحة
ahu = وحدة مناولة الهواء (AHU)
air handling unit = وحدة مناولة الهواء
outdoor unit = وحدة خارجية
outdoor units = وحدات خارجية
indoor unit = وحدة داخلية
indoor units = وحدات داخلية
condensing unit = وحدة تكثيف
compressor = ضاغط
compressors = ضواغط
inverter = بتقنية الإنفرتر
non-inverter = بدون إنفرتر
refrigerant = غاز التبريد
gas = غاز
gas charging = تعبئة الغاز
gas top-up = تعبئة الغاز
copper = نحاس
copper piping = أنابيب نحاسية
copper pipe = أنبوب نحاسي
copper pipes = أنابيب نحاسية
refrigerant piping = أنابيب غاز التبريد
insulated = معزول
insulation = عزل
ductwork = مجاري هواء
duct = مجرى هواء
ducts = مجاري هواء
ducting = مجاري هواء
flexible duct = مجرى هواء مرن
duct insulation = عزل مجاري الهواء
gi ductwork = مجاري هواء من الحديد المجلفن
galvanised iron = حديد مجلفن
galvanized iron = حديد مجلفن
galvanised = مجلفن
galvanized = مجلفن
grille = فتحة تهوية
grilles = فتحات تهوية
diffuser = ناشر هواء
diffusers = نواشر هواء
linear diffuser = ناشر هواء خطي
linear slot diffuser = ناشر هواء خطي
return air = الهواء الراجع
return air grille = فتحة الهواء الراجع
supply air = هواء التغذية
fresh air = هواء نقي
fresh air unit = وحدة الهواء النقي
exhaust fan = مروحة شفط
exhaust fans = مراوح شفط
exhaust = شفط
fan = مروحة
fans = مراوح
thermostat = ثرموستات
thermostats = ثرموستات
wall thermostat = ثرموستات جداري
programmable = قابل للبرمجة
programmable wall thermostat = ثرموستات جداري قابل للبرمجة
smart thermostat = ثرموستات ذكي
drain line = خط تصريف
drain lines = خطوط تصريف
drain pipe = أنبوب تصريف
drain pump = مضخة تصريف
drain pumps = مضخات تصريف
condensate = مياه التكثيف
condensate drain = تصريف مياه التكثيف
cooling = تبريد
cooling capacity = قدرة التبريد
heating = تدفئة
ventilation = تهوية
damper = مخمد هواء
dampers = مخمدات هواء
fire damper = مخمد حريق
fire dampers = مخمدات حريق
volume control damper = مخمد التحكم بالحجم
sensor = حساس
sensors = حساسات
controller = وحدة تحكم
controls = أنظمة التحكم
remote control = جهاز تحكم عن بعد
remote = جهاز تحكم عن بعد
bms = نظام إدارة المبنى (BMS)
filter = فلتر
filters = فلاتر
coil = ملف
coil cleaning = تنظيف الملفات
amc = عقد صيانة سنوي (AMC)
annual maintenance contract = عقد صيانة سنوي
annual maintenance = صيانة سنوية
refrigeration = تبريد
cold room = غرفة تبريد
cold rooms = غرف تبريد
heat pump = مضخة حرارية
bracket = حامل
brackets = حوامل
stand = قاعدة
vibration isolators = عوازل اهتزاز
# ── joinery, carpentry, furniture, kitchens ──
joinery = أعمال النجارة
joinery works = أعمال النجارة
carpentry = نجارة
woodwork = أعمال الخشب
wardrobe = خزانة ملابس
wardrobes = خزائن ملابس
built-in wardrobe = خزانة ملابس مدمجة
built-in wardrobes = خزائن ملابس مدمجة
built-in = مدمج
walk-in closet = غرفة ملابس
closet = خزانة
cabinet = خزانة
cabinets = خزائن
kitchen cabinet = خزانة مطبخ
kitchen cabinets = خزائن مطبخ
base cabinet = خزانة سفلية
base cabinets = خزائن سفلية
base unit = وحدة سفلية
base units = وحدات سفلية
wall cabinet = خزانة علوية
wall cabinets = خزائن علوية
wall unit = وحدة علوية
wall units = وحدات علوية
tall unit = خزانة طويلة
tall units = خزائن طويلة
carcass = هيكل الخزانة
carcasses = هياكل الخزائن
carcase = هيكل الخزانة
shutter = درفة
shutters = درف
door = باب
doors = أبواب
door leaf = درفة باب
door frame = حلق الباب
door frames = حلوق الأبواب
frame = إطار
frames = إطارات
architrave = إطار تجميلي
architraves = إطارات تجميلية
flush door = باب مسطح
flush doors = أبواب مسطحة
solid core door = باب مصمت
solid core = مصمت
hollow core = مجوف
entrance door = باب مدخل
main door = الباب الرئيسي
internal door = باب داخلي
internal doors = أبواب داخلية
skirting = وزرة
skirting board = وزرة
skirting boards = وزرات
panelling = تكسية جدران
paneling = تكسية جدران
wall panelling = تكسية جدران
wall paneling = تكسية جدران
wall cladding = تكسية جدران
cladding = تكسية
feature wall = جدار مميز
shelving = أرفف
shelf = رف
shelves = أرفف
countertop = سطح عمل
countertops = أسطح عمل
worktop = سطح عمل
worktops = أسطح عمل
counter = كاونتر
reception desk = مكتب استقبال
reception counter = كاونتر استقبال
desk = مكتب
desks = مكاتب
workstation = محطة عمل
workstations = محطات عمل
table = طاولة
tables = طاولات
tv unit = وحدة تلفاز
bed = سرير
headboard = لوح رأس السرير
bedside table = طاولة جانبية
dresser = تسريحة
vanity = خزانة مغسلة
vanity unit = وحدة مغسلة
vanity units = وحدات مغسلة
partition = قاطع
partitions = قواطع
kitchen = مطبخ
kitchens = مطابخ
pantry = مخزن مطبخ
furniture = أثاث
loose furniture = أثاث متحرك
fitted furniture = أثاث مثبت
sofa = أريكة
chair = كرسي
chairs = كراسي
wood = خشب
wooden = خشبي
timber = خشب
solid wood = خشب صلب
solid = صلب
hardwood = خشب صلب
softwood = خشب لين
engineered wood = خشب هندسي
oak = خشب البلوط
solid oak = خشب البلوط الصلب
white oak = البلوط الأبيض
european oak = البلوط الأوروبي
american oak = البلوط الأمريكي
red oak = البلوط الأحمر
walnut = خشب الجوز
american walnut = الجوز الأمريكي
teak = خشب الساج
beech = خشب الزان
ash = خشب الدردار
maple = خشب القيقب
mahogany = خشب الماهوغني
pine = خشب الصنوبر
cherry = خشب الكرز
meranti = خشب الميرانتي
sapele = خشب السابيلي
iroko = خشب الإيروكو
birch = خشب البتولا
cedar = خشب الأرز
rubberwood = خشب المطاط
mdf = ألواح MDF
mdf board = لوح MDF
mdf boards = ألواح MDF
moisture resistant mdf = MDF مقاوم للرطوبة
mr mdf = MDF مقاوم للرطوبة
fire rated mdf = MDF مقاوم للحريق
fr mdf = MDF مقاوم للحريق
plywood = خشب رقائقي (أبلكاش)
ply = خشب رقائقي
marine plywood = خشب رقائقي بحري
marine ply = خشب رقائقي بحري
birch plywood = خشب رقائقي من البتولا
commercial plywood = خشب رقائقي تجاري
chipboard = ألواح الخشب المضغوط
particle board = ألواح الخشب الحبيبي
particleboard = ألواح الخشب الحبيبي
hdf = ألواح HDF
osb = ألواح OSB
blockboard = ألواح بلوك بورد
board = لوح
boards = ألواح
panel = لوح
panels = ألواح
sheet = لوح
veneer = قشرة خشب
veneers = قشور خشب
veneered = مكسو بقشرة خشب
natural veneer = قشرة طبيعية
wood veneer = قشرة خشب
oak veneer = قشرة البلوط
walnut veneer = قشرة الجوز
teak veneer = قشرة الساج
reconstituted veneer = قشرة مُعاد تكوينها
laminate = لامينيت
laminates = لامينيت
laminated = مغطى باللامينيت
hpl = لامينيت عالي الضغط (HPL)
high pressure laminate = لامينيت عالي الضغط
melamine = ميلامين
melamine faced = مكسو بالميلامين
acrylic sheet = لوح أكريليك
lacquer = دهان لاكر
lacquered = مطلي باللاكر
pu lacquer = لاكر بولي يوريثان
pu paint = دهان بولي يوريثان
polyurethane = بولي يوريثان
pu = بولي يوريثان
duco = دهان دوكو
duco paint = دهان دوكو
duco finish = تشطيب دوكو
spray paint = دهان بالرش
spray painted = مدهون بالرش
paint finish = تشطيب دهان
matt = مطفي
matte = مطفي
matt finish = تشطيب مطفي
gloss = لامع
glossy = لامع
high gloss = شديد اللمعان
semi gloss = نصف لامع
semi-gloss = نصف لامع
satin = ساتان
stain = صبغة خشب
stained = مصبوغ
varnish = ورنيش
varnished = مورنش
oil finish = تشطيب بالزيت
oiled = مزيّت
natural finish = تشطيب طبيعي
edge band = شريط حواف
edge bands = أشرطة حواف
edge banding = شريط حواف
edgeband = شريط حواف
edging = حواف
pvc edge band = شريط حواف PVC
abs edge band = شريط حواف ABS
solid wood edging = حواف من الخشب الصلب
hinge = مفصلة
hinges = مفصلات
soft close = بإغلاق هادئ
soft-close = بإغلاق هادئ
soft close hinges = مفصلات بإغلاق هادئ
drawer = درج
drawers = أدراج
drawer runners = مجاري أدراج
drawer slides = مجاري أدراج
runners = مجاري
handle = مقبض
handles = مقابض
handleless = بدون مقابض
knob = مقبض
ironmongery = إكسسوارات الأبواب
hardware = إكسسوارات
lock = قفل
locks = أقفال
door closer = غالق باب
door stopper = مصد باب
fire rated = مقاوم للحريق
fire-rated = مقاوم للحريق
fire rating = تصنيف مقاومة الحريق
fire resistance = مقاومة الحريق
fire resistant = مقاوم للحريق
fire retardant = مثبط للحريق
moisture resistant = مقاوم للرطوبة
moisture-resistant = مقاوم للرطوبة
water resistant = مقاوم للماء
waterproof = مقاوم للماء
termite resistant = مقاوم للنمل الأبيض
low formaldehyde = منخفض الفورمالديهايد
emission class = فئة الانبعاثات
fsc certified = معتمد من FSC
upholstered = منجّد
upholstery = تنجيد
fabric = قماش
leather = جلد
foam = إسفنج
curtain = ستارة
curtains = ستائر
blind = ستارة
blinds = ستائر
roller blind = ستارة رول
roller blinds = ستائر رول
blackout = معتم
sheer = شفاف
motorised = بمحرك
motorized = بمحرك
curtain track = مجرى ستائر
track = مجرى
rail = سكة
# ── gypsum, ceilings, painting, wallpaper ──
gypsum = جبس
gypsum board = ألواح الجبس
gypsum boards = ألواح الجبس
gypsum ceiling = سقف جبسي
gypsum partition = قاطع جبسي
plasterboard = ألواح الجبس
moisture resistant gypsum board = ألواح جبس مقاومة للرطوبة
fire rated gypsum board = ألواح جبس مقاومة للحريق
false ceiling = سقف مستعار
false ceiling works = أعمال السقف المستعار
suspended ceiling = سقف معلق
ceiling = سقف
ceilings = أسقف
grid ceiling = سقف معلق شبكي
ceiling tiles = بلاطات سقف
access panel = فتحة صيانة
access panels = فتحات صيانة
metal stud = قوائم معدنية
studs = قوائم
stud = قائم
cornice = كرنيش
cornices = كرانيش
bulkhead = سقف منخفض (بلكهيد)
plaster = لياسة
plastering = لياسة
paint = دهان
paints = دهانات
painting = أعمال الدهان
painting works = أعمال الدهان
emulsion = دهان مائي
emulsion paint = دهان مائي
acrylic emulsion = دهان مائي أكريليكي
enamel = دهان زيتي
enamel paint = دهان زيتي
primer = طبقة أساس (برايمر)
sealer = مانع تسرب
putty = معجون
wall putty = معجون جدران
coats = طبقات
coat = طبقة
interior = داخلي
exterior = خارجي
wall = جدار
walls = جدران
texture = دهان محبب
textured = محبب
wallpaper = ورق جدران
wallpapers = ورق جدران
wall covering = تكسية جدران
# ── flooring, tiling, stone, carpets, epoxy ──
flooring = أرضيات
floor = أرضية
floors = أرضيات
floor tiles = بلاط أرضيات
wall tiles = بلاط جدران
vinyl = فينيل
vinyl flooring = أرضيات فينيل
spc flooring = أرضيات SPC
lvt = بلاط فينيل فاخر (LVT)
parquet = باركيه
engineered wood flooring = أرضيات خشب هندسي
laminate flooring = أرضيات لامينيت
wooden flooring = أرضيات خشبية
carpet = سجاد
carpets = سجاد
carpet tiles = بلاطات سجاد
wall to wall carpet = سجاد جداري كامل
underlay = طبقة عازلة أسفل الأرضية
screed = طبقة تسوية (سكريد)
levelling = تسوية
leveling = تسوية
self levelling = ذاتي التسوية
self-levelling = ذاتي التسوية
tile = بلاط
tiles = بلاط
tiling = تبليط
porcelain = بورسلين
porcelain tiles = بلاط بورسلين
porcelain tile = بلاط بورسلين
ceramic = سيراميك
ceramic tiles = بلاط سيراميك
mosaic = موزاييك
grout = روبة
grouting = ترويب
epoxy grout = روبة إيبوكسي
tile adhesive = لاصق بلاط
adhesive = لاصق
marble = رخام
granite = جرانيت
quartz = كوارتز
natural stone = حجر طبيعي
stone = حجر
travertine = ترافرتين
polished = مصقول
honed = مصقول غير لامع
epoxy = إيبوكسي
epoxy flooring = أرضيات إيبوكسي
epoxy coating = طلاء إيبوكسي
resin = راتنج
resin flooring = أرضيات الراتنج
anti slip = مانع للانزلاق
anti-slip = مانع للانزلاق
threshold = عتبة
thresholds = عتبات
# ── electrical, lighting, generators, solar, smart home, lifts ──
electrical = كهربائي
electric = كهربائي
electrical works = أعمال كهربائية
cable = كابل
cables = كابلات
cabling = تمديد الكابلات
wire = سلك
wires = أسلاك
wiring = تمديدات كهربائية
conduit = أنابيب تمديد
conduits = أنابيب تمديد
trunking = مجاري كابلات
cable tray = حامل كابلات
cable trays = حوامل كابلات
distribution board = لوحة توزيع كهربائي
db = لوحة توزيع
main distribution board = لوحة التوزيع الرئيسية
breaker = قاطع
breakers = قواطع
circuit breaker = قاطع دائرة
isolator = عازل كهربائي
isolators = عوازل كهربائية
electrical isolators = عوازل كهربائية
socket = مقبس
sockets = مقابس
power socket = مقبس كهرباء
switch = مفتاح
switches = مفاتيح
light = إنارة
lights = إنارة
lighting = إنارة
light fitting = وحدة إنارة
light fittings = وحدات إنارة
downlight = إنارة سقفية مدمجة
downlights = إنارات سقفية مدمجة
spotlight = كشاف
spotlights = كشافات
led strip = شريط LED
led lights = إنارة LED
chandelier = ثريا
earthing = تأريض
grounding = تأريض
lightning protection = الحماية من الصواعق
meter = عداد
generator = مولد كهربائي
generators = مولدات كهربائية
diesel generator = مولد ديزل
standby generator = مولد احتياطي
canopy = غطاء عازل
soundproof canopy = غطاء عازل للصوت
fuel tank = خزان وقود
changeover switch = مفتاح تحويل
ats = مفتاح تحويل تلقائي (ATS)
solar = شمسي
solar panel = لوح شمسي
solar panels = ألواح شمسية
solar system = نظام طاقة شمسية
pv = كهروضوئي
on-grid = متصل بالشبكة
off-grid = مستقل عن الشبكة
battery = بطارية
batteries = بطاريات
mounting structure = هيكل التثبيت
smart home = المنزل الذكي
home automation = أتمتة المنزل
automation = أتمتة
smart = ذكي
smart lighting = إنارة ذكية
smart lock = قفل ذكي
lift = مصعد
lifts = مصاعد
elevator = مصعد
elevators = مصاعد
passenger lift = مصعد ركاب
passenger elevator = مصعد ركاب
goods lift = مصعد بضائع
home lift = مصعد منزلي
escalator = سلم كهربائي
cabin = مقصورة
machine room less = بدون غرفة ماكينات
stops = وقفات
# ── security, CCTV, IT, AV ──
cctv = كاميرات المراقبة (CCTV)
cctv camera = كاميرا مراقبة
cctv cameras = كاميرات مراقبة
cctv system = نظام كاميرات المراقبة
camera = كاميرا
cameras = كاميرات
ip camera = كاميرا IP
ip cameras = كاميرات IP
dome camera = كاميرا قبة
dome cameras = كاميرات قبة
bullet camera = كاميرا أسطوانية
bullet cameras = كاميرات أسطوانية
ptz camera = كاميرا متحركة (PTZ)
night vision = رؤية ليلية
nvr = مسجل فيديو شبكي (NVR)
dvr = مسجل فيديو رقمي (DVR)
hard disk = قرص صلب
hard drive = قرص صلب
hdd = قرص صلب
monitor = شاشة
monitors = شاشات
screen = شاشة
screens = شاشات
access control = نظام التحكم بالدخول
access control system = نظام التحكم بالدخول
card reader = قارئ بطاقات
intercom = إنتركم
video intercom = إنتركم مرئي
alarm = إنذار
intrusion alarm = إنذار التسلل
security = أمن
security system = نظام أمني
security systems = أنظمة أمنية
network = شبكة
networking = شبكات
data point = نقطة بيانات
data points = نقاط بيانات
patch panel = لوحة توصيل
patch cord = كابل توصيل
rack = خزانة شبكة
server rack = خزانة خوادم
network switch = محول شبكة
poe switch = محول شبكة PoE
router = راوتر
access point = نقطة وصول
access points = نقاط وصول
wifi = شبكة واي فاي
fiber = ألياف ضوئية
fibre = ألياف ضوئية
fiber optic = ألياف ضوئية
structured cabling = الكابلات المنظمة
server = خادم
speaker = سماعة
speakers = سماعات
ceiling speaker = سماعة سقفية
ceiling speakers = سماعات سقفية
amplifier = مضخم صوت
projector = جهاز عرض
projection screen = شاشة عرض
video wall = جدار عرض
sound system = نظام صوتي
audio = صوت
video = فيديو
microphone = ميكروفون
conference room = قاعة اجتماعات
meeting room = غرفة اجتماعات
display = شاشة عرض
# ── fire safety ──
fire = حريق
fire alarm = إنذار الحريق
fire alarm system = نظام إنذار الحريق
fire alarm panel = لوحة إنذار الحريق
addressable = قابل للعنونة
conventional = تقليدي
smoke detector = كاشف دخان
smoke detectors = كواشف دخان
heat detector = كاشف حرارة
heat detectors = كواشف حرارة
manual call point = نقطة إنذار يدوية
sounder = صفارة إنذار
sprinkler = رشاش حريق
sprinklers = رشاشات حريق
sprinkler system = نظام الرشاشات
fire extinguisher = طفاية حريق
fire extinguishers = طفايات حريق
fire hose reel = بكرة خرطوم حريق
fire hose reels = بكرات خراطيم حريق
fire pump = مضخة حريق
fire fighting = مكافحة الحريق
firefighting = مكافحة الحريق
fire protection = الحماية من الحريق
fire safety = السلامة من الحريق
emergency light = إنارة طوارئ
emergency lights = إنارة طوارئ
emergency lighting = إنارة الطوارئ
exit sign = لوحة مخرج
exit signs = لوحات مخرج
civil defence = الدفاع المدني
civil defense = الدفاع المدني
civil defence approved = معتمد من الدفاع المدني
dcd approved = معتمد من الدفاع المدني
fire blanket = بطانية حريق
fm200 = نظام إطفاء FM200
suppression system = نظام إطفاء
# ── plumbing, sanitary, pools, tanks, waterproofing, insulation, roofing ──
plumbing = سباكة
plumbing works = أعمال السباكة
sanitary = صحي
pipe = أنبوب
pipes = أنابيب
piping = أنابيب
pipework = شبكة أنابيب
water supply = تغذية المياه
water heater = سخان مياه
water heaters = سخانات مياه
heater = سخان
pump = مضخة
pumps = مضخات
booster pump = مضخة تعزيز
transfer pump = مضخة نقل
submersible pump = مضخة غاطسة
water tank = خزان مياه
water tanks = خزانات مياه
tank = خزان
tanks = خزانات
valve = صمام
valves = صمامات
gate valve = صمام بوابي
ball valve = صمام كروي
mixer = خلاط
mixers = خلاطات
tap = صنبور
taps = صنابير
faucet = صنبور
wc = مرحاض
water closet = مرحاض
wall hung wc = مرحاض معلق
concealed cistern = خزان طرد مخفي
cistern = خزان طرد
basin = مغسلة
wash basin = مغسلة
washbasin = مغسلة
sink = حوض
kitchen sink = حوض مطبخ
shower = دش
showers = دشات
rain shower = دش مطري
bathtub = حوض استحمام
jacuzzi = جاكوزي
sanitary ware = أدوات صحية
sanitaryware = أدوات صحية
floor drain = مصرف أرضي
drainage = صرف
sewage = صرف صحي
drain = تصريف
manhole = غرفة تفتيش
manholes = غرف تفتيش
leak = تسرب
leakage = تسرب
leak detection = كشف التسربات
waterproofing = عزل مائي
waterproofing works = أعمال العزل المائي
membrane = غشاء
membranes = أغشية
bitumen = بيتومين
bituminous = بيتوميني
bituminous membrane = غشاء بيتوميني
cementitious = أسمنتي
cementitious waterproofing = عزل مائي أسمنتي
torch applied = بالتسخين
liquid applied = سائل
liquid membrane = غشاء سائل
roof = سطح
roofing = أعمال الأسطح
roof waterproofing = عزل مائي للسطح
thermal insulation = عزل حراري
insulation board = لوح عزل
polystyrene = بوليسترين
extruded polystyrene = بوليسترين مبثوق
rock wool = صوف صخري
rockwool = صوف صخري
glass wool = صوف زجاجي
spray foam = رغوة رش
sandwich panel = ألواح ساندويتش
sandwich panels = ألواح ساندويتش
swimming pool = مسبح
swimming pools = مسابح
pool = مسبح
filtration = فلترة
filtration system = نظام فلترة
filter pump = مضخة فلترة
chlorinator = جهاز كلورة
pool tiles = بلاط مسابح
pool lights = إنارة مسبح
tank cleaning = تنظيف الخزانات
water tank cleaning = تنظيف خزانات المياه
disinfection = تعقيم
sterilisation = تعقيم
sterilization = تعقيم
# ── glass, aluminium, steel, doors, shutters ──
glass = زجاج
glazing = تزجيج
tempered = مقسّى
tempered glass = زجاج مقسّى
toughened = مقسّى
toughened glass = زجاج مقسّى
laminated glass = زجاج مصفح
double glazed = زجاج مزدوج
double glazing = تزجيج مزدوج
insulated glass = زجاج عازل
clear = شفاف
clear glass = زجاج شفاف
frosted = مصنفر
frosted glass = زجاج مصنفر
tinted = ملون
reflective = عاكس
low-e = منخفض الانبعاث
mirror = مرآة
mirrors = مرايا
shower enclosure = كابينة دش
shower screen = حاجز دش
glass partition = قاطع زجاجي
glass partitions = قواطع زجاجية
glass door = باب زجاجي
glass doors = أبواب زجاجية
frameless = بدون إطار
patch fitting = قطع تثبيت الزجاج
patch fittings = قطع تثبيت الزجاج
aluminium = ألمنيوم
aluminum = ألمنيوم
aluminium works = أعمال الألمنيوم
aluminium profile = قطاع ألمنيوم
aluminium profiles = قطاعات ألمنيوم
aluminium frame = إطار ألمنيوم
thermal break = عازل حراري
powder coated = مطلي بالبودرة
powder-coated = مطلي بالبودرة
powder coating = طلاء بودرة
anodised = مؤكسد
anodized = مؤكسد
window = نافذة
windows = نوافذ
sliding = منزلق
sliding door = باب منزلق
sliding doors = أبواب منزلقة
sliding window = نافذة منزلقة
casement = مفصلي
casement window = نافذة مفصلية
curtain wall = واجهة زجاجية
facade = واجهة
façade = واجهة
skylight = منور
steel = فولاذ
stainless steel = فولاذ مقاوم للصدأ
ss = فولاذ مقاوم للصدأ
mild steel = حديد طري
ms = حديد طري
structural steel = حديد إنشائي
steel structure = هيكل فولاذي
steel works = أعمال الحديد
metal = معدن
metal works = أعمال معدنية
fabrication = تصنيع
fabricated = مصنّع
welding = لحام
welded = ملحوم
beam = كمرة
beams = كمرات
column = عمود
columns = أعمدة
purlin = مدادة
purlins = مدادات
base plate = لوح قاعدة
bolts = براغي
anchor bolts = براغي تثبيت
handrail = درابزين
handrails = درابزين
railing = درابزين
railings = درابزين
balustrade = درابزين
gate = بوابة
gates = بوابات
fence = سياج
fencing = سياج
mesh = شبك
chequered plate = لوح معرّج
hollow section = مقطع مجوف
angle = زاوية
channel = مجرى
roller shutter = شتر رول
roller shutters = شتر رول
rolling shutter = شتر رول
garage door = باب مرآب
garage doors = أبواب مرآب
sectional door = باب مقطعي
sectional doors = أبواب مقطعية
automatic door = باب أوتوماتيكي
automatic sliding door = باب منزلق أوتوماتيكي
motor = محرك
motors = محركات
# ── signage, acrylic, printing, tents ──
sign = لافتة
signs = لافتات
signage = لافتات
signboard = لوحة إعلانية
letters = حروف
3d letters = حروف بارزة ثلاثية الأبعاد
backlit = بإضاءة خلفية
back-lit = بإضاءة خلفية
front-lit = بإضاءة أمامية
illuminated = مضاء
non-illuminated = غير مضاء
acrylic = أكريليك
acp = ألواح ألمنيوم مركبة (ACP)
printing = طباعة
print = طباعة
printed = مطبوع
vinyl sticker = ملصق فينيل
sticker = ملصق
stickers = ملصقات
banner = لافتة قماشية
flex = فليكس
tent = خيمة
tents = خيام
shade = مظلة
shades = مظلات
shade structure = هيكل مظلات
shade structures = هياكل مظلات
car parking shade = مظلة مواقف سيارات
car park shade = مظلة مواقف سيارات
carport = مظلة سيارات
pergola = برجولا
tensile = شدّ
tensile fabric = قماش مشدود
pvc fabric = قماش PVC
hdpe fabric = قماش HDPE
# ── civil, masonry, demolition, landscaping ──
civil works = أعمال مدنية
civil = مدني
masonry = أعمال البناء
concrete = خرسانة
reinforced concrete = خرسانة مسلحة
block = بلوك
blocks = بلوك
blockwork = أعمال البلوك
hollow block = بلوك مجوف
hollow blocks = بلوك مجوف
solid block = بلوك مصمت
cement = أسمنت
sand = رمل
aggregate = ركام
steel reinforcement = حديد تسليح
rebar = حديد تسليح
excavation = حفر
backfilling = ردم
compaction = دك
foundation = أساسات
foundations = أساسات
slab = بلاطة
core cutting = ثقب خرساني
chasing = تكسير لتمديدات
demolition = هدم
demolition works = أعمال الهدم
debris = مخلفات
debris removal = إزالة المخلفات
rubble = أنقاض
skip = حاوية مخلفات
scaffold = سقالة
scaffolds = سقالات
landscaping = تنسيق الحدائق
landscape = تنسيق الحدائق
softscape = المساحات الخضراء
hardscape = الأعمال الصلبة
irrigation = ري
irrigation system = نظام ري
drip irrigation = ري بالتنقيط
artificial grass = عشب صناعي
natural grass = عشب طبيعي
grass = عشب
plants = نباتات
trees = أشجار
palm trees = نخيل
soil = تربة
sweet soil = تربة زراعية
pavers = بلاط إنترلوك
interlock = إنترلوك
interlocking = إنترلوك
kerb stones = أحجار الرصيف
kerbstone = حجر الرصيف
general building = مقاولات عامة
contracting = مقاولات
building contracting = مقاولات بناء
construction = إنشاء
renovation = تجديد
refurbishment = تجديد
fit-out = تشطيبات داخلية
fitout = تشطيبات داخلية
fit out = تشطيبات داخلية
interior fit-out = تشطيبات داخلية
interior works = أعمال داخلية
# ── cleaning, pest, movers, facade access ──
deep cleaning = تنظيف عميق
general cleaning = تنظيف عام
post construction cleaning = تنظيف ما بعد البناء
sofa cleaning = تنظيف الكنب
carpet cleaning = تنظيف السجاد
facade cleaning = تنظيف الواجهات
window cleaning = تنظيف النوافذ
rope access = الوصول بالحبال
bmu = وحدة صيانة المبنى (BMU)
pest control = مكافحة الحشرات
termite treatment = معالجة النمل الأبيض
termite = النمل الأبيض
cockroach = الصراصير
bed bugs = بق الفراش
rodent control = مكافحة القوارض
fumigation = تبخير
gel treatment = معالجة بالجل
movers = نقل الأثاث
moving = نقل
packing = تغليف
unpacking = فك التغليف
relocation = نقل
dismantling and assembly = الفك والتركيب
assembly = تركيب
boxes = صناديق
truck = شاحنة
# ── consultancy, design, manufacturing ──
interior design = تصميم داخلي
concept design = تصميم مبدئي
detailed design = تصميم تفصيلي
3d visualisation = تصور ثلاثي الأبعاد
3d visualization = تصور ثلاثي الأبعاد
renders = تصورات
rendering = تصور
architectural = معماري
structural = إنشائي
consultancy = استشارات
consultant = استشاري
engineering = هندسة
mep design = تصميم الأعمال الكهروميكانيكية
authority submission = تقديم للجهات الرسمية
noc = شهادة عدم ممانعة
cnc = قص CNC
laser cutting = قص بالليزر
machining = تشغيل آلي
prototype = نموذج أولي
batch = دفعة
# ── colours, directions, general adjectives ──
black = أسود
white = أبيض
off-white = أبيض مائل للصفرة
grey = رمادي
gray = رمادي
silver = فضي
gold = ذهبي
golden = ذهبي
bronze = برونزي
brass = نحاسي
chrome = كروم
beige = بيج
brown = بني
natural = طبيعي
dark = داكن
light = فاتح
top = علوي
bottom = سفلي
side = جانبي
front = أمامي
back = خلفي
rear = خلفي
internal = داخلي
external = خارجي
indoor = داخلي
outdoor = خارجي
large = كبير
small = صغير
double = مزدوج
single = مفرد
twin = مزدوج
manual = يدوي
automatic = أوتوماتيكي
electronic = إلكتروني
digital = رقمي
wireless = لاسلكي
portable = متنقل
fixed = ثابت
italian = إيطالي
german = ألماني
spanish = إسباني
turkish = تركي
chinese = صيني
japanese = ياباني
korean = كوري
indian = هندي
european = أوروبي
american = أمريكي
thai = تايلندي
malaysian = ماليزي
emirati = إماراتي
stated = مذكور
!not stated = غير مذكور
!coverage not stated = التغطية غير مذكورة
!timeline not stated = الجدول الزمني غير مذكور
commission = تشغيل
!on site = في الموقع
parts and labour = القطع والعمالة
parts and labor = القطع والعمالة
parts only = القطع فقط
materials and workmanship = المواد والمصنعية
workmanship = المصنعية
workmanship only = المصنعية فقط
timeline = الجدول الزمني
non-programmable = غير قابل للبرمجة
full height = بكامل الارتفاع
base and wall units = الوحدات السفلية والعلوية
points = نقاط
electrical points = نقاط كهربائية
appliances = الأجهزة
production = التصنيع
final = نهائي
final site measurements = قياسات الموقع النهائية
available = متوفرة
contact hidden until reveal = بيانات التواصل مخفية حتى الكشف
for queries = للاستفسارات
queries = استفسارات
!call = اتصل بـ
!contact = تواصل مع
carcass material = مادة الهيكل
door finish = تشطيب الأبواب
!before production = قبل التصنيع
approved equal = ما يعادله المعتمد
!or approved equal = أو ما يعادله المعتمد
!or equivalent = أو ما يعادله
equivalent = مكافئ
wall tiling = تبليط الجدران
working days = أيام عمل
included = مشمول
not included = غير مشمول
excluded = غير مشمول
coverage = التغطية
package = حزمة
joinery package = حزمة أعمال النجارة
sizing = التحجيم
sized = بمقاس
solid oak veneer = قشرة البلوط الطبيعي
natural oak veneer = قشرة البلوط الطبيعي
door leaf thickness = سماكة درفة الباب
worktop thickness = سماكة سطح العمل
carcass thickness = سماكة هيكل الخزانة
cooling load = حمل التبريد
compressor type = نوع الضاغط
rated = مصنّف
rating = التصنيف
efficiency = الكفاءة
energy efficiency = كفاءة الطاقة
star rating = تصنيف النجوم
technical = فني
data sheet = ورقة البيانات
datasheet = ورقة البيانات
`;

type Entry = { ar: string; fixed: boolean; mat: boolean };
const GLOSSARY = new Map<string, Entry>();
// A material ("MDF", "solid oak", "tempered glass") inside a noun group follows its object with
// "من": "wardrobe carcass 18mm MDF" reads "هيكل خزانة الملابس من MDF 18 مم", not the other way round.
const MATERIAL_RE = /(^|\s)(mdf|hdf|osb|plywood|ply|chipboard|particle ?board|blockboard|oak|walnut|teak|beech|ash|maple|mahogany|pine|cherry|meranti|sapele|iroko|birch|cedar|rubberwood|wood|timber|hardwood|softwood|veneer|laminate|hpl|melamine|quartz|marble|granite|porcelain|ceramic|stone|travertine|glass|aluminium|aluminum|steel|copper|galvani[sz]ed iron|gi|brass|concrete|gypsum board|plasterboard|acrylic|acp|leather|fabric|polystyrene|rock ?wool|glass wool)$/;
for (const raw of RAW.split('\n')) {
  const line = raw.trim();
  if (!line || line.startsWith('#')) continue;
  const eq = line.indexOf(' = '); const eq2 = eq < 0 ? line.lastIndexOf(' =') : eq;
  if (eq2 < 0) continue;
  let en = line.slice(0, eq2).trim(); const ar = line.slice(eq2 + (eq >= 0 ? 3 : 2)).trim();
  const fixed = en.startsWith('!'); if (fixed) en = en.slice(1).trim();
  GLOSSARY.set(en.toLowerCase(), { ar, fixed, mat: !fixed && MATERIAL_RE.test(en.toLowerCase()) });
}
/** How many English terms the glossary carries (reported in the PR, asserted in the tests). */
export const GLOSSARY_SIZE = GLOSSARY.size;
export function glossaryHas(en: string) { return GLOSSARY.has(en.toLowerCase()); }

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
  if (ATTRIBUTES_AR[k]) return ATTRIBUTES_AR[k];
  const t = arTrade(String(keyOrLabel ?? '').replace(/_/g, ' '));
  return t.complete && t.ar ? t.ar : null;
}

// ── The translator ────────────────────────────────────────────────────────────────────────────────
export type ArText = { ar: string; complete: boolean; unknown: string[] };
type Tok = { k: 'n' | 'x' | 'p' | 'm' | 'punct' | 'and' | 'for'; ar: string; mat?: boolean };

const hasArabic = (s: unknown) => /[؀-ۿ]/.test(String(s ?? ''));
const MAX_PHRASE = 6;
const SEP = '';

// Words (with inner hyphens, dots, slashes, apostrophes, ampersand as its own word), numbers with
// units, and punctuation. Measurements are recognised before words so "18mm" is one token.
const MEASURE_UNITS = Object.keys(MEASURE).sort((a, b) => b.length - a.length).map((u) => u.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&')).join('|');
const TOKEN_RE = new RegExp(
  String.raw`(\d+(?:[.,]\d+)*)\s*(?:x|×|\*)\s*(\d+(?:[.,]\d+)*)(?:\s*(?:x|×|\*)\s*(\d+(?:[.,]\d+)*))?\s*(mm|cm|m)?(?![a-z])` + '|' +
  String.raw`(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?:\s*(?:-|–|to)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm))?` + '|' +
  String.raw`(\d+(?:[.,]\d+)*)(?:\s*(?:-|–|to)\s*(\d+(?:[.,]\d+)*))?\s*-?\s*(${MEASURE_UNITS})(?![a-z0-9])` + '|' +
  String.raw`(\d+(?:[.,]\d+)*(?:\/\d+)?)(?![a-z])` + '|' +
  String.raw`([a-z0-9À-ɏ]+(?:['’][a-z]+)?(?:[-./][a-z0-9À-ɏ]+)*|&)` + '|' +
  String.raw`([,;:()\[\]/\-–—.+])`,
  'giu');

type W = { t: string; kind: 'measure' | 'num' | 'word' | 'punct'; ar?: string };
function wordsOf(s: string): W[] {
  const out: W[] = [];
  let m: RegExpExecArray | null;
  TOKEN_RE.lastIndex = 0;
  while ((m = TOKEN_RE.exec(s))) {
    if (m[1]) { const dims = [m[1], m[2], m[3]].filter(Boolean).join('×'); out.push({ t: m[0], kind: 'measure', ar: m[4] ? `${dims} ${MEASURE[m[4].toLowerCase()][0]}` : dims }); continue; }
    if (m[5]) { const t = (h: string, mm: string | undefined, ap: string) => `${h}${mm ? ':' + mm : ''} ${ap.toLowerCase() === 'am' ? 'ص' : 'م'}`; out.push({ t: m[0], kind: 'measure', ar: m[8] ? `${t(m[5], m[6], m[7])} - ${t(m[8], m[9], m[10])}` : t(m[5], m[6], m[7]) }); continue; }
    if (m[11]) { const n = m[12] ? `${m[11]}–${m[12]}` : m[11]; const ar = measureAr(m[12] ? m[12] : m[11], m[13]); out.push({ t: m[0], kind: 'measure', ar: ar ? ar.replace(/^[\d.,]+/, n) : n }); continue; }
    if (m[14]) { out.push({ t: m[14], kind: 'num' }); continue; }
    if (m[15]) { out.push({ t: m[15], kind: 'word' }); continue; }
    if (m[16]) out.push({ t: m[16], kind: 'punct' });
  }
  return out;
}

function lookup(w: string): Entry | null {
  const t = w.toLowerCase();
  const e = GLOSSARY.get(t);
  if (e) return e;
  // Plural fallback: "thermostats" → "thermostat", "boxes" → "box", "batteries" → "battery".
  if (/ies$/.test(t) && GLOSSARY.has(t.slice(0, -3) + 'y')) return GLOSSARY.get(t.slice(0, -3) + 'y')!;
  if (/(s|x|ch|sh)es$/.test(t) && GLOSSARY.has(t.slice(0, -2))) return GLOSSARY.get(t.slice(0, -2))!;
  if (/s$/.test(t) && GLOSSARY.has(t.slice(0, -1))) return GLOSSARY.get(t.slice(0, -1))!;
  return null;
}
function properAt(ws: W[], i: number): number {
  for (const p of PROPER_PHRASES) {
    const parts = p.split(/\s+/); if (i + parts.length > ws.length) continue;
    let ok = true;
    for (let j = 0; j < parts.length; j++) { const w = ws[i + j]; if (w.kind !== 'word' || w.t.toLowerCase() !== parts[j].toLowerCase()) { ok = false; break; } }
    if (ok) return parts.length;
  }
  return 0;
}

// Latin text only (the caller routes mixed Arabic/Latin text through arTrade run by run).
function translateLatin(src: string): ArText {
  const ws = wordsOf(src);
  const toks: Tok[] = []; const unknown: string[] = [];
  for (let i = 0; i < ws.length;) {
    const w = ws[i];
    if (w.kind === 'measure') { toks.push({ k: 'm', ar: w.ar! }); i++; continue; }
    if (w.kind === 'num') { toks.push({ k: 'm', ar: w.t }); i++; continue; }
    if (w.kind === 'punct') {
      // The full stop of an abbreviation ("approx.", "incl.", "no.") is not a sentence end.
      if (w.t === '.' && i > 0 && /^(approx|incl|excl|etc|no|nos|qty|dia|max|min|ref|e\.g|i\.e)$/i.test(ws[i - 1].t)) { i++; continue; }
      toks.push({ k: 'punct', ar: w.t }); i++; continue;
    }
    if (w.t === '&') { toks.push({ k: 'and', ar: 'و' }); i++; continue; }
    let best = 0; let entry: Entry | null = null;
    for (let n = Math.min(MAX_PHRASE, ws.length - i); n >= 1; n--) {
      const slice = ws.slice(i, i + n);
      if (slice.some((x) => x.kind === 'measure' || x.kind === 'num') || slice[n - 1].kind === 'punct') continue;
      const key = slice.map((x) => x.t).join(' ').replace(/ ,/g, ',').toLowerCase();
      const e = n === 1 ? lookup(key) : (GLOSSARY.get(key) ?? null);
      if (e) { best = n; entry = e; break; }
    }
    const pn = properAt(ws, i);
    if (pn > best) { toks.push({ k: 'p', ar: ws.slice(i, i + pn).map((x) => x.t).join(' ') }); i += pn; continue; }
    if (entry) {
      const lw = ws.slice(i, i + best).map((x) => x.t.toLowerCase()).join(' ');
      if (lw === 'and') toks.push({ k: 'and', ar: 'و' });
      else if (lw === 'for') toks.push({ k: 'for', ar: 'ل' });
      else if (entry.ar) toks.push({ k: entry.fixed ? 'x' : 'n', ar: entry.ar, mat: entry.mat });
      i += best; continue;
    }
    if (/^and$/i.test(w.t)) { toks.push({ k: 'and', ar: 'و' }); i++; continue; }
    if (/^for$/i.test(w.t)) { toks.push({ k: 'for', ar: 'ل' }); i++; continue; }
    if (isProperToken(w.t)) { toks.push({ k: 'p', ar: w.t }); i++; continue; }
    unknown.push(w.t); i++;
  }
  // Assemble: a noun group (n, p, m) is emitted head-first — the object nouns reversed, then "من" and
  // the material nouns reversed, then proper nouns, then measures. Anything else holds its place.
  const chunks: string[] = []; let grp: Tok[] = [];
  const flush = () => {
    if (!grp.length) return;
    const heads = grp.filter((t) => t.k === 'n' && !t.mat).map((t) => t.ar).reverse();
    const mats = grp.filter((t) => t.k === 'n' && t.mat).map((t) => t.ar).reverse();
    const p = grp.filter((t) => t.k === 'p').map((t) => t.ar);
    const m = grp.filter((t) => t.k === 'm').map((t) => t.ar);
    const matPart = mats.length ? (heads.length ? ['من', ...mats] : mats) : [];
    chunks.push([...heads, ...matPart, ...p, ...m].join(' ')); grp = [];
  };
  for (const t of toks) {
    if (t.k === 'n' || t.k === 'p' || t.k === 'm') { grp.push(t); continue; }
    flush();
    if (t.k === 'punct') chunks.push(({ ',': '،', ';': '؛' } as Record<string, string>)[t.ar] ?? t.ar);
    else chunks.push(SEP + t.k + SEP + t.ar);
  }
  flush();
  // Join: "و" and "ل" attach to the next word; ل + ال → لل. Punctuation hugs the word before it.
  let out = '';
  for (let i = 0; i < chunks.length; i++) {
    let c = chunks[i];
    if (c.startsWith(SEP + 'and' + SEP) || c.startsWith(SEP + 'for' + SEP)) {
      const isFor = c.startsWith(SEP + 'for');
      const next = chunks[i + 1];
      if (next && !next.startsWith(SEP) && /^[؀-ۿ]/.test(next)) { chunks[i + 1] = isFor ? (next.startsWith('ال') ? 'لل' + next.slice(2) : 'ل' + next) : 'و' + next; continue; }
      c = isFor ? 'لـ' : 'و';
    } else if (c.startsWith(SEP)) c = c.split(SEP)[2];
    if (!c) continue;
    if (/^[،؛.:)\]]$/.test(c) || (/^[-–]$/.test(c) && /\d\s*$/.test(out))) out = out.replace(/\s+$/, '') + c + ' ';
    else if (/^[(\[]$/.test(c)) out += c;
    else out += c + ' ';
  }
  out = out.replace(/\s+/g, ' ').replace(/\s+([،؛.:)\]])/g, '$1').replace(/([(\[])\s+/g, '$1').replace(/^[،؛.\s]+/, '').trim();
  // Two separators in a row after a dropped unknown word ("،،", "، ."): keep one.
  out = out.replace(/([،؛])\s*[،؛]+/g, '$1').replace(/[،؛]\s*\./g, '.').replace(/\(\s*\)/g, '').replace(/[،؛]$/, '').trim();
  return { ar: out, complete: unknown.length === 0, unknown };
}

/** Supplier or customer text → Arabic. Deterministic; see the file header for the rules. Text that
 * is already Arabic keeps its Arabic; an English run inside it is translated in place. */
export function arTrade(input: unknown): ArText {
  const src = String(input ?? '').replace(/\s+/g, ' ').trim();
  if (!src) return { ar: '', complete: true, unknown: [] };
  if (hasArabic(src)) {
    const unknown: string[] = [];
    const ar = src.replace(/[A-Za-z][A-Za-z0-9 .,'&/+-]*[A-Za-z0-9]|[A-Za-z]/g, (run) => {
      if (run.split(/\s+/).every(isProperToken)) return run;
      const t = translateLatin(run);
      if (t.complete) return t.ar;
      unknown.push(...t.unknown); return run;
    });
    return { ar, complete: unknown.length === 0, unknown };
  }
  return translateLatin(src);
}
