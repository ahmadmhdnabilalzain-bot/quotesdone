// identity_places.ts — NOTHING BELOW THE EMIRATE CROSSES (13 Nov 2026, sales_engineer; founder ledger 1683).
//
// The founder, 13 Nov 2026: "Dubai in general is okay. We can keep that. But villa number, for example, has to be hidden.
// The area, like it says, okay, Dubai, it says then Al Barsha 2, Villa 15. Okay, I don't want Al Barsha and Villa 15 need
// to be hidden when they are shared with the supplier."
//
// MEASURED BEFORE (anonymity audit of 13 Nov 2026, REPORT_A L1/L4, REPORT_C L2): every scrubber let these through, on
// both doors: "Al Barsha 2", "Al Barsha South", "near Mall of the Emirates", "Marina Gate 2 tower, Dubai Marina",
// "البرشاء 2 … فيلا رقم 15", "25.1123, 55.2001", a what3words address, "Plot No. 373-4512", "Makani 12345 67890",
// "visit our showroom in Al Quoz", "from our Al Quoz warehouse", "Emirates NBD, Al Quoz branch". The only full removal
// was identity_text's ADDRESS ("Villa N, …, Dubai"), and it removed "Dubai" too. All three production inquiries named
// the area in their summary ("…in Al Nahda, Sharjah", "…in Khalifa City, Abu Dhabi", "…in Business Bay, Dubai").
//
// WHAT THIS DOES. `reducePlaces` finds every place below the emirate and reduces it TO the emirate:
//   * a community, area or district from the gazetteer below (all seven emirates, English spellings and Arabic, with
//     its numbered or named sub-area: "Al Barsha 2", "Khalifa City A", "Al Quoz Industrial Area 3", "البرشاء 2");
//   * a premises number: villa / apartment / flat / shop / showroom / warehouse / office / suite / plot / house
//     (and unit / building / tower / block next to another place), "فيلا رقم 15", "شقة 1204", "قطعة رقم 7";
//   * a street with a number ("Street 14", "14th Street"), a named road ("Al Wasl Road", "شارع الوصل");
//   * a named building ("Marina Gate 2 tower", "ZZ Palm IU8 Tower", "برج الخليج");
//   * a landmark after near / opposite / behind / next to / beside / close to ("near Mall of the Emirates", "قرب مول
//     الإمارات"), and the best-known landmarks by name;
//   * a Makani number, map coordinates inside the UAE, a what3words address.
// Places next to each other are one GROUP ("Villa 15, Al Barsha 2" is one place). A group next to an emirate is removed
// and the emirate stays ("Villa 15, Al Barsha 2, Dubai" -> "Dubai"); a group whose community names its emirate becomes
// that emirate ("from our Al Quoz warehouse" -> "from our Dubai warehouse"); a group that names no emirate (only a villa
// number, a landmark nobody listed, Al Nahda which is in Dubai AND Sharjah) is removed with the caller's mark: when in
// doubt the span goes (the round's fail-closed rule).
//
// DECIDED HERE (13 Nov 2026): "Al Ain" is a city of the Abu Dhabi emirate; it crosses only as "Abu Dhabi". Hatta crosses
// as Dubai, Khor Fakkan / Kalba / Dibba Al Hisn as Sharjah. An emirate word inside a district's name ("Dubai Marina",
// "Dubai Hills", "Dubai South") is the district, so it reduces to the emirate.
//
// WHAT IT MUST NOT TOUCH (identity_places.test.ts KEEP): "Marina blue" (a colour), "Jumeirah collection" (a range),
// "Dubai Municipality approved", "Sharjah-made", "DEWA", "3-bedroom villa", "2 villas", "villa has two floors",
// "Unit 6, 2 TR" (an AC unit), "plot area 500 m2", "Villa 4 bedrooms", "Cooling Tower CT-1", "Main Building ground floor",
// levels, dimensions, model numbers. Names a word shares with ordinary text (Marina, Jumeirah, Al Ain, Masafi, Liwa,
// the acronyms JVC / DIP / DSO) count only after a place cue ("in", "at", "near", "Location:") or beside another place.
//
// WHAT NO RULE CAN SEE (left to the second reader): a community or a building nobody listed, a landmark with no cue word,
// a place described in prose ("the villa behind the mosque on the corner"), a misspelling outside the variants below.
import { STREET_ADDRESS } from './identity_contacts.ts';
const D = '[0-9٠-٩۰-۹]';
const AL_ = '[\\u0621-\\u063A\\u0641-\\u064A\\u0671-\\u06D3]';
const AW = `${AL_}+`;
const AR_START = `(?<!${AL_})`;
const AR_END = `(?!${AL_})`;

export type EmirateKey = 'D' | 'S' | 'A' | 'J' | 'R' | 'U' | 'F';
export const EMIRATE_NAME: Record<EmirateKey, { en: string; ar: string }> = {
  D: { en: 'Dubai', ar: 'دبي' }, S: { en: 'Sharjah', ar: 'الشارقة' }, A: { en: 'Abu Dhabi', ar: 'أبوظبي' }, J: { en: 'Ajman', ar: 'عجمان' },
  R: { en: 'Ras Al Khaimah', ar: 'رأس الخيمة' }, U: { en: 'Umm Al Quwain', ar: 'أم القيوين' }, F: { en: 'Fujairah', ar: 'الفجيرة' },
};

