// scripts/e2e/journey_proof/personas/customers.mjs — THE CUSTOMERS WHO PLAY A JOURNEY, as hidden truth sheets. Seat:
// customer_support. Founder, 15 Nov 2026: the scripted customer of journey A answered "Inverter units, please." when he was
// asked room sizes, and already knew tonnage, refrigerant, brands and warranty terms. These are people instead: each one
// knows some things, does NOT know others (and says so in their own words), has the files a real person has on a phone,
// and leaves when the platform is too slow or asks the same thing again (abandon.mjs).
//
// A TRUTH SHEET (one persona)
//   key, label, short           who this is (always ZZ DEMO; nobody here is a real person)
//   lang                        the language the chat is opened in ('en' | 'ar'); voice says how they write
//   opener, opener_topics       the first thing they type, and which facts it states (the dry run's reader reads those)
//   facts[]                     { id, about, knows, says, re, keys, reads?, req?, file? }
//      about   what the fact is about, in plain words (the model player matches the platform's question to it)
//      knows   true: they know it and say `says` in their own way; false: they do not know (`says` is how they put that)
//      re/keys how the DETERMINISTIC stub player (dry run, unit tests) matches a question: its key first, then its words
//      reads   what a faithful reader records when this is said: { spec key: value } (dry run stand-in reader only)
//      req     the four questions (installation, warranty, required_by, material.*) as a faithful reader files them
//      file    a file they would send instead of an answer (e.g. a phone photo of the unit's nameplate)
//   files[]                     { id, kind, caption, reads } — what is on their phone; `reads` is what a reader gets from it
//   jargon                      words they do not understand: a question built on one gets "what does that mean?"
//   patience                    abandon.mjs: { slow_s, max_slow, abandon_on_repeat, max_questions }
//   identity                    the identifying details they give, for the anonymity check
//   job                         what the live journey needs to make the run (title, trade, the lines a supplier prices)

const HVAC_LINES = (n, tr) => [
  { description: `Inspection and repair or replacement of ${n} wall split units`, qty: n, unit: 'nos' },
  { description: `Wall split unit ${tr}, inverter, supply and install (if replacement is needed)`, qty: n, unit: 'nos' },
  { description: 'Removal and disposal of old units', qty: n, unit: 'nos' },
  { description: 'Testing and commissioning', qty: 1, unit: 'lot' },
];

