// WHAT THE PORTAL CONVERSATION ALREADY HOLDS, AND THE LINES NOBODY ASKED FOR (customer_support owns the conversation,
// sales_engineer answers in it; ledger 1200, 27 Oct 2026). The pure half of the portal turn's conversation rules: no
// network, tested in portal_conversation.test.ts.
//
// MEASURED (adaptive conversation bank, scripts/e2e/adaptive_conversation_bank.mjs, 10 scenarios on the portal seat,
// runs 98aa692f / 4d74ce2d / ab519dba / 4f59f1b9, judged by a Claude session): 0 of 10 reached 95 %, mean 77 %, and
// the two findings in almost every conversation were
//   1. RE-ASKS. "Does the apartment use its own split AC or central/district cooling?" three times; "What clear door
//      width?" twice; "Is this a villa or an apartment?" after "renovate my villa's kitchen". A prompt rule saying
//      "never ask again" was already in aiSystem AND in the intake rule, and the model still did it.
//   2. LINES NOBODY ASKED FOR. "Quotes usually take 3-5 working days.", "Matched suppliers send anonymised quotes.",
//      "The supplier can price ...", the reveal-fee paragraph, a fresh greeting on turn 3, and the same correction or
//      read-back restated every turn.
// A rule only in prose is a rule that gets broken, so both are now enforced by code around the model:
//   - BEFORE the reply: heldState() reads the conversation and lists what the customer already gave (typed slots, in
//     their own words) and every question already asked; heldBlock() puts that list in front of the model as "do not
//     ask again".
//   - AFTER, sentence by sentence: replyFilter() drops a question that asks a filled slot or repeats an earlier
//     question, a line on a topic the customer's message did not ask about (fee, turnaround, the supplier process,
//     an internal hand-off, a repeated greeting), a sentence restating one already said, and every question past the
//     third. A dropped sentence is never shown; brief_answer.ts has the model rewrite when nothing is left.
// What this deliberately does NOT do: decide what the reply should ask next (the model, with the trade playbooks in
// the compiled brief, does that), or reword a sentence (code writes no reply text: rulings 1195/1196).
// 27 Oct 2026, evening (22 scenarios: 0/22 at 95 %, mean 83 %): the text-overlap re-ask match missed paraphrase and
// Arabic word forms, and the model still chose what to ask. Since then the order of the brief is code's
// (conversation_plan.ts): in a job conversation heldState carries the plan's state, heldBlock shows it to the model,
// and replyFilter compares a question by the SLOT it targets, keeps only the next must-have (plus one more), and holds
// the summary turn to the summary and its confirm question. Outside a job conversation the rules below stand alone.
// prevented by: sales_engineer/portal_conversation.test.ts, sales_engineer/conversation_plan.test.ts

/** HOW A SENIOR UAE ESTIMATOR TAKES A JOB BRIEF in the portal chat (moved here from support_reply.ts on 27 Oct 2026, when
 *  the portal turn became one streamed call (#1640) and stopped going through supportReply). */
export const PORTAL_INTAKE = 'WHEN THEY DESCRIBE A JOB THEY WANT PRICED, take the brief the way a senior UAE estimator does. '
  + '(1) Read the whole conversation first: everything they have already said is known. Never ask again for anything they already stated or answered, in any wording; a question they skipped or were unsure about is noted "to confirm at the supplier\'s site visit" and not repeated. When they change something, the change replaces the earlier choice. '
  + '(2) If a specification they state is wrong, unsafe, or not accepted in the UAE (by code, Civil Defence, the municipality or the building), say so plainly and firmly in your FIRST reply, then the correct specification and why, in one or two sentences; never go along with it, and do not repeat the correction in later replies once made. '
  + '(3) Then ask the two missing specifications that most change the price for THIS trade, as short questions, offering concrete choices where that helps (for example sliding, hinged or push-to-open doors): sizes and quantities, material, finish and type or system, the existing condition and removal, site access, permits and approvals, and timing. A must-have the trade cannot be priced without (sizes, the type of system, the approvals) comes before anything optional. What the rules or the authority require (for example a recording period, a cable rating, a permit) is yours to state, never a question to them. '
  + '(4) When the essentials are known, give a short summary of the job as they told it, with every change they made, and ask them to confirm it; once confirmed, tell them to press "New request" (Arabic portal: "طلب جديد") to send it to verified suppliers. '
  + 'Never a robotic yes or no, never "I don\'t know" or "I will check": answer what can be said now. '
  + 'A choice they made stays made: never reopen it or argue for an option they changed away from. When they say they are unsure, recommend an answer to the question you last asked, then move on.';

