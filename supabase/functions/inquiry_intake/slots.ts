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
import { orderFields, questionText, parseAnswer, isUnknown, answersAnotherKind, type Lang, type SpecField, type UniversalKind } from './interview.ts';
import { aiReply } from '../_shared/ai_reply.ts';
import { surfaceEffort } from '../_shared/effort_policy.ts';
import { isOpenRouterDown } from '../_shared/openrouter_down.ts';
import type { ThinkDeps } from '../_shared/think.ts';
import { requirementQuestions, isValidAnswer, NO_PREFERENCE, type Answers, type Ans } from '../_shared/intake_requirements.ts';
import type { Dialect } from '../_shared/inquiry_state.ts';

const asText = (v: unknown) => (typeof v === 'object' ? JSON.stringify(v) : String(v ?? '')).trim();
const filled = (v: unknown) => v !== undefined && v !== null && !['', '{}', '[]', 'null'].includes(asText(v));

/** recordedElsewhere: this message answered one of the four questions or a "does not know" (it told us something);
 *  lastText: the customer's last message alone (a CHANGED value counts as told only when its cited words are in it);
 *  stall: the stamped history of the open specs (stallOf), for the backstop below. */
export type SlotOpts = { recordedElsewhere?: boolean; lastText?: string | null; stall?: { streak: number; lastOpen: string[] | null } };
export type SlotState = { details: Record<string, string>; missingKeys: string[]; missing: string[]; complete: boolean; exhausted: string[]; held: boolean;
  /** Values the model filed under a spec they do not answer (finding b2): not recorded there, the spec stays open. */
  misfiled?: { key: string; reason: 'answers_another_kind' | 'no_customer_words'; kind?: UniversalKind }[];
  /** The keys this turn recorded that no earlier turn held, and the customer's words each came from (journey A, 15 Nov). */
  recorded?: string[]; evidence?: Record<string, string>;
  /** The open keys of `missing`, in the order they are asked (askableKeys[0] is the question for missing[0]). */
  askableKeys?: string[];
  /** Every askable spec was already asked once and is waiting for its answer (askNext). */
  waiting?: boolean;
  /** The backstop held it: no required spec moved for STALL_TURNS turns in a row (stallOf). */
  stalled?: boolean };

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
// COUNTED IN ASKS, NOT IN OPEN TURNS (15 Nov 2026, journey A, tag 8288bec3). openTurnsByKey counted every turn a key was OPEN, so a
// spec the chat had not yet asked was "asked three times" after three turns of the customer describing the job in his own order:
// the villa AC request was HELD at its fourth turn, and from then on every reply was the hold's (the same closing sentence, a
// second model call, the hold's buttons under another question). A turn now stamps the keys it ASKED (asked_keys); an older turn
// without them counts its open keys, as before.
export const MAX_OPEN_TURNS = 3;
// NO REQUEST IS STUCK, AND NO CUSTOMER IS ASKED MORE THAN EIGHT QUESTIONS BEFORE THE HOLD (independent review of 15 Nov 2026, item 2).
// Counting asks per spec, with each question asked once before any is repeated, a customer who answers nothing is asked every open
// spec three times (ten open hvac specs: 30 questions); and a model that names an optional spec as the one it asked while asking
// something else accrues no ask on any required spec at all (45 turns at needs_info, never held). The backstop: when no REQUIRED
// spec has moved (been answered, recorded as not needed or not known) on STALL_TURNS turns in a row, every open spec goes to the
// hold, so the sales engineer settles them with the customer. 8: the first message is read, and eight questions in a row that move
// nothing are the most a real customer is asked before the hold (the ninth reply is the hold's).
export const STALL_TURNS = 8;
/** The stamped history of the open required specs: how many replies in a row moved none of them, and the last open set. */
export function stallOf(turns: any[]): { streak: number; lastOpen: string[] | null } {
  let streak = 0, lastOpen: string[] | null = null;
  for (const t of turns || []) {
    const sl = t && t.role === 'assistant' && t.slots ? t.slots : null;
    if (!sl || !Array.isArray(sl.missing_keys)) continue;
    const now = sl.missing_keys.map(String);
    const moved = lastOpen === null || lastOpen.some((k) => !now.includes(k));
    streak = moved ? 0 : streak + 1;
    lastOpen = now;
  }
  return { streak, lastOpen };
}
/** HELD_FOR_SPECS without the sales-engineer offer, once a reply has made it (journey A, 15 Nov 2026: said on every turn). */
export const HELD_NO_OFFER: Record<Lang, string> = {
  en: 'Thank you. A few specifications are still open, and this goes to suppliers once they are settled. Please answer them here.',
  ar: 'شكرًا لكم. ما زالت بعض المواصفات غير محددة، وسيُرسل الطلب إلى الموردين بعد تحديدها. يُرجى الإجابة عنها هنا.',
};
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
export function heldDraftOf(checklist: SpecField[], exhausted: string[], lang: Lang, offerSettle = true): string {
  const open = heldQuestions(checklist, exhausted, lang);
  return `${offerSettle ? (HELD_FOR_SPECS[lang] || HELD_FOR_SPECS.en) : (HELD_NO_OFFER[lang] || HELD_NO_OFFER.en)}${open.length ? '\n- ' + open.join('\n- ') : ''}`;
}
/** The held reply, written by the model, naming every still-open question. by: 'model' | 'outage_fallback' (OpenRouter
 *  down: the code draft) | 'none' (the model answered but nothing it wrote passed: text '', index.ts asks it again). */
