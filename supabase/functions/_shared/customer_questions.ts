// customer_questions — WHAT THE CUSTOMER IS ASKED, IN WORDS A HOMEOWNER UNDERSTANDS (15 Nov 2026, sales_engineer).
//
// MEASURED (persona dry run of 15 Nov 2026, the REAL inquiry_intake handler offline; scratchpad handbacks/PERSONAS.md): the
// chat's question cards were the trade packs' spec labels read out loud, "Cooling capacity (BTU/h, TR or kW) per unit",
// "Room use and area or heat-load calc", "Copper pipe length included per unit". A villa owner understood neither of the first
// two; an Arabic-speaking customer saw every card in English on an Arabic chat, asked "شو يعني BTU؟", was asked capacity again
// five turns later with no explanation, and left. packFields (inquiry_trades.ts) made each card `question: <the label>` with no
// plain wording and no Arabic: the category_specs fields carry question_plain_en / question_plain_ar (the 14 Sep SQL), the
// 3,041 pack specs did not.
//
// WHAT LIVES HERE (data, never an if-statement on the customer's words; ruling 890):
//   * CUSTOMER_QUESTION: per spec CODE (scripts/kb/load_trade_spec_checklists.mjs specCode, the key the request's state and
//     the checklist rows use), the question in plain English and Arabic, a short example, a practical alternative where one
//     exists ("send a photo of the label on the outdoor unit" for capacity) and tap options in both languages. Every HVAC
//     split-AC spec, the blocking specs of the other HVAC checklists, and the specs that block most often across all packs.
//   * plainOf(code, label): what packFields puts beside the supplier-facing label: question_plain_en / question_plain_ar and
//     options / options_ar, always ending with "Not sure". A spec not in the table gets the plain English frame of its own
//     label (its parenthesised list of technical units removed) and NO Arabic: an Arabic chat then shows the model's own plain
//     wording for that spec (inquiry_intake plain_question), else the Arabic frame below; never an English card.
//   * GLOSSARY / explainTerms: what a technical word means, in both languages, for the reply that answers "what does BTU mean?"
//     before anything is asked (the model names the words it was asked about in explain_terms; code looks them up).
// Supplier-facing text is untouched: the label stays the spec's `question`, the brief's key and what the supplier reads.
// prevented by: supabase/functions/_shared/customer_questions.test.ts and
//   supabase/functions/inquiry_intake/the_customer_is_asked_in_plain_words.test.ts

import { SPEC_OPTION_AR } from './spec_options_ar.ts';
import { HOME_TRADES } from './customer_questions_home.ts';
import { BUILDING_TRADES } from './customer_questions_building.ts';
import { WORKS_TRADES } from './customer_questions_works.ts';
import { COMMERCIAL_TRADES } from './customer_questions_commercial.ts';
import { SERVICES_TRADES } from './customer_questions_services.ts';
import { INDUSTRIAL_TRADES } from './customer_questions_industrial.ts';

export type Lang = 'en' | 'ar';
type Opt = readonly [en: string, ar: string];
export interface CustomerQuestion { en: string; ar: string; eg_en?: string; eg_ar?: string; alt_en?: string; alt_ar?: string; options?: readonly Opt[] }

/** The "Not sure" every card offers: tapped, it is read as "does not know", and a blocking spec goes to the suppliers to advise. */
export const NOT_SURE: Readonly<Record<Lang, string>> = { en: 'Not sure', ar: 'لست متأكداً' };

