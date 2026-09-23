// reply.ts — what the marketing seat says back on Instagram / Facebook, decided without a model.
//
// Seat: marketing. 22 Sep 2026, founder: "We will have some standard replies, automatic, and then
// the agent needs to be able to carry on with the conversation. Only if a customer is asking 'I want
// to speak with an agent', that's where I get a notification on my email, and I'll carry on. He
// should be wired to the company knowledge."
//
// Order, first hit wins:
//   1. the person asks for a human        -> handoff (REASONED by the caller through think(); see below)
//   2. a standard reply from the library   -> public.social_reply_library, which the founder edits;
//                                             a row matches when one of its match_words appears as
//                                             whole words in the message (lowest priority number first)
//   3. the site assistant's question route -> routeQuestion + pickFaq (chat_answers.ts), the same
//                                             count / cost / timeline FAQs the website widget answers
//   4. company knowledge                   -> fn_support_corpus_search(p_public => true), the corpus the
//                                             widget reads; a passage is used only when it shares a
//                                             substantive word with the question and is written in
//                                             the asker's language ("a nearest neighbour is always found")
//   5. nothing grounded                    -> 'unknown': say so, record the gap, offer a person.
// A price, a promise or a date is never composed here: every sentence the seat sends is a library
// row, an approved FAQ answer, or a corpus passage, verbatim.
import { langOf, onTopic, pickFaq, routeQuestion, isArabic, type FaqRow, type Lang } from '../_shared/chat_answers.ts';
import { capabilityStatement, isSizeQuestion } from '../_shared/size_question.ts';
import { clip } from './meta.ts';

export interface LibraryRow { key: string; priority: number | null; match_words: string[] | null; reply_en: string; reply_ar: string; active: boolean }
export interface CorpusRow { content: string; citation?: string | null; rank?: number | null }
export type ReplyKind = 'handoff' | 'standard' | 'faq' | 'knowledge' | 'unknown' | 'held';
export interface Decision { kind: ReplyKind; key: string | null; lang: Lang; text: string }

// Arabic: diacritics and tatweel out, the alef / taa marbuta / alef maqsura variants unified, and the
// common attached prefixes stripped per word — so "والرسوم" and "رسوم" are one word on both sides.
export function norm(s: string): string {
  return String(s || '').toLowerCase()
    .replace(/[ً-ْـ]/g, '').replace(/[إأآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي')
    .replace(/[’']/g, '')
    .split(/[^a-z0-9ء-ي]+/).filter(Boolean)
    .map((w) => (/[ء-ي]/.test(w) && w.length > 4 ? w.replace(/^(وال|بال|فال|لل|ال)/, '') : w))
    .join(' ');
}

// ── 1. ASKING FOR A PERSON ───────────────────────────────────────────────────────────────────────
// REASONED, NOT MATCHED (23 Sep 2026, founder_instruction 886-903: "NO word matching anywhere"). This
// was HUMAN_EN / HUMAN_AR, ten regexes pinned by a test, because it is the one decision that pages the
// founder. A list pins the phrasings someone thought of; "is anyone actually there?" and "third time I
// ask, stop the bot" were not on it. The caller passes wantsPerson from think() (_shared/reasoned_decisions.ts
// needsAPerson); under the hold decide() is not reached at all and the message waits in the marketing
// seat's queue. The phrasings the list held are now eval cases (scripts/eval/reasoning_eval.mjs), where
// they measure the reasoning instead of replacing it.

// ── 2. THE LIBRARY ───────────────────────────────────────────────────────────────────────────────
export function matchLibrary(message: string, library: LibraryRow[]): LibraryRow | null {
  const hay = ' ' + norm(message) + ' ';
  const rows = library
    .filter((r) => r.active && r.priority != null && Array.isArray(r.match_words) && r.match_words.length)
    .sort((a, b) => (a.priority as number) - (b.priority as number));
  for (const r of rows) {
    for (const w of r.match_words as string[]) {
      const k = norm(w);
      if (k && hay.includes(' ' + k + ' ')) return r;
    }
  }
  return null;
}

const pick = (row: LibraryRow | undefined, lang: Lang) => (row ? (lang === 'ar' ? row.reply_ar : row.reply_en) : '');
const byKey = (library: LibraryRow[], key: string) => library.find((r) => r.key === key && r.active);

// ── THE DECISION ─────────────────────────────────────────────────────────────────────────────────
export function decide(message: string, library: LibraryRow[], faqs: FaqRow[], corpus: CorpusRow[], wantsPerson: boolean): Decision {
  const lang = langOf(message);
  if (wantsPerson) return { kind: 'handoff', key: 'human_handoff', lang, text: pick(byKey(library, 'human_handoff'), lang) };
  // How big are we: what we do, never a number (instruction 777) — before any library row or FAQ.
  if (isSizeQuestion(message)) return { kind: 'standard', key: 'capability_answer', lang, text: capabilityStatement(lang) };

  const lib = matchLibrary(message, library);
  if (lib) return { kind: 'standard', key: lib.key, lang, text: pick(lib, lang) };

  const faq = pickFaq(routeQuestion(message), lang, faqs);
  if (faq) return { kind: 'faq', key: 'faq:' + faq.id, lang, text: clip(String(faq.answer || '').trim(), 700) + suffix(library, lang) };

  const hit = corpus.find((c) => c.content && (lang === 'ar') === isArabic(c.content) && onTopic(message, c.content));
  if (hit) return { kind: 'knowledge', key: hit.citation ? 'kb:' + hit.citation : 'kb', lang, text: clip(String(hit.content).trim(), 700) + suffix(library, lang) };

  return unknown(library, lang);
}

export const unknown = (library: LibraryRow[], lang: Lang): Decision => ({ kind: 'unknown', key: 'unknown', lang, text: pick(byKey(library, 'unknown'), lang) });
const suffix = (library: LibraryRow[], lang: Lang) => { const s = pick(byKey(library, 'knowledge_suffix'), lang); return s ? '\n\n' + s : ''; };
