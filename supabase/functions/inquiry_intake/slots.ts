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
import { orderFields, questionText, parseAnswer, isUnknown, type Lang, type SpecField } from './interview.ts';
import { aiReply } from '../_shared/ai_reply.ts';
import { isOpenRouterDown } from '../_shared/openrouter_down.ts';
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
  en: 'Thank you. A few specifications are still open, and this goes to suppliers once they are settled. Please answer them here; our sales engineer will help with any you are unsure of.',
  ar: 'شكرًا لكم. ما زالت بعض المواصفات غير محددة، وسيُرسل الطلب إلى الموردين بعد تحديدها. يُرجى الإجابة عنها هنا، وسيساعدكم مهندس المبيعات لدينا في أي منها لستم متأكدين منه.',
};

// THE HELD REPLY NAMES WHAT IS STILL OPEN (customer_support, 19 Oct 2026). settleModelTurn clears `missing` on a hold,
// and HELD_FOR_SPECS said only "a few specifications are still open": a real customer was never told WHICH. The reply
// is now written by the model (ruling 1196) with the exhausted questions, in the inquiry language, as its facts.
// HELD_FOR_SPECS (with the open questions listed) goes out as it stands only when OpenRouter is down: no call reached a
// model (founder_instruction 1339). Every draft refused by the reply guards, model up, is NOT that case: '' comes back.
// The request chat is a portal surface, so the reply is the sales engineer's (the_portals_are_the_sales_engineer).
/** The plain questions still open on a held intake, in the customer's language, in checklist order. A field with no
 *  question text is skipped: a raw key ('area') never reaches the model. */
export function heldQuestions(checklist: SpecField[], exhausted: string[], lang: Lang): string[] {
  return orderFields(checklist).filter((o) => exhausted.includes(String(o.f.key)))
    .map((o) => String((lang === 'ar' ? o.f.question_plain_ar || o.f.question_plain_en : o.f.question_plain_en) || o.f.question || '').trim())
    .filter(Boolean);
}
/** The code draft of the held reply: the handover sentence and the open questions listed. Sent as it stands only when
 *  OpenRouter is down (founder_instruction 1339); otherwise it is the draft the model writes from (intakeVoice). */
export function heldDraftOf(checklist: SpecField[], exhausted: string[], lang: Lang): string {
  const open = heldQuestions(checklist, exhausted, lang);
  return `${HELD_FOR_SPECS[lang] || HELD_FOR_SPECS.en}${open.length ? '\n- ' + open.join('\n- ') : ''}`;
}
/** The held reply, written by the model, naming every still-open question. by: 'model' | 'outage_fallback' (OpenRouter
 *  down: the code draft) | 'none' (the model answered but nothing it wrote passed: text '', index.ts asks it again). */
export async function heldReply(deps: ThinkDeps, checklist: SpecField[], exhausted: string[], lang: Lang, message: string, conversation: { role: string; text: string }[], deadline?: number): Promise<IntakeVoice> {
  const open = heldQuestions(checklist, exhausted, lang);
  const r = await aiReply(deps, {
    seat: 'sales_engineer', channel: 'the website request chat', audience: 'customer', lang, message, deadline,
    conversation: conversation.map((t) => ({ role: t.role === 'assistant' ? 'seat' as const : 'customer' as const, text: String(t.text || '') })),
    facts: 'This request is HELD: it goes to no supplier yet. These questions were asked three times and are still unanswered:\n- ' + open.join('\n- ') +
      '\nThe customer can answer them here in this chat; our sales engineer will help settle any they are unsure of.',
    rules: 'Thank them, name EACH still-open question above in plain words and ask them to answer here (the first one is offered below with options to tap), and say our sales engineer will help settle anything they are unsure of before it goes to suppliers. Two to four sentences. Do not ask anything else.',
  }).catch(() => ({ reply: '', attempts: ['threw'] } as { reply: string; attempts: string[]; outage?: boolean }));
  const text = String(r.reply || '').trim();
  if (text) return { text, outage: false, by: 'model' };
  // the code list of open questions only when OpenRouter is down (1339)
  return replyDown(r) ? { text: heldDraftOf(checklist, exhausted, lang), outage: true, by: 'outage_fallback' } : { text: '', outage: false, by: 'none' };
}

