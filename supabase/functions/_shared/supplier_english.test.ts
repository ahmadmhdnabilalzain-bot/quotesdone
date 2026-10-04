import { assert, assertEquals } from 'jsr:@std/assert@1';
import { ENGLISH_ONLY, hasArabic } from './supplier_english.ts';

Deno.test('Arabic script anywhere is caught; English, numbers and symbols are not', () => {
  assert(hasArabic('نعم، السقف 3 أمتار'));
  assert(hasArabic('Ceiling height 3 m, اللون أبيض'));
  assert(hasArabic('ﻻ')); // presentation forms
  assertEquals(hasArabic('Ceiling height 3.2 m; white RAL 9010, 60x60 tiles - 120 m²'), false);
  assertEquals(hasArabic(null), false);
  assertEquals(hasArabic(String.fromCharCode(0xfeff) + 'Yes, 3 m'), false); // a pasted byte-order mark is not Arabic
});

Deno.test('the refusal speaks both languages and names its code', () => {
  assertEquals(ENGLISH_ONLY.code, 'english_only');
  assert(ENGLISH_ONLY.message.length > 20 && hasArabic(ENGLISH_ONLY.message_ar));
});