/** THE SHAPE OF EVERY PORTAL REPLY. replyFilter() below enforces the parts a sentence can break on its own. */
export const REPLY_SHAPE = 'SHAPE OF EVERY REPLY: (a) at most one or two short sentences that answer their message or correct a wrong specification; when they only gave details, a few words of acknowledgement at most, never a read-back of everything they said (the read-back is for the final summary only); '
  + '(b) then at most two questions, the missing specifications that most change the price; (c) nothing else. No greeting after the first reply. '
  + 'Every reply ends with a question for them: the next missing specification or, once the essentials are known, the summary and "Is this correct?". '
  + 'Do not add the fee, "posting is free", how long quotes or the work take, what suppliers will do or how the request is sent unless their message asks about it. Never mention passing anything to a team.';

import { CATALOGUE, CONFIRM_ASK as PLAN_CONFIRM_ASK, labelOf, planState, sentencesOf as planSentences, stateBlock, stems, targets,
  type Extracted, type State } from './conversation_plan.ts';

export type Lang = 'en' | 'ar';
export interface Turn { role: 'user' | 'assistant'; content: string }
export interface Slot { slot: string; said: string }
export interface Held {
  /** what the customer already gave, by slot, with the sentence they said it in */
  slots: Slot[];
  /** dimension facts: the object measured ('' when none named) and the kinds given (width, height, ...) */
  dims: { object: string; kinds: string[] }[];
  /** every question the seat already asked, oldest first */
  asked: string[];
  /** every sentence the seat already said that was not a question */
  said: string[];
  /** the seat has not replied yet in this conversation */
  firstReply: boolean;
  /** the customer's message this turn */
  message: string;
  /** the job conversation's plan state (conversation_plan.ts); mode 'none' outside a job */
  plan: State;
}

