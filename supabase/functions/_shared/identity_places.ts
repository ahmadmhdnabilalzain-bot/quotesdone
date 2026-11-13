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
// THE CODE LAYER IS THE HIGH-PRECISION BACKSTOP (coordinator, 13 Nov 2026, after the independent review measured 114 of
// 411 trade sentences damaged by the first version): a gazetteer name is a place unless a colour, range or material is
// beside it ("Marina blue", "Hatta stone"); a cue-only name needs a LOCATION cue or a sector number; a building, a road,
// a street number and the weak premises words count only beside another place or in an address running to an emirate;
// a landmark only as a gazetteer place or a known chain after near / opposite / behind; a delivery term ("CIF Jebel Ali")
// and a list of areas served pass as written; "ex works <area>" crosses as "ex works, <emirate>".
// WHAT NO RULE CAN SEE (left to the second reader): a community, building or landmark nobody listed; a place in prose
// ("the villa behind the mosque on the corner"); a bare name with no cue ("ديرة", "Deira"); a number in words ("villa
// fifteen"); a misspelling outside the variants below; "Meadows 2 villa", "JVC, District 12".
import { STREET_ADDRESS } from './identity_contacts.ts';
const D = '[0-9٠-٩۰-۹]';
/** A run of three or more blanks AFTER text on its line becomes two spaces; a line's leading indent is kept as written.
 *  Two, not one: the phone shapes refuse a number followed by ONE space and more digits (a BOQ row), so column-spaced
 *  "Sales contact    050 123 4567    12,500.00" must keep a boundary (third review of 13 Nov 2026: one space reopened it).
 *  What still changes where nothing is removed: a gap of 3+ blanks inside a line prints as two spaces. */