export const CUSTOMERS = {
  // ── 1. a Dubai villa owner who knows little ─────────────────────────────────────────────────────────────────────────
  villa_owner: {
    key: 'villa_owner', label: 'ZZ DEMO villa owner', short: 'a villa owner who knows little about AC',
    lang: 'en', voice: 'friendly and vague, not technical at all, short messages, sometimes a typo, never uses trade words',
    opener: 'Hi, my AC is not cooling properly. 4 units in the villa. Not sure of the size sorry',
    opener_topics: ['units', 'problem'],
    facts: [
      { id: 'units', about: 'how many AC units and what kind they are', knows: true, says: 'Four. The normal ones on the wall, in the bedrooms and the living room.',
        re: /how many|what (kind|type)|type of (ac|air)|kind of (ac|air)|wall split|ducted|cassette|unit type/i, keys: ['system_type', 'spec_unit_type', 'spec_number_of_units_per_type'],
        reads: { system_type: 'Wall/floor split', spec_unit_type: 'Wall split', spec_number_of_units_per_type: '4 wall splits' } },
      { id: 'problem', about: 'what is wrong with the AC', knows: true, says: 'They run but the air is not cold, mostly in the afternoon. Two are worse than the others.',
        re: /problem|wrong|issue|symptom|not cool/i, keys: [] },
      { id: 'repair_or_replace', about: 'whether this is a repair/service, a replacement or a new installation', knows: true, says: 'Honestly not sure. If they can be fixed, fix them, if not replace them. They are about 8 years old.',
        re: /new install|replac|repair|service|extension|adding more/i, keys: ['new_or_replace'], reads: { new_or_replace: 'Service / repair / maintenance; Replacement of existing (if repair is not worth it)' } },
      { id: 'location', about: 'where the property is (emirate, area) and what kind of property', knows: true, says: 'Villa 15, Al Barsha 2, Dubai.',
        re: /emirate|where|location|address|which area|property/i, keys: ['location', 'spec_site_location_and_emirate'], reads: { location: 'A villa in Dubai', spec_site_location_and_emirate: 'Dubai' } },
      { id: 'capacity', about: 'the cooling capacity / size of each unit (tons, TR, BTU, kW)', knows: false, says: 'No idea sorry. I can send a photo of the sticker on the outside unit if that helps?',
        re: /capacity|btu|\btr\b|\btons?\b|\bkw\b|size of (the |each )?unit/i, keys: ['spec_cooling_capacity'], file: 'nameplate_photo' },
      { id: 'rooms', about: 'which rooms the units cool and roughly how big the rooms are', knows: true, says: '3 bedrooms and the living room. Living room is big, maybe 5 by 6 metres? Bedrooms are normal size.',
        re: /room|m2|m²|square|space|how big|size of (the |each )?(room|space)/i, keys: ['application_area', 'spec_room_use_and_area_or_heat_load_calc'],
        reads: { application_area: 'Villa: 3 bedrooms and a living room of about 5 x 6 m', spec_room_use_and_area_or_heat_load_calc: '3 bedrooms (normal size), living room about 30 m2' } },
      { id: 'outdoor', about: 'where the outdoor units are and how to reach them', knows: true, says: 'The outside units are on the roof. There are stairs to the roof.',
        re: /outdoor|roof|condenser|floor level|outside unit|access/i, keys: ['spec_outdoor_unit_mounting'], reads: { spec_outdoor_unit_mounting: 'Roof, reached by stairs' } },
      { id: 'inverter', about: 'inverter or fixed-speed units', knows: false, says: "I don't know what that means. Whatever is cheaper to run?",
        re: /inverter|fixed.?speed/i, keys: ['spec_inverter_or_fixed_speed'] },
      { id: 'pipes', about: 'copper pipe length or reuse of the existing pipes', knows: false, says: 'No idea, the pipes are inside the walls.',
        re: /copper|pipe/i, keys: ['spec_copper_pipe_length_included_per_unit'] },
      { id: 'power', about: 'the electrical supply (single or three phase), isolators, cabling', knows: false, says: 'Not sure about that, sorry.',
        re: /electric|power|phase|voltage|isolator|cabl/i, keys: ['electrical_supply', 'spec_power_supply', 'spec_electrical_isolator_and_cabling_scope'] },
      { id: 'scope', about: 'whether the supplier should supply only or also install', knows: true, says: "They should do everything, I can't install anything myself.",
        re: /install|supply only|deliver|scope|turnkey|everything/i, keys: ['scope', 'installation'], reads: { scope: 'Supply and install' }, req: { installation: 'yes' } },
      { id: 'brand', about: 'brand or quality preference', knows: true, says: 'No preference. The ones we have are Gree I think. Something reliable.',
        re: /brand|make|daikin|gree|tier|premium|economy/i, keys: ['brand_tier', 'material.brand', 'spec_brand_preference_or_equivalent_tier'],
        reads: { brand_tier: 'Best value - recommend' }, req: { 'material.brand': { other: 'No preference; the current units are Gree' } } },
      { id: 'timeline', about: 'when the work is needed', knows: true, says: "As soon as possible please, it's getting hot.",
        re: /when|timeline|date|deadline|how soon|urgent|start/i, keys: ['timeline', 'required_by'], reads: { timeline: 'Within 2 weeks' }, req: { required_by: { date: '2026-11-29', text: 'as soon as possible (within two weeks)' } } },
      { id: 'warranty', about: 'the warranty wanted', knows: true, says: 'Whatever is normal. At least a year?',
        re: /warrant|guarantee/i, keys: ['warranty', 'spec_warranty'], req: { warranty: { months: 12 } } },
      { id: 'removal', about: 'removal of the old units', knows: true, says: 'Yes please take the old ones away if you replace them.',
        re: /remov|dispos|old unit|take (them )?away/i, keys: ['spec_old_unit_removal_and_refrigerant_recover'], reads: { spec_old_unit_removal_and_refrigerant_recover: 'Remove and take away the old units if replaced' } },
      { id: 'ducting', about: 'ducting', knows: true, says: 'There are no ducts, just the wall units.', re: /duct/i, keys: ['material.ducting'], req: { 'material.ducting': 'not_needed' } },
      { id: 'budget', about: 'the budget', knows: false, says: "I don't know what it should cost, that's why I'm asking.", re: /budget|price|cost|spend/i, keys: ['budget'] },
    ],
    files: [{ id: 'nameplate_photo', kind: 'photo', caption: 'a phone photo of the nameplate on one outdoor unit', make: 'nameplate',
      reads: { spec_cooling_capacity: '18,000 BTU/h (1.5 TR) per unit, read from the nameplate photo (model GWH18, R410A)', spec_refrigerant: 'R410A (existing units, nameplate)' } }],
    jargon: [/\bbtu\b/i, /\btr\b/i, /heat.?load/i, /refrigerant|\br32\b|\br410/i, /three.?phase|single.?phase/i, /\bmep\b/i, /\bamc\b/i, /\besma\b/i, /\bt3\b/i, /condensate/i],
    patience: { slow_s: 45, max_slow: 6, abandon_on_repeat: 3, max_questions: 16 },
    identity: [{ label: 'the villa number', value: 'Villa 15', kind: 'text' }, { label: 'the area of the job', value: 'Al Barsha', kind: 'text' }],
    job: { title: 'AC not cooling, four wall units, villa in Dubai', trade: 'hvac', emirate: 'Dubai', lines: HVAC_LINES(4, '1.5 TR') },
  },

  // ── 2. a facility manager who knows a lot but is busy ───────────────────────────────────────────────────────────────
  facility_manager: {
    key: 'facility_manager', label: 'ZZ DEMO facility manager', short: 'a facility manager who knows the job and has no time',
    lang: 'en', voice: 'terse, 2 to 10 words, no greetings, technical, wants it fast; to anything optional he says "supplier to propose"',
    opener: 'Need 6 ceiling cassettes replaced, office Business Bay, 14th floor. Quotes this week pls',
    opener_topics: ['units', 'repair_or_replace', 'location', 'timeline'],
    facts: [
      { id: 'units', about: 'how many units and what kind', knows: true, says: '6 cassettes, 2.5 TR each.', re: /how many|what (kind|type)|type of|cassette|split|unit type/i,
        keys: ['system_type', 'spec_unit_type', 'spec_number_of_units_per_type'], reads: { system_type: 'Cassette', spec_unit_type: 'Ceiling cassette', spec_number_of_units_per_type: '6 cassettes' } },
      { id: 'capacity', about: 'capacity of each unit', knows: true, says: '2.5 TR each, 30k BTU.', re: /capacity|btu|\btr\b|\btons?\b|\bkw\b|size of (the |each )?unit/i,
        keys: ['spec_cooling_capacity'], reads: { spec_cooling_capacity: '6 x 2.5 TR (30,000 BTU/h)' } },
      { id: 'repair_or_replace', about: 'new, replacement or repair', knows: true, says: 'Replacement. Old ones are dead.', re: /new install|replac|repair|service|extension/i, keys: ['new_or_replace'], reads: { new_or_replace: 'Replacement of existing' } },
      { id: 'location', about: 'where the site is', knows: true, says: 'Business Bay, Dubai. 14th floor office.', re: /emirate|where|location|address|which area|property/i,
        keys: ['location', 'spec_site_location_and_emirate'], reads: { location: 'Office, 14th floor, Business Bay, Dubai', spec_site_location_and_emirate: 'Dubai' } },
      { id: 'rooms', about: 'room use and area', knows: true, says: 'Open-plan office, about 280 m2.', re: /room|m2|m²|square|space|how big|area used/i,
        keys: ['application_area', 'spec_room_use_and_area_or_heat_load_calc'], reads: { application_area: 'Open-plan office, about 280 m2', spec_room_use_and_area_or_heat_load_calc: 'Open-plan office, about 280 m2' } },
      { id: 'inverter', about: 'inverter or fixed speed', knows: true, says: 'Inverter.', re: /inverter|fixed.?speed/i, keys: ['spec_inverter_or_fixed_speed'], reads: { spec_inverter_or_fixed_speed: 'Inverter' } },
      { id: 'refrigerant', about: 'refrigerant', knows: true, says: 'R32.', re: /refrigerant|\br32\b|\br410/i, keys: ['spec_refrigerant'], reads: { spec_refrigerant: 'R32' } },
      { id: 'pipes', about: 'copper pipes', knows: false, says: 'Supplier to check on site.', re: /copper|pipe/i, keys: ['spec_copper_pipe_length_included_per_unit'] },
      { id: 'power', about: 'electrical supply', knows: true, says: 'Three phase, isolators in place.', re: /electric|power|phase|voltage|isolator|cabl/i,
        keys: ['electrical_supply', 'spec_power_supply', 'spec_electrical_isolator_and_cabling_scope'], reads: { electrical_supply: 'Three-phase 400V', spec_power_supply: 'Three-phase', spec_electrical_isolator_and_cabling_scope: 'Isolators in place' } },
      { id: 'scope', about: 'supply only or supply and install', knows: true, says: 'Supply and install.', re: /install|supply only|deliver|scope|turnkey/i, keys: ['scope', 'installation'], reads: { scope: 'Supply and install' }, req: { installation: 'yes' } },
      { id: 'brand', about: 'brand', knows: true, says: 'Daikin or equivalent.', re: /brand|make|daikin|tier|premium/i, keys: ['brand_tier', 'material.brand', 'spec_brand_preference_or_equivalent_tier'],
        reads: { brand_tier: 'Premium (Daikin/Mitsubishi/Trane/Carrier)' }, req: { 'material.brand': { other: 'Daikin or equivalent' } } },
      { id: 'timeline', about: 'when', knows: true, says: 'Within 2 weeks. Work after 7pm only.', re: /when|timeline|date|deadline|how soon|working hours|start/i, keys: ['timeline', 'required_by'],
        reads: { timeline: 'Within 2 weeks' }, req: { required_by: { date: '2026-11-29', text: 'within two weeks, work after 7 pm only' } } },
      { id: 'warranty', about: 'warranty', knows: true, says: '2 years.', re: /warrant|guarantee/i, keys: ['warranty', 'spec_warranty'], req: { warranty: { months: 24 } } },
      { id: 'outdoor', about: 'outdoor units and access', knows: true, says: 'Condensers on the roof, service lift.', re: /outdoor|roof|condenser|access|lift/i, keys: ['spec_outdoor_unit_mounting'], reads: { spec_outdoor_unit_mounting: 'Roof, service lift' } },
      { id: 'removal', about: 'removal of old units', knows: true, says: 'Yes, remove and dispose.', re: /remov|dispos|old unit/i, keys: ['spec_old_unit_removal_and_refrigerant_recover'], reads: { spec_old_unit_removal_and_refrigerant_recover: 'Remove and dispose' } },
      { id: 'ducting', about: 'ducting', knows: true, says: 'No ducting.', re: /duct/i, keys: ['material.ducting'], req: { 'material.ducting': 'not_needed' } },
      { id: 'budget', about: 'budget', knows: false, says: 'Send prices, we compare.', re: /budget|price|cost/i, keys: ['budget'] },
    ],
    files: [],
    jargon: [],
    patience: { slow_s: 30, max_slow: 4, abandon_on_repeat: 2, max_questions: 10 },
    identity: [{ label: 'the floor', value: '14th floor', kind: 'text' }],
    job: { title: 'Replace six ceiling cassette units, office in Business Bay, Dubai', trade: 'hvac', emirate: 'Dubai',
      lines: [{ description: 'Ceiling cassette 2.5 TR, inverter, R32, supply and install', qty: 6, unit: 'nos' }, { description: 'Removal and disposal of old cassettes', qty: 6, unit: 'nos' }, { description: 'Testing and commissioning', qty: 1, unit: 'lot' }] },
  },

  // ── 3. an Arabic-speaking customer who mixes Arabic and English ─────────────────────────────────────────────────────
  arabic_mixed: {
    key: 'arabic_mixed', label: 'ZZ DEMO Arabic-speaking customer', short: 'a customer who writes Gulf Arabic mixed with English words',
    lang: 'ar', voice: 'Gulf Arabic in Arabic script, mixing English trade words (AC, split, unit, Dubai), short, polite',
    opener: 'السلام عليكم، عندي 3 مكيفات split في الفيلا في مردف، واحد ما يبرد أبداً. أبي أبدلهم كلهم new',
    opener_topics: ['units', 'problem', 'repair_or_replace', 'location'],
    facts: [
      { id: 'units', about: 'how many units and what kind', knows: true, says: '3 مكيفات split على الجدار', re: /how many|كم|what (kind|type)|نوع|split|سبليت|unit type/i,
        keys: ['system_type', 'spec_unit_type', 'spec_number_of_units_per_type'], reads: { system_type: 'Wall/floor split', spec_unit_type: 'Wall split', spec_number_of_units_per_type: '3 wall splits' } },
      { id: 'problem', about: 'what is wrong', knows: true, says: 'واحد ما يبرد أبداً، والباقي قديمة', re: /problem|wrong|مشكلة|issue/i, keys: [] },
      { id: 'repair_or_replace', about: 'new, replacement or repair', knows: true, says: 'تبديل، أبي new units', re: /new install|replac|repair|service|تبديل|جديد|صيانة|تركيب جديد/i,
        keys: ['new_or_replace'], reads: { new_or_replace: 'Replacement of existing' } },
      { id: 'location', about: 'where the property is', knows: true, says: 'فيلا في مردف، دبي', re: /emirate|where|location|address|which area|وين|أين|الإمارة|المنطقة|العنوان/i,
        keys: ['location', 'spec_site_location_and_emirate'], reads: { location: 'A villa in Mirdif, Dubai', spec_site_location_and_emirate: 'Dubai' } },
      { id: 'capacity', about: 'capacity of each unit', knows: false, says: 'والله ما أعرف الـ size، يمكن 1.5 طن؟ مو متأكد', re: /capacity|btu|\btr\b|\btons?\b|طن|قدرة|سعة|حجم المكيف/i, keys: ['spec_cooling_capacity'] },
      { id: 'rooms', about: 'which rooms and how big', knows: true, says: 'غرفتين نوم والصالة، الصالة كبيرة شوي', re: /room|m2|m²|square|space|how big|غرف|غرفة|مساحة|الصالة/i,
        keys: ['application_area', 'spec_room_use_and_area_or_heat_load_calc'], reads: { application_area: 'Villa: 2 bedrooms and a fairly large hall', spec_room_use_and_area_or_heat_load_calc: '2 bedrooms and a large hall (no sizes)' } },
      { id: 'scope', about: 'supply only or supply and install', knows: true, says: 'توريد وتركيب، كل شي عليهم', re: /install|supply|deliver|scope|تركيب|توريد/i, keys: ['scope', 'installation'], reads: { scope: 'Supply and install' }, req: { installation: 'yes' } },
      { id: 'brand', about: 'brand', knows: true, says: 'أي brand زين، LG أو Gree', re: /brand|make|ماركة|نوع الماركة|tier/i, keys: ['brand_tier', 'material.brand', 'spec_brand_preference_or_equivalent_tier'],
        reads: { brand_tier: 'Mid (LG/Gree/O-General)' }, req: { 'material.brand': { other: 'LG or Gree' } } },
      { id: 'timeline', about: 'when', knows: true, says: 'قبل نهاية الشهر إن شاء الله', re: /when|timeline|date|deadline|متى|موعد|وقت/i, keys: ['timeline', 'required_by'],
        reads: { timeline: '2-4 weeks' }, req: { required_by: { date: '2026-11-30', text: 'before the end of the month' } } },
      { id: 'inverter', about: 'inverter or fixed speed', knows: true, says: 'inverter أحسن للكهرباء صح؟ خلها inverter', re: /inverter|انفرتر|fixed.?speed/i, keys: ['spec_inverter_or_fixed_speed'], reads: { spec_inverter_or_fixed_speed: 'Inverter' } },
      { id: 'pipes', about: 'copper pipes', knows: false, says: 'ما أدري عن المواسير', re: /copper|pipe|مواسير|أنابيب|نحاس/i, keys: ['spec_copper_pipe_length_included_per_unit'] },
      { id: 'outdoor', about: 'outdoor units', knows: true, says: 'الوحدات الخارجية على السطح', re: /outdoor|roof|condenser|السطح|خارجية/i, keys: ['spec_outdoor_unit_mounting'], reads: { spec_outdoor_unit_mounting: 'Roof' } },
      { id: 'warranty', about: 'warranty', knows: false, says: 'الضمان؟ اللي عادي عندكم', re: /warrant|guarantee|ضمان|كفالة/i, keys: ['warranty', 'spec_warranty'] },
      { id: 'power', about: 'electricity', knows: false, says: 'ما أعرف', re: /electric|power|phase|voltage|كهرباء/i, keys: ['electrical_supply', 'spec_power_supply'] },
      { id: 'removal', about: 'old units', knows: true, says: 'إيه شيلوا القديمة', re: /remov|dispos|old unit|القديمة|إزالة/i, keys: ['spec_old_unit_removal_and_refrigerant_recover'], reads: { spec_old_unit_removal_and_refrigerant_recover: 'Remove the old units' } },
      { id: 'ducting', about: 'ducting', knows: true, says: 'ما في duct', re: /duct|دكت|مجاري/i, keys: ['material.ducting'], req: { 'material.ducting': 'not_needed' } },
      { id: 'budget', about: 'budget', knows: false, says: 'ما عندي رقم، أبي أشوف الأسعار', re: /budget|price|cost|ميزانية|سعر/i, keys: ['budget'] },
    ],
    files: [],
    jargon: [/\bbtu\b/i, /heat.?load/i, /refrigerant|\br32\b|\br410/i, /three.?phase|single.?phase/i, /\bmep\b/i, /\besma\b/i, /\bt3\b/i, /condensate/i],
    patience: { slow_s: 40, max_slow: 5, abandon_on_repeat: 2, max_questions: 14 },
    identity: [{ label: 'the area of the job', value: 'Mirdif', kind: 'text' }],
    job: { title: 'Replace three wall split units, villa in Dubai', trade: 'hvac', emirate: 'Dubai', lines: HVAC_LINES(3, '1.5 TR') },
  },

  // ── 4. an impatient customer who leaves ─────────────────────────────────────────────────────────────────────────────
  impatient: {
    key: 'impatient', label: 'ZZ DEMO impatient customer', short: 'a customer who wants a price now and leaves if kept waiting',
    lang: 'en', voice: 'curt, a little irritated, one line, wants a price now; complains when asked twice',
    opener: 'how much to replace 2 split ac in JLT apartment. need price today',
    opener_topics: ['units', 'repair_or_replace', 'location', 'timeline'],
    facts: [
      { id: 'units', about: 'how many units and what kind', knows: true, says: '2 splits. wall ones', re: /how many|what (kind|type)|type of|split|unit type|cassette|ducted/i,
        keys: ['system_type', 'spec_unit_type', 'spec_number_of_units_per_type'], reads: { system_type: 'Wall/floor split', spec_unit_type: 'Wall split', spec_number_of_units_per_type: '2 wall splits' } },
      { id: 'repair_or_replace', about: 'new, replacement or repair', knows: true, says: 'replace. i said that', re: /new install|replac|repair|service|extension/i, keys: ['new_or_replace'], reads: { new_or_replace: 'Replacement of existing' } },
      { id: 'location', about: 'where', knows: true, says: 'JLT, Dubai', re: /emirate|where|location|address|which area|property/i, keys: ['location', 'spec_site_location_and_emirate'], reads: { location: 'An apartment in JLT, Dubai', spec_site_location_and_emirate: 'Dubai' } },
      { id: 'capacity', about: 'capacity', knows: true, says: '1.5 ton each', re: /capacity|btu|\btr\b|\btons?\b|\bkw\b|size of (the |each )?unit/i, keys: ['spec_cooling_capacity'], reads: { spec_cooling_capacity: '2 x 1.5 TR' } },
      { id: 'rooms', about: 'rooms', knows: true, says: 'bedroom and living', re: /room|m2|m²|square|space|how big/i, keys: ['application_area', 'spec_room_use_and_area_or_heat_load_calc'],
        reads: { application_area: 'Apartment: a bedroom and the living room', spec_room_use_and_area_or_heat_load_calc: 'Bedroom and living room' } },
      { id: 'scope', about: 'supply only or install', knows: true, says: 'supply and install obviously', re: /install|supply only|deliver|scope/i, keys: ['scope', 'installation'], reads: { scope: 'Supply and install' }, req: { installation: 'yes' } },
      { id: 'timeline', about: 'when', knows: true, says: 'this week', re: /when|timeline|date|deadline|how soon|start/i, keys: ['timeline', 'required_by'], reads: { timeline: 'Within 2 weeks' }, req: { required_by: { date: '2026-11-21', text: 'this week' } } },
      { id: 'inverter', about: 'inverter', knows: false, says: 'whatever. just give me a price', re: /inverter|fixed.?speed/i, keys: ['spec_inverter_or_fixed_speed'] },
      { id: 'pipes', about: 'copper pipes', knows: false, says: 'no idea. supplier can check', re: /copper|pipe/i, keys: ['spec_copper_pipe_length_included_per_unit'] },
      { id: 'brand', about: 'brand', knows: false, says: 'dont care, cheapest decent one', re: /brand|make|daikin|tier/i, keys: ['brand_tier', 'material.brand'] },
      { id: 'warranty', about: 'warranty', knows: false, says: 'standard', re: /warrant|guarantee/i, keys: ['warranty'] },
      { id: 'outdoor', about: 'outdoor unit', knows: true, says: 'balcony', re: /outdoor|roof|condenser|balcony/i, keys: ['spec_outdoor_unit_mounting'], reads: { spec_outdoor_unit_mounting: 'Balcony' } },
      { id: 'ducting', about: 'ducting', knows: true, says: 'no ducts', re: /duct/i, keys: ['material.ducting'], req: { 'material.ducting': 'not_needed' } },
      { id: 'budget', about: 'budget', knows: false, says: 'thats what im asking you', re: /budget|price|cost/i, keys: ['budget'] },
    ],
    files: [],
    jargon: [/heat.?load/i, /\bmep\b/i, /\besma\b/i, /\bt3\b/i, /condensate/i],
    patience: { slow_s: 20, max_slow: 3, abandon_on_repeat: 1, max_questions: 6 },
    identity: [{ label: 'the area of the job', value: 'JLT', kind: 'text' }],
    job: { title: 'Replace two wall split units, apartment in Dubai', trade: 'hvac', emirate: 'Dubai', lines: HVAC_LINES(2, '1.5 TR') },
  },
};

