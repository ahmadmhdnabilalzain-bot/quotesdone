// A question about how big we are is answered with what we do, never a number (founder_instruction 777,
// 22 Sep 2026). WHETHER a message is one is REASONED since 23 Sep 2026 (the 'size' option of
// reasoned_channels.ts, founder_instruction 886-903); the phrasings once pinned here against regexes are what
// the reasoning is asked. Fails if the statement gains a digit, if a surface that was told 'size' answers with
// anything else, or if a public surface answers before it asks.
//
//   deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/size_question.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { capabilityStatement } from './size_question.ts';
import { decide } from '../marketing_social_inbox/reply.ts';
import { SIZE, SITE_OPTIONS, socialOptions, whatsappOptions } from './reasoned_channels.ts';

Deno.test('777: the statement carries no count, in both languages, and ends with the request link', () => {
  for (const lang of ['en', 'ar'] as const) {
    const t = capabilityStatement(lang);
    assert(!/\d/.test(t.replace(/https?:\/\/\S+/g, '')), lang + ': a digit outside the link');
    assert(!/perfect|hundreds|thousands|largest|leading|مئات|آلاف|الأكبر|الرائد/i.test(t), lang + ': an unmeasured claim');
    assert(t.endsWith(lang === 'ar' ? 'https://quotesdone.com/ar/me?new=1' : 'https://quotesdone.com/me?new=1'), lang);
  }
});

Deno.test('777: every public surface offers the reasoning the size option, and keeps it apart from "how many quotes will I get"', () => {
  for (const opts of [whatsappOptions([], []), SITE_OPTIONS, socialOptions([], [])]) assert(opts.some((o) => o.id === SIZE.id));
  assert(/NOT a question about how many quotes THEIR request/.test(SIZE.meaning));
});

Deno.test('777: the social inbox answers a reasoned size question with the statement, before any library row', () => {
  // A library row that says a number must not win, whatever it would once have matched.
  const library = [{ key: 'suppliers', active: true, priority: 1, match_words: ['suppliers'], reply_en: 'We have 0 suppliers', reply_ar: 'لدينا 0 مورد' }];
  for (const [q, lang] of [['how many suppliers do you have', 'en'], ['كم عدد الموردين لديكم', 'ar']] as const) {
    const d = decide(q, library, [], [], false, 'size');
    assertEquals(d.key, 'capability_answer', q);
    assertEquals(d.text, capabilityStatement(lang));
  }
  // Held (null): not guessed to be a size question.
  assertEquals(decide('how many suppliers do you have', library, [], [], false, null).kind, 'unknown');
});

Deno.test('777: the site assistant asks the reasoning before its FAQ route, the gateway and the model', async () => {
  const src = await Deno.readTextFile(new URL('../site_assistant/index.ts', import.meta.url));
  const at = src.indexOf("if (asked === 'size')");
  assert(at > 0 && src.indexOf('siteQuestion(defaultDeps(admin') < at, 'site_assistant must reason the question first');
  assert(at < src.indexOf('pickFaq(qType'), 'before the count/cost/timeline FAQ');
  assert(at < src.indexOf("sec('cred_fn_ai')"), 'before the gateway credential');
});