export const capBlanks = (s: string) => s.replace(/(?<=[^\s])[ \t\u00a0\u2000-\u200a\u202f\u205f\u3000]{3,}/g, '  ');
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
  ['D', 'Al Barsha|Barsha|AlBarsha'], ['D', 'Barsha Heights|~^TECOM|~Tecom'], ['D', 'Al Quoz|Quoz|AlQuoz'], ['D', 'Al Qusais|Qusais|Al Ghusais'], ['D', '~Deira'], ['D', 'Bur Dubai'],
  ['D', 'Al Rigga|Rigga'], ['D', 'Port Saeed'], ['D', 'Hor Al Anz'], ['D', 'Abu Hail'], ['D', 'Al Muteena|Muteena'], ['D', 'Al Murar'], ['D', 'Al Baraha'], ['D', 'Al Mamzar|Mamzar'],
  ['D', 'Al Twar|Twar'], ['DS', 'Al Nahda|Nahda|Al Nahdah'], ['D', 'Muhaisnah|Muhaisna|Mhaisnah|Al Muhaisnah'], ['D', 'Al Mizhar|Mizhar'], ['D', 'Mirdif|Mirdiff|Mirdaf|Uptown Mirdif'],
  ['D', 'Al Warqa|Warqa|Al Warqaa'], ['D', 'Nad Al Sheba|Nad Al Shiba|Nad Al Hamar|Nad Al Hammar'], ['DJ', 'Al Rashidiya|Rashidiya|Rashidiyah|Al Rashidiyah'],
  ['D', 'Al Garhoud|Garhoud|Garhood|Al Garhood|Al Qarhoud'], ['D', 'Umm Ramool'], ['D', 'Al Khawaneej|Khawaneej'], ['D', 'Al Aweer|Aweer'], ['D', 'Ras Al Khor'],
  ['D', 'Al Jaddaf|Jaddaf'], ['D', 'Oud Metha'], ['D', 'Umm Hurair'], ['D', 'Al Mankhool|Mankhool'], ['D', 'Al Satwa|Satwa'], ['D', 'Al Jafiliya|Jafiliya|Jafiliyah|Al Jafiliyah'],
  ['D', 'Al Bada|Al Badaa'], ['D', '~Al Wasl'], ['D', '~Al Safa'], ['D', 'Umm Suqeim|Umm Suqaim|Umm Sequim'], ['D', 'Al Manara'], ['D', 'Al Sufouh|Sufouh'], ['D', 'Al Hudaiba'],
  ['D', 'Al Raffa'], ['D', 'Al Fahidi'], ['D', 'Al Shindagha|Shindagha'], ['D', "Za'abeel|Zabeel|Zaabeel"], ['D', 'Business Bay'], ['D', 'Downtown Dubai|~^Downtown'], ['D', '~^DIFC'],
  ['D', 'World Trade Centre|World Trade Center|Trade Centre'], ['D', 'Al Kifaf'], ['D', 'City Walk'], ['D', 'Dubai Marina'], ['D', '~Marina'],
  ['D', 'Jumeirah Lakes Towers|^JLT'], ['D', 'Jumeirah Beach Residence|^JBR'], ['D', 'Jumeirah Village Circle|~^JVC'], ['D', 'Jumeirah Village Triangle|~^JVT'],
  ['D', 'Jumeirah Islands|Jumeirah Park|Jumeirah Golf Estates|Jumeirah Heights|Jumeirah Bay|Jumeira Bay'], ['D', 'Palm Jumeirah|Palm Jumeira|Palm Jebel Ali|^The Palm'],
  ['D', '~Jumeirah|~Jumeira|~Jumera'], ['D', 'Bluewaters|Bluewaters Island'], ['D', 'Emirates Hills|Emirates Living'], ['D', '^The Meadows|^The Springs|^The Lakes|^The Greens|^The Views|^The Valley|~^Meadows|~^Springs|~^Greens|~^Lakes'],
  ['D', 'Arabian Ranches'], ['D', '~Al Barari'], ['D', 'Dubai Hills Estate|Dubai Hills'], ['D', 'Mohammed Bin Rashid City|Mohammed bin Rashid City|MBR City'], ['D', 'Meydan'],
  ['D', 'Sobha Hartland'], ['D', 'Al Furjan|Furjan'], ['D', 'Discovery Gardens'], ['D', 'Jebel Ali|Jabal Ali'], ['D', 'Dubai Investment Park|Dubai Investments Park|~^DIP'],
  ['D', 'Dubai Industrial City|Dubai Industrial Park'], ['D', 'Dubai South'], ['D', 'Dubai World Central|~^DWC'], ['D', 'Dubai Silicon Oasis|Silicon Oasis|~^DSO'],
  ['D', 'International City'], ['D', 'Dubai Sports City|Sports City'], ['D', 'Motor City|Dubai Motor City'], ['D', 'Dubai Production City|^IMPZ'], ['D', 'Dubai Studio City|Studio City'],
  ['D', '~Arjan'], ['D', 'Dubailand'], ['D', 'Town Square'], ['D', 'Remraam'], ['D', 'Mudon'], ['D', 'Damac Hills|DAMAC Hills|Damac Lagoons|DAMAC Lagoons|~Akoya'],
  ['D', 'Tilal Al Ghaf'], ['D', '~Villanova'], ['D', 'Al Warsan|Warsan'], ['D', '~Liwan'], ['D', 'Wadi Al Safa'], ['D', 'Dubai Festival City|Festival City'],
  ['D', 'Dubai Creek Harbour|Creek Harbour|Dubai Creek Harbor'], ['D', 'Culture Village'], ['D', 'Al Habtoor City'], ['D', 'Dubai Media City|Media City'], ['D', 'Dubai Internet City|Internet City'],
  ['D', 'Knowledge Village|Dubai Knowledge Park'], ['D', 'Dubai Healthcare City|Healthcare City'], ['D', 'Dubai Academic City|Academic City'], ['D', 'Dubai Design District'],
  ['D', 'Al Khail'], ['D', '~Hatta'], ['D', 'Al Lisaili|Lisaili'], ['D', 'Al Marmoom'], ['D', 'Lehbab'], ['DS', 'Al Hamriya|Al Hamriyah|Hamriyah'], ['DA', 'Al Mushrif|Mushrif'],
  ['D', 'Al Khabaisi'], ['D', 'Al Muraqqabat|Muraqqabat'], ['D', 'Dubai Maritime City|Dubai Harbour|Dubai Waterfront'], ['D', 'La Mer'], ['D', 'Pearl Jumeirah'], ['D', 'Port Rashid'],
  ['D', 'Dubai Airport Free Zone|^DAFZA'], ['D', 'Jebel Ali Free Zone|~^JAFZA'], ['D', 'Dubai Outsource City|Dubai Science Park'], ['DA', '~Al Karama|~Karama|~Al Karamah|~Karamah'],
  ['D', 'Al Qudra'], ['D', 'Dubai Waterfront'], ['D', 'Al Sufouh'], ['D', 'Umm Al Sheif|Umm Al Sheef'], ['D', 'Al Quoz Creative Zone'],
  // ── Sharjah
  ['S', 'Al Majaz|Majaz'], ['S', 'Al Qasba|Qasba|Al Qasbaa'], ['S', 'Al Khan'], ['S', "Al Taawun|Taawun|Al Taawon|Al Ta'awun"], ['S', 'Al Qasimia|Qasimia|Al Qasimiya|Al Qasimiyah'],
  ['S', 'Al Nabba'], ['S', 'Muwaileh|Muwailih|Muweilah|Al Muwaileh'], ['S', 'University City'], ['S', 'Al Rahmaniya|Rahmaniya|Al Rahmaniyah'], ['S', 'Al Zahia|Al Zahiya'],
  ['S', 'Aljada'], ['S', 'Tilal City'], ['S', 'Al Yarmook'], ['S', 'Al Ghuwair'], ['S', '~Rolla'], ['S', '~Al Soor'], ['S', '~Al Jubail'], ['S', 'Al Layyeh'], ['S', 'Al Heera'],
  ['SA', 'Al Khalidiya|Al Khalidiyah|Khalidiya|Khalidiyah'], ['S', '~Al Musalla'], ['S', "Al Sajaa|Al Saja'a|Sajja|Sajaa|Al Sajja"], ['S', 'Maliha'], ['S', 'Al Riqa'], ['S', 'Al Fisht'],
  ['S', 'Halwan'], ['S', 'Al Ramtha'], ['S', 'Al Mirgab'], ['S', 'Abu Shagara'], ['S', 'Al Butina'], ['S', '~Al Sharq'], ['S', 'Al Azra'], ['S', '~Al Falaj'], ['S', 'Samnan'],
  ['S', 'Al Jazzat'], ['S', 'Al Suyoh'], ['S', '~Hoshi'], ['S', "~Al Rifa'a|~Al Rifaa"], ['S', 'Kalba'], ['S', 'Khor Fakkan|Khorfakkan|Khor Fakan'], ['S', 'Dibba Al Hisn'],
  ['S', 'Al Dhaid|Dhaid'], ['S', 'Mleiha'], ['S', 'Al Madam'], ['S', 'Al Mujarrah'], ['S', '~Al Gharb'], ['S', 'Al Ramla'], ['S', 'Al Qadisiya'], ['S', 'Al Fayha'],
  ['S', 'Al Sabkha'], ['S', 'Al Shuwaihean'], ['S', 'Al Khezamia'], ['S', 'Al Tai'], ['S', 'Sharjah Airport Free Zone|SAIF Zone|^SAIF'], ['S', 'Hamriyah Free Zone'],
  // ── Abu Dhabi (and its Al Ain region)
  ['A', 'Khalifa City'], ['A', 'Mohammed Bin Zayed City|Mohammed bin Zayed City|MBZ City|~^MBZ'], ['A', 'Mussafah|Musaffah|Mussaffah|Musafah|Al Mussafah|^ICAD'],
  ['A', 'Al Reem Island|Reem Island'], ['A', 'Saadiyat Island|Saadiyat'], ['A', 'Yas Island'], ['A', 'Al Raha Beach|Raha Beach|Al Raha Gardens'], ['A', '~Al Raha'], ['A', 'Al Reef'],
  ['A', 'Al Shamkha|Shamkha'], ['A', '~Al Falah'], ['A', 'Baniyas|Bani Yas'], ['A', 'Shakhbout City|Shakhbout'], ['A', 'Al Bateen'], ['A', 'Al Nahyan'], ['A', '~Al Wahda'],
  ['A', 'Al Manhal'], ['A', 'Tourist Club Area|Tourist Club'], ['A', 'Al Zahiyah'], ['A', 'Al Maryah Island|Maryah Island'], ['A', 'Al Muroor|Muroor'], ['A', 'Madinat Zayed'],
  ['A', 'Mina Zayed'], ['A', 'Al Danah'], ['A', 'Al Markaziyah'], ['AJ', 'Al Rawdah|Al Rawda'], ['A', 'Al Maqtaa'], ['A', 'Bain Al Jessrain|Between Two Bridges'], ['A', 'Al Rahba'],
  ['A', 'Al Samha'], ['A', 'Al Wathba'], ['A', 'Masdar City|~Masdar'], ['A', 'Zayed City'], ['A', 'Ruwais|Al Ruwais'], ['A', 'Ghayathi'], ['A', '~Liwa'], ['A', 'Al Dhafra|Western Region'],
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
  ['R', 'Al Dhait'], ['R', '~Julphar'], ['R', 'Al Hamra Village'], ['R', '~Al Hamra'], ['R', 'Mina Al Arab'], ['R', 'Al Marjan Island|Marjan Island'], ['R', 'Khuzam'], ['R', 'Al Qusaidat'],
  ['R', 'Seih Al Uraibi|Al Uraibi'], ['R', 'Al Jazirah Al Hamra|Al Jazeera Al Hamra'], ['R', 'Al Rams'], ['R', 'Digdaga|Digdagga'], ['R', 'Al Mairid'], ['R', 'Khatt'], ['R', '~Shamal'],
  ['R', 'Al Mamourah'], ['R', 'Dafan Al Nakheel'], ['R', 'Ghalilah'], ['R', 'Al Ghail'], ['R', 'Al Kharran'], ['R', 'Al Hamraniyah'], ['R', 'Al Hulaila'],
  // ── Umm Al Quwain
  ['U', '~Al Salamah|~Salamah'], ['U', '~Al Raas'], ['U', 'Al Ramlah'], ['U', '~Al Haditha'], ['U', '~Al Raudah'], ['U', 'Al Humrah'], ['U', 'Falaj Al Mualla'], ['U', 'Al Sinniyah'],
  ['U', '~Al Maidan'],
  // ── Fujairah
  ['F', 'Dibba Al Fujairah|Dibba Fujairah'], ['FS', '~Dibba'], ['F', 'Mirbah'], ['F', 'Qidfa'], ['F', 'Al Faseel|Faseel'], ['F', 'Sakamkam'], ['F', 'Al Gurfa'], ['F', '~Masafi'],
  ['F', 'Al Bidya|Bidiyah|Al Badiyah'], ['F', 'Murbeh'], ['F', '~Al Hail'], ['F', 'Madhab'], ['F', 'Al Taween'], ['F', 'Al Aqah|Aqah'], ['F', 'Dadna'],
  // ── landmarks known by name (each one is in exactly one emirate)
  ['D', 'Mall of the Emirates|Mall of Emirates|~^MOE'], ['D', 'Dubai Mall'], ['D', 'Burj Khalifa'], ['D', 'Burj Al Arab'], ['D', 'Ibn Battuta Mall|Ibn Battuta'], ['D', 'Mirdif City Centre'],
  ['D', 'Deira City Centre|City Centre Deira'], ['D', 'Global Village'], ['D', 'Dragon Mart'], ['D', 'Expo City|Expo 2020 site'], ['D', 'Dubai Frame'], ['D', 'Burjuman|BurJuman|Burjuman Centre'], ['D', 'Al Ghurair Centre|Al Ghurair Center|Dubai Hospital|Rashid Hospital|Wafi Mall|Wafi City|Lamcy Plaza|City Centre Mirdif|Dubai Festival City Mall'], ['A', 'Shabiya|Shabiyah|Shabia'], ['D', 'Mohammed Bin Rashid Boulevard|Mohammed bin Rashid Boulevard'], ['DA', 'Sheikh Zayed Road|Shaikh Zayed Road|^SZR'],
  ['D', 'Hessa Street|Al Khail Road|Al Wasl Road|Jumeirah Beach Road|Al Sufouh Road|Umm Suqeim Road|Al Barsha Road'], ['DS', 'Al Ittihad Road|Ittihad Road'], ['D', 'Atlantis The Palm'],
  ['A', 'Yas Mall'], ['A', 'Ferrari World'], ['A', 'Sheikh Zayed Grand Mosque'], ['A', 'Al Wahda Mall'], ['A', 'Abu Dhabi Mall'], ['A', 'Louvre Abu Dhabi'], ['A', 'Emirates Palace'],
  ['S', 'Sahara Centre|Sahara Center'], ['S', 'Mega Mall'], ['S', 'City Centre Sharjah'], ['J', 'Ajman City Centre'], ['R', 'Manar Mall'], ['R', 'RAK Mall'], ['F', 'Fujairah City Centre'],
];
const GAZ_AR: [string, string][] = [
  ['D', 'البرشاء|البرشا'], ['D', 'القوز'], ['D', 'القصيص'], ['D', 'ديرة'], ['D', 'بر دبي'], ['D', 'هور العنز'], ['D', 'أبو هيل'], ['D', 'المطينة'], ['D', 'الممزر'], ['D', 'الطوار'],
  ['DS', 'النهدة'], ['D', 'محيصنة'], ['D', 'المزهر'], ['D', 'مردف'], ['D', 'الورقاء'], ['D', 'ند الشبا|ند الحمر'], ['DJ', 'الراشدية'], ['D', 'القرهود'], ['D', 'الخوانيج'],
  ['D', 'العوير'], ['D', 'رأس الخور'], ['D', 'الجداف'], ['D', 'عود ميثاء'], ['D', 'المنخول'], ['D', 'السطوة'], ['D', 'الجافلية'], ['D', '~الوصل'], ['D', '~الصفا'], ['D', 'جميرا|جميرة|الجميرا|الجميرة'],
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
/** Arabic letter variants: any alef, ة/ه, final ي/ى, a tatweel between any two letters ("البرشـاء"); one or more spaces. */
const arForm = (v: string) => v.split(/\s+/).map((w) => [...w].map((c, i, a) => (/[أإآا]/.test(c) ? '[أإآا]' : /[ةه]/.test(c) && i === a.length - 1 ? '[ةه]' : /[يى]/.test(c) && i === a.length - 1 ? '[يى]' : c)).join('ـ*')).join('\\s+');
const keyEn = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, '');
const keyAr = (s: string) => s.replace(/[ـ\s]/g, '').replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي');
type Entry = { keys: EmirateKey[]; cue: boolean };
// A numbered or named sub-area belongs to the place: "Al Barsha 2", "Barsha2", "Al Barsha South", "Khalifa City A", "Al
// Quoz Industrial Area 3". A single letter only standing alone ("Al Quoz A/C units" keeps its A/C). Group 2 = a number.
// A number after a place name followed by one of these is a quantity, not a sector ("Deira 3 piece set", "Greens 4 trays").
const COUNT_WORDS = 'nos?|pcs|pieces?|sets?|units?|villas?|bed|br|bhk|m2|sqm|m|mm|cm|kw|tr|x|seater|seats?|doors?|coats?|years?|kg|g|l|ltr|ml|litres?|liters?|bags?|trays?|packs?|boxes|box|rolls?|sheets?|bottles?|cans?|cartons?|pairs?|layers?|tons?|%';
const SUB_EN = `(?:[\\s\\-]+(?:Industrial(?:\\s+Area)?(?:[\\s\\-]*(?:No\\.?\\s*)?\\d{1,2}(?![\\d.,]\\d))?|Ind\\.?\\s*Area(?:[\\s\\-]*\\d{1,2})?|(?:South|North|East|West|First|Second|Third|1st|2nd|3rd)(?![A-Za-z])|[A-D](?![\\w/&'’-]))|([\\s\\-]*)(\\d{1,2})(?![\\d.,]\\d)(?![\\s\\-]*(?:${COUNT_WORDS})(?![A-Za-z])))?`;
const SUB_AR = `(?:(\\s*)(${D}{1,2})(?!${D})|\\s*(?:الأولى|الاولى|الثانية|الثالثة|الأول|الاول|الثاني|الثالث|الجنوبية|الشمالية|جنوب|شمال|الصناعية(?:\\s*${D}{1,2})?))?`;
// Names whose every word is an ordinary English word ("International City", "City Walk", "Dubai Hills", "Town Square")
// are a place only in Title Case or capitals: "international standards", "city walk paving pattern" are not.
const ORDINARY = new Set(('international city global village walk town square media internet sports motor studio academic healthcare festival university garden gardens discovery '
  + 'business bay emirates hills living lakes springs meadows greens views valley palm the marina downtown trade centre center world creek harbour harbor culture knowledge science park '
  + 'industrial investment investments south silicon oasis dubai abu dhabi sharjah ajman ras al khaimah fujairah maritime waterfront outsource design district airport free zone mall '
  + 'tourist club area western region island between two bridges port of frame expo site village emirates arabian ranches heights tower towers lagoons estate jumeirah golf estates '
  + 'beach residence islands lakes uptown road street boulevard').split(' '));
