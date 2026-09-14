// intake_requirements — the questions the SALES ENGINEER asks on every request before it can be
// posted, and the one shape the answers are stored in. Pure: no network, no env, no model.
//
// THE FOUNDER, 14 Sep 2026: "when we take the inquiry from the customer, we can ask those questions
// to make sure the inquiry is fully detailed ... do you require a warranty? do you require
// installation? do you have specific material in mind (for example if he is doing a custom table,
// maybe he wants the legs to be steel, or wood, or acrylic, or maybe he doesnt even care, but our
// job is to ask.)" Then: "its always the sales agent. no other agent is involved in customer or
// supplier portal." So every answer here is recorded under ACTOR = 'sales_engineer'. And later the
// same day: "for installation for example, we need to ask, cause maybe the customer will forget. we
// don't assume stuff."
//
// WHY A SECOND LIST BESIDE category_specs. category_specs.fields is what a supplier needs to PRICE
// the job (area, quantity, emirate). What was missing (measured 14 Sep 2026 over all 56 rows) is
// what the customer WANTS in the finished result: 0 of 56 categories asked about a warranty. Suppliers
// must state installation, warranty, materials and a date for every quote (the exact-specs-or-hold
// gate), so the customer's side of each has to exist first. It is the BASELINE that "matches your
// request / differs" is judged against, and the hold check reads installation and warranty
// applicability from THESE answers, never from trade defaults. See docs/contracts/intake_answers.md.
//
// THE RULES THE FOUNDER SET, AS CODE:
//   * all four, every trade, never assumed. Installation, warranty, a material preference for at
//     least one main component, and the required date are asked of EVERY request. A trade where
//     installation or a warranty is unusual (cleaning, movers, consultancy) still asks; its profile
//     only SUGGESTS "Not needed", and the customer confirms with one tap or picks another answer.
//   * a suggestion is never an answer. What the trade usually needs, and what the category
//     checklist already heard ("supply + installation", "2-4 weeks"), is offered as the suggested
//     option. Nothing is filled in without the customer choosing it.
//   * quick. Every question has options to tap; materials also take the customer's own words.
//   * explicit, never silent. Each question is answered only by an option ("Supply only", "Not
//     needed", "Not sure", "No preference", "Flexible" included) or, for materials, the customer's own
//     description. An unreadable answer to installation, warranty or the date is asked again.
//   * in the customer's language. Every question and option exists in English and Arabic (MSA).
//
// ponytail: one profile per category slug, hand-written against production's 56 category_specs
// rows (14 Sep 2026). A category added later gets DEFAULT_PROFILE until it is given its own row.
// When the per-trade spec model lands (branch exact-specs-or-hold) it can adopt PROFILES as its
// customer-side attribute list.
import { parseWhen, parseYesNo, isUnknown, normDigits } from '../inquiry_intake/interview.ts';

export const ACTOR = 'sales_engineer' as const;
export const VERSION = 2;
export type Lang = 'en' | 'ar';

/** [value, English label, Arabic label] */
type O = [string, string, string];
type Component = { c: string; en: string; ar: string; opts: O[]; field?: string };
/**
 * install / warranty say what this trade USUALLY needs. They never skip a question: when false, the
 * question is still asked and "Not needed" is offered as the suggestion for the customer to confirm.
 */
type Profile = { install: boolean; warranty: boolean; components: Component[] };

// ── COMPONENTS SHARED BY SEVERAL TRADES ─────────────────────────────────────────────────────────
const tier = (c: string, en: string, ar: string, field?: string): Component => ({ c, en, ar, field,
  opts: [['premium', 'Premium brands', 'ماركات فاخرة'], ['mid', 'Mid-range brands', 'ماركات متوسطة'], ['economy', 'Economy', 'اقتصادية']] });
const BOARD: Component = { c: 'board', en: 'Board / carcass', ar: 'الألواح والهيكل', field: 'carcass_material',
  opts: [['mr_mdf', 'Moisture-resistant MDF', 'MDF مقاوم للرطوبة'], ['plywood', 'Plywood', 'خشب رقائقي (بلاي وود)'], ['solid_wood', 'Solid wood', 'خشب طبيعي صلب'], ['particle_board', 'Particle board / chipboard', 'خشب حبيبي (شيبورد)']] };
const finish = (field?: string): Component => ({ c: 'finish', en: 'Finish', ar: 'التشطيب', field,
  opts: [['laminate', 'Laminate', 'لامينيت'], ['acrylic', 'Acrylic (high gloss)', 'أكريليك لامع'], ['lacquer', 'Lacquer / PU paint', 'دهان لاكر أو بولي يوريثين'], ['veneer', 'Natural wood veneer', 'قشرة خشب طبيعي']] });
const hardware = (field?: string): Component => ({ c: 'hardware', en: 'Hinges and runners', ar: 'المفصلات والمجاري', field,
  opts: [['branded_soft_close', 'Branded soft-close (Blum, Hettich, Häfele)', 'ماركات بإغلاق هادئ (Blum أو Hettich أو Häfele)'], ['standard', 'Standard', 'عادية']] });
const PIPES: Component = { c: 'pipes', en: 'Pipes', ar: 'الأنابيب',
  opts: [['ppr', 'PPR', 'أنابيب PPR'], ['copper', 'Copper', 'نحاس'], ['upvc', 'uPVC / CPVC', 'uPVC أو CPVC']] };
const FLOOR_FINISH: Component = { c: 'floor_finish', en: 'Floor finish', ar: 'تشطيب الأرضية',
  opts: [['porcelain', 'Porcelain tiles', 'بلاط بورسلان'], ['vinyl_spc', 'Vinyl / SPC', 'فينيل أو SPC'], ['carpet', 'Carpet tiles', 'بلاط سجاد'], ['marble', 'Marble', 'رخام']] };
const CEILING: Component = { c: 'ceiling', en: 'Ceiling', ar: 'السقف',
  opts: [['gypsum', 'Gypsum board', 'ألواح جبس'], ['grid', 'Grid / tile ceiling', 'سقف معلّق ببلاطات'], ['exposed', 'Exposed (painted)', 'مكشوف ومدهون']] };
const PARTITIONS: Component = { c: 'partitions', en: 'Partitions', ar: 'القواطع',
  opts: [['gypsum', 'Gypsum partitions', 'قواطع جبس'], ['glass', 'Glass partitions', 'قواطع زجاج'], ['block', 'Block walls', 'جدران بلوك']] };