// THE HELD REPLY ASKS THE ONE QUESTION ITS BUTTONS ANSWER, AND OFFERS THE SALES ENGINEER ONCE (15 Nov 2026, journey A, tag 8288bec3).
// Live, the hold's reply named every open question in the order the model chose while the buttons under it were heldAsk's (the
// system type under a question about room sizes, "New installation | Replacement" under one about pipes), and its rule had the
// model close EVERY held turn with "our sales engineer will help settle anything you're unsure of before it goes to suppliers".
// It ran as a conversation_reply with the ~35k-token company brief (ai_cost_log: ~70-74k prompt tokens, 6-13 s, after the
// interview call). Now: `ask` is the one question asked (heldAsk's, the one whose options are shown), the other open questions
// are named as still open, not asked; the sales-engineer sentence is in the facts only when `offerSettle` (no earlier reply
// offered it); and it is the voice_draft task with no brief (intakeVoice's class: the facts are all it needs).
export async function heldReply(deps: ThinkDeps, checklist: SpecField[], exhausted: string[], lang: Lang, message: string, conversation: { role: string; text: string }[], deadline?: number,
  o: { ask?: { text: string; options?: string[] | null } | null; offerSettle?: boolean; answer?: string | null } = {}): Promise<IntakeVoice> {
  const open = heldQuestions(checklist, exhausted, lang);
  const offer = o.offerSettle !== false;
  const ask = o.ask && String(o.ask.text || '').trim() ? o.ask : open[0] ? { text: open[0], options: null } : null;
  const others = open.filter((q) => q !== ask?.text);
  const r = await aiReply(deps, {
    seat: 'sales_engineer', channel: 'the website request chat', audience: 'customer', lang, message, deadline,
    taskClass: VOICE_CLASS, briefInPrompt: false,
    effort: surfaceEffort('inquiry_intake.held_reply'),   // inside the chat turn: the effort that fits it (effort_policy.ts clock, ledger 1642)
    conversation: conversation.map((t) => ({ role: t.role === 'assistant' ? 'seat' as const : 'customer' as const, text: String(t.text || '') })),
    // THEIR QUESTION IS STILL ANSWERED ON A HELD TURN (review of 15 Nov 2026, item 5): the interview's answer_to_question (fees,
    // anonymity, refunds...) was dropped when the hold wrote the reply; it goes first, in the facts.
    facts: (String(o.answer || '').trim() ? 'They asked us something; answer it first, in these words: ' + String(o.answer).trim() + '\n' : '')
      + 'This request is HELD: it goes to no supplier until these are settled.'
      + (ask ? '\nTHE ONE QUESTION TO ASK NOW (ask exactly this, in plain words): ' + String(ask.text).trim() + (ask.options?.length ? '\nThey can tap one of: ' + ask.options.join(' | ') : '') : '')
      + (others.length ? '\nAlso still open (name them as still open; do not ask them now):\n- ' + others.join('\n- ') : '')
      + (offer ? '\nOur sales engineer will help settle anything they are unsure of before it goes to suppliers (say this once).' : ''),
    rules: (String(o.answer || '').trim() ? 'Answer their question first, as given above. Then thank' : 'Thank') + ' them, ask THE ONE QUESTION above and no other' + (others.length ? ', and name the other open points as still open' : '')
      + (offer ? ', and say once that our sales engineer will help settle anything they are unsure of' : '; do not mention the sales engineer again')
      + '. Two to three short sentences. Never repeat a question they already answered.',
  }).catch(() => ({ reply: '', attempts: ['threw'] } as { reply: string; attempts: string[]; outage?: boolean }));
  const text = String(r.reply || '').trim();
  if (text) return { text, outage: false, by: 'model' };
  // the code list of open questions only when OpenRouter is down (1339)
  return replyDown(r) ? { text: heldDraftOf(checklist, exhausted, lang, offer), outage: true, by: 'outage_fallback' } : { text: '', outage: false, by: 'none' };
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
// THE WHOLE CONVERSATION (10 Nov 2026, founder ledger 1572: "nothing said in message 2 may be forgotten by message 30+").
// This sent only the last twelve turns: after turn 14 the reply writer could not see turn 2 and could repeat a resolved
// question or contradict an early preference. aiReply hands every turn to the model as real messages, cached by the
// gateway (chat_history.fitHistory: whole up to ~500k tokens, and past that every customer turn verbatim), so nothing is
// cut here; `state` is the request's state as text (_shared/inquiry_state.ts stateSummary) and `rule` the cap stage's.
export async function intakeVoice(deps: ThinkDeps, o: { draft: string; lang: Lang; message: string; conversation: { role: string; text: string }[];
  next?: { text: string; options?: string[] | null } | null; deadline?: number; state?: string; rule?: string; dialect?: Dialect | null }): Promise<IntakeVoice> {
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
    facts: 'WHAT TO SAY ON THIS TURN (decided by our systems from the request\'s state; convey it in your own words, change nothing in its meaning, add nothing):\n' + o.draft + ask
      + (o.state ? '\n\n' + o.state : ''),
    rules: 'One to three short sentences for the request chat. Never say the request is ready, complete or sent unless the facts above say so. Never repeat a question they already answered.'
      + (o.rule ? ' ' + o.rule : ''),
    ...(o.dialect ? { dialect: o.dialect } : {}),
    deadline: o.deadline,
    effort: surfaceEffort('inquiry_intake.voice'),   // inside the chat turn: the effort that fits it (effort_policy.ts clock, ledger 1642)
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

/** A TAPPED option of the spec a hold asked: the reply is exactly one of that spec's options (a fixed payload), or null.
 *  WITH A MODEL READING, THIS IS ALL CODE READS (15 Nov 2026, journey A; rulings 1663/1664/1666: the model reads first). The
 *  hold read the reply to its question by code (readHeldAnswer), and a reply about something else became the answer: "The power
 *  points and isolators are already there; you only connect to them." was stored as the AC system type, "Yes, remove the old
 *  split units and take them away." as new-or-replacement. Words the customer typed are the model's to read; readHeldAnswer stays
 *  for a turn with no model reading. */
export function tappedHeldAnswer(checklist: SpecField[], askedKey: string | null | undefined, text: string): string | null {
  const f = askedKey ? checklist.find((x) => x && String(x.key) === String(askedKey)) : null;
  const t = String(text || '').replace(/\s+/g, ' ').trim().toLowerCase();
  if (!f || !t || !Array.isArray(f.options)) return null;
  return f.options.find((o) => typeof o === 'string' && o.trim().toLowerCase() === t) ?? null;
}

/** The spec the last reply asked (its stamped next_question key), so "I don't know" is read as the answer to THAT spec. */
export function lastAskedKey(turns: any[]): string | null {
  for (let i = (turns || []).length - 1; i >= 0; i--) {
    const t = turns[i];
    if (t && t.role === 'assistant') { const k = t.slots?.reply?.next_question?.key; return k ? String(k) : null; }
  }
  return null;
}
/** The held draft when every spec still open is one the customer said they do not know: nothing is asked again; the
 *  sales engineer settles them with the customer. Voiced by the model (intakeVoice); sent as it stands only on an outage. */
export function unknownHeldDraft(checklist: SpecField[], unknownKeys: string[], lang: Lang): string {
  const open = heldQuestions(checklist, unknownKeys, lang);
  return lang === 'ar'
    ? 'شكرًا لكم. لا بأس في عدم معرفة بعض التفاصيل، وسيتواصل معكم مهندس المبيعات لدينا لتحديدها قبل إرسال الطلب إلى الموردين، دون حاجة إلى الإجابة عنها هنا.' + (open.length ? '\n- ' + open.join('\n- ') : '')
    : 'Thank you. It is fine not to know some of the details; our sales engineer will settle them with you before the request goes to suppliers, so there is nothing more to answer about them here.' + (open.length ? '\n- ' + open.join('\n- ') : '');
}

/** How many earlier replies ASKED each spec (stampTurn's asked_keys); a turn stamped before asked_keys counts its open keys. */
export function askedTurnsByKey(turns: any[]): Record<string, number> {
  const n: Record<string, number> = {};
  for (const t of turns || []) {
    const sl = t && t.role === 'assistant' && t.slots ? t.slots : null;
    const ks = !sl ? [] : Array.isArray(sl.asked_keys) ? sl.asked_keys : Array.isArray(sl.missing_keys) ? sl.missing_keys : [];
    for (const k of ks) n[String(k)] = (n[String(k)] || 0) + 1;
  }
  return n;
}
/** The former name: what it counts is the asks (above). */
export const openTurnsByKey = askedTurnsByKey;

/** Merge what the model extracted this turn into what earlier turns captured, then derive missing. */
// A SPEC THE CUSTOMER SAID THEY DO NOT KNOW IS NEVER ASKED AGAIN (10 Nov 2026, founder ledger 1572; _shared/inquiry_state.ts).
// It counts as exhausted at once, exactly as a key asked three times does: nothing is written under it (exact specs or the
// quote is held), the other keys are still asked, and when only such keys are left the intake is held for the sales
// engineer (the spec.not_sure handoff). `unknownKeys` comes from the conversation's state: what the customer said they do
// not know, on this turn or any earlier one, on this surface or the portal chat it was carried from.
// AN ANSWER COUNTS ONLY UNDER THE SPEC IT ANSWERS (evidence run of 10 Nov 2026, ledger 1604, finding b2). The model filed
// "We need it finished by 15 December 2026." under spec_mep_scope and "At least 2 years warranty ..." under
// spec_authority_approvals_and_responsibility, and both counted. A value the model adds THIS turn under a checklist key
// is now recorded only when:
//   * it is not ONLY a statement of another universal kind (a date, money, a warranty period, an emirate; interview.ts
//     answersAnotherKind) — such a value answers that kind, and is filed under the checklist's own field for it when
//     there is one; the asked spec stays open;
//   * when the model cites the customer's words (its structured "spec_evidence": {key: quote}), the quote is the
//     customer's own words (verbatim in what they wrote) and passes the same guard. A key the model filled without a
//     quote, on a turn where it cited others, is not recorded.
// "Customer does not know: supplier to advise" is an explicit answer and always counts. What earlier turns recorded is
// never re-judged here.
const SUPPLIER_TO_ADVISE_TEXT = 'Customer does not know: supplier to advise';
// ── A SPEC THE JOB DOES NOT NEED IS RECORDED AS NOT NEEDED, NEVER ASKED (15 Nov 2026, journey A) ─────────────────────────
// Live, room sizes were asked six times of a customer who had given every unit's capacity (two of 1.5 TR, two of 2.0 TR, three
// of 3 TR), and a ducting preference of a service of existing ducted units. Whether a spec is needed is the TRADE'S DATA, on
// the spec itself (interview.ts SpecField.not_needed_when; the pack's guide row; category_specs): code checks only that a
// named spec holds an answer, and the model judges the condition in words, citing the customer (its "not_needed"). The spec is
// then recorded as not needed, so the slots, the blocking gate and dispatch's required check all read it as settled and a
// supplier reads why. same_as: two specs that ask the same thing (a slug's field and the placed trade's) are asked once.
export const NOT_NEEDED_PREFIX = 'Not needed for this job: ';
export const notNeededValue = (text: string) => NOT_NEEDED_PREFIX + String(text || '').trim();
const squash = (s: string) => String(s || '').toLowerCase().replace(/[\s\u00a0]+/g, ' ').replace(/[“”"'’‘]/g, '').trim();
const UNIVERSAL_FIELD_KEY: Record<UniversalKind, string[]> = { required_by: ['required_by', 'timeline'], budget: ['budget'], warranty: ['warranty'], location: ['location', 'emirate'] };
export function reconcileSlots(checklist: SpecField[], prevDetails: Record<string, unknown> | null | undefined, modelOut: any, lang: Lang, openTurns: Record<string, number> = {}, unknownKeys: Iterable<string> = [], customerText?: string | null, o: SlotOpts = {}): SlotState {
  const unknown = new Set([...unknownKeys].map(String));
  const details: Record<string, string> = {};
  for (const [k, v] of Object.entries(prevDetails || {})) if (filled(v)) details[k] = asText(v);
  const b = modelOut && typeof modelOut.brief === 'object' && modelOut.brief ? modelOut.brief : {};
  const det = b.details && typeof b.details === 'object' ? b.details : {};
  const keys = new Set(checklist.map((f) => f && f.key).filter(Boolean) as string[]);
  const evidence = modelOut && modelOut.spec_evidence && typeof modelOut.spec_evidence === 'object' && !Array.isArray(modelOut.spec_evidence) ? modelOut.spec_evidence as Record<string, unknown> : null;
  const said = customerText != null ? squash(customerText) : null;
  const misfiled: NonNullable<SlotState['misfiled']> = [];
  const evidenceNow: Record<string, string> = {};
  const put = (k: string, v: unknown) => {
    const text = asText(v);
    const f = checklist.find((x) => x && String(x.key) === k);
    if (!f || text === SUPPLIER_TO_ADVISE_TEXT || details[k] === text) { details[k] = text; return; }
    const ev = evidence ? asText(evidence[k] ?? '') : '';
    const kind = answersAnotherKind(f, text) || (ev ? answersAnotherKind(f, ev) : null);
    if (kind) {
      misfiled.push({ key: k, reason: 'answers_another_kind', kind });
      const home = UNIVERSAL_FIELD_KEY[kind].find((h) => keys.has(h) && !filled(details[h]));
      if (home) details[home] = text;
      return;
    }
    if (evidence && said !== null && (!ev || !said.includes(squash(ev)))) { misfiled.push({ key: k, reason: 'no_customer_words' }); return; }
    details[k] = text;
  };
  for (const [k, v] of Object.entries(det)) if (filled(v)) put(k, v);
  // A checklist key the model put at the top of the brief (brief.location) instead of under details.
  for (const k of keys) if (!(k in details) && filled(b[k])) put(k, b[k]);
  // NOT NEEDED (above): a named spec answered, or the model's judgement of the condition with the customer's words.
  const declared = modelOut && modelOut.not_needed && typeof modelOut.not_needed === 'object' && !Array.isArray(modelOut.not_needed) ? modelOut.not_needed as Record<string, unknown> : {};
  const sameAs = () => { for (const f of checklist) { const s = f && f.same_as ? String(f.same_as) : ''; if (f?.key && s && keys.has(s) && !(String(f.key) in details) && filled(details[s])) details[String(f.key)] = details[s]; } };
  sameAs();
  for (const f of checklist) {
    const k = f && f.key ? String(f.key) : '', nn = f && f.not_needed_when;
    if (!k || !nn || !String(nn.text || '').trim() || k in details) continue;
    // A REAL ANSWER ONLY (review of 15 Nov 2026, item 1): "does not know" (supplier to advise), a spec itself recorded as not needed,
    // or a key the customer said they do not know never makes another spec unnecessary: "I don't know the capacity" asks the room.
    const real = (a: string) => filled(details[a]) && details[a] !== SUPPLIER_TO_ADVISE_TEXT && !String(details[a]).startsWith(NOT_NEEDED_PREFIX) && !unknown.has(a);
    const byAnswer = (nn.answered ?? []).some((a) => real(String(a)));
    const words = asText(declared[k] ?? '');
    const byModel = !!words && (said === null || said.includes(squash(words)));
    if (words && !byModel) misfiled.push({ key: k, reason: 'no_customer_words' });
    if (byAnswer || byModel) { details[k] = notNeededValue(nn.text); if (byModel) evidenceNow[k] = words; }
  }
  sameAs();
  const required = orderFields(checklist).filter((o) => o.f.required && o.f.key);
  const open = required.filter((o) => !(String(o.f.key) in details));
  // A spec that is the same question as another open spec is asked as that one, never on its own.
  const askedAs = (f: SpecField) => !!(f.same_as && keys.has(String(f.same_as)) && !(String(f.same_as) in details));
  // The backstop (STALL_TURNS): this message moved no required spec either, after STALL_TURNS - 1 replies that moved none.
  const openNow = open.map((o) => String(o.f.key));
  const st = o.stall;
  const stalled = !!st && st.lastOpen !== null && !st.lastOpen.some((k) => !openNow.includes(k)) && st.streak + 1 >= STALL_TURNS;
  const exhausted = open.filter((x) => (stalled && !askedAs(x.f)) || (openTurns[String(x.f.key)] || 0) >= MAX_OPEN_TURNS || unknown.has(String(x.f.key))).map((x) => String(x.f.key));
  // THE NEXT QUESTION IS ONE NOT YET ASKED (15 Nov 2026, journey A): a spec the customer has not been asked yet comes before one
  // already waiting for its answer; the checklist's order decides between equals.
  const askable = open.filter((o) => !exhausted.includes(String(o.f.key)) && !askedAs(o.f))
    .map((o, i) => ({ o, i, n: openTurns[String(o.f.key)] || 0 })).sort((a, z) => a.n - z.n || a.i - z.i).map((x) => x.o);
  const prevKeys = new Set(Object.keys(prevDetails || {}).filter((k) => filled((prevDetails as Record<string, unknown>)[k])));
  // checklist keys only: a key outside the checklist the model adds is no answer, and must never silence a waiting question.
  // A CHANGED value counts too (review of 15 Nov 2026, item 3: "actually supply only" was followed by the waiting pipe-length question),
  // but only when the customer's words it cites are in THIS message: a model rewording an old answer is not the customer telling us.
  const last = o.lastText ? squash(o.lastText) : null;
  const changedNow = (k: string) => prevKeys.has(k) && asText((prevDetails as Record<string, unknown>)[k]) !== details[k] && !!last && !!evidence && filled(evidence[k]) && last.includes(squash(asText(evidence[k])));
  const recorded = Object.keys(details).filter((k) => keys.has(k) && (!prevKeys.has(k) || changedNow(k)));
  for (const k of recorded) if (!evidenceNow[k] && evidence && filled(evidence[k])) evidenceNow[k] = asText(evidence[k]);
  const waiting = askable.length > 0 && askable.every((x) => (openTurns[String(x.f.key)] || 0) > 0);
  return {
    details, exhausted, ...(misfiled.length ? { misfiled } : {}),
    missingKeys: open.map((o) => String(o.f.key)),
    missing: askable.map((o) => questionText(o.f, lang)),
    askableKeys: askable.map((o) => String(o.f.key)),
    complete: open.length === 0,
    held: open.length > 0 && askable.length === 0,
    recorded, evidence: evidenceNow, ...(stalled ? { stalled } : {}),
    // nothing new to ask: every open spec is waiting, and this message brought an answer (here or to the four questions)
    waiting: waiting && (recorded.length > 0 || !!o.recordedElsewhere),
  };
}

/** OPEN SPECS NOW, for the interview prompt (rule 18): each required spec the request does not hold yet, in checklist order, how
 *  often it was asked, and its NOT NEEDED condition. '' when none is open. Our checklist's words only; nothing the customer said. */
export function openSpecsBlock(checklist: SpecField[], held: Record<string, unknown>, asked: Record<string, number>, lang: Lang): string {
  const open = orderFields(checklist).filter((o) => o.f.required && o.f.key && !filled(held?.[String(o.f.key)]));
  if (!open.length) return '';
  return 'OPEN SPECS NOW (required and not yet answered; read the customer\'s last message against ALL of them):\n' + open.map((o) => {
    const k = String(o.f.key), n = asked[k] || 0;
    return `- [${k}] ${questionText(o.f, lang)} (${n ? `asked ${n} time${n > 1 ? 's' : ''}` : 'not asked yet'})`
      + (o.f.not_needed_when?.text ? ` | NOT NEEDED when: ${o.f.not_needed_when.text}` : '') + (o.f.same_as ? ` | same question as [${o.f.same_as}]` : '');
  }).join('\n');
}

/** The reply when the status the code settled on is not the one the model wrote its sentence for. */
export function replyFromState(status: string, firstMissingQuestion: string | null, lang: Lang, askNothing = false): string {
  if (status === 'ready') {
    return lang === 'ar'
      ? 'شكرًا لك، اكتمل كل ما يحتاجه المورّدون. راجع الملخص أدناه، ثم اضغط «أرسل إلى الموردين».'
      : 'Thank you — that is everything suppliers need. Check the summary below and press Send to suppliers.';
  }
  const ack = lang === 'ar' ? 'شكرًا، دوّنت ذلك. ' : 'Thanks, noted. ';
  // nothing new to ask (SlotState.waiting): the message is acknowledged and no question goes with it
  if (askNothing && !firstMissingQuestion) return ack.trim();
  return ack + (firstMissingQuestion || (lang === 'ar' ? 'هل يمكنك إخبارنا بالمزيد عن العمل المطلوب؟' : 'Could you tell me a little more about the job?'));
}

/**
 * Apply the slots to one parsed model turn, in place: details accumulate, status and missing are the
 * row's, and the reply is rebuilt whenever the status differs from the one the model wrote it for.
 * `briefOf` builds a brief from the slots when the model sent none (index.ts passes buildBrief).
 */
export function settleModelTurn(checklist: SpecField[], prevDetails: Record<string, unknown> | null | undefined, out: any, lang: Lang, briefOf: (details: Record<string, string>) => any, openTurns: Record<string, number> = {}, unknownKeys: Iterable<string> = [], customerText?: string | null, o: SlotOpts = {}): SlotState {
  const sl = reconcileSlots(checklist, prevDetails, out, lang, openTurns, unknownKeys, customerText, o);
  const modelStatus = out.status;
  const modelAsked = Array.isArray(out.questions) && out.questions.some((q: unknown) => String(q ?? '').trim() !== '');
  // claims_ready: the model's own structured flag saying its sentence tells the customer the request is
  // ready/complete/about to be shared. A missing flag is read as a claim (it cannot be shown false).
  const claimsReady = out.claims_ready !== false;
  out.status = sl.complete ? 'ready' : sl.held ? 'held' : 'needs_info';
  // A value not recorded (misfiled) leaves the model's brief too: the brief carries only what the slots hold.
  if (out.brief && typeof out.brief === 'object' && out.brief.details && typeof out.brief.details === 'object') for (const m of sl.misfiled ?? []) delete out.brief.details[m.key];
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
    // NOTHING IS ASKED TWICE IN A ROW OF ANSWERS (15 Nov 2026, journey A): when every open spec has already been asked and this
    // message brought an answer to something (sl.waiting), the reply takes what was said and asks nothing; the open specs stay
    // in remaining_questions, and a message that answers nothing is when a waiting question is asked again.
    if (sl.exhausted.length || !Array.isArray(out.questions) || !out.questions.length) out.questions = sl.waiting ? [] : sl.missing.slice(0, 1);
  }
  // The reply must agree with the row (review of #1277). READY: always the state's sentence, which tells
  // the customer to press Send to suppliers - the request goes nowhere until they confirm. NOT READY: the
  // model's sentence stands only when it wrote for needs_info, asked something, and flagged
  // claims_ready=false; anything else ("The request is ready to share with suppliers" beside needs_info,
  // run fe7ba9c4) is replaced by the state's next question. Structured fields only, no word matching.
  if (out.status === 'ready' || modelStatus !== out.status || !modelAsked || claimsReady || sl.exhausted.length) {
    const ask = out.status === 'needs_info' && Array.isArray(out.questions) && !out.questions.length ? null : sl.missing[0] || null;
    out.assistant_message = replyFromState(out.status, ask, lang, out.status === 'needs_info' && !ask);
  }
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
  // a component the job may not have (its not_needed_when) offers "not_needed", which the model returns when the condition holds
  const mats = qs.filter((q) => q.kind === 'material').map((q) => `"${q.key}": one of ${JSON.stringify(q.options.filter((o) => o.v !== 'not_needed').map((o) => o.v))}, or "not_sure" when the customer is unsure or asks for the standard, or {"other": "<their words>"}`
    + (q.not_needed_when ? `, or "not_needed" when ${q.not_needed_when} (then it is never asked)` : ''));
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

/**
 * The model's reading merged into what is recorded (12 Nov 2026, independent review of #1979; LLM-first audit A7). A key
 * not yet recorded takes the model's value. A RECORDED key takes it only when the model names it in `changed` (its own
 * "changed_answers": the customer's last message changes it) or it is the question this message answers (`askedKey`):
 * a slip on another key, or a date re-anchored to today, never rewrites a confirmed answer. Code reads no words here.
 */
export function mergeRequirements(recorded: Answers, fromModel: Answers, changed: unknown, askedKey: string | null): Answers {
  const named = new Set(Array.isArray(changed) ? changed.map((k) => String(k)) : []);
  const out: Answers = { ...recorded };
  for (const [k, a] of Object.entries(fromModel)) if (!recorded[k] || named.has(k) || k === askedKey) out[k] = a;
  return out;
}

/** The answers already recorded, as the model is shown them in the prompt (one line, our stored values). */
export function recordedRequirements(category: string | null, recorded: unknown): string {
  if (!recorded || typeof recorded !== 'object') return 'RECORDED: none yet.';
  const r = recorded as Answers;
  const parts = requirementQuestions(String(category || '')).filter((q) => r[q.key]).map((q) => {
    const a = r[q.key];
    const v = q.kind === 'warranty' && a.v === 'yes' ? `{"months": ${a.min_months}}` : q.kind === 'required_by' && a.v === 'date' ? `{"date": "${a.date}"}`
      : q.kind === 'material' && a.v === 'other' ? `{"other": ${JSON.stringify(String(a.note || ''))}}` : JSON.stringify(a.v);
    return `"${q.key}": ${v}`;
  });
  return parts.length ? 'RECORDED (what the customer already answered): ' + parts.join('; ') + '.' : 'RECORDED: none yet.';
}

/** The model's answer to a question the customer asked back, bounded: at most 400 characters, cut at a sentence or word. */
export function answerToQuestion(v: unknown): string {
  const t = typeof v === 'string' ? v.replace(/\s+/g, ' ').trim() : '';
  if (t.length <= 400) return t;
  const cut = t.slice(0, 400);
  const end = Math.max(cut.lastIndexOf('. '), cut.lastIndexOf('\u061F '), cut.lastIndexOf('? '), cut.lastIndexOf('! '));
  return end > 120 ? cut.slice(0, end + 1) : cut.slice(0, Math.max(cut.lastIndexOf(' '), 1)).trim() + '…';
}

// ── WHAT WAS RECORDED WHEN (7 Oct 2026) ──────────────────────────────────────────────────────────
// The run's transcripts showed what the assistant SAID each turn and only the final row, so nobody
// could see that turn 1's slots were never stored. Each assistant turn now carries the state saved
// with it.
// reply: what the portal was shown for this turn beyond its text, so a retry of a turn that already landed is answered
// from the row (turn_clock.ts storedReply) instead of reading the same words as the answer to the next question.
export type TurnSlots = { status: string; details: Record<string, unknown>; req_answers: Answers; missing: string[]; missing_keys?: string[];
  /** The specs this reply asked (askedTurnsByKey counts them); what it recorded and the customer's words each came from. */
  asked_keys?: string[]; recorded?: string[]; evidence?: Record<string, string>;
  reply?: { next_question: unknown; remaining_questions: string[]; readiness: { filled: number; required: number } | null } };
export function stampTurn(turns: any[], snap: TurnSlots): void {
  for (let i = turns.length - 1; i >= 0; i--) {
    if (turns[i] && turns[i].role === 'assistant') { turns[i].slots = { ...snap, at: new Date().toISOString() }; return; }
  }
}

// ---- the open key and the hold's reason (stage2 run 321d13ae, 18 Oct 2026) ----------------------
/** The slot state's first askable question and its key, or null (exhausted keys are never asked). */
export function slotAskOf(sl: SlotState): { key: string; text: string } | null {
  const askKeys = sl.askableKeys ?? sl.missingKeys.filter((k) => !sl.exhausted.includes(k));
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