const EN_CI: string[] = [], EN_CS: string[] = [], AR_ALTS: string[] = [];
const BY_KEY = new Map<string, Entry>();
const put = (k: string, e: Entry) => { if (!BY_KEY.has(k)) BY_KEY.set(k, e); };
for (const [k, list] of GAZ_EN) for (const raw of list.split('|')) {
  const cue = raw.includes('~'), v = raw.replace(/[~^]/g, '');
  const cs = raw.includes('^') || v.split(/\s+/).every((w) => ORDINARY.has(w.toLowerCase()));
  if (cs) EN_CS.push(enForm(v), enForm(v.toUpperCase())); else EN_CI.push(enForm(v));
  put(keyEn(v), { keys: k.split('') as EmirateKey[], cue });
}
// Most one-word Arabic place names are also words ("التعاون" cooperation, "المرور" traffic, "المشرف" the supervising
// engineer, "الروضة" a garden, "مربح" profitable): a one-word Arabic name counts only after a place cue or beside a place,
// unless it is a name and nothing else (AR_DISTINCT).
const AR_DISTINCT = new Set(['البرشاء', 'البرشا', 'القوز', 'مردف', 'محيصنة', 'القرهود', 'الخوانيج', 'جميرا', 'جميرة', 'الجميرا', 'الجميرة', 'الجافلية', 'مويلح', 'كلباء', 'خورفكان', 'مصفح',
  'المصفح', 'النعيمية', 'الظيت', 'دقداقة', 'القصيدات', 'المعيريض', 'القاسمية', 'المويجعي', 'الجيمي', 'سويحان', 'زاخر', 'الخبيصي', 'المرقبات', 'الفرجان', 'الممزر', 'القصيص']);
for (const [k, list] of GAZ_AR) for (const raw of list.split('|')) {
  const v = raw.replace(/[~^]/g, ''), cue = raw.includes('~') || (!/\s/.test(v) && !AR_DISTINCT.has(v));
  AR_ALTS.push(arForm(v));
  put('ar:' + keyAr(v), { keys: k.split('') as EmirateKey[], cue });
}
const byLen = (a: string, b: string) => b.length - a.length;
// THREE regexes compiled ONCE (review of 13 Nov 2026: about 700 regexes rebuilt per string cost 340 ms per 1,200 BOQ
// cells). Group 1 is the name, looked up in BY_KEY; group 2 a sector number.
// "Al …" names share their prefix: one "Al" then the rest (50 KB of "Al-Al-…" re-read "Al" for each of ~300 names).
const AL_PREFIX = 'Al[\\s\\-]*';
const EN_CI_AL = EN_CI.filter((f) => f.startsWith(AL_PREFIX)).map((f) => f.slice(AL_PREFIX.length)), EN_CI_REST = EN_CI.filter((f) => !f.startsWith(AL_PREFIX));
const GAZ_EN_CI = new RegExp(`(?<![A-Za-z0-9])((?:Al[\\s\\-]*(?:${EN_CI_AL.sort(byLen).join('|')})|${EN_CI_REST.sort(byLen).join('|')}))(?![A-Za-z])${SUB_EN}`, 'gi');
const GAZ_EN_CS = new RegExp(`(?<![A-Za-z0-9])(${EN_CS.sort(byLen).join('|')})(?![A-Za-z])${SUB_EN}`, 'g');
// An Arabic place takes a joined preposition (بالبرشاء, في is a word of its own); لل for an ال name ("للبرشاء").
const GAZ_AR_RE = new RegExp(`${AR_START}(?:[وبف]|وب)?(${AR_ALTS.sort(byLen).join('|')})${AR_END}${SUB_AR}`, 'g');
const GAZ_AR_LIL = new RegExp(`${AR_START}لل(${AR_ALTS.filter((a) => a.startsWith('ال')).map((a) => a.slice(2).replace(/^ـ\*/, '')).sort(byLen).join('|')})${AR_END}`, 'g');
/** A colour, a range or a material after a place name ("Marina blue", "Deira blue tiles", "Hatta stone", "Liwa sand")
 *  or a colour / range word before it ("Colour: Marina blue", "Jumeirah collection", "available in Al Ain white"). */
