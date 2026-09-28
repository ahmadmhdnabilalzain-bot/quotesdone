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
//   internal  an error, stack trace, routine, vendor or credential name → the whole reply is replaced;
//   prompt    wording from our own system prompts → the whole reply is replaced.
// A replaced reply is a courteous one in the person's language with the published contact.
// It does NOT judge tone, grounding or routing — the scenario suite grades those.

export type GuardLang = 'en' | 'ar';
export type Violation = 'licence' | 'ai_word' | 'internal' | 'prompt';

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

const CONTACT_EN = 'call or WhatsApp +971 50 931 9355 (Mon-Fri, 9am-6pm GST) or email management@quotesdone.com';
const CONTACT_AR = 'تواصل معنا اتصالًا أو عبر واتساب على\n+971 50 931 9355\n(من الاثنين إلى الجمعة، 9 صباحًا حتى 6 مساءً بتوقيت الخليج)، أو راسلنا على\nmanagement@quotesdone.com';

export function safeReply(lang: GuardLang): string {
  return lang === 'ar'
    ? 'يسعدني الرد على أسئلتك حول آلية عمل QuotesDone، والرسوم، وتقديم الطلبات، والانضمام كمورّد. وللتحدث مع أحد فريقنا مباشرة، ' + CONTACT_AR + '.'
    : 'I can help with how QuotesDone works, fees, posting a job, or joining as a supplier. To speak with someone directly, ' + CONTACT_EN + '.';
}

/** What is wrong with a reply, without changing it. The scenario suite grades with this too. */
export function replyViolations(text: string): Violation[] {
  const s = String(text || '');
  const v: Violation[] = [];
  if (LICENCE.test(s)) v.push('licence');
  if (new RegExp(AI_EN.source, 'i').test(s) || new RegExp(AI_AR.source).test(s)) v.push('ai_word');
  if (INTERNAL.test(s)) v.push('internal');
  if (PROMPT.test(s)) v.push('prompt');
  return v;
}

/** The reply that may be sent, and what was wrong with the one that was offered. */
export function guardSupportReply(text: string, lang: GuardLang): { text: string; violations: Violation[] } {
  const violations = replyViolations(text);
  if (!violations.length) return { text, violations };
  if (violations.includes('internal') || violations.includes('prompt')) return { text: safeReply(lang), violations };
  let out = String(text);
  if (violations.includes('licence')) {
    // Drop the sentence (or line) that names it; a parenthesis holding it goes with its sentence.
    out = out.split('\n')
      .map((line) => line.split(/(?<=[.!?؟])[ \t]+/).filter((part) => !LICENCE.test(part)).join(' '))
      .join('\n').replace(/\n{3,}/g, '\n\n').trim();
  }
  if (violations.includes('ai_word')) {
    out = out.replace(AI_EN, 'smart').replace(AI_AR, 'التقنية الذكية');
  }
  // Nothing sensible left once the offending sentence is gone: say something true instead of nothing.
  if (out.replace(/\s/g, '').length < 12) out = safeReply(lang);
  return { text: out, violations };
}
