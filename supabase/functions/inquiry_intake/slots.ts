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
import { aiReply } from '../_shared/ai_reply.ts';
import { modelOrOutage } from '../_shared/openrouter_down.ts';
import type { ThinkDeps } from '../_shared/think.ts';
import { requirementQuestions, isValidAnswer, NO_PREFERENCE, type Answers, type Ans } from '../_shared/intake_requirements.ts';

const asText = (v: unknown) => (typeof v === 'object' ? JSON.stringify(v) : String(v ?? '')).trim();
const filled = (v: unknown) => v !== undefined && v !== null && !['', '{}', '[]', 'null'].includes(asText(v));

export type SlotState = { details: Record<string, string>; missingKeys: string[]; missing: string[]; complete: boolean; exhausted: string[]; held: boolean };

// ── A QUESTION IS NOT ASKED FOREVER (12 Oct 2026, sales_engineer) ─────────────────────────────────
// MEASURED. Stage-2 run f4294be8: C9 (waterproofing, EN) was asked "Is there a leak now, or is this to
// prevent one?" on 13 consecutive turns, and C6 (joinery, AR) the finish question the same way. Each
// customer replied every turn and no reply carried the fact, so the slot stayed open and the request
// never reached ready (inquiry_intake 7abdcac0..., b99d73de..., 14 turns each). A real customer who
// does not know, or answers in words the model does not file under the key, was trapped the same way.
// Once a required key has stayed open through MAX_OPEN_TURNS answered turns it is EXHAUSTED: it is not
// asked again, and it stays MISSING - nothing is written under its key, so the request is never ready
// without the exact spec (founder rule: exact specs or the quote is held; review of #1319). The other
// open keys are still asked. When only exhausted keys are left, the intake is HELD and handed to the
// sales engineer (index.ts opens the spec.not_sure handoff, the same door the not-sure path uses).
export const MAX_OPEN_TURNS = 3;
export const HELD_FOR_SPECS: Record<Lang, string> = {
  en: 'Thank you. A few specifications are still open, so our sales engineer will help you settle them before this goes to suppliers. We will continue with you here; there is no need to type anything again.',
  ar: 'شكرًا لكم. ما زالت بعض المواصفات غير محددة، لذلك سيساعدكم مهندس المبيعات لدينا على تحديدها قبل إرسال الطلب إلى الموردين. سنكمل معكم هنا، ولا حاجة إلى إعادة كتابة أي شيء.',
};

// THE HELD REPLY NAMES WHAT IS STILL OPEN (customer_support, 19 Oct 2026). settleModelTurn clears `missing` on a hold,
// and HELD_FOR_SPECS said only "a few specifications are still open": a real customer was never told WHICH. The reply
// is now written by the model (ruling 1196) with the exhausted questions, in the inquiry language, as its facts.
// HELD_FOR_SPECS stays only as the handover when OpenRouter is down (no call reached a model: the deadline passed or the
// models errored; founder_instruction 1339). Every draft refused by the guards, model up, is NOT that case: '' comes back.
// The request chat is a portal surface, so the reply is the sales engineer's (the_portals_are_the_sales_engineer).
/** The plain questions still open on a held intake, in the customer's language, in checklist order. A field with no
 *  question text is skipped: a raw key ('area') never reaches the model. */
export function heldQuestions(checklist: SpecField[], exhausted: string[], lang: Lang): string[] {
  return orderFields(checklist).filter((o) => exhausted.includes(String(o.f.key)))
    .map((o) => String((lang === 'ar' ? o.f.question_plain_ar || o.f.question_plain_en : o.f.question_plain_en) || o.f.question || '').trim())
    .filter(Boolean);
}
/** The held reply, written by the model, naming every still-open question. */
export async function heldReply(deps: ThinkDeps, checklist: SpecField[], exhausted: string[], lang: Lang, message: string, conversation: { role: string; text: string }[], deadline?: number): Promise<string> {
  const open = heldQuestions(checklist, exhausted, lang);
  const r = await aiReply(deps, {
    seat: 'sales_engineer', channel: 'the website request chat', audience: 'customer', lang, message, deadline,
    conversation: conversation.map((t) => ({ role: t.role === 'assistant' ? 'seat' as const : 'customer' as const, text: String(t.text || '') })),
    facts: 'This request is HELD: it goes to no supplier yet. These questions were asked three times and are still unanswered:\n- ' + open.join('\n- ') +
      '\nOur sales engineer will help the customer settle them here in this chat; nothing needs to be typed again.',
    rules: 'Thank them, name EACH still-open question above in plain words, say our sales engineer will help settle them in this chat before it goes to suppliers. Two to four sentences. Do not ask anything else.',
  });
  // HELD_FOR_SPECS only when OpenRouter is down (founder_instruction 1339); a model that answered and was refused gives ''
  // and index.ts has the model say the hold again (intakeVoice), never this line.
  return modelOrOutage(r, HELD_FOR_SPECS[lang] || HELD_FOR_SPECS.en);
}