/** The material question every trade gets when it has no components of its own. */
const GENERIC: Component = { c: 'main', en: 'Main material or brand', ar: 'المادة أو الماركة الرئيسية', opts: [] };

const P = (install: boolean, warranty: boolean, components: Component[]): Profile => ({ install, warranty, components });
export const DEFAULT_PROFILE: Profile = P(true, true, [GENERIC]);

// One row per production category_specs slug (56, read 14 Sep 2026). `field` names the
// category_specs key that already asks the same thing: when the customer answered it there, that
// answer is offered as the suggestion here (and still confirmed).
export const PROFILES: Record<string, Profile> = {
  acrylic: P(true, true, [{ c: 'sheet', en: 'Sheet type', ar: 'نوع اللوح', opts: [['cast_acrylic', 'Cast acrylic', 'أكريليك مصبوب'], ['extruded_acrylic', 'Extruded acrylic', 'أكريليك مبثوق'], ['polycarbonate', 'Polycarbonate', 'بولي كربونات']] }]),
  aluminium: P(true, true, [
    { c: 'profile', en: 'Aluminium profile system', ar: 'نظام قطاعات الألمنيوم', field: 'system_finish', opts: [['standard', 'Standard profile', 'قطاع عادي'], ['thermal_break', 'Thermal-break (insulated)', 'قطاع معزول حرارياً'], ['premium_brand', 'Premium system (Schüco, Technal)', 'نظام فاخر (Schüco أو Technal)']] },
    { c: 'glass', en: 'Glass', ar: 'الزجاج', field: 'glazing', opts: [['single', 'Single glazed', 'زجاج مفرد'], ['double', 'Double glazed', 'زجاج مزدوج'], ['laminated', 'Laminated safety glass', 'زجاج أمان مصفّح']] }]),
  'av-systems': P(true, true, [tier('equipment', 'Equipment brands', 'ماركات الأجهزة')]),
  'blinds-curtains': P(true, true, [
    { c: 'fabric', en: 'Fabric', ar: 'القماش', field: 'fabric', opts: [['blackout', 'Blackout', 'معتم بالكامل'], ['dim_out', 'Dim-out', 'نصف معتم'], ['sheer', 'Sheer', 'شفاف'], ['linen', 'Linen or cotton', 'كتان أو قطن']] },
    { c: 'mechanism', en: 'Track or mechanism', ar: 'السكة أو آلية التشغيل', field: 'operation', opts: [['manual', 'Manual track', 'سكة يدوية'], ['motorised', 'Motorised', 'كهربائية بمحرك']] }]),
  carpentry: P(true, true, [BOARD, finish('material_finish'), hardware()]),
  'carpentry-joinery': P(true, true, [BOARD, finish('finish'), hardware('hardware_level')]),
  carpets: P(true, true, [{ c: 'fibre', en: 'Carpet fibre', ar: 'ألياف السجاد', field: 'fibre', opts: [['nylon', 'Nylon', 'نايلون'], ['polypropylene', 'Polypropylene', 'بولي بروبيلين'], ['wool', 'Wool', 'صوف']] }]),
  cleaning: P(false, false, [{ c: 'products', en: 'Cleaning products', ar: 'مواد التنظيف', opts: [['standard', 'Standard products', 'مواد عادية'], ['eco', 'Eco-friendly, non-toxic', 'صديقة للبيئة وغير سامة']] }]),
  'combined-mep': P(true, true, [PIPES, tier('equipment', 'Equipment and cable brands', 'ماركات المعدات والكابلات')]),
  'commercial-retail-fitout': P(true, true, [FLOOR_FINISH, CEILING, PARTITIONS]),
  'custom-furniture': P(true, true, [
    { c: 'top_body', en: 'Top or main body', ar: 'السطح أو الجسم الرئيسي', opts: [['solid_wood', 'Solid wood', 'خشب طبيعي صلب'], ['mdf_veneer', 'MDF with veneer or laminate', 'MDF بقشرة خشب أو لامينيت'], ['glass', 'Glass', 'زجاج'], ['marble_stone', 'Marble or stone', 'رخام أو حجر'], ['metal', 'Metal', 'معدن']] },
    { c: 'legs_base', en: 'Legs or base', ar: 'الأرجل أو القاعدة', opts: [['steel', 'Steel', 'حديد (ستيل)'], ['wood', 'Wood', 'خشب'], ['acrylic', 'Acrylic', 'أكريليك'], ['aluminium', 'Aluminium', 'ألمنيوم']] },
    hardware('hardware')]),
  demolition: P(false, false, []),
  electrical: P(true, true, [tier('cables_devices', 'Cables, switches and sockets', 'الكابلات والمفاتيح والمقابس')]),
  elevators: P(true, true, [{ c: 'cabin_finish', en: 'Cabin finish', ar: 'تشطيب الكابينة', opts: [['stainless_hairline', 'Stainless steel (hairline)', 'ستانلس ستيل مطفي'], ['mirror_steel', 'Mirror stainless steel', 'ستانلس ستيل لامع كالمرآة'], ['glass', 'Glass', 'زجاج'], ['painted_steel', 'Painted steel', 'حديد مدهون']] }]),
  'engineering-and-architectural-consultancies': P(false, false, []),
  'epoxy-flooring': P(true, true, [{ c: 'resin', en: 'Resin system', ar: 'نوع الراتنج', opts: [['epoxy', 'Epoxy', 'إيبوكسي'], ['polyurethane', 'Polyurethane (PU)', 'بولي يوريثين'], ['polyaspartic', 'Polyaspartic', 'بولي أسبارتيك']] }]),
  'facade-cleaning': P(false, false, []),
  fitout: P(true, true, [FLOOR_FINISH, CEILING, PARTITIONS]),
  flooring: P(true, true, [tier('grade', 'Material grade', 'درجة المادة')]),
  'garage-doors': P(true, true, [{ c: 'panels', en: 'Door panels', ar: 'ألواح الباب', opts: [['insulated', 'Insulated (foam-filled)', 'معزولة (محشوة بالفوم)'], ['single_skin', 'Single skin', 'طبقة واحدة']] }]),
  general: P(true, true, [GENERIC]),
  'general-building-contracting': P(false, true, [
    { c: 'structure', en: 'Structure', ar: 'الهيكل الإنشائي', opts: [['rc', 'Reinforced concrete', 'خرسانة مسلحة'], ['steel_frame', 'Steel frame', 'هيكل حديدي'], ['load_bearing_block', 'Load-bearing blockwork', 'جدران بلوك حاملة']] },
    { c: 'finishes', en: 'Finishes', ar: 'التشطيبات', opts: [['premium', 'Premium', 'فاخرة'], ['standard', 'Standard', 'عادية'], ['economy', 'Economy', 'اقتصادية']] }]),
  'general-services-other': P(false, false, [GENERIC]),
  generators: P(true, true, [
    { c: 'engine', en: 'Engine brand', ar: 'ماركة المحرك', opts: [['perkins', 'Perkins', 'Perkins'], ['cummins', 'Cummins', 'Cummins'], ['volvo_penta', 'Volvo Penta', 'Volvo Penta'], ['other_brand', 'Another recognised brand', 'ماركة معروفة أخرى']] },
    { c: 'alternator', en: 'Alternator brand', ar: 'ماركة المولّد الكهربائي (الدينامو)', opts: [['stamford', 'Stamford', 'Stamford'], ['leroy_somer', 'Leroy-Somer', 'Leroy-Somer'], ['mecc_alte', 'Mecc Alte', 'Mecc Alte']] }]),
  glass: P(true, true, [{ c: 'frame', en: 'Frame', ar: 'الإطار', opts: [['aluminium', 'Aluminium framed', 'بإطار ألمنيوم'], ['frameless', 'Frameless', 'بدون إطار'], ['steel', 'Steel framed', 'بإطار حديد']] }]),
  gypsum: P(true, true, [{ c: 'board', en: 'Gypsum board', ar: 'ألواح الجبس', opts: [['standard', 'Standard board', 'ألواح عادية'], ['moisture_resistant', 'Moisture-resistant (green) board', 'ألواح مقاومة للرطوبة'], ['fire_rated', 'Fire-rated board', 'ألواح مقاومة للحريق']] }]),
  hvac: P(true, true, [tier('brand', 'Air-conditioning brand', 'ماركة المكيفات', 'brand_tier'),
    { c: 'ducting', en: 'Ducting', ar: 'مجاري الهواء', opts: [['gi', 'Galvanised steel (GI)', 'حديد مجلفن'], ['pre_insulated', 'Pre-insulated panel', 'ألواح معزولة مسبقاً'], ['flexible', 'Flexible duct', 'مجاري مرنة']] }]),
  insulation: P(true, true, [{ c: 'material', en: 'Insulation material', ar: 'مادة العزل', field: 'material', opts: [['xps_eps', 'XPS / EPS board', 'ألواح XPS أو EPS'], ['pu_spray', 'Polyurethane spray', 'رش بولي يوريثين'], ['rockwool', 'Rockwool / mineral wool', 'صوف صخري']] }]),
  'interior-design': P(false, false, []),
  'it-networking': P(true, true, [{ c: 'cabling', en: 'Cabling', ar: 'الكابلات', opts: [['cat6', 'Cat6', 'Cat6'], ['cat6a', 'Cat6A', 'Cat6A'], ['fibre', 'Fibre optic', 'ألياف ضوئية']] }, tier('equipment', 'Network equipment brands', 'ماركات أجهزة الشبكة')]),
  'job-shop-manufacturing': P(false, true, []),
  kitchens: P(true, true, [BOARD, finish('field_3'),
    { c: 'countertop', en: 'Countertop', ar: 'سطح المطبخ', opts: [['quartz', 'Quartz', 'كوارتز'], ['granite', 'Granite', 'جرانيت'], ['solid_surface', 'Solid surface (Corian)', 'سطح صلب (كوريان)'], ['laminate', 'Laminate', 'لامينيت']] }]),
  landscaping: P(true, true, [
    { c: 'paving', en: 'Paving', ar: 'الأرضيات الخارجية', opts: [['interlock', 'Interlock', 'إنترلوك'], ['natural_stone', 'Natural stone', 'حجر طبيعي'], ['porcelain', 'Outdoor porcelain', 'بورسلان خارجي']] },
    { c: 'lawn', en: 'Lawn', ar: 'العشب', opts: [['natural', 'Natural grass', 'عشب طبيعي'], ['artificial', 'Artificial grass', 'عشب صناعي']] }]),
  'marble-granite': P(true, true, [{ c: 'stone', en: 'Stone', ar: 'نوع الحجر', field: 'field_3', opts: [['marble', 'Marble', 'رخام'], ['granite', 'Granite', 'جرانيت'], ['quartz', 'Quartz', 'كوارتز'], ['travertine', 'Travertine', 'ترافرتين']] }]),
  masonry: P(false, true, [{ c: 'block', en: 'Blocks', ar: 'البلوك', opts: [['hollow', 'Hollow concrete block', 'بلوك خرساني مفرغ'], ['solid', 'Solid block', 'بلوك مصمت'], ['aac', 'Lightweight thermal block (AAC)', 'بلوك خفيف عازل (AAC)']] }]),
  mep: P(true, true, [PIPES, tier('equipment', 'Equipment and cable brands', 'ماركات المعدات والكابلات')]),
  movers: P(false, false, []),
  painting: P(false, true, [
    { c: 'brand', en: 'Paint brand', ar: 'ماركة الدهان', opts: [['jotun', 'Jotun', 'جوتن'], ['national', 'National Paints', 'الدهانات الوطنية'], ['asian', 'Asian Paints', 'Asian Paints'], ['other_brand', 'Another brand', 'ماركة أخرى']] },
    { c: 'finish', en: 'Paint finish', ar: 'لمعة الدهان', field: 'finish', opts: [['matte', 'Matte', 'مطفي'], ['silk', 'Silk / satin', 'نصف لامع'], ['gloss', 'Gloss', 'لامع']] }]),
  pest: P(false, true, [{ c: 'treatment', en: 'Treatment', ar: 'نوع المعالجة', opts: [['standard', 'Standard', 'عادية'], ['odourless', 'Odourless, safe for children and pets', 'بدون رائحة وآمنة للأطفال والحيوانات'], ['organic', 'Organic / green', 'عضوية وصديقة للبيئة']] }]),
  plumbing: P(true, true, [PIPES,
    { c: 'fixtures', en: 'Sanitary fixtures', ar: 'الأدوات الصحية', field: 'fixtures_grade', opts: [['premium', 'Premium (Grohe, Duravit, TOTO)', 'فاخرة (Grohe أو Duravit أو TOTO)'], ['mid', 'Mid-range (RAK, Geberit, American Standard)', 'متوسطة (RAK أو Geberit أو American Standard)'], ['economy', 'Economy', 'اقتصادية']] }]),
  roofing: P(true, true, [{ c: 'membrane', en: 'Roof membrane', ar: 'غشاء السطح', opts: [['bitumen', 'Bitumen membrane', 'غشاء بيتومين'], ['pvc_tpo', 'PVC / TPO membrane', 'غشاء PVC أو TPO'], ['liquid', 'Liquid-applied coating', 'طلاء سائل']] }]),
  safety: P(true, true, [{ c: 'equipment', en: 'Equipment approvals', ar: 'اعتمادات المعدات', opts: [['ul_fm', 'UL / FM listed', 'معتمدة من UL أو FM'], ['civil_defence', 'Civil Defence approved', 'معتمدة من الدفاع المدني']] }]),
  scaffolding: P(false, false, []),
  security: P(true, true, [{ c: 'cameras', en: 'Camera brand', ar: 'ماركة الكاميرات', opts: [['premium', 'Premium (Axis, Hanwha, Bosch)', 'فاخرة (Axis أو Hanwha أو Bosch)'], ['mid', 'Mid-range (Hikvision, Dahua)', 'متوسطة (Hikvision أو Dahua)']] }]),
  signage: P(true, true, [
    { c: 'face', en: 'Sign face', ar: 'واجهة اللوحة', opts: [['acrylic', 'Acrylic', 'أكريليك'], ['acp', 'Aluminium composite (ACP)', 'ألمنيوم مركب (ACP)'], ['stainless', 'Stainless steel', 'ستانلس ستيل']] },
    { c: 'lighting', en: 'Lighting', ar: 'الإضاءة', opts: [['led_modules', 'LED modules', 'وحدات LED'], ['neon_flex', 'LED neon flex', 'نيون LED مرن'], ['none', 'No lighting', 'بدون إضاءة']] }]),
  'smart-home': P(true, true, [{ c: 'platform', en: 'Control system', ar: 'نظام التحكم', opts: [['knx', 'KNX (wired)', 'KNX سلكي'], ['zigbee', 'Zigbee / Z-Wave (wireless)', 'Zigbee أو Z-Wave لاسلكي'], ['wifi', 'Wi-Fi devices', 'أجهزة Wi-Fi']] }]),
  solar: P(true, true, [
    { c: 'panels', en: 'Solar panels', ar: 'الألواح الشمسية', opts: [['mono', 'Monocrystalline', 'أحادية البلورة'], ['bifacial', 'Bifacial', 'ثنائية الوجه']] },
    { c: 'inverter', en: 'Inverter brand', ar: 'ماركة العاكس', opts: [['huawei', 'Huawei', 'Huawei'], ['sma', 'SMA', 'SMA'], ['fronius', 'Fronius', 'Fronius']] }]),
  steel: P(true, true, [{ c: 'finish', en: 'Finish', ar: 'التشطيب', field: 'finish', opts: [['powder', 'Powder-coated', 'دهان بودرة'], ['galvanised', 'Hot-dip galvanised', 'مجلفن بالغمس الساخن'], ['painted', 'Painted', 'مدهون']] }]),
  'structural-steel-fabrication': P(true, true, [{ c: 'grade', en: 'Steel grade', ar: 'درجة الحديد', opts: [['s275', 'S275', 'S275'], ['s355', 'S355', 'S355']] }]),
  'swimming-pools': P(true, true, [
    { c: 'finish', en: 'Pool finish', ar: 'تشطيب المسبح', opts: [['mosaic', 'Glass mosaic tiles', 'موزاييك زجاجي'], ['porcelain', 'Porcelain tiles', 'بلاط بورسلان'], ['plaster', 'Pool plaster', 'لياسة مسابح']] },
    tier('equipment', 'Pumps and filtration brands', 'ماركات المضخات والفلاتر')]),
  'tents-and-shade-structures': P(true, true, [
    { c: 'fabric', en: 'Fabric', ar: 'القماش', field: 'fabric', opts: [['pvc', 'Standard PVC', 'PVC عادي'], ['pvdf', 'PVDF (long UV life)', 'PVDF (يدوم أطول تحت الشمس)'], ['hdpe', 'HDPE shade mesh', 'شبك تظليل HDPE']] },
    { c: 'frame', en: 'Frame', ar: 'الهيكل', opts: [['aluminium', 'Aluminium', 'ألمنيوم'], ['steel', 'Galvanised steel', 'حديد مجلفن']] }]),
  tiling: P(true, true, [{ c: 'grout', en: 'Grout', ar: 'الترويب', opts: [['cement', 'Cement grout', 'ترويب إسمنتي'], ['epoxy', 'Epoxy grout', 'ترويب إيبوكسي']] }]),
  upholstery: P(true, true, [{ c: 'fabric', en: 'Fabric', ar: 'القماش', field: 'fabric', opts: [['leather', 'Leather', 'جلد'], ['velvet', 'Velvet', 'مخمل'], ['linen', 'Linen or cotton', 'كتان أو قطن']] }]),
  wallpaper: P(true, true, [{ c: 'material', en: 'Wallpaper material', ar: 'مادة ورق الجدران', opts: [['vinyl', 'Vinyl', 'فينيل'], ['non_woven', 'Non-woven', 'غير منسوج'], ['fabric', 'Fabric', 'قماش']] }]),
  'water-tank-cleaning': P(false, false, []),
  waterproofing: P(false, true, [{ c: 'system', en: 'Waterproofing system', ar: 'نظام العزل المائي', opts: [['bitumen', 'Bitumen membrane', 'غشاء بيتومين'], ['pu_liquid', 'Polyurethane liquid', 'بولي يوريثين سائل'], ['cementitious', 'Cementitious coating', 'طلاء إسمنتي']] }]),
};
export const profileFor = (category: string): Profile => PROFILES[String(category || '')] || DEFAULT_PROFILE;
/** A component's names from the catalogue above, for a stored material that carries only its key
 * (measured 14 Sep 2026: a request with materials [{component:'glass'}] printed "المادة — glass" in
 * the Arabic comparison). The first trade that defines the key names it. */
