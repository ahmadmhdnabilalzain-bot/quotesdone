// inquiry_intake/question_card.ts — WHAT THE PORTAL RENDERS UNDER THE REPLY: the question card (the one question, with its own
// buttons) and the readiness bar, and every question still open. Moved verbatim from handle.ts (19 Nov 2026, it_engineer;
// ledgers 1714/1715/1556: handle.ts was 1,418 lines), which runs it once the reply's content is decided.
// deno-lint-ignore-file no-explicit-any
import { questionText, optionsOf } from './interview.ts';
import { slotKeyFor } from './slots.ts';
import { requirementQuestions } from '../_shared/intake_requirements.ts';

type NextQuestion = { key: string | null; text: string; options: string[] | null; suggested?: string | null } | null;

export function questionCard(c: { checklist: any[]; status: string; requiredGate: { category: string; missing_keys: string[] } | null; out: any;
  slotAsk: { key: string; text: string } | null; slotLang: 'en' | 'ar'; category: string | null; reqProgress: { filled: number; total: number } | null;
  reqRemaining: string[]; readinessFields: { filled: number; required: number } | null; nextQuestion: NextQuestion }) {
  const { checklist, status, requiredGate, out, slotAsk, slotLang, category, reqProgress, reqRemaining } = c;
  let { readinessFields, nextQuestion } = c;
  // The two additions the portal renders (14 Sep 2026). On the model path they are derived from
  // what the model and the canonical gate returned; on the interview path they are exact.
  const reqCount = checklist.filter((f: any) => f && f.required).length;
  if (!readinessFields) readinessFields = { filled: status === 'ready' ? reqCount : Math.max(0, reqCount - (requiredGate ? requiredGate.missing_keys.length : (Array.isArray(out.missing) ? out.missing.length : reqCount))), required: reqCount };
  // The drawing's confirm question is the one question allowed beside a ready request (above).
  if (status === 'ready') { if (!nextQuestion || nextQuestion.key !== 'boq_check') nextQuestion = null; readinessFields = { filled: readinessFields.required, required: readinessFields.required }; }
  else if (!nextQuestion && Array.isArray(out.questions) && out.questions.length) {
    const key = requiredGate ? requiredGate.missing_keys[0] || null
      // Before a ready the gate is null; the slot state's key is named only when its question is the one asked
      // (a question the model wrote in its own words has no key we can vouch for). Run 321d13ae: key was always null.
      : slotKeyFor(slotAsk, String(out.questions[0]));
    // ITS OWN BUTTONS, AND ONLY ITS OWN (15 Nov 2026, journey A): a spec code asks, by its key, carries that spec's options; a
    // question with no key we can vouch for (the model's own words) carries none.
    const f = key ? checklist.find((x: any) => x && String(x.key) === key) : null;
    const opts = optionsOf(f, slotLang) ?? [];
    const own = slotKeyFor(slotAsk, String(out.questions[0])) === key || (!!requiredGate && !!f && String(out.questions[0]) === questionText(f, slotLang));
    nextQuestion = { key, text: String(out.questions[0]), options: opts.length && own ? opts : null };
  }
  // The readiness bar counts the sales engineer's questions from the first turn, so it never reads
  // 100% while something is still going to be asked, and remaining_questions lists every open
  // question in the customer's language, so the composer can show exactly what is left.
  if (category) {
    const reqTotal = reqProgress ? reqProgress.total : requirementQuestions(category).length;
    if (status === 'ready') readinessFields = { filled: readinessFields.required + reqTotal, required: readinessFields.required + reqTotal };
    else if (reqProgress) { readinessFields = { filled: readinessFields.required + reqProgress.filled, required: readinessFields.required + reqTotal }; out.readiness = Math.min(95, Math.round(100 * readinessFields.filled / Math.max(1, readinessFields.required))); }
    else readinessFields = { filled: readinessFields.filled, required: readinessFields.required + reqTotal };
  }
  const remainingQuestions: string[] = status === 'ready' ? [] : Array.from(new Set([...(Array.isArray(out.missing) ? out.missing.map((m: any) => String(m)) : []), ...reqRemaining])).slice(0, 12);
  return { readinessFields, nextQuestion, remainingQuestions };
}
