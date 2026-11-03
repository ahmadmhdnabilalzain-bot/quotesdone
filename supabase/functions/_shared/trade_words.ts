// WHICH TRADE A CONVERSATION IS ABOUT, READ BY CODE (moved out of sales_engineer/conversation_plan.ts, it_engineer, 3 Nov 2026).
// The portal's plan already picked its playbook from the customer's own words with these patterns. Every chat reply now
// needs the same answer to choose its one trade pack (company_brief.ts), so the patterns live in _shared and the plan
// imports them. One change in the move: three two- and three-letter Arabic words match only as whole words, because the
// brief's exam questions showed them inside other words (بق in بقيمة "worth", نش in أنشر "I post", شتر in أشتري "I buy"),
// and with a pack chosen from them a fee question would carry the pest pack and a price question lose its trade's prices.
// prevented by: sales_engineer/conversation_plan.test.ts (the bank's 43 openings to their playbooks), _shared/brief_budget.test.ts

const AR_DIGITS = '٠١٢٣٤٥٦٧٨٩';
/** Lower-case, NFKC, Arabic digits to ASCII, diacritics and tatweel removed, alef/ta marbuta/alef maqsura unified. */
export function normalise(s: string): string {
  return String(s || '').normalize('NFKC').toLowerCase()
    .replace(/[٠-٩]/g, (d) => String(AR_DIGITS.indexOf(d)))
    .replace(/[ً-ٰٟـ]/g, '')
    .replace(/[أإآٱ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي').replace(/ؤ/g, 'و').replace(/ئ/g, 'ي');
}
/** A pattern written in ordinary Arabic spelling, matched against normalise()d text. */
export const rx = (src: string) => new RegExp(src.replace(/[أإآٱ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي').replace(/ؤ/g, 'و').replace(/ئ/g, 'ي')
  .replace(/§/g, '(?<![\\p{L}])(?:وال|بال|فال|لل|ال|و|ف|ب|ل)?'), 'iu');

// ── which playbook a conversation is: the customer's own words, most specific first ───────────────────────────────
export const TRADE_WORDS: [string, RegExp][] = ([
  ['water-tank-cleaning', String.raw`tank clean|clean\w* (the |my |our )?(water )?tanks?|تنظيف (ال)?خزان`],
  ['cleaning', String.raw`\bclean(ing)?\b|\bdeep clean|تنظيف|نظافة`],
  ['pest', String.raw`\bpest|cockroach|bed ?bugs|termite|rodent|\brats?\b|\bmice\b|mosquito|صراصير|صرصور|حشرات|(?<![\p{L}])بق(?![\p{L}])|نمل|فئران|قوارض|ناموس`],
  ['safety', String.raw`fire (alarm|fighting|safety|suppression)|sprinkler|انذار حريق|الحريق|حريق|رشاشات`],
  ['security', String.raw`\bcctv|camera|surveillance|access control|intercom|intrusion|burglar|كاميرا|كاميرات|مراقبة|انتركم|بصمة`],
  ['solar', String.raw`\bsolar|photovoltaic|\bpv\b|شمسي|شمسية|الواح شمسية`],
  ['smart-home', String.raw`smart home|home automation|\bsmart\b|سمارت|منزل ذكي|بيت ذكي|ذكي`],
  ['generators', String.raw`\bgenerator|genset|مولد`],
  ['mep', String.raw`maintenance contract|\bamc\b|\bmep\b|facility management|\bppm\b|عقد صيانة`],
  ['hvac', String.raw`\bac\b|a/c|air[- ]?con|aircon|\bsplit\b|ducted|\bhvac|\bbtu\b|cooling|مكيف|مكيفات|تكييف|دكت|سبليت`],
  // a water tank (خزان), never a wardrobe (خزانة)
  ['plumbing', String.raw`water tank|\btanks?\b|§خزان(?!ه)`],
  ['carpets', String.raw`\bcarpet|موكيت|سجاد`],
  ['tiling', String.raw`\btiles?\b|\btiling|بلاط|سيراميك|بورسلين`],
  ['flooring', String.raw`\bfloor(ing)?\b|parquet|vinyl|laminate floor|ارضيات|ارضية|باركيه`],
  ['plumbing', String.raw`\bbathroom|\bplumb|\bpipe|\bleaking tap|blockage|حمام|سباكة|مواسير`],
  ['waterproofing', String.raw`waterproof|roof leak|leak\w* (from|through) (the )?roof|seepage|damp proof|عزل مائي|عزل السطح|تسريب|تسرب|(?<![\p{L}])نش(?![\p{L}])`],
  ['roofing', String.raw`\bre-?roof|roof (tiles|sheets?|replacement)|new roof|سقف معدني|قرميد`],
  ['swimming-pools', String.raw`\bpool\b|swimming|مسبح|بركة سباحة`],
  ['landscaping', String.raw`\bgarden|landscap|\blawn|\bturf|irrigation|interlock|paving|driveway|حديقة|عشب|انترلوك|بلاط حوش`],
  ['tents-and-shade-structures', String.raw`pergola|\bshade\b|canopy|carport|\btent|shade sail|مظلة|مظلات|برجولا|خيمة`],
  ['blinds-curtains', String.raw`curtain|\bblinds?\b|ستائر|ستارة|برادي`],
  ['glass', String.raw`\bglass|glazing|mirror|shower enclosure|balustrade|زجاج|مرايا|مراية`],
  ['aluminium', String.raw`\bwindows?\b|alumin|upvc|curtain wall|نوافذ|شبابيك|شباك|المنيوم`],
  ['garage-doors', String.raw`garage door|roller shutter|(?<![\p{L}])شتر(?![\p{L}])|باب كراج`],
  ['elevators', String.raw`\blift\b|elevator|مصعد`],
  ['signage', String.raw`signage|\bsign\b|light box|لوحة اعلانية|يافطة`],
  ['marble-granite', String.raw`marble|granite|رخام|جرانيت`],
  ['epoxy-flooring', String.raw`epoxy|ايبوكسي`],
  ['gypsum', String.raw`gypsum|false ceiling|cornice|bulkhead|جبس|جبسم|اسقف معلقة`],
  ['painting', String.raw`\bpaint|repaint|صبغ|صباغة|نصبغ|اصبغ|دهان|طلاء`],
  ['wallpaper', String.raw`wallpaper|ورق جدران`],
  ['steel', String.raw`\bgate\b|\bfence|railing|staircase|mezzanine|\bsteel\b|بوابة|سياج|درابزين|حديد`],
  ['kitchens', String.raw`\bkitchen|مطبخ`],
  ['carpentry-joinery', String.raw`wardrobe|closet|vanity|tv unit|shelving|built-in|joinery|cabinet|خزانة|خزائن|دولاب|كبت|نجارة`],
  ['upholstery', String.raw`\bsofa|upholster|majlis|seating|جلسة|كنب|مجلس|تنجيد`],
  ['electrical', String.raw`\belectric\w*|\bev\b|charger|wiring|rewir|socket|\bdb\b|electrician|شاحن|كهرباء|كهربائي`],
  ['commercial-retail-fitout', String.raw`(cafe|restaurant|clinic|salon|showroom|retail|shop)[^.]{0,40}fit[- ]?out|fit[- ]?out[^.]{0,40}(cafe|restaurant|clinic|salon|showroom|retail|shop)`],
  ['fitout', String.raw`fit[- ]?out|fitted out|تشطيب مكتب|فت اوت`],
  ['interior-design', String.raw`interior design|مصمم داخلي|تصميم داخلي`],
  ['movers', String.raw`\bmov(ing|ers)\b|relocat|نقل عفش|نقل اثاث`],
  ['demolition', String.raw`demoli|strip[- ]out|هدم`],
  ['masonry', String.raw`block ?work|masonry|plaster|cladding|بلوك|لياسة`],
  ['scaffolding', String.raw`scaffold|سقالة|سقالات`],
  ['it-networking', String.raw`network|wi-?fi|cabling|server|شبكة|واي فاي`],
  ['av-systems', String.raw`audio|home cinema|projector|speakers|صوتيات|سينما`],
  ['insulation', String.raw`insulat|عزل حراري`],
  ['general-building-contracting', String.raw`extension|annex|build a|construct|ملحق|بناء`],
] as [string, string][]).map(([k, src]) => [k, rx(src)]);

/** The trade of the first text that names one `known` accepts (the texts in the caller's order of authority), or null. */
export function tradeIn(texts: (string | null | undefined)[], known: (code: string) => boolean): string | null {
  for (const t of texts) {
    if (!t) continue;
    const n = normalise(t);
    for (const [k, re] of TRADE_WORDS) if (re.test(n) && known(k)) return k;
  }
  return null;
}