export function componentLabel(c: string): { en: string; ar: string } | null {
  for (const p of [...Object.values(PROFILES), DEFAULT_PROFILE]) {
    const hit = p.components.find((x) => x.c === c);
    if (hit) return { en: hit.en, ar: hit.ar };
  }
  return null;
}

// ── THE QUESTIONS ────────────────────────────────────────────────────────────────────────────────
export type Kind = 'material' | 'installation' | 'warranty' | 'required_by';
export type Opt = { v: string; en: string; ar: string };
/** `suggested` is the option value the TRADE usually needs. It is offered, never recorded. */
export type ReqQuestion = { key: string; kind: Kind; label_en: string; label_ar: string; en: string; ar: string; options: Opt[]; free_text: boolean; field?: string; suggested?: string };

const o = ([v, en, ar]: O): Opt => ({ v, en, ar });
export const NO_PREFERENCE: Opt = { v: 'no_preference', en: 'No preference', ar: 'لا تفضيل لدي' };
const NOT_SURE: Opt = { v: 'not_sure', en: 'Not sure', ar: 'لست متأكداً' };
export const INSTALL_VALUES = ['yes', 'supply_only', 'not_needed', 'not_sure'] as const;
export const WARRANTY_VALUES = ['yes', 'not_needed', 'not_sure'] as const;
const INSTALL: Opt[] = [
  { v: 'yes', en: 'Yes, install it', ar: 'نعم، مع التركيب' },
  { v: 'supply_only', en: 'Supply only, no installation', ar: 'توريد فقط، بدون تركيب' },
  { v: 'not_needed', en: 'Not needed for this job', ar: 'غير مطلوب لهذا العمل' }, NOT_SURE];
