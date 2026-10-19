// scripts/e2e/live_seat_conversations.mjs — ledger 1200 (12 Oct 2026): customer-facing seats hold adaptive, expert
// conversations (the custom wardrobe from a studio photo: dimensions, shelves vs hanging, door type ...), never robotic
// yes/no, never "I don't know". Seats: customer_support (suite owner), sales_engineer (knowledge). Harness: it_engineer.
//
// THE REAL SEATS, LIVE. Every agent turn is the DEPLOYED site_assistant, the code a customer reaches:
//   seat 'support'  path '/'    an anonymous visitor on the homepage widget  -> customer_support
//   seat 'sales'    path '/me'  a signed-in ZZ DEMO customer in the portal    -> sales_engineer
// The reply is written by the model there (ruling 1196: no canned reply exists to be measured). Calls carry this run's
// tag and are let through only inside its capped rehearsal window; demo accounts are torn down in the finally.
//
// THE CUSTOMER IS SCRIPTED, NOT A MODEL. Each scenario holds the customer's hidden facts, each released only when the
// agent's turn asks about it (its pattern, EN + AR). Nothing is volunteered, so the conversation measures whether the
// agent asks for what the trade needs. A summary with nothing new asked is confirmed. No spend on a simulated customer.
//
// THE GRADE, in two parts:
//   code    (every turn)  answered; no "I don't know" / "not sure" / "I'll check"; no yes/no-only reply; the reply's
//                         script is the customer's language; the first reply asks at least one question.
//   claude  (judgement)   a Claude agent on the subscription reads each transcript and scores adaptiveness,
//                         correctness, completeness and overall 0-10 (--judged <file>, never a paid judge).
//   scenario score = overall x 10 when every code gate passed, else 0. Target (ledger 1200): every one of >= 30
//   scenarios >= 95, with 0 "I don't know" and 0 yes/no-only replies.
// Every scenario below its target is a gap for the weekly audit (scripts/e2e/knowledge_gap_audit.mjs).
//
//   node scripts/e2e/live_seat_conversations.mjs run [--only a,b] [--cap-usd 6] [--out <dir>]
//   SITE_ASSISTANT_URL=http://localhost:8000 ... run   proves a branch before deploy: the function served locally (deno run) against production.
//   node scripts/e2e/live_seat_conversations.mjs score --results <run.json> --judged <judged.json>
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import sharp from 'sharp';
import { internalCred, keys, BASE, q } from '../lib/demo_factory.mjs';
import { openRun, closeRun, makeDemoCustomer, read } from './fixtures.mjs';

const argv = process.argv.slice(2);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const OUT = val('--out') || join(process.env.TEMP || '.', 'qd_live_seat_conversations');
mkdirSync(OUT, { recursive: true });
process.env.QD_FIXTURES = '1';
const MAX_AGENT_TURNS = 7;

