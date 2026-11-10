// legend_vocabulary — what a drawing's legend entry, a CAD block name or a BOQ line CALLS a device,
// mapped to one line type the BOQ uses. English and Arabic. No model.
//
// WHY (14 Sep 2026). A fire alarm drawing read through the free path produced one junk BOQ line
// because nothing knew that "SMOKE DETECTOR c/w SOUNDER" is a thing a supplier prices. The legend is
// the drawing's own statement of what is on it; this turns its words into line types.
//
// ORDER MATTERS: a combined device ("smoke detector c/w sounder") is tested before its parts, or it
// would be read as a plain smoke detector. OCR-tolerant: "¢/w", "c/w", "c w", "complete with" and
// "with" are the same thing, and common OCR confusions (0/O, 1/l/I, rn/m) are folded before matching.
//
// WHAT IT DOES NOT DO. It does not count. A legend entry says a device TYPE exists; how many there
// are comes from the counters (symbol_count.ts, a CAD block count) or from the customer.

export type DeviceType = {
  type: string; en: string; ar: string; unit: 'nos' | 'm';
  /** Tested against folded text; the first type whose pattern matches wins. */
  re: RegExp;
  /** The BOQ section a counted line of this type belongs to (every trade, ruling 1586). Fire alarm rows have none. */
  section?: string;
};

