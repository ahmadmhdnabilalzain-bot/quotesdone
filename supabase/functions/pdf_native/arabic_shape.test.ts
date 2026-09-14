// deno test --no-lock supabase/functions/pdf_native/arabic_shape.test.ts
// The joined forms a reader expects, letter by letter. If this breaks, Arabic on every QuotesDone
// PDF comes out as disconnected letters — or, as before 14 Sep 2026, not at all.
import { assertEquals } from 'jsr:@std/assert@1';
import { shapeArabic } from './arabic_shape.ts';

const hex = (s: string) => [...s].map((c) => c.codePointAt(0)!.toString(16).toUpperCase());

Deno.test('initial, medial, final and isolated forms', () => {
  // عرض: ain initial, reh final (reh never joins onward), dad isolated after a reh.
  assertEquals(hex(shapeArabic('عرض')), ['FECB', 'FEAE', 'FEBD']);
  // سعر: seen initial, ain medial, reh final.
  assertEquals(hex(shapeArabic('سعر')), ['FEB3', 'FECC', 'FEAE']);
  // A lone letter is isolated.
  assertEquals(hex(shapeArabic('ب')), ['FE8F']);
});

Deno.test('lam-alef is one ligature, final when joined from the right', () => {
  assertEquals(hex(shapeArabic('لا')), ['FEFB']);
  // الإ (as in الإنجاز): the lam follows a right-joining alef, which never joins onward, so the
  // lam-alef ligature is the ISOLATED one.
  assertEquals(hex(shapeArabic('الإ')), ['FE8D', 'FEF9']);
  // بلا: beh initial, then lam-alef joined from the beh: final ligature.
  assertEquals(hex(shapeArabic('بلا')), ['FE91', 'FEFC']);
});

Deno.test('harakat are dropped, Latin and digits pass through', () => {
  assertEquals(shapeArabic('مقدّمة'), shapeArabic('مقدمة'));
  assertEquals(shapeArabic('AED 78,900'), 'AED 78,900');
  assertEquals(hex(shapeArabic('يومًا')), hex(shapeArabic('يوما')));
});