const WARRANTY: (Opt & { months?: number })[] = [
  { v: 'yes_12', en: 'Yes, at least 1 year', ar: 'نعم، سنة على الأقل', months: 12 },
  { v: 'yes_24', en: 'Yes, at least 2 years', ar: 'نعم، سنتان على الأقل', months: 24 },
  { v: 'yes_60', en: 'Yes, at least 5 years', ar: 'نعم، 5 سنوات على الأقل', months: 60 },
  { v: 'not_needed', en: 'Not needed', ar: 'غير مطلوب' }, NOT_SURE];
const WHEN: (Opt & { days?: number })[] = [
  { v: 'w2', en: 'Within 2 weeks', ar: 'خلال أسبوعين', days: 14 },
  { v: 'm1', en: 'Within 1 month', ar: 'خلال شهر', days: 30 },
  { v: 'm3', en: 'Within 3 months', ar: 'خلال 3 أشهر', days: 90 },
  { v: 'flexible', en: 'Flexible, no fixed date', ar: 'مرن، لا يوجد موعد محدد' }];

/** The questions for a category, in the order asked: materials, installation, warranty, date. All four kinds, always. */
export function requirementQuestions(category: string): ReqQuestion[] {
  const p = profileFor(category);
  const comps = p.components.length ? p.components : [GENERIC];
  const qs: ReqQuestion[] = comps.map((c) => ({
    key: 'material.' + c.c, kind: 'material', label_en: c.en, label_ar: c.ar, field: c.field,
    en: `Any preference for the ${c.en.charAt(0).toLowerCase() + c.en.slice(1)}? Tap one, or type what you have in mind.`,
    ar: `هل لديك تفضيل بخصوص ${c.ar}؟ اختر أحد الخيارات، أو اكتب ما في ذهنك.`,
    options: [...c.opts.map(o), NO_PREFERENCE], free_text: true,
  }));
  qs.push({ key: 'installation', kind: 'installation', label_en: 'Installation', label_ar: 'التركيب', en: 'Do you need the supplier to install it, or only deliver it?', ar: 'هل تحتاج أن يقوم المورد بالتركيب، أم التوريد فقط؟', options: INSTALL, free_text: false, suggested: p.install ? undefined : 'not_needed' });
  qs.push({ key: 'warranty', kind: 'warranty', label_en: 'Warranty', label_ar: 'الضمان', en: 'Do you need a warranty, and for how long at least?', ar: 'هل تحتاج ضماناً، وما أقل مدة تقبلها؟', options: WARRANTY, free_text: false, suggested: p.warranty ? undefined : 'not_needed' });
  qs.push({ key: 'required_by', kind: 'required_by', label_en: 'Needed by', label_ar: 'مطلوب بحلول', en: 'By when do you need it done or delivered? Tap one, or type a date.', ar: 'متى تحتاج إنجاز العمل أو التسليم؟ اختر أحد الخيارات، أو اكتب تاريخاً.', options: WHEN, free_text: false });
  return qs;
}
export const questionIn = (q: ReqQuestion, lang: Lang) => (lang === 'ar' ? q.ar : q.en);
export const optionLabels = (q: ReqQuestion, lang: Lang) => q.options.map((x) => (lang === 'ar' ? x.ar : x.en));