const BASE_QUESTION: Readonly<Record<string, CustomerQuestion>> = {
  // ── HVAC: split / ducted split AC (hvac:spec-split-ac), every spec ────────────────────────────────────────────────────
  spec_unit_type: {
    en: 'What kind of AC units are they?', ar: 'ما نوع وحدات التكييف؟',
    eg_en: 'For example: units on the wall, hidden in the ceiling with vents, or square units in the ceiling.',
    eg_ar: 'مثلًا: وحدات على الجدار، أو مخفية في السقف مع فتحات تهوية، أو وحدات مربعة في السقف.',
    options: [['On the wall (split)', 'على الجدار (سبليت)'], ['Hidden in the ceiling (ducted)', 'مخفية في السقف (دكت)'], ['Square, in the ceiling (cassette)', 'مربعة في السقف (كاسيت)'], ['Standing on the floor', 'واقفة على الأرض']],
  },
  spec_cooling_capacity: {
    en: 'How big is each AC unit?', ar: 'ما حجم كل وحدة تكييف؟',
    eg_en: 'It is printed on the sticker on the unit: a number like 12,000, 18,000 or 24,000.',
    eg_ar: 'مكتوب على الملصق الموجود على الوحدة: رقم مثل 12,000 أو 18,000 أو 24,000.',
    alt_en: 'No idea? Send a photo of the sticker on the outdoor unit, or tell us the room sizes and the supplier will work it out.',
    alt_ar: 'لا تعرف؟ أرسل صورة الملصق على الوحدة الخارجية، أو أخبرنا بمساحات الغرف وسيحسبها المورّد.',
    options: [['Small (12,000, 1 ton)', 'صغيرة (12,000، طن واحد)'], ['Medium (18,000, 1.5 ton)', 'متوسطة (18,000، طن ونصف)'], ['Large (24,000, 2 ton)', 'كبيرة (24,000، طنّان)']],
  },
  spec_room_use_and_area_or_heat_load_calc: {
    en: 'Which rooms do the units cool, and roughly how big is each room?', ar: 'ما الغرف التي تبرّدها الوحدات، وما مساحة كل غرفة تقريبًا؟',
    eg_en: 'For example: 3 bedrooms of about 4 x 4 m and a living room of about 5 x 6 m.',
    eg_ar: 'مثلًا: 3 غرف نوم مساحة كل منها نحو 4 × 4 م، وصالة نحو 5 × 6 م.',
  },
  spec_inverter_or_fixed_speed: {
    en: 'Do you want inverter units (they use less electricity but cost a little more) or standard ones?',
    ar: 'هل تريد وحدات إنفرتر (تستهلك كهرباء أقل لكن سعرها أعلى قليلًا) أم وحدات عادية؟',
    options: [['Inverter (saves electricity)', 'إنفرتر (يوفّر الكهرباء)'], ['Standard (cheaper to buy)', 'عادية (أرخص في الشراء)']],
  },
  spec_minimum_esma_star_rating: {
    en: 'How energy-saving should the units be? The star label on the unit shows it: more stars, lower bills.',
    ar: 'ما مستوى توفير الطاقة المطلوب؟ ملصق النجوم على الوحدة يبيّنه: نجوم أكثر تعني فاتورة أقل.',
    options: [['The most efficient', 'الأكثر توفيرًا'], ['Standard is fine', 'العادي يكفي']],
  },
  spec_refrigerant: {
    en: 'Do you have a preference for the cooling gas the units use?', ar: 'هل لديك تفضيل لنوع غاز التبريد في الوحدات؟',
    eg_en: 'Most people leave this to the supplier, who uses the current standard gas.',
    eg_ar: 'معظم العملاء يتركون هذا للمورّد، فيستخدم الغاز المعتمد حاليًا.',
    options: [['No preference', 'لا تفضيل']],
  },
  spec_power_supply: {
    en: 'Is the electricity at the property normal household power, or a heavy-duty supply like big buildings have?', ar: 'هل الكهرباء في العقار منزلية عادية، أم تغذية قوية مثل المباني الكبيرة؟',
    alt_en: 'A photo of the electrical board also works.', alt_ar: 'صورة لوحة الكهرباء تكفي أيضًا.',
    options: [['Normal household power', 'كهرباء منزلية عادية'], ['Heavy-duty (three-phase)', 'تغذية قوية (ثلاثية الطور)']],
  },
  spec_t3_high_ambient_rating: {
    en: 'Should the units be the kind made for very hot summers (they keep cooling above 46°C)?', ar: 'هل تريد وحدات مصممة للصيف الحار جدًا (تواصل التبريد فوق 46 درجة)؟',
    options: [['Yes', 'نعم'], ['No preference', 'لا تفضيل']],
  },
  spec_copper_pipe_length_included_per_unit: {
    en: 'How far is each indoor unit from its outdoor unit?', ar: 'كم تبعد كل وحدة داخلية عن وحدتها الخارجية؟',
    eg_en: 'For example: "the outdoor unit is just behind the wall" or "on the roof, two floors up". The pipes run between them.',
    eg_ar: 'مثلًا: "الوحدة الخارجية خلف الجدار مباشرة" أو "على السطح، فوق بطابقين". الأنابيب تمتد بينهما.',
    alt_en: 'If the pipes are inside the walls, choose Not sure: the supplier will measure on site.', alt_ar: 'إن كانت الأنابيب داخل الجدران فاختر «لست متأكداً» وسيقيسها المورّد في الموقع.',
  },
  spec_drain_routing_condensate_pump: {
    en: 'Is there a drain near each indoor unit for the water the AC drips?', ar: 'هل يوجد تصريف قريب من كل وحدة داخلية لماء التكييف؟',
    options: [['Yes, there is a drain', 'نعم، يوجد تصريف'], ['No drain nearby', 'لا يوجد تصريف قريب']],
  },
  spec_electrical_isolator_and_cabling_scope: {
    en: 'Is there already a power point and switch for each AC unit, or should the supplier do the wiring?', ar: 'هل توجد نقطة كهرباء ومفتاح لكل وحدة، أم يقوم المورّد بالتمديدات الكهربائية؟',
    options: [['Already there', 'موجودة'], ['Supplier to do the wiring', 'المورّد يقوم بالتمديدات']],
  },
  spec_outdoor_unit_mounting: {
    en: 'Where will the outdoor units go?', ar: 'أين ستوضع الوحدات الخارجية؟',
    options: [['On a wall', 'على جدار'], ['On the roof', 'على السطح'], ['On the ground', 'على الأرض']],
  },
  spec_ductwork_and_grilles_scope: {
    en: 'For hidden ceiling units: are the air ducts and vents already there, or should the supplier install them?', ar: 'للوحدات المخفية في السقف: هل مجاري الهواء والفتحات موجودة، أم يركّبها المورّد؟',
    options: [['Already there', 'موجودة'], ['Supplier to install', 'يركّبها المورّد'], ['No hidden units', 'لا توجد وحدات مخفية']],
  },
  spec_false_ceiling_opening_and_making_good: {
    en: 'Will the ceiling need to be opened to fit the units? If so, should the supplier close and repaint it afterwards?', ar: 'هل يلزم فتح السقف لتركيب الوحدات؟ وإن لزم، هل يعيد المورّد إغلاقه ودهانه بعد ذلك؟',
    options: [['Yes, and close it after', 'نعم، مع إعادة الإغلاق'], ['No ceiling work', 'لا أعمال في السقف']],
  },
  spec_old_unit_removal_and_refrigerant_recover: {
    en: 'Should the supplier remove and take away the old units?', ar: 'هل يزيل المورّد الوحدات القديمة ويأخذها؟',
    options: [['Yes, take them away', 'نعم، يأخذها'], ['No old units', 'لا توجد وحدات قديمة']],
  },
  spec_warranty: {
    en: 'How long a warranty do you want, and would you like a yearly maintenance contract?', ar: 'ما مدة الضمان التي تريدها، وهل تريد عقد صيانة سنوي؟',
    eg_en: 'For example: 1 year on parts, 5 years on the compressor (the main part).', eg_ar: 'مثلًا: سنة على القطع، و5 سنوات على الكمبروسر (الجزء الرئيسي).',
    options: [['Standard warranty', 'الضمان المعتاد'], ['Warranty and a yearly maintenance contract', 'ضمان مع عقد صيانة سنوي']],
  },
  spec_number_of_units_per_type: {
    en: 'How many AC units do you need, of each kind?', ar: 'كم وحدة تكييف تحتاج، من كل نوع؟',
    eg_en: 'For example: 4 wall units and 1 hidden ceiling unit.', eg_ar: 'مثلًا: 4 وحدات جدارية ووحدة واحدة مخفية في السقف.',
  },
  spec_brand_preference_or_equivalent_tier: {
    en: 'Do you prefer a brand, or a price level?', ar: 'هل تفضّل ماركة معيّنة، أو مستوى سعر؟',
    options: [['Premium brand', 'ماركة ممتازة'], ['Mid-range', 'متوسطة'], ['Best value', 'الأفضل قيمة'], ['No preference', 'لا تفضيل']],
  },
  // ── HVAC: the blocking specs of the other checklists (VRF, chiller, AHU, ductwork, maintenance contract) ──────────────────
  spec_indoor_unit_schedule: {
    en: 'How many indoor units do you need, and in which rooms?', ar: 'كم وحدة داخلية تحتاج، وفي أي غرف؟',
    alt_en: 'A drawing or a list from your consultant also works.', alt_ar: 'المخطط أو القائمة من الاستشاري تكفي أيضًا.',
  },
  spec_heat_pump_vs_heat_recovery: {
    en: 'Do different rooms need to heat and cool at the same time, or does the whole system cool together?', ar: 'هل تحتاج غرف مختلفة إلى التدفئة والتبريد في الوقت نفسه، أم يبرّد النظام كله معًا؟',
    options: [['All rooms cool together', 'كل الغرف تبرّد معًا'], ['Some heat while others cool', 'بعضها يدفّئ وبعضها يبرّد']],
  },
  spec_capacity_at_uae_design_ambient: {
    en: 'Do you have the cooling size from your consultant or drawings?', ar: 'هل لديك حجم التبريد المطلوب من الاستشاري أو المخططات؟',
    alt_en: 'If not, tell us the building size and use and the supplier will work it out.', alt_ar: 'إن لم يكن لديك، أخبرنا بمساحة المبنى واستخدامه وسيحسبه المورّد.',
  },
  spec_capacity: {
    en: 'What size or capacity do you need?', ar: 'ما الحجم أو السعة المطلوبة؟',
    alt_en: 'If you do not know, describe what it is for and the supplier will size it.', alt_ar: 'إن لم تكن تعرف، صف استخدامه وسيحدد المورّد الحجم المناسب.',
  },
  spec_chilled_water_entering_leaving_temp: {
    en: 'Do you have the water temperatures the chiller must work at, from your consultant or drawings?', ar: 'هل لديك درجات حرارة الماء المطلوبة للمبرّد من الاستشاري أو المخططات؟',
  },
  spec_design_ambient: {
    en: 'What is the hottest outdoor temperature the system must handle? In the UAE this is usually 46 to 50°C.', ar: 'ما أعلى حرارة خارجية يجب أن يتحمّلها النظام؟ في الإمارات عادةً من 46 إلى 50 درجة.',
  },
  spec_full_load_efficiency: {
    en: 'Is there a minimum energy efficiency the chiller must meet (from your consultant or the authority)?', ar: 'هل يوجد حد أدنى لكفاءة الطاقة يجب أن يحققه المبرّد (من الاستشاري أو الجهة المختصة)؟',
  },
  spec_number_of_chillers: { en: 'How many chillers do you need?', ar: 'كم مبرّدًا (تشيلر) تحتاج؟' },
  spec_airflow_and_external_static_pressure: {
    en: 'Do you have the air volume the unit must move, from your consultant or drawings?', ar: 'هل لديك كمية الهواء التي يجب أن تحرّكها الوحدة، من الاستشاري أو المخططات؟',
  },
  spec_outdoor_return_air: {
    en: 'Should the unit bring in fresh outside air, reuse the indoor air, or a mix of both?', ar: 'هل تُدخل الوحدة هواءً خارجيًا نقيًا، أم تعيد تدوير الهواء الداخلي، أم مزيجًا منهما؟',
    options: [['Fresh outside air', 'هواء خارجي نقي'], ['Indoor air', 'هواء داخلي'], ['A mix', 'مزيج']],
  },
  spec_on_coil_and_off_coil_conditions: {
    en: 'Do you have the air temperatures the unit must deliver, from your consultant or drawings?', ar: 'هل لديك درجات حرارة الهواء المطلوبة من الوحدة، من الاستشاري أو المخططات؟',
  },
  spec_duct_routes_sizes_or_drawings: {
    en: 'Do you have drawings showing where the air ducts go?', ar: 'هل لديك مخططات تبيّن مسار مجاري الهواء؟',
    alt_en: 'If not, describe the rooms and the supplier will visit to design it.', alt_ar: 'إن لم تكن لديك، صف الغرف وسيزور المورّد الموقع لتصميمها.',
  },
  spec_material: {
    en: 'Which material do you want?', ar: 'ما المادة المطلوبة؟',
    alt_en: 'If you are not sure, the supplier will propose the usual one.', alt_ar: 'إن لم تكن متأكداً، سيقترح المورّد المادة المعتادة.',
  },
  spec_asset_list_with_type_capacity_age: {
    en: 'Which AC units should the contract cover: how many, what kind, and roughly how old?', ar: 'ما وحدات التكييف التي يشملها العقد: كم عددها، وما نوعها، وكم عمرها تقريبًا؟',
    eg_en: 'For example: 6 wall units, about 5 years old.', eg_ar: 'مثلًا: 6 وحدات جدارية، عمرها نحو 5 سنوات.',
    alt_en: 'Photos of the units and their stickers also work.', alt_ar: 'صور الوحدات وملصقاتها تكفي أيضًا.',
  },
  spec_contract_type: {
    en: 'Should the contract cover only regular servicing, or repairs and parts as well?', ar: 'هل يشمل العقد الصيانة الدورية فقط، أم الإصلاحات وقطع الغيار أيضًا؟',
    options: [['Servicing only', 'صيانة دورية فقط'], ['Servicing and repairs', 'صيانة وإصلاحات'], ['Servicing, repairs and parts', 'صيانة وإصلاحات وقطع غيار']],
  },
  spec_visit_frequency: {
    en: 'How often should the technician visit?', ar: 'كم مرة يزور الفني الموقع؟',
    options: [['Every month', 'كل شهر'], ['Every 3 months', 'كل 3 أشهر'], ['Twice a year', 'مرتين في السنة']],
  },
  spec_site_locations_and_emirates: {
    en: 'Where are the properties, and in which emirate?', ar: 'أين تقع العقارات، وفي أي إمارة؟',
    eg_en: 'For example: 2 villas in Al Barsha, Dubai.', eg_ar: 'مثلًا: فيلتان في البرشاء، دبي.',
  },
  // ── the specs that block most often across all packs (measured 15 Nov 2026: 1,572 blocking specs, 1,238 distinct) ───────
  spec_delivery_terms_and_location: {
    en: 'Where should it be delivered, and should the price include delivery?', ar: 'إلى أين يُسلَّم الطلب، وهل يشمل السعر التوصيل؟',
    eg_en: 'For example: delivered to our warehouse in Jebel Ali, Dubai.', eg_ar: 'مثلًا: التوصيل إلى مستودعنا في جبل علي، دبي.',
    options: [['Delivered to my address', 'توصيل إلى عنواني'], ['I will collect', 'سأستلمه بنفسي']],
  },
  spec_quantity_and_unit_of_measure: {
    en: 'How much do you need?', ar: 'ما الكمية التي تحتاجها؟',
    eg_en: 'For example: 500 pieces, 20 boxes, 120 m² or 3 tonnes.', eg_ar: 'مثلًا: 500 قطعة، أو 20 كرتونة، أو 120 م²، أو 3 أطنان.',
  },
  spec_quantity: { en: 'How many do you need?', ar: 'كم تحتاج من العدد؟', eg_en: 'For example: 10 pieces.', eg_ar: 'مثلًا: 10 قطع.' },
  spec_quantity_per_item: { en: 'How many of each item do you need?', ar: 'كم تحتاج من كل صنف؟' },
  spec_quantity_of_units: { en: 'How many units do you need?', ar: 'كم وحدة تحتاج؟' },
  spec_quantity_and_unit: { en: 'How much do you need?', ar: 'ما الكمية التي تحتاجها؟', eg_en: 'For example: 50 pieces or 100 metres.', eg_ar: 'مثلًا: 50 قطعة أو 100 متر.' },
  spec_quantity_per_type: { en: 'How many of each kind do you need?', ar: 'كم تحتاج من كل نوع؟' },
  spec_dimensions: {
    en: 'What size is it?', ar: 'ما المقاسات؟',
    eg_en: 'For example: 2 m wide and 1.2 m high.', eg_ar: 'مثلًا: عرض 2 م وارتفاع 1.2 م.',
    alt_en: 'A photo or a rough sketch with measurements also works.', alt_ar: 'صورة أو رسم تقريبي بالمقاسات يكفي أيضًا.',
  },
  spec_delivery_and_installation_scope: {
    en: 'Should the supplier only deliver it, or also install it?', ar: 'هل يكتفي المورّد بالتوريد، أم يقوم بالتركيب أيضًا؟',
    options: [['Deliver only', 'توريد فقط'], ['Deliver and install', 'توريد وتركيب']],
  },
  spec_installation_or_commissioning_scope: {
    en: 'Should the supplier install it and set it up ready to use?', ar: 'هل يقوم المورّد بالتركيب والتشغيل حتى يصبح جاهزًا للاستخدام؟',
    options: [['Yes, install and set up', 'نعم، تركيب وتشغيل'], ['Delivery only', 'توريد فقط']],
  },
  spec_supply_only_or_supply_and_install: {
    en: 'Should the supplier only supply it, or supply and install it?', ar: 'هل يكتفي المورّد بالتوريد، أم يورّد ويركّب؟',
    options: [['Supply only', 'توريد فقط'], ['Supply and install', 'توريد وتركيب']],
  },
  spec_brand: {
    en: 'Do you want a particular brand or product?', ar: 'هل تريد ماركة أو منتجًا معيّنًا؟',
    alt_en: 'A photo of the product or its label also works.', alt_ar: 'صورة المنتج أو ملصقه تكفي أيضًا.',
    options: [['No preference', 'لا تفضيل']],
  },
  spec_brand_and_model: {
    en: 'Which brand and model do you want?', ar: 'ما الماركة والموديل المطلوبان؟',
    alt_en: 'A photo of the label also works.', alt_ar: 'صورة الملصق تكفي أيضًا.', options: [['No preference', 'لا تفضيل']],
  },
  spec_make_and_model: {
    en: 'Which make and model is it?', ar: 'ما الماركة والموديل؟',
    alt_en: 'A photo of the label on it also works.', alt_ar: 'صورة الملصق الموجود عليه تكفي أيضًا.',
  },
  spec_contract_duration: {
    en: 'For how long do you need the service?', ar: 'ما المدة التي تحتاج فيها الخدمة؟',
    options: [['One-off', 'مرة واحدة'], ['3 months', '3 أشهر'], ['1 year', 'سنة']],
  },
  spec_contract_duration_and_pricing_basis: {
    en: 'For how long do you need the service, and how would you like to pay: a fixed monthly amount, or per job?', ar: 'ما مدة الخدمة، وكيف تفضّل الدفع: مبلغ شهري ثابت أم حسب كل عمل؟',
    options: [['Fixed monthly', 'مبلغ شهري ثابت'], ['Per job', 'حسب كل عمل']],
  },
  spec_contract_term: { en: 'For how long do you need the contract?', ar: 'ما مدة العقد المطلوبة؟', options: [['1 year', 'سنة'], ['2 years', 'سنتان']] },
  spec_pricing_basis: {
    en: 'How would you like the price: one total, a monthly amount, or per unit?', ar: 'كيف تفضّل السعر: مبلغًا إجماليًا، أم شهريًا، أم لكل وحدة؟',
    options: [['One total', 'مبلغ إجمالي'], ['Monthly', 'شهري'], ['Per unit', 'لكل وحدة']],
  },
  spec_size: {
    en: 'What size do you need?', ar: 'ما المقاس المطلوب؟',
    alt_en: 'A photo of the existing one with its label also works.', alt_ar: 'صورة القطعة الحالية مع ملصقها تكفي أيضًا.',
  },
  spec_pack_size: { en: 'What pack size do you want?', ar: 'ما حجم العبوة المطلوب؟', eg_en: 'For example: boxes of 100.', eg_ar: 'مثلًا: كراتين في كل منها 100.' },
  spec_pack_size_and_quantity: { en: 'What pack size, and how many packs?', ar: 'ما حجم العبوة، وكم عبوة؟', eg_en: 'For example: 20 boxes of 100.', eg_ar: 'مثلًا: 20 كرتونة في كل منها 100.' },
  spec_indoor_or_outdoor: { en: 'Will it be used indoors or outdoors?', ar: 'هل سيُستخدم داخل المبنى أم خارجه؟', options: [['Indoors', 'داخلي'], ['Outdoors', 'خارجي']] },
  spec_fault_description: {
    en: 'What is wrong with it? Tell us what you see or hear.', ar: 'ما المشكلة؟ أخبرنا بما تراه أو تسمعه.',
    alt_en: 'A photo or a short video also helps.', alt_ar: 'صورة أو فيديو قصير يساعد أيضًا.',
  },
  spec_layout_drawing: {
    en: 'Do you have a drawing or a plan of the space?', ar: 'هل لديك مخطط أو رسم للمكان؟',
    alt_en: 'A phone photo of a hand sketch with measurements also works.', alt_ar: 'صورة لرسم يدوي بالمقاسات تكفي أيضًا.',
  },
  spec_soil_report: {
    en: 'Do you have a soil test report for the plot?', ar: 'هل لديك تقرير فحص التربة للأرض؟',
    options: [['Yes, I can send it', 'نعم، سأرسله'], ['No, the supplier should arrange it', 'لا، يرتّبه المورّد']],
  },
  spec_service_location_and_emirate: { en: 'Where is the service needed, and in which emirate?', ar: 'أين تحتاج الخدمة، وفي أي إمارة؟' },
  spec_site_location: { en: 'Where is the site, which floor, and how is it reached?', ar: 'أين الموقع، وفي أي طابق، وكيف يُوصل إليه؟' },
  spec_delivery_terms: {
    en: 'Should the price include delivery to you?', ar: 'هل يشمل السعر التوصيل إليك؟',
    options: [['Yes, delivered', 'نعم، مع التوصيل'], ['No, I will collect', 'لا، سأستلمه بنفسي']],
  },
  spec_scope_of_services: { en: 'What exactly do you need done?', ar: 'ما المطلوب إنجازه تحديدًا؟' },
  spec_weight_and_dimensions: { en: 'Roughly how heavy and how big is it?', ar: 'كم وزنه وحجمه تقريبًا؟' },
  spec_origin_and_destination: { en: 'From where to where?', ar: 'من أين وإلى أين؟', eg_en: 'For example: from Jebel Ali to Abu Dhabi.', eg_ar: 'مثلًا: من جبل علي إلى أبوظبي.' },
  // ── the request's universal fields (inquiry_trades.ts UNIVERSAL_QUESTION), asked once for the whole request ─────────────
  location: {
    en: 'Where is the job, and in which emirate?', ar: 'أين موقع العمل، وفي أي إمارة؟',
    eg_en: 'For example: a villa in Al Barsha, Dubai.', eg_ar: 'مثلًا: فيلا في البرشاء، دبي.',
  },
  payment_terms: {
    en: 'How would you like to pay?', ar: 'كيف تفضّل الدفع؟',
    options: [['Part in advance, the rest on completion', 'جزء مقدّمًا والباقي عند الإنجاز'], ['All on completion', 'كامل المبلغ عند الإنجاز'], ['30 days after the invoice', 'بعد 30 يومًا من الفاتورة']],
  },
};

