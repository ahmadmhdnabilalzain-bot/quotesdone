// inquiry_intake/four_questions.ts — THE SALES ENGINEER'S FOUR QUESTIONS (founder, 14 Sep 2026), and the emirate asked once
// before them when none is held. Runs after the category's checklist and the blocking gate, on the model path and the
// deterministic one alike; rewrites the reply (`out`) when it asks, and hands back the status, the next question and the
// answers handle.ts saves on the brief. Moved verbatim from handle.ts (19 Nov 2026, it_engineer; ledgers 1714/1715/1556:
// handle.ts was 1,418 lines).
// deno-lint-ignore-file no-explicit-any
import { replyFromState, mergeRequirements, requirementsFromModel, askedTurnsByKey } from './slots.ts';
import { emirateOf, SEVEN_EMIRATES, SEVEN_EMIRATES_AR } from './classify.ts';
import { notSureAnswer, requirementsStep, requirementQuestions, statedAnswers, questionIn, type Answers } from '../_shared/intake_requirements.ts';
import { saysDontKnow } from '../_shared/inquiry_state.ts';

type NextQuestion = { key: string | null; text: string; options: string[] | null; suggested?: string | null } | null;

export function fourQuestions(c: { ar: boolean; prevBrief: any; out: any; llmParseOk: boolean; category: string | null; placed: string; text: string; emirate: string | null;
  status: string; interview: { details: Record<string, string>; asked_key: string | null } | null; turns: any[]; slotRecorded: string[]; allText: string; slotLang: 'en' | 'ar';
  nextQuestion: NextQuestion }) {
  const { ar, prevBrief, out, llmParseOk, category, placed, text, emirate, interview, turns, slotRecorded, allText, slotLang } = c;
  let { status, nextQuestion } = c;
  // ── THE SALES ENGINEER'S FOUR QUESTIONS (founder, 14 Sep 2026) ─────────────────────────────────
  // "do you require a warranty? do you require installation? do you have specific material in mind
  // ... maybe he doesnt even care, but our job is to ask." A request that has every field its
  // category needs is still not ready until these are answered too: the material of each main
  // component, installation where the trade installs, a warranty where one is sold, and the date it
  // is needed by. Asked here, AFTER the category's own checklist, one at a time with options to tap,
  // on the model path and the deterministic one alike. The answers are recorded under the sales
  // engineer and become the baseline the technical comparison judges quotes against
  // (_shared/intake_requirements.ts, docs/contracts/intake_answers.md).
  const reqLang = ar ? 'ar' : 'en';
  let reqAnswers: Answers = (prevBrief.req_answers && typeof prevBrief.req_answers === 'object') ? prevBrief.req_answers : {};
  // THE MODEL UNDERSTANDS THE FOUR ANSWERS (12 Nov 2026, founder rulings 1664/1666; LLM-first audit A7). It reads them
  // from the whole conversation on every turn (./slots.ts requirementsContract), so its reading is the answer: one
  // message can answer two questions, and an answer the customer changes replaces the earlier one when the model says so
  // (changed_answers, below; before this date the earlier one always won, so "actually two years" left the warranty at
  // one). A key the model leaves out keeps what an earlier turn recorded. Code reads the customer's words for these answers only when there is no model reading
  // this turn (OpenRouter down, or a reply we could not parse: llmParseOk false); with a reading, code takes only a
  // tapped option (intake_requirements.ts tappedAnswer). Prevented by:
  // the_four_questions_are_understood_by_the_model.test.ts
  // A RECORDED ANSWER CHANGES ONLY WHEN THE MODEL SAYS THIS MESSAGE CHANGED IT (independent review of #1979, 12 Nov 2026).
  // With the model's reading simply winning, a slip rewrote a confirmed answer: tapped "supply only", then "2 years" to the
  // warranty question, and a model that also returned installation "yes" saved "yes"; and "within a month" re-read on a
  // later turn moved the date forward from that day. The model is shown what is recorded and names, in "changed_answers",
  // each one the customer's message changes; only those (or the question this message answers) are replaced. Nothing here
  // reads the customer's words: it is the model's own declaration (slots.ts mergeRequirements).
  if (out && llmParseOk && category) reqAnswers = mergeRequirements(reqAnswers, requirementsFromModel(category, out.requirements), out.changed_answers, prevBrief.req_asked || null);
  // "I don't know" to the one of the four questions just asked is its not-sure answer, as it is "does not know" for a checklist spec
  // (unknownNow above; re-check of 15 Nov 2026, item 3): it was asked again for ever whenever the model did not file it.
  if (placed === 'added' && category && prevBrief.req_asked && text && saysDontKnow(text)) {
    const q = requirementQuestions(category).find((x) => x.key === prevBrief.req_asked);
    if (q && !reqAnswers[q.key]) reqAnswers = { ...reqAnswers, [q.key]: notSureAnswer(q) };
  }
  let reqAsked: string | null = null;
  // "6 LEFT" while the category questions still run counted every sales-engineer question as open,
  // including the three the customer had already stated (measured 21 Sep 2026, customer audit,
  // finding 8). With a model reading its answers are already in reqAnswers; with none, code's reading counts them.
  const stated = category && !llmParseOk ? statedAnswers(category, allText) : {};
  let reqRemaining: string[] = category ? requirementQuestions(category).filter((q) => !reqAnswers[q.key] && !stated[q.key]).map((q) => questionIn(q, reqLang)) : [];
  let reqProgress: { filled: number; total: number } | null = null;
  // NO EMIRATE, NO SILENT DEFAULT (independent review of #1979, 12 Nov 2026; A1). When a request would be ready and no
  // emirate is held (the model named none, or a value not on the list: "Dubai Marina", "UAE", two emirates), the location
  // is ASKED once, with the seven to tap, before the four questions; it is never skipped because a location detail
  // ("Al Barsha") is filled. Asked once: a second turn without one goes on, and the suppliers count across the UAE.
  let emirateAsked = prevBrief.emirate_asked === true;
  const emirateHeld = emirate || (!llmParseOk ? emirateOf(out?.brief?.emirate) : null);
  if (status === 'ready' && !emirateHeld && !emirateAsked) {
    const q = ar ? { key: 'emirate', text: 'في أي إمارة يقع موقع العمل؟', options: SEVEN_EMIRATES_AR } : { key: 'emirate', text: 'Which emirate is the job in?', options: SEVEN_EMIRATES };
    status = 'needs_info'; out.status = 'needs_info';
    out.assistant_message = (ar ? 'شكرًا، دوّنت ذلك. ' : 'Thanks, noted. ') + q.text;
    out.questions = [q.text]; out.missing = [q.text];
    nextQuestion = { key: q.key, text: q.text, options: q.options };
    emirateAsked = true;
  }
  if (status === 'ready' && category) {
    const known = { ...((interview && interview.details) || prevBrief.details || {}), ...((out.brief && out.brief.details) || {}) };
    const reqAskedCounts = askedTurnsByKey(turns);
    const rs = requirementsStep(category, reqAnswers, prevBrief.req_asked || null, text, known, reqLang, new Date(), allText,
      { modelRead: llmParseOk, asked: reqAskedCounts, recordedNow: slotRecorded.length > 0 || Object.keys(reqAnswers).some((k) => !(prevBrief.req_answers ?? {})[k]) });
    reqAnswers = rs.answers; reqRemaining = rs.remaining; reqProgress = { filled: rs.filled, total: rs.total };
    if (!rs.complete && rs.next) {
      const lead = rs.retry
        ? (ar ? 'لم أتمكن من مطابقة إجابتك مع أيٍّ من الخيارات. اختر أحد الخيارات أدناه، أو «لست متأكداً». ' : "I couldn't match that to one of the answers. Tap an option below, or Not sure. ")
        : !prevBrief.req_asked
          ? (ar ? 'شكرًا، دوّنت ذلك. بقيت أسئلة قصيرة عن المواد والتركيب والضمان والموعد، ليأتي كل عرض مطابقًا لما تريده تمامًا. ' : 'Thanks, noted. A few quick questions about materials, installation, warranty and timing, so every quote matches exactly what you want. ')
          : (ar ? 'شكرًا، دوّنت ذلك. ' : 'Thanks, noted. ');
      status = 'needs_info'; out.status = 'needs_info';
      // A question the model left unanswered is simply asked again: "I couldn't match that" is only ever said when code
      // alone read the reply (no model reading this turn) and could not (A7).
      out.assistant_message = (rs.unanswered ? '' : lead) + rs.next.text;
      out.questions = [rs.next.text];
      out.missing = rs.remaining;
      // suggested: what the trade or the checklist points to. The composer highlights it; only the
      // customer tapping it records it (founder, 14 Sep 2026: "we don't assume stuff").
      nextQuestion = { key: rs.next.key, text: rs.next.text, options: rs.next.options, suggested: rs.next.suggested };
      reqAsked = rs.next.key;
    } else if (!rs.complete) {
      // every open question is already waiting for its answer and this message answered something: noted, nothing asked
      status = 'needs_info'; out.status = 'needs_info';
      out.assistant_message = replyFromState('needs_info', null, slotLang, true);
      out.questions = []; out.missing = rs.remaining;
      reqAsked = prevBrief.req_asked || null;
    }
  }
  return { status, nextQuestion, reqAnswers, reqAsked, reqRemaining, reqProgress, emirateAsked };
}