// What a customer is asked about, in the words an agent uses (EN + AR). A fact is released when ITS pattern matches.
const R = {
  size: /size|dimension|measure|width|wide|height|high|length|long|how (big|large|many)|area|square|sqm|m2|metre|meter|قياس|مقاس|أبعاد|ابعاد|مساحة|المساحة|عرض|ارتفاع|طول|متر/i,
  where: /where|location|located|which area|emirate|community|address|villa|apartment|flat|office|building|floor|موقع|وين|أين|المنطقة|منطقة|إمارة|الإمارة|فيلا|شقة|مكتب|مبنى|طابق/i,
  when: /when|timeline|time ?frame|deadline|how soon|start|complete|finish|urgent|متى|موعد|المدة|الوقت|بحاجة.*خلال|تبدأ|الانتهاء|مستعجل/i,
  budget: /budget|price range|spend|cost range|الميزانية|ميزانية/i,
  access: /permit|approval|noc|building management|management|landlord|owner|own|rent|tenant|access|association|developer|تصريح|موافقة|المالك|مالك|ملك|إيجار|مستأجر|إدارة المبنى|المطور|عدم ممانعة/i,
  existing: /existing|current|currently|old|remove|replace|already|condition|الحالي|القديم|الموجود|إزالة|استبدال|حالة/i,
  material: /material|finish|colou?r|type|brand|spec|grade|quality|thickness|المواد|مادة|خامة|تشطيب|لون|نوع|ماركة|مواصفات|سماكة|جودة/i,
};
const f = (k, say) => [k, say];
const S = [
  { id: 'wardrobe_photo', seat: 'sales', lang: 'en', trade: 'carpentry-joinery', image: true,
    open: 'Hi, I want a custom wardrobe for my studio, here is a photo of the wall where it should go.',
    facts: [f('size', 'The wall is about 2.4 m wide and the ceiling is 2.7 m.'), f(/hang|shel|drawer|layout|inside|interior|internal|storage/i, 'Mostly hanging, plus 4 shelves and 2 drawers.'),
      f(/door|sliding|hinged|push|handle/i, 'Sliding doors, handle-less.'), f('material', 'Matte white.'), f('where', 'A rented studio in JLT, Dubai.'),
      f('access', 'I rent; the landlord is fine with it but wants to be told. Building allows work 9 to 6 on weekdays.'), f('when', 'Within 4 weeks.'), f('budget', 'Moderate, not luxury.')] },
  { id: 'kitchen_villa_ar', seat: 'sales', lang: 'ar', trade: 'kitchens',
    open: 'السلام عليكم، أريد تجديد مطبخ الفيلا بالكامل.',
    facts: [f('size', 'المطبخ على شكل L تقريباً 4 في 3 متر.'), f(/خزائن|كبائن|دواليب|خشب|لون|تشطيب|مواد|نوع/i, 'خزائن لامعة هاي جلوس، وسطح كوارتز.'),
      f(/أجهزة|فرن|شفاط|ثلاجة/i, 'أبقي الأجهزة الحالية إلا فرن مدمج جديد وشفاط.'), f(/سباكة|مواسير|مغسلة|كهرباء/i, 'السباكة تبقى في مكانها.'),
      f('existing', 'المطبخ القديم يجب إزالته.'), f('where', 'فيلا ملك في البرشاء.'), f('when', 'خلال شهرين.'), f('budget', 'متوسطة.')] },
  { id: 'ac_replacement', seat: 'support', lang: 'en', trade: 'hvac',
    open: 'My AC in the bedroom stopped cooling, I think I need to replace it.',
    facts: [f('size', 'The master bedroom is about 4 m by 4.5 m with a big west-facing window.'), f(/type|split|ducted|window unit|existing|current|old|brand|age/i, 'It is a 12-year-old wall split; the outdoor unit is on the balcony.'),
      f(/inverter|efficien|capacity|ton|btu/i, 'I want an inverter split.'), f(/pipe|copper|drain/i, 'The copper pipes look fine.'), f('where', '2-bedroom apartment in Dubai Marina.'),
      f('access', 'Building management needs a work permit.'), f('when', 'This week please.')] },
  { id: 'roof_waterproofing_ar', seat: 'support', lang: 'ar', trade: 'waterproofing',
    open: 'عندي تسريب مياه من السطح إلى غرفة النوم بعد المطر.',
    facts: [f('size', 'السطح خرسانة مستوي تقريباً 150 متر مربع.'), f('existing', 'آخر عزل قبل 10 سنوات بممبرين بيتومين، والبلاط متشقق في أماكن.'),
      f(/ضمان|كفالة/i, 'أبي عزل كامل مع ضمان.'), f(/مكيف|خزان|معدات|أجهزة على السطح/i, 'فيه وحدات مكيفات وخزان ماء على السطح.'), f('where', 'فيلا في الشارقة.'), f('when', 'مرن، قبل الشتاء.')] },
  { id: 'cctv_shop', seat: 'support', lang: 'en', trade: 'security',
    open: 'I need CCTV for my shop.',
    facts: [f('size', 'About 60 square metres, one entrance, one stock room and a cash counter.'), f(/face|cover|camera|view|see|where.*camera|record|retention|days|storage/i, 'I need to see faces at the entrance and the cash counter, view on my phone, and keep recordings as the law requires.'),
      f('existing', 'There is no existing system.'), f('where', 'A phone accessories shop in a Deira mall.'), f('access', 'Mall management requires an approved contractor.'), f('when', 'Within 2 weeks.')] },
  { id: 'floor_tiles', seat: 'sales', lang: 'en', trade: 'tiling',
    open: 'How much to replace the floor tiles in my apartment?',
    facts: [f('size', 'About 70 square metres, not counting bathrooms.'), f('existing', 'Existing ceramic tiles, some sound hollow. Not sure whether to remove them or tile over.'),
      f('material', 'Large-format porcelain 60x120, matt light grey.'), f('where', '1-bedroom apartment on Reem Island, Abu Dhabi. I own it.'),
      f(/live|living|occupied|phase|furniture|empty/i, 'I am living there, so it needs to be done in phases.'), f('when', 'Next month.')] },
  { id: 'painting_ar', seat: 'sales', lang: 'ar', trade: 'painting',
    open: 'أبي صباغة شقتي قبل ما أسلم المفتاح.',
    facts: [f('size', 'شقة غرفتين تقريباً 110 متر مربع.'), f(/لون|أبيض|سقف|أسقف|ألوان/i, 'المالك يبي الجدران والأسقف أبيض.'), f('existing', 'فيه ثقوب مسامير وبقعة رطوبة قرب الحمام.'),
      f('where', 'النهدة، دبي. أنا مستأجر.'), f(/فاضية|فارغة|أثاث|مسكونة/i, 'الشقة فاضية.'), f('when', 'خلال 5 أيام.')] },
  { id: 'pool_build', seat: 'sales', lang: 'en', trade: 'swimming-pools',
    open: 'We want to build a swimming pool in our garden.',
    facts: [f('size', 'Garden is about 12 m by 8 m; pool about 8 m by 4 m, 1.2 to 1.6 m deep.'), f(/finish|tile|mosaic|feature|shelf|light|heat|chill|temperature/i, 'Mosaic tiles, a small sun shelf, a heater-chiller and LED lights.'),
      f('where', 'Our villa in Arabian Ranches.'), f('access', 'The community needs a developer NOC and engineer drawings.'), f(/safety|child|kids|fence|cover/i, 'We have young kids, so safety matters.'), f('when', 'Before next summer.')] },
  { id: 'glass_partition_ar', seat: 'support', lang: 'ar', trade: 'glass',
    open: 'نحتاج قواطع زجاج لمكتبنا.',
    facts: [f('size', 'ثلاث غرف اجتماعات، الطول الكلي حوالي 18 متر، والارتفاع 2.8 متر.'), f(/إطار|فريم|بدون|نوع|سماكة|مطفي|مصنفر|خصوصية/i, 'بدون إطار مع شريط مصنفر.'),
      f(/باب|أبواب|منزلق|مفصلي/i, 'باب منزلق لغرفة وبابين مفصليين.'), f(/صوت|عزل/i, 'العزل الصوتي مهم.'), f('where', 'الطابق 14 في الخليج التجاري.'), f('access', 'لوائح المبنى والدفاع المدني تنطبق.'), f('when', 'خلال 6 أسابيع.')] },
  { id: 'solar_villa', seat: 'sales', lang: 'en', trade: 'solar',
    open: 'Is it worth putting solar panels on my villa?',
    facts: [f('size', 'Flat roof about 120 square metres, some shade from a water tank.'), f(/bill|consum|usage|dewa|kwh/i, 'Summer DEWA bills are around AED 3,500 a month.'),
      f(/battery|grid|off.?grid|net/i, 'Grid-connected, no batteries.'), f('where', 'Owned villa in Dubai.'), f('when', 'I want a proposal within a month.')] },
  { id: 'bathroom_refit', seat: 'support', lang: 'en', trade: 'bathrooms',
    open: 'I want to redo my bathroom completely.',
    facts: [f('size', 'About 2.5 m by 2 m, ceiling 2.6 m.'), f(/shower|bath|tub|vanity|toilet|wc|fixture|layout/i, 'Swap the bathtub for a walk-in shower, wall-hung WC, new vanity.'),
      f('material', 'Porcelain wall and floor tiles, matt black fittings.'), f(/water ?proof|leak/i, 'There was a small leak to the flat below last year.'), f('where', 'Apartment in Al Nahda, Sharjah. I own it.'), f('access', 'Building needs a permit and work hours 9 to 5.'), f('when', 'Within 6 weeks.')] },
  { id: 'gypsum_ceiling_ar', seat: 'sales', lang: 'ar', trade: 'gypsum',
    open: 'أبغى أسوي جبس بورد في الصالة مع إضاءة مخفية.',
    facts: [f('size', 'الصالة 6 في 5 متر، والارتفاع 3.2 متر.'), f(/تصميم|شكل|مستوى|مستويات|إضاءة|سبوت|ليد/i, 'سقف بمستويين مع ليد مخفي وسبوتات.'), f(/مكيف|تكييف|فتحات/i, 'فيه فتحات تكييف مركزي لازم تبقى.'),
      f('where', 'فيلا في العين.'), f('when', 'خلال 3 أسابيع.'), f('budget', 'متوسطة.')] },
  { id: 'aluminium_windows', seat: 'sales', lang: 'en', trade: 'aluminium',
    open: 'Our villa windows let in dust and heat, we want to change them.',
    facts: [f('size', '14 windows, mostly 1.5 m by 1.8 m, and two sliding doors 3 m by 2.4 m.'), f(/glass|glaz|double|thermal|break|profile|system|sound|noise/i, 'Double glazed with thermal break, it is noisy near the road too.'),
      f('material', 'Dark grey frames.'), f('existing', 'Old single-glazed aluminium, about 18 years old, to be removed.'), f('where', 'Villa in Mirdif, owned.'), f('when', 'Within 2 months.')] },
  { id: 'villa_painting_ext_ar', seat: 'support', lang: 'ar', trade: 'painting',
    open: 'نبي نصبغ واجهة الفيلا من برا.',
    facts: [f('size', 'فيلا دورين، الواجهات حوالي 400 متر مربع.'), f('existing', 'الصبغ الحالي متقشر وفيه شروخ صغيرة.'), f(/لون|نوع|تكستشر|ملمس|مواد/i, 'نفس اللون البيج، تكستشر.'),
      f(/سقالة|ارتفاع|وصول/i, 'لازم سقالة، الارتفاع حوالي 8 متر.'), f('where', 'الراشدية، دبي.'), f('access', 'الفيلا ملك.'), f('when', 'الشهر الجاي.')] },
  { id: 'office_fitout', seat: 'sales', lang: 'en', trade: 'fit-out',
    open: 'We just leased an office and need it fitted out.',
    facts: [f('size', 'About 220 square metres shell and core.'), f(/layout|room|seat|people|staff|workstation|meeting|pantry/i, '25 workstations, 2 meeting rooms, a manager office and a pantry.'),
      f(/design|drawing|plan|concept/i, 'We have no design yet; we need design and build.'), f('where', 'JLT Cluster X, Dubai.'), f('access', 'Landlord and DMCC approvals plus Civil Defence apply.'), f('when', 'Move in within 3 months.'), f('budget', 'Mid-range.')] },
  { id: 'pest_control_ar', seat: 'support', lang: 'ar', trade: 'pest-control',
    open: 'عندي صراصير في المطبخ ما راحت.',
    facts: [f('size', 'شقة 3 غرف.'), f(/أطفال|حيوان|قطط|أمان/i, 'عندي أطفال صغار وقطة.'), f(/متى بدأ|مدة|منذ|كم صار/i, 'من شهرين تقريباً.'), f('where', 'شقة في المجاز، الشارقة.'), f('when', 'هالأسبوع.'), f(/مرة|عقد|زيارات|متابعة/i, 'أبي معالجة مع زيارة متابعة.')] },
  { id: 'electrical_ev', seat: 'sales', lang: 'en', trade: 'electrical',
    open: 'I bought an electric car and need a charger at home.',
    facts: [f(/car|model|vehicle|kw|charger|power/i, 'It is a Tesla Model Y; I want a 7 kW wall charger.'), f(/distance|cable|run|park|garage|meter|board|panel|db/i, 'The parking is about 15 m from the main board, in a covered car porch.'),
      f(/load|supply|phase|capacity|dewa/i, 'Single-phase supply, I do not know the load.'), f('where', 'Villa in Dubai Hills, owned.'), f('access', 'DEWA EV Green Charger approval if needed.'), f('when', 'Within 2 weeks.')] },
  { id: 'landscaping_ar', seat: 'sales', lang: 'ar', trade: 'landscaping',
    open: 'أبغى أرتب الحديقة، عشب وإضاءة وجلسة.',
    facts: [f('size', 'الحديقة حوالي 200 متر مربع.'), f(/عشب|طبيعي|صناعي|نباتات|أشجار/i, 'عشب صناعي في جزء وطبيعي في جزء، وكم شجرة.'), f(/ري|سقي|تنقيط/i, 'نظام ري بالتنقيط أوتوماتيك.'),
      f(/جلسة|برجولا|مظلة|ممر/i, 'برجولا خشب وممر حجر.'), f('where', 'فيلا في خليفة سيتي، أبوظبي.'), f('when', 'قبل الشتاء.'), f('budget', 'متوسطة.')] },
  { id: 'carpet_office', seat: 'support', lang: 'en', trade: 'flooring',
    open: 'We need new carpet tiles for our office.',
    facts: [f('size', 'About 300 square metres open plan.'), f('existing', 'Old carpet glued down, needs removing; raised floor underneath.'), f('material', 'Commercial nylon carpet tiles, dark grey, heavy traffic.'),
      f(/night|weekend|hours|operating|occupied/i, 'Work must happen on weekends while we keep operating.'), f('where', 'Office in Business Bay, 9th floor.'), f('access', 'Building management needs a permit.'), f('when', 'Next month.')] },
  { id: 'water_tank_ar', seat: 'support', lang: 'ar', trade: 'plumbing',
    open: 'خزان الماء عندي يسرب وأبي أغيره.',
    facts: [f('size', 'خزان علوي 1000 جالون.'), f('material', 'أبي خزان فايبر جلاس أو بلاستيك مزدوج الطبقات.'), f('existing', 'الخزان الحالي فايبر قديم، والقاعدة بحالة جيدة.'),
      f(/مضخة|ضغط|مواسير/i, 'المضخة شغالة بس ضعيفة.'), f('where', 'فيلا في عجمان.'), f('when', 'بأسرع وقت.')] },
  { id: 'kitchen_cabinets_en', seat: 'support', lang: 'en', trade: 'kitchens',
    open: 'Can I just replace my kitchen cabinet doors?',
    facts: [f('size', 'About 14 doors and 6 drawer fronts.'), f('existing', 'The carcasses are fine, the doors are peeling foil.'), f('material', 'Matt sage green, handle-less with J-pull.'),
      f(/hinge|soft|close/i, 'Yes, soft-close hinges please.'), f('where', 'Townhouse in Town Square, owned.'), f('when', 'Within a month.')] },
  { id: 'interlock_paving', seat: 'sales', lang: 'en', trade: 'paving',
    open: 'I need interlock paving for my driveway.',
    facts: [f('size', 'About 90 square metres.'), f(/car|vehicle|load|traffic|heavy|use/i, 'Two cars park on it daily.'), f('existing', 'Currently sand and some broken concrete to remove.'),
      f('material', '80 mm interlock, grey and charcoal pattern.'), f(/level|slope|drain|water/i, 'Water collects near the gate.'), f('where', 'Villa in Al Warqa, owned.'), f('when', 'In 3 weeks.')] },
  { id: 'smart_home_ar', seat: 'sales', lang: 'ar', trade: 'smart-home',
    open: 'أبغى بيتي يكون سمارت، إضاءة ومكيفات وستائر.',
    facts: [f('size', 'فيلا 5 غرف، دورين.'), f(/سلكي|لاسلكي|واي فاي|نظام|منصة|تطبيق/i, 'أفضل نظام لاسلكي يشتغل من تطبيق واحد.'), f(/ستائر|ستارة/i, '8 ستائر كهربائية.'),
      f(/مكيف|تكييف/i, 'مكيفات سبليت في كل غرفة.'), f('existing', 'الفيلا مسكونة وما أبي تكسير.'), f('where', 'الخوانيج، دبي.'), f('when', 'خلال شهر.')] },
  { id: 'fence_gate', seat: 'support', lang: 'en', trade: 'metal-works',
    open: 'I need a new gate and fence for my villa.',
    facts: [f('size', 'Front boundary about 22 m; gate opening 4.5 m.'), f(/automat|motor|remote|manual|sliding|swing/i, 'An automatic sliding gate with a remote.'), f('material', 'Galvanised steel, powder-coated black, privacy panels.'),
      f('existing', 'The old fence is a low wall with railings, to be removed.'), f('where', 'Villa in Al Barsha South, owned.'), f('access', 'Community guidelines restrict the height.'), f('when', 'Within 6 weeks.')] },
  { id: 'deep_clean_ar', seat: 'support', lang: 'ar', trade: 'cleaning',
    open: 'أبي تنظيف عميق للشقة بعد التشطيب.',
    facts: [f('size', 'شقة 3 غرف تقريباً 160 متر.'), f(/غبار|بقايا|أسمنت|دهان|نوع الأوساخ/i, 'غبار جبس وبقع دهان على الأرضيات والزجاج.'), f(/زجاج|نوافذ|واجهة/i, 'النوافذ من داخل فقط.'),
      f('where', 'جميرا فيلج سيركل.'), f('when', 'يوم الخميس.'), f(/مواد|معدات|أدوات/i, 'تجيبون موادكم.')] },
  { id: 'mep_maintenance', seat: 'sales', lang: 'en', trade: 'mep-maintenance',
    open: 'We need an annual maintenance contract for our building.',
    facts: [f('size', 'A G+8 residential building, 64 apartments.'), f(/system|scope|chiller|pump|fire|lift|ac|plumb|electr/i, 'Central chillers, pumps, fire alarm and fighting, electrical and plumbing; lifts are separate.'),
      f(/response|emergency|24|ppm|visit|frequency/i, 'We need 24/7 emergency response and monthly PPM visits.'), f('where', 'Al Qusais, Dubai.'), f('access', 'We are the owners association.'), f('when', 'Contract to start on 1 January.')] },
  { id: 'curtains_ar', seat: 'sales', lang: 'ar', trade: 'curtains',
    open: 'أبغى ستائر للمجلس وغرف النوم.',
    facts: [f('size', 'المجلس فيه 3 نوافذ كل وحدة 2.5 متر عرض، وغرف النوم 4 نوافذ 1.8 متر.'), f(/نوع|قماش|بلاك ?أوت|شفاف|طبقة|خامة/i, 'بلاك أوت مع طبقة شيفون.'), f(/كهرب|يدوي|موتور|ريموت/i, 'المجلس كهربائي والغرف يدوي.'),
      f('material', 'لون رمادي فاتح.'), f('size', 'الارتفاع من السقف 3 متر.'), f('where', 'فيلا في الشارقة، الرحمانية.'), f('when', 'خلال 3 أسابيع.')] },
  { id: 'roof_pergola', seat: 'support', lang: 'en', trade: 'carpentry-joinery',
    open: 'Can you get me a pergola for my roof terrace?',
    facts: [f('size', 'About 5 m by 4 m.'), f('material', 'Aluminium louvred, white.'), f(/wind|fix|anchor|load|slab|waterproof/i, 'The terrace is waterproofed, so I do not want it drilled through.'),
      f(/light|fan|motor|heater|electric/i, 'Motorised louvres with LED lighting.'), f('where', 'Penthouse in Al Reem, Abu Dhabi.'), f('access', 'Building owners association approval needed.'), f('when', 'Before the cool season.')] },
  { id: 'gym_flooring', seat: 'sales', lang: 'en', trade: 'flooring',
    open: 'I am opening a small gym and need the right floor.',
    facts: [f('size', 'About 180 square metres.'), f(/zone|weight|free|cardio|drop|impact|activity|use/i, 'A free-weights zone with dropping, and a cardio area.'), f('material', 'Rubber tiles, 30 mm in the weights zone.'),
      f('existing', 'Bare concrete screed, level.'), f('where', 'Ground floor unit in Al Quoz.'), f('access', 'Landlord approval in hand.'), f('when', 'Within 5 weeks.')] },
  { id: 'majlis_furniture_ar', seat: 'support', lang: 'ar', trade: 'furniture',
    open: 'أبغى تفصيل جلسة مجلس عربي.',
    facts: [f('size', 'المجلس 7 في 5 متر.'), f(/شكل|توزيع|حرف|ضلع|جهات|تصميم/i, 'جلسة على ثلاث جهات بشكل U.'), f('material', 'قماش مخمل لون بيج مع ذهبي.'),
      f(/ارتفاع|عمق|جلسة أرضية|كنب/i, 'جلسة أرضية بارتفاع 25 سم.'), f('where', 'رأس الخيمة.'), f('when', 'قبل رمضان.'), f('budget', 'متوسطة إلى عالية.')] },
];

