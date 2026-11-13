// identity_places.test.ts — nothing below the emirate crosses, and the emirate does (13 Nov 2026, founder ledger 1683).
// The LEAKED rows are the anonymity audit's own probes (REPORT_A L1/L4, REPORT_C L2: every one passed every scrubber
// before); the KEEP rows are the round's over-redaction list. Both halves must hold, through the shared list that every
// scrubber runs (identity_text.scrubIdentityText) and through the residual scan that holds a drawing page.
// deno test --no-lock supabase/functions/_shared/identity_places.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { placeSpans, reducePlaces } from './identity_places.ts';
import { identityShapesIn, scrubIdentityText } from './identity_text.ts';

// [input, exactly what crosses]
const REDUCE: [string, string][] = [
  ['Villa 15, Al Barsha 2, Dubai', 'Dubai'],
  ['Al Barsha 2, Villa 15, Dubai', 'Dubai'],
  ['Dubai, Al Barsha 2, Villa 15', 'Dubai'],
  ['Site is Villa 15 Al Barsha 2', 'Site is Dubai'],
  ['The house is in Al Barsha 2 near Mall of the Emirates', 'The house is in Dubai'],
  ['3 bathrooms in a villa near Mall of the Emirates', '3 bathrooms in a villa in Dubai'],
  ['الفيلا في البرشاء 2 قرب مول الإمارات، فيلا رقم 15', 'الفيلا في دبي'],
  ['Plot No. 373-4512 in Al Barsha South', 'Dubai'],
  ['Apartment 1204, Marina Gate 2 tower, Dubai Marina', 'Dubai'],
  ['visit our showroom in Al Quoz', 'visit our showroom in Dubai'],
  ['from our Al Quoz warehouse', 'from our Dubai warehouse'],
  ['Showroom 12, Al Quoz Industrial Area 3, Dubai', 'Dubai'],
  ['Office 735, ZZ Palm IU8 Tower, Al Quoz Industrial Area 3, Dubai.', 'Dubai.'],
  ['Villa 23, Street 14, Jumeirah 1, Dubai', 'Dubai'],
  ['مكتب ١٢، برج الخليج، دبي', 'دبي'],
  ['مكتب رقم ١٢ - بناية النور - الشارقة', 'الشارقة'],
  ['Interior painting in Al Nahda, Sharjah', 'Interior painting in Sharjah'],
  ['Interior painting of a villa in Business Bay, Dubai', 'Interior painting of a villa in Dubai'],
  ['Landscaping in Khalifa City, Abu Dhabi', 'Landscaping in Abu Dhabi'],
  ['Khalifa City A villa', 'Abu Dhabi villa'],
  ['my villa in Al Ain', 'my villa in Abu Dhabi'],
  ['warehouse in Mussafah M-37', 'warehouse in Abu Dhabi'],
  ['Sharjah Industrial Area 6', 'Sharjah'],
  ['Unit 12, Block B, Dubai', 'Dubai'],
  ['villa in JVC', 'villa in Dubai'],
  ['in the Marina, Dubai', 'in the Dubai'],
  ['Delivery from Jebel Ali Industrial Area 2 warehouse', 'Delivery from Dubai warehouse'],
  ['شقة في الخليج التجاري، دبي', 'شقة في دبي'],
  ['فيلا في مدينة خليفة', 'فيلا في أبوظبي'],
];
// [input, what must be gone] — the place names no emirate, so the caller's mark replaces it.
const REMOVE: [string, string][] = [
  ['Makani 12345 67890', '67890'], ['Makani number: 1234567890', '1234567890'], ['مكاني ١٢٣٤٥ ٦٧٨٩٠', '٦٧٨٩٠'], ['Location 25.1123, 55.2001', '25.1123'],
  ['what3words ///filled.count.soap', 'filled'], ['Pin: ///filled.count.soap', 'filled'], ['villa in Al Nahda', 'Nahda'], ['near Sheikh Zayed Road', 'Zayed'],
  ['Villa 15 please quote', 'Villa 15'], ['فيلا رقم 15', '15'], ['شارع الشيخ زايد', 'زايد'], ['Street 14, near ENOC petrol station', 'ENOC'],
];
const KEEP = ['Marina blue emulsion 2 coats', 'Jumeirah collection wallpaper 10 rolls', 'Dubai Municipality approved', 'Sharjah-made concrete blocks', 'DEWA connection',
  '3-bedroom villa', '2 villas', 'villa has two floors', 'Unit 6, 2 TR', 'plot area 500 m2', 'Villa 4 bedrooms', 'Cooling Tower CT-1 1 nos', 'Main Building ground floor',
  'Room 0450 x 1200', 'Office 1 nos', 'Al Ain Ready Mix', 'next to DB-01', 'near the main door', 'JVC TV 55 inch', 'DIP switch 8 way', 'Supply Of Steel For Tower', 'Level 3 slab',
  'Steel Tower 2 nos', 'Access Road paving 200 m2', 'Valves DN 050/065/080 2 nos each', 'Project Manager Full Time On Site', 'Interior painting in Dubai', 'Supply to Abu Dhabi',
  'يتم الاستلام من قبل المهندس المشرف على المشروع', 'مع الشكر للتعاون', 'شركة التأمين تتحمل التكاليف', 'المرور من الباب الرئيسي', 'Masafi water dispenser 2 nos',
  'Liwa dates 5 kg', 'Kitchen near the window', 'Tower crane hire 3 months', 'SHALLOW END FFL -1.20 DEEP END FFL -1.80', 'Price 25.1123 55.2001 per kg'];

