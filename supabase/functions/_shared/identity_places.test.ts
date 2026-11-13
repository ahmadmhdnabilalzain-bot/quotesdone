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
  ['warehouse in Mussafah M-37', 'warehouse in Abu Dhabi M-37'],
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
