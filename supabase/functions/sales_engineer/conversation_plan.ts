// WHAT THE PORTAL ASKS NEXT IS DECIDED BY CODE (customer_support owns the conversation, sales_engineer answers in it;
// ledger 1200, 27 Oct 2026). A deterministic state machine per trade: the model writes the words, code decides what
// is asked.
//
// MEASURED BEFORE (#1635 at 1e64a9eca, adaptive conversation bank, 22 scenarios on the portal seat, runs 3de61aa6 and
// ecb6b6b2, judged by a Claude session): 22/22 code gates, 0/22 at the founder's 95 %, mean 83 %. The points were lost
// to three things, each a prompt rule the model did not keep:
//   1. 10 of 22 conversations ended before the summary: the seat kept asking things the customer had no answer for.
//   2. The timeline was never asked in 5 of 22.
//   3. Re-asks in other words or another Arabic word form (كاميرا / الكاميرات; "how many rooms" then "what type is
//      your flat"), which the text-overlap filter could not see.
// So the order of the brief is no longer the model's:
//   - THE PLAN: each playbook section (knowledge/brief/conversation/*.md) carries a "Must-haves" line, read here from
//     the compiled brief. Its slots are the trade's must-haves in order, location and timing included.
//   - THE STATE: after every customer turn, code works out which slots are filled (the slot detectors below, on
//     normalised Arabic and English, plus an optional bounded extraction call for what the detectors cannot read),
//     which are "to confirm at the site visit" (they were asked and the customer was unsure or skipped them), and
//     picks the single next must-have (with the one after it as an optional second question).
//   - THE SUMMARY: when every must-have is filled or to confirm, or after SUMMARY_AFTER replies, the reply IS the
//     summary and must end by asking whether it is correct. Once confirmed, the reply tells them to press New request.
//   - RE-ASKS: a question is compared by the SLOT it targets, not its surface text; a question on a filled or
//     to-confirm slot is dropped (portal_conversation.replyFilter), whatever its wording or word form.
// What this does NOT do: write reply text (rulings 1195/1196); the model words every question and the summary.
// It does not touch the posted request either: exact specs or the quote is held stays in inquiry_intake and the line
// specs, which read the category checklists, not this plan.
// prevented by: sales_engineer/conversation_plan.test.ts, sales_engineer/portal_conversation.test.ts
import { BRIEF_TEXT } from '../_shared/brief.generated.ts';

export type Lang = 'en' | 'ar';
export interface Turn { role: 'user' | 'assistant'; content: string }