const PRODUCT_AFTER = /^[\s-]*(?:blue|white|grey|gray|green|red|black|beige|sand|stone|brown|gold|silver|cream|ivory|pearl|sky|night|sunset|collection|range|series|style|styled|finish|colou?r|edition|grade|water|cement|paints?|tiles?|marble|granite|sanitaryware|ceramics?|porcelain|glass|steel|cable|cables|mixer|type|model|design|pattern|look|theme|inspired|pergola|kiosk|paving|supplier\s+type)(?![A-Za-z])/i;
const PRODUCT_BEFORE = /(?:colou?r|finish|shade|tone|range|collection|series|style|available\s+in|in\s+the\s+colou?r|painted\s+in|paint)\s*:?\s*$/i;
const PRODUCT_AFTER_AR = /^\s*(?:للمياه|للسيراميك|للأسمنت|للاسمنت|الرملي|اللون|للدهانات|للحديد)/;
const PRODUCT_BEFORE_AR = /(?:سلسل[ةه]|مجموع[ةه]|لون|بلون|تشكيل[ةه]|مياه|[أا]سمنت|بلاط|رمل|دهان)\s*$/;

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
const NOT_COUNT = `(?![\\s\\-]*(?:[Ss][Qq]|[Nn][Oo][Ss]?|[Nn][Rr]|[Pp][Cc][Ss]|[Ss][Ee][Tt][Ss]?|[Uu][Nn][Ii][Tt][Ss]?|[Ll][Aa][Nn][Ee][Ss]?|[Gg][Aa][Nn][Gg]|[Ww][Aa][Yy][Ss]?|[Bb][Aa][Yy][Ss]?|[Dd][Oo][Oo][Rr][Ss]?|[Cc][Oo][Aa][Tt][Ss]?|[Bb][Ee][Dd]|[Bb][Ee][Dd][Ss]|[Bb][Ee][Dd][Rr][Oo][Oo][Mm][Ss]?|[Bb][Aa][Tt][Hh][Rr][Oo][Oo][Mm][Ss]?|[Rr][Oo][Oo][Mm][Ss]?|[Bb][Rr]|[Bb][Hh][Kk]|[Ss][Tt][Oo][Rr][Ee][Yy]|[Ss][Tt][Oo][Rr][Ee][Yy][Ss]|[Ss][Tt][Oo][Rr][Ii][Ee][Ss]|[Ss][Tt][Oo][Rr][Yy]|[Ff][Ll][Oo][Oo][Rr][Ss]?|[Ll][Ee][Vv][Ee][Ll][Ss]?|[Mm]2|[Mm]²|[Mm]3|[Ss][Qq][Mm]|[Ss][Qq]\\.?\\[Ss]*[Mm]|[Ss][Qq][Ff][Tt]|[Ss][Qq]\\.?\\[Ss]*[Ff][Tt]|[Ff][Tt]|[Mm]|[Mm][Mm]|[Cc][Mm]|[Tt][Rr]|[Kk][Ww]|[Kk][Vv][Aa]|[Xx]|×|%|[Yy][Ee][Aa][Rr][Ss]?|[Yy][Rr][Ss]?|[Mm][Oo][Nn][Tt][Hh][Ss]?|[Ww][Ee][Ee][Kk][Ss]?|[Dd][Aa][Yy][Ss]?|[Hh][Rr][Ss]?|[Hh][Oo][Uu][Rr][Ss]?|[Vv][Ii][Ll][Ll][Aa][Ss]?|[Ll][Oo][Tt][Ss]?|[Ll][Ss]|[Pp][Ee][Oo][Pp][Ll][Ee]|[Pp][Ee][Rr][Ss][Oo][Nn][Ss]|[Cc][Aa][Rr][Ss]?|[Pp][Aa][Rr][Kk][Ii][Nn][Gg]|[Ss][Ee][Aa][Tt][Ee][Rr]|[Tt][Oo][Nn]|[Tt][Oo][Nn][Ss]|[Kk][Gg])(?![A-Za-z]))`;
const NUM = `(?:${ci('no')}\\.?|${ci('number')}|#|:)?\\s*[:.]?\\s*\\d{1,5}(?:\\s*[\\-/]\\s*\\d{1,5})?[A-Z]?(?![\\w])(?![.,]\\d)${NOT_COUNT}`;
function ci(w: string) { return w.replace(/[A-Za-z]/g, (c) => `[${c.toUpperCase()}${c.toLowerCase()}]`); }
// "OFFICE 101", "SHOP 3", "WAREHOUSE 2" are room and unit tags on a drawing or a BOQ as often as an address (the CAD
// suites caught "OFFICE 101" boxed, 13 Nov 2026): those count only beside another place or running on to an emirate.
// A word split by OCR ("Of fice 000", "Vil la 15") is the same word.
const split = (w: string) => ci(w.slice(0, 2)) + '\\s?' + ci(w.slice(2));
const STRONG_EN = [...['villa', 'vila', 'apartment', 'apt', 'flat', 'plot', 'parcel', 'townhouse', 'penthouse'].map(ci), split('villa'), split('apartment')].join('|');
const WEAK_EN = [...['unit', 'building', 'bldg', 'tower', 'block', 'office', 'shop', 'showroom', 'warehouse', 'suite', 'house', 'district', 'cluster'].map(ci), split('office'), split('shop'), split('showroom'), split('warehouse')].join('|');
// "Villa E-23", "Plot C-12", "Sector E-23": a letter before the number only for these (not "flat M10 washer").
const NUMBER_WORD = '(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[\\s-](?:one|two|three|four|five|six|seven|eight|nine))?';
const PREMISES_EN = new RegExp(`(?<![A-Za-z])(?:(?:${STRONG_EN})\\.?\\s*${NUM}|${ci('villa')}\\s+${NUMBER_WORD}(?![A-Za-z])${NOT_COUNT}(?!\\s+(?:bed|bedroom|bedrooms|storey|storeys|stories|story|floors?|rooms?|bhk|br|units?|villas?)(?![A-Za-z]))|${ci('villas')}\\s*(?:${ci('no')}\\.?|${ci('number')}|#)\\s*\\d{1,4}(?!\\d)(?:\\s*(?:${ci('to')}|-|–|&|${ci('and')})\\s*\\d{1,4}(?!\\d))?|(?:${ci('villa')}|${ci('plot')})\\s*(?:${ci('no')}\\.?\\s*)?[A-Z]-?\\d{1,4}(?![\\w])${NOT_COUNT}|${ci('land')}\\s*(?:${ci('no')}\\.?|${ci('number')}|#)\\s*[:.]?\\s*\\d[\\d\\-/]{0,12}\\d)`, 'g');
const PREMISES_WEAK_EN = new RegExp(`(?<![A-Za-z])(?:(?:${WEAK_EN})\\.?\\s*${NUM}|${ci('sector')}\\s*[A-Z]?-?\\d{1,3}(?![\\w])|${ci('frond')}\\s+[A-P](?![A-Za-z])|V-\\d{1,4}(?![\\w]))`, 'g');
/** A number followed by a count noun or a unit is a size, not an address ("فيلا ٣ غرف نوم", "قطعة ٥٠ سم", "شارع 7 متر عرض"). */
const NOT_COUNT_AR = `(?!\\s*(?:غرف|غرف[ةه]|غرفتين|متر|م(?![\\u0621-\\u064A])|سم|مم|طابق|طوابق|[×xX*]|حمام|حمامات|كجم|كغ|لتر|قطع|عدد|سنوات|سنة|اشهر|أشهر|ايام|أيام|طن))`;
// A plot ("قطعة") only with رقم or أرض: "قطعة ٥٠ سم" is a piece.
const PREMISES_AR = new RegExp(`${AR_START}[وبل]?(?:(?:فيلا|فيلّا|ڤيلا|شق[ةه]|منزل|بيت)\\s*(?:رقم\\s*|ر\\.\\s*)?|قطع[ةه]\\s*(?:[أا]رض\\s*)?(?:رقم)\\s*|قطع[ةه]\\s+[أا]رض\\s*)[:：]?\\s*${D}{1,5}(?:\\s*[\\-/]\\s*${D}{1,5})?(?!${D})${NOT_COUNT_AR}`, 'g');
const PREMISES_WEAK_AR = new RegExp(`${AR_START}[وبل]?(?:مبنى|بناي[ةه]|برج|عمار[ةه]|مكتب|محل|معرض|مستودع|مخزن)\\s*(?:رقم\\s*)?[:：]?\\s*${D}{1,5}(?!${D})${NOT_COUNT_AR}`, 'g');
/** A street with a number: "Street 14", "St. 14", "Road No. 2", "14th Street", "شارع 14", "شارع رقم ١٤". */
// Not "St 2" / "St 3" (surface preparation grades, ISO 8501-1) and not "RD10" (a regulation): "Street", "Road", "Rd." only.
const STREET_NO = new RegExp(`(?<![A-Za-z])(?:${ci('street')}|${ci('road')}|Rd\\.|${ci('lane')})\\s*(?:${ci('no')}\\.?|#)?\\s*\\d{1,3}[A-Z]?(?![\\w])(?![.,]\\d)${NOT_COUNT}|(?<![A-Za-z0-9])\\d{1,3}(?:st|nd|rd|th)\\s+(?:${ci('street')}|St\\.?|${ci('road')}|Rd\\.?)(?![A-Za-z])`
  + `|${AR_START}[وبف]?شارع\\s*(?:رقم\\s*)?${D}{1,4}(?!${D})${NOT_COUNT_AR}`, 'g');