Deno.test('a place below the emirate becomes the emirate; next to the emirate it is removed and the emirate stays', () => {
  for (const [s, want] of REDUCE) assertEquals(reducePlaces(s, '[X]'), want, s);
});
Deno.test('a place that names no emirate is removed with the caller\'s mark', () => {
  for (const [s, gone] of REMOVE) { const out = reducePlaces(s, '[X]'); assert(!out.includes(gone), `${s} -> ${out}`); assert(out.includes('[X]'), `${s} -> ${out}`); }
});
Deno.test('KEEP: a colour, a range, an authority, a count, a size, a level is not a place', () => {
  const bad = KEEP.filter((s) => reducePlaces(s, '[X]') !== s || placeSpans(s).length).map((s) => `${s} -> ${reducePlaces(s, '[X]')}`);
  assertEquals(bad, []);
});
Deno.test('the shared list every scrubber runs reduces places too, and the residual scan reads them', () => {
  assertEquals(scrubIdentityText('Villa 15, Al Barsha 2, Dubai', '[removed]'), 'Dubai');
  assertEquals(scrubIdentityText('visit our showroom in Al Quoz, call 050 123 4567', '[removed]'), 'visit our showroom in Dubai, call [removed]');
  assert(identityShapesIn('AL BARSHA 2').includes('place'));
  assert(identityShapesIn('(Survey by ZZ Demo Surveyors, Al Barsha 2)').includes('place'));
  assert(!identityShapesIn('Interior painting in Dubai').includes('place'));
});
Deno.test('every gazetteer name reduces after a place cue, and its emirate is the one written (one sample per emirate)', () => {
  for (const [s, want] of [['villa in Mirdif', 'villa in Dubai'], ['shop in Muwaileh', 'shop in Sharjah'], ['villa in Al Reem Island', 'villa in Abu Dhabi'],
    ['flat in Al Nuaimiya', 'flat in Ajman'], ['villa in Al Dhait', 'villa in Ras Al Khaimah'], ['farm in Falaj Al Mualla', 'farm in Umm Al Quwain'], ['villa in Mirbah', 'villa in Fujairah'],
    ['villa in Hatta', 'villa in Dubai'], ['shop in Khor Fakkan', 'shop in Sharjah']] as const) assertEquals(reducePlaces(s, '[X]'), want);
});
Deno.test('no place pattern backtracks: long text reduces in well under a second', () => {
  for (const s of ['Al '.repeat(4000), 'Villa '.repeat(3000), 'near '.repeat(3000) + 'Mall', 'A B C D E F G '.repeat(1500) + 'Tower', 'شارع '.repeat(3000), '1 '.repeat(8000)]) {
    const t0 = performance.now(); reducePlaces(s, '[X]'); const ms = performance.now() - t0;
    assert(ms < 1000, `${ms.toFixed(0)} ms for ${JSON.stringify(s.slice(0, 30))}`);
  }
});