// ── ONE ANSWER ───────────────────────────────────────────────────────────────────────────────────
export type Ans = { v: string; note?: string | null; min_months?: number | null; date?: string | null; text?: string | null };
export type Answers = Record<string, Ans>;

const isoDay = (now: Date, days: number) => new Date(now.getTime() + days * 86400000).toISOString().slice(0, 10);
const NOPREF_RE = /no preference|no specific|doesn'?t matter|does not matter|don'?t mind|don'?t care|whatever|any (?:is|will be) fine|up to (?:you|the supplier)|supplier (?:to )?(?:decide|choose|recommend)|لا تفضيل|لا يهم|أي شيء|اي شيء|أي نوع|اي نوع|حسب المورد|بدون تفضيل|ليس لدي تفضيل/i;
const NOT_NEEDED_RE = /not needed|no need|don'?t need|do not need|not required|غير مطلوب|لا نحتاج|لا أحتاج|لا احتاج|لا حاجة/i;
function warrantyMonths(t: string): number | null {
  const m = t.match(/(\d+(?:\.\d+)?)\s*(years?|yrs?|سنة|سنوات|سنين|أعوام|اعوام|عام|months?|mos?|شهر|أشهر|اشهر|شهور|شهراً|شهرا)/i);
  if (m) { const n = Number(m[1]); if (!(n > 0)) return null; return Math.round(/month|mo|شهر|أشهر|اشهر|شهور/i.test(m[2]) ? n : n * 12); }
  if (/سنتين|سنتان|two years/i.test(t)) return 24;
  if (/\b(a|one) year\b|(^|\s)سنة(\s|$)|(^|\s)عام(\s|$)/i.test(t)) return 12;
  return null;
}
function fromOption(q: ReqQuestion, x: Opt & { months?: number; days?: number }, now: Date): Ans {
  if (q.kind === 'warranty') return x.months ? { v: 'yes', min_months: x.months } : { v: x.v, min_months: null };
  if (q.kind === 'required_by') return x.days ? { v: 'date', date: isoDay(now, x.days), text: x.en } : { v: 'flexible', date: null, text: x.en };
  return { v: x.v };
}