/** Every spec's plain wording: the base table above, then the trade tables (one file per group of trades). */
export const CUSTOMER_QUESTION: Readonly<Record<string, CustomerQuestion>> = { ...BASE_QUESTION, ...HOME_TRADES, ...BUILDING_TRADES, ...WORKS_TRADES, ...COMMERCIAL_TRADES, ...SERVICES_TRADES, ...INDUSTRIAL_TRADES };

/** The label as a plain English question when the table has no entry: its parenthesised list of technical units dropped. */
export function plainFrame(label: string): string {
  const s = String(label ?? '').replace(/\s*\([^)]*\)/g, '').replace(/\s+/g, ' ').trim();
  if (!s) return '';
  return `${s.charAt(0).toUpperCase() + s.slice(1)}? If you are not sure, tap "${NOT_SURE.en}" and the supplier will advise.`;
}
/** The Arabic card for a spec with no Arabic of its own and no plain wording from the model this turn: an Arabic sentence
 *  that asks for the detail without naming it in English, with "Not sure" (the reply names it in Arabic when it is written). */
export const ARABIC_FRAME = 'يحتاج المورّد إلى تفصيلة أخرى عن هذا العمل ليعطيك سعرًا دقيقًا: صِفها بكلماتك، أو أرسل صورة. إن لم تكن متأكداً فاختر «لست متأكداً» وسيقترح المورّد.';

