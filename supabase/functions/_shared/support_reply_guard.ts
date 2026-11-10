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
// A reply that cites the knowledge it was given ("the brief doesn't give a public address", conversation-quality run of
// 3 Nov 2026) is prompt wording too; the customer's own job brief ("a priceable brief", "the same brief") is not.
// The job's brief stays allowed in the portal ("the brief does not mention the frame colour yet"): only the company brief,
// "my brief", our sources, or the brief withholding a company fact (a public address, an office) is caught.
const CITES_BRIEF = /\bthe company brief\b|\bthe brief (?:does(?:n'?t| not) (?:give|state|list|mention|say|include)|gives no|has no) (?:a |an |any )?(?:public|street|office|company|physical)|\b(?:according to|per) (?:my|our) brief\b|\bmy brief\b|\b(?:my|our) sources (?:do(?:n'?t| not)|say|state)|\bthe sources (?:do(?:n'?t| not)) state/i;
const PROMPT = new RegExp(/SHARED FACTS|CUSTOMER-SIDE FACTS|SUPPLIER-SIDE FACTS|AUDIENCE RULES|FORMAT RULES|GENERAL RULES|COMPANY BLOCK|FAQ CONTEXT|PRICE GUIDANCE:|system prompt|my instructions (?:are|say)|I (?:was|am) instructed to/.source + '|' + CITES_BRIEF.source, 'i');
// THE MODEL'S OWN REASONING IS NEVER A REPLY (live conversation suite run a8ad5ed7, 19 Oct 2026: 2 of 30 Arabic
// conversations showed the customer a "<reasoning>...</reasoning>" block in English). Caught in the first sentence it
// opens, before anything is shown, so the attempt is written again.
const REASONING = /<\/?(?:reasoning|thinking|think|scratchpad)\b[^>]*>/i;


// INTERNAL NUMBER (19 Oct 2026; second review of #1549). Two rules, judged per sentence:
//   A. A BIG COUNT, ALWAYS: 1,000 or more next to (within 40 characters, either order) suppliers, vendors, companies,
//      businesses, leads, customers, clients, buyers, registrations or members (Arabic مورد/موردين/عملاء/شركات), with or
//      without any "we have": "19,901 suppliers", "15k suppliers", "nineteen thousand suppliers", "QuotesDone has
//      19,901 suppliers". Forms: digits with or without separators, "15k", "1.9 thousand", "2 million", words with
//      thousand/million, "thousands of", Arabic "15 ألف" / "آلاف".
//   B. A SMALLER COUNT CLAIMED AS OURS: 100-999 next to those words AND a cue that it is ours in the same sentence
//      (we have / our network, platform, directory, database / there are / registered / on our platform; Arabic
//      لدينا، منصتنا، شبكتنا، مسجل). "Your request went to 120 suppliers" alone is not our size.
// Never a count, removed before judging: a reference ("QD-10234"), a phone number (short ones too: "800 1234",
// "04 123 4567"), a year, a price, a duration ("120 days", "30 minutes"), "up to N" (a capacity), and the published
// programme figures (the first 1,000 free; the fee from the 1,001st).
const PEOPLE = String.raw`(?:suppliers?|vendors?|compan(?:y|ies)|businesses|customers?|clients?|buyers?|leads|registrations?|members|موردين|مورّدين|موردًا|مورد|عملاء|عميل|شركات|شركة)`;
const NUM_WORD_UNIT = String.raw`(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[- ](?:one|two|three|four|five|six|seven|eight|nine))?`;
const BIG = String.raw`(?:[0-9٠-٩]{1,3}(?:[,٬   ][0-9٠-٩]{3})+|[0-9٠-٩]{4,}|[0-9٠-٩]+(?:[.,٫][0-9٠-٩]+)?\s*(?:k|K|thousand|million)\b|(?:${NUM_WORD_UNIT}|a|one)[- ](?:thousand|million)|(?:thousands|millions|tens of thousands) of|[0-9٠-٩]+(?:[.,٫][0-9٠-٩]+)?\s*(?:ألف|آلاف|مليون)|آلاف)\+?`;
const MID = String.raw`(?:[0-9٠-٩]{3}|${NUM_WORD_UNIT}[- ]hundred|(?:a|one) hundred|hundreds of|مئات)\+?`;
const near = (n: string) => new RegExp(String.raw`(?<![0-9٠-٩,٬.])${n}[^.!?؟\n]{0,40}?${PEOPLE}|${PEOPLE}[^.!?؟\n]{0,40}?(?<![0-9٠-٩,٬.])${n}(?![0-9٠-٩])`, 'iu');
const BIG_NEAR_PEOPLE = near(BIG);
const MID_NEAR_PEOPLE = near(MID);
const OURS = /\b(?:we have|we've|we currently|we now have|our (?:network|platform|directory|database|base|community|list|system)|there are|registered|signed up|on (?:our|the) (?:platform|network|directory))\b|لدينا|منصتنا|شبكتنا|مسجل|مسجّل|مسجلين/iu;
const PHONE = /\+?\(?\d{2,4}\)?[\s.-]\d{2,4}(?:[\s.-]\d{2,4}){0,3}\b/g;   // phone numbers, short ones too (7+ digits)
// A phone word DIRECTLY before the number, with at most a few joining words ("call 800 123", "WhatsApp at 050 123",
// "phone us on 600 522", "اتصلوا على 800 123"). Anywhere else in the sentence it proves nothing (fifth review of #1549:
// "Call us today: we have 19 900 suppliers.").
const PHONE_WORD_BEFORE = /(?:\b(?:call|phone|tel|telephone|mobile|whatsapp|hotline|toll[- ]free|dial|fax)\b|اتصل|اتصلوا|هاتف|جوال|واتساب|الرقم)[\s:.]*(?:(?:us|me|them|on|at|via|number|no\.?|رقم|على|عبر)[\s:.]+){0,3}$/iu;
const NOT_A_COUNT = [
  /\b[A-Z]{2,}(?:-[A-Z0-9]+)+\b/g,                                                    // references: QD-10234, QD-S-KYUUSA
  // a request, job or report number written as a reference: "#5202", "Job 7731", "طلب رقم 5202" (it_engineer, 10 Nov 2026).
  // Eval A (docs/reports/2026-11-10-model-routing-evals.md): "طلبكم #5202 ... وصل إلى 4 موردين" read 5202 as OUR supplier
  // count, the sentence was refused, and the rewrite then left out the reference the reply must carry (3 of 12 status turns).
  /#\s?[0-9٠-٩]{3,}\b|\b(?:job|request|inquiry|report|quote)\s+(?:no\.?\s*|number\s+|#\s?)?[0-9]{3,}\b|(?:طلب|الطلب|طلبكم|طلبك|رقم)\s+(?:رقم\s+)?#?\s?[0-9٠-٩]{3,}/giu,
  /\b(?:19|20)\d{2}\b(?![,٬]\d)/g,                                                      // years
  /(?:AED|USD|Dhs?|درهم)\s*[0-9٠-٩][0-9٠-٩,٬.]*|[0-9٠-٩][0-9٠-٩,٬.]*\s*(?:AED|USD|Dhs?|درهم)/giu, // prices
  /[0-9٠-٩][0-9٠-٩,٬.]*\s*(?:seconds?|minutes?|hours?|days?|weeks?|months?|years?|MB|KB|GB|km|m2|sqm|sq ft|يوم|أيام|ساعة|ساعات|شهر|أشهر)\b/giu, // durations, sizes
  /\bup to\s+\S+|حتى\s+\S+/giu,                                                         // a capacity, not our size
  /(?:first|أول|أوّل)\s*(?:1[,٬]?000|١[٬,]?٠٠٠)|(?:1[,٬]?001|١[٬,]?٠٠١)(?:st)?/giu,     // the published programme figures
];
function hasInternalNumber(s: string): boolean {
  return String(s || '').split(/(?<=[.!?؟])\s+|\n+/).some((sentence) => {
    // a phone number has at least 7 digits; "19 900" (5) is a count, not a phone (third review of #1549)
    // ...unless the sentence says it is a phone number ("call 800 123"): then any phone-shaped group is one (fourth review)
    // ...unless a phone word stands directly before it ("call 800 123"): then a shorter group is a phone number too
    let t = sentence.replace(PHONE, (m, ...a) => { const at = a[a.length - 2] as number; return (m.replace(/[^0-9]/g, '').length >= 7 || PHONE_WORD_BEFORE.test(sentence.slice(Math.max(0, at - 40), at))) ? ' ' : m; });
    for (const re of NOT_A_COUNT) t = t.replace(re, ' ');
    return BIG_NEAR_PEOPLE.test(t) || (OURS.test(t) && MID_NEAR_PEOPLE.test(t));
  });
}


/** What is wrong with a reply, without changing it. The scenario suite grades with this too. */
export function replyViolations(text: string): Violation[] {
  const s = String(text || '');
  const v: Violation[] = [];
  if (LICENCE.test(s)) v.push('licence');
  if (new RegExp(AI_EN.source, 'i').test(s) || new RegExp(AI_AR.source).test(s)) v.push('ai_word');
  if (INTERNAL.test(s)) v.push('internal');
  if (PROMPT.test(s) || REASONING.test(s)) v.push('prompt');
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
