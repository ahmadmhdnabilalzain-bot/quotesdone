// photos_to_ask — THE PHOTOS A SITE-VISIT JOB ASKS FOR, DERIVED FROM THE PACK'S OWN SITE-VISIT SENTENCE (15 Nov 2026,
// sales_engineer; founder ledger 1704: "For stuff that requires a site visit. The sales engineer should ask for photos. It will
// make it easier for suppliers to quote.").
//
// WHAT IT IS. Every spec_checklist of a trade pack carries `site_visit_required_when`, the sentence that says what a visit
// would check before a firm price ("A site visit is needed for replacements and ducted systems to check pipe runs, outdoor
// unit positions, drainage and the electrical supply."). A photo can show most of what the visit checks, so the shot list is
// read off THAT sentence: each rule below matches one thing the visit checks and names the photo that shows it, in plain words
// a homeowner understands, English and Arabic. Every shot carries `from`, the exact words of the sentence it was read from, so
// a shot can never ask for something the pack does not say a visit checks
// (scripts/checks/a_site_visit_job_asks_for_the_photos_its_visit_would_check.test.mjs re-derives every list and holds it to it).
//
// WHEN THERE IS NO LIST. A sentence that names no physical look at a site (a CAD file, a tech pack, a sample, a meeting, a
// document review: 102 of the 250 sentences measured 15 Nov 2026) gets none: those jobs need a file, not a photo. A sentence that
// names a visit but nothing a photo shows (a teardown, a risk survey of an insurer) gets none either: a rule must match.
// A list has 2 to 6 shots: when fewer than three things are matched, "a wide photo of the whole area" (from the visit's own
// words) comes first, because every visit starts by looking at the place.
//
//   node scripts/kb/photos_to_ask.mjs knowledge/packs            # DRY RUN: per checklist, the list it would write
//   node scripts/kb/photos_to_ask.mjs knowledge/packs --write    # writes photos_to_ask into each pack (format kept byte for byte)
// Then: node scripts/kb/load_trade_spec_checklists.mjs knowledge/packs (the loader carries it to public.trade_spec_checklist).
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

/** The words that make a sentence a physical look at a site (a photo can stand in for part of it). */
export const VISIT = /\b(site visit|visit|site survey|survey(?:ed)?|inspection|site inspection|site measure(?:ment)?|measuring visit|site templating|templating|site test|site check|site look|site readiness check|recce|photos|on board|on-site|sees the site)\b/i;
/** A sentence that says no visit is needed, or names only a meeting or a document: never a photo list. */
const NOT_A_VISIT = /\b(not normally needed|visit is advisable before signing)\b/i;
/** Checklists whose visit no photo can stand in for (an engine teardown, an insurer's risk survey, a strip-down diagnosis). */
export const NO_PHOTOS = new Set(['aircraft_parts_mro:spec-checklist', 'insurance_brokerage:spec-checklist', 'hse_consultancy:spec-checklist',
  'iso_certification:spec-checklist', 'call_centre_bpo:spec-checklist', 'labour_supply:spec-checklist', 'event_management:spec-checklist',
  'staff_transport:spec-checklist', 'business_centres:spec-checklist', 'telecom_services:spec-checklist', 'testing_labs:spec-checklist',
  'environmental_consultancy:spec-checklist', 'energy_services:spec-checklist', 'photo_video_production:spec-checklist',
  'security_guarding:spec-checklist', 'land_survey:spec-checklist', 'logistics_moving:spec-checklist', 'it_services:spec-fibre-backbone',
  'railway_equipment:spec-checklist', 'instrumentation_automation:spec-checklist', 'calibration_services:spec-checklist',
  'uniforms_corporate_apparel:spec-checklist', 'occupational_health:spec-checklist', 'power_generators:sizing', 'drones_uav:spec-checklist',
  'records_management:spec-checklist', 'vending_machines:spec-checklist']);

/** One rule: what the visit checks (re, matched in the sentence) and the photo(s) that show it. Order is the order shots are
 *  asked in when two rules match the same sentence at the same place; otherwise shots follow the sentence. */
