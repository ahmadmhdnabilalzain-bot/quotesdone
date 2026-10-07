// slots — the model path's state is the intake row, not the model's mood (7 Oct 2026, sales_engineer).
//
// MEASURED. Stage-2 sandbox run fe7ba9c4 (7 Oct ~00:15-01:30 UTC, inquiry_qualification_conversation on
// openai/gpt-6-luna, every llm_attempt ok with finish_reason=stop): customer C1's first message was
// "Aluminium ... for a villa in Dubai. Line 1: windows x 20 ...". The assistant said it had the villa
// location and later that the request was ready to share, yet the row stayed status=needs_info with
// missing=[element, location] and brief.details={} for ten turns, and no inquiry was ever created.
// Every demo customer, EN and AR, ended the same way (ai_qa_log kind=intake, 22 Sep–7 Oct readiness
// wandering 45..85, never ready).
//
// WHY. Three defects on the model path in index.ts, none on the deterministic interview:
//  1. The prompt told the model to return brief=null unless status=ready, and the row saved
//     `details: prevBrief.details || {}` on every non-ready turn. What the customer stated in turn 1
//     was therefore never captured anywhere; each turn the model re-derived everything from the raw
//     conversation and the row carried nothing forward.
//  2. status and missing were the model's own free answer, so a model that kept listing a stated key
//     as missing kept the request parked forever — nothing compared its claim to a slot.
//  3. assistant_message was the model's text even when the code then changed the status (the canonical
//     ready gate flips ready -> needs_info and left the model's "ready to share" sentence in place).
//
// WHAT THIS DOES. The model only EXTRACTS (brief.details under the checklist's canonical keys, every
// turn). The slots accumulate across turns on the row. Status and missing are DERIVED from the slots:
// every required key filled -> ready, else needs_info with exactly the unfilled keys. When the derived
// status differs from the status the model wrote its sentence for, the sentence is replaced by one
// built from the state, so the customer is never told "ready" while the row says otherwise. No word of
// the customer's text is matched here (ruling 890): only keys and values the model returned are read.
import { orderFields, questionText, type Lang, type SpecField } from './interview.ts';

const asText = (v: unknown) => (typeof v === 'object' ? JSON.stringify(v) : String(v ?? '')).trim();
const filled = (v: unknown) => v !== undefined && v !== null && !['', '{}', '[]', 'null'].includes(asText(v));

export type SlotState = { details: Record<string, string>; missingKeys: string[]; missing: string[]; complete: boolean };

/** Merge what the model extracted this turn into what earlier turns captured, then derive missing. */
export function reconcileSlots(checklist: SpecField[], prevDetails: Record<string, unknown> | null | undefined, modelOut: any, lang: Lang): SlotState {
  const details: Record<string, string> = {};
  for (const [k, v] of Object.entries(prevDetails || {})) if (filled(v)) details[k] = asText(v);
  const b = modelOut && typeof modelOut.brief === 'object' && modelOut.brief ? modelOut.brief : {};
  const det = b.details && typeof b.details === 'object' ? b.details : {};
  const keys = new Set(checklist.map((f) => f && f.key).filter(Boolean) as string[]);
  for (const [k, v] of Object.entries(det)) if (filled(v)) details[k] = asText(v);
  // A checklist key the model put at the top of the brief (brief.location) instead of under details.
  for (const k of keys) if (!(k in details) && filled(b[k])) details[k] = asText(b[k]);
  const required = orderFields(checklist).filter((o) => o.f.required && o.f.key);
  const open = required.filter((o) => !(String(o.f.key) in details));
  return {
    details,
    missingKeys: open.map((o) => String(o.f.key)),
    missing: open.map((o) => questionText(o.f, lang)),
    complete: open.length === 0,
  };
}

/** The reply when the status the code settled on is not the one the model wrote its sentence for. */
export function replyFromState(status: string, firstMissingQuestion: string | null, lang: Lang): string {
  if (status === 'ready') {
    return lang === 'ar'
      ? 'شكرًا لك، اكتمل كل ما يحتاجه المورّدون. راجع الملخص أدناه، ثم اضغط «أرسل إلى الموردين».'
      : 'Thank you — that is everything suppliers need. Check the summary below and press Send to suppliers.';
  }
  const ack = lang === 'ar' ? 'شكرًا، دوّنت ذلك. ' : 'Thanks, noted. ';
  return ack + (firstMissingQuestion || (lang === 'ar' ? 'هل يمكنك إخبارنا بالمزيد عن العمل المطلوب؟' : 'Could you tell me a little more about the job?'));
}

/**
 * Apply the slots to one parsed model turn, in place: details accumulate, status and missing are the
 * row's, and the reply is rebuilt whenever the status differs from the one the model wrote it for.
 * `briefOf` builds a brief from the slots when the model sent none (index.ts passes buildBrief).
 */
export function settleModelTurn(checklist: SpecField[], prevDetails: Record<string, unknown> | null | undefined, out: any, lang: Lang, briefOf: (details: Record<string, string>) => any): SlotState {
  const sl = reconcileSlots(checklist, prevDetails, out, lang);
  const modelStatus = out.status;
  const modelAsked = Array.isArray(out.questions) && out.questions.some((q: unknown) => String(q ?? '').trim() !== '');
  out.status = sl.complete ? 'ready' : 'needs_info';
  if (sl.complete) {
    const base = out.brief && typeof out.brief === 'object' ? out.brief : briefOf(sl.details);
    out.brief = { ...base, details: { ...(base.details || {}), ...sl.details } };
    out.missing = [];
  } else {
    out.missing = sl.missing;
    if (!Array.isArray(out.questions) || !out.questions.length) out.questions = sl.missing.slice(0, 1);
  }
  // A needs_info sentence that asks nothing is a sentence written as if the request were done (run
  // fe7ba9c4: "The request is ready to share with suppliers" beside status needs_info). Not ready and
  // asking nothing -> the state asks its next question instead.
  if (modelStatus !== out.status || (out.status === 'needs_info' && !modelAsked)) out.assistant_message = replyFromState(out.status, sl.missing[0] || null, lang);
  return sl;
}