// The independent review's 60 place probes (13 Nov 2026; 18 leaked on the first version, 4 on the second). One is left to
// the model-based second reader: a sub-community nobody listed ("Cedre Villas").
const REVIEW_PROBES: [string, string][] = [
  ['الفيلا في البرشـاء ٢', 'برش'], ['في البرشاء٢', 'برش'], ['فيلا رقم ١٥، البرشاء، دبي', '١٥'], ['بالبرشاء', 'برش'], ['منطقة القوز الصناعية ٣', 'قوز'],
  ['فيلا رقم ۱۵', '۱۵'], ['فيلا ١٥', '١٥'], ['فيلا رقم ١٥ في الجميرا', 'جمير'], ['شقة رقم ١٢٠٤ برج الخليج', '١٢٠٤'], ['قرب مسجد الفاروق', 'الفاروق'],
  ['أم سقيم ٣، فيلا ٢٢', 'سقيم'], ['المنطقة: البرشا جنوب', 'برش'], ['في حي الورقاء الأول', 'ورقاء'], ['مكاني ١٢٣٤٥ ٦٧٨٩٠', '٦٧٨٩٠'], ['الإحداثيات ٢٥٫١١٢٣، ٥٥٫٢٠٠١', '٢٥٫١١٢٣'],
  ['Al-Barsha 2', 'Barsha'], ['AL BARSHA SOUTH', 'BARSHA'], ['Barsha2', 'Barsha'], ['Al Barsha Second', 'Barsha'], ['Villa no. 15', '15'], ['Villa#15', '15'], ['V-15, Al Barsha', 'V-15'],
  ['villa fifteen in Al Barsha', 'fifteen'], ['Bldg 4, Al Barsha', 'Bldg 4'], ['Flat 1204', '1204'], ['Jumeirah 3', 'Jumeirah'], ['Umm Suqeim 3', 'Suqeim'], ['Springs 5', 'Springs'],
  ['Meadows 2 villa', 'Meadows'], ['Arabian Ranches 2', 'Ranches'], ['Damac Hills 2', 'Damac'], ['Jumeirah Beach Road', 'Jumeirah'], ['The villa is in Jumeirah', 'Jumeirah'],
  ['Al Nahda 2', 'Nahda'], ['Al Nahda, Sharjah', 'Nahda'], ['Site: Dubai Silicon Oasis, Cedre Villas', 'Cedre'], ['Jumeirah Village Circle District 12', 'District 12'],
  ['JVC, District 12', 'District'], ['Motor City, Uptown Mirdif', 'Uptown'], ['Emirates Hills villa E-23', 'E-23'], ['Sector E-23 Emirates Hills', 'E-23'], ['near ENOC on Al Khail', 'ENOC'],
  ['opp. Lulu', 'Lulu'], ['behind Carrefour Mirdif', 'Carrefour'], ['next to Burjuman metro', 'Burjuman'], ['Burjuman Centre', 'Burjuman'], ['in Silicon Oasis', 'Silicon'],
  ['villa in Al Barsha 2, Dubai. Makani 12345 67890', '67890'], ['location pin 25.1123,55.2001', '25.1123'], ['25°06\'44"N 55°12\'00"E', '25°'], ['Plot 373-4512', '4512'],
  ['plot no 6457', '6457'], ['Land no. 373-4512', '4512'], ['Building 7, Street 14, Al Quoz 4', 'Quoz'], ['Street 14, Al Quoz', 'Street 14'], ['Hessa Street', 'Hessa'],
  ['Sheikh Zayed Road, Al Barsha 1', 'Barsha'], ['Mohammed Bin Rashid Boulevard', 'Boulevard'], ['Downtown, Burj Vista tower 1', 'Vista'], ['Palm Jumeirah Frond K villa 12', 'Frond'],
];
const SECOND_READER = new Set(['Site: Dubai Silicon Oasis, Cedre Villas']);
Deno.test('the review\'s place probes: every one the code layer owns is gone', () => {
  const left = REVIEW_PROBES.filter(([s]) => !SECOND_READER.has(s)).map(([s, n]) => [s, scrubIdentityText(s, '[X]'), n]).filter(([, o, n]) => o.toLowerCase().includes(n.toLowerCase()));
  assertEquals(left, []);
});

