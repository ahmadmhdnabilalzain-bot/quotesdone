// trade_classify — the deterministic trade reading of a customer's words (EN + AR). No model.
//
// THE ONE KEYWORD CLASSIFIER. inquiry_intake (classify.ts re-exports this) and customer_api's
// create_inquiry fallback both read a trade from free text; they used two maps with the same defect.
//
// WHAT WAS WRONG, MEASURED 14 Sep 2026 through the real customer path with a fire alarm layout
// titled "GROUND FLOOR FIRE ALARM SYSTEM LAYOUT": the old map matched raw substrings and counted
// one point per phrase, so
//   * "ground floor"  hit flooring ('floor'),
//   * "fire alarm"    hit security ('alarm') AND safety ('fire alarm'),
// three categories scored 1 each, and the tie went to the first key in the object — flooring. The
// same substring rule filed "break glass unit" under glass, "ceiling mounted detector" under
// gypsum, "waterproofing" under roofing ('roof') and "content" under tents ('tent').
//
// WHAT IT DOES NOW.
//   1. Phrases that name a PLACE on a drawing rather than a trade ("ground floor", "floor plan",
//      "3 floors", "ceiling mounted") are blanked before matching. They describe where, not what.
//   2. A Latin phrase matches on WORD boundaries (a trailing plural s/es is allowed; a phrase ending
//      in '*' is a stem and takes any ending). Arabic matches as a substring after normalising
//      alef/hamza/taa-marbuta, because Arabic attaches ال / و / ب to the word.
//   3. Where two phrases overlap, the LONGER one wins the span: "fire alarm" consumes "alarm",
//      "break glass" consumes "glass", "pest control" consumes nothing of fire fighting.
//   4. A phrase is worth its word count, so "manual call point" (3) outweighs a stray "pipe" (1).
// The category slugs are category_specs.category — the intake's checklist keys. Fire alarm, fire
// fighting and detection are 'safety' ("Fire Safety & Fire Fighting"), which is what
// fn_intake_slug_for_catalog returns for fire-fighting-equipment-suppliers and, from
// scripts/sql/fire_alarm_and_elv_catalogues_reach_their_checklists.sql, for
// fire-alarm-and-life-safety-suppliers too.
//
// WHAT IT DOES NOT DO. It does not decide between two genuinely different trades that score the
// same — the tie keeps the map's order, as before, and inquiry_intake's router (fn_kb_route_decide)
// is what asks the customer when a request is truly ambiguous.