/** What is wrong with a truth sheet (a run refuses to start on one). */
export function personaProblems(p) {
  const out = [];
  if (!p || typeof p !== 'object') return ['no persona'];
  if (!/^ZZ DEMO /.test(p.label || '')) out.push(`${p.key}: the label must start "ZZ DEMO " (never a real person)`);
  if (!p.opener) out.push(`${p.key}: no opener`);
  const ids = new Set((p.facts || []).map((f) => f.id));
  for (const t of p.opener_topics || []) if (!ids.has(t)) out.push(`${p.key}: opener topic ${t} is not a fact`);
  for (const f of p.facts || []) {
    if (!f.id || !f.about || typeof f.knows !== 'boolean' || !f.says) out.push(`${p.key}: fact ${f.id || '?'} needs id, about, knows and says`);
    if (f.file && !(p.files || []).some((x) => x.id === f.file)) out.push(`${p.key}: fact ${f.id} offers a file ${f.file} the persona does not have`);
  }
  if (!(p.facts || []).some((f) => !f.knows)) out.push(`${p.key}: a real person does not know everything; give at least one "not sure"`);
  for (const k of ['slow_s', 'max_slow', 'abandon_on_repeat', 'max_questions']) if (!(k in (p.patience || {}))) out.push(`${p.key}: patience.${k} is not set`);
  if (!p.job?.title || !p.job?.trade || !p.job?.lines?.length) out.push(`${p.key}: job needs title, trade and lines`);
  return out;
}
