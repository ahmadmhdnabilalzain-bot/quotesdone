// A MIXED MESSAGE KEEPS THE CONVERSATION'S LANGUAGE (customer_support, 3 Nov 2026; scripts/eval/conversation_quality.mjs).
// Measured on the live widget (site_assistant, 5 conversations of villa_windows_sharjah): an English inquiry whose 4th
// message mixed in an Arabic phrase ("sorry, الزجاج 8 مم مو 6mm. And the villa is in Sharjah ...") was answered wholly in
// Arabic, sign-up link /ar/me included, because langOf read ANY Arabic letter as an Arabic message. The canon
// (knowledge/brief/company.md §10): a customer is answered in the language of the inquiry; a visitor in the language they
// write in. A message in one script decides; a message that mixes both keeps the language the conversation began in.
import { assertEquals } from 'jsr:@std/assert@1';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';
import { langOf, turnLang } from './chat_answers.ts';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

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
  // the language is a WHOLE-reply rule (review of #1830): handed to answerFromBrief as checkWhole, never run per streamed sentence
  assert(/replyLanguageProblems\(t, lang\)/.test(read('../site_assistant/reply_check.ts')), 'the widget\'s whole-reply language check');
  assert(/checkWhole: siteReplyLanguage\(replyLang\)/.test(read('../site_assistant/index.ts')), 'site_assistant passes it as checkWhole');
  assert(/checkWhole: \(t: string\) => replyLanguageProblems\(t, lang\)/.test(functionSource('sales_engineer')), 'sales_engineer checkWhole');
  assert(/replyLanguageProblems\(t, replyLang\)/.test(read('./ai_reply.ts')), 'aiReply whole-reply check');
  assert(!/const sentenceCheck = [^\n]*replyLanguageProblems/.test(read('./ai_reply.ts')) && /const sentenceCheck = [^\n]*audience === 'supplier' \? english/.test(read('./ai_reply.ts')), 'aiReply\'s sentence check judges only a supplier\'s language');
  assert(/langGiven \?\? turnLang\(Body/.test(functionSource('wa_inbound')), 'wa_inbound language');
});

// A MESSAGE WITH NO LETTERS KEEPS THE CONVERSATION'S LANGUAGE (review of #1830): "14", a phone number, "OK" say nothing about it.
Deno.test('a number, a phone number or "OK" keeps the Arabic conversation Arabic; a full English sentence still switches', () => {
  assertEquals(turnLang('14', 'en', arStart), 'ar');
  assertEquals(turnLang('+971 50 123 4567', 'en', arStart), 'ar');
  assertEquals(turnLang('OK', 'en', arStart), 'ar');
  assertEquals(turnLang('ok', 'en', arStart), 'ar');
  assertEquals(turnLang('14', 'en', enStart), 'en');
  assertEquals(turnLang('نعم', 'en', enStart), 'en');
  assertEquals(turnLang('Can you send me the quotation again please?', 'en', arStart), 'en', 'a full English sentence in an Arabic chat still switches');
  assertEquals(langOf('14'), 'en', 'no conversation yet: as before');
});