// ── THE INTAKE'S WORDS ARE THE MODEL'S (founder_instruction 1339, 27 Oct 2026) ──────────────────────────────────────
// "the engineer and customer support never replies without llm unless the server of open router is down".
// Code decides WHAT is said (the status, the one question, its options); intakeVoice hands that draft to the model as
// facts and the model writes it. The draft is sent as it stands only when no call reached a model (OpenRouter down);
// a model that answered but whose words were all refused leaves the reply '' (the question card and its options still
// show the question; the next turn asks again).
/** problems: why the model's drafts were refused (by 'none'); a turn filed for the re-ask names them (_shared/reask.ts). */
export interface IntakeVoice { text: string; outage: boolean; by: 'model' | 'outage_fallback' | 'none'; problems?: string[] }
/** Whether an aiReply result says OpenRouter was down: its own `outage` flag where aiReply carries one, else read from
 *  its attempts — no attempt produced text and every failure is an outage (openrouter_down.ts). */
export function replyDown(r: { reply?: string | null; outage?: boolean; attempts?: string[] }): boolean {
  if (String(r.reply ?? '').trim()) return false;
  if (typeof r.outage === 'boolean') return r.outage;
  const a = (r.attempts ?? []).filter((x) => !/^salvaged/.test(x));
  if (!a.length || a.some((x) => /:ok\b/.test(x))) return false;
  return a.every((x) => {
    if (/^deadline/.test(x)) return true;
    const m = x.match(/^[\w-]+:failed\s*(.*)$/);
    // 'no answer': the call returned nothing at all (it threw, or the deadline stopped it) — never a model's answer
    return !!m && !/^\[/.test(m[1]) && (m[1].trim() === 'no answer' || isOpenRouterDown(m[1]));
  });
}
/** The request chat's voice class (model_policy voice_draft, ruling 1571): a code-decided sentence in the customer's words. */
export const VOICE_CLASS = 'voice_draft';
export async function intakeVoice(deps: ThinkDeps, o: { draft: string; lang: Lang; message: string; conversation: { role: string; text: string }[];
  next?: { text: string; options?: string[] | null } | null; deadline?: number }): Promise<IntakeVoice> {
  const ask = o.next && String(o.next.text || '').trim()
    ? '\nTHE ONE QUESTION TO ASK NOW (ask exactly this, in plain words; no other question): ' + String(o.next.text).trim()
      + (o.next.options?.length ? '\nThey can tap one of: ' + o.next.options.join(' | ') : '')
    : '\nAsk no question unless the message above asks one.';
  // THE VOICE IS A SIMPLE TASK WITH THE WHOLE CONVERSATION (it_engineer, 10 Nov 2026; rulings 1571 and 1572). It ran on
  // conversation_reply (Sonnet 5.5) with the ~35k-token company brief to reword one sentence code had decided: USD 0.040-0.053
  // a call (ai_cost_log, 4 and 10 Nov). It now runs on voice_draft (model_policy: Luna Pro > Qwen 3.8 Flash) with no brief: the
  // draft already holds the facts, and every draft is still checked against the brief's figures. And it hears EVERY turn: it
  // was the last 12, so "never repeat a question they already answered" could not hold for an answer given at message 2 of 30
  // (1572). fitHistory (chat_history.ts) keeps ~500k tokens; a 100-message intake is ~14k. Prevented by: inquiry_intake/voice_draft.test.ts.
  const r = await aiReply(deps, {
    seat: 'sales_engineer', channel: 'the website request chat', audience: 'customer', lang: o.lang, message: o.message || '(they sent a file or tapped an option)',
    taskClass: VOICE_CLASS, briefInPrompt: false,
    conversation: o.conversation.map((t) => ({ role: t.role === 'assistant' ? 'seat' as const : 'customer' as const, text: String(t.text || '') })),
    facts: 'WHAT TO SAY ON THIS TURN (decided by our systems from the request\'s state; convey it in your own words, change nothing in its meaning, add nothing):\n' + o.draft + ask,
    rules: 'One to three short sentences for the request chat. Never say the request is ready, complete or sent unless the facts above say so. Never repeat a question they already answered.',
    deadline: o.deadline,
  }).catch(() => ({ reply: '', attempts: ['threw'] } as { reply: string; attempts: string[]; outage?: boolean; problems?: string[] }));
  const text = String(r.reply || '').trim();
  if (text) return { text, outage: false, by: 'model' };
  return replyDown(r) ? { text: o.draft, outage: true, by: 'outage_fallback' } : { text: '', outage: false, by: 'none', problems: (r as { problems?: string[] }).problems ?? [] };
}

// ── A HELD INTAKE ASKS ONE SPEC AT A TIME AND READS THE ANSWER BY CODE (27 Oct 2026, sales_engineer) ─────────
// MEASURED on production, founder ledger 580, run 6dd2316c (agent_runs inquiry_intake 27 Oct 07:52-07:54 UTC): a
// ZZ DEMO customer's HVAC drawing intake asked 4, 4 and 3 questions on its first three turns, then answered
// status=held with questions=0 on every turn after (readiness 55..80). settleModelTurn cleared `questions` and
// `missing` on a hold and index.ts left next_question null, so the portal (NewRequest.tsx renders next_question and
// remaining_questions) had nothing to show, create_inquiry answered 428 intake_required, and no inquiry, BOQ PDF or
// supplier was ever reached. A real customer would have been stuck exactly so.
//
// The hold stays: exact specs or nothing goes to a supplier (founder, 14 Sep 2026). What changes is that a held
// intake names the specific spec it is waiting for and asks it, with the checklist's own options to tap, and the
// answer to THAT question is read by code (interview.ts parseAnswer, targeted), because the hold exists precisely
// where the model did not file three answers under the key. A bare "not sure" fills nothing (the key stays missing
// and the sales_engineer handoff opened by index.ts helps settle it); an option the checklist itself offers, such
// as "Not sure - need site survey", is a spec the trade defined and is recorded as the answer.

/** The first still-open spec of a held intake, in checklist order, as the question to ask now. */
export function heldAsk(checklist: SpecField[], exhausted: string[], lang: Lang): { key: string; text: string; options: string[] | null } | null {
  const o = orderFields(checklist).find((x) => exhausted.includes(String(x.f.key)) && questionText(x.f, lang));
  if (!o) return null;
  const opts = Array.isArray(o.f.options) ? o.f.options.filter((x) => typeof x === 'string' && x) : [];
  return { key: String(o.f.key), text: questionText(o.f, lang), options: opts.length ? opts : null };
}

// A DEFERRAL IS NOT A SPEC (independent review of #1641, 27 Oct 2026). The hold exists because the customer answered
// "As per the attached drawings." three times (run 6dd2316c). parseAnswer, targeted, takes a short free-text reply as
// the answer to a text field and to a tap question that names none of its options, so the fourth "as per the drawings"
// was stored as system_type and the intake went ready with no spec. A reply that only points elsewhere, defers, or says
// nothing fills nothing here: the spec stays held and the sales_engineer handoff settles it.
const DEFERRAL = new RegExp([
  String.raw`^(as|according to|refer to|see|check|per|same as|like)\b.*\b(drawing|drawings|plan|plans|attach\w*|file|files|boq|document|pdf|photo|picture|image|before|above|previous)\b`,
  String.raw`^(attached|in the (drawing|attachment|file)s?|on the (drawing|plan)s?)\b`,
  String.raw`^(ok|okay|k|yes|yeah|yep|no|nope|sure|fine|any|anything|whatever|either|both|all|none|na|n/?a|tbd|tbc|later|soon|asap|same|normal|standard|usual|default|good|best|cheap|cheapest|\?+|\.+|-+)[\s.!?]*$`,
  String.raw`(حسب|كما في|راجع|انظر|شوف)\s*(ال)?(مخطط|مخططات|رسم|رسومات|مرفق|المرفق|الملف|الصور)`,
  String.raw`^(مرفق|نعم|لا|اوكي|أوكي|تمام|ماشي|أي شي|اي شي|أي شيء|اي شيء|عادي|بعدين|لاحقا|لاحقاً)[\s.!؟]*$`,
].join('|'), 'i');
export const isDeferral = (text: string) => DEFERRAL.test(String(text || '').trim());

/** The customer's answer to the spec a hold asked, read by code, or null when it did not answer it. */
export function readHeldAnswer(checklist: SpecField[], askedKey: string | null | undefined, text: string): string | null {
  if (!askedKey || !String(text || '').trim()) return null;
  const f = checklist.find((x) => x && String(x.key) === String(askedKey));
  if (!f) return null;
  const v = parseAnswer(f, text, true);
  if (!v) return null;
  const listed = Array.isArray(f.options) && f.options.includes(v);
  if (listed) return v;   // an option the trade itself defines (a bare yes/no only reaches here as a listed Yes/No option)
  // not listed: a not-sure of any wording, or a reply that only defers, is no spec
  if (/^not sure$/i.test(v.trim()) || isUnknown(text) || isDeferral(text)) return null;
  return v;
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
    // A HELD INTAKE STILL ASKS (27 Oct 2026, ledger 580): the open questions travel with the hold. This branch used
    // to clear both lists, so every held turn answered questions=0, missing=[] and no next_question (see heldAsk).
    const open = heldQuestions(checklist, sl.exhausted, lang);
    out.missing = open; out.questions = open; out.brief = null;
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
// reply: what the portal was shown for this turn beyond its text, so a retry of a turn that already landed is answered
// from the row (turn_clock.ts storedReply) instead of reading the same words as the answer to the next question.
export type TurnSlots = { status: string; details: Record<string, unknown>; req_answers: Answers; missing: string[]; missing_keys?: string[];
  reply?: { next_question: unknown; remaining_questions: string[]; readiness: { filled: number; required: number } | null } };
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