// EVERY TRADE (10 Nov 2026, sales_engineer; founder 10 Nov and ruling 1586: drawings come from every trade - shops, villas,
// offices, HVAC, lifts, pools, scaffolding, landscape, steel, joinery, signage, kitchens, sanitary, racking). ONE TABLE:
// [section, type, English, Arabic, pattern, unit]. Tested after the fire-alarm rows above and in this order, so a
// specific row ("emergency light", "kitchen sink", "fire door") stands before its general one ("light", "sink", "door").
// The patterns read a legend's wording AND a CAD block name with "_" / "-" read as spaces ("DOOR-SGL", "WC_WALLHUNG").
// Abbreviations are whole words only; a 2-3 letter code that is also a tag (SD, SKT) is left to drawing_set's tags.
type Row = [string, string, string, string, RegExp, ('nos' | 'm')?];
const TRADES: Row[] = [
  // electrical
  ['Electrical devices', 'emergency_light', 'Emergency light fitting', 'وحدة إنارة طوارئ', /emergency\s*(?:light|luminaire|lighting)|\bem\s*light|اناره?\s*طوارئ|إنار[ةه]\s*طوارئ/i],
  ['Electrical devices', 'exit_sign', 'Exit sign', 'لوحة مخرج', /exit\s*sign|exit\s*light|\bexit\b(?!\s*door)|لوح[ةه]\s*(?:ال)?مخرج/i],
  ['Electrical devices', 'distribution_board', 'Distribution board', 'لوحة توزيع كهربائية', /distribution\s*board|\bsmdb\b|\bmdb\b|\bdb\b|panel\s*board|لوح[ةه]\s*توزيع/i],
  ['Electrical devices', 'isolator_switch', 'Isolator switch', 'مفتاح عزل', /isolat(?:or|ing)\s*switch|\bdp\s*switch|مفتاح\s*عزل/i],
  ['Electrical devices', 'socket_outlet', 'Socket outlet', 'مقبس كهربائي', /socket|power\s*outlet|\b13\s*a\b|مقبس|بريز[ةه]/i],
  ['Electrical devices', 'light_switch', 'Light switch', 'مفتاح إنارة', /light\s*switch|\b\d\s*-?\s*gang\b|\bswitch\b|مفتاح\s*(?:ال)?(?:اناره|إنار[ةه])/i],
  ['Electrical devices', 'data_outlet', 'Data / telephone outlet', 'مخرج بيانات / هاتف', /data\s*(?:outlet|point|socket)|\brj\s*45\b|telephone\s*(?:outlet|point)|مخرج\s*(?:بيانات|هاتف)/i],
  ['Electrical devices', 'tv_outlet', 'TV outlet', 'مخرج تلفزيون', /\btv\s*(?:outlet|point|socket)|satellite\s*outlet|مخرج\s*تلفزيون/i],
  ['Electrical devices', 'cctv_camera', 'CCTV camera', 'كاميرا مراقبة', /\bcctv\b|camera|كاميرا/i],
  ['Electrical devices', 'access_control', 'Access control reader', 'قارئ التحكم بالدخول', /access\s*control|card\s*reader|التحكم\s*بالدخول/i],
  ['Electrical devices', 'speaker', 'Ceiling speaker', 'سماعة سقفية', /speaker|loud\s*speaker|سماع[ةه]/i],
  ['Electrical devices', 'light_bollard', 'Bollard light', 'إنارة عمودية قصيرة (بولارد)', /bollard/i],
  ['Electrical devices', 'light_fitting', 'Light fitting', 'وحدة إنارة', /down\s*light|\bluminaire|light\s*fitting|led\s*panel|recessed\s*light|pendant\s*light|wall\s*light|ceiling\s*light|spot\s*light|strip\s*light|linear\s*light|flood\s*light|وحد[ةه]\s*(?:اناره|إنار[ةه])|كشاف/i],
  // fire fighting
  ['Fire fighting', 'sprinkler_head', 'Sprinkler head', 'رأس رشاش حريق', /(?:pendent|pendant|upright|side\s*wall|concealed)\s*sprinkler|sprinkler\s*(?:head|pendent|pendant|upright|side\s*wall)|fire\s*sprinkler|رشاش\s*(?:ال)?حريق|رأس\s*رشاش/i],
  ['Fire fighting', 'fire_extinguisher', 'Fire extinguisher', 'طفاية حريق', /extinguisher|\bco2\b|dry\s*powder|طفاي[ةه]/i],
  ['Fire fighting', 'fire_hose_reel', 'Fire hose reel cabinet', 'خزانة بكرة خرطوم الحريق', /hose\s*reel|\bfhr\b|fire\s*hose\s*cabinet|خرطوم\s*(?:ال)?حريق/i],
  ['Fire fighting', 'landing_valve', 'Fire hydrant / landing valve', 'محبس حريق / فوهة إطفاء', /hydrant|landing\s*valve|fire\s*department\s*connection|\bfdc\b|حنفي[ةه]\s*حريق|فوه[ةه]\s*اطفاء/i],
  ['Fire fighting', 'fire_blanket', 'Fire blanket', 'بطانية حريق', /fire\s*blanket|بطاني[ةه]\s*حريق/i],
  // HVAC
  ['HVAC', 'fire_damper', 'Fire damper', 'خانق حريق', /fire\s*damper|\bfd\s*damper|خانق\s*حريق/i],
  ['HVAC', 'smoke_damper', 'Smoke damper', 'خانق دخان', /smoke\s*damper|خانق\s*دخان/i],
  ['HVAC', 'volume_damper', 'Volume control damper', 'خانق تحكم بالحجم', /volume\s*(?:control\s*)?damper|\bvcd\b|خانق/i],
  ['HVAC', 'linear_diffuser', 'Linear slot diffuser', 'ناشر هواء خطي', /linear\s*(?:slot\s*)?diffuser|slot\s*diffuser|ناشر\s*خطي/i],
  ['HVAC', 'supply_diffuser', 'Supply air diffuser', 'ناشر هواء التغذية', /supply\s*(?:air\s*)?diffuser|ceiling\s*diffuser|square\s*diffuser|round\s*diffuser|\bdiffuser|ناشر\s*هواء/i],
  ['HVAC', 'return_grille', 'Return / exhaust grille', 'شبكة هواء راجع / عادم', /return\s*(?:air\s*)?grille|exhaust\s*(?:air\s*)?grille|transfer\s*grille|\bgrille|register|شبك[ةه]\s*(?:هواء|راجع)/i],
  ['HVAC', 'louvre', 'Louvre', 'جلاّلة تهوية', /louv(?:re|er)|جلال[ةه]/i],
  ['HVAC', 'exhaust_fan', 'Exhaust fan', 'مروحة شفط', /exhaust\s*fan|extract\s*fan|\bef\b|\btef\b|مروح[ةه]\s*شفط/i],
  ['HVAC', 'fan_coil_unit', 'Fan coil unit', 'وحدة ملف المروحة', /fan\s*coil|\bfcu\b|وحد[ةه]\s*ملف/i],
  ['HVAC', 'air_handling_unit', 'Air handling unit', 'وحدة مناولة الهواء', /air\s*handling\s*unit|\bahu\b|\bfahu\b|وحد[ةه]\s*مناول[ةه]/i],
  ['HVAC', 'split_unit', 'Split / VRF indoor unit', 'وحدة تكييف منفصلة / داخلية', /split\s*(?:unit|ac|a\/c)|\bvrf\b|\bvrv\b|indoor\s*unit|cassette\s*unit|ducted\s*split|مكيف\s*سبليت|وحد[ةه]\s*داخلي[ةه]/i],
  ['HVAC', 'outdoor_unit', 'Condensing / outdoor unit', 'وحدة تكثيف خارجية', /condensing\s*unit|outdoor\s*unit|\bodu\b|\baccu\b|وحد[ةه]\s*خارجي[ةه]/i],
  ['HVAC', 'thermostat', 'Thermostat', 'منظم حرارة (ثرموستات)', /thermostat|room\s*controller|ثرموستات/i],
  // plumbing / sanitary
  ['Sanitary fixtures', 'kitchen_sink', 'Kitchen sink', 'حوض مطبخ', /kitchen\s*sink|حوض\s*مطبخ|مغسل[ةه]\s*مطبخ/i],
  ['Sanitary fixtures', 'water_closet', 'Water closet (WC)', 'مرحاض', /water\s*closet|\bw\s*\.?\s*c\b|toilet\s*(?:pan|suite)|wall\s*hung\s*wc|close\s*coupled|مرحاض|كرسي\s*افرنجي/i],
  ['Sanitary fixtures', 'wash_basin', 'Wash basin', 'مغسلة', /wash\s*(?:hand\s*)?basin|\bwhb\b|lavatory|vanity\s*basin|\bbasin|مغسل[ةه]/i],
  ['Sanitary fixtures', 'urinal', 'Urinal', 'مبولة', /urinal|مبول[ةه]/i],
  ['Sanitary fixtures', 'shower', 'Shower', 'دش', /shower|دش\b|دوش/i],
  ['Sanitary fixtures', 'bathtub', 'Bathtub', 'حوض استحمام', /bath\s*tub|bathtub|\bbath\b(?!\s*room)|بانيو|حوض\s*استحمام/i],
  ['Sanitary fixtures', 'bidet_spray', 'Bidet spray (shattaf)', 'شطاف', /bidet|shattaf|شطاف/i],
  ['Sanitary fixtures', 'sink', 'Sink', 'حوض', /\bsink\b|حوض\b/i],
  ['Drainage', 'floor_drain', 'Floor drain', 'صفاية أرضية', /floor\s*drain|floor\s*trap|\bfd\b|gully|صفاي[ةه]|بالوع[ةه]/i],
  ['Drainage', 'cleanout', 'Cleanout', 'فتحة تنظيف', /clean\s*out|rodding\s*eye|فتح[ةه]\s*تنظيف/i],
  ['Drainage', 'manhole', 'Manhole / inspection chamber', 'غرفة تفتيش', /man\s*hole|inspection\s*chamber|غرف[ةه]\s*تفتيش/i],
  ['Plumbing', 'water_heater', 'Water heater', 'سخان مياه', /water\s*heater|\bewh\b|calorifier|سخان/i],
  ['Plumbing', 'tap_mixer', 'Tap / mixer', 'خلاط / حنفية', /mixer|\btap\b|faucet|خلاط|حنفي[ةه]/i],
  // architecture / joinery / fit-out
  ['Doors', 'fire_door', 'Fire-rated door', 'باب مقاوم للحريق', /fire\s*(?:rated\s*)?door|\bfrd\b|باب\s*(?:مقاوم\s*)?(?:لل)?حريق/i],
  ['Doors', 'sliding_door', 'Sliding door', 'باب منزلق', /sliding\s*door|باب\s*منزلق|باب\s*سحاب/i],
  ['Doors', 'double_door', 'Double leaf door', 'باب بضلفتين', /double\s*(?:leaf\s*)?door|\bdbl\s*door|باب\s*(?:مزدوج|بضلفتين)/i],
  ['Doors', 'door', 'Door', 'باب', /\bdoor\b|\bdoors\b|\bdr\b|باب|أبواب|ابواب/i],
  ['Windows', 'window', 'Window', 'نافذة', /\bwindow|\bwin\b|\bwndw\b|نافذ[ةه]|شباك/i],
  ['Joinery', 'kitchen_cabinet', 'Kitchen cabinet unit', 'خزانة مطبخ', /kitchen\s*cabinet|base\s*unit|wall\s*unit|tall\s*unit|خزان[ةه]\s*مطبخ/i],
  ['Joinery', 'wardrobe', 'Wardrobe', 'خزانة ملابس', /wardrobe|built\s*-?in\s*closet|خزان[ةه]\s*ملابس|دولاب/i],
  ['Joinery', 'vanity_unit', 'Vanity unit', 'وحدة مغسلة', /vanity\s*(?:unit|counter)|وحد[ةه]\s*مغسل/i],
  ['Joinery', 'counter', 'Counter', 'كاونتر', /reception\s*(?:desk|counter)|cash\s*counter|counter|كاونتر/i],
  ['Joinery', 'shelving', 'Shelving unit', 'وحدة أرفف', /shelving|shelf\s*unit|display\s*unit|gondola|أرفف|ارفف/i],
  ['Furniture', 'workstation', 'Workstation / desk', 'محطة عمل / مكتب', /workstation|\bdesk\b|محط[ةه]\s*عمل/i],
  ['Furniture', 'chair', 'Chair', 'كرسي', /\bchair|كرسي/i],
  // commercial kitchen
  ['Kitchen equipment', 'kitchen_hood', 'Kitchen exhaust hood', 'شفاط مطبخ تجاري', /kitchen\s*hood|exhaust\s*hood|canopy\s*hood|\bhood\b|شفاط/i],
  ['Kitchen equipment', 'cooking_range', 'Cooking range', 'موقد طبخ', /cooking\s*range|\bhob\b|burner|\boven|موقد|فرن/i],
  ['Kitchen equipment', 'fryer', 'Fryer', 'مقلاة', /fryer|مقلا[ةه]/i],
  ['Kitchen equipment', 'refrigerator', 'Refrigerator / chiller', 'ثلاجة', /refrigerator|fridge|reach\s*-?in\s*(?:chiller|freezer)|\bfreezer|cold\s*room|ثلاج[ةه]|فريزر/i],
  ['Kitchen equipment', 'dishwasher', 'Dishwasher', 'غسالة صحون', /dish\s*washer|غسال[ةه]\s*صحون/i],
  ['Kitchen equipment', 'work_table', 'Stainless steel work table', 'طاولة عمل ستانلس ستيل', /work\s*table|prep(?:aration)?\s*table|طاول[ةه]\s*عمل/i],
  // landscape
  ['Landscape', 'palm_tree', 'Palm tree', 'نخلة', /palm\s*tree|\bpalm\b|date\s*palm|نخل/i],
  ['Landscape', 'tree', 'Tree', 'شجرة', /\btree\b|\btrees\b|شجر/i],
  ['Landscape', 'shrub', 'Shrub', 'شجيرة', /shrub|hedge|شجير/i],
  ['Landscape', 'planter', 'Planter', 'حوض زراعة', /planter|plant\s*pot|حوض\s*زراع/i],
  ['Landscape', 'irrigation_sprinkler', 'Irrigation sprinkler / pop-up', 'رشاش ري', /pop\s*-?\s*up|irrigation\s*(?:sprinkler|head)|bubbler|rotor|رشاش\s*ري/i],
  ['Landscape', 'valve_box', 'Irrigation valve box', 'صندوق محابس الري', /valve\s*box|صندوق\s*محابس/i],
  ['Landscape', 'bench', 'Outdoor bench', 'مقعد خارجي', /\bbench|مقعد/i],
  ['Landscape', 'litter_bin', 'Litter bin', 'سلة مهملات', /litter\s*bin|waste\s*bin|\bbin\b|سل[ةه]\s*مهملات/i],
  // lifts and escalators
  ['Lifts', 'escalator', 'Escalator', 'سلم كهربائي متحرك', /escalator|travelator|سلم\s*متحرك|سلم\s*كهربائي/i],
  ['Lifts', 'lift', 'Lift / elevator', 'مصعد', /\blift\b|elevator|مصعد/i],
  // pools
  ['Swimming pool', 'pool_light', 'Underwater pool light', 'إنارة تحت الماء', /under\s*water\s*light|pool\s*light|انار[ةه]\s*تحت\s*الماء|إنار[ةه]\s*تحت\s*الماء/i],
  ['Swimming pool', 'pool_skimmer', 'Pool skimmer', 'قاشطة حوض السباحة', /skimmer|قاشط/i],
  ['Swimming pool', 'pool_inlet', 'Pool return inlet', 'فوهة رجوع حوض السباحة', /(?:return|wall)\s*inlet|pool\s*inlet|فوه[ةه]\s*رجوع/i],
  ['Swimming pool', 'pool_main_drain', 'Pool main drain', 'مصرف رئيسي لحوض السباحة', /main\s*drain|مصرف\s*رئيسي/i],
  ['Swimming pool', 'pool_pump', 'Pool filtration pump', 'مضخة ترشيح الحوض', /pool\s*pump|filtration\s*pump|مضخ[ةه]\s*(?:ال)?ترشيح/i],
  ['Swimming pool', 'pool_filter', 'Pool sand filter', 'فلتر رملي للحوض', /sand\s*filter|pool\s*filter|فلتر/i],
  ['Swimming pool', 'pool_ladder', 'Pool ladder', 'سلم حوض السباحة', /pool\s*ladder|سلم\s*(?:ال)?حوض/i],
  // signage
  ['Signage', 'directional_sign', 'Directional / wayfinding sign', 'لوحة إرشادية', /directional\s*sign|wayfinding|totem|pylon\s*sign|\bsign(?:age)?\b|لوح[ةه]\s*ارشادي[ةه]|لوح[ةه]\s*إرشادي[ةه]/i],
  // racking / warehouse
  ['Racking', 'pallet_rack_bay', 'Pallet racking bay', 'خلية رفوف منصات', /pallet\s*rack|rack(?:ing)?\s*bay|رفوف\s*منصات/i],
  ['Racking', 'upright_frame', 'Racking upright frame', 'قائم رفوف', /upright\s*frame|قائم\s*رفوف/i],
  // structure
  ['Structure', 'column', 'Column', 'عمود', /\bcolumn|\bcol\b|عمود|أعمد[ةه]/i],
  ['Structure', 'pile', 'Pile', 'خازوق', /\bpile\b|\bpiles\b|خازوق|خوازيق/i],
  ['Structure', 'footing', 'Footing / pad foundation', 'قاعدة', /footing|pad\s*foundation|\bfooting\b|قاعد[ةه]/i],
  ['Structure', 'base_plate', 'Steel base plate', 'لوح قاعدة حديدي', /base\s*plate|لوح\s*قاعد/i],
  // scaffolding
  ['Scaffolding', 'scaffold_tower', 'Mobile scaffold tower', 'برج سقالات متحرك', /scaffold\s*tower|mobile\s*tower|برج\s*سقال/i],
  ['Scaffolding', 'scaffold_tie', 'Scaffold tie', 'رباط سقالة', /scaffold\s*tie|wall\s*tie|رباط\s*سقال/i],
];

