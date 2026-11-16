// THE WEEKLY SEAT EXAM, RUN BY THE COMPANY ITSELF (it_engineer, 16 Nov 2026). Founder ledgers 1084 and 1443.
//
// 1084 (30 Sep): "the exam must test the real answer with the model on, and a mistake must lead to an actual fix, not just
// a record. Questions are never asked in the same wording." 1443 (1 Nov): the weekly Claude limit was spent in a day.
// Until this file the exam ran only inside the Claude scheduled task "QuotesDone weekly jobs" (a session on the founder's
// subscription wrote the wordings and judged the misses; scripts/eval/seat_exam_llm_on.mjs): seat_exam_asked holds 61 asks,
// the last on 1 Nov; the run of 9 Nov finished in 21 s and asked nothing.
//
// NOW the company runs it on its own clock. The duty it_engineer.seat_exam (scripts/sql/the_company_runs_its_own_weekly_seat_exam.sql)
// opens one run a week, chooses the items (an item with an open fix first, then the least recently asked) and posts to
// the it_engineer function, action 'seat_exam', until every planned item is asked. Each post runs runExamBatch below:
//   1. a FRESH WORDING by the model (fn knowledge_exam, the exam's own gateway credential), refused by code when it
//      repeats the source question or any wording already asked of the item;
//   2. the seat ANSWERS it through think() end to end, as at work;
//   3. GRADED BY CODE first (every expected fact present, ignoring case and punctuation); only a code miss on an answered
//      question is put to the model as judge (other words, Arabic);
//   4. RECORDED (fn_seat_exam_record): a miss opens a fix; a pass closes an open fix that was made;
//   5. THE FIX: a miss whose fix has not been made writes the item's canon into the seat's own knowledge (fn_seat_exam_fix_lesson:
//      agent_knowledge, read only by that seat for an internal audience) with its vector, and sets the fix's fix_ref. The next
//      run asks the item first, in a new wording; a pass closes the fix, a second miss after the fix is the IT engineer's
//      finding (the duty's), because then the knowledge is there and the seat still does not use it.
// Spend: every model call is fn knowledge_exam in ai_cost_log; the duty stops the run at the week's AED cap
// (decision_policy seat_exam_weekly.week_aed_cap) before it posts again, and this batch stops at its own clock.
// This module holds no I/O: index.ts wires the database, the gateway and think(); seat_exam.test.ts drives it with stubs.

export type ExamItem = {
  item_id: string; seat: string; q_en: string; expected_facts: string[];
  used_wordings: string[]; fix_id: number | null; fix_ref: string | null;
};
export type Answer = { status: string; answer: string; model: string | null; reason: string | null };
export type Recorded = { asked_id: number; fix_id: number | null; lesson_needed: boolean; error?: string | null };
export type AskRow = {
  run_id: number; item_id: string; seat: string; wording: string; answer: string; model: string | null;
  status: string; pass: boolean; graded_by: 'code' | 'model'; missing: string[];
};
export type ExamDeps = {
  /** The planned items of the run not yet asked, at most n; stop names why the run must not go on (cap, closed). */
  next: (runId: number, n: number) => Promise<{ items: ExamItem[]; stop: string | null }>;
  /** The model's raw reply to the rewording prompt (null content = the call failed). */
  reword: (system: string, input: string) => Promise<{ content: string | null; error: string | null }>;
  answer: (seat: string, wording: string, itemId: string) => Promise<Answer>;
  /** The model's raw reply to the judging prompt. */
  judge: (system: string, input: string) => Promise<{ content: string | null; error: string | null }>;
  record: (row: AskRow) => Promise<Recorded>;
  /** Writes the item's canon into the seat's knowledge and sets the fix's fix_ref; returns the knowledge row id. */
  lesson: (fixId: number) => Promise<{ knowledge_id: number | null; error: string | null }>;
  now: () => number;
};

/** Case, punctuation and hyphenation ignored ("title-block" = "title block"), as scripts/eval/seat_exam_llm_on.mjs. */
export const norm = (t: unknown) => String(t ?? '').toLowerCase().replace(/[\W_]+/gu, '');
export const missingFacts = (answer: string, facts: string[]) => facts.filter((f) => !norm(answer).includes(norm(f)));

/** A wording is fresh when it is not empty and differs from the source question and every wording already asked. */
export function isFreshWording(w: string, item: Pick<ExamItem, 'q_en' | 'used_wordings'>): boolean {
  const n = norm(w);
  if (n.length < 12) return false;
  return ![item.q_en, ...item.used_wordings].map(norm).includes(n);
}

export const REWORD_SYSTEM = 'You write exam questions for the staff of QuotesDone, a UAE B2B procurement marketplace. '
  + 'Rewrite the QUESTION so it asks exactly the same thing with every constraint kept, in different words and a different '
  + 'sentence shape from the question and from every EARLIER WORDING. Do not add facts, hints, options or the answer. '
  + 'English, one question. Reply with one JSON object: {"wording": "<the new question>"}.';

