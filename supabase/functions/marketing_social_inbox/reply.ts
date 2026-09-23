// reply.ts — what the marketing seat says back on Instagram / Facebook, decided without a model.
//
// Seat: marketing. 22 Sep 2026, founder: "We will have some standard replies, automatic, and then
// the agent needs to be able to carry on with the conversation. Only if a customer is asking 'I want
// to speak with an agent', that's where I get a notification on my email, and I'll carry on. He
// should be wired to the company knowledge."
//
// Order, first hit wins:
//   1. the person asks for a human        -> handoff (REASONED by the caller through think(); see below)
//   2. what they ask, REASONED ONCE by the caller (_shared/reasoned_channels.ts socialMeaning, 23 Sep 2026,
//      founder_instruction 886-903) among everything grounded this seat can say:
//        size       -> the capability statement, never a number (instruction 777)
//        lib:<key>  -> a standard reply from public.social_reply_library, which the founder edits
//        faq:<type> -> the approved cost / count / timeline FAQ the website widget answers (pickFaq)
//        kb:<n>     -> the n-th retrieved company-knowledge passage in the asker's language
//      Until 23 Sep a row's match_words substring picked the library reply, COUNT/COST/TIMELINE regexes
//      picked the FAQ, and ONE shared word decided a passage answered the question. All three are gone.
//   3. nothing grounded, or not yet reasoned (the hold) -> 'unknown': say so, record the gap, offer a person;
//      the caller files the meaning in the marketing seat's queue and the replay sends the grounded reply.
// A price, a promise or a date is never composed here: every sentence the seat sends is a library
// row, an approved FAQ answer, or a corpus passage, verbatim.
import { isArabic, langOf, pickFaq, type FaqRow, type Lang, type QuestionType } from '../_shared/chat_answers.ts';
import { capabilityStatement } from '../_shared/size_question.ts';
import { clip } from './meta.ts';

export interface LibraryRow { key: string; priority: number | null; match_words: string[] | null; reply_en: string; reply_ar: string; active: boolean }
export interface CorpusRow { content: string; citation?: string | null; rank?: number | null }
export type ReplyKind = 'handoff' | 'standard' | 'faq' | 'knowledge' | 'unknown' | 'held';
export interface Decision { kind: ReplyKind; key: string | null; lang: Lang; text: string }

// ── 1. ASKING FOR A PERSON ───────────────────────────────────────────────────────────────────────
// REASONED, NOT MATCHED (23 Sep 2026, founder_instruction 886-903: "NO word matching anywhere"). This
// was HUMAN_EN / HUMAN_AR, ten regexes pinned by a test, because it is the one decision that pages the
// founder. A list pins the phrasings someone thought of; "is anyone actually there?" and "third time I
// ask, stop the bot" were not on it. The caller passes wantsPerson from think() (_shared/reasoned_decisions.ts
// needsAPerson); under the hold decide() is not reached at all and the message waits in the marketing
// seat's queue. The phrasings the list held are now eval cases (scripts/eval/reasoning_eval.mjs), where
// they measure the reasoning instead of replacing it.

const pick = (row: LibraryRow | undefined, lang: Lang) => (row ? (lang === 'ar' ? row.reply_ar : row.reply_en) : '');
const byKey = (library: LibraryRow[], key: string) => library.find((r) => r.key === key && r.active);

/** The retrieved passages a social reply may quote: those written in the asker's language (a script test on
 *  our own corpus, not a reading of meaning), in retrieval order — the order the reasoning's kb:<n> refers to. */
export function passagesFor(message: string, corpus: CorpusRow[]): CorpusRow[] {
  const ar = langOf(message) === 'ar';
  return corpus.filter((c) => c.content && ar === isArabic(c.content));
}

// ── THE DECISION ─────────────────────────────────────────────────────────────────────────────────
// `meaning` is the reasoned choice (socialMeaning), or null while it cannot be reasoned: then nothing is guessed.
export function decide(message: string, library: LibraryRow[], faqs: FaqRow[], passages: CorpusRow[], wantsPerson: boolean, meaning: string | null): Decision {
  const lang = langOf(message);
  if (wantsPerson) return { kind: 'handoff', key: 'human_handoff', lang, text: pick(byKey(library, 'human_handoff'), lang) };
  const m = meaning ?? '';
  // How big are we: what we do, never a number (instruction 777).
  if (m === 'size') return { kind: 'standard', key: 'capability_answer', lang, text: capabilityStatement(lang) };
  const lib = m.startsWith('lib:') ? library.find((r) => r.active && r.priority != null && 'lib:' + r.key === m) : undefined;
  if (lib) return { kind: 'standard', key: lib.key, lang, text: pick(lib, lang) };
  const faq = m.startsWith('faq:') ? pickFaq(m.slice(4) as QuestionType, lang, faqs) : null;
  if (faq) return { kind: 'faq', key: 'faq:' + faq.id, lang, text: clip(String(faq.answer || '').trim(), 700) + suffix(library, lang) };
  const hit = m.startsWith('kb:') ? passages[Number(m.slice(3))] : undefined;
  if (hit?.content) return { kind: 'knowledge', key: hit.citation ? 'kb:' + hit.citation : 'kb', lang, text: clip(String(hit.content).trim(), 700) + suffix(library, lang) };
  return unknown(library, lang);
}

export const unknown = (library: LibraryRow[], lang: Lang): Decision => ({ kind: 'unknown', key: 'unknown', lang, text: pick(byKey(library, 'unknown'), lang) });
const suffix = (library: LibraryRow[], lang: Lang) => { const s = pick(byKey(library, 'knowledge_suffix'), lang); return s ? '\n\n' + s : ''; };