// ── THE INTAKE'S WORDS ARE THE MODEL'S (founder_instruction 1339, 27 Oct 2026) ──────────────────────────────────────
// "the engineer and customer support never replies without llm unless the server of open router is down".
// MEASURED on main before this (read from index.ts): the customer read code-written text on every turn where code
// decided the reply — the deterministic interview's question (taken whenever the model's JSON did not parse, model up),
// replyFromState (every turn the slots or the canonical gate disagreed with the model's status), HELD_FOR_SPECS, the
// "Thanks, noted. A few quick questions about materials…" lead before the four requirement questions, the drawing
// confirm question and the CAD ask appended to the reply, and the held-for-trade notice. Code still decides WHAT is
// said (the status, the one question, its options); intakeVoice hands that to the model as facts and the model writes
// it. The code draft is sent only when no call reached a model (outage); a model that answered but whose words were all
// refused leaves the reply '' (the question card and its options still show it; the next turn asks again).
export interface IntakeVoice { text: string; outage: boolean; by: 'model' | 'outage_fallback' | 'none' }
export async function intakeVoice(deps: ThinkDeps, o: { draft: string; lang: Lang; message: string; conversation: { role: string; text: string }[];
  next?: { text: string; options?: string[] | null } | null; deadline?: number }): Promise<IntakeVoice> {
  const ask = o.next && String(o.next.text || '').trim()
    ? '\nTHE ONE QUESTION TO ASK NOW (ask exactly this, in plain words; no other question): ' + String(o.next.text).trim()
      + (o.next.options?.length ? '\nThey can tap one of: ' + o.next.options.join(' | ') : '')
    : '\nAsk no question unless the message above asks one.';
  const r = await aiReply(deps, {
    seat: 'sales_engineer', channel: 'the website request chat', audience: 'customer', lang: o.lang, message: o.message || '(they sent a file or tapped an option)',
    conversation: o.conversation.slice(-12).map((t) => ({ role: t.role === 'assistant' ? 'seat' as const : 'customer' as const, text: String(t.text || '') })),
    facts: 'WHAT TO SAY ON THIS TURN (decided by our systems from the request\'s state; convey it in your own words, change nothing in its meaning, add nothing):\n' + o.draft + ask,
    rules: 'One to three short sentences for the request chat. Never say the request is ready, complete or sent unless the facts above say so. Never repeat a question they already answered.',
    deadline: o.deadline,
  }).catch(() => ({ reply: '', outage: false } as { reply: string; outage?: boolean }));
  const text = String(r.reply || '').trim();
  if (text) return { text, outage: false, by: 'model' };
  return r.outage === true ? { text: o.draft, outage: true, by: 'outage_fallback' } : { text: '', outage: false, by: 'none' };
}

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
  const open = required.filter((o) => !(String(o.f.key) in details));
  const exhausted = open.map((o) => String(o.f.key)).filter((k) => (openTurns[k] || 0) >= MAX_OPEN_TURNS);
  const askable = open.filter((o) => !exhausted.includes(String(o.f.key)));
  return {
    details, exhausted,
    missingKeys: open.map((o) => String(o.f.key)),
    missing: askable.map((o) => questionText(o.f, lang)),
    complete: open.length === 0,
    held: open.length > 0 && askable.length === 0,
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
  const modelStatus = out.status;
  const modelAsked = Array.isArray(out.questions) && out.questions.some((q: unknown) => String(q ?? '').trim() !== '');
  // claims_ready: the model's own structured flag saying its sentence tells the customer the request is
  // ready/complete/about to be shared. A missing flag is read as a claim (it cannot be shown false).
  const claimsReady = out.claims_ready !== false;
  out.status = sl.complete ? 'ready' : sl.held ? 'held' : 'needs_info';
  if (sl.complete) {
    const base = out.brief && typeof out.brief === 'object' ? out.brief : briefOf(sl.details);
    out.brief = { ...base, details: { ...(base.details || {}), ...sl.details } };
    out.missing = [];
  } else if (sl.held) {
    out.missing = []; out.questions = []; out.brief = null;
    out.assistant_message = HELD_FOR_SPECS[lang] || HELD_FOR_SPECS.en;
    return sl;
  } else {
    out.missing = sl.missing;
    // An exhausted question is never asked again: the state's next askable question replaces the model's.
    if (sl.exhausted.length || !Array.isArray(out.questions) || !out.questions.length) out.questions = sl.missing.slice(0, 1);
  }
  // The reply must agree with the row (review of #1277). READY: always the state's sentence, which tells
  // the customer to press Send to suppliers - the request goes nowhere until they confirm. NOT READY: the
  // model's sentence stands only when it wrote for needs_info, asked something, and flagged
  // claims_ready=false; anything else ("The request is ready to share with suppliers" beside needs_info,
  // run fe7ba9c4) is replaced by the state's next question. Structured fields only, no word matching.
  if (out.status === 'ready' || modelStatus !== out.status || !modelAsked || claimsReady || sl.exhausted.length) out.assistant_message = replyFromState(out.status, sl.missing[0] || null, lang);
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

// ---- the open key and the hold's reason (stage2 run 321d13ae, 18 Oct 2026) ----------------------
/** The slot state's first askable question and its key, or null (exhausted keys are never asked). */
export function slotAskOf(sl: SlotState): { key: string; text: string } | null {
  const askKeys = sl.missingKeys.filter((k) => !sl.exhausted.includes(k));
  return askKeys.length && sl.missing.length ? { key: askKeys[0], text: sl.missing[0] } : null;
}
/** The key goes with the question only on an EXACT match with the state's question: a question the
 *  model wrote in its own words has no key we can vouch for. */
export function slotKeyFor(ask: { key: string; text: string } | null, question: string): string | null {
  return ask && question === ask.text ? ask.key : null;
}
/** Only our own harness subject (@example.invalid) is told why an intake is held; a customer never is. */
export function heldReasonFor(status: string, email: string, exhausted: string[]): { held_reason: string } | Record<string, never> {
  return status === 'held' && String(email || '').toLowerCase().endsWith('@example.invalid')
    ? { held_reason: 'specs_unanswered: ' + (exhausted.join(',') || 'unknown') } : {};
}
