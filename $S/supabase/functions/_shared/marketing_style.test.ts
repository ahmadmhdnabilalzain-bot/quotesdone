// The marketing seat's style gate (marketing, 22 Sep 2026). No network.
//   deno test supabase/functions/_shared/marketing_style.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { lintDraft, numbersIn, ungroundedNumbers } from './marketing_style.ts';

const rules = (t: string, k: Parameters<typeof lintDraft>[1] = 'message') => lintDraft(t, k).map((f) => f.rule);

Deno.test('the known machine openers and words are refused, in English and Arabic', () => {
  for (const t of [
    'Hi Sara, I hope this message finds you well.',
    'I hope you’re doing well and wanted to share something.',   // typographic apostrophe
    'Let us delve into procurement.',
    'A seamless way to buy.',
    'In today\'s fast-paced construction market...',
    'Trusted by thousands of contractors.',
    'أتمنى أن تكون بخير، أود أن أعرض عليك المنصة.',
    'في عالم اليوم يتغير كل شيء.',
    'سوف يتم إرسال العروض.',
    'منصة يثق بنا فيها الجميع.',
  ]) assert(lintDraft(t, 'message').length > 0, t);
});

Deno.test('stock adjective lists, emoji, exclamations and em-dash runs are refused', () => {
  assert(rules('A fast, simple and transparent way to buy.').includes('adjective_triplet'));
  assert(rules('Quotes that are reliable, secure and effortless.').includes('adjective_triplet'));
  assert(rules('Great news 🚀').includes('emoji'));
  assert(rules('Great! Really great!').includes('exclamation'));
  assert(rules('One — two — three').includes('em_dash_run'));
  // an article may use dashes the way the existing blog does
  assert(!rules('One — two — three', 'article').includes('em_dash_run'));
});

Deno.test('plain professional text passes', () => {
  for (const t of [
    'Hello Sara,\n\nI founded QuotesDone, a Dubai-licensed platform for construction and fit-out procurement.\nIt lets a procurement team send one request and compare structured quotes from verified UAE suppliers.\n\nIf it would be useful for your team, I would be glad to show you how it works.',
    'Steel, timber and glass are priced per line.',   // nouns, not stock adjectives
    'السلام عليكم سارة، أسّستُ QuotesDone، منصة مرخّصة في دبي لطلب عروض الأسعار في قطاع البناء والتشطيبات.',
  ]) assertEquals(lintDraft(t, 'message'), [], t);
});

Deno.test('an article states no number its sources do not contain', () => {
  const src = ['The buyer pays a 3% reveal fee. DET Dubai Trader License No. 1633275.'];
  assertEquals(ungroundedNumbers('<p>A 3% fee, licence 1633275.</p>', src), []);
  assertEquals(ungroundedNumbers('<p>A 3% fee saves 40% on average across 1,200 jobs.</p>', src), ['40', '1,200']);
  // Arabic-Indic digits are the same numbers
  assertEquals(numbersIn('رسوم ٣٪'), ['3']);
  assertEquals(ungroundedNumbers('رسوم كشف بنسبة ٣٪', src), []);
});
