// support_reply_guard — the last thing every customer_support reply passes before it is sent.
//
// MEASURED 28 Sep 2026 (read-only, production assistant_logs): 4 widget replies carried the trade licence
// number, the latest on 22 Sep to "What does QuotesDone do?". The founder's rule (23 Sep) is that no reply,
// profile or bio shows the licence number and none says "AI". Both prompts (site_assistant, wa_inbound)
// typed the number into their facts, and a support-pack passage carries it too — so it reached people by
// the model path AND the deterministic corpus path. Nothing looked at a reply before it left: the widget
// only stripped markdown.
//
// This is deliberately code, not a prompt rule (founder instruction 781: "there will be always a trick in
// the wording that will leak"). It runs on EVERY outgoing text, model or not:
//   licence   a sentence naming the licence number is dropped (the rest of the reply stands);
//   ai_word   "AI" / "artificial intelligence" / its Arabic becomes "smart" (profile-copy rule);
//   internal  an error, stack trace, routine, vendor or credential name → the reply is REFUSED (text '');
//   prompt    wording from our own system prompts → the reply is REFUSED (text '').
//   internal_number  a stated count of OUR suppliers, customers or leads (19 Oct 2026: the exam answer told a supplier
//            the registered supplier count) → the sentence is dropped. Narrowed on review: see hasInternalNumber.
// 12 Oct 2026 (founder rulings 1195/1196, review of #1330): code no longer substitutes a canned reply. A refused reply
// goes BACK TO THE MODEL for a rewrite — callers check replyViolations() first and ask aiReply (_shared/ai_reply.ts),
// which rewrites with the problems named. guardSupportReply is the last line only: a refusal it still sees sends nothing.
// It does NOT judge tone, grounding or routing — the scenario suite grades those.

export type GuardLang = 'en' | 'ar';
export type Violation = 'licence' | 'ai_word' | 'internal' | 'prompt' | 'internal_number';

// The operator's own licence number only. A supplier's OWN licence number is a wanted confirmation
// ("updated: licence no …" after a WhatsApp upload), so no generic "licence no + digits" pattern.
const LICENCE = /1633275/;
// "AI" as a whole word (\b keeps "Dubai" and "said" out), any case.
const AI_EN = /\bA\.?I\b(?:[-‑ ]?(?:powered|driven|based))?|\bartificial intelligence\b/gi;
const AI_AR = /(?:ال)?ذكاء\s+(?:ال)?اصطناعي/g;
// Text that only ever comes from our own machinery. Tokens are specific on purpose: "error" or "server"
// alone appear in honest customer answers ("an error on your invoice").
const INTERNAL = /circuit_open|openrouter|supabase|service_role|app_secrets|\bfn_[a-z0-9_]{3,}\b|\bai_gateway\b|\bedge function\b|\bSQLSTATE\b|\b(?:Type|Reference|Syntax)Error\b|\bat [\w$.]+ \([^)]*:\d+:\d+\)|\bHTTP [45]\d\d\b|\bjwt\b|\bnull pointer\b|\bundefined is not\b|\bstack trace\b/i;
// Headings and phrases that exist only inside our system prompts.
const PROMPT = /SHARED FACTS|CUSTOMER-SIDE FACTS|SUPPLIER-SIDE FACTS|AUDIENCE RULES|FORMAT RULES|GENERAL RULES|COMPANY BLOCK|FAQ CONTEXT|PRICE GUIDANCE:|system prompt|my instructions (?:are|say)|I (?:was|am) instructed to/i;


