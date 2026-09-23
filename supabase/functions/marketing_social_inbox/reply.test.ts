// deno test --allow-read supabase/functions/marketing_social_inbox/reply.test.ts
// What the marketing seat answers. The library is read from the SQL seed itself
// (scripts/sql/every_social_message_is_answered.sql), so these cases pin the rows that ship.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { decide, matchLibrary, type LibraryRow } from './reply.ts';
import type { FaqRow } from '../_shared/chat_answers.ts';

const SQL = Deno.readTextFileSync(new URL('../../../scripts/sql/every_social_message_is_answered.sql', import.meta.url));
function seededLibrary(): LibraryRow[] {
  const out: LibraryRow[] = [];
  const re = /^\('(\w+)', (\d+|null),\s*(?:array\[([\s\S]*?)\]|'\{\}'),\s*'((?:[^']|'')*)',\s*'((?:[^']|'')*)',/gm;
  for (const m of SQL.matchAll(re)) {
    const words = m[3] ? [...m[3].matchAll(/'((?:[^']|'')*)'/g)].map((w) => w[1].replace(/''/g, "'")) : [];
    out.push({ key: m[1], priority: m[2] === 'null' ? null : Number(m[2]), match_words: words, reply_en: m[4].replace(/''/g, "'"), reply_ar: m[5].replace(/''/g, "'"), active: true });
  }
  return out;
}
const LIB = seededLibrary();

Deno.test('the seed parses: nine rows, the three code-chosen rows have no match words, every row has EN and AR', () => {
  assertEquals(LIB.map((r) => r.key).sort(), ['contact', 'greeting', 'hours', 'how_it_works', 'human_handoff', 'knowledge_suffix', 'pricing', 'supplier_signup', 'unknown']);
  for (const r of LIB) {
    assert(r.reply_en.length > 20 && /[؀-ۿ]/.test(r.reply_ar), r.key);
    if (['human_handoff', 'unknown', 'knowledge_suffix'].includes(r.key)) assertEquals([r.priority, r.match_words], [null, []], r.key);
  }
});

// ── HUMAN HANDOFF, EN + AR ───────────────────────────────────────────────────────────────────────
// Whether a person is wanted is REASONED by the caller (think(); founder_instruction 886-903). The EN+AR
// phrasings this file used to pin against a regex list are cases in scripts/eval/reasoning_eval.mjs's
// bank (marketing / needs_a_person), where they score the reasoning. Here: the reply given once it is.
Deno.test('handoff: the decision is the reasoning\'s — the words "speak to an agent" alone hand nobody over', () => {
  assertEquals(decide('I want to speak with an agent', LIB, [], [], false).kind === 'handoff', false);
  assertEquals(decide('أريد التحدث مع موظف', LIB, [], [], false).kind === 'handoff', false);
});
Deno.test('handoff: the acknowledgement is the library row, in the asker\'s language', () => {
  const en = decide('I want to speak with an agent', LIB, [], [], true);
  assertEquals([en.kind, en.text], ['handoff', LIB.find((r) => r.key === 'human_handoff')!.reply_en]);
  const ar = decide('أريد التحدث مع موظف', LIB, [], [], true);
  assertEquals([ar.kind, ar.lang, ar.text], ['handoff', 'ar', LIB.find((r) => r.key === 'human_handoff')!.reply_ar]);
});

// ── STANDARD REPLIES, EN + AR ────────────────────────────────────────────────────────────────────
const STANDARD: Array<[string, string]> = [
  ['Hi', 'greeting'], ['Hello!', 'greeting'], ['Good morning', 'greeting'],
  ['hi, what are your fees?', 'pricing'], ['Is it free for customers?', 'pricing'], ['do you take a commission', 'pricing'],
  ['How does it work?', 'how_it_works'], ['what is QuotesDone', 'how_it_works'],
  ['We are a supplier, how do we register? I want to list my company', 'supplier_signup'], ['how do I become a supplier', 'supplier_signup'],
  ["What's your phone number?", 'contact'], ['how can I contact you', 'contact'],
  ['What are your working hours?', 'hours'], ['are you open on friday', 'hours'],
  ['مرحبا', 'greeting'], ['السلام عليكم', 'greeting'], ['مرحبًا، كم الرسوم؟', 'pricing'], ['هل الخدمة مجانية؟', 'pricing'],
  ['كم العمولة', 'pricing'], ['كيف تعمل المنصة؟', 'how_it_works'], ['وش تسوون بالضبط', 'how_it_works'],
  ['أبي التسجيل كمورد', 'supplier_signup'], ['كيف اتواصل معكم', 'contact'], ['وش رقمكم', 'contact'],
  ['ما هي ساعات العمل؟', 'hours'], ['متى الدوام', 'hours'],
];
Deno.test('standard replies: each question gets its library row, EN and AR', () => {
  for (const [m, key] of STANDARD) assertEquals(matchLibrary(m, LIB)?.key, key, m);
});
Deno.test('standard replies: "hi" inside a word is not a greeting, and the reply is in the asker\'s language', () => {
  assertEquals(matchLibrary('this is about my ceiling', LIB), null);
  const d = decide('كم الرسوم', LIB, [], [], false);
  assertEquals([d.kind, d.key, d.text], ['standard', 'pricing', LIB.find((r) => r.key === 'pricing')!.reply_ar]);
});
Deno.test('standard replies: an edited or deactivated row is what the seat uses', () => {
  const edited = LIB.map((r) => (r.key === 'hours' ? { ...r, match_words: ['saturday'] } : r.key === 'greeting' ? { ...r, active: false } : r));
  assertEquals(matchLibrary('open on saturday?', edited)?.key, 'hours');
  assertEquals(matchLibrary('hello', edited), null);
});

// ── CARRYING ON FROM COMPANY KNOWLEDGE ───────────────────────────────────────────────────────────
const FAQS: FaqRow[] = [
  { id: 13, question: 'How many suppliers receive my RFQ?', answer: 'Your request goes to up to 5 matched suppliers.', language: 'en' },
];
Deno.test('carry on: a count question takes the approved FAQ the website widget uses', () => {
  const d = decide('How many quotes will I get for my request?', LIB, FAQS, [], false);
  assertEquals([d.kind, d.key], ['faq', 'faq:13']);
  assert(d.text.startsWith('Your request goes to up to 5 matched suppliers.'));
  assert(d.text.includes('reply "agent"'));
});
Deno.test('carry on: an on-topic knowledge passage is quoted, in the asker\'s language', () => {
  const corpus = [{ content: 'Warranty terms are set by each supplier in their quotation; compare them side by side before you reveal.', citation: 'support:12' }];
  const d = decide('who decides the warranty terms?', LIB, [], corpus, false);
  assertEquals([d.kind, d.key], ['knowledge', 'kb:support:12']);
  // An Arabic question is not answered with an English passage.
  assertEquals(decide('من يحدد شروط الضمان؟', LIB, [], corpus, false).kind, 'unknown');
});

// ── GROUNDING REFUSAL ────────────────────────────────────────────────────────────────────────────
Deno.test('grounding: nothing on-topic means the honest unknown — no invented price, no nearest neighbour', () => {
  const unrelated = [{ content: 'Every document is backed up to Dropbox nightly and verified by the IT engineer.', citation: 'ops:7' }];
  const d = decide('what does a gypsum false ceiling cost per sqm in Dubai?', LIB, FAQS, unrelated, false);
  assertEquals([d.kind, d.text], ['unknown', LIB.find((r) => r.key === 'unknown')!.reply_en]);
  assertEquals(/AED|\d+\s*(dirham|درهم)/i.test(d.text), false);
  const ar = decide('كم سعر متر الجبس في دبي؟', LIB, FAQS, unrelated, false);
  assertEquals([ar.kind, ar.text], ['unknown', LIB.find((r) => r.key === 'unknown')!.reply_ar]);
});
