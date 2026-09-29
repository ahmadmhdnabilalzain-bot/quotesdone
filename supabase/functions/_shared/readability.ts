// readability — is a customer reply written in plain language, in the customer's language? Seat: customer_support.
// Founder instruction 1013 item 7 (29 Sep 2026): plain-language customer answers.
//
// Deterministic, no model: a reply is scored on three things a customer feels at once.
//   1. SENTENCE LENGTH. Longest sentence <= 28 words and average <= 20. A chat answer is read on a phone;
//      past ~25 words a sentence needs a second read (plain-language guidance used by UAE government
//      service writing and the plainlanguage.gov "average 15-20 words" rule). 28 leaves room for one
//      list-like sentence without letting a paragraph-sentence through.
//      THE AVERAGE IS A TEXT'S MEASURE, NOT A SENTENCE'S (review of #1071, 29 Sep 2026): it is judged only from
//      MIN_SENTENCES_FOR_AVERAGE sentences up. Over one or two sentences the average is the longest sentence
//      again, held to a tighter limit than the longest-sentence rule itself: a correct one-sentence answer of 21
//      words ("You describe the job once, we send it anonymously ...") failed at 21 > 20 while the cap is 28.
//      A WORD HAS A LETTER IN IT. A bare figure (500, 12%, 1,000, 3.5) is read at a glance and is not counted;
//      a unit or currency beside it (AED, a year) is. The supplier's non-response terms list four amounts in one
//      sentence and were 30 "words" only because 500 and 12% were counted.
//   2. JARGON. Legal filler ("pursuant", "herein"), trade and system abbreviations a buyer does not use
//      (RFQ, SLA, KYC, API), and anything shaped like an internal identifier (snake_case, fn_ names).
//   3. LANGUAGE. An Arabic conversation gets an Arabic reply: at least 60% of the letters are Arabic.
//      An English one gets at most 10% Arabic letters. Links, e-mails and numbers are not counted.
// Tone is scored alongside (it never fails a reply on its own): shouting, stacked exclamation marks and
// blaming phrases each cost points. Both scores feed the monthly customer_support self-review.
import type { GuardLang } from './support_reply_guard.ts';

export const MAX_SENTENCE_WORDS = 28;
export const MAX_AVG_SENTENCE_WORDS = 20;
export const MIN_SENTENCES_FOR_AVERAGE = 3;