const join = (...xs: Array<string | undefined>) => xs.filter((x) => x && x.trim()).join(' ');
/** What packFields puts beside a spec's supplier-facing label: the plain questions and the tap options in both languages,
 *  each list ending with "Not sure". `question_plain_ar` is absent for a spec the table does not hold (see plainOf's callers). */
export function plainOf(code: string, label: string): { question_plain_en: string; question_plain_ar?: string; options: string[]; options_ar: string[]; plain: boolean } {
  const c = CUSTOMER_QUESTION[String(code)];
  if (!c) return { question_plain_en: plainFrame(label), options: [NOT_SURE.en], options_ar: [NOT_SURE.ar], plain: false };
  const opts = c.options ?? [];
  return {
    question_plain_en: join(c.en, c.eg_en, c.alt_en), question_plain_ar: join(c.ar, c.eg_ar, c.alt_ar),
    options: [...opts.map((o) => o[0]), NOT_SURE.en], options_ar: [...opts.map((o) => o[1]), NOT_SURE.ar], plain: true,
  };
}

// ── WHAT A WORD MEANS ───────────────────────────────────────────────────────────────────────────────────────────────────
// The words our questions, the packs and suppliers use that a homeowner may not know. `terms` are the spellings the model may
// name in explain_terms (compared lower-cased, after code removes quotes and punctuation): model output, never the customer's text.
export const GLOSSARY: ReadonlyArray<{ terms: readonly string[]; en: string; ar: string }> = [
  { terms: ['btu', 'btu/h', 'btus', 'بي تي يو'], en: 'BTU measures how much cooling an AC unit gives: a bigger number cools a bigger room. A normal bedroom needs about 12,000 to 18,000 BTU.', ar: 'BTU وحدة تقيس قوة التبريد في المكيف: الرقم الأكبر يبرّد غرفة أكبر. غرفة النوم العادية تحتاج نحو 12,000 إلى 18,000 BTU.' },
  { terms: ['tr', 'ton', 'tons', 'tonnage', 'طن'], en: 'A "ton" (TR) is another way to say how much cooling an AC unit gives: 1 ton is 12,000 BTU, enough for a normal bedroom.', ar: '«الطن» طريقة أخرى للتعبير عن قوة تبريد المكيف: الطن الواحد يساوي 12,000 BTU ويكفي غرفة نوم عادية.' },
  { terms: ['kw', 'kilowatt', 'كيلوواط'], en: 'kW here is the cooling power of the unit; 3.5 kW is about one ton, enough for a normal bedroom.', ar: 'الكيلوواط هنا هو قوة تبريد الوحدة؛ 3.5 كيلوواط تعادل طنًا تقريبًا وتكفي غرفة نوم عادية.' },
  { terms: ['capacity', 'cooling capacity', 'سعة', 'السعة'], en: 'Capacity is how much cooling a unit gives. It is printed on the sticker on the unit, in BTU or tons.', ar: 'السعة هي قوة التبريد في الوحدة، ومكتوبة على الملصق بوحدة BTU أو بالطن.' },
  { terms: ['heat-load', 'heat load', 'heat-load calc', 'heat load calculation', 'حمل حراري', 'الحمل الحراري'], en: 'A heat-load calculation works out how much cooling each room needs from its size, sun and use. You do not need one: tell us the room sizes and the supplier works it out.', ar: 'حساب الحمل الحراري يحدد كمية التبريد التي تحتاجها كل غرفة حسب مساحتها والشمس واستخدامها. لست بحاجة إليه: أخبرنا بمساحات الغرف وسيحسبه المورّد.' },
  { terms: ['inverter', 'انفرتر', 'إنفرتر'], en: 'An inverter AC changes its speed instead of switching on and off, so it uses less electricity. It costs a little more to buy.', ar: 'مكيف الإنفرتر يغيّر سرعته بدل أن يعمل ويتوقف، فيستهلك كهرباء أقل، لكن سعره أعلى قليلًا.' },
  { terms: ['fixed speed', 'fixed-speed', 'non-inverter'], en: 'A fixed-speed AC switches fully on and off. It is cheaper to buy but uses more electricity than an inverter.', ar: 'المكيف ثابت السرعة يعمل ويتوقف بالكامل؛ أرخص في الشراء لكنه يستهلك كهرباء أكثر من الإنفرتر.' },
  { terms: ['refrigerant', 'r32', 'r410a', 'r22', 'gas', 'غاز', 'فريون'], en: 'Refrigerant is the cooling gas inside the AC. Most new units use R32; you do not need to choose it.', ar: 'غاز التبريد هو الغاز داخل المكيف. معظم الوحدات الجديدة تستخدم R32، ولا يلزمك اختياره.' },
  { terms: ['esma', 'star rating', 'stars'], en: 'The star label shows how much electricity the AC uses: more stars means lower bills. Every unit sold in the UAE must carry it.', ar: 'ملصق النجوم يبيّن استهلاك المكيف للكهرباء: نجوم أكثر تعني فاتورة أقل. كل وحدة تباع في الإمارات تحمله.' },
  { terms: ['t3', 't3 rating', 'high ambient', 'high-ambient'], en: 'T3 means the AC is built for very hot summers and keeps cooling above 46°C.', ar: 'T3 تعني أن المكيف مصمم للصيف الحار جدًا ويواصل التبريد فوق 46 درجة.' },
  { terms: ['phase', 'single-phase', 'single phase', 'three-phase', 'three phase', '3 phase', 'طور', 'ثلاثي'], en: 'Phase is the kind of electricity supply. Most homes have normal single-phase power; big units may need three-phase. A photo of the electrical board tells the supplier.', ar: 'الطور هو نوع التغذية الكهربائية. معظم البيوت فيها كهرباء أحادية عادية، والوحدات الكبيرة قد تحتاج ثلاثية. صورة لوحة الكهرباء تكفي المورّد.' },
  { terms: ['isolator', 'isolators', 'عازل', 'قاطع'], en: 'An isolator is a switch next to the AC that cuts its power for safe servicing.', ar: 'القاطع مفتاح بجانب المكيف يفصل الكهرباء عنه للصيانة بأمان.' },
  { terms: ['condensate', 'condensate pump', 'drain', 'تصريف'], en: 'An AC drips water while it cools; it runs to a drain through a small pipe, or a small pump pushes it there.', ar: 'المكيف يقطر ماءً أثناء التبريد، ويُصرَّف بأنبوب صغير أو بمضخة صغيرة.' },
  { terms: ['copper pipe', 'copper pipes', 'pipes', 'pipe length', 'مواسير', 'أنابيب', 'النحاس'], en: 'Copper pipes carry the cooling gas between the indoor and the outdoor unit. Suppliers include a few metres; a longer run costs extra.', ar: 'أنابيب النحاس تنقل غاز التبريد بين الوحدة الداخلية والخارجية. المورّد يشمل بضعة أمتار، والمسافة الأطول بتكلفة إضافية.' },
  { terms: ['ducted', 'ducts', 'duct', 'ductwork', 'دكت', 'مجاري'], en: 'A ducted AC is hidden in the ceiling and blows air through ducts to vents in each room.', ar: 'المكيف المخفي (الدكت) يوضع داخل السقف ويدفع الهواء عبر مجارٍ إلى فتحات في كل غرفة.' },
  { terms: ['cassette', 'كاسيت'], en: 'A cassette is a square AC unit fitted into the ceiling that blows air in four directions.', ar: 'الكاسيت وحدة تكييف مربعة تُركّب في السقف وتدفع الهواء في أربعة اتجاهات.' },
  { terms: ['split', 'wall split', 'سبليت'], en: 'A split AC has an indoor unit on the wall and an outdoor unit outside, joined by pipes.', ar: 'المكيف السبليت له وحدة داخلية على الجدار ووحدة خارجية، يربط بينهما أنابيب.' },
  { terms: ['vrf', 'vrv'], en: 'VRF is a central system where one outdoor unit serves many indoor units, used in big villas and offices.', ar: 'VRF نظام مركزي تخدم فيه وحدة خارجية واحدة وحدات داخلية كثيرة، ويستخدم في الفلل الكبيرة والمكاتب.' },
  { terms: ['amc', 'maintenance contract', 'عقد صيانة'], en: 'An AMC is a yearly maintenance contract: the supplier services the units on a schedule for a fixed price.', ar: 'عقد الصيانة السنوي يعني أن المورّد يصون الوحدات في مواعيد محددة بسعر ثابت.' },
  { terms: ['compressor', 'كمبروسر', 'ضاغط'], en: 'The compressor is the main part of the AC, in the outdoor unit; it usually has a longer warranty.', ar: 'الكمبروسر هو الجزء الرئيسي في المكيف ويوجد في الوحدة الخارجية، وعادةً له ضمان أطول.' },
  { terms: ['mep'], en: 'MEP means the building\'s mechanical, electrical and plumbing works, and the drawings for them.', ar: 'MEP تعني أعمال المبنى الميكانيكية والكهربائية والسباكة ومخططاتها.' },
  { terms: ['commissioning', 'تشغيل'], en: 'Commissioning is when the supplier tests everything after installing it, so it works properly from day one.', ar: 'التشغيل والاختبار يعني أن المورّد يفحص كل شيء بعد التركيب ليعمل جيدًا من اليوم الأول.' },
  { terms: ['false ceiling', 'gypsum ceiling', 'سقف مستعار', 'جبس'], en: 'A false ceiling is the inner ceiling (usually gypsum board) hung below the real one; hidden AC units sit above it.', ar: 'السقف المستعار هو السقف الداخلي (عادة من الجبس) المعلّق تحت السقف الأصلي، والوحدات المخفية تكون فوقه.' },
];
const norm = (s: string) => String(s ?? '').toLowerCase().replace(/[«»"'“”‘’؟?!.,:;()]/g, ' ').replace(/\s+/g, ' ').trim();
/** The explanations of the words the model says the customer asked about, in the customer's language, each once. '' when none
 *  is in the glossary (the model's own answer_to_question then stands alone). */
export function explainTerms(terms: unknown, lang: Lang): string {
  if (!Array.isArray(terms)) return '';
  const out: string[] = [];
  for (const t of terms.slice(0, 4)) {
    const n = norm(String(t ?? ''));
    if (!n) continue;
    const g = GLOSSARY.find((x) => x.terms.some((w) => norm(w) === n));
    const text = g ? (lang === 'ar' ? g.ar : g.en) : '';
    if (text && !out.includes(text)) out.push(text);
  }
  return out.join(' ');
}

// ── A CATEGORY QUESTION'S OPTIONS ON AN ARABIC CHAT ─────────────────────────────────────────────────────────────────────
// category_specs fields carry question_plain_ar but their tap options only in English (SELECT, 15 Nov 2026: hvac has no
// options_ar). The Arabic label of every category option already had ONE home, the portal spec helper's table (666 options);
// it now lives in _shared/spec_options_ar.ts SPEC_OPTION_AR, read by the portal and by this card alike. An option with no Arabic label
// there (or one with no Arabic letter in it, "VRF / VRV") is not shown on an Arabic chat (the customer types instead); "Not
// sure" always is. The tapped Arabic label is read back to its English option by code (slots.ts tappedHeldAnswer).
const ARABIC_LETTER = /[\u0600-\u06FF]/;
const SPEC_OPTION_AR_LOWER = new Map(Object.entries(SPEC_OPTION_AR).map(([k, v]) => [k.trim().toLowerCase(), v]));
/** The Arabic label of an English option, or null when there is none. */
export function optionAr(o: string): string | null {
  const k = String(o ?? '').trim();
  const v = SPEC_OPTION_AR[k] ?? SPEC_OPTION_AR_LOWER.get(k.toLowerCase()) ?? null;
  return v && ARABIC_LETTER.test(v) ? v : null;
}
/** Two Arabic labels are the same words whatever their diacritics ("متأكداً" and "متأكدًا"). */
export const sameArabic = (a: string, b: string): boolean => {
  const n = (x: string) => String(x ?? '').replace(/[\u064B-\u0652\u0640]/g, '').replace(/\s+/g, ' ').trim();
  return n(a) === n(b);
};
export const saysNotSureAr = (a: string): boolean => {
  const n = (x: string) => String(x ?? '').replace(/[\u064B-\u0652\u0640]/g, '');
  return n(a).includes(n(NOT_SURE.ar));
};
