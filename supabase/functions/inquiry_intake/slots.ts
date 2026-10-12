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
import { requirementQuestions, isValidAnswer, NO_PREFERENCE, type Answers, type Ans } from '../_shared/intake_requirements.ts';

const asText = (v: unknown) => (typeof v === 'object' ? JSON.stringify(v) : String(v ?? '')).trim();
const filled = (v: unknown) => v !== undefined && v !== null && !['', '{}', '[]', 'null'].includes(asText(v));

export type SlotState = { details: Record<string, string>; missingKeys: string[]; missing: string[]; complete: boolean; settledUnanswered: string[] };

// ── A QUESTION IS NOT ASKED FOREVER (12 Oct 2026, sales_engineer) ─────────────────────────────────
// MEASURED. Stage-2 run f4294be8: C9 (waterproofing, EN) was asked "Is there a leak now, or is this to
// prevent one?" on 13 consecutive turns, and C6 (joinery, AR) the finish question the same way. Each
// customer replied every turn and no reply carried the fact, so the slot stayed open and the request
// never reached ready (inquiry_intake 7abdcac0..., b99d73de..., 14 turns each). A real customer who
// does not know, or answers in words the model does not file under the key, was trapped the same way.
// Once a required key has stayed open through MAX_OPEN_TURNS answered turns it is SETTLED as
// unanswered: recorded under its key as "not specified - supplier to advise" (the prompt's rule 5, a
// supplier decision, never an invented fact), provenance 'unanswered', and the request can go ready.
export const MAX_OPEN_TURNS = 3;
export const UNANSWERED: Record<Lang, string> = {
  en: 'Not specified by the customer - supplier to advise',
  ar: 'لم يحدده العميل - يقترحه المورّد',
};

/** How many earlier assistant turns each required key stayed open on (stampTurn's missing_keys). */
export function openTurnsByKey(turns: any[]): Record<string, number> {
  const n: Record<string, number> = {};
  for (const t of turns || []) {
    const ks = t && t.role === 'assistant' && t.slots && Array.isArray(t.slots.missing_keys) ? t.slots.missing_keys : [];
    for (const k of ks) n[String(k)] = (n[String(k)] || 0) + 1;
  }
  return n;
}