/**
 * Parse `text` as the answer to `q`. A tapped option comes back as its own label in either language.
 * Returns null when the text does not answer the question: the caller asks it again rather than
 * guessing. A bare "no" to installation is asked again, because it could mean "supply only" or "not
 * needed" and the supplier quotes differently for each. Materials never return null: the customer's
 * own words ARE an answer ('other' + note).
 */
export function parseRequirementAnswer(q: ReqQuestion, text: string, now = new Date()): Ans | null {
  const raw = normDigits(String(text || '')).replace(/\s+/g, ' ').trim();
  if (!raw) return null;
  const lo = raw.toLowerCase();
  const exact = q.options.find((x) => x.en.toLowerCase() === lo || x.ar === raw || x.v === lo);
  if (exact) return fromOption(q, exact, now);
  switch (q.kind) {
    case 'installation': {
      if (isUnknown(raw)) return { v: 'not_sure' };
      if (/supply only|delivery only|deliver only|just deliver|only deliver|توريد فقط|التوريد فقط|بدون تركيب/.test(lo)) return { v: 'supply_only' };
      if (NOT_NEEDED_RE.test(raw)) return { v: 'not_needed' };
      if (parseYesNo(raw) === 'Yes' || /\binstall|تركيب|ركّب|ركب/.test(lo)) return { v: 'yes' };
      return null;
    }
    case 'warranty': {
      if (isUnknown(raw)) return { v: 'not_sure', min_months: null };
      const months = warrantyMonths(raw);
      if (!months && (NOT_NEEDED_RE.test(raw) || parseYesNo(raw) === 'No')) return { v: 'not_needed', min_months: null };
      // "Yes" with no period is not an answer to "for how long at least": asked again, not guessed.
      return months ? { v: 'yes', min_months: months } : null;
    }
    case 'material': {
      const other = raw.match(/^(?:other|أخرى)\s*:\s*(.+)$/i);
      if (other) return { v: 'other', note: other[1].slice(0, 200) };
      const hit = q.options.find((x) => {
        if (x.v === NO_PREFERENCE.v) return false;
        const en = x.en.toLowerCase().replace(/\s*\(.*?\)\s*/g, ' ').trim();
        const enHead = en.split(/[\s/,]+/)[0];
        const arHead = x.ar.split(/[\s(]/)[0];
        return lo.includes(en) || (enHead.length > 3 && new RegExp(`(^|[^a-z])${enHead.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^a-z]|$)`).test(lo)) || (arHead.length > 2 && raw.includes(arHead));
      });
      if (hit) return { v: hit.v };
      if (NOPREF_RE.test(raw) || isUnknown(raw)) return { v: NO_PREFERENCE.v };
      // The customer's own words are an answer — a phrase, not a paragraph about something else
      // (measured, harness journey a: "Ground and first floor, direct vehicle access, no crane
      // needed. Budget is open." was recorded as the aluminium profile). A long statement is asked again.
      // "A phrase" = one clause, at most 80 characters: a reply with a sentence break in it is a
      // statement (the measured one was 79 characters, so length alone was not the test).
      return raw.length <= 80 && !/[.!?؟]\s+\S/.test(raw) ? { v: 'other', note: raw.slice(0, 200) } : null;
    }
    case 'required_by': {
      const iso = raw.match(/\b(\d{4})-(\d{2})-(\d{2})\b/);
      if (iso && !isNaN(Date.parse(iso[0]))) return { v: 'date', date: iso[0], text: iso[0] };
      const w = parseWhen(raw, now);
      if (!w) return null;
      if (w.flexible) return { v: 'flexible', date: null, text: 'Flexible' };
      if (w.days === null) return null;
      return { v: 'date', date: isoDay(now, w.days), text: w.text };
    }
  }
  return null;
}

/** A stored or carried answer that is not a valid answer to `q` today (e.g. version 1's 'no') is not an answer. */
export function isValidAnswer(q: ReqQuestion, v: Ans | undefined): boolean {
  if (!v) return false;
  if (q.kind === 'installation') return (INSTALL_VALUES as readonly string[]).includes(v.v);
  if (q.kind === 'warranty') return v.v === 'yes' ? Number.isInteger(v.min_months) && Number(v.min_months) > 0 : ['not_needed', 'not_sure'].includes(v.v);
  if (q.kind === 'material') return v.v === 'other' ? !!String(v.note || '').trim() : q.options.some((x) => x.v === v.v);
  return v.v === 'flexible' || /^\d{4}-\d{2}-\d{2}$/.test(String(v.date || ''));
}

/**
 * SUGGESTIONS, never answers. What the category checklist already heard (a material field, a
 * supply/install scope, a timeline) and, failing that, what the trade usually needs. Offered as the
 * highlighted option; the customer confirms it by tapping it, or picks another.
 */
export function suggestions(category: string, details: Record<string, unknown>, now = new Date()): Answers {
  const out: Answers = {};
  const d = details || {};
  const val = (k: string) => { const v = d[k]; return v == null ? '' : String(v).trim(); };
  for (const q of requirementQuestions(category)) {
    if (q.kind === 'material' && q.field) {
      const v = val(q.field);
      if (v && !isUnknown(v) && !/^not sure/i.test(v)) out[q.key] = parseRequirementAnswer(q, v, now) || { v: 'other', note: v.slice(0, 200) };
    }
    if (q.kind === 'installation') {
      const k = Object.keys(d).find((x) => /supply_install|^scope|installation|scope_mode|delivery_erection/.test(x) && val(x));
      const v = k ? val(k).toLowerCase() : '';
      if (/supply only|delivery only|supply and delivery only|توريد فقط/.test(v)) out[q.key] = { v: 'supply_only' };
      else if (/install|application|تركيب/.test(v)) out[q.key] = { v: 'yes' };
    }
    if (q.kind === 'required_by') {
      const k = Object.keys(d).find((x) => /timeline|timing|deadline|date|duration/.test(x) && val(x));
      const a = k ? parseRequirementAnswer(q, val(k), now) : null;
      if (a) out[q.key] = a;
    }
    if (!out[q.key] && q.suggested) out[q.key] = q.kind === 'warranty' ? { v: q.suggested, min_months: null } : { v: q.suggested };
  }
  return out;
}

/**
 * ANSWERS THE CUSTOMER ALREADY STATED, in their own words, anywhere in the conversation. Not
 * suggestions: only an unambiguous statement is read — "installation is required", "2 year
 * warranty", "delivery needed by 30 November 2026", or an option of a material question named
 * outright. Measured on harness journey a (14 Sep 2026): the customer said all four in their first
 * three messages and was asked all four again, with each later message stored as the wrong answer.
 */
export function statedAnswers(category: string, conversation: string, now = new Date()): Answers {
  const out: Answers = {};
  const t = normDigits(String(conversation || '')).replace(/\s+/g, ' ');
  const lo = t.toLowerCase();
  for (const q of requirementQuestions(category)) {
    if (q.kind === 'installation') {
      if (/\b(?:supply|delivery|deliver)\s+only\b|\bwithout installation\b|\bno installation\b|توريد فقط|بدون تركيب/.test(lo)) out[q.key] = { v: 'supply_only' };
      else if (/\binstallation (?:is )?(?:required|needed|included)\b|\bsuppl(?:y|ied) and install(?:ed)?\b|\bwith installation\b|\bneeds? (?:to be )?installed\b|مع التركيب|التوريد والتركيب/.test(lo)) out[q.key] = { v: 'yes' };
    }
    if (q.kind === 'warranty') {
      const m = lo.match(/(\d+(?:\.\d+)?|one|two|three|five|ten)[\s-]*(years?|yrs?|months?)[\s-]+warranty|warranty (?:of|for)\s+(?:at least\s+)?(\d+(?:\.\d+)?|one|two|three|five|ten)\s*(years?|months?)/);
      if (m) {
        const words: Record<string, number> = { one: 1, two: 2, three: 3, five: 5, ten: 10 };
        const n = Number(words[m[1] || m[3]] ?? (m[1] || m[3])); const unit = m[2] || m[4];
        if (n > 0) out[q.key] = { v: 'yes', min_months: Math.round(/month/.test(unit) ? n : n * 12) };
      }
    }
    if (q.kind === 'required_by') {
      const d = t.match(/\b(?:by|before|deadline|needed by|required by|delivery (?:needed |required )?by)\s+(\d{1,2}\s+[A-Za-z]+\s+\d{4}|[A-Za-z]+\s+\d{1,2},?\s+\d{4}|\d{1,2}[\/.-]\d{1,2}[\/.-]\d{2,4}|\d{4}-\d{2}-\d{2})/i);
      if (d) {
        const parsed = Date.parse(d[1].replace(/(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})/, '$3-$2-$1'));
        if (!isNaN(parsed)) { const iso = new Date(parsed + 12 * 3600e3).toISOString().slice(0, 10); if (iso >= now.toISOString().slice(0, 10)) out[q.key] = { v: 'date', date: iso, text: d[1] }; }
      }
    }
    if (q.kind === 'material') {
      // Hyphens and spaces fold the same way on both sides: the option "Thermal-break (insulated)"
      // is what a customer writes as "thermal break" (measured, harness journey a).
      const fold = (s: string) => s.toLowerCase().replace(/[-\s]+/g, ' ').trim();
      const flo = fold(lo);
      const hit = q.options.find((x) => x.v !== NO_PREFERENCE.v && (() => { const en = fold(x.en.replace(/\s*\(.*?\)\s*/g, ' ')); return en.length > 4 && new RegExp(`(^|[^a-z])${en.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^a-z]|$)`).test(flo); })());
      if (hit) out[q.key] = { v: hit.v };
    }
  }
  return out;
}

