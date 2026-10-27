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
// prevented by: sales_engineer/portal_conversation.test.ts

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
}

// ── text helpers ──────────────────────────────────────────────────────────────────────────────────────────────────
/** Sentences of a text, each with its terminator; a trailing piece without one is a sentence too. */
export function sentencesOf(text: string): string[] {
  const out: string[] = [];
  // a full stop between digits ("2.6 m") is not the end of a sentence
  const re = /(?:[^.!?؟\n]|(?<=\d)\.(?=\d)|[.!?؟]+(?!["')\]”’]*(?:\s|$)))*(?:[.!?؟]+["')\]”’]*(?=\s|$)|\n+|$)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(String(text || ''))) && m[0] !== '') { if (/[\p{L}\p{N}]/u.test(m[0])) out.push(m[0].trim()); }
  return out;
}
export const isQuestion = (s: string) => /[?؟]["')\]”’]*\s*$/.test(s.trim());

const STOP = new Set(('a an the and or of to for in on at is are be been do does did you your yours we our us i me my it its this that these those would '
  + 'could should will can may might what which how when where who whom whose any some each every per with by from as if about into please also just '
  + 'there here have has had want like need prefer more much many than then so not no yes ok let know tell share give get make sure one two '
  + 'من في على الى إلى عن ما ماذا هل كم اي أي التي الذي هذا هذه هو هي انت أنت لك لديك عندك تريد تفضل او أو و ثم مع لا نعم كل اذا إذا').split(' '));
const norm = (s: string) => s.toLowerCase().normalize('NFKC').replace(/[ً-ْـ]/g, '').replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي');
const stem = (w: string) => /[a-z]/.test(w)
  ? w.replace(/(ings?|ers?|ed|es|s)$/, (x) => (w.length - x.length >= 3 ? '' : x))
  : w.replace(/^(وال|بال|لل|فال|ال)/, (x) => (w.length - x.length >= 2 ? '' : x));
/** The content words of a text, normalised and stemmed. */
export function contentWords(s: string): Set<string> {
  const out = new Set<string>();
  for (const w of norm(s).split(/[^\p{L}\p{N}]+/u)) {
    if (!w || STOP.has(w)) continue;
    const t = stem(w);
    if (t.length >= (/[a-z]/.test(t) ? 3 : 2) && !STOP.has(t)) out.add(t);
  }
  return out;
}
const overlap = (a: Set<string>, b: Set<string>) => { let n = 0; for (const x of a) if (b.has(x)) n++; return n; };
/** The clauses of a question: "What width, and do you want sliding doors?" asks two things. */
const clausesOf = (q: string) => q.split(/,\s*(?:and|or)\s+|;\s*|\s+and (?=(?:do|does|is|are|would|will|should|can|what|which|how|when|where)\b)|،\s*(?:و|أو)?/i)
  .map((x) => x.trim()).filter((x) => contentWords(x).size > 0);
/** Two questions ask the same thing: they share at least two content words, and most of the shorter one. */
export function sameAsk(a: string, b: string): boolean {
  const A = contentWords(a), B = contentWords(b);
  const n = overlap(A, B), m = Math.min(A.size, B.size);
  return n >= 2 && (n / m >= 0.6 || (n >= 3 && n / m >= 0.4));
}

// ── the typed slots a customer fills ──────────────────────────────────────────────────────────────────────────────
// fill: the customer's text gives a value for it. ask: a QUESTION asks for it. Both narrow on purpose: a missed slot
// costs one re-ask the earlier-question match may still catch; a wrong one would drop a question the job needs.
interface SlotDef { slot: string; fill: RegExp; ask: RegExp }
const MONTHS = 'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?';
const PLACES = 'dubai|abu dhabi|sharjah|ajman|ras al khaimah|rak|fujairah|umm al quwain|al ain|jlt|jvc|marina|deira|bur dubai|mirdif|al barsha|jumeirah|downtown|business bay|silicon oasis|al nahda|khalifa city|reem|yas|saadiyat|motor city|sports city|arabian ranches|palm|karama|al qusais|international city|discovery gardens'
  + '|دبي|أبوظبي|ابوظبي|أبو ظبي|ابو ظبي|الشارقة|الشارقه|عجمان|رأس الخيمة|راس الخيمه|الفجيرة|الفجيره|أم القيوين|ام القيوين|العين|البرشاء|ديرة|ديره|مردف|جميرا|الخوانيج|النهدة|خليفة';
export const SLOTS: SlotDef[] = [
  { slot: 'property type',
    fill: /\b(villa|apartment|flat|studio|townhouse|penthouse|office|shop|warehouse|restaurant|clinic|school|hotel|showroom)\b|فيلا|فيله|شقة|شقه|مكتب|محل|مستودع|مطعم|عيادة|مدرسة|فندق/i,
    ask: /\b(villa|apartment|flat|townhouse|office|shop|house)\b[^?]{0,25}\bor\b[^?]{0,25}\b(villa|apartment|flat|townhouse|office|shop|house|another|other)\b|\b(type|kind) of (property|premises|building)\b|(فيلا|شقة|شقه)[^؟]{0,15}(أو|او|أم|ام)[^؟]{0,15}(فيلا|شقة|شقه|مكتب)|نوع العقار/i },
  { slot: 'ownership',
    fill: /\b(own|owned|owner|rent|rented|renting|tenant|landlord|leased?)\b|ملك|مالك|إيجار|ايجار|مستأجر|مستاجر/i,
    ask: /\b(do|are) you (own|rent|the owner|a tenant)|\bown(ed)? or rent|\bowner or (a )?tenant|تملك|مالك (أم|او|أو) مستأجر|ملك (أم|او|أو) (إيجار|ايجار)/i },
  { slot: 'location',
    fill: new RegExp(`\\b(${PLACES})\\b|(${PLACES})`, 'i'),
    ask: /\b(which|what) (emirate|area|community|city|location|part of)\b|\bwhere is (it|the|your)\b|\bwhere are you\b|\blocated\b|في أي (إمارة|امارة|منطقة|منطقه)|وين (موقع|المكان|تقع|يقع)|أين (يقع|تقع|الموقع)|ما (هي )?المنطقة/i },
  { slot: 'timing',
    fill: new RegExp(`\\b(within|in) (\\d+|a|one|two|three|four|five|six|eight|few|couple of) (days?|weeks?|months?)\\b|\\b(this|next) (week|month)\\b|\\basap\\b|\\burgent|\\bby (the )?(end of )?(${MONTHS})\\b|\\bbefore (summer|winter|ramadan|eid)\\b|\\bflexible\\b|\\bno rush\\b|خلال|هذا الأسبوع|الاسبوع|الأسبوع القادم|الشهر القادم|مستعجل|قبل (الشتاء|الصيف|رمضان|العيد)|مرن`, 'i'),
    ask: /\bwhen (do|would|should|can|are) you\b|\btimeline\b|\btime ?frame\b|\bhow soon\b|\bdeadline\b|\btarget (date|completion)\b|\bstart date\b|متى|الموعد|الإطار الزمني|الاطار الزمني|المدة المطلوبة/i },
  { slot: 'budget',
    fill: /\bbudget\b|\beconomy\b|\bmid-?range\b|\bpremium\b|\bluxury\b|\bmoderate\b|\baffordable\b|\bAED\s?\d|\d[\d,.]*\s?(k|aed|dirhams?)\b|ميزانية|الميزانية|متوسطة|متوسطه|اقتصادي|فاخر|درهم/i,
    ask: /\bbudget\b|\bprice range\b|\beconomy,? mid-?range\b|الميزانية|ميزانية|فئة السعر/i },
  { slot: 'door type',
    fill: /\b(sliding|hinged|push[- ]to[- ]open|bi-?fold|pocket)\b|سحاب|منزلق|منزلقة|مفصل|مفصلات|بالضغط|ضغط/i,
    ask: /\b(sliding|hinged|push[- ]to[- ]open|bi-?fold)\b[^?]{0,40}\bor\b|\b(door|doors) type\b|\btype of doors?\b|نوع الأبواب|نوع الابواب|(سحاب|منزلق)[^؟]{0,20}(أو|او|أم|ام)/i },
  { slot: 'internal layout',
    fill: /\b(hanging|shelves|shelving|drawers)\b|تعليق|رفوف|أدراج|ادراج/i,
    ask: /\binternal layout\b|\blayout inside\b|\b(long|short|double) (or (long|short|double) )?hanging\b|\b(hanging|shelves|drawers)\b[^?]{0,30}\b(or|and)\b[^?]{0,30}\b(hanging|shelves|drawers)\b|الترتيب الداخلي|(تعليق|رفوف|أدراج)[^؟]{0,20}(أو|او|و)[^؟]{0,20}(تعليق|رفوف|أدراج)/i },
  { slot: 'existing',
    fill: /\b(no existing|there is no|new installation|nothing there|existing (one|unit|system|kitchen|wardrobe)|(remove|replace|demolish) the (old|existing))\b|لا يوجد|جديد بالكامل|إزالة|ازالة|القديم/i,
    ask: /\b(is there|do you have) an? (existing|current)\b|\breplacing an existing\b|\bremove (and dispose of )?(the |any )?(existing|old)\b|هل (يوجد|في|فيه) (نظام|مطبخ|وحدة)? ?(حالي|قديم|موجود)|إزالة (القديم|المطبخ القديم)/i },
];

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

/** What the conversation already holds. `past` is every earlier turn (oldest first); `message` this turn's message. */
export function heldState(past: Turn[], message: string): Held {
  const customer = [...past.filter((t) => t.role === 'user').map((t) => t.content), message].filter(Boolean);
  const slots: Slot[] = []; const dims: Held['dims'] = [];
  for (const text of customer) {
    for (const s of sentencesOf(text)) {
      for (const d of SLOTS) if (d.fill.test(s) && !slots.some((x) => x.slot === d.slot)) slots.push({ slot: d.slot, said: s.slice(0, 160) });
      if (MEASURE.test(s)) {
        // "about 12 m of partition in total, 2.7 m high": two figures, one named; the unnamed one is the main extent
        const kinds = kindsOf(s);
        const figures = (s.match(new RegExp(MEASURE.source, 'gi')) ?? []).length;
        if (figures > kinds.filter((k) => k !== 'area').length) kinds.push('size');
        const objs = objectsOf(s);
        for (const o of objs.length ? objs : ['']) dims.push({ object: o, kinds: [...new Set(kinds)] });
        if (!slots.some((x) => x.slot === 'sizes')) slots.push({ slot: 'sizes', said: s.slice(0, 160) });
        else { const i = slots.findIndex((x) => x.slot === 'sizes'); if (!slots[i].said.includes(s.slice(0, 40))) slots[i] = { slot: 'sizes', said: (slots[i].said + ' ' + s).slice(0, 240) }; }
      }
    }
  }
  const seat = past.filter((t) => t.role === 'assistant').flatMap((t) => sentencesOf(t.content));
  return { slots, dims, asked: seat.filter(isQuestion), said: seat.filter((s) => !isQuestion(s)), firstReply: !past.some((t) => t.role === 'assistant'), message };
}

/** The model is shown what it must not ask again, in the customer's own words. '' when nothing is held yet. */
export function heldBlock(h: Held): string {
  const lines: string[] = [];
  if (h.slots.length) lines.push('ALREADY GIVEN BY THE CUSTOMER (never ask for these again, in any wording):\n' + h.slots.map((s) => `- ${s.slot}: "${s.said}"`).join('\n'));
  if (h.asked.length) lines.push('QUESTIONS ALREADY ASKED IN THIS CONVERSATION (answered, skipped or unsure: never ask any of them again):\n' + h.asked.slice(-12).map((q) => '- ' + q.slice(0, 200)).join('\n'));
  return lines.join('\n\n');
}

/** Why a QUESTION re-asks: a filled slot, a measured dimension, or an earlier question. null when it asks something new. */
export function reaskOf(q: string, h: Held): string | null {
  const filled = new Set(h.slots.map((s) => s.slot));
  for (const d of SLOTS) if (filled.has(d.slot) && d.ask.test(q)) return `asks the ${d.slot} again`;
  if (DIM_ASK.test(q) && h.dims.length) {
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
export function unaskedOf(s: string, h: Held): string | null {
  if (!h.firstReply && GREETING.test(s)) return 'a greeting after the first reply';
  for (const [topic, re, licence] of UNASKED) {
    // "If that is correct, press New request" closes the summary (PORTAL_INTAKE step 4): asking them to confirm is never
    // an unasked process line (run 143372b1: two summaries lost their confirm request this way and the conversation stalled)
    if (topic === 'what suppliers will do' && CONFIRM.test(s)) continue;
    if (re.test(s) && !(licence && licence.test(h.message))) return `a line on ${topic} they did not ask about`;
  }
  // the final read-back restates on purpose (PORTAL_INTAKE step 4): it is never dropped as a repeat
  const W = contentWords(s);
  if (W.size >= 5 && !SUMMARY.test(s)) for (const p of h.said) { const P = contentWords(p); if (overlap(W, P) / W.size >= 0.7) return 'restates a sentence already said'; }
  return null;
}

/** A fresh filter for ONE reply: called on each sentence in order, it says why a sentence is dropped, or null to keep it.
 *  It counts the questions it kept, so a fourth is dropped (the shape allows two; a third is tolerated). */
export function replyFilter(h: Held): ReplyFilter {
  let kept = 0; let reasked = 0;
  const f = (sentence: string): Verdict => {
    const s = sentence.trim();
    if (!s) return null;
    if (isQuestion(s)) {
      const r = reaskOf(s, h);
      if (r) { reasked++; return r; }
      const one = newClauseOf(s, h);
      if (kept >= MAX_QUESTIONS) return `more than ${MAX_QUESTIONS} questions`;
      kept++;
      return one ? { text: one, why: 'part of the question was asked before' } : null;
    }
    return unaskedOf(s, h);
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