const CW = String.raw`(?:c\s*/?\s*w|complete\s+with|with|w/)`;
export const DEVICE_TYPES: DeviceType[] = [
  { type: 'fire_alarm_control_panel', en: 'Fire alarm control panel', ar: 'لوحة تحكم إنذار الحريق', unit: 'nos',
    re: new RegExp(String.raw`fire\s*alarm\s*(?:control\s*)?panel|\bf\.?a\.?c\.?p\b|\bfap\b|لوح[هة]\s*(?:تحكم\s*)?انذار`, 'i') },
  { type: 'repeater_panel', en: 'Repeater panel', ar: 'لوحة مكررة', unit: 'nos', re: /repeater\s*panel|\bmimic\s*panel/i },
  { type: 'manual_call_point', en: 'Manual call point (break glass)', ar: 'نقطة نداء يدوية (كسر الزجاج)', unit: 'nos',
    re: /manual\s*call\s*-?\s*point|\bmcp\b|break\s*glass|نقط[هة]\s*نداء|كسر\s*الزجاج/i },
  { type: 'smoke_detector_sounder', en: 'Smoke detector c/w sounder', ar: 'كاشف دخان مع صفارة', unit: 'nos',
    re: new RegExp(String.raw`smoke\s*detector\s*${CW}\s*(?:base\s*)?sounder|كاشف\s*دخان\s*مع\s*صفار`, 'i') },
  { type: 'heat_detector_sounder', en: 'Heat detector c/w sounder', ar: 'كاشف حرارة مع صفارة', unit: 'nos',
    re: new RegExp(String.raw`heat\s*detector\s*${CW}\s*(?:base\s*)?sounder|كاشف\s*حرار[هة]\s*مع\s*صفار`, 'i') },
  { type: 'multi_sensor_detector', en: 'Multi-sensor detector', ar: 'كاشف متعدد الحساسات', unit: 'nos', re: /multi[\s-]*sensor|optical\s*heat|كاشف\s*متعدد/i },
  { type: 'beam_detector', en: 'Beam detector', ar: 'كاشف شعاعي', unit: 'nos', re: /beam\s*detector|كاشف\s*شعاع/i },
  { type: 'smoke_detector', en: 'Smoke detector', ar: 'كاشف دخان', unit: 'nos', re: /smoke\s*det(?:ector)?\b|optical\s*detector|كاشف\s*دخان|كواشف\s*دخان/i },
  { type: 'heat_detector', en: 'Heat detector', ar: 'كاشف حرارة', unit: 'nos', re: /heat\s*det(?:ector)?\b|كاشف\s*حرار/i },
  { type: 'wall_sounder_beacon', en: 'Wall-mounted sounder beacon', ar: 'صفارة مع ضوء وامض جدارية', unit: 'nos',
    re: /(?:wall\s*mounted\s*)?sounder\s*[/&+]?\s*(?:visual\s*)?beacon|\bvad\b|صفار[هة]\s*(?:مع\s*)?(?:ضوء|وامض)/i },
  { type: 'sounder', en: 'Sounder', ar: 'صفارة إنذار', unit: 'nos', re: /\bsounder\b|\bbell\b|صفار[هة]\s*انذار/i },
  { type: 'beacon', en: 'Beacon', ar: 'ضوء وامض', unit: 'nos', re: /\bbeacon\b|\bstrobe\b|ضوء\s*وامض/i },
  { type: 'interface_module', en: 'Interface / input-output module', ar: 'وحدة ربط', unit: 'nos', re: /interface\s*(?:unit|module)|\bi\/o\s*module|وحد[هة]\s*ربط/i },
  { type: 'loop_isolator', en: 'Loop isolator', ar: 'عازل الحلقة', unit: 'nos', re: /loop\s*isolator|\bisolator\s*module|عازل\s*(?:ال)?حلق/i },
  { type: 'fire_rated_cable', en: 'Fire-rated cable', ar: 'كابل مقاوم للحريق', unit: 'm', re: /fp\s*200|fire\s*(?:rated|resistant)\s*cable|\bmicc\b|كابل\s*مقاوم/i },
  ...TRADES.map(([section, type, en, ar, re, unit]) => ({ type, en, ar, unit: unit ?? 'nos', re, section })),
];