// ── text helpers ──────────────────────────────────────────────────────────────────────────────────────────────────
/** Sentences of a text, each with its terminator; a trailing piece without one is a sentence too. */
export const sentencesOf = planSentences;
export const isQuestion = (s: string) => /[?؟]["')\]”’]*\s*$/.test(s.trim());

/** The content words of a text, normalised and stemmed (conversation_plan.stems: كاميرا and الكاميرات are one word). */
export const contentWords = stems;
const overlap = (a: Set<string>, b: Set<string>) => { let n = 0; for (const x of a) if (b.has(x)) n++; return n; };
/** The clauses of a question: "What width, and do you want sliding doors?" asks two things. A clause starts only where
 *  a new question word does: a list ("استوديو، أو غرفة، أو غرفتان") or "a wall split, or a ducted unit" is ONE ask
 *  (run ecb6b6b2, painting_ar: split at every Arabic comma, the room-count question became one-word fragments that
 *  never matched, and it was asked three times). */
const QWORD_EN = '(?:do|does|did|is|are|would|will|should|can|could|what|which|how|when|where|who|whose|have|has)\\b';
const QWORD_AR = '(?:هل|ماذا|متى|كم |كيف|أين|وين|أي |ما )';
const CLAUSE = new RegExp(`,\\s*(?:and|or)\\s+(?=${QWORD_EN})|;\\s*|\\s+and (?=${QWORD_EN})|،\\s*(?:و|أو|ف)?\\s*(?=${QWORD_AR})|\\s+و(?=${QWORD_AR})`, 'i');
const clausesOf = (q: string) => q.split(CLAUSE).map((x) => x.trim()).filter((x) => contentWords(x).size > 0);
/** Two questions ask the same thing: they share at least two content words, and most of the shorter one. */
export function sameAsk(a: string, b: string): boolean {
  const A = contentWords(a), B = contentWords(b);
  const n = overlap(A, B), m = Math.min(A.size, B.size);
  return n >= 2 && (n / m >= 0.6 || (n >= 3 && n / m >= 0.4));
}

// ── the typed slots a customer fills: the shared catalogue (conversation_plan.CATALOGUE) ─────────────────────────
// fill: the customer's text gives a value for it. ask: a QUESTION asks for it. 'size' is never dropped on the slot
// alone: a measured object can still be asked another dimension (the per-object rule below decides).
const NAME: Record<string, string> = { size: 'sizes', count: 'count', property: 'property type', location: 'location', ownership: 'ownership',
  permits: 'permits', existing: 'existing condition', finish: 'finish', layout: 'internal layout', doors: 'door type', handles: 'handles',
  system: 'system', scope: 'scope', coverage: 'coverage', performance: 'performance', recording: 'recording', services: 'services',
  appliances: 'appliances', design: 'design', usage: 'use', occupancy: 'occupancy', fixing: 'fixing', budget: 'budget', timing: 'timing' };
export const slotName = (id: string) => NAME[id] ?? id;

// Dimensions are a slot per OBJECT and KIND: "the wall is 2.4 m wide" fills the wall's width, not the door's.
const MEASURE = /\d+(?:[.,]\d+)?\s*(?:mm|cm|m|metres?|meters?|ft|feet|foot|sq\.?\s?m|sqm|m2|m²|square)\b|\d+(?:[.,]\d+)?\s*(?:x|by|×|في)\s*\d+|\d+(?:[.,]\d+)?\s*(?:متر|م٢|م2|سم|مم)|(?:متر|مترين)/i;
const OBJECTS: [string, RegExp][] = [
  ['wall', /\bwalls?\b|الجدار|جدار|الحائط|حائط|السور|سور/i], ['room', /\b(room|bedroom|living room|majlis|bathroom|kitchen)s?\b|الغرفة|غرفة|المجلس|الحمام|المطبخ/i],
  ['ceiling', /\bceilings?\b|السقف/i], ['roof', /\broofs?\b|السطح/i], ['floor', /\bfloors?\b|الأرضية|الارضيه/i],
  ['partition', /\bpartitions?\b|القواطع|قاطع/i], ['door', /\bdoors?\b|الباب|الأبواب|باب/i], ['window', /\bwindows?\b|النافذة|الشباك/i],
  ['wardrobe', /\bwardrobes?\b|الخزانة|خزانة|الدولاب|دولاب/i], ['shop', /\b(shop|store|office|unit|warehouse)s?\b|المحل|المكتب|المستودع/i],
  ['space', /\b(space|area|plot|garden|terrace|balcony|pool)s?\b|المساحة|الحديقة|الشرفة|البلكونة|المسبح/i],
];
const KINDS: [string, RegExp][] = [
  ['width', /\b(wide|width|widths)\b|عرض/i], ['height', /\b(high|height|heights|tall|ceiling)\b|ارتفاع|السقف/i],
  ['length', /\b(long|length|lengths|run)\b|طول/i], ['depth', /\b(deep|depth|depths)\b|عمق/i],
  ['area', /\b(sq\.?\s?m|sqm|m2|m²|square|area)\b|متر مربع|مساحة|المساحة/i],
];
const DIM_ASK = /\b(size|sizes|dimensions?|measurements?|width|height|length|depth|area|how (big|large|wide|high|tall|long|deep))\b|square met|\bsqm\b|قياس|مقاس|أبعاد|ابعاد|مساحة|المساحة|عرض|ارتفاع|طول|عمق/i;
const GENERIC_DIM = /\b(size|sizes|dimensions?|measurements?|how big|how large)\b|قياس|مقاس|أبعاد|ابعاد/i;
const objectsOf = (s: string) => OBJECTS.filter(([, re]) => re.test(s)).map(([o]) => o);
const kindsOf = (s: string) => {
  const k = KINDS.filter(([, re]) => re.test(s)).map(([n]) => n);
  if (/\d\s*(?:x|by|×|في)\s*\d/i.test(s)) k.push('width', 'length', 'area');
  return [...new Set(k)];
};

/** What the conversation already holds. `past` is every earlier turn (oldest first); `message` this turn's message;
 *  `extracted` what the bounded extraction call read from the message (conversation_plan.parseExtraction). */
export function heldState(past: Turn[], message: string, extracted: Extracted | null = null): Held {
  const plan = planState(past, message, extracted);
  const customer = [...past.filter((t) => t.role === 'user').map((t) => t.content), message].filter(Boolean);
  const slots: Slot[] = []; const dims: Held['dims'] = [];
  for (const text of customer) {
    for (const s of sentencesOf(text)) {
      for (const d of CATALOGUE) if (d.id !== 'size' && d.fill.test(normalised(s)) && !slots.some((x) => x.slot === d.id)) slots.push({ slot: d.id, said: s.slice(0, 160) });
      if (MEASURE.test(s)) {
        // "about 12 m of partition in total, 2.7 m high": two figures, one named; the unnamed one is the main extent
        const kinds = kindsOf(s);
        const figures = (s.match(new RegExp(MEASURE.source, 'gi')) ?? []).length;
        if (figures > kinds.filter((k) => k !== 'area').length) kinds.push('size');
        const objs = objectsOf(s);
        for (const o of objs.length ? objs : ['']) dims.push({ object: o, kinds: [...new Set(kinds)] });
        if (!slots.some((x) => x.slot === 'size')) slots.push({ slot: 'size', said: s.slice(0, 160) });
        else { const i = slots.findIndex((x) => x.slot === 'size'); if (!slots[i].said.includes(s.slice(0, 40))) slots[i] = { slot: 'size', said: (slots[i].said + ' ' + s).slice(0, 240) }; }
      }
    }
  }
  // the plan's to-confirm slots are held too: asked once, unsure or skipped, never asked again
  for (const id of plan.toConfirm) if (!slots.some((x) => x.slot === id)) slots.push({ slot: id, said: 'to confirm at the site visit' });
  for (const [id, v] of plan.filled) if (!slots.some((x) => x.slot === id)) slots.push({ slot: id, said: v.slice(0, 160) });
  const seat = past.filter((t) => t.role === 'assistant').flatMap((t) => sentencesOf(t.content));
  return { slots, dims, asked: seat.filter(isQuestion), said: seat.filter((s) => !isQuestion(s)), firstReply: !past.some((t) => t.role === 'assistant'), message, plan };
}
const normalised = (s: string) => s.normalize('NFKC').toLowerCase().replace(/[ً-ٰٟـ]/g, '').replace(/[أإآٱ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي').replace(/ؤ/g, 'و').replace(/ئ/g, 'ي');

/** The model is shown what it must not ask again, in the customer's own words. '' when nothing is held yet. */
export function heldBlock(h: Held): string {
  const lines: string[] = [];
  const state = stateBlock(h.plan);
  if (state) {
    lines.push(state);
    if (h.asked.length) lines.push('QUESTIONS ALREADY ASKED IN THIS CONVERSATION (never ask any of them again, in any wording):\n' + h.asked.slice(-12).map((q) => '- ' + q.slice(0, 200)).join('\n'));
    return lines.join('\n\n');
  }
  if (h.slots.length) lines.push('ALREADY GIVEN BY THE CUSTOMER (never ask for these again, in any wording):\n' + h.slots.map((s) => `- ${s.slot}: "${s.said}"`).join('\n'));
  if (h.asked.length) lines.push('QUESTIONS ALREADY ASKED IN THIS CONVERSATION (answered, skipped or unsure: never ask any of them again):\n' + h.asked.slice(-12).map((q) => '- ' + q.slice(0, 200)).join('\n'));
  return lines.join('\n\n');
}

/** Why a QUESTION re-asks: a filled slot, a measured dimension, or an earlier question. null when it asks something new. */
export function reaskOf(q: string, h: Held): string | null {
  // a question of two asks re-asks only when both do; newClauseOf keeps the new one (run 143372b1, cctv_shop turn 3)
  const parts = clausesOf(q);
  if (parts.length >= 2) {
    const why = parts.map((c) => reaskOne(c.replace(/[?؟.]*\s*$/, '') + (/[؀-ۿ]/.test(c) ? '؟' : '?'), h));
    if (why.every(Boolean)) return why[0];
    if (why.some(Boolean)) return null;
  }
  return reaskOne(q, h);
}
function reaskOne(q: string, h: Held): string | null {
  const filled = new Set(h.slots.map((s) => s.slot));
  // the slot a question targets, in any wording or word form: a filled or to-confirm slot is never asked again
  const t = targets(q, h.plan.plan);
  const onOpen = h.plan.mode === 'ask' && t.some((id) => h.plan.open.includes(id));
  if (!onOpen) for (const id of t) if (id !== 'size' && filled.has(id)) return `asks the ${slotName(id)} again`;
  // a question that quotes a figure ("Is the 85 square metres the dry areas only?") asks ABOUT what they gave, not for it
  if (DIM_ASK.test(q) && h.dims.length && !/\d/.test(q)) {
    const objs = objectsOf(q); const kinds = kindsOf(q);
    for (const o of objs) {
      const got = h.dims.filter((d) => d.object === o);
      if (!got.length) continue;
      const have = new Set(got.flatMap((d) => d.kinds));
      if (GENERIC_DIM.test(q) && !kinds.length) return `asks the ${o} size again`;
      const known = (k: string) => have.has(k) || (have.has('size') && (k === 'width' || k === 'length'))
        || (k === 'height' && h.dims.some((d) => d.object === 'ceiling'));
      if (kinds.length && kinds.every(known)) return `asks the ${o} ${kinds.join(' and ')} again`;
    }
  }
  const clauses = clausesOf(q);
  for (const a of h.asked) {
    const earlier = clausesOf(a);
    if (clauses.length && clauses.every((c) => earlier.some((e) => sameAsk(c, e)))) return 'repeats an earlier question';
  }
  return null;
}

// Lines on a topic the customer's message did not ask about. [topic, the sentence pattern, what in their message licenses it]
const UNASKED: [string, RegExp, RegExp | null][] = [
  ['the fee', /\b(fees?|free of charge|is free|for free|no charge|commission|reveal)\b|\bAED\b|\bdirhams?\b|رسوم|مجاني|مجانا|مجاناً|درهم|عمولة/i,
    /\b(fee|fees|cost|costs|charge|pay|paid|price|pricing|how much|free|commission|budget|aed|reveal)\b|رسوم|تكلفة|تكلفه|سعر|بكم|كم (يكلف|سعر|التكلفة)|ادفع|أدفع|مجان/i],
  ['how long it takes', /\b(working|business) days\b|\bwithin \d+\s*(hours?|days?)\b|\b\d+\s*[–-]\s*\d+\s*(working |business )?(days|weeks|hours)\b|\bquotes? (usually |typically |normally |will )?(take|arrive|come)\b|أيام عمل|خلال \d+ (ساعة|أيام|يوم)|يستغرق|تستغرق/i,
    // a question about time, not a timeline they state ("within 2 weeks" licensed the 3-5 day line until this was narrowed)
    /\bhow long\b|\bwhen (will|would|can|do|could)\b|\bhow soon\b|\bhow quickly\b|\bhow many (days|weeks)\b|\b(is|would) (that|it|this) (possible|realistic|enough)\b|\bin time\b|متى|كم يوم|كم المدة|كم تستغرق|هل يمكن|هل ممكن/i],
  ['what suppliers will do', /\bmatched suppliers?\b|\bverified suppliers?\b|\banonymi[sz]ed quotes?\b|\b(suppliers?|installers?|contractors?) (will|can|then|would) (then )?(propose|suggest|measure|price|quote|send)\b|\b(propose|suggest|measure) and price\b|\b(send|route|share|submit) (it|this|your request|the request|your brief) to\b|new request|طلب جديد|الموردين المعتمدين|الموردين الموثقين|سيقوم المورد|عروض الأسعار من/i,
    /\bhow (does|do|will|can) (it|this|that|quotes?|you|i)\b|\bnext\b|\bsend\b|\bsubmit\b|\bsuppliers?\b|\bquotes?\b|\bconfirm|\bcorrect\b|^\s*(yes|yeah|yep|ok|okay)\b|كيف|الخطوة|ارسال|إرسال|أرسل|ارسل|مورد|عرض|نعم|صحيح|تمام|أكد/i],
  ['an internal hand-off', /\b(passed|forwarded|handed|escalated|routed|referred) (it |this |that |your [a-z -]+ )?(on |over )?to (the|our) [a-z -]*team\b|(أحلت|حولت|أحلنا|حولنا)[^.؟]*فريق/i, null],
];
// \b is ASCII-only in JS, so the end of a greeting is "not followed by a letter" (an Arabic greeting ends in one)
const GREETING = /^\s*(hi|hello|hey|dear|good (morning|afternoon|evening)|greetings|thank you for (contacting|reaching|your message)|thanks for (contacting|reaching|your message)|السلام عليكم|وعليكم السلام|مرحبا|مرحباً|أهلا|اهلا|أهلاً)(?!\p{L})/iu;
const SUMMARY = /^\s*(here is|here's|here are|to summari[sz]e|in summary|summary|your request|the job as)\b|^\s*(ملخص|إليك ملخص|هذا ملخص)/i;
export const MAX_QUESTIONS = 3;
const CONFIRM = /\b(confirm|correct|right)\b|صحيح|تأكيد|أكد|أكّد/i;
// A question asking them to confirm the read-back (PORTAL_INTAKE step 4). It restates the job, so it shares most of its
// words with the questions that gathered it, and it must never be taken for a re-ask (run 94311f64, ac_replacement:
// "Here is the job as you told it: ... is that correct?" was dropped as "repeats an earlier question" twice).
const CONFIRM_ASK = /\b(is (that|this|it|everything|all of (that|this)) (correct|right|accurate)|did I (get|capture)|(can|could) you confirm|please confirm|shall I (send|submit)|(correct|right)\s*[?]\s*$)|(صحيح|تؤكد|أكد|التأكيد)[^؟]*؟\s*$/i;
export const ALL_QUESTIONS_DROPPED = 'every question it asked was already asked or answered; ask the next missing specification instead, or, when the essentials are known, give the summary and ask them to confirm it';
/** What the filter says of one sentence: null keep it, a reason drop it, or keep only `text` (the model's own words,
 *  one clause of its question) for `why`. */
export type Verdict = string | null | { text: string; why: string };
/** A sentence filter for one reply; `end()` names a problem with the reply as a whole once every sentence was seen. */
export type ReplyFilter = ((sentence: string) => Verdict) & { end: () => string | null };
export const ENDS_WITHOUT_A_QUESTION = 'it ends without asking them anything; end with the next missing specification as a question or, when the essentials are known, the summary and "Is this correct?"';
const ASKS = /^\s*(do|does|did|is|are|was|were|would|will|should|can|could|have|has|what|which|how|when|where|who|whose|هل|ما|ماذا|كم|متى|أين|اين|وين|كيف|أي|اي|شو|ايش)\b|^\s*(هل|ما|ماذا|كم|متى|أين|وين|كيف|أي|شو)/i;
const CONFIRMED = /^\s*(yes|yeah|yep|correct|that is correct|confirmed?)\b|^\s*(نعم|صحيح|تمام|أكيد|أكد)/i;
/** A two-part question whose other parts are re-asks keeps its one new part, when that part is a question on its own
 *  (run 143372b1: "Does the mall need its own installer, and do you want economy, mid-range or premium?" one turn after
 *  the budget was asked). Returns that clause as a question, or null when no clean single clause is left. */
export function newClauseOf(q: string, h: Held): string | null {
  const parts = clausesOf(q);
  if (parts.length < 2) return null;
  const fresh = parts.filter((c) => !reaskOf(c.replace(/[?؟.]*\s*$/, '') + (/[؀-ۿ]/.test(c) ? '؟' : '?'), h));
  if (fresh.length !== 1 || !ASKS.test(fresh[0].replace(/^[وف]/, ''))) return null;
  const c = fresh[0].replace(/[?؟.]*\s*$/, '');
  return c.charAt(0).toUpperCase() + c.slice(1) + (/[؀-ۿ]/.test(c) ? '؟' : '?');
}

/** Why a NON-question sentence is a line nobody asked for. null when it may stay. */
const UNSURE_SEAT = /\b(i don'?t know|i do not know|(i'?m|i am|you'?re|you are) (not sure|unsure)|i'?ll (check|find out|get back)|i will (check|find out|get back))\b|لا أعرف|ما أعرف|لست متأكد|مو متأكد|غير متأكد|سأتحقق|راح أتأكد/i;
export function unaskedOf(s: string, h: Held, inSummary = false): string | null {
  if (UNSURE_SEAT.test(s)) return 'it says someone does not know or is unsure';
  if (!h.firstReply && GREETING.test(s)) return 'a greeting after the first reply';
  for (const [topic, re, licence] of UNASKED) {
    // "If that is correct, press New request" closes the summary (PORTAL_INTAKE step 4): asking them to confirm is never
    // an unasked process line (run 143372b1: two summaries lost their confirm request this way and the conversation stalled)
    if (topic === 'what suppliers will do' && CONFIRM.test(s)) continue;
    if (re.test(s) && !(licence && licence.test(h.message))) return `a line on ${topic} they did not ask about`;
  }
  // the final read-back restates on purpose (PORTAL_INTAKE step 4): it is never dropped as a repeat
  const W = contentWords(s);
  if (W.size >= 5 && !inSummary && !SUMMARY.test(s)) for (const p of h.said) { const P = contentWords(p); if (overlap(W, P) / W.size >= 0.7) return 'restates a sentence already said'; }
  return null;
}

/** A fresh filter for ONE reply: called on each sentence in order, it says why a sentence is dropped, or null to keep it.
 *  It counts the questions it kept, so a fourth is dropped (the shape allows two; a third is tolerated). */
export function replyFilter(h: Held): ReplyFilter {
  if (h.plan.plan && h.plan.mode !== 'none') return planFilter(h);
  let kept = 0; let reasked = 0; let inSummary = false;
  const f = (sentence: string): Verdict => {
    const s = sentence.trim();
    if (!s) return null;
    // once the read-back starts, the rest of the reply restates the job on purpose: nothing in it is a repeat
    if (SUMMARY.test(s)) inSummary = true;
    if (isQuestion(s)) {
      if (inSummary || CONFIRM_ASK.test(s)) { kept++; return null; }
      const r = reaskOf(s, h);
      if (r) { reasked++; return r; }
      const one = newClauseOf(s, h);
      if (kept >= MAX_QUESTIONS) return `more than ${MAX_QUESTIONS} questions`;
      kept++;
      return one ? { text: one, why: 'part of the question was asked before' } : null;
    }
    return unaskedOf(s, h, inSummary);
  };
  // A JOB CONVERSATION NEVER ENDS ON A STATEMENT (run 143372b1, 27 Oct 2026: replies whose questions were dropped, or that
  // wrote none, left the customer nothing to answer and the brief was never finished: 5 of 10 conversations stopped
  // before a summary). Once the job is under way (something given or asked) and they did not just confirm, a reply with
  // no question is rewritten; brief_answer keeps it as the last resort, never sends nothing.
  const job = h.slots.length > 0 || h.asked.length > 0;
  return Object.assign(f, { end: () => (kept > 0 ? null : reasked > 0 ? ALL_QUESTIONS_DROPPED
    : job && !h.firstReply && !CONFIRMED.test(h.message) ? ENDS_WITHOUT_A_QUESTION : null) });
}

/** The reply with the dropped sentences taken out (a whole answer: a rewrite or a retry). */
export function stripReply(text: string, h: Held): { text: string; dropped: { sentence: string; why: string }[]; end: string | null } {
  const f = replyFilter(h);
  const kept: string[] = []; const dropped: { sentence: string; why: string }[] = [];
  for (const s of sentencesOf(text)) {
    const v = f(s);
    if (typeof v === 'string') dropped.push({ sentence: s, why: v });
    else if (v) { dropped.push({ sentence: s, why: v.why }); kept.push(v.text); }
    else kept.push(s);
  }
  return { text: kept.join(' ').trim(), dropped, end: f.end() };
}

// ── THE FILTER IN A JOB CONVERSATION: code decides what is asked (conversation_plan.ts) ───────────────────────────
/** In a job conversation a reply asks at most this many questions: the next must-have and one more. */
export const MAX_PLAN_QUESTIONS = 2;
export const SUMMARY_NEEDS_CONFIRM = 'this reply must be the summary of the job as they told it, ending with one question asking whether it is correct';
export const askTheNext = (h: Held) => `it does not ask about ${labelOf(h.plan, h.plan.next!)}; ask one short question about that and nothing already given`;
/** The filter for one reply in a job conversation (h.plan.mode is 'ask', 'summary' or 'confirmed'):
 *   ask       a question on a filled or to-confirm slot, or repeating an earlier question, is dropped (reaskOf);
 *             a question on another must-have than the next two is dropped (it is asked in its turn); one question
 *             on something outside the plan (an expert follow-up) may stay; at most MAX_PLAN_QUESTIONS; a reply
 *             asking neither the next must-have nor anything code cannot place is rewritten (end()).
 *   summary   every statement stays (the read-back restates on purpose); the only question kept is the one asking
 *             whether it is correct, and a summary without it is rewritten.
 *   confirmed nothing is asked; the reply tells them to press New request. */
function planFilter(h: Held): ReplyFilter {
  const st = h.plan; const plan = st.plan!;
  const inPlan = (id: string) => plan.slots.some((s) => s.id === id);
  const chosen = new Set([st.next, st.also].filter(Boolean) as string[]);
  if (chosen.has('size')) chosen.add('count');
  let kept = 0; let onPlan = 0; let unplaced = 0; let extra = 0; let reasked = 0; let confirmAsk = 0; let inSummary = st.mode === 'summary';
  const f = (sentence: string): Verdict => {
    const s = sentence.trim();
    if (!s) return null;
    if (SUMMARY.test(s)) inSummary = true;
    if (!isQuestion(s)) return unaskedOf(s, h, inSummary);
    if (st.mode === 'confirmed') return 'they confirmed the summary: nothing more is asked';
    if (st.mode === 'summary') {
      if (confirmAsk === 0 && (PLAN_CONFIRM_ASK.test(s) || CONFIRM_ASK.test(s))) { confirmAsk++; kept++; return null; }
      return 'the summary asks only whether it is correct';
    }
    if (PLAN_CONFIRM_ASK.test(s) || CONFIRM_ASK.test(s)) return 'a read-back before the essentials are in';
    const r = reaskOf(s, h);
    if (r) { reasked++; return r; }
    const one = newClauseOf(s, h);
    const q = one ?? s;
    const t = targets(q, plan).filter((id) => !(id === 'size' && /\d/.test(q)));
    if (t.some((id) => chosen.has(id))) onPlan++;
    else if (t.some(inPlan)) {
      const id = t.find(inPlan)!;
      return `asks the ${slotName(id)} before the ${slotName(st.next!)}: code asks the ${slotName(st.next!)} now`;
    } else {
      if (extra >= 1) return 'more than one question beyond the must-have code chose';
      extra++;
      if (!t.length) unplaced++;
    }
    if (kept >= MAX_PLAN_QUESTIONS) return `more than ${MAX_PLAN_QUESTIONS} questions`;
    kept++;
    return one ? { text: one, why: 'part of the question was asked before' } : null;
  };
  return Object.assign(f, { end: () => {
    if (st.mode === 'confirmed') return null;
    if (st.mode === 'summary') return confirmAsk ? null : SUMMARY_NEEDS_CONFIRM;
    if (kept === 0) return reasked ? ALL_QUESTIONS_DROPPED + ` (the next one: ${labelOf(st, st.next!)})` : askTheNext(h);
    // a question code cannot place may be the next must-have in other words; one placed elsewhere is not
    return onPlan || unplaced ? null : askTheNext(h);
  } });
}