// ── normalisation: one spelling per letter, one stem per word form ─────────────────────────────────────────────────
const AR_DIGITS = '٠١٢٣٤٥٦٧٨٩';
/** Lower-case, NFKC, Arabic digits to ASCII, diacritics and tatweel removed, alef/ta marbuta/alef maqsura unified. */
export function normalise(s: string): string {
  return String(s || '').normalize('NFKC').toLowerCase()
    .replace(/[٠-٩]/g, (d) => String(AR_DIGITS.indexOf(d)))
    .replace(/[ً-ٰٟـ]/g, '')
    .replace(/[أإآٱ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي').replace(/ؤ/g, 'و').replace(/ئ/g, 'ي');
}
/** A pattern written in ordinary Arabic spelling, matched against normalise()d text. */
const rx = (src: string) => new RegExp(src.replace(/[أإآٱ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي').replace(/ؤ/g, 'و').replace(/ئ/g, 'ي')
  .replace(/§/g, '(?<![\\p{L}])(?:وال|بال|فال|لل|ال|و|ف|ب|ل)?'), 'iu');

const AR_PREFIX = /^(?:وال|فال|بال|كال|لل|ال|و|ف)(?=..)/;
/** A light stem: English plural/tense endings; Arabic article and conjunction prefixes, plural, dual and pronoun
 *  suffixes (كاميرا / الكاميرات -> كامير, غرفة / غرفتين / غرف -> غرف, شقتي / الشقة -> شق). */
export function stem(w: string): string {
  if (/[a-z]/.test(w)) return w.replace(/(ings?|ers?|ed|es|s)$/, (x) => (w.length - x.length >= 3 ? '' : x));
  let t = w.replace(AR_PREFIX, '');
  for (let i = 0; i < 2; i++) {
    const before = t;
    t = t.replace(/(?:ات|ون|ين|ان|ها|هم|كم|نا|ه|ي|ك|ا)$/, (x) => (t.length - x.length >= 2 ? '' : x));
    // the feminine t before a suffix: غرفتين and شقتي
    if (t !== before && /ت$/.test(t) && t.length >= 3) t = t.slice(0, -1);
    if (t === before) break;
  }
  return t;
}
const STOP = new Set(('a an the and or of to for in on at is are be been do does did you your yours we our us i me my it its this that these those would '
  + 'could should will can may might what which how when where who whom whose any some each every per with by from as if about into please also just '
  + 'there here have has had want like need prefer more much many than then so not no yes ok let know tell share give get make sure one two '
  + 'من في على الى عن ما ماذا هل كم اي التي الذي هذا هذه هو هي انت لك لديك عندك تريد تفضل او و ثم مع لا نعم كل اذا تبي تبغي ابي ابغي شو وش ايش بس عشان يعني').split(' '));
/** The content stems of a text, after normalisation. */
export function stems(s: string): Set<string> {
  const out = new Set<string>();
  for (const w of normalise(s).split(/[^\p{L}\p{N}]+/u)) {
    if (!w || STOP.has(w)) continue;
    const t = stem(w);
    if (t.length >= (/[a-z]/.test(t) ? 3 : 2) && !STOP.has(t)) out.add(t);
  }
  return out;
}

// ── the slot catalogue ────────────────────────────────────────────────────────────────────────────────────────────
// fill: a customer sentence gives a value for it. ask: a QUESTION asks for it. Both run on normalise()d text and are
// written in ordinary spelling (rx() normalises the pattern). Narrow on purpose where a wrong hit would drop a question
// the job needs; the plan's own labels widen ask() per trade (targets()).
export interface SlotSpec { id: string; label: string; fill: RegExp; ask: RegExp }
const MONTHS = 'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?';
const PLACES = 'dubai|abu dhabi|sharjah|ajman|ras al khaimah|rak|fujairah|umm al quwain|al ain|jlt|jvc|marina|deira|bur dubai|mirdif|al barsha|barsha|jumeirah|downtown|business bay|silicon oasis|al nahda|khalifa city|reem|yas|saadiyat|motor city|sports city|arabian ranches|palm|karama|al qusais|qusais|international city|discovery gardens|dubai hills|town square|al warqa|warqa|al quoz|jumeirah park|al rashidiya|al mizhar|khawaneej|al majaz|majaz|rahmaniya|al rahmaniya|al yasmeen|sajaa|dso'
  + '|دبي|ابوظبي|ابو ظبي|الشارقة|عجمان|راس الخيمة|الفجيرة|ام القيوين|العين|البرشاء|ديرة|مردف|جميرا|الخوانيج|النهدة|خليفة|الراشدية|المجاز|الرحمانية|الياسمين|الصجعة|الورقاء|القوز|الخليج التجاري|القصيص|ابراج بحيرات|بحيرات جميرا|الريم|ياس';
const MEASURE = /\d+(?:[.,]\d+)?\s*(?:cm|m|metres?|meters?|ft|feet|foot|sq\.?\s?m|sqm|m2|m²|square)\b|\d+(?:[.,]\d+)?\s*(?:x|by|×|في)\s*\d+|\d+(?:[.,]\d+)?\s*(?:متر|م٢|م2|سم)|(?:^|\s)(?:متر|مترين)/i;
const COUNT = rx(String.raw`\b\d+\s*(?:rooms?|bedrooms?|bed|br|windows?|doors?|units?|apartments?|flats?|floors?|storeys?|stories|tanks?|workstations?|people|staff|seats?|drawer fronts?|fronts?|panels?|points?|cameras?|wardrobes?|gallons?|litres?|liters?|ton|tons|tonnes?|kw|kva|amps?)\b|\b(?:one|two|three|four|five|six|seven|\d)[- ](?:bed(?:room)?s?|br)\b|\bstudio (?:flat|apartment)\b|\bg\s*\+\s*\d|\d+\s*(?:غرف|غرفة|نوافذ|نافذة|ابواب|باب|شقة|شقق|طابق|طوابق|ادوار|دور|خزان|جالون|لتر|طن|وحدة|وحدات|كاميرا|كاميرات)|غرفتين|غرفتان|دورين|طابقين|شقة استوديو|(?:ثلاث|اربع|خمس|ست|سبع|ثمان|عشر)\S*\s+(?:غرف|نوافذ|ابواب|ادوار|طوابق|شقق)`);
export const CATALOGUE: SlotSpec[] = [
  { id: 'size', label: 'the sizes (dimensions or area)',
    fill: rx(MEASURE.source),
    ask: rx(String.raw`\b(size|sizes|dimensions?|measurements?|width|wide|height|high|tall|length|long|depth|deep|area|square met|sqm|m2|how (big|large))\b|قياس|مقاس|ابعاد|مساحة|المساحة|عرض|ارتفاع|طول|عمق|حجم`) },
  { id: 'count', label: 'how many (rooms, units, windows, points)',
    fill: COUNT,
    ask: rx(String.raw`\bhow many (rooms|bedrooms|windows|doors|units|floors|storeys|tanks|workstations|people|staff|seats|fronts|panels|points|wardrobes|cameras)\b|\b(type|size) of (flat|apartment|home|house|villa|unit)\b|\b(studio|1-bed|one-bed|bedroom)\b[^?]{0,40}\bor\b|كم (عدد )?(غرف|غرفة|الغرف|نافذة|نوافذ|باب|ابواب|طابق|دور|خزان|وحدة|كاميرا)|عدد (الغرف|النوافذ|الابواب|الطوابق|الادوار|الوحدات|الكاميرات)|كم غرفة|استوديو[^؟]{0,40}(او|ام)|نوع الشقة|حجم الشقة`) },
  { id: 'property', label: 'the property type (villa, apartment, office, shop)',
    fill: rx(String.raw`\b(villa|apartment|flat|studio|townhouse|penthouse|office|shop|warehouse|restaurant|cafe|clinic|school|hotel|showroom|building|gym|mall)\b|فيلا|فيله|فيلت|شقة|شقت|مكتب|محل|مستودع|مطعم|عيادة|مدرسة|فندق|مبنى|بناية|عمارة`),
    ask: rx(String.raw`\b(villa|apartment|flat|townhouse|office|shop|house)\b[^?]{0,25}\bor\b[^?]{0,25}\b(villa|apartment|flat|townhouse|office|shop|house|another|other)\b|\b(type|kind) of (property|premises|building|home)\b|\b(is|are) (it|this|the (property|premises|place|unit|home))\b[^?]{0,20}\b(a|an)\s+(villa|apartment|flat|house|office|shop|warehouse|townhouse)\b|(فيلا|شقة)[^؟]{0,15}(او|ام)[^؟]{0,15}(فيلا|شقة|مكتب)|نوع العقار|(هل|هي) (هي )?(فيلا|شقة)`) },
  { id: 'location', label: 'the emirate and area',
    fill: rx(String.raw`\b(${PLACES})\b|(${PLACES})`),
    ask: rx(String.raw`\b(which|what) (emirate|area|community|city|location|neighbou?rhood|part of)\b|\bwhere is (it|the|your)\b|\bwhere are you\b|\blocated\b|\blocation\b|في (اي|أي) (امارة|منطقة)|اي (امارة|منطقة)|وين (موقع|المكان|تقع|يقع|الفيلا|الشقة|المكتب|المحل|المستودع)|اين (يقع|تقع|الموقع)|ما (هي )?المنطقة|موقع (الفيلا|الشقة|المكتب|المحل|العقار|المشروع|المستودع)|المنطقة والامارة`) },
  { id: 'ownership', label: 'whether they own or rent',
    fill: rx(String.raw`\b(own|owned|owner|rent|rented|renting|tenant|landlord|lease[sd]?)\b|ملك|مالك|ايجار|مستاجر|اجار`),
    ask: rx(String.raw`\b(are|is) you (the |a )?(tenant|owner|landlord)\b|\bown(ed)? or rent|\brent(ed|ing)? or own|\b(do|did) you (own|rent)\b|\bowner or (a |the )?tenant|\btenant or (the )?owner|تملك|(مالك|ملك)[^؟]{0,10}(ام|او)[^؟]{0,10}(مستاجر|ايجار)|(مستاجر|ايجار)[^؟]{0,10}(ام|او)[^؟]{0,10}(مالك|ملك)|هل انت (المالك|مستاجر)`) },
  { id: 'permits', label: 'the permits and approvals (building, landlord, community, authority)',
    fill: rx(String.raw`\b(permits?|noc|approvals?|approved contractor|building management|management|association|developer|municipality|civil defen[cs]e|dewa|sira|community (rules|guidelines)|work(ing)? hours|landlord (approval|consent)|allowed|guidelines|drawings first)\b|تصريح|موافقة|عدم ممانعة|ادارة المبنى|الادارة|المطور|البلدية|الدفاع المدني|لوائح`),
    ask: rx(String.raw`\b(permits?|noc|approvals?|approve|building management|management company|association|developer|municipality|landlord'?s? (approval|consent)|work(ing)? hours|community rules|allowed hours)\b|تصريح|موافقة|عدم ممانعة|ادارة المبنى|المطور|البلدية|ساعات العمل|لوائح`) },
  { id: 'existing', label: 'what is there now (the existing condition, removal, or a new installation)',
    fill: rx(String.raw`\b(existing|currently|current|old|older|no (existing|unit|system|cabling|wiring)|nothing (there|now)|new installation|new build|first time|bare|shell and core|peeling|cracked|cracks|broken|damaged|hollow|faded|\d+[- ]years?[- ]old|years old|temporary hoarding|(is|are) [a-z ]{1,30} now)\b|القديم|القديمة|الحالي|الحالية|موجود|ما فيه|ما في|لا يوجد|§جديد|ازالة|متقشر|تقشر|متشقق|شروخ|باهت|قبل \d+ سن|متهالك`),
    ask: rx(String.raw`\b(existing|current|currently|old|remove|removal|replace|replacing|replacement|new install\w*|already (there|have)|condition)\b|الحالي|الحالية|القديم|القديمة|موجود|ازالة|استبدال|§جديد (ام|او)|حالة`) },
  { id: 'finish', label: 'the material, finish and colour',
    fill: rx(String.raw`\b(white|black|grey|gray|beige|walnut|oak|sage|green|blue|charcoal|sand|off-white|cream|ivory|brown|gold|silver|mdf|plywood|laminate|lacquer|gloss|glossy|matt|matte|satin|quartz|granite|marble|porcelain|ceramic|vinyl|spc|lvt|nylon|rubber|aluminium|aluminum|steel|galvani[sz]ed|powder[- ]coated|timber|wood|wooden|fibreglass|fiberglass|plastic|velvet|fabric|acrylic|textured?|smooth|mosaic|louvred|louvered|stone|interlock|engineered|elastomeric|emulsion)\b|لون|ابيض|اسود|رمادي|بيج|جوزي|رملي|ذهبي|خشب|لامع|مطفي|هاي جلوس|كوارتز|رخام|بورسلين|سيراميك|مخمل|قماش|المنيوم|ستيل|فايبر|بلاستيك|تكستشر|ناعم|mdf`),
    ask: rx(String.raw`\b(material|materials|finish|finishes|colou?rs?|grade|thickness|brand|style|which board|type of board|board (type|and colou?r|and finish))\b|\bwhat (type|kind) of (tile|tiles|paint|board|wood|glass|fabric|stone|carpet|worktop|flooring)\b|مادة|المواد|المادة|خامة|الخامة|تشطيب|التشطيب|لون|اللون|الالوان|نوع (الخشب|البلاط|الصبغ|الدهان|القماش|الزجاج|الحجر)|سماكة|ستايل`) },
  { id: 'layout', label: 'the layout (inside arrangement, rooms, shape)',
    fill: rx(String.raw`\b(hanging|shelves|shelving|drawers?|workstations?|meeting rooms?|pantry|l[- ]shaped?|u[- ]shaped?|island|galley|straight run|zones?|open plan|half and half|walk-in shower|shower|bathtub|tub|vanity|wc|toilet|levels?|cove|spotlights?|led)\b|تعليق|رفوف|ادراج|شكل l|شكل u|جزيرة|توزيع|جهات|مستوي|مستويين|ليد|سبوت|حرف`),
    ask: rx(String.raw`\b(layout|inside|interior arrangement|internal|hanging|shelves|shelving|drawers|arrangement|shape|configuration|zones|levels|fixtures)\b|الترتيب|التقسيم|من الداخل|داخلي|تعليق|رفوف|ادراج|التوزيع|الشكل|شكل|مستويات`) },
  { id: 'doors', label: 'how the doors open (sliding, hinged, push-to-open)',
    fill: rx(String.raw`\b(sliding|hinged|push[- ]to[- ]open|bi-?fold|folding|pocket|swing|pivot|automatic|motori[sz]ed|remote)\b|سحاب|منزلق|مفصلي|مفصلية|بالضغط|اوتوماتيك|اتوماتيك|ريموت`),
    // two opening types offered as the choice; "handles or push-to-open" is the handles slot (run 91fb819d)
    ask: rx(String.raw`\b(sliding|hinged|swing|folding|bi-?fold|pivot|automatic|manual|motori[sz]ed)\b[^?]{0,40}\bor\b[^?]{0,25}\b(sliding|hinged|swing|folding|bi-?fold|pivot|automatic|manual|motori[sz]ed|push[- ]to[- ]open)\b|\b(door|doors|opening|gate) (type|style|system|mechanism)\b|\btype of (doors?|gate|opening)\b|\bhow (should|will|would|do) (the )?(doors?|gate) open\b|نوع (الابواب|الباب|البوابة)|(منزلق|سحاب|مفصلي)[^؟]{0,25}(او|ام)[^؟]{0,25}(منزلق|سحاب|مفصلي|عادي|ضغط)`) },
  { id: 'handles', label: 'handles or handle-less',
    fill: rx(String.raw`\bhandle-?less\b|\bwith handles\b|\bhandles\b|\bpush[- ]to[- ]open\b|\bgola\b|\bj-?pull\b|بدون مقابض|مقابض|بالضغط`),
    ask: rx(String.raw`\bhandles?\b[^?]{0,30}\bor\b[^?]{0,30}\b(push|handle-?less|gola|touch|j-?pull)|\b(push[- ]to[- ]open|handle-?less)\b[^?]{0,30}\bor\b[^?]{0,30}\bhandles?\b|مقابض[^؟]{0,20}(او|ام)|(بالضغط|اللمس)[^؟]{0,20}(او|ام)[^؟]{0,20}مقابض`) },
  { id: 'system', label: 'the system or type',
    fill: rx(String.raw`\b(split|ducted|concealed|cassette|vrf|package unit|inverter|wall split|window unit|wired|wireless|knx|zigbee|wi-?fi|addressable|conventional|grid[- ](tied|connected)|off[- ]grid|batter(y|ies)|hybrid|framed|frameless|membrane|bitumen|polyurethane|cementitious|ip cameras?|poe|nvr|dvr|full (system|replacement|waterproofing)|patch|design and build|blackout|black-out|sheer|chiffon|roller|motori[sz]ed|manual|ppm|visits?|follow[- ]?up|one[- ]off|24/7|emergency|comprehensive|bmu|rope access|wall-to-wall|carpet tiles|broadloom|rugs?|double[- ]glaz\w*|thermal break|toughened|tempered|laminated)\b|سبليت|مخفي|دكت|كاسيت|انفرتر|سلكي|لاسلكي|واي فاي|عنونة|تقليدي|بطاريات|بدون اطار|باطار|ممبرين|بيتومين|عزل كامل|موضعي|بلاك ?اوت|شيفون|كهربائي|يدوي|زيارة|متابعة|مزدوج|مقسى`),
    ask: rx(String.raw`\b(which system|what system|system type|type of system|kind of system|type of (unit|ac|panel|glass|glazing|curtain|blind|membrane|waterproofing|carpet|cleaning|treatment|contract)|which type|split or|ducted|wired or wireless|wireless or wired|addressable|grid|batter(y|ies)|framed or|frameless or|blackout|sheer|motori[sz]ed or|manual or|one visit|follow[- ]?up|contract|glazing|single or double|full (system|replacement)|local repair)\b|نظام|النظام|نوع (المكيف|التكييف|اللوحة|الزجاج|الستائر|العزل|القماش|المعالجة)|سلكي|لاسلكي|(مخفي|سبليت)[^؟]{0,15}(ام|او)|بلاك ?اوت|كهربائي[^؟]{0,15}(ام|او)|زيارة واحدة|عقد|عزل كامل|اعادة عزل|معالجة موضعية|موضعي|ترقيع|الضمان|ضمان|كفالة`) },
  { id: 'scope', label: 'what the job includes',
    fill: rx(String.raw`\b(chillers?|pumps?|fire alarm|fire fighting|lifts?|elevators?|plumbing and|electrical and|lighting|curtains|intercom|all (systems|rooms)|ceilings (too|as well)|walls and ceilings|inside only|outside only|interior|exterior|inside of|outside of|facade|cockroach\w*|bed ?bugs|ants|termites|rodents|rats|mice|sprinklers?|suppression|fm-?200|hose reels?|extinguishers?|post[- ]construction|deep clean|move[- ](in|out) clean\w*|design only|design and execution|re-?upholster\w*|new (pieces|pool|roof|kitchen)|leak\w*|blockage|blocked|low pressure|no hot water|replumb\w*|redo|lawn|plants|paving|pergola|lighting|charger|wall charger|\d+ ?kw|points|rewir\w*)\b|الجدران|الاسقف|النوافذ|من داخل|من برا|من الخارج|خارجي|داخلي|واجهة|صراصير|بق|نمل|نمل ابيض|فئران|رشاشات|اطفاء|مضخة|خراطيم|طفايات|بعد التشطيب|تفصيل|تنجيد|يسرب|تسريب|انسداد|ضعف الضغط|اغيره|تغيير|عشب|اضاءة|جلسة|برجولا|ممر|نباتات|اشجار|مكيفات|ستائر|شاحن`),
    ask: rx(String.raw`\b(scope|include|included|including|which (systems|items|parts|rooms|areas|walls)|what should be (smart|included|covered)|ceilings? (too|as well|included)|interior or exterior|inside or outside|which pest|what pest|sprinklers?|suppression|hose reels?|what kind of (clean|cleaning|work|job)|what needs doing|design only)\b|تشمل|يشمل|اي (الانظمة|الغرف|الاجزاء|الحشرات)|ما نوع الحشرات|داخلي ام خارجي|داخل ام خارج|رشاشات|اطفاء|ما المطلوب|ايش المطلوب`) },
  { id: 'coverage', label: 'the areas to cover and how many points',
    fill: rx(String.raw`\b(entrance|entrances|gate|parking|car park|cash counter|counter|stock ?room|perimeter|backyard|back yard|corridors?|lobby|outdoor only|outside only|indoor|outdoor|faces? at|all rooms|every room)\b|البوابة|الحوش|مواقف|المدخل|خارجي|داخلي|الكاشير|المخزن|الممرات|السور|الحديقة`),
    ask: rx(String.raw`\b(cover|coverage|which areas|what areas|which points|how many cameras|cameras? (go|should go|placed)|where (should|would|do) (you want )?(the )?cameras|indoor or outdoor|inside or outside)\b|تغطية|اماكن|المناطق|كم كاميرا|عدد الكاميرات|داخلي ام خارجي|داخل ام خارج|وين (تبي|تريد) الكاميرات|اين (تريد|تبي) الكاميرات`) },
  { id: 'performance', label: 'the performance needed',
    fill: rx(String.raw`\b(night|dark|faces?|number plates?|plates|resolution|\dk|\d ?mp|megapixels?|clear (picture|image|video)|noise|noisy|sound|acoustic|soundproof\w*|thermal|heat|hot|insulat\w*|traffic|heavy|cars? park|vehicles?|load|tons?|btu|kw|kva|capacity|bills?|consumption|kwh|weights|dropping|impact|cardio|privacy|frosted|single-phase|three-phase|single phase|three phase)\b|ليل|بالليل|الليل|واضح|وضوح|دقة|ميجا|صوت|ازعاج|العزل الصوتي|حراري|حرارة|سيارات|حمل|طن|استهلاك|فاتورة|الفاتورة|خصوصية|مصنفر`),
    ask: rx(String.raw`\b(night|resolution|faces?|plates|detail|noise|sound|acoustic|thermal|heat|load|traffic|vehicles?|cars|capacity|tonnage|tons?|btu|consumption|bills?|how much power|impact|privacy|supply|phase)\b|ليلي|الليل|بالليل|الدقة|الوضوح|الصوت|العزل الصوتي|الحمل|السيارات|الاستهلاك|الفاتورة|القدرة|الخصوصية`) },
  { id: 'recording', label: 'recording days and remote viewing',
    fill: rx(String.raw`\b\d+ days of\b|\brecord\w*|\bremote(ly)?\b|\bon (my|the|a) phone\b|\bphone app\b|\bmobile app\b|\bthe app\b|\bview(ing)? on\b|\bas the law requires\b|تسجيل|الجوال|جوال|تطبيق|عن بعد`),
    ask: rx(String.raw`\b(record|recording|retention|how many days|remote view\w*|phone|app|playback|storage|nvr)\b|تسجيل|مدة التسجيل|كم يوم|الجوال|تطبيق|المشاهدة`) },
  { id: 'services', label: 'the services and routes (pipes, cables, sockets, drains, AC grilles)',
    fill: rx(String.raw`\b(sink|plumbing|pipes?|drains?|sockets?|power points?|isolator|hob|gas|cable run|distance|from the (main )?board|main board|db|meter|ac pipes|grilles?|vents?|outdoor unit|condenser|balcony|copper)\b|مواسير|سباكة|مغسلة|كهرباء|فتحات (التكييف|تكييف)|فتحات|التمديدات|تمديدات|كيبل|اسلاك|المسافة|الطبلون|لوحة الكهرباء`),
    ask: rx(String.raw`\b(plumbing|pipes?|pipework|drains?|sockets?|power points?|gas|cables?|cabling|wiring|distance|route|outdoor unit|condenser|vents|grilles|isolator|services|how far|main (electrical )?board|distribution board|sink|hob|stove|cooker position)\b|السباكة|المواسير|الكهرباء|التمديد|التمديدات|الاسلاك|المسافة|الوحدة الخارجية|فتحات|الحوض|حوض|المغسلة|مغسلة|المجلى|الموقد|موقد|الغاز|غاز`) },
  { id: 'appliances', label: 'the appliances',
    fill: rx(String.raw`\b(oven|hob|cooker|hood|extractor|dishwasher|fridge|refrigerator|microwave|built-?in|freestanding)\b|فرن|شفاط|ثلاجة|غسالة صحون|مايكرويف|اجهزة|الاجهزة`),
    ask: rx(String.raw`\b(appliances?|oven|hob|cooker|hood|fridge|dishwasher|built-?in or|freestanding)\b|الاجهزة|فرن|شفاط|ثلاجة`) },
  { id: 'design', label: 'the drawings or design',
    fill: rx(String.raw`\b(drawings?|design|designs|consultant|architect\w*|stamped|floor ?plans?|concept|shop drawings)\b|مخطط|مخططات|تصميم|استشاري|رسومات`),
    ask: rx(String.raw`\b(drawings?|design|designs|consultant|architect\w*|floor ?plans?|shop drawings)\b|مخطط|مخططات|تصميم|استشاري|رسومات`) },
  { id: 'usage', label: 'how it is used and by whom',
    fill: rx(String.raw`\b(kids|children|child|pets?|cats?|dogs?|store|storage|cartons|hazardous|dangerous|chemicals|customers|free-?weights|weights zone|cardio|dropping|heavy traffic|family|guests|cars?|vehicles?|parking|cafe|restaurant|retail|clinic|salon|showroom|standby|backup|prime power|event)\b|اطفال|حيوان|قطة|كلب|تخزين|نخزن|كراتين|خطرة|مواد خطرة|سيارات`),
    ask: rx(String.raw`\b(kids|children|pets|who (will|uses)|used for|day to day|what (does|will) (the|your) \w+ do|(is|are) (kept|stored)|keep (in|there)|anything (else )?stored|use it for|what (will|is) (it|the space|the room) (be )?used|stored|storage|hazard\w*|what business|type of business|activity)\b|اطفال|حيوانات|اليفة|تخزن|المواد المخزنة|الاستخدام|نوع النشاط|النشاط|تستخدم`) },
  { id: 'occupancy', label: 'whether the place is occupied during the work',
    fill: rx(String.raw`\b(live there|living there|we live|i live|occupied|empty|vacant|unfurnished|phases?|weekends?|after hours|night work|keep operating|while we (work|operate)|furniture (has|must|needs) to be moved|move(d)? the furniture)\b|مسكونة|فاضية|فارغة|نسكن|ساكنين|ساكن`),
    ask: rx(String.raw`\b(occupied|empty|vacant|live (there|in it)|living there|furniture|phases|working hours|after hours|weekends?|in use)\b|مسكونة|فاضية|فارغة|ساكن|الاثاث|اثاث`) },
  { id: 'fixing', label: 'how it is fixed',
    fill: rx(String.raw`\b(drill\w*|fix(ed|ing)?|anchor\w*|ballast|base ?plates?|footings?|slab|waterproofed)\b|تثبيت|حفر|قاعدة`),
    ask: rx(String.raw`\b(fix|fixed|fixing|anchor\w*|ballast|base ?plates?|footings?|wind)\b|تثبيت|حفر|الرياح`) },
  { id: 'budget', label: 'the budget range',
    fill: rx(String.raw`\bbudget\b|\beconomy\b|\bmid-?range\b|\bpremium\b|\bluxury\b|\bmoderate\b|\baffordable\b|\baed\s?\d|\d[\d,.]*\s?(k|aed|dirhams?)\b|ميزانية|الميزانية|متوسطة|اقتصادي|فاخر|درهم|عالية`),
    ask: rx(String.raw`\bbudget\b|\bprice range\b|\beconomy,? mid-?range\b|\bmid-?range or\b|الميزانية|ميزانية|فئة السعر`) },
  { id: 'timing', label: 'when they need it done',
    fill: rx(String.raw`\b(within|in) (\d+|a|an|one|two|three|four|five|six|eight|few|couple of) (days?|weeks?|months?)\b|\b(this|next) (week|month|year)\b|\basap\b|\burgent\w*|\bby (the )?(end of )?(${MONTHS})\b|\bbefore (summer|winter|ramadan|eid|the cool season|the hot season|next summer|we open|we move|opening)\b|\bflexible\b|\bno rush\b|\bmove in\b|\bstart on\b|\bon (monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b|\b\d+ (january|february|march|april|may|june|july|august|september|october|november|december)\b|\b(1|first) (${MONTHS})\b|خلال|هذا الاسبوع|هالاسبوع|الاسبوع (القادم|الجاي)|الشهر (القادم|الجاي)|مستعجل|قبل (الشتاء|الصيف|رمضان|العيد)|مرن|باسرع وقت|اسرع وقت|يوم (الخميس|الجمعة|السبت|الاحد|الاثنين|الثلاثاء|الاربعاء)`),
    ask: rx(String.raw`\bwhen (do|would|should|can|are|is|will) (you|it|the work|this)\b|\btimeline\b|\btime ?frame\b|\bhow soon\b|\bdeadline\b|\btarget (date|completion)\b|\bstart date\b|\bby when\b|\bwhen\b[^?]{0,40}\b(start|done|finished|complete|ready|installed|open|move)\b|متى|الموعد|الاطار الزمني|المدة المطلوبة|موعد`) },
];
const SPEC = new Map(CATALOGUE.map((s) => [s.id, s]));

// THE ARTICLE IS NOT THE WORD (run e1 of 27 Oct, roof_waterproofing_ar: "هل يوجد عزل حالي" and "عزل قديم" were placed on no
// slot because the detectors spelled الحالي and القديم). Every detector is matched a second time with the article taken
// off both the text and the pattern, so الحالي also reads حالي and the other way round.
const AR_ARTICLE = /(^|[^\p{L}])(?:وال|بال|فال|كال|لل|ال)(?=\p{L}{2})/gu;
const bareText = (n: string) => n.replace(AR_ARTICLE, '$1');
const BARE = new Map<RegExp, RegExp>();
const bareOf = (re: RegExp) => {
  let b = BARE.get(re);
  if (!b) { b = new RegExp(re.source.replace(/(^|[|(\s])(?:ال)(?=[ء-ي])/g, '$1'), re.flags); BARE.set(re, b); }
  return b;
};
/** A detector on normalised text, with or without the Arabic article. */
export const hits = (re: RegExp, n: string) => re.test(n) || bareOf(re).test(bareText(n));

// ── the plan, read from the playbooks in the compiled brief ───────────────────────────────────────────────────────
/** `when`: the slot applies only once the customer's own words match it (a playbook slot written `id [a|b]`). */
export interface PlanSlot { id: string; label: string; when?: RegExp }
export interface Plan { key: string; title: string; slots: PlanSlot[] }
const MUST = /^- \*\*Must-haves[^*]*\*\*\s*(.+)$/;
/** Every playbook section's plan, keyed by each of its category codes. Throws on a slot id the catalogue lacks. */
export function plansFrom(text: string): Map<string, Plan> {
  const out = new Map<string, Plan>();
  let title = ''; let keys: string[] = [];
  for (const line of text.split('\n')) {
    const h = line.match(/^## (.+?)\s*\(([^)]+)\)\s*$/);
    if (h) { title = h[1].replace(/:.*$/, '').trim(); keys = h[2].split(',').map((k) => k.trim()); continue; }
    const m = line.match(MUST);
    if (!m || !keys.length) continue;
    const slots = m[1].split(';').map((p) => p.trim()).filter(Boolean).map((p) => {
      const [id, ...rest] = p.split(':');
      const m = id.trim().match(/^([a-z]+)\s*(?:\[([^\]]+)\])?$/);
      const sid = m?.[1] ?? id.trim();
      if (!SPEC.has(sid)) throw new Error(`playbook "${title}": unknown slot "${sid}"`);
      return { id: sid, label: rest.join(':').trim() || SPEC.get(sid)!.label, ...(m?.[2] ? { when: rx(m[2].split('|').map((w) => w.trim()).filter(Boolean).join('|')) } : {}) };
    });
    for (const k of keys) out.set(k, { key: keys[0], title, slots });
    keys = [];
  }
  return out;
}
export const PLANS = plansFrom(BRIEF_TEXT);

// ── which playbook a conversation is: the customer's own words, most specific first ───────────────────────────────
export const TRADE_WORDS: [string, RegExp][] = ([
  ['water-tank-cleaning', String.raw`tank clean|clean\w* (the |my |our )?(water )?tanks?|تنظيف (ال)?خزان`],
  ['cleaning', String.raw`\bclean(ing)?\b|\bdeep clean|تنظيف|نظافة`],
  ['pest', String.raw`\bpest|cockroach|bed ?bugs|termite|rodent|\brats?\b|\bmice\b|mosquito|صراصير|صرصور|حشرات|بق|نمل|فئران|قوارض|ناموس`],
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
  ['waterproofing', String.raw`waterproof|roof leak|leak\w* (from|through) (the )?roof|seepage|damp proof|عزل مائي|عزل السطح|تسريب|تسرب|نش`],
  ['roofing', String.raw`\bre-?roof|roof (tiles|sheets?|replacement)|new roof|سقف معدني|قرميد`],
  ['swimming-pools', String.raw`\bpool\b|swimming|مسبح|بركة سباحة`],
  ['landscaping', String.raw`\bgarden|landscap|\blawn|\bturf|irrigation|interlock|paving|driveway|حديقة|عشب|انترلوك|بلاط حوش`],
  ['tents-and-shade-structures', String.raw`pergola|\bshade\b|canopy|carport|\btent|shade sail|مظلة|مظلات|برجولا|خيمة`],
  ['blinds-curtains', String.raw`curtain|\bblinds?\b|ستائر|ستارة|برادي`],
  ['glass', String.raw`\bglass|glazing|mirror|shower enclosure|balustrade|زجاج|مرايا|مراية`],
  ['aluminium', String.raw`\bwindows?\b|alumin|upvc|curtain wall|نوافذ|شبابيك|شباك|المنيوم`],
  ['garage-doors', String.raw`garage door|roller shutter|شتر|باب كراج`],
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

/** The playbook of a conversation: the first customer message that names a trade decides it, and it stays. */
export function tradeOf(customerTexts: string[]): Plan | null {
  for (const t of customerTexts) {
    const n = normalise(t);
    for (const [k, re] of TRADE_WORDS) if (re.test(n) && PLANS.has(k)) return PLANS.get(k)!;
  }
  return null;
}

// ── the sentence helpers the state needs ──────────────────────────────────────────────────────────────────────────
export function sentencesOf(text: string): string[] {
  const out: string[] = [];
  const re = /(?:[^.!?؟\n]|(?<=\d)\.(?=\d)|[.!?؟]+(?!["')\]”’]*(?:\s|$)))*(?:[.!?؟]+["')\]”’]*(?=\s|$)|\n+|$)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(String(text || ''))) && m[0] !== '') { if (/[\p{L}\p{N}]/u.test(m[0])) out.push(m[0].trim()); }
  return out;
}
export const isQuestion = (s: string) => /[?؟]["')\]”’]*\s*$/.test(s.trim());

/** The slots a customer sentence gives a value for. */
export function fillsOf(sentence: string): string[] {
  const n = normalise(sentence);
  return CATALOGUE.filter((s) => hits(s.fill, n)).map((s) => s.id);
}
/** The slots a QUESTION asks for: the catalogue's ask patterns or, when none matches, the plan's own label for its
 *  slots (a question sharing two content stems with "the wall width, height and depth available" asks that slot, in
 *  any word form). */
export function targets(question: string, plan: Plan | null): string[] {
  const n = normalise(question);
  const out = new Set(CATALOGUE.filter((s) => hits(s.ask, n)).map((s) => s.id));
  // the labels place only what the catalogue cannot ("handles or push-to-open" is the handles slot, not the doors label)
  if (plan && !out.size) {
    const Q = stems(question);
    for (const p of plan.slots) {
      const L = stems(p.label); let k = 0; for (const x of L) if (Q.has(x)) k++;
      if (k >= 2) out.add(p.id);
    }
  }
  return [...out];
}
// "I'm not sure", "you decide", "whatever you recommend" - the asked slot is noted "to confirm", never asked again
export const UNSURE = rx(String.raw`\b(not sure|unsure|no idea|don'?t know|do not know|no preference|whatever (you|is)|you (decide|choose|tell me)|what do you (recommend|suggest)|up to you|any is fine|not decided)\b|مو متاكد|مش متاكد|ما اعرف|ما ادري|لا اعرف|غير متاكد|شو تنصح|ايش تنصح|وش تنصح|انت شو تنصح|على راحتك|اي شي|ما عندي فكرة|اللي تشوفه`);
export const CONFIRMED = /^\s*(yes|yeah|yep|correct|that is correct|that's correct|that's right|confirmed?|all good|perfect)\b|^\s*(نعم|صحيح|تمام|اكيد|أكيد|ايوه|أيوه|مضبوط|صح)/i;
// the seat asked them to confirm a read-back
export const CONFIRM_ASK = /\b(is (that|this|it|everything|all of (that|this)) (correct|right|accurate)|did I (get|capture)|(can|could) you confirm|please confirm|shall I (send|submit)|(correct|right)\s*[?]\s*$)|(صحيح|تؤكد|أكد|اكد|التأكيد|مضبوط)[^؟]*؟\s*$/i;

// ── the state machine ─────────────────────────────────────────────────────────────────────────────────────────────
/** After this many seat replies the next reply is the summary, whatever is still open (it is noted "to confirm").
 *  The bank's scripted customer gives up after two questions it cannot answer; a real one sooner. Six replies with
 *  up to two must-haves each covers the longest plan (7 slots) with room for a trap correction. */
export const SUMMARY_AFTER = 6;
export type Mode = 'none' | 'ask' | 'summary' | 'confirmed';
export interface State {
  plan: Plan | null;
  /** slot -> the customer's latest words for it */
  filled: Map<string, string>;
  /** slot -> what they said before they changed it */
  changed: Map<string, string>;
  /** asked and unsure or skipped: noted "to confirm at the supplier's site visit", never asked again */
  toConfirm: Set<string>;
  /** plan slots neither filled nor to confirm, in plan order */
  open: string[];
  next: string | null;
  also: string | null;
  mode: Mode;
  seatTurns: number;
  /** the customer's message this turn was "not sure" */
  unsure: boolean;
  /** asked together last turn, answered by a statement no detector could read: the extraction call decides these */
  undecided: string[];
}
/** Extra fills for the latest message from the extraction call (slot -> value, or 'unsure'). */
export type Extracted = Record<string, string>;
const CHANGE = rx(String.raw`\b(change|changed|actually|instead|rather|switch|no longer|not .{0,20} anymore)\b|بدل|غير|خلها|بدال|الحين ابي`);

/** Where the current job starts: after the last summary the customer confirmed (one conversation per customer,
 *  ruling 1255, so a second job months later starts a fresh plan), at the first customer message naming a trade. */
export function jobStart(turns: Turn[]): number {
  let from = 0;
  for (let i = 1; i < turns.length - 1; i++) {
    if (turns[i].role === 'user' && turns[i - 1].role === 'assistant' && CONFIRMED.test(turns[i].content)
      && sentencesOf(turns[i - 1].content).some((q) => isQuestion(q) && CONFIRM_ASK.test(q))) from = i + 1;
  }
  for (let i = from; i < turns.length; i++) if (turns[i].role === 'user' && tradeOf([turns[i].content])) return i;
  return from;
}

/** The state after the customer's latest message. `past` is every earlier turn, oldest first. */
export function planState(past: Turn[], message: string, extracted: Extracted | null = null, guard = true): State {
  const all: Turn[] = [...past, { role: 'user', content: message }];
  const turns = all.slice(jobStart(all));
  const said = turns.filter((t) => t.role === 'user').map((t) => t.content);
  const full = tradeOf(said);
  // a conditional must-have (drawings for a ducted system) joins the plan once their words call for it
  const plan = full && full.slots.some((x) => x.when)
    ? { ...full, slots: full.slots.filter((x) => !x.when || said.some((t) => hits(x.when!, normalise(t)))) } : full;
  const filled = new Map<string, string>(); const changed = new Map<string, string>(); const toConfirm = new Set<string>();
  let lastAsked: string[] = []; let lastWasSummary = false; let seatTurns = 0; let unsure = false; let undecided: string[] = [];
  turns.forEach((t, i) => {
    if (t.role === 'assistant') {
      seatTurns++;
      const qs = sentencesOf(t.content).filter(isQuestion);
      lastWasSummary = qs.some((q) => CONFIRM_ASK.test(q));
      lastAsked = [...new Set(qs.flatMap((q) => targets(q, plan)))];
      return;
    }
    const latest = i === turns.length - 1;
    const text = t.content;
    const got = new Set<string>();
    for (const s of sentencesOf(text)) {
      if (isQuestion(s) && !fillsOf(s.replace(/[?؟]\s*$/, '')).length) continue;
      const change = CHANGE.test(normalise(s));
      for (const id of fillsOf(s)) {
        got.add(id);
        const prev = filled.get(id);
        if (prev && change) { if (!changed.has(id)) changed.set(id, prev); filled.set(id, s); }
        else if (!prev) filled.set(id, s);
        else if (!prev.includes(s) && prev.length < 200) filled.set(id, prev + ' ' + s);
      }
    }
    if (latest && extracted) for (const [id, v] of Object.entries(extracted)) {
      if (!SPEC.has(id)) continue;
      if (/^unsure$/i.test(v)) { if (lastAsked.includes(id) && !filled.has(id)) toConfirm.add(id); continue; }
      if (!filled.has(id)) { filled.set(id, v); got.add(id); }
    }
    const isUnsure = UNSURE.test(normalise(text));
    if (latest) unsure = isUnsure;
    // "I'm not sure, what do you recommend?" ends in a question mark and is still an answer
    const asksBack = !isUnsure && sentencesOf(text).every(isQuestion);
    // what the seat asked last and this reply did not give: unsure or skipped -> to confirm (PORTAL_INTAKE (1)).
    // A statement answering the ONE slot asked is its answer, in their words, when it gives no other must-have
    // ("the hob is electric" answers "where are the sink and hob?"; "Within 2 weeks." answers the timing, not the
    // existing unit asked); with two asked, only the detectors or the extraction call can say which was answered,
    // and the rest is to confirm.
    const unanswered = lastAsked.filter((id) => !filled.has(id) && !got.has(id));
    if (!asksBack && unanswered.length) {
      const gavePlanSlot = [...got].some((id) => plan?.slots.some((p) => p.id === id || (p.id === 'size' && id === 'count')));
      if (!isUnsure && lastAsked.length === 1 && !gavePlanSlot) filled.set(unanswered[0], text.slice(0, 200));
      else {
        for (const id of unanswered) toConfirm.add(id);
        if (latest && !isUnsure && !got.size && !extracted) undecided = unanswered.filter((id) => plan?.slots.some((p) => p.id === id));
      }
    }
    for (const id of got) toConfirm.delete(id);
    if (!latest) lastWasSummary = false;
  });
  // A SLOT IS NEVER ASKED THREE TIMES (run fafbabb3, kitchen_villa_ar: the sink and hob positions were the next
  // must-have for three replies; the detectors placed none of the seat's Arabic questions on that slot, so it never
  // became "to confirm", every rewrite was dropped as a re-ask, and two turns took 54 s). A slot code required as the
  // next must-have for each of the last two replies that is still open was asked and not answered: it is to confirm.
  if (plan && guard) {
    const seatIdx = turns.map((t, i) => (t.role === 'assistant' ? i : -1)).filter((i) => i > 0);
    if (seatIdx.length >= 2) {
      const chosenAt = (i: number) => { const b = planState(turns.slice(0, i - 1), turns[i - 1].content, null, false); return [b.next].filter(Boolean) as string[]; };
      const [a1, a2] = [chosenAt(seatIdx.at(-2)!), chosenAt(seatIdx.at(-1)!)];
      for (const id of a1) if (a2.includes(id) && !given(filled, id)) toConfirm.add(id);
    }
  }
  const open = plan ? plan.slots.map((s) => s.id).filter((id) => !given(filled, id) && !toConfirm.has(id)) : [];
  let mode: Mode = 'none';
  if (plan) {
    if (lastWasSummary && CONFIRMED.test(message) && !CHANGE.test(normalise(message))) mode = 'confirmed';
    else if (lastWasSummary || !open.length || seatTurns >= SUMMARY_AFTER) mode = 'summary';
    else mode = 'ask';
  }
  if (mode === 'summary') for (const id of open) toConfirm.add(id);
  return { plan, filled, changed, toConfirm, open: mode === 'summary' ? [] : open, next: mode === 'ask' ? open[0] : null,
    also: mode === 'ask' ? open[1] ?? null : null, mode, seatTurns, unsure, undecided: mode === 'ask' ? undecided : [] };
}

/** A plan slot is given when its own slot is filled; the plan's 'size' also by a count ("a 2-bedroom flat"). */
export const given = (filled: Map<string, string>, id: string) => filled.has(id) || (id === 'size' && filled.has('count'));
export const labelOf = (st: State, id: string) => st.plan?.slots.find((s) => s.id === id)?.label ?? SPEC.get(id)?.label ?? id;

/** What the model is told this turn. '' when no trade plan applies (the general conversation rules stand alone). */
export function stateBlock(st: State): string {
  if (!st.plan || st.mode === 'none') return '';
  const lines = [`CONVERSATION STATE (worked out by code from the whole conversation; follow it exactly). Job: ${st.plan.title}.`];
  const given = [...st.filled].filter(([id]) => st.plan!.slots.some((s) => s.id === id) || ['property', 'ownership', 'budget', 'permits'].includes(id));
  if (given.length) lines.push('ALREADY GIVEN BY THE CUSTOMER (never ask for any of these again, in any wording):\n'
    + given.map(([id, v]) => `- ${labelOf(st, id)}: "${v.slice(0, 200)}"` + (st.changed.has(id) ? ` (they changed this; earlier: "${st.changed.get(id)!.slice(0, 120)}"; only the latest choice counts)` : '')).join('\n'));
  if (st.toConfirm.size) lines.push('TO CONFIRM AT THE SUPPLIER\'S SITE VISIT (they were unsure or skipped it; never ask again):\n'
    + [...st.toConfirm].map((id) => '- ' + labelOf(st, id)).join('\n'));
  if (st.mode === 'ask') {
    lines.push(`ASK NOW: one short question about ${labelOf(st, st.next!)}.` + (st.also ? ` You may add one more short question about ${labelOf(st, st.also)}.` : '')
      + ' Ask nothing else: no other question, and nothing listed above.' + (st.unsure ? ' They were unsure about your last question: first recommend an answer to it in one sentence, without repeating that they are unsure.' : ''));
  } else if (st.mode === 'summary') {
    lines.push('THIS REPLY IS THE SUMMARY. Open with a short phrase such as "Here is your request as I have it:" (Arabic: "هذا ملخص طلبك:"), then the job in short sentences of under 20 words each, with every value above (only the latest choice where they changed one), then the items to confirm at the site visit, if any. End with one question asking whether it is correct, such as "Is this correct?" (Arabic: "هل هذا صحيح؟"). No other question.');
  } else {
    lines.push('THEY CONFIRMED THE SUMMARY. Thank them in a few words and tell them to press "New request" (Arabic portal: "طلب جديد") to send it to verified suppliers. Ask nothing.');
  }
  return lines.join('\n');
}

// ── the bounded extraction call: what the detectors cannot read ───────────────────────────────────────────────────
/** Whether this turn needs the extraction call: only when code cannot decide. Two or more must-haves were asked
 *  together and the customer answered with a statement none of the detectors could read (with ONE asked, the answer is
 *  that slot's; with any slot read, the rest were skipped). Measured 27 Oct 2026 (run 8962e747): json_extraction runs
 *  on gpt-6-luna-pro in 7-13 s, so calling it on every turn held each turn 3 s for an answer that never arrived. */
export function needsExtraction(st: State, message: string): boolean {
  return st.mode === 'ask' && st.undecided.length > 0 && normalise(message).split(/\s+/).filter(Boolean).length >= 3 && !CONFIRMED.test(message);
}
/** The extraction request: the open slots, the seat's last question, and the message. */
export function extractionPrompt(st: State, lastSeat: string, message: string): { sys: string; input: string } {
  const slots = (st.plan?.slots ?? []).filter((s) => st.undecided.includes(s.id));
  return {
    sys: 'You read one customer message in a UAE renovation chat and report which of the listed details it states. Reply with JSON only, an object: '
      + 'each key a slot id below that the message clearly gives a value for, each value the customer\'s own words for it (under 15 words). '
      + 'If the message says they are unsure or leave it to the seat for a slot the seat just asked about, give that slot the value "unsure". '
      + 'Never guess a value the message does not state. {} when it gives none.\nSLOTS:\n' + slots.map((s) => `${s.id}: ${s.label}`).join('\n'),
    input: (lastSeat ? 'THE SEAT ASKED: ' + lastSeat.slice(-400) + '\n' : '') + 'CUSTOMER MESSAGE: ' + message.slice(0, 1200),
  };
}
/** The extraction answer, kept only where it names an open slot and its value is the customer's own words. */
export function parseExtraction(text: string, st: State, message: string): Extracted {
  const m = String(text || '').match(/\{[\s\S]*\}/);
  if (!m) return {};
  let o: Record<string, unknown>;
  try { o = JSON.parse(m[0]); } catch { return {}; }
  const out: Extracted = {}; const M = stems(message);
  for (const [k, v] of Object.entries(o ?? {})) {
    if (!st.undecided.includes(k) || typeof v !== 'string' || !v.trim()) continue;
    const val = v.trim().slice(0, 160);
    if (/^unsure$/i.test(val)) { out[k] = 'unsure'; continue; }
    let k2 = 0; for (const x of stems(val)) if (M.has(x)) k2++;
    if (k2 >= 1) out[k] = val;   // a value with none of their words is a guess, never a fill
  }
  return out;
}

/** The extraction call never holds the turn past this point, counted from the request's arrival. It runs beside the
 *  reads (1.1-3.9 s, agent_runs ms.reads, 27 Oct 2026) and takes 7-13 s (run 8962e747), so the few turns that need it
 *  wait up to about 8 s more; past it the slots stay "to confirm" as the detectors left them. */
export const EXTRACT_BY_MS = 12_000;
/** The bounded extraction call (task class json_extraction through the gateway). Resolves to the slots it read, or
 *  null when it was not needed, timed out, or failed: the detectors' state then stands. Never throws. */
export async function extractSlots(o: { gateway: string; secret: string; st: State; lastSeat: string; message: string; deadline: number },
  f: typeof fetch = fetch): Promise<{ slots: Extracted; ms: number } | null> {
  if (!needsExtraction(o.st, o.message)) return null;
  const t0 = Date.now(); const ms = o.deadline - t0;
  if (ms < 1_500) return null;
  const p = extractionPrompt(o.st, o.lastSeat, o.message);
  try {
    const r = await f(o.gateway, { method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(ms),
      body: JSON.stringify({ __secret: o.secret, fn: 'sales_engineer', agent: 'sales_engineer', task_class: 'json_extraction', sys: p.sys, input: p.input,
        max: 200, temperature: 0, cache_ttl_min: 0, try_faq: false, client_timeout_ms: ms }) });
    const j = await r.json().catch(() => null) as { content?: unknown } | null;
    if (typeof j?.content !== 'string') return null;
    return { slots: parseExtraction(j.content, o.st, o.message), ms: Date.now() - t0 };
  } catch { return null; }
}