/** Lower-case, fold OCR look-alikes that turn up in drawing text, keep Arabic. */
export function foldOcr(s: string): string {
  return String(s || '').toLowerCase()
    .replace(/[¢©]/g, 'c').replace(/[|]/g, 'l').replace(/[‘’`´]/g, "'")
    .replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه')
    .replace(/(?<=[a-z])0(?=[a-z])/g, 'o').replace(/(?<=[a-z])1(?=[a-z])/g, 'l').replace(/rn(?=[a-z])/g, 'm')
    .replace(/\s+/g, ' ').trim();
}

export function deviceTypeOf(text: string): DeviceType | null {
  const t = snapWords(foldOcr(text));
  for (const d of DEVICE_TYPES) if (d.re.test(t)) return d;
  return null;
}

// A phone photo's OCR (19 Oct 2026 drawing bench, the sample sheet photographed at 1.5 deg, blurred, JPEG q60) read
// "MEAT DETECTOR", "SMOKE DETICTOR c 'wr SOBER", "WALL MOUNTED SOUNDER BEAL ON": 3 of 7 legend rows were lost.
// Each English word within a small edit distance of a legend word is snapped to it, and "c 'w" / "c =" is c/w.
// ponytail: English legend words only; Arabic OCR is not snapped.
const LEGEND_WORDS = ['smoke', 'detector', 'heat', 'sounder', 'beacon', 'manual', 'callpoint', 'call', 'point', 'mounted', 'wall', 'fire', 'alarm', 'control', 'panel'];
const lev = (a: string, b: string) => { const d = Array.from({ length: b.length + 1 }, (_, i) => i); for (let i = 1; i <= a.length; i++) { let p = d[0]; d[0] = i; for (let j = 1; j <= b.length; j++) { const t = d[j]; d[j] = Math.min(d[j] + 1, d[j - 1] + 1, p + (a[i - 1] === b[j - 1] ? 0 : 1)); p = t; } } return d[b.length]; };
export function snapWords(t: string): string {
  const s = t.replace(/\bc\s*['/]?\s*(?:w+r?|=)(?=\s|$)/g, 'c/w');
  return s.replace(/[a-z]{4,}/g, (w) => { if (LEGEND_WORDS.includes(w)) return w; const hit = LEGEND_WORDS.find((v) => Math.abs(v.length - w.length) <= 2 && lev(w, v) <= Math.max(1, Math.floor(v.length / 4))); return hit ?? w; })
    .replace(/\bsounder (?:bea[a-z]*|beal on|beal)\b/g, 'sounder beacon');
}