/** A named road: "Al Wasl Road", "Sheikh Zayed Road", "Al Khail Rd"; "Service Road", "Access Road" are scope. */
// A road is a place only beside another place (it is WEAK): "Asphalt Road works", "Wall Street finish" are not.
const ROAD_EN = /(?<![A-Za-z])((?:[A-Z][A-Za-z'’]+|al|bin|ibn)(?:[\s-]+(?:[A-Z][A-Za-z'’]+|al|bin|ibn)){0,3})\s+(?:Street|St\.|Road|Rd\.?|Highway|Hwy|Boulevard|Blvd\.?)(?![A-Za-z])(?!\s+(?:[Ss]tuds?|[Bb]arriers?|[Mm]arking|[Ss]ign(?:s|age)?|[Ll]ighting|[Ww]orks|[Ff]inish|[Pp]aving|[Cc]rossings?)(?![A-Za-z]))/g;
const ROAD_GENERIC = new Set(['asphalt', 'gravel', 'reflective', 'concrete', 'solar', 'cat', 'eye', 'wall', 'dirt', 'sand', 'paved', 'unpaved', 'service', 'access', 'main', 'internal', 'ring', 'link', 'slip', 'site', 'temporary', 'the', 'new', 'existing', 'haul', 'approach', 'perimeter', 'private',
  'public', 'feeder', 'connecting', 'side', 'back', 'front', 'boundary', 'existing', 'proposed', 'future', 'car', 'parking', 'emergency', 'fire', 'bus', 'truck', 'cross', 'off', 'on',
  'a', 'an', 'and', 'to', 'of', 'for', 'from', 'with', 'by', 'at', 'in', 'near', 'opposite', 'behind', 'beside', 'via', 'along', 'no', 'one', 'two', 'any', 'each', 'all', 'our', 'your']);
