// A question about how big we are is answered with what we do, never a number (founder_instruction 777,
// 22 Sep 2026). Fails if a size question stops being recognised, if a product question starts being
// swallowed, if the statement gains a digit, or if a public surface answers before asking the detector.
//
//   deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/size_question.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { capabilityStatement, isSizeQuestion } from './size_question.ts';
import { decide } from '../marketing_social_inbox/reply.ts';

const SIZE = [
  'how many suppliers do we have', 'How many suppliers do you have?', 'how many suppliers', 'number of customers?',
  'how many customers use quotesdone', 'how many requests have you received so far', 'how many companies are registered',
  'how many vendors are on the platform', 'how big are you', 'How big is QuotesDone?', 'what is your revenue',
  "what's quotesdone's turnover", 'how much revenue do you make', 'total number of users on your platform',
  'كم عدد الموردين لديكم', 'كم عدد الموردين؟', 'كم عدد العملاء المسجلين في المنصة', 'كم مورد عندكم', 'ما حجم شركتكم',
  'ما هي إيراداتكم', 'كم عدد الطلبات التي استقبلتم حتى الآن',
];
const PRODUCT = [
  'how many quotes will I receive', 'how many quotes will I get', 'how many suppliers receive my RFQ',
  'how much does it cost', 'how much is the reveal fee', 'what do suppliers pay', 'how long does it take',
  'I need 20 suppliers of gypsum board quoted', 'change the weekly cap for emails into 15 instead of 10', 'hi', 'figures',
  'كم عدد العروض التي سأستلمها', 'كم تكلفة الخدمة', 'كم يستغرق الحصول على عروض الأسعار', 'السلام عليكم',
];

Deno.test('777: size questions are recognised in English and Arabic', () => {
  for (const q of SIZE) assertEquals(isSizeQuestion(q), true, q);
});

Deno.test('777: product questions, commands and greetings are not size questions', () => {
  for (const q of PRODUCT) assertEquals(isSizeQuestion(q), false, q);
});

Deno.test('777: the statement carries no count, in both languages, and ends with the request link', () => {
  for (const lang of ['en', 'ar'] as const) {
    const t = capabilityStatement(lang);
    assert(!/\d/.test(t.replace(/https?:\/\/\S+/g, '')), lang + ': a digit outside the link');
    assert(!/perfect|hundreds|thousands|largest|leading|مئات|آلاف|الأكبر|الرائد/i.test(t), lang + ': an unmeasured claim');
    assert(t.endsWith(lang === 'ar' ? 'https://quotesdone.com/ar/me?new=1' : 'https://quotesdone.com/me?new=1'), lang);
  }
});

Deno.test('777: the social inbox answers a size question with the statement, before its library and FAQ', () => {
  // A library row that would otherwise match "suppliers" must not win.
  const library = [{ key: 'suppliers', active: true, priority: 1, match_words: ['suppliers', 'الموردين'], reply_en: 'We have 0 suppliers', reply_ar: 'لدينا 0 مورد' }];
  for (const [q, lang] of [['how many suppliers do you have', 'en'], ['كم عدد الموردين لديكم', 'ar']] as const) {
    // deno-lint-ignore no-explicit-any
    const d = decide(q, library as any, [], []);
    assertEquals(d.key, 'capability_answer', q);
    assertEquals(d.text, capabilityStatement(lang));
  }
});

Deno.test('777: the site assistant asks the detector before its count route, the gateway and the model', async () => {
  const src = await Deno.readTextFile(new URL('../site_assistant/index.ts', import.meta.url));
  const at = src.indexOf('if (isSizeQuestion(message))');
  assert(at > 0, 'site_assistant must check isSizeQuestion');
  assert(at < src.indexOf('routeQuestion(message)'), 'before the count/cost/timeline route');
  assert(at < src.indexOf("sec('cred_fn_ai')"), 'before the gateway credential');
});