// ── THE GAZETTEER ────────────────────────────────────────────────────────────────────────────────────────────────
// One entry per place: its emirates (two letters = the name exists in both, e.g. Al Nahda), then its spellings.
// `~` before a spelling: it is also an ordinary word or a brand, so it counts only after a place cue or beside a place.
// `^` before a spelling: matched in this exact case (acronyms, "The Springs").
// Written from the Dubai Land Department / Abu Dhabi Municipality community names and the common spellings on UAE
// documents and listings, 13 Nov 2026. Add a place here, never in a scrubber.
const GAZ_EN: [string, string][] = [
  // ── Dubai
  ['D', 'Al Barsha|Barsha|AlBarsha'], ['D', 'Barsha Heights|^TECOM|Tecom'], ['D', 'Al Quoz|Quoz|AlQuoz'], ['D', 'Al Qusais|Qusais|Al Ghusais'], ['D', 'Deira'], ['D', 'Bur Dubai'],
  ['D', 'Al Rigga|Rigga'], ['D', 'Port Saeed'], ['D', 'Hor Al Anz'], ['D', 'Abu Hail'], ['D', 'Al Muteena|Muteena'], ['D', 'Al Murar'], ['D', 'Al Baraha'], ['D', 'Al Mamzar|Mamzar'],
  ['D', 'Al Twar|Twar'], ['DS', 'Al Nahda|Nahda|Al Nahdah'], ['D', 'Muhaisnah|Muhaisna|Mhaisnah|Al Muhaisnah'], ['D', 'Al Mizhar|Mizhar'], ['D', 'Mirdif|Mirdiff|Mirdaf'],
  ['D', 'Al Warqa|Warqa|Al Warqaa'], ['D', 'Nad Al Sheba|Nad Al Shiba|Nad Al Hamar|Nad Al Hammar'], ['DJ', 'Al Rashidiya|Rashidiya|Rashidiyah|Al Rashidiyah'],
  ['D', 'Al Garhoud|Garhoud|Garhood|Al Garhood|Al Qarhoud'], ['D', 'Umm Ramool'], ['D', 'Al Khawaneej|Khawaneej'], ['D', 'Al Aweer|Aweer'], ['D', 'Ras Al Khor'],
  ['D', 'Al Jaddaf|Jaddaf'], ['D', 'Oud Metha'], ['D', 'Umm Hurair'], ['D', 'Al Mankhool|Mankhool'], ['D', 'Al Satwa|Satwa'], ['D', 'Al Jafiliya|Jafiliya|Jafiliyah|Al Jafiliyah'],
  ['D', 'Al Bada|Al Badaa'], ['D', '~Al Wasl'], ['D', '~Al Safa'], ['D', 'Umm Suqeim|Umm Suqaim|Umm Sequim'], ['D', 'Al Manara'], ['D', 'Al Sufouh|Sufouh'], ['D', 'Al Hudaiba'],
  ['D', 'Al Raffa'], ['D', 'Al Fahidi'], ['D', 'Al Shindagha|Shindagha'], ['D', "Za'abeel|Zabeel|Zaabeel"], ['D', 'Business Bay'], ['D', 'Downtown Dubai'], ['D', '~^DIFC'],
  ['D', 'World Trade Centre|World Trade Center|Trade Centre'], ['D', 'Al Kifaf'], ['D', 'City Walk'], ['D', 'Dubai Marina'], ['D', '~Marina'],
  ['D', 'Jumeirah Lakes Towers|^JLT'], ['D', 'Jumeirah Beach Residence|^JBR'], ['D', 'Jumeirah Village Circle|~^JVC'], ['D', 'Jumeirah Village Triangle|~^JVT'],
  ['D', 'Jumeirah Islands|Jumeirah Park|Jumeirah Golf Estates|Jumeirah Heights|Jumeirah Bay|Jumeira Bay'], ['D', 'Palm Jumeirah|Palm Jumeira|Palm Jebel Ali|^The Palm'],
  ['D', '~Jumeirah|~Jumeira|~Jumera'], ['D', 'Bluewaters|Bluewaters Island'], ['D', 'Emirates Hills|Emirates Living'], ['D', '^The Meadows|^The Springs|^The Lakes|^The Greens|^The Views|^The Valley'],
  ['D', 'Arabian Ranches'], ['D', 'Al Barari'], ['D', 'Dubai Hills Estate|Dubai Hills'], ['D', 'Mohammed Bin Rashid City|Mohammed bin Rashid City|MBR City'], ['D', 'Meydan'],
  ['D', 'Sobha Hartland'], ['D', 'Al Furjan|Furjan'], ['D', 'Discovery Gardens'], ['D', 'Jebel Ali|Jabal Ali'], ['D', 'Dubai Investment Park|Dubai Investments Park|~^DIP'],
  ['D', 'Dubai Industrial City|Dubai Industrial Park'], ['D', 'Dubai South'], ['D', 'Dubai World Central|~^DWC'], ['D', 'Dubai Silicon Oasis|Silicon Oasis|~^DSO'],
  ['D', 'International City'], ['D', 'Dubai Sports City|Sports City'], ['D', 'Motor City|Dubai Motor City'], ['D', 'Dubai Production City|^IMPZ'], ['D', 'Dubai Studio City|Studio City'],
  ['D', 'Arjan'], ['D', 'Dubailand'], ['D', 'Town Square'], ['D', 'Remraam'], ['D', 'Mudon'], ['D', 'Damac Hills|DAMAC Hills|Damac Lagoons|DAMAC Lagoons|Akoya'],
  ['D', 'Tilal Al Ghaf'], ['D', 'Villanova'], ['D', 'Al Warsan|Warsan'], ['D', 'Liwan'], ['D', 'Wadi Al Safa'], ['D', 'Dubai Festival City|Festival City'],
  ['D', 'Dubai Creek Harbour|Creek Harbour|Dubai Creek Harbor'], ['D', 'Culture Village'], ['D', 'Al Habtoor City'], ['D', 'Dubai Media City|Media City'], ['D', 'Dubai Internet City|Internet City'],
  ['D', 'Knowledge Village|Dubai Knowledge Park'], ['D', 'Dubai Healthcare City|Healthcare City'], ['D', 'Dubai Academic City|Academic City'], ['D', 'Dubai Design District'],
  ['D', 'Al Khail'], ['D', 'Hatta'], ['D', 'Al Lisaili|Lisaili'], ['D', 'Al Marmoom'], ['D', 'Lehbab'], ['DS', 'Al Hamriya|Al Hamriyah|Hamriyah'], ['DA', 'Al Mushrif|Mushrif'],
  ['D', 'Al Khabaisi'], ['D', 'Al Muraqqabat|Muraqqabat'], ['D', 'Dubai Maritime City|Dubai Harbour|Dubai Waterfront'], ['D', 'La Mer'], ['D', 'Pearl Jumeirah'], ['D', 'Port Rashid'],
  ['D', 'Dubai Airport Free Zone|^DAFZA'], ['D', 'Jebel Ali Free Zone|~^JAFZA'], ['D', 'Dubai Outsource City|Dubai Science Park'], ['DA', 'Al Karama|Karama|Al Karamah|Karamah'],
  ['D', 'Al Qudra'], ['D', 'Dubai Waterfront'], ['D', 'Al Sufouh'], ['D', 'Umm Al Sheif|Umm Al Sheef'], ['D', 'Al Quoz Creative Zone'],
  // ── Sharjah
  ['S', 'Al Majaz|Majaz'], ['S', 'Al Qasba|Qasba|Al Qasbaa'], ['S', 'Al Khan'], ['S', "Al Taawun|Taawun|Al Taawon|Al Ta'awun"], ['S', 'Al Qasimia|Qasimia|Al Qasimiya|Al Qasimiyah'],
  ['S', 'Al Nabba'], ['S', 'Muwaileh|Muwailih|Muweilah|Al Muwaileh'], ['S', 'University City'], ['S', 'Al Rahmaniya|Rahmaniya|Al Rahmaniyah'], ['S', 'Al Zahia|Al Zahiya'],
  ['S', 'Aljada'], ['S', 'Tilal City'], ['S', 'Al Yarmook'], ['S', 'Al Ghuwair'], ['S', 'Rolla'], ['S', '~Al Soor'], ['S', '~Al Jubail'], ['S', 'Al Layyeh'], ['S', 'Al Heera'],
  ['SA', 'Al Khalidiya|Al Khalidiyah|Khalidiya|Khalidiyah'], ['S', '~Al Musalla'], ['S', "Al Sajaa|Al Saja'a|Sajja|Sajaa|Al Sajja"], ['S', 'Maliha'], ['S', 'Al Riqa'], ['S', 'Al Fisht'],
  ['S', 'Halwan'], ['S', 'Al Ramtha'], ['S', 'Al Mirgab'], ['S', 'Abu Shagara'], ['S', 'Al Butina'], ['S', '~Al Sharq'], ['S', 'Al Azra'], ['S', '~Al Falaj'], ['S', 'Samnan'],
  ['S', 'Al Jazzat'], ['S', 'Al Suyoh'], ['S', 'Hoshi'], ['S', "~Al Rifa'a|~Al Rifaa"], ['S', 'Kalba'], ['S', 'Khor Fakkan|Khorfakkan|Khor Fakan'], ['S', 'Dibba Al Hisn'],
  ['S', 'Al Dhaid|Dhaid'], ['S', 'Mleiha'], ['S', 'Al Madam'], ['S', 'Al Mujarrah'], ['S', '~Al Gharb'], ['S', 'Al Ramla'], ['S', 'Al Qadisiya'], ['S', 'Al Fayha'],
  ['S', 'Al Sabkha'], ['S', 'Al Shuwaihean'], ['S', 'Al Khezamia'], ['S', 'Al Tai'], ['S', 'Sharjah Airport Free Zone|SAIF Zone|^SAIF'], ['S', 'Hamriyah Free Zone'],
  // ── Abu Dhabi (and its Al Ain region)
  ['A', 'Khalifa City'], ['A', 'Mohammed Bin Zayed City|Mohammed bin Zayed City|MBZ City|~^MBZ'], ['A', 'Mussafah|Musaffah|Mussaffah|Musafah|Al Mussafah|^ICAD'],
  ['A', 'Al Reem Island|Reem Island'], ['A', 'Saadiyat Island|Saadiyat'], ['A', 'Yas Island'], ['A', 'Al Raha Beach|Raha Beach|Al Raha Gardens'], ['A', '~Al Raha'], ['A', 'Al Reef'],
  ['A', 'Al Shamkha|Shamkha'], ['A', '~Al Falah'], ['A', 'Baniyas|Bani Yas'], ['A', 'Shakhbout City|Shakhbout'], ['A', 'Al Bateen'], ['A', 'Al Nahyan'], ['A', '~Al Wahda'],
  ['A', 'Al Manhal'], ['A', 'Tourist Club Area|Tourist Club'], ['A', 'Al Zahiyah'], ['A', 'Al Maryah Island|Maryah Island'], ['A', 'Al Muroor|Muroor'], ['A', 'Madinat Zayed'],
  ['A', 'Mina Zayed'], ['A', 'Al Danah'], ['A', 'Al Markaziyah'], ['AJ', 'Al Rawdah|Al Rawda'], ['A', 'Al Maqtaa'], ['A', 'Bain Al Jessrain|Between Two Bridges'], ['A', 'Al Rahba'],
  ['A', 'Al Samha'], ['A', 'Al Wathba'], ['A', 'Masdar City|Masdar'], ['A', 'Zayed City'], ['A', 'Ruwais|Al Ruwais'], ['A', 'Ghayathi'], ['A', '~Liwa'], ['A', 'Al Dhafra|Western Region'],
  ['A', 'Sas Al Nakhl'], ['A', 'Hudayriyat'], ['A', 'Jubail Island'], ['A', 'Al Bahia'], ['A', 'Al Shawamekh'], ['A', 'Al Mafraq'], ['A', 'Khalifa Industrial Zone|^KIZAD'],
  ['A', 'Al Ghadeer'], ['A', '~Al Ain'], ['A', 'Al Jimi'], ['A', 'Al Muwaiji'], ['A', 'Hili'], ['A', 'Al Towayya'], ['A', 'Al Maqam'], ['A', 'Zakher'], ['A', 'Al Khabisi'],
  ['A', 'Al Mutaredh'], ['A', 'Al Hayer'], ['A', 'Sweihan'], ['A', 'Al Yahar'], ['A', 'Falaj Hazza'], ['A', 'Al Foah'], ['A', 'Al Sarooj|Al Sarouj'], ['A', 'Al Jahili'],
  ['A', 'Al Mutawaa'], ['A', 'Al Qattara'], ['A', 'Al Masoudi'], ['A', 'Al Bawadi'],
  // ── Ajman
  ['J', 'Al Nuaimiya|Nuaimiya|Al Nuaimia|Al Nuaimiyah'], ['J', 'Al Jurf'], ['J', 'Al Mowaihat|Mowaihat'], ['J', 'Al Hamidiya|Hamidiya|Al Hamidiyah'], ['J', 'Al Rumaila'],
  ['J', '~Al Bustan'], ['J', '~Al Zahra'], ['J', 'Al Tallah'], ['J', 'Emirates City'], ['J', 'Ajman Uptown'], ['J', '~Al Yasmeen'], ['J', 'Al Helio'], ['J', '~Al Alia'],
  ['J', 'Al Amerah'], ['J', 'Masfout'], ['J', '~Manama'], ['J', 'Al Zorah'], ['J', '~Garden City'], ['JR', '~Al Nakhil|~Al Nakheel'], ['J', 'Al Owan'], ['J', 'Al Mushairif'],
  ['J', 'Ajman Free Zone'], ['J', 'Al Sawan'],
  // ── Ras Al Khaimah
  ['R', 'Al Dhait'], ['R', 'Julphar'], ['R', 'Al Hamra Village'], ['R', '~Al Hamra'], ['R', 'Mina Al Arab'], ['R', 'Al Marjan Island|Marjan Island'], ['R', 'Khuzam'], ['R', 'Al Qusaidat'],
  ['R', 'Seih Al Uraibi|Al Uraibi'], ['R', 'Al Jazirah Al Hamra|Al Jazeera Al Hamra'], ['R', 'Al Rams'], ['R', 'Digdaga|Digdagga'], ['R', 'Al Mairid'], ['R', 'Khatt'], ['R', 'Shamal'],
  ['R', 'Al Mamourah'], ['R', 'Dafan Al Nakheel'], ['R', 'Ghalilah'], ['R', 'Al Ghail'], ['R', 'Al Kharran'], ['R', 'Al Hamraniyah'], ['R', 'Al Hulaila'],
  // ── Umm Al Quwain
  ['U', '~Al Salamah|~Salamah'], ['U', '~Al Raas'], ['U', 'Al Ramlah'], ['U', '~Al Haditha'], ['U', '~Al Raudah'], ['U', 'Al Humrah'], ['U', 'Falaj Al Mualla'], ['U', 'Al Sinniyah'],
  ['U', '~Al Maidan'],
  // ── Fujairah
  ['F', 'Dibba Al Fujairah|Dibba Fujairah'], ['FS', '~Dibba'], ['F', 'Mirbah'], ['F', 'Qidfa'], ['F', 'Al Faseel|Faseel'], ['F', 'Sakamkam'], ['F', 'Al Gurfa'], ['F', '~Masafi'],
  ['F', 'Al Bidya|Bidiyah|Al Badiyah'], ['F', 'Murbeh'], ['F', '~Al Hail'], ['F', 'Madhab'], ['F', 'Al Taween'], ['F', 'Al Aqah|Aqah'], ['F', 'Dadna'],
  // ── landmarks known by name (each one is in exactly one emirate)
  ['D', 'Mall of the Emirates|Mall of Emirates|^MOE'], ['D', 'Dubai Mall'], ['D', 'Burj Khalifa'], ['D', 'Burj Al Arab'], ['D', 'Ibn Battuta Mall|Ibn Battuta'], ['D', 'Mirdif City Centre'],
  ['D', 'Deira City Centre|City Centre Deira'], ['D', 'Global Village'], ['D', 'Dragon Mart'], ['D', 'Expo City|Expo 2020 site'], ['D', 'Dubai Frame'], ['D', 'Atlantis The Palm'],
  ['A', 'Yas Mall'], ['A', 'Ferrari World'], ['A', 'Sheikh Zayed Grand Mosque'], ['A', 'Al Wahda Mall'], ['A', 'Abu Dhabi Mall'], ['A', 'Louvre Abu Dhabi'], ['A', 'Emirates Palace'],
  ['S', 'Sahara Centre|Sahara Center'], ['S', 'Mega Mall'], ['S', 'City Centre Sharjah'], ['J', 'Ajman City Centre'], ['R', 'Manar Mall'], ['R', 'RAK Mall'], ['F', 'Fujairah City Centre'],
];
const GAZ_AR: [string, string][] = [
  ['D', 'البرشاء|البرشا'], ['D', 'القوز'], ['D', 'القصيص'], ['D', 'ديرة'], ['D', 'بر دبي'], ['D', 'هور العنز'], ['D', 'أبو هيل'], ['D', 'المطينة'], ['D', 'الممزر'], ['D', 'الطوار'],
  ['DS', 'النهدة'], ['D', 'محيصنة'], ['D', 'المزهر'], ['D', 'مردف'], ['D', 'الورقاء'], ['D', 'ند الشبا|ند الحمر'], ['DJ', 'الراشدية'], ['D', 'القرهود'], ['D', 'الخوانيج'],
  ['D', 'العوير'], ['D', 'رأس الخور'], ['D', 'الجداف'], ['D', 'عود ميثاء'], ['D', 'المنخول'], ['D', 'السطوة'], ['D', 'الجافلية'], ['D', '~الوصل'], ['D', '~الصفا'], ['D', 'جميرا|جميرة'],
  ['D', 'أم سقيم'], ['D', '~المنارة'], ['D', 'الصفوح'], ['D', 'زعبيل'], ['D', 'الخليج التجاري'], ['D', 'وسط مدينة دبي|داون تاون دبي'], ['D', 'دبي مارينا|مرسى دبي|مارينا دبي'],
  ['D', 'أبراج بحيرات جميرا'], ['D', 'نخلة جميرا'], ['D', 'المرابع العربية'], ['D', 'تلال الإمارات'], ['D', 'جبل علي'], ['D', 'ديسكفري جاردنز'], ['D', 'الفرجان'],
  ['D', 'واحة دبي للسيليكون|واحة السيليكون'], ['D', 'المدينة العالمية'], ['D', 'مدينة دبي الرياضية'], ['D', 'مدينة دبي للإعلام|مدينة دبي للانترنت|مدينة دبي للإنترنت'], ['D', 'حتا'], ['D', 'الخيل'],
  ['D', 'دبي هيلز'], ['DA', 'الكرامة'], ['DS', 'الحمرية'], ['D', 'ورسان'], ['D', 'المدينة الأكاديمية'], ['D', 'الصفوح'], ['D', 'ميدان'], ['D', 'الخبيصي'], ['D', 'المرقبات'],
  ['D', 'مول الإمارات'], ['D', 'دبي مول'], ['D', 'برج خليفة'], ['D', 'برج العرب'], ['D', 'القرية العالمية'], ['D', 'ابن بطوطة'],
  ['S', 'المجاز'], ['S', 'القصباء'], ['S', '~الخان'], ['S', 'التعاون'], ['S', 'القاسمية'], ['S', 'النباعة'], ['S', 'مويلح'], ['S', 'المدينة الجامعية'], ['S', 'الرحمانية'],
  ['S', 'الزاهية'], ['S', 'الجادة'], ['S', 'اليرموك'], ['S', 'الغوير'], ['S', 'الرولة'], ['SA', 'الخالدية'], ['S', 'السجع|الصجعة'], ['S', 'مليحة'], ['S', 'الفشت'], ['S', 'حلوان'],
  ['S', 'الرمثاء'], ['S', 'المرقاب'], ['S', 'أبو شغارة'], ['S', 'البطينة'], ['S', 'سمنان'], ['S', 'كلباء'], ['S', 'خورفكان|خور فكان'], ['S', 'دبا الحصن'], ['S', 'الذيد'], ['S', 'المدام'],
  ['A', 'مدينة خليفة'], ['A', 'مدينة محمد بن زايد'], ['A', 'مصفح|المصفح'], ['A', 'جزيرة الريم'], ['A', 'جزيرة السعديات|السعديات'], ['A', 'جزيرة ياس'], ['A', 'شاطئ الراحة'],
  ['A', 'الشامخة'], ['A', 'بني ياس'], ['A', 'مدينة شخبوط'], ['A', 'البطين'], ['DA', 'المشرف'], ['A', 'النهيان'], ['A', 'المنهل'], ['A', 'النادي السياحي'], ['A', 'جزيرة الماريه|جزيرة المارية'],
  ['A', 'المرور'], ['A', 'مدينة زايد'], ['A', 'ميناء زايد'], ['AJ', 'الروضة'], ['A', 'المقطع'], ['A', 'بين الجسرين'], ['A', 'الرحبة'], ['A', 'السمحة'], ['A', 'الوثبة'], ['A', 'مدينة مصدر'],
  ['A', 'الرويس'], ['A', 'غياثي'], ['A', '~ليوا'], ['A', 'الظفرة'], ['A', 'الشوامخ'], ['A', 'المفرق'], ['A', '~العين'], ['A', 'الجيمي'], ['A', 'المويجعي'], ['A', 'هيلي'], ['A', 'الطوية'],
  ['A', 'زاخر'], ['A', 'الخبيصي'], ['A', 'سويحان'], ['A', 'فلج هزاع'], ['A', 'الفوعة'], ['A', 'الجاهلي'], ['A', 'القطارة'], ['A', 'المسعودي'], ['A', 'جامع الشيخ زايد الكبير'],
  ['J', 'النعيمية'], ['J', 'الجرف'], ['J', 'المويهات'], ['J', 'الحميدية'], ['J', 'الرميلة'], ['J', '~البستان'], ['J', 'التلة'], ['J', 'مدينة الإمارات'], ['J', 'الحليو'], ['J', 'مصفوت'],
  ['J', 'الزوراء'], ['JR', '~النخيل'], ['J', 'المشيرف'],
  ['R', 'الظيت'], ['R', 'جلفار'], ['R', '~الحمراء'], ['R', 'ميناء العرب'], ['R', 'جزيرة المرجان'], ['R', 'خزام'], ['R', 'القصيدات'], ['R', 'سيح العريبي|العريبي'], ['R', 'الجزيرة الحمراء'],
  ['R', 'الرمس'], ['R', 'دقداقة'], ['R', 'المعيريض'], ['R', 'المعمورة'], ['R', 'غليلة'], ['R', 'الحمرانية'],
  ['U', 'فلج المعلا'], ['U', 'السينية'], ['U', '~الرملة'],
  ['F', 'دبا الفجيرة'], ['FS', '~دبا'], ['F', 'مربح'], ['F', 'قدفع'], ['F', 'الفصيل'], ['F', 'سكمكم'], ['F', '~مسافي'], ['F', 'البدية'], ['F', 'مضب'], ['F', 'العقة'], ['F', 'دادنا'],
];