export function rewordInput(item: Pick<ExamItem, 'q_en' | 'used_wordings'>): string {
  return JSON.stringify({ question: item.q_en, earlier_wordings: item.used_wordings.slice(-12) });
}

/** The wording out of the model's reply, or null when it is absent, not JSON, or not fresh. */
export function parseWording(content: string | null, item: Pick<ExamItem, 'q_en' | 'used_wordings'>): string | null {
  if (!content) return null;
  const m = content.match(/\{[\s\S]*\}/);
  let w = '';
  try { w = String((JSON.parse(m ? m[0] : content) as { wording?: unknown }).wording ?? '').trim(); } catch { return null; }
  return isFreshWording(w, item) ? w : null;
}

export const JUDGE_SYSTEM = 'You grade one exam answer given by a member of staff. For each REQUIRED FACT say whether the '
  + 'ANSWER states it: the same meaning in other words or in Arabic counts; a contradiction, a hedge or a different figure '
  + 'does not. Reply with one JSON object: {"facts": [{"fact": "<the required fact, verbatim>", "present": true|false}]}.';

export function judgeInput(question: string, answer: string, facts: string[]): string {
  return JSON.stringify({ question, required_facts: facts, answer: answer.slice(0, 6000) });
}

/** The facts the judge found missing, or null when its reply cannot be read or does not grade every fact asked. */
export function parseJudge(content: string | null, facts: string[]): string[] | null {
  if (!content) return null;
  const m = content.match(/\{[\s\S]*\}/);
  let rows: { fact?: unknown; present?: unknown }[];
  try { rows = (JSON.parse(m ? m[0] : content) as { facts?: typeof rows }).facts ?? []; } catch { return null; }
  if (!Array.isArray(rows)) return null;
  const seen = new Map(rows.map((r) => [norm(r.fact), r.present === true]));
  if (!facts.every((f) => seen.has(norm(f)))) return null;
  return facts.filter((f) => seen.get(norm(f)) !== true);
}

export type BatchResult = {
  asked: number; passed: number; missed: number; no_wording: number; lessons: number; lesson_errors: string[];
  stop: string | null; items: { item_id: string; seat: string; status: string; pass: boolean; graded_by: string; missing: string[] }[];
};

/** One post of the duty: asks the run's next items until none is left, the run must stop, or the clock is spent. */
export async function runExamBatch(deps: ExamDeps, runId: number, o: { budgetMs?: number; max?: number } = {}): Promise<BatchResult> {
  const t0 = deps.now();
  const budget = o.budgetMs ?? 100_000;
  const out: BatchResult = { asked: 0, passed: 0, missed: 0, no_wording: 0, lessons: 0, lesson_errors: [], stop: null, items: [] };
  while (out.asked < (o.max ?? 4)) {
    // An item takes up to about 45 s (the wording, think()'s phases, the judge): none is started in the last 45 s.
    if (deps.now() - t0 > budget - 45_000) { out.stop = 'clock'; break; }
    const { items, stop } = await deps.next(runId, 1);
    if (stop) { out.stop = stop; break; }
    const item = items[0];
    if (!item) { out.stop = 'all_asked'; break; }

    const rw = await deps.reword(REWORD_SYSTEM, rewordInput(item));
    const wording = parseWording(rw.content, item);
    let row: AskRow;
    if (!wording) {
      // The question was not put: an outage of the wording step is recorded as such and opens no fix (it is not a
      // knowledge miss), so the run still finishes and the duty can count it.
      row = { run_id: runId, item_id: item.item_id, seat: item.seat, wording: '', answer: '', model: null, status: 'no_wording',
              pass: false, graded_by: 'code', missing: item.expected_facts };
      out.no_wording++;
    } else {
      const a = await deps.answer(item.seat, wording, item.item_id);
      let missing = a.status === 'answered' ? missingFacts(a.answer, item.expected_facts) : item.expected_facts;
      let by: 'code' | 'model' = 'code';
      if (a.status === 'answered' && missing.length) {
        const j = await deps.judge(JUDGE_SYSTEM, judgeInput(wording, a.answer, item.expected_facts));
        const still = parseJudge(j.content, item.expected_facts);
        if (still) { missing = still; by = 'model'; }
      }
      row = { run_id: runId, item_id: item.item_id, seat: item.seat, wording, answer: a.answer, model: a.model,
              status: a.status, pass: a.status === 'answered' && !missing.length, graded_by: by, missing };
    }
    const rec = await deps.record(row);
    if (rec.error) { out.stop = 'record_failed: ' + rec.error; break; }
    out.asked++;
    if (row.pass) out.passed++; else if (row.status !== 'no_wording') out.missed++;
    if (rec.lesson_needed && rec.fix_id) {
      const l = await deps.lesson(rec.fix_id);
      if (l.knowledge_id) out.lessons++; else out.lesson_errors.push(`${item.item_id}: ${l.error ?? 'no row'}`);
    }
    out.items.push({ item_id: item.item_id, seat: item.seat, status: row.status, pass: row.pass, graded_by: row.graded_by, missing: row.missing });
  }
  return out;
}
