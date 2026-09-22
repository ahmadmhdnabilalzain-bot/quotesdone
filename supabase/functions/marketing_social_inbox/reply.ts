// reply.ts — what the marketing seat says back on Instagram / Facebook, decided without a model.
//
// Seat: marketing. 22 Sep 2026, founder: "We will have some standard replies, automatic, and then
// the agent needs to be able to carry on with the conversation. Only if a customer is asking 'I want
// to speak with an agent', that's where I get a notification on my email, and I'll carry on. He
// should be wired to the company knowledge."
//
// Order, first hit wins:
//   1. the person asks for a human        -> handoff (a fixed list of phrasings, EN + AR, below)
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
export type ReplyKind = 'handoff' | 'standard' | 'faq' | 'knowledge' | 'unknown';
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
// Deterministic on purpose: this is the one decision that pages the founder, so it is a list that
// a test pins (reply.test.ts), not a judgement. Matched against norm(), so the Arabic is written in
// its normalised spelling (ا for أ/إ, ه for ة, ي for ى).
const HUMAN_EN: RegExp[] = [
  /\b(speak|talk|chat)( to| with)( a| an| the| your| some| one of your)?( real| live| actual)? (person|human|agent|someone|somebody|representative|rep|staff|team|manager|operator|employee)\b/,
  /\b(real|live|actual) (person|human|agent|representative)\b/,
  /\bhuman (agent|being|please|support)\b/,
  // "connect me with a supplier" is a customer asking for the product, not for us: the object must be one of ours.
  /\b(connect|transfer|put) me (to|with|through to) (a |an |the |your )?(person|human|agent|someone|somebody|representative|team|staff|manager|operator)\b/,
  /\bi (want|need|would like|d like) (a|an|to speak to an?|to talk to an?) ?(agent|human|person|representative)\b/,
  /^(agent|human|representative|operator|real person)( please)?$/,
];
const HUMAN_AR: RegExp[] = [
  /(اريد|ابي|ابغي|ابغا|ودي|احتاج|ممكن|اقدر|بدي)( ا| ان)? ?(تحدث|اتحدث|اكلم|اتكلم|اتواصل|احكي) ?(مع|الي|ل)? ?(موظف|شخص|احد|مندوب|انسان|بشر|مسؤول|المسؤول|خدمه|فريق)/,
  /(موظف|شخص|انسان) (حقيقي|بشري)/,
  /(كلمني|كلموني|خلني اكلم|حولني|حولوني) ?(ل|الي|مع)? ?(موظف|احد|شخص|مندوب)?/,
  /^(موظف|انسان|بشري|مندوب|خدمه عملاء)( لو سمحت| من فضلك)?$/,
];
export function wantsHuman(message: string): boolean {
  const n = norm(message);
  return HUMAN_EN.some((re) => re.test(n)) || HUMAN_AR.some((re) => re.test(n));
}

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
export function decide(message: string, library: LibraryRow[], faqs: FaqRow[], corpus: CorpusRow[]): Decision {
  const lang = langOf(message);
  if (wantsHuman(message)) return { kind: 'handoff', key: 'human_handoff', lang, text: pick(byKey(library, 'human_handoff'), lang) };
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