const rxEsc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/** "Al Barsha" -> Al[\s-]*Barsha: a hyphen, no space or two spaces between the words are the same place. */
const enForm = (v: string) => v.split(/\s+/).map(rxEsc).join("[\\s\\-]*").replace(/'/g, "['’]?");
/** Arabic letter variants: any alef, ة/ه, final ي/ى; a space between the words may be one or more. */
const arForm = (v: string) => v.split(/\s+/).map((w) => w.replace(/[أإآا]/g, '[أإآا]').replace(/[ةه](?=$)/g, '[ةه]').replace(/[يى](?=$)/g, '[يى]')).join('\\s+');
type Entry = { keys: EmirateKey[]; cue: boolean; re: RegExp; ar: boolean };
// A numbered or named sub-area belongs to the place: "Al Barsha 2", "Al Barsha South", "Khalifa City A", "Al Quoz
// Industrial Area 3", "Mirdif 1". A single letter only standing alone ("Al Quoz A/C units" keeps its A/C).
const SUB_EN = `(?:[\\s\\-]+(?:Industrial(?:\\s+Area)?(?:[\\s\\-]*(?:No\\.?\\s*)?\\d{1,2}(?![\\d.,]\\d))?|Ind\\.?\\s*Area(?:[\\s\\-]*\\d{1,2})?|(?:South|North|East|West|First|Second|Third|1st|2nd|3rd)(?![A-Za-z])|\\d{1,2}(?![\\d.,]\\d)(?![\\s\\-]*(?:nos?|pcs|sets?|units?|villas?|bed|br|bhk|m2|sqm|m|mm|kw|tr|x)(?![A-Za-z]))|[A-D](?![\\w/&'’-])))?`;
const SUB_AR = `(?:\\s*(?:${D}{1,2}(?!${D})|الأولى|الاولى|الثانية|الثالثة|الأول|الاول|الثاني|الثالث|الجنوبية|الشمالية|جنوب|شمال|الصناعية(?:\\s*${D}{1,2})?))?`;
const ENTRIES: Entry[] = [];
for (const [k, list] of GAZ_EN) for (const raw of list.split('|')) {
  const cue = raw.includes('~'), cs = raw.includes('^'), v = raw.replace(/[~^]/g, '');
  ENTRIES.push({ keys: k.split('') as EmirateKey[], cue, ar: false, re: new RegExp(`(?<![A-Za-z0-9])${enForm(v)}(?![A-Za-z0-9])${SUB_EN}`, cs ? 'g' : 'gi') });
}
// Most one-word Arabic place names are also words ("التعاون" cooperation, "المرور" traffic, "المشرف" the supervising
// engineer, "الروضة" a garden, "مربح" profitable): a one-word Arabic name counts only after a place cue or beside a place,
// unless it is a name and nothing else (AR_DISTINCT).
const AR_DISTINCT = new Set(['البرشاء', 'البرشا', 'القوز', 'ديرة', 'مردف', 'محيصنة', 'القرهود', 'الخوانيج', 'جميرا', 'جميرة', 'الجافلية', 'مويلح', 'كلباء', 'خورفكان', 'مصفح', 'المصفح',
  'النعيمية', 'الظيت', 'جلفار', 'دقداقة', 'القصيدات', 'المعيريض', 'القاسمية', 'المويجعي', 'الجيمي', 'سويحان', 'زاخر', 'الخبيصي', 'المرقبات', 'الفرجان', 'الممزر', 'القصيص', 'محيصنه']);
