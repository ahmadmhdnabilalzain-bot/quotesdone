// A MIXED MESSAGE KEEPS THE CONVERSATION'S LANGUAGE (customer_support, 3 Nov 2026; scripts/eval/conversation_quality.mjs).
// Measured on the live widget (site_assistant, 5 conversations of villa_windows_sharjah): an English inquiry whose 4th
// message mixed in an Arabic phrase ("sorry, الزجاج 8 مم مو 6mm. And the villa is in Sharjah ...") was answered wholly in
// Arabic, sign-up link /ar/me included, because langOf read ANY Arabic letter as an Arabic message. The canon
// (knowledge/brief/company.md §10): a customer is answered in the language of the inquiry; a visitor in the language they
// write in. A message in one script decides; a message that mixes both keeps the language the conversation began in.
import { assertEquals } from 'jsr:@std/assert@1';
import { langOf, turnLang } from './chat_answers.ts';

const mixed = 'ZZ DEMO sorry, الزجاج 8 مم مو 6mm. And the villa is in Sharjah, Al Rahmaniya, not Dubai like I told you before?';
const enStart = [{ role: 'user', content: 'ZZ DEMO Hi, I need aluminium windows for my villa in Sharjah: 12 windows.' }, { role: 'assistant', content: 'Thanks.' }];
const arStart = [{ role: 'user', content: 'مرحبا، أحتاج نوافذ ألمنيوم لفيلا في الشارقة' }, { role: 'assistant', content: 'أهلاً' }];

Deno.test('a mixed message in an English conversation is answered in English', () => {
  assertEquals(turnLang(mixed, 'en', enStart), 'en');
});
Deno.test('a mixed message in an Arabic conversation is answered in Arabic', () => {
  assertEquals(turnLang('ZZ DEMO خلها 16 نافذة، and the glass 10mm please.', 'en', arStart), 'ar');
});
Deno.test('a message wholly in the other script switches the language', () => {
  assertEquals(turnLang('كم الرسوم؟', 'en', enStart), 'ar');
  assertEquals(turnLang('How much is the fee?', 'en', arStart), 'en');
});
Deno.test('the first message, and the Arabic screen, keep their old rules', () => {
  assertEquals(turnLang('أبغى عرض سعر split AC units 2 ton inverter', 'en', []), 'ar', 'a first message with any Arabic is Arabic, as before');
  assertEquals(turnLang('hello', 'ar', enStart), 'ar', 'the Arabic portal names its buttons in Arabic, as before');
  assertEquals(langOf('مرحبا'), 'ar');
  assertEquals(langOf('ZZ DEMO كم تبلغ رسوم الاشتراك؟'), 'ar', 'the fixture tag is not English');
});

// THE LANGUAGE IS CHECKED, NOT ONLY ASKED FOR (CI run 41621633737, conversation-quality, this branch's widget): with turnLang
// choosing English, 1 of 5 replies to the mixed message was still wholly Arabic. Every reply path now sends such a draft back.
import { replyLanguageProblems } from './chat_answers.ts';
import { assert } from 'jsr:@std/assert@1';
const arabicReply = 'لا أستطيع تسجيل أي تفاصيل أو تعديلها في هذه المحادثة، لذلك لن يتغير شيء في طلبك من هنا.';
Deno.test('a reply in the other script is refused; quoted words and a link are not', () => {
  assertEquals(replyLanguageProblems(arabicReply, 'en').length, 1);
  assertEquals(replyLanguageProblems('Please put the glass (الزجاج) thickness in your request at /me.', 'en'), []);
  assertEquals(replyLanguageProblems('Sign up free and post your job here, we match it to verified suppliers.', 'ar').length, 1);
  assertEquals(replyLanguageProblems(arabicReply, 'ar'), []);
  assertEquals(replyLanguageProblems('/ar/me', 'ar'), [], 'a link line alone');
});
Deno.test('the widget, the portal, aiReply (WhatsApp) and the WhatsApp language all use it', () => {
  const read = (p: string) => Deno.readTextFileSync(new URL(p, import.meta.url));
  // the widget's check is siteReplyCheck (site_assistant/reply_check.ts, from main), which carries the language check
  assert(/check: siteReplyCheck\(brief, sys, replyLang\)/.test(read('../site_assistant/index.ts')), 'site_assistant uses siteReplyCheck');
  assert(/\.\.\.replyLanguageProblems\(s, lang\)/.test(read('../site_assistant/reply_check.ts')), 'siteReplyCheck checks the language');
  assert(/\.\.\.replyLanguageProblems\(t, lang\)/.test(read('../sales_engineer/index.ts')), 'sales_engineer check');
  assert(/replyLanguageProblems\(t, replyLang\)/.test(read('./ai_reply.ts')), 'aiReply check');
  assert(/langGiven \?\? turnLang\(Body/.test(read('../wa_inbound/index.ts')), 'wa_inbound language');
});
