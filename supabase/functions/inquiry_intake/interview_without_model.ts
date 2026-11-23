// inquiry_intake/interview_without_model.ts — THE TURN WITH NO MODEL READING (OpenRouter down or held, or a reply we could
// not parse): the deterministic interview of ./interview.ts asks one plain question at a time. handle.ts runs it when `out`
// is null and takes back the reply, the interview's state, the next question and the readiness. Moved verbatim from
// handle.ts (19 Nov 2026, it_engineer; ledgers 1714/1715/1556: handle.ts was 1,418 lines).
// deno-lint-ignore-file no-explicit-any
import { interviewStep, orderFields, questionText, buildBrief } from './interview.ts';
import { adviseUnknown, packFields, withUniversal, universalAnswers, type TradeContext } from '../_shared/inquiry_trades.ts';
import type { InquiryState } from '../_shared/inquiry_state.ts';
import { firstAsk, unreadLead, type PhotoRead } from '../_shared/photo_reading.ts';

export function interviewWithoutModel(c: { ar: boolean; draft: any; tradeCtx: TradeContext | null; topicsNow: string[]; st: InquiryState | null; emirate: string | null;
  unknownNow: Record<string, string>; category: string | null; checklist: any[]; text: string; allText: string; askOrder: Record<string, number>; turns: any[]; catLabel: string; photoReads: PhotoRead[] }) {
  const { ar, draft, tradeCtx, topicsNow, st, emirate, unknownNow, category, checklist, text, allText, askOrder, turns, catLabel, photoReads } = c;
  let out: any = null;
  let interview: { details: Record<string, string>; asked_key: string | null } | null = null;
  let nextQuestion: { key: string | null; text: string; options: string[] | null; suggested?: string | null } | null = null;
  let readinessFields: { filled: number; required: number } | null = null;
  // THIS IS THE LIVE PATH TODAY, NOT A RARE FALLBACK. Every model route in llm_route_health is
  // open_until 2126 under the founder's OpenRouter hold, so `out` is null on every real intake
  // and these questions are what a customer actually sees.
  //
  // They come straight out of category_specs.fields, which is written in trade language for our
  // own desks — "confirm the substrate condition", "specify the BTU load". The founder,
  // 10 Sep 2026: ask "in a very smart way because customers are not all technical". The model
  // is instructed to translate; with no model there is nothing doing the translating, so the
  // deterministic path must not simply read the trade checklist out loud.
  //
  // What it does instead: ask for what the customer CAN give — their own words, a photo, a
  // drawing — and surface at most THREE checklist items as prompts rather than a wall of
  // requirements. Fewer, softer questions that get answered beat a complete list that gets
  // abandoned, and an attached drawing answers most of them anyway.
  //
  // 14 Sep 2026: the data fix landed — scripts/sql/the_intake_asks_every_question_in_plain_words.sql
  // writes question_plain_en / question_plain_ar beside all 396 fields — and this path now runs
  // an actual interview (./interview.ts): one plain question at a time, each answer parsed into
  // its canonical key, state kept in brief.details, 'ready' when every required key is filled.
  const lang = ar ? 'ar' : 'en';
  const prevState0 = (draft.brief && typeof draft.brief === 'object' && draft.brief.details && typeof draft.brief.details === 'object')
    ? { details: draft.brief.details as Record<string, string>, asked_key: (draft.brief.asked_key as string) || null }
    : { details: {}, asked_key: null };
  // the same "supplier to advise" for a pack spec they do not know, on the interview's own state
  const packNow = packFields(tradeCtx, topicsNow);
  const prevState = { ...prevState0, details: adviseUnknown(withUniversal(prevState0.details, packNow, universalAnswers({ specs: { ...(st?.specs ?? {}), ...prevState0.details }, emirate })),
    packNow, [...Object.keys(st?.unknown ?? {}), ...Object.keys(unknownNow)]) as Record<string, string> };
  const step = category && checklist.length ? interviewStep(checklist, prevState, text, allText, lang, askOrder) : null;
  interview = step ? { details: step.details, asked_key: step.next ? step.next.key : null } : null;
  nextQuestion = step?.next ? { key: step.next.key, text: step.next.text, options: step.next.options } : null;
  readinessFields = step ? step.readiness : null;
  const remaining = step ? orderFields(checklist, askOrder).filter((o) => o.f.required && !(o.key in step.details)).map((o) => questionText(o.f, lang)) : [];
  const missingReq = remaining.slice(0, 3);
  // THE FIRST ASK SAYS ONLY WHAT IS TRUE (19 Nov 2026, ruling 1200; _shared/photo_reading.ts firstAsk). It promised every
  // customer "attach it and I will read the details off it for you instead of asking", and no photo was ever read. Now: a photo
  // read this turn is asked about (its open questions); one that could not be read is said so; with none, a photo or a drawing
  // is welcome, and we say if we cannot read it.
  const plainAsk = firstAsk(photoReads, lang);
  const firstUser = String(turns.find((t: any) => t.role === 'user')?.text || allText);
  const score = step && step.readiness.required ? Math.round(100 * step.readiness.filled / step.readiness.required) : 10;
  const provenanceStated = step ? Object.fromEntries(Object.keys(step.details).map((k) => [k, 'stated'])) : {};
  if (!allText.trim() || allText.trim().length < 8 || !category) {
    // No trade recognised yet: the plain question, else ask
    // for the job in their own words. Nothing to interview against until a category exists.
    out = { category, status: 'needs_info', assistant_message: plainAsk, questions: [plainAsk], readiness: 10, missing: [], brief: null };
  } else if (step && !step.complete && step.next) {
    const firstTurn = !prevState.asked_key && turns.filter((t: any) => t.role === 'user').length <= 1;
    const ack = unreadLead(photoReads, lang) + (firstTurn
      ? (ar ? 'فهمت. ' : `Got it — ${catLabel || category} work. `)
      : (step.filled_now.length ? (ar ? 'شكرًا، دوّنت ذلك. ' : 'Thanks, noted. ') : ''));
    out = { category, status: 'needs_info', assistant_message: ack + step.next.text, questions: [step.next.text], readiness: Math.min(score, 95), missing: remaining, brief: null, provenance: provenanceStated };
  } else if (step && step.complete) {
    out = { category, status: 'ready', assistant_message: ar ? 'شكرًا لك، اكتمل كل ما يحتاجه المورّدون. راجع الملخص أدناه، ثم اضغط «أرسل إلى الموردين».' : 'Thank you — that is everything suppliers need. Check the summary below and press Send to suppliers.', questions: [], readiness: 100, missing: [], provenance: provenanceStated, brief: buildBrief(String(category), step.details, allText, emirate, firstUser) };
  } else {
    // A category with no checklist rows at all: nothing to ask, so the description is the brief.
    out = { category, status: 'ready', assistant_message: ar ? 'ممتاز، راجع الملخص أدناه، ثم أرسله إلى المورّدين المطابقين.' : "Great — check the summary below and send it to matching suppliers.", questions: [], readiness: 75, missing: [], brief: buildBrief(String(category), {}, allText, emirate, firstUser) };
  }
  return { out, interview, nextQuestion, readinessFields };
}