export type ReqStep = {
  answers: Answers; filled_now: string[]; retry: boolean;
  next: { key: string; text: string; options: string[]; suggested: string | null } | null;
  remaining: string[]; filled: number; total: number; complete: boolean;
};
/**
 * One turn: `text` answers `askedKey` (the question last asked); the next unanswered question is
 * returned with its suggestion, if any, highlighted but NOT recorded. Only the customer's own choice
 * fills an answer.
 */
export function requirementsStep(category: string, prev: Answers, askedKey: string | null, text: string, details: Record<string, unknown>, lang: Lang, now = new Date(), conversation = ''): ReqStep {
  const qs = requirementQuestions(category);
  const answers: Answers = {};
  for (const q of qs) if (prev && isValidAnswer(q, prev[q.key])) answers[q.key] = prev[q.key];
  const filledNow: string[] = [];
  // What the customer already said outright is their answer; nothing inferred, nothing suggested.
  const stated = conversation ? statedAnswers(category, conversation, now) : {};
  for (const q of qs) if (!answers[q.key] && stated[q.key] && isValidAnswer(q, stated[q.key])) { answers[q.key] = stated[q.key]; filledNow.push(q.key); }
  let retry = false;
  if (askedKey && String(text || '').trim()) {
    const q = qs.find((x) => x.key === askedKey);
    if (q && !answers[q.key]) {
      const a = parseRequirementAnswer(q, text, now);
      if (a && isValidAnswer(q, a)) { answers[q.key] = a; filledNow.push(q.key); } else retry = true;
    }
  }
  const missing = qs.filter((q) => !answers[q.key]);
  const n = missing[0];
  let next: ReqStep['next'] = null;
  if (n) {
    const s = suggestions(category, details, now)[n.key];
    const sLabel = s && isValidAnswer(n, s) ? describe(n, s, lang) : null;
    const options = optionLabels(n, lang);
    if (sLabel && !options.includes(sLabel)) options.unshift(sLabel);
    const hint = sLabel ? (lang === 'ar' ? ` المقترح لهذا العمل: ${sLabel}. اضغطه للتأكيد، أو اختر غيره.` : ` Suggested for this job: ${sLabel}. Tap it to confirm, or pick another.`) : '';
    next = { key: n.key, text: questionIn(n, lang) + hint, options, suggested: sLabel };
  }
  return {
    answers, filled_now: filledNow, retry, next,
    remaining: missing.map((q) => questionIn(q, lang)),
    filled: qs.length - missing.length, total: qs.length, complete: !n,
  };
}

