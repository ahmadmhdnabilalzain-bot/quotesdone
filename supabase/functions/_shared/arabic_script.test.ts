// An Arabic line with a supplier label or a code in it is Arabic; an English line is not (arabic_script.ts).
// The lines are the ones the held Arabic comparison report of 1 Nov 2026 waited on forever (waiter 32bf6955…).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { needsArabic } from './arabic_script.ts';
import { compareDocument } from './quote_documents.ts';

const ALREADY_ARABIC = ['المورّد C (مستبعد)', 'الترقية في المورّد A – الخيار 2', 'الزجاج بلا طبقة Low-E، وعزله للحرارة أضعف في صيف دبي',
  'الوصف يقول "منزلقة" مع نظام AWS 70، وهو عادةً نظام نوافذ مفصلية'];
const STILL_ENGLISH = ['Aluminium sliding windows, Schuco AWS 70', 'Supplier C (excluded)', 'Supply نوافذ aluminium windows and installation', 'MDF'];

Deno.test('Arabic with a label or a code kept as written needs no translation; English, or mostly English, still does', () => {
  for (const s of ALREADY_ARABIC) assertEquals(needsArabic(s), false, s);
  for (const s of STILL_ENGLISH) assertEquals(needsArabic(s), true, s);
  assertEquals([needsArabic('12.5'), needsArabic(''), needsArabic('مطابق')], [false, false, false]);
});

Deno.test('KNOWN-BAD CONTROL: the rule before 2 Nov ("any Latin letter") held every one of these Arabic lines', () => {
  const old = (s: string) => /[A-Za-z]/.test(s);
  assertEquals(ALREADY_ARABIC.filter(old).length, ALREADY_ARABIC.length);
});

Deno.test('the Arabic comparison report built on an Arabic analysis is not held for its own Arabic sentences', () => {
  const analysis = { lang: 'ar', summary: 'الزجاج بلا طبقة Low-E، وعزله للحرارة أضعف في صيف دبي', top3: [{ label: 'Supplier A – Option 2', why: 'الترقية في المورّد A – الخيار 2' }],
    quotes: [{ label: 'Supplier C', price: 131000, flags: ['المورّد C (مستبعد)'] }], all_quotes: [{ label: 'Supplier C', price: 131000, status: 'received' }] };
  const d = compareDocument({ analysis, inquiry: { id: 'zz-demo', rfq_no: 1, category: 'aluminium', summary: 'نوافذ ألمنيوم', emirate: 'Dubai' } as never, lang: 'ar' });
  const own = d.untranslated.filter((t) => ALREADY_ARABIC.includes(t));
  assertEquals(own, [], 'held for Arabic it already has: ' + own.join(' | '));
  assert(!d.untranslated.some((t) => /[؀-ۿ]/.test(t) && !needsArabic(t)));
});