for (const [k, list] of GAZ_AR) for (const raw of list.split('|')) {
  const v = raw.replace(/[~^]/g, ''), cue = raw.includes('~') || (!/\s/.test(v) && !AR_DISTINCT.has(v));
  // An Arabic place takes a joined preposition (بالبرشاء, في is a word of its own); لل for an ال name ("للبرشاء").
  const f = arForm(v), lil = v.startsWith('ال') ? `|لل${arForm(v.slice(2))}` : '';
  ENTRIES.push({ keys: k.split('') as EmirateKey[], cue, ar: true, re: new RegExp(`${AR_START}(?:[وبف]|وب)?(?:${f}${lil})${AR_END}${SUB_AR}`, 'g') });
}

// ── the emirates themselves (what may cross) ─────────────────────────────────────────────────────────────────────
const EMIRATE_RE: [EmirateKey, RegExp][] = [
  ['D', /(?<![A-Za-z])Dubai(?![A-Za-z])|(?<![ء-ي])[وبف]?دبي(?![ء-ي])/gi],
  ['S', /(?<![A-Za-z])Sharjah(?![A-Za-z])|(?<![ء-ي])[وبف]?(?:ال|لل)شارق[ةه](?![ء-ي])/gi],
  ['A', /(?<![A-Za-z])Abu[\s-]*Dhabi(?![A-Za-z])|(?<![ء-ي])[وبف]?[أا]بو\s*ظبي(?![ء-ي])/gi],
  ['J', /(?<![A-Za-z])Ajman(?![A-Za-z])|(?<![ء-ي])[وبف]?عجمان(?![ء-ي])/gi],
  ['R', /(?<![A-Za-z])Ras[\s-]+Al[\s-]*Khaimah(?![A-Za-z])|(?<![A-Za-z])RAK(?![A-Za-z])|(?<![ء-ي])[وبف]?ر[أا]س\s+الخيم[ةه](?![ء-ي])/g],
  ['U', /(?<![A-Za-z])Umm[\s-]+Al[\s-]*Quwain(?![A-Za-z])|(?<![A-Za-z])UAQ(?![A-Za-z])|(?<![ء-ي])[وبف]?[أا]م\s+القيوين(?![ء-ي])/g],
  ['F', /(?<![A-Za-z])Fujairah(?![A-Za-z])|(?<![ء-ي])[وبف]?(?:ال|لل)فجير[ةه](?![ء-ي])/gi],
];
// Case-insensitive "ras al khaimah" too.
EMIRATE_RE.push(['R', /(?<![A-Za-z])ras[\s-]+al[\s-]*khaimah(?![A-Za-z])/gi], ['U', /(?<![A-Za-z])umm[\s-]+al[\s-]*quwain(?![A-Za-z])/gi]);