const JARGON_EN = [
  'pursuant', 'herein', 'hereby', 'aforementioned', 'heretofore', 'notwithstanding', 'utilise', 'utilize',
  'leverage', 'synergy', 'facilitate', 'escalation matrix', 'ticket id', 'workflow', 'backend', 'endpoint',
  'payload', 'webhook', 'database', 'null', 'undefined', 'rfq', 'sla', 'kyc', 'api', 'rls', 'sku', 'moq', 'incoterm',
];
const JARGON_AR = ['بموجب', 'المذكور أعلاه', 'آنف الذكر', 'حيثما ينطبق', 'قاعدة البيانات'];
// Upper-case words that are ordinary in a UAE customer reply and are not shouting.
const ACRONYMS = new Set(['UAE', 'AED', 'VAT', 'FAQ', 'PDF', 'OTP', 'USD', 'GCC', 'DED', 'LLC', 'FZE', 'FZCO', 'OK']);
const BLAME = [/\byou (failed|forgot|should have|must have|did not read|didn'?t read)\b/i, /\byour fault\b/i, /\bobviously\b/i,
  /\bas (i|we) (already )?(said|explained|told you)\b/i, /كما ذكرنا سابقا/, /خطؤك/];

export interface Readability {
  ok: boolean;
  score: number;          // 0-100, plain-language score
  tone: number;           // 0-100, tone score (informational; never fails a reply alone)
  issues: string[];       // why it failed; empty when ok
  sentences: number;
  maxSentenceWords: number;
  avgSentenceWords: number;
  jargon: string[];
  arabicShare: number;    // share of letters that are Arabic, 0-1
}

const strip = (t: string) => t.replace(/https?:\/\/\S+|www\.\S+|\S+@\S+\.\S+/g, ' ');

export function checkReadability(text: string, lang: GuardLang): Readability {
  const body = strip(String(text || '')).trim();
  // a sentence ends at . ! ? ؟ or a line break; a decimal point inside a number is not an end
  const sentences = body.split(/(?<!\d)[.!?؟]+(?!\d)|\n+/).map((s) => s.trim()).filter((s) => /[\p{L}\p{N}]/u.test(s));
  const counts = sentences.map((s) => s.split(/\s+/).filter((w) => /\p{L}/u.test(w)).length);
  const maxW = counts.length ? Math.max(...counts) : 0;
  const avgW = counts.length ? Math.round((counts.reduce((a, b) => a + b, 0) / counts.length) * 10) / 10 : 0;

  const lower = body.toLowerCase();
  const jargon = [
    ...JARGON_EN.filter((j) => new RegExp(`(^|[^\\p{L}])${j.replace(/ /g, '\\s+')}([^\\p{L}]|$)`, 'u').test(lower)),
    ...JARGON_AR.filter((j) => body.includes(j)),
    ...(body.match(/\b[a-z]+(?:_[a-z0-9]+)+\b/g) ?? []),
  ];

  const ar = (body.match(/[؀-ۿ]/g) ?? []).length;
  const la = (body.match(/[A-Za-z]/g) ?? []).length;
  const arabicShare = ar + la ? Math.round((ar / (ar + la)) * 100) / 100 : 0;

  const issues: string[] = [];
  if (maxW > MAX_SENTENCE_WORDS) issues.push(`long_sentence:${maxW}`);
  const averaged = counts.length >= MIN_SENTENCES_FOR_AVERAGE;
  if (averaged && avgW > MAX_AVG_SENTENCE_WORDS) issues.push(`long_average:${avgW}`);
  if (jargon.length) issues.push('jargon:' + [...new Set(jargon)].slice(0, 5).join(','));
  if (ar + la > 0 && lang === 'ar' && arabicShare < 0.6) issues.push('wrong_language:expected_ar');
  if (ar + la > 0 && lang === 'en' && arabicShare > 0.1) issues.push('wrong_language:expected_en');

  let score = 100;
  score -= Math.max(0, maxW - MAX_SENTENCE_WORDS) * 2;
  if (averaged) score -= Math.max(0, avgW - MAX_AVG_SENTENCE_WORDS) * 3;
  score -= new Set(jargon).size * 10;
  if (issues.some((i) => i.startsWith('wrong_language'))) score -= 50;

  let tone = 100;
  const shouting = (body.match(/\b[A-Z]{4,}\b/g) ?? []).filter((w) => !ACRONYMS.has(w)).length;
  tone -= shouting * 10;
  tone -= (body.match(/!{2,}/g) ?? []).length * 10;
  tone -= BLAME.filter((b) => b.test(body)).length * 20;

  const clamp = (n: number) => Math.max(0, Math.min(100, Math.round(n)));
  return { ok: issues.length === 0, score: clamp(score), tone: clamp(tone), issues, sentences: sentences.length,
    maxSentenceWords: maxW, avgSentenceWords: avgW, jargon: [...new Set(jargon)], arabicShare };
}

/** The instruction handed to the model when a composed reply failed the gate. */
export function rewritePrompt(lang: GuardLang): string {
  return 'You rewrite a customer-support reply for QuotesDone so a busy person reads it once on a phone. '
    + `Write it in ${lang === 'ar' ? 'formal Gulf Arabic' : 'plain UAE English'}. Keep every fact, figure, rule, phone number, e-mail and link exactly; add nothing. `
    + `Every sentence under ${MAX_SENTENCE_WORDS - 8} words. No legal or technical terms, no abbreviations a buyer would not use, no internal names. `
    + 'Warm, calm, never blaming. Plain text, no markdown. Answer only with JSON: {"answer": "..."}';
}