export const KW: Record<string, string[]> = {
  flooring: ['floor', 'flooring', 'spc', 'vinyl', 'lvt', 'epoxy', 'parquet', 'laminate', 'tiles floor', 'marble floor', 'carpet', 'أرضيات', 'ارضيات', 'باركيه'],
  // 'facade' alone was here and filed "scaffolding for facade work" under glass; a facade is where
  // work happens, a glass facade is the trade.
  glass: ['glass', 'glazing', 'shower enclosure', 'mirror', 'partition glass', 'glass facade', 'facade glazing', 'curtain wall', 'railing glass', 'زجاج'],
  aluminium: ['aluminium', 'aluminum', 'window frame', 'sliding window', 'thermal break', 'ألمنيوم', 'المنيوم', 'الومنيوم'],
  steel: ['steel', 'metal fabrication', 'stainless', 'gate steel', 'staircase steel', 'canopy', 'حدادة'],
  gypsum: ['gypsum', 'ceiling', 'false ceiling', 'partition wall', 'drywall', 'plasterboard', 'جبس', 'اسقف معلقه', 'سقف معلق'],
  painting: ['paint*', 'painters', 'repaint*', 'wall paint', 'texture paint', 'دهان', 'صبغ'],
  carpentry: ['carpentry', 'joinery', 'wardrobe', 'kitchen cabinet', 'mdf', 'woodwork', 'wooden door', 'نجاره', 'خزائن'],
  fitout: ['fit out', 'fit-out', 'fitout', 'interior', 'renovation', 'refurbish*', 'office fitout', 'shop fitout', 'تشطيب', 'ترميم'],
  landscaping: ['landscap*', 'garden', 'gardening', 'turf', 'grass', 'irrigation', 'plants', 'softscape', 'hardscape', 'تنسيق حدائق', 'حديقه'],
  electrical: ['electric*', 'wiring', 'db board', 'lighting install*', 'electrician', 'power point', 'dewa connection', 'كهرباء', 'تمديدات كهربائيه'],
  plumbing: ['plumb*', 'water leak', 'drainage', 'sanitary', 'pipe', 'water tank', 'geyser', 'سباكه', 'تسريب مياه'],
  hvac: ['air condition*', 'hvac', 'chiller', 'ducting', 'split unit', 'fahu', 'ahu', 'cooling', 'تكييف', 'مكيف'],
  cleaning: ['clean*', 'deep clean*', 'housekeeping', 'facade cleaning', 'sofa cleaning', 'تنظيف'],
  // 'roof leak' sat in both this list and roofing's; an identical phrase in two lists always went to
  // whichever came first. It is roofing's.
  waterproofing: ['waterproof*', 'water proofing', 'membrane', 'bathroom leak', 'عزل مائي'],
  tiling: ['tiling', 'tiler', 'wall tiles', 'ceramic tiles', 'grouting', 'بلاط'],
  masonry: ['masonry', 'block work', 'blockwork', 'plaster', 'concrete', 'screed', 'لياسه', 'خرسانه'],
  mep: ['mep', 'mechanical electrical plumbing'],
  signage: ['signage', 'sign board', '3d letters', 'acrylic sign', 'led sign', 'billboard', 'لافتات', 'لوحات اعلانيه'],
  security: ['cctv', 'access control', 'security system', 'alarm', 'burglar alarm', 'intruder alarm', 'intercom', 'gate barrier', 'كاميرات مراقبه', 'نظام امني', 'انتركم'],
  scaffolding: ['scaffold*', 'scaffolding rental', 'access platform', 'سقالات'],
  upholstery: ['upholstery', 'curtain', 'curtains', 'sofa reupholster', 'blinds', 'ستائر'],
  wallpaper: ['wallpaper', 'wall covering', 'wall mural', 'ورق جدران'],
  pest: ['pest', 'pest control', 'termite', 'cockroach', 'fumigation', 'مكافحه حشرات', 'مكافحه الحشرات'],
  movers: ['moving', 'movers', 'relocation', 'shifting', 'packing', 'نقل اثاث'],
  'custom-furniture': ['custom furniture', 'bespoke furniture', 'reception desk', 'display counter'],
  acrylic: ['acrylic', 'perspex', 'plexiglass'],
  tents: ['tent', 'shade', 'car park shade', 'pergola', 'gazebo', 'مظلات'],
  // 14 Sep 2026 — fire alarm, detection and fire fighting. The legend vocabulary of a real fire alarm
  // drawing (manual callpoint, smoke / heat detector, sounder beacon, FAP) was absent, so a drawing
  // that said nothing but those words could not reach this checklist at all.
  safety: [
    'fire fighting', 'firefighting', 'fire alarm', 'fire detection', 'fire alarm control panel', 'facp', 'fap',
    'smoke detector', 'heat detector', 'multi sensor', 'call point', 'callpoint', 'manual call point', 'manual callpoint',
    'break glass', 'sounder', 'sounder beacon', 'loop isolator', 'sprinkler', 'fire extinguisher', 'hose reel',
    'fire pump', 'fire hydrant', 'fire suppression', 'fm200', 'fm-200', 'civil defence', 'civil defense',
    'emergency lighting', 'exit sign', 'fire rated cable', 'fp200',
    'انذار الحريق', 'انذار حريق', 'كاشف دخان', 'كواشف دخان', 'كاشف حراره', 'نقطه نداء', 'كسر الزجاج',
    'مكافحه الحريق', 'مكافحه حريق', 'رشاشات', 'طفايه', 'طفايات', 'الدفاع المدني', 'لوحه انذار', 'صفاره انذار', 'انارة طوارئ', 'اناره طوارئ',
  ],
  roofing: ['roof', 'roofing', 'gi sheet', 'roof tiles', 'roof leak', 'roofing sheet'],
  solar: ['solar', 'pv panel', 'photovoltaic', 'solar panel', 'طاقه شمسيه', 'الواح شمسيه'],
  'smart-home': ['smart home', 'home automation', 'automation', 'smart lighting', 'knx', 'منزل ذكي'],
  'swimming-pools': ['swimming pool', 'pool', 'jacuzzi', 'مسبح', 'حمام سباحه'],
  'interior-design': ['interior design', 'designer', 'mood board', '3d design', 'تصميم داخلي'],
  elevators: ['elevator', 'lift', 'escalator', 'مصعد', 'مصاعد'],
  // 14 Sep 2026 — founder's generators request (see inquiry_intake/generators_replay.test.ts).
  // 'مولد كهرباء' (an electricity generator) must outrank electrical's bare 'كهرباء'; the longer
  // phrase wins the span.
  generators: ['generator', 'genset', 'gen set', 'gen-set', 'backup power', 'standby power', 'مولد', 'مولّد', 'مولدات', 'مولد كهرباء', 'مولدات كهرباء'],
};