// ── premises, streets, buildings, landmarks, numbers ────────────────────────────────────────────────────────────
// What a number after a premises word must NOT be followed by: then it is a count or a size ("Villa 4 bedrooms", "Plot
// 500 m2", "Office 1 nos", "Unit 6 TR").
const NOT_COUNT = `(?![\\s\\-]*(?:nos?|nr|pcs|sets?|units?|bed|beds|bedrooms?|bathrooms?|rooms?|br|bhk|storey|storeys|stories|story|floors?|levels?|m2|m²|m3|sqm|sq\\.?\\s*m|sqft|sq\\.?\\s*ft|ft|m|mm|cm|tr|kw|kva|x|×|%|years?|yrs?|months?|weeks?|days?|hrs?|hours?|villas?|lots?|ls|people|persons|cars?|parking|seater|ton|tons|kg)(?![A-Za-z]))`;
const NUM = `(?:${ci('no')}\\.?|${ci('number')}|#|:)?\\s*[:.]?\\s*(?:[A-Z]{1,2}[\\-\\s]?)?\\d{1,5}(?:\\s*[\\-/]\\s*\\d{1,5})?[A-Z]?(?![\\w])(?![.,]\\d)${NOT_COUNT}`;
function ci(w: string) { return w.replace(/[A-Za-z]/g, (c) => `[${c.toUpperCase()}${c.toLowerCase()}]`); }
// "OFFICE 101", "SHOP 3", "WAREHOUSE 2" are room and unit tags on a drawing or a BOQ as often as an address (the CAD
// suites caught "OFFICE 101" boxed, 13 Nov 2026): those count only beside another place or running on to an emirate.
const STRONG_EN = ['villa', 'vila', 'apartment', 'apt', 'flat', 'plot', 'parcel', 'townhouse', 'penthouse'].map(ci).join('|');
const WEAK_EN = ['unit', 'building', 'bldg', 'tower', 'block', 'office', 'shop', 'showroom', 'warehouse', 'suite', 'house'].map(ci).join('|');
const PREMISES_EN = new RegExp(`(?<![A-Za-z])(?:${STRONG_EN})\\.?\\s*${NUM}`, 'g');
const PREMISES_WEAK_EN = new RegExp(`(?<![A-Za-z])(?:${WEAK_EN})\\.?\\s*${NUM}`, 'g');
const PREMISES_AR = new RegExp(`${AR_START}[وبل]?(?:فيلا|فيلّا|ڤيلا|شق[ةه]|قطع[ةه](?:\\s+[أا]رض)?|منزل|بيت)\\s*(?:رقم\\s*|ر\\.\\s*)?[:：]?\\s*${D}{1,5}(?:\\s*[\\-/]\\s*${D}{1,5})?(?!${D})`, 'g');
const PREMISES_WEAK_AR = new RegExp(`${AR_START}[وبل]?(?:مبنى|بناي[ةه]|برج|عمار[ةه]|مكتب|محل|معرض|مستودع|مخزن)\\s*(?:رقم\\s*)?[:：]?\\s*${D}{1,5}(?!${D})`, 'g');
/** A street with a number: "Street 14", "St. 14", "Road No. 2", "14th Street", "شارع 14", "شارع رقم ١٤". */
// Not "St 2" / "St 3" (surface preparation grades, ISO 8501-1) and not "RD10" (a regulation): "Street", "Road", "Rd." only.
const STREET_NO = new RegExp(`(?<![A-Za-z])(?:${ci('street')}|${ci('road')}|Rd\\.|${ci('lane')})\\s*(?:${ci('no')}\\.?|#)?\\s*\\d{1,3}[A-Z]?(?![\\w])(?![.,]\\d)${NOT_COUNT}|(?<![A-Za-z0-9])\\d{1,3}(?:st|nd|rd|th)\\s+(?:${ci('street')}|St\\.?|${ci('road')}|Rd\\.?)(?![A-Za-z])`
  + `|${AR_START}[وبف]?شارع\\s*(?:رقم\\s*)?${D}{1,4}(?!${D})`, 'g');