// The second review's 40 place probes (13 Nov 2026; 12 leaked) and its letterhead addresses: a NUMBERED premises beside a
// cue-only name is an address ("Office 14, Hatta"). One is the second reader's: a sub-community nobody listed ("Khannour").
const REVIEW_PROBES_2: [string, string][] = [
  ['Villa 23, Street 5, Al Safa 2', 'Safa'], ['Al Safa 1, Dubai', 'Safa'], ['Al Wasl area villa', 'Wasl'], ['Umm Al Sheif villa 7', 'Sheif'], ['in Al Manara 3', 'Manara'],
  ['Arabian Ranches 3, Sun', 'Ranches'], ['Townhouse 112 in Town Square', '112'], ['The Springs 14, street 3', 'Springs'], ['Emirates Hills Sector W', 'Emirates Hills'], ['Jumeirah Islands cluster 22', 'cluster 22'],
  ['DIP 2, warehouse 45', 'warehouse 45'], ['Ras Al Khor Industrial Area 2', 'Khor'], ['Al Qusais Industrial Area 4 warehouse', 'Qusais'], ['Sharjah Industrial Area 13', 'Area 13'], ['Ajman Industrial 1', 'Industrial 1'],
  ['Mussafah M-37', 'M-37'], ['ICAD 3 plot 12', 'plot 12'], ['Musaffah Shabiya ME-10', 'ME-10'], ['Khalifa City SE-45 villa 3', 'SE-45'], ['Al Reem Island, Sky Tower', 'Sky Tower'],
  ['Saadiyat Beach villas no. 40', '40'], ['Yas Acres villa 900', '900'], ['Al Raha Gardens, Khannour community', 'Khannour'], ['Sharjah, Muwaileh Commercial', 'Muwaileh'],
  ['Al Majaz 3 near Al Majaz waterfront', 'Majaz'], ['Aljada, block C', 'Aljada'], ['Ajman, Al Rawda 3 villa 12', 'Rawda'], ['RAK, Mina Al Arab, villa 9', 'Mina'], ['Fujairah, Al Faseel area', 'Faseel'],
  ['UAQ, Al Salamah', 'Salamah'], ['شارع الوصل، فيلا ١٢', '١٢'], ['منطقة الصفا ٢', 'الصفا'], ['مصفح الصناعية م ٣٧', 'مصفح'], ['المدينة الصناعية بالشارقة ١٣', '١٣'], ['قرب دوار الساعة', 'الساعة'],
  ['في عجمان، النعيمية ٣', 'النعيمية'], ['شقة ٥٠٤ برج الأميرة', '٥٠٤'], ['مكتب ٣٠٢، بناية الملا، ديرة', 'الملا'], ['near Dubai Hospital, Deira', 'Hospital'], ['behind Al Ghurair Centre', 'Ghurair'],
];
const LETTERHEAD: [string, string][] = [['Office 302, Al Mulla Building, Deira', 'Mulla'], ['Office 14, Hatta', 'Hatta'], ['Warehouse 7, Masdar', 'Masdar'], ['Shop 3, Karama', 'Karama'],
  ['Unit 4, Al Karama', 'Karama']];
Deno.test('the second review\'s place probes and the letterhead addresses are gone; plot sizes stay', () => {
  const left = [...REVIEW_PROBES_2.filter(([s]) => s !== 'Al Raha Gardens, Khannour community'), ...LETTERHEAD].map(([s, n]) => [s, scrubIdentityText(s, '[X]'), n]).filter(([, o, n]) => o.toLowerCase().includes(n.toLowerCase()));
  assertEquals(left, []);
  for (const keep of ['PLOT 3451 M2', 'Plot 6457 sq', 'Plot 6457 sq m', 'Villa 15 m frontage']) assertEquals(scrubIdentityText(keep, '[X]'), keep);
  assertEquals(scrubIdentityText('Renovation at Al Barsha 2', '[X]'), 'Renovation in Dubai');
});