/** Alef / hamza / taa-marbuta / alef-maqsura folded, diacritics and tatweel dropped. */
export function normArabic(s: string): string {
  return String(s || '').replace(/[ً-ْـ]/g, '').replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي');
}

// Words that say WHERE on a drawing, not WHAT trade. Blanked (same length, so offsets hold).
const NOT_A_TRADE: RegExp[] = [
  /\b(?:ground|first|second|third|fourth|fifth|sixth|top|upper|lower|mezzanine|typical|basement|podium|\d+(?:st|nd|rd|th)?)\s+floors?\b/g,
  /\bfloor\s*(?:plans?|layouts?|levels?|areas?|no\.?|numbers?|to\s+ceiling)\b/g,
  /\b\d+\s+floors?\b/g, /\b(?:per|each|every|all)\s+floors?\b/g,
  /\bceiling[\s-]+(?:mounted|mount|void|height|level)\b/g,
  /(?:الطابق|طابق)\s+(?:الارضي|الاول|الثاني|الثالث)/g,
];
const blank = (s: string, re: RegExp) => s.replace(re, (m) => ' '.repeat(m.length));

type Hit = { cat: string; start: number; end: number; weight: number; phrase: string };
const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const isArabicPhrase = (p: string) => /[؀-ۿ]/.test(p);
const COMPILED: { cat: string; phrase: string; re: RegExp; weight: number }[] = [];
for (const [cat, list] of Object.entries(KW)) {
  for (const raw of list) {
    const stem = raw.endsWith('*');
    const p = normArabic(stem ? raw.slice(0, -1) : raw).toLowerCase();
    const body = esc(p).replace(/\\?[\s-]+/g, '[\\s-]+');
    const re = isArabicPhrase(p)
      ? new RegExp(body, 'g')
      : new RegExp(`(?<![a-z0-9])${body}${stem ? '[a-z]*' : '(?:e?s)?'}(?![a-z0-9])`, 'g');
    COMPILED.push({ cat, phrase: raw, re, weight: p.split(/\s+/).length });
  }
}

/** Every non-overlapping trade phrase in the text; where two overlap the longer keeps the span. */
export function tradeHits(text: string): Hit[] {
  let t = normArabic(String(text || '')).toLowerCase();
  for (const re of NOT_A_TRADE) t = blank(t, re);
  const all: Hit[] = [];
  for (const c of COMPILED) {
    c.re.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = c.re.exec(t)) !== null) { all.push({ cat: c.cat, start: m.index, end: m.index + m[0].length, weight: c.weight, phrase: c.phrase }); if (!m[0].length) c.re.lastIndex++; }
  }
  all.sort((a, b) => (b.end - b.start) - (a.end - a.start) || a.start - b.start);
  const kept: Hit[] = [];
  for (const h of all) if (!kept.some((k) => h.start < k.end && k.start < h.end)) kept.push(h);
  return kept.sort((a, b) => a.start - b.start);
}

function scores(text: string): Map<string, number> {
  const s = new Map<string, number>();
  for (const h of tradeHits(text)) s.set(h.cat, (s.get(h.cat) || 0) + h.weight);
  return s;
}

/** The single best trade, or null. Ties keep KW's order. */
export function detectCat(text: string): string | null {
  const s = scores(text);
  let best: string | null = null; let bestN = 0;
  for (const cat of Object.keys(KW)) { const n = s.get(cat) || 0; if (n > bestN) { bestN = n; best = cat; } }
  return best;
}

/** Every trade the text names, in KW order. */
export function detectTrades(text: string): string[] {
  const s = scores(text);
  return Object.keys(KW).filter((c) => (s.get(c) || 0) > 0);
}

/** The phrases that decided `cat` in this text — the keywords a supplier match can use. */
export function tradePhrases(text: string, cat: string): string[] {
  return [...new Set(tradeHits(text).filter((h) => h.cat === cat).map((h) => h.phrase.replace(/\*$/, '')))];
}