/** A named road: "Al Wasl Road", "Sheikh Zayed Road", "Al Khail Rd"; "Service Road", "Access Road" are scope. */
const ROAD_EN = /(?<![A-Za-z])((?:[A-Z][A-Za-z'’]+|al|bin|ibn)(?:[\s-]+(?:[A-Z][A-Za-z'’]+|al|bin|ibn)){0,3})\s+(?:Street|St\.|Road|Rd\.?|Highway|Hwy)(?![A-Za-z])/g;
const ROAD_GENERIC = new Set(['service', 'access', 'main', 'internal', 'ring', 'link', 'slip', 'site', 'temporary', 'the', 'new', 'existing', 'haul', 'approach', 'perimeter', 'private',
  'public', 'feeder', 'connecting', 'side', 'back', 'front', 'boundary', 'existing', 'proposed', 'future', 'car', 'parking', 'emergency', 'fire', 'bus', 'truck', 'cross', 'off', 'on',
  'a', 'an', 'and', 'to', 'of', 'for', 'from', 'with', 'by', 'at', 'in', 'near', 'opposite', 'behind', 'beside', 'via', 'along', 'no', 'one', 'two', 'any', 'each', 'all', 'our', 'your']);
const ROAD_AR = new RegExp(`${AR_START}[وبف]?شارع\\s+(?!(?:رئيسي|فرعي|داخلي|خدمة|خدمات|جانبي|عام|الخدمة|الخدمات|الرئيسي|الفرعي|الداخلي)${AR_END})(?:(?:الشيخ|الملك|الأمير|الامير)\\s+${AW}(?:\\s+بن\\s+${AW})?|ال${AW}(?:\\s+ال${AW})?|${AW}\\s+بن\\s+${AW})`, 'g');
/** A building named before Tower / Residence / Heights / Building: "Marina Gate 2 tower", "ZZ Palm IU8 Tower". */
// Not when a code, a rule or an authority follows: "Dubai Building Code", "Abu Dhabi building permit", "UAE building projects".
const BUILDING_EN = /(?<![A-Za-z0-9])((?:[A-Z][\w'’&-]*|\d{1,3})(?:\s+(?:[A-Z][\w'’&-]*|\d{1,3})){0,4})\s+(?:[Tt]owers?|TOWERS?|[Rr]esidences?|RESIDENCES?|[Hh]eights|HEIGHTS|[Bb]uilding|BUILDING|Bldg\.?|BLDG\.?)(?![A-Za-z])(?!\s+(?:[Cc]odes?|[Rr]egulations?|[Pp]ermits?|[Ss]tandards?|[Dd]epartment|[Aa]uthority|[Mm]aterials|[Cc]ontrol|[Ss]ervices|[Ii]nformation|[Mm]odel(?:l)?ing|[Mm]anagement|[Ss]ystems?|[Ww]orks|[Cc]ontractors?|[Mm]aintenance|[Ee]nvelope|[Hh]eight|[Ll]ine|[Aa]rea|[Pp]lot|[Ff]ootprint|[Pp]rojects?|[Ss]ector|[Ii]ndustry|[Tt]rade|[Ll]icen[cs]e|[Cc]ompletion|[Cc]ertificate)(?![A-Za-z]))/g;
/** Words before a building noun that say what KIND of thing it is, never which: "Cooling Tower", "Main Building". */
const BUILDING_GENERIC = new Set(['cooling', 'water', 'lighting', 'light', 'telecom', 'transmission', 'clock', 'control', 'main', 'office', 'new', 'existing', 'parking', 'car', 'staff',
  'service', 'services', 'school', 'admin', 'administration', 'the', 'this', 'that', 'our', 'your', 'a', 'an', 'each', 'all', 'guard', 'security', 'pump', 'plant', 'electrical',
  'mechanical', 'scaffold', 'scaffolding', 'crane', 'mobile', 'lattice', 'steel', 'concrete', 'tv', 'radio', 'cell', 'drying', 'wind', 'solar', 'storage', 'tank', 'residential',
  'commercial', 'apartment', 'apartments', 'villa', 'proposed', 'ceiling', 'room', 'floor', 'mounting', 'lift', 'stair', 'stairs', 'utility', 'substation', 'generator', 'rooftop',
  'roof', 'podium', 'retail', 'hotel', 'hospital', 'mosque', 'warehouse', 'factory', 'industrial', 'labour', 'labor', 'camp', 'site', 'temporary', 'permanent', 'adjacent', 'nearby',
  'twin', 'high', 'low', 'rise', 'mid', 'g', 'b', 'm', 'and', 'of', 'for', 'to', 'in', 'at', 'on', 'with', 'by', 'from', 'supply', 'install', 'installation', 'works', 'work', 'whole',
  'entire', 'complete', 'full', 'total', 'per', 'every', 'both', 'tall', 'glass', 'aluminium', 'aluminum', 'facade', 'green', 'smart', 'cladding', 'block', 'level', 'basement', 'heights',
  'tower', 'building', 'office', 'one', 'two', 'three', 'single', 'double', 'mixed', 'use', 'fit', 'out', 'fitout', 'interior', 'exterior', 'external', 'internal',
  'abu', 'dhabi', 'dubai', 'sharjah', 'ajman', 'fujairah', 'uae', 'emirates', 'emirate', 'international', 'national', 'federal', 'municipal', 'municipality', 'government', 'public', 'private']);