/** Merge what the model extracted this turn into what earlier turns captured, then derive missing. */
export function reconcileSlots(checklist: SpecField[], prevDetails: Record<string, unknown> | null | undefined, modelOut: any, lang: Lang, openTurns: Record<string, number> = {}): SlotState {
  const details: Record<string, string> = {};
  for (const [k, v] of Object.entries(prevDetails || {})) if (filled(v)) details[k] = asText(v);
  const b = modelOut && typeof modelOut.brief === 'object' && modelOut.brief ? modelOut.brief : {};
  const det = b.details && typeof b.details === 'object' ? b.details : {};
  const keys = new Set(checklist.map((f) => f && f.key).filter(Boolean) as string[]);
  for (const [k, v] of Object.entries(det)) if (filled(v)) details[k] = asText(v);
  // A checklist key the model put at the top of the brief (brief.location) instead of under details.
  for (const k of keys) if (!(k in details) && filled(b[k])) details[k] = asText(b[k]);
  const required = orderFields(checklist).filter((o) => o.f.required && o.f.key);
  const settledUnanswered: string[] = [];
  for (const o of required) {
    const k = String(o.f.key);
    if (!(k in details) && (openTurns[k] || 0) >= MAX_OPEN_TURNS) { details[k] = UNANSWERED[lang] || UNANSWERED.en; settledUnanswered.push(k); }
  }
  const open = required.filter((o) => !(String(o.f.key) in details));
  return {
    details, settledUnanswered,
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
export function settleModelTurn(checklist: SpecField[], prevDetails: Record<string, unknown> | null | undefined, out: any, lang: Lang, briefOf: (details: Record<string, string>) => any, openTurns: Record<string, number> = {}): SlotState {
  const sl = reconcileSlots(checklist, prevDetails, out, lang, openTurns);
  if (sl.settledUnanswered.length) out.provenance = { ...(out.provenance && typeof out.provenance === 'object' ? out.provenance : {}), ...Object.fromEntries(sl.settledUnanswered.map((k) => [k, 'unanswered'])) };
  const modelStatus = out.status;
  const modelAsked = Array.isArray(out.questions) && out.questions.some((q: unknown) => String(q ?? '').trim() !== '');
  // claims_ready: the model's own structured flag saying its sentence tells the customer the request is
  // ready/complete/about to be shared. A missing flag is read as a claim (it cannot be shown false).
  const claimsReady = out.claims_ready !== false;
  out.status = sl.complete ? 'ready' : 'needs_info';
  if (sl.complete) {
    const base = out.brief && typeof out.brief === 'object' ? out.brief : briefOf(sl.details);
    out.brief = { ...base, details: { ...(base.details || {}), ...sl.details } };
    out.missing = [];
  } else {
    out.missing = sl.missing;
    if (!Array.isArray(out.questions) || !out.questions.length) out.questions = sl.missing.slice(0, 1);
  }
  // The reply must agree with the row (review of #1277). READY: always the state's sentence, which tells
  // the customer to press Send to suppliers - the request goes nowhere until they confirm. NOT READY: the
  // model's sentence stands only when it wrote for needs_info, asked something, and flagged
  // claims_ready=false; anything else ("The request is ready to share with suppliers" beside needs_info,
  // run fe7ba9c4) is replaced by the state's next question. Structured fields only, no word matching.
  if (out.status === 'ready' || modelStatus !== out.status || !modelAsked || claimsReady) out.assistant_message = replyFromState(out.status, sl.missing[0] || null, lang);
  return sl;
}

// ── THE SALES ENGINEER'S FOUR QUESTIONS, READ BY THE MODEL (7 Oct 2026, run fe7ba9c4) ─────────────
// Measured in the run's transcripts: C1 and C7 said "Supply and install, within six weeks" in turn 3
// and were still asked "By when do you need it done?" at turn 10; "grade: not sure, standard
// commercial" and "standard specification, please assume typical values" were never recorded as a
// material answer (C1 req_answers kept only installation + material.profile; C7 only installation),
// because the deterministic reader only takes an answer to the ONE question it last asked, and reads
// "six" as no number. The model reads the whole conversation; it returns each answer as a VALUE from
// the closed vocabulary below, and only a value isValidAnswer accepts is recorded. No customer word is
// matched here (ruling 890).

/** Instruction text for the prompt: every requirement key of the trade and the values it accepts. */
export function requirementsContract(category: string | null): string {
  const qs = requirementQuestions(String(category || ''));
  const mats = qs.filter((q) => q.kind === 'material').map((q) => `"${q.key}": one of ${JSON.stringify(q.options.map((o) => o.v))}, or "not_sure" when the customer is unsure or asks for the standard, or {"other": "<their words>"}`);
  return [...mats,
    '"installation": "yes" | "supply_only" | "not_needed" | "not_sure"',
    '"warranty": {"months": <minimum months>} | "not_needed" | "not_sure"',
    '"required_by": {"days": <days from today>, "text": "<their words>"} | {"date": "YYYY-MM-DD"} | "flexible"',
  ].join('\n');
}

const isoDay = (now: Date, days: number) => new Date(now.getTime() + days * 86400000).toISOString().slice(0, 10);

/** The model's values -> stored answers, keeping only what is a valid answer to the question. */
export function requirementsFromModel(category: string | null, req: unknown, now = new Date()): Answers {
  const out: Answers = {};
  if (!req || typeof req !== 'object') return out;
  const r = req as Record<string, any>;
  for (const q of requirementQuestions(String(category || ''))) {
    const v = r[q.key];
    if (v === undefined || v === null || v === '') continue;
    let a: Ans | null = null;
    if (q.kind === 'material') {
      if (v === 'not_sure' || v === NO_PREFERENCE.v) a = { v: NO_PREFERENCE.v, note: v === 'not_sure' ? 'Not sure: supplier to propose the standard specification' : null };
      else if (typeof v === 'object' && String(v.other ?? '').trim()) a = { v: 'other', note: String(v.other).trim().slice(0, 200) };
      else if (typeof v === 'string') a = { v };
    } else if (q.kind === 'installation') {
      if (typeof v === 'string') a = { v };
    } else if (q.kind === 'warranty') {
      if (typeof v === 'object' && Number(v.months) > 0) a = { v: 'yes', min_months: Math.round(Number(v.months)) };
      else if (typeof v === 'string') a = { v, min_months: null };
    } else if (q.kind === 'required_by') {
      if (v === 'flexible') a = { v: 'flexible', date: null, text: 'Flexible' };
      else if (typeof v === 'object' && /^\d{4}-\d{2}-\d{2}$/.test(String(v.date || ''))) a = { v: 'date', date: String(v.date), text: String(v.text || v.date) };
      else if (typeof v === 'object' && Number(v.days) >= 0 && Number.isFinite(Number(v.days))) a = { v: 'date', date: isoDay(now, Math.round(Number(v.days))), text: String(v.text || `${Math.round(Number(v.days))} days`).slice(0, 80) };
    }
    if (a && isValidAnswer(q, a)) out[q.key] = a;
  }
  return out;
}

// ── WHAT WAS RECORDED WHEN (7 Oct 2026) ──────────────────────────────────────────────────────────
// The run's transcripts showed what the assistant SAID each turn and only the final row, so nobody
// could see that turn 1's slots were never stored. Each assistant turn now carries the state saved
// with it.
export type TurnSlots = { status: string; details: Record<string, unknown>; req_answers: Answers; missing: string[]; missing_keys?: string[] };
export function stampTurn(turns: any[], snap: TurnSlots): void {
  for (let i = turns.length - 1; i >= 0; i--) {
    if (turns[i] && turns[i].role === 'assistant') { turns[i].slots = { ...snap, at: new Date().toISOString() }; return; }
  }
}