const ROAD_AR = new RegExp(`${AR_START}[وبف]?شارع\\s+(?!(?:رئيسي|فرعي|داخلي|خدمة|خدمات|جانبي|عام|الخدمة|الخدمات|الرئيسي|الفرعي|الداخلي)${AR_END})(?:(?:الشيخ|الملك|الأمير|الامير)\\s+${AW}(?:\\s+بن\\s+${AW})?|ال${AW}(?:\\s+ال${AW})?|${AW}\\s+بن\\s+${AW})`, 'g');
/** A building named before Tower / Residence / Heights / Building: "Marina Gate 2 tower", "ZZ Palm IU8 Tower". */
// Not when a code, a rule or an authority follows: "Dubai Building Code", "Abu Dhabi building permit", "UAE building projects".
// WEAK: a building counts only beside another place or in an address running to an emirate ("Liebherr Tower Crane",
// "Pre-Engineered Building", "Siemens Building Technologies" are products). "Burj <Name>" is a named tower (BURJ).
const BUILDING_EN = /(?<![A-Za-z0-9'’&-])((?:[A-Z][\w'’&-]{0,30}(?![\w'’&-])|\d{1,3})(?:\s+(?:[A-Z][\w'’&-]{0,30}(?![\w'’&-])|\d{1,3})){0,4})\s+(?:[Tt]owers?|TOWERS?|[Rr]esidences?|RESIDENCES?|[Hh]eights|HEIGHTS|[Bb]uilding|BUILDING|Bldg\.?|BLDG\.?|Centre|Center|CENTRE|CENTER|Plaza|PLAZA|Complex|COMPLEX)(?![A-Za-z])(?!\s+(?:[Cc]ranes?|[Ll]ights?|[Ff]ill|[Ss]caffold|[Tt]echnolog(?:y|ies)|[Aa]utomation|[Ss]olutions|[Cc]odes?|[Rr]egulations?|[Pp]ermits?|[Ss]tandards?|[Dd]epartment|[Aa]uthority|[Mm]aterials|[Cc]ontrol|[Ss]ervices|[Ii]nformation|[Mm]odel(?:l)?ing|[Mm]anagement|[Ss]ystems?|[Ww]orks|[Cc]ontractors?|[Mm]aintenance|[Ee]nvelope|[Hh]eight|[Ll]ine|[Aa]rea|[Pp]lot|[Ff]ootprint|[Pp]rojects?|[Ss]ector|[Ii]ndustry|[Tt]rade|[Ll]icen[cs]e|[Cc]ompletion|[Cc]ertificate)(?![A-Za-z]))/g;
/** Words before a building noun that say what KIND of thing it is, never which: "Cooling Tower", "Main Building". */
const BUILDING_GENERIC = new Set(['cooling', 'water', 'lighting', 'light', 'telecom', 'transmission', 'clock', 'control', 'main', 'office', 'new', 'existing', 'parking', 'car', 'staff',
  'service', 'services', 'school', 'admin', 'administration', 'the', 'this', 'that', 'our', 'your', 'a', 'an', 'each', 'all', 'guard', 'security', 'pump', 'plant', 'electrical',
  'mechanical', 'scaffold', 'scaffolding', 'crane', 'mobile', 'lattice', 'steel', 'concrete', 'tv', 'radio', 'cell', 'drying', 'wind', 'solar', 'storage', 'tank', 'residential',
  'commercial', 'apartment', 'apartments', 'villa', 'proposed', 'ceiling', 'room', 'floor', 'mounting', 'lift', 'stair', 'stairs', 'utility', 'substation', 'generator', 'rooftop',
  'roof', 'podium', 'retail', 'hotel', 'hospital', 'mosque', 'warehouse', 'factory', 'industrial', 'labour', 'labor', 'camp', 'site', 'temporary', 'permanent', 'adjacent', 'nearby',
  'twin', 'high', 'low', 'rise', 'mid', 'g', 'b', 'm', 'and', 'of', 'for', 'to', 'in', 'at', 'on', 'with', 'by', 'from', 'supply', 'install', 'installation', 'works', 'work', 'whole',
  'entire', 'complete', 'full', 'total', 'per', 'every', 'both', 'tall', 'glass', 'aluminium', 'aluminum', 'facade', 'green', 'smart', 'cladding', 'block', 'level', 'basement', 'heights',
  'tower', 'building', 'office', 'one', 'two', 'three', 'single', 'double', 'mixed', 'use', 'fit', 'out', 'fitout', 'interior', 'exterior', 'external', 'internal',
  'pre-engineered', 'modular', 'portable', 'telescopic', 'prefab', 'prefabricated', 'siemens', 'honeywell', 'johnson', 'schneider', 'abb', 'bac', 'evapco', 'marley', 'frp',
  'liebherr', 'potain', 'service', 'call', 'data', 'shopping', 'trade', 'business', 'distribution', 'control', 'command', 'medical', 'health', 'sports', 'fitness', 'community',
  'abu', 'dhabi', 'dubai', 'sharjah', 'ajman', 'fujairah', 'uae', 'emirates', 'emirate', 'international', 'national', 'federal', 'municipal', 'municipality', 'government', 'public', 'private']);
const BUILDING_AR = new RegExp(`${AR_START}[وبف]?(?:برج|بناي[ةه]|مبنى|عمار[ةه])\\s+(?!(?:الإنار[ةه]|الانار[ةه]|المراقب[ةه]|الحمام|الدرج|الإدار[ةه]|الادار[ةه]|الرئيسي|الجديد|القديم|المكاتب|التبريد|المياه|الخدمات|السكني|التجاري|المشروع|الموقع|المدرس[ةه]|الحراس[ةه]|المولدات|الكهرباء|الاتصالات|المستودع|السكن)${AR_END})ال${AW}(?:\\s+ال${AW})?`, 'g');
/** A landmark after a cue word, only when it is a place we know: a gazetteer name ("near Mall of the Emirates", "next to
 *  Burjuman metro") or a chain everyone gives directions by ("near ENOC", "opp. Lulu", "behind Carrefour Mirdif"). Any two
 *  Title-Case words were a landmark once and took "next to Main Distribution Board" (review of 13 Nov 2026). */
const LANDMARK_CUE_EN = `(?:${ci('near')}(?:\\s+${ci('to')})?|${ci('nearby')}|${ci('opposite')}(?:\\s+${ci('to')})?|${ci('opp')}\\.?|${ci('behind')}|${ci('next')}\\s+${ci('to')}|${ci('beside')}|${ci('close')}\\s+${ci('to')}|${ci('in')}\\s+${ci('front')}\\s+${ci('of')}|${ci('across')}\\s+${ci('from')}|${ci('adjacent')}\\s+${ci('to')}|${ci('walking')}\\s+${ci('distance')}\\s+${ci('from')})`;
const LANDMARK_CUE_END_EN = new RegExp(`(?<![A-Za-z])${LANDMARK_CUE_EN}\\s+(?:${ci('the')}\\s+)?$`);
const CHAINS_EN = /(?<![A-Za-z])(?:ENOC|ADNOC|EPPCO|Emarat|EMARAT|Lulu|LULU|Carrefour|CARREFOUR|Spinneys|SPINNEYS|Choithrams|Union\s+Coop|Nesto|NESTO|Waitrose)(?:\s+(?:[Pp]etrol|[Ss]tation|[Hh]ypermarket|[Ss]upermarket|[Mm]all|[Pp]ump|[Mm]etro|[Ee]xpress|[Mm]arket|[Cc]entre|[Cc]enter))*(?![A-Za-z])/g;
const LANDMARK_AR = new RegExp(`${AR_START}(?:بالقرب\\s+من|قريب\\s+من|قرب|مقابل|خلف|وراء|بجانب|جنب|بجوار|أمام|امام|جوار|بمحاذا[ةه])\\s+(?:(?:مول|مسجد|جامع|مدرس[ةه]|مستشفى|محط[ةه]\\s+مترو|مترو|دوار|دوّار|فندق|سوق|جمعي[ةه]|كارفور|لولو|إشار[ةه]|اشار[ةه])${AR_END}(?:\\s+${AW}){0,3})`, 'g');
/** A Makani number (Dubai's building locator): ten digits after "Makani" / "مكاني", spaced or not. */
const MAKANI = new RegExp(`(?<![A-Za-z])${ci('makani')}(?:\\s*(?:${ci('no')}\\.?|${ci('number')}|#))?\\s*[:.\\-]?\\s*${D}{5}\\s?${D}{5}(?!${D})|${AR_START}مكاني(?:\\s*رقم)?\\s*[:：]?\\s*${D}{5}\\s?${D}{5}(?!${D})`, 'g');
/** Map coordinates inside the UAE (latitude 22-26 N, longitude 51-56 E), decimal or labelled. */
// A comma, semicolon or slash between the two, or a N / ° marker: "Price 25.1123 55.2001 per kg" is two figures.
// Four decimals at least (a GPS reading; "Tolerance 25.400/55.200 mm", "Rate 25.125, 55.750" are figures), in Latin or
// Arabic-Indic digits with the Arabic decimal sign and comma ("٢٥٫١١٢٣، ٥٥٫٢٠٠١").
const COORDS = /(?<![\d.])(?:(?<![A-Za-z])[Nn]\s*)?2[2-6]\.\d{4,8}\s*°?\s*[Nn]?\s*[,;/]\s*(?:[Ee]\s*)?5[1-6]\.\d{4,8}\s*°?\s*[Ee]?(?![\d.])|(?<![\d.])2[2-6]\.\d{4,8}\s*(?:°\s*)?[Nn]\s+5[1-6]\.\d{4,8}\s*(?:°\s*)?[Ee](?![A-Za-z])|(?<![٠-٩])٢[٢-٦][٫.][٠-٩]{4,8}\s*[،,]\s*٥[١-٦][٫.][٠-٩]{4,8}(?![٠-٩])|(?<![\d.])2[2-6]\s*°\s*\d{1,2}\s*['′]\s*(?:\d{1,2}(?:\.\d+)?\s*["″])?\s*[Nn]?[\s,]*5[1-6]\s*°\s*\d{1,2}\s*['′]\s*(?:\d{1,2}(?:\.\d+)?\s*["″])?\s*[Ee]?/g;
/** A what3words address: "///filled.count.soap", "what3words: filled.count.soap". */
const W3W = /(?:\/\/\/|(?<![A-Za-z])what\s*3\s*words\s*[:\-]?\s*\/{0,3})[a-z]{2,}\.[a-z]{2,}\.[a-z]{2,}(?![A-Za-z])|(?<![\w/])\/\/\/[a-z]{2,}\.[a-z]{2,}\.[a-z]{2,}/gi;
/** An industrial area by number with no community before it: "Industrial Area 6" (Sharjah, Ajman and Al Ain have them). */
// A bare "Industrial Area" needs its number ("Industrial Area lighting fixture" is a product); and no trailing blank is
// taken with it (third review of 13 Nov 2026: "[X]lighting fixture").
const IND_AREA = new RegExp(`(?<![A-Za-z])(?:Al\\s+[A-Z][a-z]+\\s+(?:Industrial|INDUSTRIAL)\\s+(?:Area|AREA)(?:\\s*(?:No\\.?\\s*)?\\d{1,2}(?!\\d))?|(?:Industrial|INDUSTRIAL)\\s+(?:Area|AREA)\\s*(?:No\\.?\\s*)?\\d{1,2}(?!\\d))|(?<![ء-ي])(?:ال)?منطق[ةه]\\s+الصناعي[ةه]\\s*${D}{1,2}(?!${D})`, 'g');

/** Abu Dhabi's sector codes after their district: "Mussafah M-37", "Khalifa City SE-45", "Shabiya ME-10", "MBZ Z-22". */
const SECTOR_CODE = /(?<=(?:Mussafah|Musaffah|Mussaffah|Musafah|MUSSAFAH|Khalifa\s+City(?:\s+[A-D])?|KHALIFA\s+CITY|MBZ(?:\s+City)?|Mohammed\s+[Bb]in\s+Zayed\s+City|Shabiya|Shabiyah|Shabia|ICAD(?:\s+\d)?)[\s,]+)[A-Z]{1,2}-?\d{1,3}(?![\w-])/g;
/** A street with a letter in its number beside a place ("Al Barsha 2 - 23B Street"): weak, so "4B Street sign" alone stays. */
const STREET_ALNUM = /(?<![A-Za-z0-9])\d{1,3}[A-Z]\s+(?:Street|St\.|Road|Rd\.)(?![A-Za-z])/g;
/** "Meadows 2", "Springs 5", "The Lakes 3": the Emirates Living sub-communities by number, in Title Case. */
const NUMBERED_COMMUNITY = new RegExp(`(?<![A-Za-z])(?:The\\s+)?(?:Meadows|Springs|Lakes|Greens)\\s+\\d{1,2}(?!\\d)(?![\\s-]*(?:${COUNT_WORDS.replace('villas?|', '')})(?![A-Za-z]))`, 'gi');
/** "Ajman Industrial 1", "Sharjah Industrial Area 13", "المدينة الصناعية بالشارقة ١٣": an emirate's numbered industrial area. */
const IND_EMIRATE = new RegExp(`(?<=(?:Ajman|Sharjah|Umm\\s+Al\\s+Quwain|Ras\\s+Al\\s+Khaimah|Fujairah|AJMAN|SHARJAH)\\s+)(?:Industrial|INDUSTRIAL)(?:\\s+(?:Area|AREA))?\\s*(?:No\\.?\\s*)?\\d{1,2}(?!\\d)|(?:ال)?(?:مدين|منطق)[ةه]\\s+(?:ال)?صناعي[ةه](?:\\s+(?:ب|في\\s+)?(?:ال|لل)?(?:شارق[ةه]|عجمان))?\\s*${D}{1,2}(?!${D})`, 'g');
// "Al Wasl area rug" is a rug (third review): not when a product follows the word.
const AREA_AFTER = /^\s+(?:area|community|district|neighbourhood|neighborhood)(?![A-Za-z])(?!\s+(?:rugs?|carpets?|mats?|lights?|lighting|lamps?|drains?|tiles?)(?![A-Za-z]))/i;

// ── finding and grouping ─────────────────────────────────────────────────────────────────────────────────────────
type Span = { s: number; e: number; keys: EmirateKey[] | null; ar: boolean; cue?: boolean; landmark?: boolean; weak?: boolean; gaz?: boolean; num?: boolean };
const isAr = (t: string) => /[؀-ۿ]/.test(t);
/** A LOCATION cue right before a name: "in", "at", "near", "located in", "Location:", "في", "منطقة". Not "Colour:". */
const CUE_BEFORE_EN = /(?:\b(?:in|at|near|inside|located|based|around|area|community|villa|site|district)(?:\s+the)?|\b(?:location|site|address|area|community|district)\s*:|\b(?:CIF|CFR|CNF|FOB|FAS|DAP|DPU|DDP|CPT|CIP|FCA|ex|EXW|ex[\s-]?works)\s*,?)\s*$/i;
const CUE_BEFORE_AR = /(?:في|قرب|عند|منطق[ةه]|حي|بمنطق[ةه]|الموقع\s*[:：]|العنوان\s*[:：])\s*$/;
const SEP = /^[\s,،;\-–—/|&]*(?:(?:and|in|at|of|و|في)[\s,،\-–—]*)?$/i;
const SEP_STRICT = /^[\s,،\-–—/|]*$/;
/** Anything a place could start with: a capital, an Arabic letter, a digit, a premises or cue word. A text with none of
 *  these (all lower-case prose with no number) has no place a rule can see, and costs one test. */
const MAYBE_PLACE = /[A-Z0-9؀-ۿ٠-٩]|\b(?:villa|flat|apartment|plot|office|shop|street|road|makani|what3words|near|opposite|behind)\b|\/\/\//i;

function emirateTokens(t: string): { s: number; e: number; key: EmirateKey }[] {
  const out: { s: number; e: number; key: EmirateKey }[] = [];
  for (const [key, re] of EMIRATE_RE) { re.lastIndex = 0; for (const m of t.matchAll(re)) out.push({ s: m.index!, e: m.index! + m[0].length, key }); }
  return out;
}
/** Every place span below the emirate in `t`, unmerged (exported for the residual scan and the tests). */
/** `drawing`: the text is a label on a drawing (a title block, a key plan): a cue-only name in capitals or alone on its
 *  line ("ARJAN", "DEIRA") IS a place there; in text it is not ("Arjan model chair"). Third review of 13 Nov 2026: the
 *  drawings branch released a title block naming ARJAN. */
export function placeSpans(text: unknown, opts: { drawing?: boolean } = {}): Span[] {
  const t = String(text ?? '');
  if (!t.trim() || !MAYBE_PLACE.test(t)) return [];
  const raw: Span[] = [];
  const add = (re: RegExp, keys: EmirateKey[] | null, more: Partial<Span> = {}, check?: (m: RegExpMatchArray) => [number, number] | null) => {
    re.lastIndex = 0;
    for (const m of t.matchAll(re)) {
      if (!m[0].trim()) continue;
      const sp = check ? check(m) : [m.index!, m.index! + m[0].length] as [number, number];
      if (sp) raw.push({ s: sp[0], e: sp[1], keys, ar: isAr(m[0]), ...more });
    }
  };
  // The gazetteer: one pass per script, the name looked up; a colour, a range or a material beside it is a product.
  const gaz = (re: RegExp, ar: boolean, lil = false) => {
    re.lastIndex = 0;
    for (const m of t.matchAll(re)) {
      const name = m[1];
      const en = BY_KEY.get(ar ? 'ar:' + keyAr(lil ? 'ال' + name : name) : keyEn(name));
      if (!en) continue;
      const s0 = m.index!, e0 = s0 + m[0].length;
      const before = t.slice(Math.max(0, s0 - 30), s0), after = t.slice(e0, e0 + 20);
      if (ar ? (PRODUCT_BEFORE_AR.test(before) || PRODUCT_AFTER_AR.test(after)) : (PRODUCT_BEFORE.test(before) || PRODUCT_AFTER.test(after))) continue;
      // A sector number after a cue-only name is its cue ("Jumeirah 3", "Al Safa 2", "Springs 5").
      // ...with a space before it: "MBZ-1 panel" is a part code (third review of 13 Nov 2026).
      const numbered = !!m[3] && /\s$/.test(m[2] ?? '');
      raw.push({ s: s0, e: e0, keys: en.keys, ar, cue: en.cue && !numbered, gaz: true });
    }
  };
  gaz(GAZ_EN_CI, false); gaz(GAZ_EN_CS, false); gaz(GAZ_AR_RE, true); gaz(GAZ_AR_LIL, true, true);
  add(PREMISES_EN, null); add(PREMISES_AR, null); add(PREMISES_WEAK_EN, null, { weak: true, num: true }); add(PREMISES_WEAK_AR, null, { weak: true, num: true });
  add(SECTOR_CODE, null, { weak: true }); add(STREET_ALNUM, null, { weak: true }); add(NUMBERED_COMMUNITY, ['D']);
  IND_EMIRATE.lastIndex = 0;
  for (const m of t.matchAll(IND_EMIRATE)) raw.push({ s: m.index!, e: m.index! + m[0].length, ar: isAr(m[0]), keys: /شارق/.test(m[0]) ? ['S'] : /عجمان/.test(m[0]) ? ['J'] : null });
  // A house number and its street, anywhere ("4209 COUNTY ROAD 24 1/2", identity_contacts): one place, not "ROAD 24" alone.
  add(STREET_ADDRESS, null); add(STREET_NO, null, { weak: true }); add(MAKANI, null); add(COORDS, null); add(W3W, null); add(IND_AREA, null);
  add(LANDMARK_AR, null, { landmark: true }); add(CHAINS_EN, null, {}, (m) => (LANDMARK_CUE_END_EN.test(t.slice(Math.max(0, m.index! - 40), m.index!)) ? [m.index!, m.index! + m[0].length] : null));
  add(BURJ, null);
  add(ROAD_EN, null, { weak: true }, (m) => {
    // Trim leading ordinary words ("Access to Al Wasl Road" keeps "Al Wasl Road"); a road named only by them is scope.
    const words = [...m[1].matchAll(/\S+/g)];
    let i = 0; while (i < words.length && ROAD_GENERIC.has(words[i][0].toLowerCase())) i++;
    if (i >= words.length || words.slice(i).every((w) => /^(?:al|bin|ibn)$/i.test(w[0]))) return null;
    return [m.index! + words[i].index!, m.index! + m[0].length];
  });
  add(ROAD_AR, null);
  add(BUILDING_EN, null, { weak: true }, (m) => {
    // Read the name backwards from the noun and stop at the first word that says what kind of building it is.
    const words = [...m[1].matchAll(/\S+/g)];
    let i = words.length; while (i > 0 && !BUILDING_GENERIC.has(words[i - 1][0].toLowerCase())) i--;
    const kept = words.slice(i);
    if (!kept.length || kept.every((w) => /^\d+$/.test(w[0]))) return null;
    return [m.index! + kept[0].index!, m.index! + m[0].length];
  });
  add(BUILDING_AR, null, { weak: true });
  // Longest first; a span inside a longer one goes ("Dubai Marina" over "Marina", "Al Quoz Industrial Area 3" over "Industrial Area 3").
  raw.sort((a, b) => a.s - b.s || b.e - a.e);
  const spans: Span[] = [];
  // A span never ends on a blank (the removal would eat the space after it).
  for (const r of raw) while (r.e > r.s && /\s/.test(t[r.e - 1])) r.e--;
  for (const r of raw) {
    const last = spans[spans.length - 1];
    if (last && r.s < last.e) { if (r.e > last.e) { last.e = r.e; last.keys = last.keys ?? r.keys; } else if (!last.keys && r.keys) last.keys = r.keys; if (!r.cue) last.cue = false; if (!r.weak) last.weak = false; if (r.num) last.num = true; continue; }
    spans.push({ ...r });
  }
  if (!spans.length) return spans;
  // An emirate word INSIDE a span is the span's ("Dubai Marina"): emirate tokens outside spans are what stays.
  const emirates = emirateTokens(t).filter((x) => !spans.some((s) => x.s >= s.s && x.e <= s.e));
  const nextTo = (a: Span, b: { s: number; e: number }, re = SEP) => (a.e <= b.s ? re.test(t.slice(a.e, b.s)) : b.e <= a.s ? re.test(t.slice(b.e, a.s)) : true);
  // A cue-only name ("Marina", "Jumeirah", "Al Ain") counts after a LOCATION cue or next to another place or an emirate;
  // a weak one ("Unit 12", "Tower 2", "Liebherr Tower") only next to another place or in an address running to an emirate.
  const accepted = spans.map((s) => !s.cue && !s.weak);
  for (const [i, s] of spans.entries()) {
    if (accepted[i] || s.weak) continue;
    const before = t.slice(Math.max(0, s.s - 30), s.s), after = t.slice(s.e, s.e + 20);
    // "Al Wasl area", "Al Karama community": the word after a cue-only name says it is a place.
    const own = t.slice(s.s, s.e), lineOf = t.slice(t.lastIndexOf('\n', s.s - 1) + 1, (t.indexOf('\n', s.e) + 1 || t.length + 1) - 1);
    if (opts.drawing && s.gaz && (!/[a-z]/.test(own) || lineOf.trim() === own.trim())) { accepted[i] = true; continue; }
    if ((s.ar ? CUE_BEFORE_AR : CUE_BEFORE_EN).test(before) || (!s.ar && LANDMARK_CUE_END_EN.test(before)) || (!s.ar && AREA_AFTER.test(after))) accepted[i] = true;
  }
  // COMPONENTS: spans touching with only separators between them are one address. It is a place when one member is
  // (a strong place, or a cue-only name after a cue), when it touches an emirate, when a weak member runs on to an emirate
  // (CHAIN), or when it holds a NUMBERED premises AND a cue-only name ("Office 14, Hatta", "Shop 3, Karama", "Office 302,
  // Al Mulla Building, Deira": the letterhead address, second review of 13 Nov 2026). Linear: spans are sorted.
  spans.sort((a, b) => a.s - b.s);
  const comps: number[][] = [];
  for (let i = 0; i < spans.length; i++) {
    if (i && SEP_STRICT.test(t.slice(spans[i - 1].e, spans[i].s))) comps[comps.length - 1].push(i); else comps.push([i]);
  }
  const ends = spans.map((x) => x.e), starts = spans.map((x) => x.s);
  const touching = new Set<number>();
  for (const x of emirates) {
    let lo = 0, hi = ends.length - 1, j = -1; while (lo <= hi) { const mid = (lo + hi) >> 1; if (ends[mid] <= x.s) { j = mid; lo = mid + 1; } else hi = mid - 1; }
    if (j >= 0 && SEP_STRICT.test(t.slice(ends[j], x.s))) touching.add(j);
    lo = 0; hi = starts.length - 1; let k = -1; while (lo <= hi) { const mid = (lo + hi) >> 1; if (starts[mid] >= x.e) { k = mid; hi = mid - 1; } else lo = mid + 1; }
    if (k >= 0 && SEP_STRICT.test(t.slice(x.e, starts[k]))) touching.add(k);
  }
  for (const c of comps) {
    const ok = c.some((i) => accepted[i] || touching.has(i) || (spans[i].weak && (t.slice(spans[i].e, spans[i].e + 400).match(CHAIN)?.[0] ?? '') !== ''))
      || (c.some((i) => spans[i].num) && c.some((i) => spans[i].cue && spans[i].gaz));
    if (ok) for (const i of c) accepted[i] = true;
  }
  // A delivery term ("CIF Jebel Ali") and a list of areas served ("Installation in Abu Dhabi and Al Ain") cross as written
  // (the coordinator's ruling of 13 Nov 2026), so they are not places to reduce, and not a residual that holds a field.
  const out = spans.filter((s, i) => accepted[i] && !(s.gaz && (INCOTERM_BEFORE.test(t.slice(Math.max(0, s.s - 30), s.s)) || serviceSentence(t, s.s, s.e))));
  // "near Mall of the Emirates": the cue goes with the place, and the place reads "in Dubai".
  for (const s of out) if (s.gaz && !s.ar) { const m = t.slice(Math.max(0, s.s - 40), s.s).match(LANDMARK_CUE_END_EN); if (m) { s.s -= m[0].length; s.landmark = true; } }
  return out;
}
/** "Burj Vista", "Burj Al Salam": "burj" is Arabic for tower, so a Burj with a name is a named tower. */
const BURJ = /(?<![A-Za-z])Burj\s+(?:Al\s+)?[A-Z][a-z]+(?:\s+(?:[Tt]ower\s+)?\d{1,2})?(?![A-Za-z])/g;

const INCOTERM_BEFORE = /\b(?:CIF|CFR|CNF|C&F|FOB|FAS|DAP|DPU|DDP|CPT|CIP|FCA)\s+(?:port\s+(?:of\s+)?)?$|\bex\s+(?!works)$/i;
const EXWORKS_BEFORE = /\b(?:ex[\s-]?works|EXW)\s*,?\s*$/i;
const SERVICE_CUE = /\b(?:deliver(?:y|ies|ed)?|supply|supplies|serv(?:e|es|ing|ice\s+area)|cover(?:s|age|ing)?|across|throughout|install(?:ation)?\s+across|branches|distributors?|dealers?|outlets?)\b|التوصيل|التسليم|نغطي|التركيب\s+في/i;
/** The group sits in a sentence that lists the emirates or regions a supplier serves, and names an emirate itself. */
// One answer per sentence (a 50 KB run of places asked this 5,000 times of the same 50 KB sentence).
let SENT_MEMO: { t: string; m: Map<number, boolean> } = { t: '', m: new Map() };
function serviceSentence(t: string, gs: number, ge: number): boolean {
  const a = Math.max(t.lastIndexOf('.', gs), t.lastIndexOf('\n', gs), t.lastIndexOf(';', gs)) + 1;
  if (SENT_MEMO.t !== t) SENT_MEMO = { t, m: new Map() };
  const hit = SENT_MEMO.m.get(a); if (hit !== undefined) return hit;
  const ends = [t.indexOf('.', ge), t.indexOf('\n', ge), t.indexOf(';', ge)].filter((x) => x >= 0);
  const sent = t.slice(a, ends.length ? Math.min(...ends) : t.length);
  const r = SERVICE_CUE.test(sent) && emirateTokens(sent).length > 0;
  SENT_MEMO.m.set(a, r); return r;
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
  const t = capBlanks(String(text ?? ''));
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
    const pre = t.slice(Math.max(0, gs - 30), gs);
    const onlyGaz = g.every((x) => x.gaz);
    // The coordinator's ruling of 13 Nov 2026: a delivery term ("CIF Jebel Ali", "FOB Jebel Ali port", "ex Jebel Ali") is
    // commercial information a buyer needs and passes as written; "ex works <area>" is the supplier's own location.
    // A list of emirates and regions served ("Delivery to Abu Dhabi, Al Ain and the Western Region") is neither the
    // customer's site nor the supplier's address: it passes.
    void onlyGaz;
    // The group's emirates: each one its places name, or (Al Nahda: Dubai or Sharjah) the one the text names.
    const keys = g.map((s) => s.keys).filter(Boolean) as EmirateKey[][];
    const own: EmirateKey[] = [];
    for (const k of keys) { const pick = k.length === 1 ? k[0] : (k.filter((x) => named.has(x)).length === 1 ? k.filter((x) => named.has(x))[0] : null); if (pick && !own.includes(pick)) own.push(pick); }
    // Next to an emirate its places belong to (or that names none): removed, the emirate stays. "Deira, Sharjah" is two.
    const fits = (x: { key: EmirateKey }) => !own.length || own.every((k) => k === x.key);
    if (after && fits(after)) { const head = t.slice(at, gs); out += /\bat\s+$/i.test(head) && !isAr(whole) ? head.replace(/\b([Aa])t(\s+)$/, (_m, a: string, sp: string) => (a === 'A' ? 'In' : 'in') + sp) : head; at = after.s; tell(); continue; }
    if (before && fits(before)) { out += t.slice(at, before.e); at = ge; tell(); continue; }
    const ar = isAr(whole);
    const shown = own.filter((k) => k !== after?.key && k !== before?.key);
    if (shown.length) {
      const names = shown.map((k) => (ar ? EMIRATE_NAME[k].ar : EMIRATE_NAME[k].en));
      const name = names.length === 1 ? names[0] : names.slice(0, -1).join(', ') + (ar ? ' و' : ' and ') + names[names.length - 1];
      // "villa near Mall of the Emirates" reads "villa in Dubai", not "villa Dubai".
      const lead = g[0].landmark && !(ar ? /في\s*$/.test(pre) : /\b(?:in|at)\s*$/i.test(pre)) ? (ar ? 'في ' : 'in ') : '';
      const exw = EXWORKS_BEFORE.test(pre) && !/,\s*$/.test(pre) ? ', ' : '';
      // Never the same emirate twice in a row ("Dubai, Al Barsha and Dubai").
      const prev = (out + t.slice(at, gs)).replace(/[\s,،\-–—/|&]*(?:and|or|و)?[\s,،]*$/i, '');
      if (!lead && names.length === 1 && prev.endsWith(name)) { out = prev; at = ge; tell(); continue; }
      // "Renovation at Al Barsha 2" reads "Renovation in Dubai", not "at Dubai".
      const head = t.slice(at, gs);
      const fixed = !lead && !ar && /\bat\s+$/i.test(head) ? head.replace(/\b([Aa])t(\s+)$/, (_m, a: string, sp: string) => (a === 'A' ? 'In' : 'in') + sp) : head;
      out += fixed + exw + lead + name; at = ge; tell(); continue;
    }
    out += t.slice(at, gs) + (typeof rep === 'string' ? rep : rep(whole)); at = ge;
  }
  return (out + t.slice(at)).replace(/[ \t]{2,}/g, ' ').replace(/\s+([,.;:،])/g, '$1').replace(/([,،])\s*(?=[,،])/g, '');
}

/** True when a customer's seed phrase is itself a place the reducer turns into its emirate (a stored site address): paint
 *  such seeds AFTER reducePlaces, never before, or "at Al Barsha 2" loses "at Dubai" too. Seeds are lower-case, so the
 *  test reads them in Title Case. */
export function reducibleSeed(seed: string): boolean {
  const title = String(seed ?? '').replace(/\b([a-z])/g, (c) => c.toUpperCase());
  // Only a seed that is NOTHING BUT a place: "zz demo barsha garden villa" (a project) must still be painted whole.
  if (!placeSpans(title).length) return false;
  let left = reducePlaces(title, '').replace(/\b(?:in|at)\b/gi, '');
  for (const e of Object.values(EMIRATE_NAME)) left = left.split(e.en).join('').split(e.ar).join('');
  return left.replace(/[\s,.\-]/g, '') === '';
}
