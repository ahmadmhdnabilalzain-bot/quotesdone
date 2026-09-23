// deno test --allow-read supabase/functions/marketing_social_inbox/reply.test.ts
// What the marketing seat answers. The library is read from the SQL seed itself
// (scripts/sql/every_social_message_is_answered.sql), so these cases pin the rows that ship.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { decide, passagesFor, type LibraryRow } from './reply.ts';
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
  assertEquals(decide('I want to speak with an agent', LIB, [], [], false, null).kind === 'handoff', false);
  assertEquals(decide('أريد التحدث مع موظف', LIB, [], [], false, 'none').kind === 'handoff', false);
});
Deno.test('handoff: the acknowledgement is the library row, in the asker\'s language', () => {
  const en = decide('I want to speak with an agent', LIB, [], [], true, null);
  assertEquals([en.kind, en.text], ['handoff', LIB.find((r) => r.key === 'human_handoff')!.reply_en]);
  const ar = decide('أريد التحدث مع موظف', LIB, [], [], true, 'lib:pricing');
  assertEquals([ar.kind, ar.lang, ar.text], ['handoff', 'ar', LIB.find((r) => r.key === 'human_handoff')!.reply_ar]);
});

// ── STANDARD REPLIES ─────────────────────────────────────────────────────────────────────────────
// WHICH standard reply fits is REASONED (reasoned_channels.ts socialMeaning, 23 Sep 2026); a row's match_words
// are no longer read. The EN/AR phrasings once pinned here against match_words are what the reasoning is asked.
Deno.test('standard replies: the reasoned row is sent, in the asker\'s language, and its words are never matched', () => {
  const d = decide('كم الرسوم', LIB, [], [], false, 'lib:pricing');
  assertEquals([d.kind, d.key, d.text], ['standard', 'pricing', LIB.find((r) => r.key === 'pricing')!.reply_ar]);
  // A message full of a row's own match_words gets nothing from them: unreasoned (held) is the honest unknown.
  assertEquals(decide('hi, what are your fees? commission? pricing?', LIB, [], [], false, null).kind, 'unknown');
});
Deno.test('standard replies: only an active row with a priority can be chosen — a utility row or a deactivated one cannot', () => {
  const off = LIB.map((r) => (r.key === 'greeting' ? { ...r, active: false } : r));
  assertEquals(decide('hello', off, [], [], false, 'lib:greeting').kind, 'unknown');
  assertEquals(decide('hello', LIB, [], [], false, 'lib:unknown').kind, 'unknown'); // priority null: chosen by code only
  assertEquals(decide('hello', LIB, [], [], false, 'lib:no_such_row').kind, 'unknown');
});

// ── CARRYING ON FROM COMPANY KNOWLEDGE ───────────────────────────────────────────────────────────
const FAQS: FaqRow[] = [
  { id: 13, question: 'How many suppliers receive my RFQ?', answer: 'Your request goes to up to 5 matched suppliers.', language: 'en' },
];
Deno.test('carry on: a reasoned count question takes the approved FAQ the website widget uses', () => {
  const d = decide('How many quotes will I get for my request?', LIB, FAQS, [], false, 'faq:count');
  assertEquals([d.kind, d.key], ['faq', 'faq:13']);
  assert(d.text.startsWith('Your request goes to up to 5 matched suppliers.'));
  assert(d.text.includes('reply "agent"'));
});
Deno.test('carry on: the reasoned passage is quoted; passages are offered only in the asker\'s language', () => {
  const corpus = [{ content: 'Warranty terms are set by each supplier in their quotation; compare them side by side before you reveal.', citation: 'support:12' }];
  const en = passagesFor('who decides the warranty terms?', corpus);
  const d = decide('who decides the warranty terms?', LIB, [], en, false, 'kb:0');
  assertEquals([d.kind, d.key], ['knowledge', 'kb:support:12']);
  // An Arabic question is never offered an English passage.
  assertEquals(passagesFor('من يحدد شروط الضمان؟', corpus), []);
  assertEquals(decide('من يحدد شروط الضمان؟', LIB, [], [], false, 'kb:0').kind, 'unknown');
});

// ── GROUNDING REFUSAL ────────────────────────────────────────────────────────────────────────────
Deno.test('grounding: reasoned "none" (or held) means the honest unknown — no invented price, no nearest neighbour', () => {
  const unrelated = [{ content: 'Every document is backed up to Dropbox nightly and verified by the IT engineer.', citation: 'ops:7' }];
  for (const meaning of ['none', null]) {
    const d = decide('what does a gypsum false ceiling cost per sqm in Dubai?', LIB, FAQS, unrelated, false, meaning);
    assertEquals([d.kind, d.text], ['unknown', LIB.find((r) => r.key === 'unknown')!.reply_en]);
    assertEquals(/AED|\d+\s*(dirham|درهم)/i.test(d.text), false);
  }
  const ar = decide('كم سعر متر الجبس في دبي؟', LIB, FAQS, unrelated, false, 'none');
  assertEquals([ar.kind, ar.text], ['unknown', LIB.find((r) => r.key === 'unknown')!.reply_ar]);
});