const BUILDING_AR = new RegExp(`${AR_START}[وبف]?(?:برج|بناي[ةه]|مبنى|عمار[ةه])\\s+(?!(?:الإدار[ةه]|الادار[ةه]|الرئيسي|الجديد|القديم|المكاتب|التبريد|المياه|الخدمات|السكني|التجاري|المشروع|الموقع|المدرس[ةه]|الحراس[ةه]|المولدات|الكهرباء|الاتصالات|المستودع|السكن)${AR_END})ال${AW}(?:\\s+ال${AW})?`, 'g');
/** A landmark after a cue word: "near Mall of the Emirates", "opposite Lulu Hypermarket", "behind ENOC petrol station". */
const LANDMARK_CUE_EN = `(?:${ci('near')}(?:\\s+${ci('to')})?|${ci('nearby')}|${ci('opposite')}(?:\\s+${ci('to')})?|${ci('opp')}\\.?|${ci('behind')}|${ci('next')}\\s+${ci('to')}|${ci('beside')}|${ci('besides')}|${ci('close')}\\s+${ci('to')}|${ci('in')}\\s+${ci('front')}\\s+${ci('of')}|${ci('across')}\\s+${ci('from')}|${ci('adjacent')}\\s+${ci('to')}|${ci('walking')}\\s+${ci('distance')}\\s+${ci('from')})`;
const LANDMARK_EN = new RegExp(`(?<![A-Za-z])${LANDMARK_CUE_EN}\\s+(?:${ci('the')}\\s+)?((?:[A-Z0-9][\\w'’&.-]*)(?:\\s+(?:of\\s+the|of|the|al|bin|&|[A-Z0-9][\\w'’&.-]*|mall|metro|station|mosque|masjid|school|hospital|clinic|park|tower|hotel|centre|center|market|supermarket|hypermarket|souq|souk|roundabout|signal|bridge|beach|club|plaza|circle|interchange|gate|petrol|pump|building|stadium|airport|university|college|academy|church|embassy|bank|branch|stop)(?![A-Za-z])){0,6})`, 'g');
const LANDMARK_WORDS = /\b(?:mall|metro|station|mosque|masjid|school|academy|college|university|hospital|clinic|park|tower|towers|hotel|centre|center|market|supermarket|hypermarket|souq|souk|roundabout|r\/a|signal|bridge|beach|club|plaza|circle|interchange|gate|petrol|pump|enoc|adnoc|eppco|emarat|carrefour|lulu|spinneys|choithrams|coop|co-op|nesto|safeer|waitrose|airport|port|terminal|stadium|building|bank|church|temple|embassy|consulate|police|garden|gardens|lake|canal|creek|corniche|compound|community|district|village|city|island|bay|marina|square|walk|boulevard|residence|residences|heights|villas)\b/i;
const LANDMARK_AR = new RegExp(`${AR_START}(?:بالقرب\\s+من|قريب\\s+من|قرب|مقابل|خلف|وراء|بجانب|جنب|بجوار|أمام|امام|جوار|بمحاذا[ةه])\\s+(?:(?:مول|مركز|مسجد|جامع|مدرس[ةه]|مستشفى|عياد[ةه]|محط[ةه]|مترو|دوار|دوّار|برج|فندق|سوق|حديق[ةه]|جسر|شاطئ|نادي|جامع[ةه]|جمعي[ةه]|كارفور|لولو|بنك|مصرف|إشار[ةه]|اشار[ةه])${AR_END}(?:\\s+${AW}){0,3})`, 'g');
/** A Makani number (Dubai's building locator): ten digits after "Makani" / "مكاني", spaced or not. */
const MAKANI = new RegExp(`(?<![A-Za-z])${ci('makani')}(?:\\s*(?:${ci('no')}\\.?|${ci('number')}|#))?\\s*[:.\\-]?\\s*${D}{5}\\s?${D}{5}(?!${D})|${AR_START}مكاني(?:\\s*رقم)?\\s*[:：]?\\s*${D}{5}\\s?${D}{5}(?!${D})`, 'g');
/** Map coordinates inside the UAE (latitude 22-26 N, longitude 51-56 E), decimal or labelled. */
// A comma, semicolon or slash between the two, or a N / ° marker: "Price 25.1123 55.2001 per kg" is two figures.
const COORDS = /(?<![\d.])(?:(?<![A-Za-z])[Nn]\s*)?2[2-6]\.\d{3,8}\s*°?\s*[Nn]?\s*[,;/]\s*(?:[Ee]\s*)?5[1-6]\.\d{3,8}\s*°?\s*[Ee]?(?![\d.])|(?<![\d.])2[2-6]\.\d{3,8}\s*(?:°\s*)?[Nn]\s+5[1-6]\.\d{3,8}\s*(?:°\s*)?[Ee](?![A-Za-z])|(?<![\d.])2[2-6]\s*°\s*\d{1,2}\s*['′]\s*(?:\d{1,2}(?:\.\d+)?\s*["″])?\s*[Nn]?[\s,]*5[1-6]\s*°\s*\d{1,2}\s*['′]\s*(?:\d{1,2}(?:\.\d+)?\s*["″])?\s*[Ee]?/g;
/** A what3words address: "///filled.count.soap", "what3words: filled.count.soap". */
const W3W = /(?:\/\/\/|(?<![A-Za-z])what\s*3\s*words\s*[:\-]?\s*\/{0,3})[a-z]{2,}\.[a-z]{2,}\.[a-z]{2,}(?![A-Za-z])|(?<![\w/])\/\/\/[a-z]{2,}\.[a-z]{2,}\.[a-z]{2,}/gi;
/** An industrial area by number with no community before it: "Industrial Area 6" (Sharjah, Ajman and Al Ain have them). */
const IND_AREA = /(?<![A-Za-z])(?:Al\s+[A-Z][a-z]+\s+)?(?:Industrial|INDUSTRIAL)\s+(?:Area|AREA)\s*(?:No\.?\s*)?\d{0,2}(?![\d])|(?<![ء-ي])(?:ال)?منطق[ةه]\s+الصناعي[ةه]\s*${D}{0,2}/g;

// ── finding and grouping ─────────────────────────────────────────────────────────────────────────────────────────
type Span = { s: number; e: number; keys: EmirateKey[] | null; ar: boolean; cue?: boolean; landmark?: boolean; weak?: boolean };
const isAr = (t: string) => /[؀-ۿ]/.test(t);
/** A place cue right before a span: "in", "at", "near", "Location:", "في", "منطقة"; or a joined Arabic preposition. */
const CUE_BEFORE_EN = /(?:\b(?:in|at|near|inside|located|based|around|area|community|villa|site|address|location|shop|office|warehouse|showroom|branch|district)(?:\s+the)?|[:])\s*$/i;
const CUE_BEFORE_AR = /(?:في|من|قرب|عند|إلى|الى|منطق[ةه]|حي|بمنطق[ةه]|موقع|العنوان|[:：])\s*$/;
const SEP = /^[\s,،;\-–—/|&]*(?:(?:and|in|at|of|و|في)[\s,،\-–—]*)?$/i;
const SEP_STRICT = /^[\s,،\-–—/|]*$/;

function emirateTokens(t: string): { s: number; e: number; key: EmirateKey }[] {
  const out: { s: number; e: number; key: EmirateKey }[] = [];
  for (const [key, re] of EMIRATE_RE) for (const m of t.matchAll(new RegExp(re.source, re.flags))) out.push({ s: m.index!, e: m.index! + m[0].length, key });
  return out;
}
/** Every place span below the emirate in `t`, unmerged (exported for the residual scan and the tests). */
export function placeSpans(text: unknown): Span[] {
  const t = String(text ?? '');
  if (!t.trim()) return [];
  const raw: Span[] = [];
  const add = (re: RegExp, keys: EmirateKey[] | null, more: Partial<Span> = {}, check?: (m: RegExpMatchArray) => [number, number] | null) => {
    for (const m of t.matchAll(new RegExp(re.source, re.flags))) {
      if (!m[0].trim()) continue;
      const sp = check ? check(m) : [m.index!, m.index! + m[0].length] as [number, number];
      if (sp) raw.push({ s: sp[0], e: sp[1], keys, ar: isAr(m[0]), ...more });
    }
  };
  for (const en of ENTRIES) add(en.re, en.keys, { cue: en.cue });
  add(PREMISES_EN, null); add(PREMISES_AR, null); add(PREMISES_WEAK_EN, null, { weak: true }); add(PREMISES_WEAK_AR, null, { weak: true });
  // A house number and its street, anywhere ("4209 COUNTY ROAD 24 1/2", identity_contacts): one place, not "ROAD 24" alone.
  add(STREET_ADDRESS, null); add(STREET_NO, null); add(MAKANI, null); add(COORDS, null); add(W3W, null); add(IND_AREA, null); add(LANDMARK_AR, null, { landmark: true });
  add(ROAD_EN, null, {}, (m) => {
    // Trim leading ordinary words ("Access to Al Wasl Road" keeps "Al Wasl Road"); a road named only by them is scope.
    const words = [...m[1].matchAll(/\S+/g)];
    let i = 0; while (i < words.length && ROAD_GENERIC.has(words[i][0].toLowerCase())) i++;
    if (i >= words.length || words.slice(i).every((w) => /^(?:al|bin|ibn)$/i.test(w[0]))) return null;
    return [m.index! + words[i].index!, m.index! + m[0].length];
  });
  add(ROAD_AR, null);
  add(BUILDING_EN, null, {}, (m) => {
    // Read the name backwards from the noun and stop at the first word that says what kind of building it is.
    const words = [...m[1].matchAll(/\S+/g)];
    let i = words.length; while (i > 0 && !BUILDING_GENERIC.has(words[i - 1][0].toLowerCase())) i--;
    const kept = words.slice(i);
    if (!kept.length || kept.every((w) => /^\d+$/.test(w[0]))) return null;
    return [m.index! + kept[0].index!, m.index! + m[0].length];
  });
  add(BUILDING_AR, null);
  add(LANDMARK_EN, null, { landmark: true }, (m) => {
    const name = m[1];
    // Two Title-Case words make a name ("Lamcy Plaza" is, "208 L" and "FR" are not).
    const caps = (name.match(/(?<![A-Za-z])[A-Z][a-z][\w'’&.-]*/g) || []).length;
    if (!(LANDMARK_WORDS.test(name) || caps >= 2 || ENTRIES.some((en) => !en.ar && new RegExp(en.re.source, en.re.flags.replace('g', '')).test(name)))) return null;
    return [m.index!, m.index! + m[0].length];
  });
  // Longest first; a span inside a longer one goes ("Dubai Marina" over "Marina", "Al Quoz Industrial Area 3" over "Industrial Area 3").
  raw.sort((a, b) => a.s - b.s || b.e - a.e);
  const spans: Span[] = [];
  for (const r of raw) {
    const last = spans[spans.length - 1];
    if (last && r.s < last.e) { if (r.e > last.e) { last.e = r.e; last.keys = last.keys ?? r.keys; } else if (!last.keys && r.keys) last.keys = r.keys; if (!r.cue) last.cue = false; if (!r.weak) last.weak = false; continue; }
    spans.push({ ...r });
  }
  // An emirate word INSIDE a span is the span's ("Dubai Marina"): emirate tokens outside spans are what stays.
  const emirates = emirateTokens(t).filter((x) => !spans.some((s) => x.s >= s.s && x.e <= s.e));
  const nextTo = (a: Span, b: { s: number; e: number }, re = SEP) => (a.e <= b.s ? re.test(t.slice(a.e, b.s)) : b.e <= a.s ? re.test(t.slice(b.e, a.s)) : true);
  // A cue-only name ("Marina", "Jumeirah", "Al Ain") or a weak premises ("Unit 12", "Tower 2") counts only after a place
  // cue or next to another place or an emirate.
  const accepted = spans.map((s) => !s.cue && !s.weak);
  for (const [i, s] of spans.entries()) {
    if (accepted[i]) continue;
    const before = t.slice(Math.max(0, s.s - 30), s.s);
    if (s.cue && !s.weak && (s.ar ? CUE_BEFORE_AR : CUE_BEFORE_EN).test(before)) accepted[i] = true;
  }
  for (let grew = true; grew;) {
    grew = false;
    for (const [i, s] of spans.entries()) {
      if (accepted[i]) continue;
      if (spans.some((o, j) => accepted[j] && j !== i && nextTo(s, o, SEP_STRICT)) || emirates.some((x) => nextTo(s, x, SEP_STRICT))
        || (s.weak && (t.slice(s.e).match(CHAIN)?.[0] ?? '') !== '')) { accepted[i] = grew = true; }
    }
  }
  return spans.filter((_s, i) => accepted[i]);
}

/** A premises number runs on to the emirate through the address parts after it ("Shop 5, Foo Plaza, Dubai"). */
const CHAIN = new RegExp(`^(?:\\s*[,،\\-–]\\s*[A-Z0-9\\u0600-\\u06FF][^,،;\\n\\-–]{0,40}){0,4}?(?=\\s*[,،\\-–]\\s*(?:Dubai|Sharjah|Abu\\s*Dhabi|Ajman|Fujairah|Ras\\s+Al\\s*Khaimah|Umm\\s+Al\\s*Quwain|دبي|الشارق[ةه]|[أا]بو\\s*ظبي|عجمان|الفجير[ةه]|ر[أا]س\\s+الخيم[ةه]|[أا]م\\s+القيوين)(?![A-Za-z\\u0621-\\u064A]))`, 'i');
const PREMISES_START = new RegExp(`^(?:${STRONG_EN}|${WEAK_EN})|^[وبل]?(?:فيلا|شق[ةه]|محل|معرض|مستودع|مكتب|مبنى|بناي[ةه]|برج)`);

/**
 * Every place below the emirate in `text` reduced to the emirate (see the header). `rep` is the caller's mark for a place
 * that names no emirate (a string, or a function of the removed text); a function is also told about every place reduced
 * to its emirate, so a caller that records what it took (masked_terms) records these too.
 */
export function reducePlaces(text: unknown, rep: string | ((m: string) => string) = ''): string {
  const t = String(text ?? '');
  const spans = placeSpans(t);
  if (!spans.length) return t;
  // Chain a premises number through the address parts that follow it, up to an emirate.
  for (const s of spans) if (PREMISES_START.test(t.slice(s.s, s.e))) { const m = t.slice(s.e).match(CHAIN); if (m && m[0]) s.e += m[0].length; }
  // Group spans that touch (only separators between them).
  spans.sort((a, b) => a.s - b.s);
  const groups: Span[][] = [];
  for (const s of spans) {
    const g = groups[groups.length - 1], last = g?.[g.length - 1];
    if (last && (s.s <= last.e || SEP.test(t.slice(last.e, s.s)))) g.push(s); else groups.push([s]);
  }
  const emirates = emirateTokens(t).filter((x) => !spans.some((s) => x.s >= s.s && x.e <= s.e));
  const named = new Set(emirates.map((x) => x.key));
  let out = '', at = 0;
  for (const g of groups) {
    const gs = g[0].s, ge = Math.max(...g.map((s) => s.e));
    if (gs < at) continue;
    const whole = t.slice(gs, ge);
    const after = emirates.find((x) => x.s >= ge && SEP_STRICT.test(t.slice(ge, x.s)));
    const before = [...emirates].reverse().find((x) => x.e <= gs && SEP_STRICT.test(t.slice(x.e, gs)));
    const tell = () => { if (typeof rep === 'function') rep(whole); };
    // The group's emirates: each one its places name, or (Al Nahda: Dubai or Sharjah) the one the text names.
    const keys = g.map((s) => s.keys).filter(Boolean) as EmirateKey[][];
    const own: EmirateKey[] = [];
    for (const k of keys) { const pick = k.length === 1 ? k[0] : (k.filter((x) => named.has(x)).length === 1 ? k.filter((x) => named.has(x))[0] : null); if (pick && !own.includes(pick)) own.push(pick); }
    // Next to an emirate its places belong to (or that names none): removed, the emirate stays. "Deira, Sharjah" is two.
    const fits = (x: { key: EmirateKey }) => !own.length || own.every((k) => k === x.key);
    if (after && fits(after)) { out += t.slice(at, gs); at = after.s; tell(); continue; }
    if (before && fits(before)) { out += t.slice(at, before.e); at = ge; tell(); continue; }
    const ar = isAr(whole);
    const shown = own.filter((k) => k !== after?.key && k !== before?.key);
    if (shown.length) {
      const names = shown.map((k) => (ar ? EMIRATE_NAME[k].ar : EMIRATE_NAME[k].en));
      const name = names.length === 1 ? names[0] : names.slice(0, -1).join(', ') + (ar ? ' و' : ' and ') + names[names.length - 1];
      // "villa near Mall of the Emirates" reads "villa in Dubai", not "villa Dubai".
      const pre = t.slice(Math.max(0, gs - 6), gs);
      const lead = g[0].landmark && !(ar ? /في\s*$/.test(pre) : /\b(?:in|at)\s*$/i.test(pre)) ? (ar ? 'في ' : 'in ') : '';
      out += t.slice(at, gs) + lead + name; at = ge; tell(); continue;
    }
    out += t.slice(at, gs) + (typeof rep === 'string' ? rep : rep(whole)); at = ge;
  }
  return (out + t.slice(at)).replace(/[ \t]{2,}/g, ' ').replace(/\s+([,.;:،])/g, '$1').replace(/([,،])\s*(?=[,،])/g, '');
}