// INTERNAL NUMBER (19 Oct 2026, narrowed on review of #1549). A sentence is refused only when ALL three hold:
//   1. a COUNT: 100 or more as digits ("19,901", "19901", "20,000+"), a short form ("15k", "1.9 thousand", "2 million"),
//      or words ("nineteen thousand", "twenty thousand", "thousands of", Arabic "15 ألف", "آلاف");
//   2. within 40 characters of a word for the people we hold: suppliers, vendors, customers, clients, buyers, leads,
//      registrations, members (Arabic مورد/موردين/عملاء/شركات);
//   3. an OURS cue in the same sentence: we have / we currently / our network, platform, directory, database / there
//      are / registered / signed up / on our or the platform (Arabic لدينا، منصتنا، شبكتنا، مسجل).
// Never a count: a reference ("QD-10234"), a year (1900-2099), a phone number, a price (AED 1,000), "up to N" (a
// capacity, not a size), and the published programme figures (the first 1,000 free; the fee from the 1,001st).
const PEOPLE = String.raw`(?:suppliers?|vendors?|customers?|clients?|buyers?|leads|registrations?|members|موردين|مورّدين|موردًا|مورد|عملاء|عميل|شركات)`;
const WORD_NUM = String.raw`(?:(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[- ](?:one|two|three|four|five|six|seven|eight|nine))?[- ](?:hundred|thousand|million)|(?:a|one) (?:hundred|thousand)|(?:hundreds|thousands|tens of thousands) of)`;
const AR_NUM = String.raw`(?:[0-9٠-٩]+(?:[.,٫][0-9٠-٩]+)?\s*(?:ألف|آلاف|مليون)|آلاف|مئات)`;
const DIGIT_NUM = String.raw`(?:[0-9٠-٩]{1,3}(?:[,٬][0-9٠-٩]{3})+|[0-9٠-٩]{3,}|[0-9٠-٩]+(?:[.,٫][0-9٠-٩]+)?\s*(?:k|K|thousand|million)\b)\+?`;
const COUNT = String.raw`(?:${DIGIT_NUM}|${WORD_NUM}|${AR_NUM})`;
const COUNT_NEAR_PEOPLE = new RegExp(String.raw`${COUNT}[^.!?؟\n]{0,40}?${PEOPLE}|${PEOPLE}[^.!?؟\n]{0,40}?${COUNT}`, 'iu');
const OURS = /\b(?:we have|we've|we currently|we now have|our (?:network|platform|directory|database|base|community|list|system)|there are|registered|signed up|on (?:our|the) (?:platform|network|directory))\b|لدينا|منصتنا|شبكتنا|مسجل|مسجّل|مسجلين/iu;
const NOT_A_COUNT = [
  /\b[A-Z]{2,}(?:-[A-Z0-9]+)+\b/g,                                          // references: QD-10234, QD-S-KYUUSA
  /\+?\d[\d\s().-]{7,}\d/g,                                                   // phone numbers
  /\b(?:19|20)\d{2}\b(?![,٬]\d)/g,                                            // years
  /(?:AED|USD|Dhs?|درهم)\s*[0-9٠-٩][0-9٠-٩,٬.]*|[0-9٠-٩][0-9٠-٩,٬.]*\s*(?:AED|USD|Dhs?|درهم)/giu, // prices
  /\bup to\s+\S+|حتى\s+\S+/giu,                                               // a capacity, not our size
  /(?:first|أول|أوّل)\s*(?:1[,٬]?000|١[٬,]?٠٠٠)|(?:1[,٬]?001|١[٬,]?٠٠١)(?:st)?/giu, // the published programme figures
];
function hasInternalNumber(s: string): boolean {
  return String(s || '').split(/(?<=[.!?؟])\s+|\n+/).some((sentence) => {
    let t = sentence;
    for (const re of NOT_A_COUNT) t = t.replace(re, ' ');
    return OURS.test(t) && COUNT_NEAR_PEOPLE.test(t);
  });
}


/** What is wrong with a reply, without changing it. The scenario suite grades with this too. */
export function replyViolations(text: string): Violation[] {
  const s = String(text || '');
  const v: Violation[] = [];
  if (LICENCE.test(s)) v.push('licence');
  if (new RegExp(AI_EN.source, 'i').test(s) || new RegExp(AI_AR.source).test(s)) v.push('ai_word');
  if (INTERNAL.test(s)) v.push('internal');
  if (PROMPT.test(s)) v.push('prompt');
  if (hasInternalNumber(s)) v.push('internal_number');
  return v;
}

/** The reply that may be sent, and what was wrong with the one that was offered. */
export function guardSupportReply(text: string, lang: GuardLang): { text: string; violations: Violation[] } {
  const violations = replyViolations(text);
  if (!violations.length) return { text, violations };
  void lang;
  if (violations.includes('internal') || violations.includes('prompt')) return { text: '', violations };
  let out = String(text);
  if (violations.includes('licence')) {
    // Drop the sentence (or line) that names it; a parenthesis holding it goes with its sentence.
    out = out.split('\n')
      .map((line) => line.split(/(?<=[.!?؟])[ \t]+/).filter((part) => !LICENCE.test(part)).join(' '))
      .join('\n').replace(/\n{3,}/g, '\n\n').trim();
  }
  if (violations.includes('internal_number')) {
    out = out.split('\n')
      .map((line) => line.split(/(?<=[.!?؟])[ \t]+/).filter((part) => !hasInternalNumber(part)).join(' '))
      .join('\n').replace(/\n{3,}/g, '\n\n').trim();
  }
  if (violations.includes('ai_word')) {
    out = out.replace(AI_EN, 'smart').replace(AI_AR, 'التقنية الذكية');
  }
  // Nothing sensible left once the offending sentence is gone: send nothing (the caller asks the model again).
  if (out.replace(/\s/g, '').length < 12) out = '';
  return { text: out, violations };
}