// ── THE STORED SHAPE (docs/contracts/intake_answers.md) ─────────────────────────────────────────
type Row = { key: string; label: string; value: string };
export type Stored = {
  version: 2; recorded_by: typeof ACTOR; category: string; recorded_at: string;
  installation: { required: typeof INSTALL_VALUES[number] } | null;
  warranty: { required: typeof WARRANTY_VALUES[number]; min_months: number | null } | null;
  materials: { component: string; label_en: string; label_ar: string; choice: string; choice_en: string; choice_ar: string; note: string | null }[];
  required_by: { flexible: boolean; date: string | null; text: string | null };
  display: { en: Row[]; ar: Row[] };
};

function describe(q: ReqQuestion, a: Ans, lang: Lang): string {
  const L = (x: Opt) => (lang === 'ar' ? x.ar : x.en);
  if (q.kind === 'material') {
    if (a.v === 'other') return (lang === 'ar' ? 'أخرى: ' : 'Other: ') + String(a.note || '');
    const x = q.options.find((y) => y.v === a.v); return x ? L(x) : a.v;
  }
  if (q.kind === 'installation') { const x = INSTALL.find((y) => y.v === a.v); return x ? L(x) : a.v; }
  if (q.kind === 'warranty') {
    if (a.v === 'yes') {
      const x = WARRANTY.find((y) => y.months === a.min_months);
      if (x) return L(x);
      return lang === 'ar' ? `نعم، ${a.min_months} شهراً على الأقل` : `Yes, at least ${a.min_months} months`;
    }
    const x = WARRANTY.find((y) => y.v === a.v); return x ? L(x) : a.v;
  }
  if (a.v === 'flexible') return L(WHEN[3]);
  return (lang === 'ar' ? 'بحلول ' : 'By ') + String(a.date || '');
}

/** The customer's explicit answers, in the stored shape. An unanswered question stays null / absent and fails validateStored. */
export function toStored(category: string, answers: Answers, now = new Date()): Stored {
  const qs = requirementQuestions(category);
  const get = (k: string) => answers[k];
  const inst = get('installation'), war = get('warranty'), when = get('required_by');
  const disp = (lang: Lang) => qs.filter((q) => get(q.key)).map((q) => ({ key: q.key, label: lang === 'ar' ? q.label_ar : q.label_en, value: describe(q, get(q.key)!, lang) }));
  return {
    version: 2, recorded_by: ACTOR, category, recorded_at: now.toISOString(),
    installation: inst ? { required: inst.v as typeof INSTALL_VALUES[number] } : null,
    warranty: war ? { required: war.v as typeof WARRANTY_VALUES[number], min_months: war.v === 'yes' ? Number(war.min_months) : null } : null,
    materials: qs.filter((q) => q.kind === 'material' && get(q.key)).map((q) => {
      const a = get(q.key)!;
      return { component: q.key.slice('material.'.length), label_en: q.label_en, label_ar: q.label_ar, choice: a.v,
        choice_en: describe(q, a, 'en'), choice_ar: describe(q, a, 'ar'), note: a.v === 'other' ? String(a.note || '') : null };
    }),
    required_by: when ? { flexible: when.v === 'flexible', date: when.v === 'flexible' ? null : (when.date || null), text: when.text || null } : { flexible: false, date: null, text: null },
    display: { en: disp('en'), ar: disp('ar') },
  };
}

/** The inverse, so an edit can be applied to a stored answer set and re-validated. */
export function toAnswers(s: Partial<Stored> | null | undefined): Answers {
  const a: Answers = {};
  if (!s || typeof s !== 'object') return a;
  if (s.installation && s.installation.required) a.installation = { v: s.installation.required };
  if (s.warranty && s.warranty.required) a.warranty = { v: s.warranty.required, min_months: s.warranty.min_months ?? null };
  for (const m of Array.isArray(s.materials) ? s.materials : []) if (m && m.component && m.choice) a['material.' + m.component] = { v: m.choice, note: m.note ?? null };
  if (s.required_by && (s.required_by.flexible || s.required_by.date)) a.required_by = s.required_by.flexible ? { v: 'flexible', date: null, text: s.required_by.text } : { v: 'date', date: s.required_by.date, text: s.required_by.text };
  return a;
}

/** The post gate: all four kinds answered explicitly, in the current version, recorded by the sales engineer. */
export function validateStored(category: string, s: unknown): { ok: boolean; missing: string[] } {
  const x = (s && typeof s === 'object' ? s : {}) as Partial<Stored>;
  const missing: string[] = [];
  if ((x as { version?: unknown }).version !== VERSION || x.recorded_by !== ACTOR || x.category !== category) missing.push('recorded_by');
  const a = toAnswers(x);
  for (const q of requirementQuestions(category)) if (!isValidAnswer(q, a[q.key])) missing.push(q.key);
  return { ok: missing.length === 0, missing };
}

/** Apply the customer's edits from the summary card ({key: text or tapped label}) and rebuild. */
export function applyEdits(category: string, s: unknown, edits: Record<string, unknown>, now = new Date()): { stored: Stored; invalid: string[] } {
  const answers = toAnswers(s as Partial<Stored>);
  const qs = requirementQuestions(category);
  const invalid: string[] = [];
  for (const [k, v] of Object.entries(edits || {})) {
    const q = qs.find((y) => y.key === k);
    const a = q ? parseRequirementAnswer(q, String(v ?? ''), now) : null;
    if (q && a && isValidAnswer(q, a)) answers[k] = a; else invalid.push(k);
  }
  return { stored: toStored(category, answers, now), invalid };
}

/** The customer-facing and edit-ready list the summary card renders, in the customer's language. */
export function forCard(category: string, answers: Answers, lang: Lang) {
  return requirementQuestions(category).map((q) => ({
    key: q.key, label: lang === 'ar' ? q.label_ar : q.label_en, question: questionIn(q, lang),
    options: optionLabels(q, lang), answer: answers[q.key] ? describe(q, answers[q.key], lang) : '',
  }));
}

/** One English line for the supplier invitation. Chip values only: a customer's own note stays in the brief. */
export function supplierLine(s: Partial<Stored> | null | undefined): string {
  const rows = (s && s.display && Array.isArray(s.display.en)) ? s.display.en : [];
  if (!rows.length) return '';
  return ' The customer asks for: ' + rows.map((r) => r.label + ': ' + (r.value.startsWith('Other: ') ? 'their own specification (see the brief)' : r.value)).join('; ') + '.';
}
