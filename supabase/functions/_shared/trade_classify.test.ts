// deno test supabase/functions/_shared/trade_classify.test.ts
// A table of customer phrases, English and Arabic, across trades. Each row is the trade a person
// would file the request under. The first block is the case that forced the rewrite: a fire alarm
// layout titled "GROUND FLOOR ..." was filed as flooring (see the header of trade_classify.ts).
import { assertEquals } from 'jsr:@std/assert@1';
import { detectCat, detectTrades } from './trade_classify.ts';

const TABLE: [string, string][] = [
  // fire alarm / detection / fire fighting — the measured failure and its vocabulary
  ['GROUND FLOOR FIRE ALARM SYSTEM LAYOUT', 'safety'],
  ['Fire alarm installation, smoke detectors and manual call points, ground floor', 'safety'],
  ['All break glass units and sounders have loop isolators fitted', 'safety'],
  ['FAP near main entrance, heat detector c/w sounder in kitchen', 'safety'],
  ['ceiling mounted smoke detectors in 12 rooms', 'safety'],
  ['sprinkler system and hose reels for a warehouse, civil defence approval', 'safety'],
  ['fire extinguishers refill for our office', 'safety'],
  ['نحتاج نظام إنذار الحريق مع كاشف دخان في الطابق الأرضي', 'safety'],
  ['تركيب رشاشات ومكافحة الحريق لمستودع', 'safety'],
  ['كواشف دخان ونقطة نداء يدوية', 'safety'],
  // the words that used to steal it must still work for their own trades
  ['SPC flooring for 120 sqm apartment', 'flooring'],
  ['parquet floor for the living room on the first floor', 'flooring'],
  ['أرضيات باركيه لشقة', 'flooring'],
  ['CCTV cameras and access control for a villa', 'security'],
  ['burglar alarm and intercom', 'security'],
  ['كاميرات مراقبة لفيلا', 'security'],
  ['frameless glass shower enclosure', 'glass'],
  ['false ceiling gypsum board for office', 'gypsum'],
  ['سقف معلق جبس', 'gypsum'],
  ['waterproofing of the roof terrace membrane', 'waterproofing'],
  ['roof leak repair, new roofing sheets', 'roofing'],
  // many other trades, EN and AR
  ['repaint 3 bedroom villa interior walls', 'painting'],
  ['دهان شقة ثلاث غرف', 'painting'],
  ['bathroom water leak and blocked drainage', 'plumbing'],
  ['سباكة وتسريب مياه في الحمام', 'plumbing'],
  ['AC not cooling, split unit service', 'hvac'],
  ['صيانة تكييف مكيف سبليت', 'hvac'],
  ['aluminium sliding windows supply and install', 'aluminium'],
  ['نوافذ ألمنيوم لفيلا', 'aluminium'],
  ['kitchen cabinets and wardrobes joinery', 'carpentry'],
  ['garden landscaping with irrigation and artificial grass', 'landscaping'],
  ['تنسيق حدائق مع ري', 'landscaping'],
  ['deep cleaning after renovation handover', 'cleaning'],
  ['electrical wiring and DB board upgrade', 'electrical'],
  ['تمديدات كهربائية لمحل', 'electrical'],
  ['pest control for cockroaches', 'pest'],
  ['مكافحة حشرات للمطبخ', 'pest'],
  ['swimming pool construction with jacuzzi', 'swimming-pools'],
  ['مسبح لفيلا', 'swimming-pools'],
  ['passenger lift for a G+4 building', 'elevators'],
  ['مصعد لبناية', 'elevators'],
  ['solar panel installation on roof', 'solar'],
  ['diesel genset for a warehouse', 'generators'],
  ['أحتاج مولد كهرباء احتياطي لفيلا في دبي', 'generators'],
  ['scaffolding rental for facade work', 'scaffolding'],
  ['3d letters signage for shop front', 'signage'],
  ['blockwork and plaster for boundary wall', 'masonry'],
];

Deno.test('detectCat: EN/AR phrase table across trades', () => {
  const wrong = TABLE.map(([t, want]) => ({ t, want, got: detectCat(t) })).filter((r) => r.got !== r.want);
  assertEquals(wrong, []);
});

Deno.test('a place on the drawing is not a trade', () => {
  assertEquals(detectTrades('GROUND FLOOR FIRE ALARM SYSTEM LAYOUT'), ['safety']);
  assertEquals(detectTrades('floor plan attached'), []);
  assertEquals(detectTrades('3 floors building, fire alarm'), ['safety']);
});

Deno.test('a component of a trade\'s product is not a second trade (EN/AR)', () => {
  // Harness journey a, 14 Sep 2026: split into aluminium + glass.
  assertEquals(detectTrades('We need 40 aluminium windows supplied and installed. Sizes 1200 x 1500 mm, double glazed, powder coated white. Materials: thermal break aluminium frames, double glazed 6-12-6 glass'), ['aluminium']);
  assertEquals(detectTrades('نوافذ ألمنيوم مع زجاج مزدوج لفيلا'), ['aluminium']);
  assertEquals(detectTrades('wooden door with glass panel, joinery'), ['carpentry']);
  assertEquals(detectTrades('SPC flooring with tiling of the skirting'), ['flooring']);
  assertEquals(detectTrades('steel gate, painted'), ['steel']);
});

Deno.test('genuine multi-trade requests still split', () => {
  // A component named as its own job is its own trade.
  assertEquals(detectTrades('aluminium windows and a frameless glass shower enclosure'), ['glass', 'aluminium']);
  assertEquals(detectTrades('aluminium sliding windows plus a glass railing for the balcony'), ['glass', 'aluminium']);
  assertEquals(detectTrades('نوافذ ألمنيوم ومرآة زجاج للحمام'), ['glass', 'aluminium']);
  // Different trades, no component relation.
  assertEquals(detectTrades('AC not cooling, blocked drainage, and we want CCTV'), ['plumbing', 'hvac', 'security']);
  assertEquals(detectTrades('repaint the villa and replace the wooden doors'), ['painting', 'carpentry']);
  // Glass alone is glass.
  assertEquals(detectTrades('replace a broken glass pane'), ['glass']);
});

Deno.test('stems and word boundaries', () => {
  assertEquals(detectCat('the content of the tender'), null);   // 'tent' is not inside 'content'
  assertEquals(detectCat('waterproofing'), 'waterproofing');     // not roofing
  assertEquals(detectCat('landscaping works'), 'landscaping');   // stem 'landscap*'
});