const IDK = /\b(i don'?t know|i do not know|(i'?m|i am) (not sure|unsure)|i'?ll (check|find out|get back)|i will (check|find out|get back)|can'?t help|cannot help|unable to help)\b|لا أعرف|ما أعرف|لست متأكد|مو متأكد|غير متأكد|سأتحقق|راح أتأكد|لا أستطيع المساعدة/i;
const YESNO_ONLY = /^\s*(yes|no|yeah|nope|sure|ok(ay)?|نعم|لا|أكيد|تمام|ايوه)[\s.!،,]*([^\s]+\s*){0,3}$/i;
// A READ-BACK ASKED TO BE CONFIRMED, not any sentence with 'confirm' in it (run a8ad5ed7: 'to confirm at the site visit' and
// 'للتأكيد' ended 11 conversations early as if the customer had confirmed a summary that was never given).
const CONFIRM_ASK = /(here is|here's|summary|summar|request as i have it|ملخص)[\s\S]*(correct|right|confirm)[^.?!؟]*[?؟]|(صحيح|تؤكد|أكد)[^.?!؟]*[؟?]/i;
const arabicShare = (t) => { const a = (t.match(/[؀-ۿ]/g) || []).length, l = (t.match(/[A-Za-z]/g) || []).length; return a / Math.max(1, a + l); };

export function customerTurn(s, agentText, given) {
  const out = [];
  s.facts.forEach(([k, say], i) => {
    if (given.has(i)) return;
    const re = typeof k === 'string' ? R[k] : k;
    if (re.test(agentText)) { given.add(i); out.push(say); }
  });
  if (out.length) return out.join(' ');
  if (CONFIRM_ASK.test(agentText)) return s.lang === 'ar' ? 'نعم، صحيح.' : 'Yes, that is correct.';
  return null;
}
export function codeGates(s, agentTurns) {
  const g = {
    answered: agentTurns.length > 0 && agentTurns.every((t) => t.trim() && !/^\(NO ANSWER/.test(t)),
    no_idk: !agentTurns.some((t) => IDK.test(t)),
    no_yesno_only: !agentTurns.some((t) => YESNO_ONLY.test(t)),
    language: agentTurns.every((t) => (s.lang === 'ar' ? arabicShare(t) >= 0.6 : arabicShare(t) <= 0.05)),
    asks_first: /[?؟]/.test(agentTurns[0] || ''),
  };
  return { ...g, pass: Object.values(g).every(Boolean) };
}

async function studioSketch() {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="800" height="600"><rect width="800" height="600" fill="#fbfaf5"/>
  <rect x="150" y="80" width="420" height="460" fill="none" stroke="#333" stroke-width="4"/><rect x="600" y="160" width="150" height="200" fill="#cfe6f5" stroke="#333" stroke-width="3"/>
  <text x="615" y="390" font-size="20" font-family="Arial">window</text><rect x="160" y="500" width="400" height="12" fill="#999"/><circle cx="540" cy="470" r="8" fill="#333"/>
  <text x="200" y="300" font-size="28" font-family="Arial">wardrobe here?</text></svg>`;
  return 'data:image/png;base64,' + (await sharp(Buffer.from(svg)).png().toBuffer()).toString('base64');
}

async function runSuite() {
  const ONLY = (val('--only') || '').split(',').filter(Boolean);
  const list = S.filter((s) => !ONLY.length || ONLY.includes(s.id));
  const cap = Number(val('--cap-usd') || 6);
  const { ANON } = await keys();
  const image = await studioSketch();
  const run = await openRun({ capUsd: cap, minutes: 120 });
  try {
    const jwt = { en: (await makeDemoCustomer(run, { locale: 'en' })).jwt, ar: (await makeDemoCustomer(run, { locale: 'ar' })).jwt };
    const secret = await internalCred();
    const results = [];
    for (const [n, s] of list.entries()) {
      const path = s.seat === 'sales' ? (s.lang === 'ar' ? '/ar/me' : '/me') : (s.lang === 'ar' ? '/ar' : '/');
      const tok = s.seat === 'sales' ? jwt[s.lang] : ANON;
      const conv = `qdlsc${run.tag}${n}`.slice(0, 64);
      const history = [], turns = [{ role: 'customer', text: s.open, image: !!s.image }], given = new Set();
      let stalls = 0;
      for (let t = 0; t < MAX_AGENT_TURNS; t++) {
        const message = turns.at(-1).text;
        const body = { message, lang: s.lang, path, conv, history: [...history, { role: 'user', content: message }], ...(t === 0 && s.image ? { images: [image] } : {}) };
        const r = await fetch(process.env.SITE_ASSISTANT_URL || `${BASE}/functions/v1/site_assistant?forceFunctionRegion=ap-southeast-1`, { method: 'POST', signal: AbortSignal.timeout(120000),
          headers: { apikey: ANON, Authorization: 'Bearer ' + tok, 'Content-Type': 'application/json', 'x-qd-e2e-run': run.tag, 'x-qd-e2e-secret': secret,
            // one documentation address (RFC 5737) per conversation, so 30 conversations do not share one visitor bucket
            'x-forwarded-for': `198.51.100.${1 + (n % 254)}` }, body: JSON.stringify(body) })
          .then(async (x) => ({ status: x.status, json: await x.json().catch(() => null) })).catch((e) => ({ status: 0, json: { error: e.message } }));
        const reply = String(r.json?.reply || '').trim();
        if (!reply || r.json?.rate_limited) { turns.push({ role: 'agent', text: `(NO ANSWER: ${r.status} ${r.json?.error ?? (r.json?.rate_limited ? 'rate_limited' : '')})` }); break; }
        turns.push({ role: 'agent', text: reply });
        history.push({ role: 'user', content: message }, { role: 'assistant', content: reply });
        let c = customerTurn(s, reply, given);
        if (!c) { if (++stalls > 1) break; c = s.lang === 'ar' ? 'مو متأكد، شو تنصحني؟' : 'I am not sure, what do you recommend?'; }
        turns.push({ role: 'customer', text: c });
        if (/^(Yes, that is correct\.|نعم، صحيح\.)$/.test(c)) break;
      }
      const agentTurns = turns.filter((x) => x.role === 'agent').map((x) => x.text);
      const gates = codeGates(s, agentTurns);
      const facts_released = given.size, facts_total = s.facts.length;
      results.push({ id: s.id, seat: s.seat, lang: s.lang, trade: s.trade, path, gates, facts_released, facts_total, hidden_facts: s.facts.map(([, say]) => say), transcript: turns });
      console.log(`${s.id} [${s.seat}/${s.lang}] code ${gates.pass ? 'PASS' : 'FAIL ' + JSON.stringify(gates)} facts asked ${facts_released}/${facts_total} turns ${agentTurns.length}`);
    }
    const spend = (await read(`select count(*)::int calls, coalesce(sum(cost_aed),0)::numeric(12,4) aed, string_agg(distinct model_used, ',') models from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`))[0];
    const file = join(OUT, `live_seat_conversations_${run.tag}.json`);
    writeFileSync(file, JSON.stringify({ ledger: 1200, run_tag: run.tag, measured_at: new Date().toISOString(), spend, results }, null, 1));
    console.log(`spend ${JSON.stringify(spend)}\ntranscripts: ${file}\nnext: a Claude agent scores each transcript -> score --results ${file} --judged <judged.json>`);
  } finally { await closeRun(run).catch((e) => console.error('teardown: ' + e.message)); }
}

function score() {
  const R0 = JSON.parse(readFileSync(val('--results'), 'utf8'));
  const J = JSON.parse(readFileSync(val('--judged'), 'utf8'));
  // The gates are recomputed from the transcript, so a corrected gate re-grades a stored run.
  for (const r of R0.results) r.gates = codeGates(S.find((s) => s.id === r.id), r.transcript.filter((x) => x.role === 'agent').map((x) => x.text));
  const rows = R0.results.map((r) => {
    const j = J[r.id];
    const pct = j && r.gates.pass ? Math.round(Number(j.overall) * 10) : 0;
    return { id: r.id, seat: r.seat, lang: r.lang, code: r.gates.pass, overall: j?.overall ?? null, pct, met: pct >= 95, issues: j?.issues ?? [] };
  });
  const idk = R0.results.filter((r) => !r.gates.no_idk).length, yn = R0.results.filter((r) => !r.gates.no_yesno_only).length;
  for (const r of rows) console.log(`${r.met ? 'MET ' : 'GAP '} ${r.id} [${r.seat}/${r.lang}] ${r.pct}%${r.issues.length ? ' - ' + r.issues.join('; ') : ''}`);
  const met = rows.filter((r) => r.met).length;
  const summary = { run_tag: R0.run_tag, scenarios: rows.length, met, mean_pct: Math.round(rows.reduce((a, r) => a + r.pct, 0) / rows.length), idk_conversations: idk, yesno_only_conversations: yn,
    acceptance: rows.length >= 30 && met === rows.length && idk === 0 && yn === 0 ? 'MET' : 'NOT MET', gaps: rows.filter((r) => !r.met).map((r) => ({ id: r.id, seat: r.seat, lang: r.lang, pct: r.pct, issues: r.issues })) };
  writeFileSync(val('--results').replace(/\.json$/, '.scored.json'), JSON.stringify(summary, null, 1));
  console.log(JSON.stringify({ ...summary, gaps: summary.gaps.length }));
}

if (process.argv[1]?.endsWith('live_seat_conversations.mjs')) {
  if (argv[0] === 'run') await runSuite();
  else if (argv[0] === 'score') score();
  else { console.error('usage: live_seat_conversations.mjs run|score (see the header)'); process.exit(2); }
}
export { S };