const R = (re, ...shots) => ({ re, shots });
export const RULES = [
  R(/\breplacements?\b|\breplacing\b|\breplace\b/i, ['Each existing unit or item to be replaced, from the front', 'كل وحدة أو قطعة سيتم استبدالها، من الأمام'],
    ['The label or nameplate on it, close up (make, model, size)', 'الملصق أو اللوحة التعريفية عليها عن قرب (الماركة، الموديل، الحجم)']),
  R(/\boutdoor unit (?:positions|locations)\b/i, ['Each outdoor unit and where it sits (roof, balcony or wall)', 'كل وحدة خارجية ومكانها (سطح، شرفة أو جدار)']),
  R(/\bpipe (?:runs|routes?)\b|\bpipework\b/i, ['The route the pipes would take, from one end to the other', 'المسار الذي ستمر به الأنابيب، من طرف إلى آخر']),
  R(/\bdrainage\b|\bdrain\b/i, ['Where the water drains (the drain point or floor drain)', 'مكان تصريف المياه (نقطة الصرف أو صرف الأرضية)']),
  R(/\belectrical supply\b|\bmain board(?: capacity)?\b|\belectrical board\b|\bthe main board\b/i, ['The electrical board (DB) with its door open, and any isolator switch near the work', 'لوحة الكهرباء مفتوحة الباب، وأي مفتاح فصل قريب من مكان العمل']),
  R(/\bexisting (?:wiring|back boxes)\b/i, ['The existing switches and sockets, with one cover off if it is safe', 'المفاتيح والمقابس الحالية، مع فك غطاء واحد إن كان ذلك آمناً']),
  R(/\bcable (?:routes?|runs)\b/i, ['Where the cables would run (ceiling, walls, trunking or trays)', 'أماكن مرور الكابلات (السقف، الجدران، المجاري أو الحوامل)']),
  R(/\bceiling voids?\b|\bceilings\b|\bexisting ceiling\b|\bceiling void\b/i, ['Inside the false ceiling through an access panel, if one opens', 'داخل السقف المستعار من فتحة الصيانة إن أمكن فتحها']),
  R(/\bcontainment\b/i, ['The existing cable trays or trunking', 'حوامل أو مجاري الكابلات الحالية']),
  R(/\btelecom rooms?\b|\bexisting panel\b|\bfire alarm panel\b|\brack locations\b/i, ['The existing panel or equipment room, with the panel front readable', 'اللوحة أو غرفة الأجهزة الحالية، مع وضوح واجهة اللوحة']),
  R(/\bcrane route\b|\bcrane position\b|\baccess for the crane\b|\boverhead obstructions\b/i, ['The open ground or road where a crane would stand, and anything overhead (wires, trees, roofs)', 'الأرض أو الطريق حيث ستقف الرافعة، وأي شيء فوقها (أسلاك، أشجار، أسقف)']),
  R(/\bdelivery route\b|\baccess hours\b|\baccess\b|\bremoval\b/i, ['The way in for workers and materials: gate, door, stairs or lift', 'طريق دخول العمال والمواد: البوابة، الباب، الدرج أو المصعد']),
  R(/\bplinths?\b|\bbase\b(?! vehicle)|\bfoundations\b|\bpad\b/i, ['What the equipment stands on (the base, plinth or slab), from the side', 'ما تقف عليه المعدات (القاعدة أو الأرضية)، من الجانب']),
  R(/\bplant room space\b|\bpump room\b|\bspace\b|\bcheck location\b/i, ['The room or space where it goes, from the doorway, showing all four sides if you can', 'الغرفة أو المساحة المخصصة لها من الباب، مع إظهار جوانبها كلها إن أمكن']),
  R(/\bconnections\b|\bsuction arrangement\b|\bexisting services\b|\bservices below\b|\bservices\b|\butilities\b/i, ['The pipes, cables and connections at the point where it will be connected', 'الأنابيب والكابلات ونقاط التوصيل في مكان التركيب']),
  R(/\bwater supply\b|\bwater point\b|\bplumbing\b/i, ['The nearest water point or pipe, and the valve that feeds it', 'أقرب نقطة مياه أو أنبوب، والمحبس الذي يغذيه']),
  R(/\bexhaust routes?\b|\bduct route\b|\bventilation\b/i, ['Where the air or exhaust would go out (window, wall or roof)', 'مخرج الهواء أو العادم (نافذة، جدار أو سطح)']),
  R(/\binstalled (?:units|equipment)\b|\basset survey\b|\bsurvey of the systems\b|\bcondition survey\b/i, ['Each installed unit, with its label or nameplate readable', 'كل وحدة مركّبة مع وضوح ملصقها أو لوحتها التعريفية']),
  R(/\broof structure\b|\broof conditions\b|\brefurbishment roofs\b|\broof-mounted\b/i, ['The roof from one corner, showing its surface and what is on it', 'السطح من إحدى الزوايا، مع إظهار سطحه وما عليه']),
  R(/\bshading\b/i, ['Anything that throws shade on the roof (walls, tanks, nearby buildings, trees)', 'كل ما يلقي ظلاً على السطح (جدران، خزانات، مبانٍ مجاورة، أشجار)']),
  R(/\bfalls\b|\blevels\b|\bunevenness\b|\bflatness\b/i, ['The surface from a low angle, so slopes and dips show', 'السطح من زاوية منخفضة لتظهر الميول والانخفاضات']),
  R(/\bleaks?\b|\bleak source\b|\bwater ingress\b|\bleak-finding\b|\bmoisture\b|\bdamp\b/i, ['Close-ups of any damp, stains or leaks, with something for scale', 'صور قريبة لأي رطوبة أو بقع أو تسريب، مع شيء يوضح الحجم']),
  R(/\bcracks?\b|\bpeeling\b|\bsubstrate(?: condition)?\b|\bexisting coating\b|\bexisting primer\b|\bcorrosion\b|\bcondition\b|\bold paper\b/i, ['Close-ups of the surface as it is now (cracks, peeling, rust or old coating)', 'صور قريبة للسطح بحالته الحالية (تشققات، تقشر، صدأ أو طلاء قديم)']),
  R(/\bexisting system\b|\bexisting structure\b|\bstructure\b|\bexisting fixings\b|\bfixing\b|\bframes\b|\bwall construction\b|\btruss\b|\bmounting\b|\banchors\b|\banchoring\b|\bties\b/i, ['Where it would be fixed: the wall, frame or structure, close enough to see what it is made of', 'مكان التثبيت: الجدار أو الإطار أو الهيكل، عن قرب يكفي لمعرفة مادته']),
  R(/\bwalls\b/i, ['Each wall to be worked on, from far enough back to see all of it', 'كل جدار سيتم العمل عليه، من مسافة تكفي لرؤيته كاملاً']),
  R(/\bmeasure(?:d|ment)?\b|\bmeasuring\b|\bopenings?\b|\bnot been measured\b|\btemplating\b|\bheadroom\b|\bside room\b|\bslab-to-slab heights\b|\bclear height\b|\bdimensions\b|\bpit\b/i, ['Each opening or area, straight on, with a tape measure across it if you have one', 'كل فتحة أو مساحة من الأمام مباشرة، مع شريط قياس عليها إن توفر']),
  R(/\bground(?: bearing)?\b|\bsoil\b|\bslab\b/i, ['The ground or floor where the work will stand', 'الأرض أو الأرضية التي سيقوم عليها العمل']),
  R(/\bneighbours\b|\bobstructions\b/i, ['The boundary and anything right next to the work (walls, neighbours, trees)', 'الحدود وكل ما يجاور مكان العمل مباشرة (جدران، جيران، أشجار)']),
  R(/\bhazardous materials\b|\bgrade the material\b|\bscrap\b/i, ['The material or items as they are now, from a few angles', 'المواد أو القطع بحالتها الحالية، من عدة زوايا']),
  R(/\bshaft\b|\bexisting shafts?\b|\btruss, pit\b/i, ['Inside the lift shaft or pit, from the landing door, if it is safe', 'داخل بئر المصعد أو الحفرة من باب الطابق، إن كان ذلك آمناً']),
  R(/\bfault-finding\b|\bmodifications\b|\bdiagnosis\b|\brepairs?\b/i, ['The fault or the part to be repaired, close up', 'العطل أو الجزء المطلوب إصلاحه عن قرب']),
  R(/\btermites\b|\bbed bugs\b|\brodents\b/i, ['Any signs of pests (droppings, damage, nests), close up', 'أي آثار للحشرات أو القوارض (فضلات، أضرار، أعشاش) عن قرب']),
  R(/\bdeep cleaning\b|\bafter-construction cleaning\b/i, ['Each room or area as it is now, from the doorway', 'كل غرفة أو مساحة بحالتها الحالية، من الباب']),
  R(/\blandlord handover condition\b|\bexisting MEP\b/i, ['The space as handed over, from each corner, with the ceiling and floor in view', 'المساحة كما سُلِّمت، من كل زاوية مع ظهور السقف والأرضية']),
  R(/\bwindows?\b|\bwindow sizes\b/i, ['Each window, straight on, from inside', 'كل نافذة من الأمام مباشرة، من الداخل']),
  R(/\bfloor load\b|\bexisting floor\b|\bscreed\b/i, ['The floor as it is now, with a close-up of its surface', 'الأرضية بحالتها الحالية، مع صورة قريبة لسطحها']),
  R(/\bdamage\b|\bframe damage\b|\bthe frame\b/i, ['Each item, whole, and a close-up of the damage', 'كل قطعة كاملة، وصورة قريبة للضرر']),
  R(/\bnameplate\b|\bold part\b|\bbase vehicle\b|\bthe vehicles' condition\b/i, ['The label or nameplate on it, close up (make, model, size)', 'الملصق أو اللوحة التعريفية عليها عن قرب (الماركة، الموديل، الحجم)']),
  R(/\btank replacement\b|\btank pad\b|\bsafety distances\b/i, ['The area around it, showing the distance to walls and doors', 'المنطقة المحيطة، مع إظهار المسافة إلى الجدران والأبواب']),
  R(/\bshielding\b/i, ['The room where the equipment will go, including its walls and door', 'الغرفة المخصصة للجهاز، بما فيها الجدران والباب']),
  R(/\bgoods and both buildings' access\b|\bthe goods\b/i, ['Each room of goods to be moved, from the doorway', 'كل غرفة فيها أغراض للنقل، من الباب']),
  R(/\bcameras\b|\bplace cameras\b/i, ['Each place you want covered by a camera, from where the camera would be', 'كل مكان تريد تغطيته بالكاميرا، من موقع الكاميرا المقترح']),
  R(/\bzones\b|\bvolume\b|\broom integrity\b|\bcylinder location\b/i, ['The room as a whole, showing doors, openings and the ceiling', 'الغرفة كاملة، مع إظهار الأبواب والفتحات والسقف']),
  R(/\bnetwork(?: coverage)?\b|\bthe network\b/i, ['The internet router or network cabinet', 'جهاز الإنترنت (الراوتر) أو خزانة الشبكة']),
  R(/\bfootfall\b|\bsite and footfall\b/i, ['The spot where it would stand and the people passing it', 'المكان الذي ستوضع فيه وحركة المارة حوله']),
];
/** A checklist whose own sentence is the founder's worked example (ledger 1704, the brief of 15 Nov 2026): its list is written
 *  out, shot by shot, and each shot still names the words of the sentence it shows. Held to the sentence like every other list. */
export const OVERRIDES = {
  'hvac:spec-split-ac': [
    ['Each indoor unit, from the front', 'كل وحدة داخلية، من الأمام', 'replacements'],
    ['Each outdoor unit and where it sits (roof, balcony or wall)', 'كل وحدة خارجية ومكانها (سطح، شرفة أو جدار)', 'outdoor unit positions'],
    ['The label (nameplate) on a unit, close up', 'الملصق (اللوحة التعريفية) على إحدى الوحدات عن قرب', 'replacements'],
    ['The route the pipes take between the indoor and outdoor units', 'مسار الأنابيب بين الوحدة الداخلية والخارجية', 'pipe runs'],
    ['Where the water from the unit drains', 'مكان تصريف المياه من الوحدة', 'drainage'],
    ['The isolator switch near the unit, or the electrical board', 'مفتاح الفصل بجانب الوحدة، أو لوحة الكهرباء', 'electrical supply'],
  ],
};
/** The first shot of a short list: the whole place, read from the visit's own words. */
export const WIDE = ['A wide photo of the whole area where the work is', 'صورة واسعة للمنطقة كاملة حيث سيتم العمل'];
export const MIN_SHOTS = 2;
export const MAX_SHOTS = 6;

/** The shot list of one checklist, or [] when its sentence names no look a photo can stand in for. */
export function photosFor(id, sentence) {
  const text = String(sentence ?? '');
  if (!text.trim() || NO_PHOTOS.has(id) || NOT_A_VISIT.test(text)) return [];
  if (OVERRIDES[id]) return OVERRIDES[id].filter(([, , from]) => text.toLowerCase().includes(from.toLowerCase())).map(([shot, shot_ar, from]) => ({ shot, shot_ar, from }));
  const visit = text.match(VISIT);
  if (!visit) return [];
  const hits = [];
  for (const [k, r] of RULES.entries()) {
    const m = text.match(r.re);
    if (m) hits.push({ k, at: m.index, from: m[0], shots: r.shots });
  }
  hits.sort((a, b) => a.at - b.at || a.k - b.k);
  const out = [];
  const seen = new Set();
  for (const h of hits) for (const [en, ar] of h.shots) {
    if (seen.has(en)) continue;
    seen.add(en);
    out.push({ shot: en, shot_ar: ar, from: h.from });
  }
  if (!out.length) return [];
  if (out.length < 3) out.unshift({ shot: WIDE[0], shot_ar: WIDE[1], from: visit[0] });
  return out.length >= MIN_SHOTS ? out.slice(0, MAX_SHOTS) : [];
}

// ── the packs, written in their own format ───────────────────────────────────────────────────────────────────────────
const asciiJson = (d, indent) => JSON.stringify(d, null, indent).replace(/[\u0080-￿]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
/** The serialiser that reproduces this file's own bytes (indent 1 or 2, Arabic escaped or not, final newline or not). */
export function formatOf(raw) {
  const d = JSON.parse(raw);
  for (const indent of [2, 1]) for (const ascii of [true, false]) for (const nl of ['\n', '']) {
    const s = (ascii ? asciiJson(d, indent) : JSON.stringify(d, null, indent)) + nl;
    if (s === raw) return (x) => (ascii ? asciiJson(x, indent) : JSON.stringify(x, null, indent)) + nl;
  }
  return null;
}
/** Each pack file with photos_to_ask set on every spec_checklist that has a site-visit sentence (absent when none). */
export function packsWithPhotos(dir) {
  const out = [];
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.json') && !x.includes('.draft') && !x.includes('.market')).sort()) {
    const raw = readFileSync(join(dir, f), 'utf8');
    const pack = JSON.parse(raw);
    let changed = false;
    const lists = [];
    for (const e of pack.entries ?? []) {
      if (e.kind !== 'spec_checklist') continue;
      const want = photosFor(e.id, e.site_visit_required_when);
      if (want.length) lists.push({ id: e.id, photos: want });
      const have = JSON.stringify(e.photos_to_ask ?? null);
      const next = want.length ? JSON.stringify(want) : 'null';
      if (have === next) continue;
      changed = true;
      if (want.length) e.photos_to_ask = want; else delete e.photos_to_ask;
    }
    out.push({ file: f, raw, pack, changed, lists });
  }
  return out;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [dir, ...flags] = process.argv.slice(2);
  if (!dir) { console.error('usage: node scripts/kb/photos_to_ask.mjs <packs dir> [--write]'); process.exit(2); }
  const packs = packsWithPhotos(dir);
  let n = 0, shots = 0, unformatted = 0;
  for (const p of packs) for (const l of p.lists) { n++; shots += l.photos.length; console.log(`${l.id}: ${l.photos.map((s) => s.shot).join(' | ')}`); }
  console.log(`${n} checklists ask for photos (${shots} shots); ${packs.filter((p) => p.changed).length} pack files would change`);
  if (!flags.includes('--write')) process.exit(0);
  for (const p of packs.filter((x) => x.changed)) {
    const fmt = formatOf(p.raw);
    if (!fmt) { unformatted++; console.error(`${p.file}: its format is not reproducible; not written`); continue; }
    writeFileSync(join(dir, p.file), fmt(p.pack));
  }
  if (unformatted) process.exit(1);
  console.log('written');
}
