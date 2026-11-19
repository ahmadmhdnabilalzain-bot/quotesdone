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
//      question is put to the model as judge (other words, Arabic), naming the answer's model so the gateway routes the
//      judge to another family (19 Nov 2026: run 1's judge was refused for want of it);
//   4. RECORDED (fn_seat_exam_record): a miss opens a fix; a pass closes an open fix that was made;
//   5. THE FIX: a miss whose fix has not been made writes the item's canon into the seat's own knowledge (fn_seat_exam_fix_lesson:
//      agent_knowledge, read only by that seat for an internal audience) with its vector, and sets the fix's fix_ref. The next
//      run asks the item first, in a new wording; a pass closes the fix, a second miss after the fix is the IT engineer's
//      finding (the duty's), because then the knowledge is there and the seat still does not use it.
// Spend: every model call is fn knowledge_exam in ai_cost_log; the duty stops the run at the week's AED cap
// (decision_policy seat_exam_weekly.week_aed_cap) before it posts again, and this batch stops at its own clock.
// This module holds no I/O: index.ts wires the database, the gateway and think(); seat_exam.test.ts drives it with stubs.

import { parseJson } from '../_shared/model_json.ts';
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
  /** The model's raw reply to the judging prompt. authorModel is the model that wrote the answer: the judge is a review
   *  class, so ai_gateway routes it to another family through it (counterpart_model) and refuses it without one. */
  judge: (system: string, input: string, authorModel: string) => Promise<{ content: string | null; error: string | null }>;
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

// THE TERMS OF ART A REWORDING MUST KEEP (it_engineer, 19 Nov 2026). Run 1 (15 Nov): ceo-exam-09 "Which strategic powers can
// QuotesDone realistically build first?" was reworded "Which strategic capabilities ...", and ceo-exam-10 "What is the buyer
// really hiring QuotesDone to do?" became "What service is the buyer bringing QuotesDone in to provide?". Each term named the
// framework its expected fact belongs to (counter-positioning is one of the strategic powers; "hiring a product to do a job"
// is the jobs-to-be-done question), so the seat answered a different question and both were marked misses. The rewording now
// gets the question's terms of art to keep verbatim, and code refuses a wording that drops one (recorded no_wording, no fix).
// Found by code, never by a model: a quoted phrase; a named ruling, ledger or instruction with its number; a snake_case id; a
// name (a capitalised word that does not open a sentence, or one with an inner capital or digit, joined across "of", "and",
// "the": "Federal Decree-Law No", "GitHub Actions", "NRM2"); a number; and the frameworks the exam asks about (FRAMEWORKS).
const FRAMEWORKS: RegExp[] = [
  /\bstrategic powers?\b/i, /\bcounter-?positioning\b/i, /\bswitching costs?\b/i, /\bnetwork (?:economies|effects?)\b/i,
  /\bscale economies\b/i, /\bcornered resources?\b/i, /\bprocess power\b/i, /\bjobs? to be done\b/i, /\bhir(?:e|es|ed|ing)\b/i,
  /\b(?:excess )?share of voice\b/i, /\breveal fee\b/i,
];
const CONNECTOR = /^(?:of|and|the)$/;
/** The question's terms of art, in the order they appear: what a rewording must carry unchanged. */
export function termsOfArt(q: string): string[] {
  const found: { t: string; at: number; test: (w: string) => boolean }[] = [];
  const has = (t: string) => (w: string) => norm(w).includes(norm(t));
  let rest = String(q ?? '');
  const take = (re: RegExp, test?: (m: string) => (w: string) => boolean) => {
    for (const m of [...rest.matchAll(re)]) {
      const t = (m[1] ?? m[0]).trim();
      found.push({ t, at: m.index!, test: (test ?? has)(t) });
      rest = rest.slice(0, m.index!) + ' '.repeat(m[0].length) + rest.slice(m.index! + m[0].length);
    }
  };
  take(/["\u201c]([^"\u201d]{3,})["\u201d]/g);
  take(/\b(?:ruling|ledger|instruction|founder_instruction|decision)s?\s+(?:no\.?\s*)?\d+/gi);
  take(/\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b/g);
  for (const re of FRAMEWORKS) {
    const g = new RegExp(re.source, 'gi');
    take(g, () => (w: string) => new RegExp(re.source, 'i').test(w));
  }
  const toks = [...rest.matchAll(/[\p{L}\p{N}][\p{L}\p{N}.,%'\u2019-]*/gu)];
  let run: { t: string; at: number }[] = [];
  const flush = () => {
    while (run.length && CONNECTOR.test(run[run.length - 1].t)) run.pop();
    if (run.length) found.push({ t: run.map((x) => x.t).join(' '), at: run[0].at, test: has(run.map((x) => x.t).join(' ')) });
    run = [];
  };
  toks.forEach((m, i) => {
    const raw = m[0];
    // "Stripe's" -> Stripe, "No." -> No, "Arabic-speaking" -> Arabic (a lower-case tail is not the name; Decree-Law is)
    const t = raw.replace(/(?:['\u2019]s)?[.,'\u2019-]*$/u, '').replace(/^(\p{Lu}[\p{L}\p{N}]*)-\p{Ll}[\p{L}-]*$/u, '$1');
    const before = rest.slice(0, m.index).trimEnd();
    const opens = i === 0 || /[.?!:]$/.test(before) || /[.?!:]$/.test(toks[i - 1][0]);
    if (/^\d[\d.,]*%?$/.test(t)) { flush(); found.push({ t, at: m.index!, test: has(t) }); return; }
    const named = t.length > 1 && /\p{Lu}/u.test(t) && (!opens || /.\p{Lu}|\d/u.test(t));
    if (named) run.push({ t, at: m.index! });
    else if (run.length && CONNECTOR.test(t)) run.push({ t, at: m.index! });
    else flush();
    if (/[.?!:]$/.test(raw)) flush();
  });
  flush();
  const seen = new Set<string>();
  return found.sort((a, b) => a.at - b.at).map((f) => f.t).filter((t) => !seen.has(norm(t)) && seen.add(norm(t)));
}
/** The terms of art of the question that the wording does not carry. */
export function droppedTerms(w: string, q: string): string[] {
  return termsOfArt(q).filter((t) => {
    const fw = FRAMEWORKS.find((re) => re.test(t));
    return fw ? !fw.test(w) : !norm(w).includes(norm(t));
  });
}

export const REWORD_SYSTEM = 'You write exam questions for the staff of QuotesDone, a UAE B2B procurement marketplace. '
  + 'Rewrite the QUESTION so it asks exactly the same thing with every constraint kept, in different words and a different '
  + 'sentence shape from the question and from every EARLIER WORDING. Do not add facts, hints, options or the answer. '
  + 'Keep every term of art exactly as the QUESTION writes it, never a synonym: named laws, decrees and standards, product, '
  + 'company and role terms, framework terms (strategic powers, the job a buyer is hiring a product to do, share of voice), '
  + 'numbers, identifiers and named rulings; every phrase in KEEP_VERBATIM must appear in your question unchanged. '
  + 'DROPPED_LAST_TIME, when given, lists the terms your last question left out: this time keep them. '
  + 'English, one question. Reply with one JSON object: {"wording": "<the new question>"}.';

export function rewordInput(item: Pick<ExamItem, 'q_en' | 'used_wordings'>, droppedLastTime: string[] = []): string {
  const keep = termsOfArt(item.q_en);
  return JSON.stringify({ question: item.q_en, ...(keep.length ? { keep_verbatim: keep } : {}),
    ...(droppedLastTime.length ? { dropped_last_time: droppedLastTime } : {}), earlier_wordings: item.used_wordings.slice(-12) });
}

/** The terms of art a fresh wording in the model's reply left out ([] when there is no fresh wording to judge). */
export function droppedFromReply(content: string | null, item: Pick<ExamItem, 'q_en' | 'used_wordings'>): string[] {
  const w = String(parseJson<{ wording?: unknown }>(content)?.wording ?? '').trim();
  return w && isFreshWording(w, item) ? droppedTerms(w, item.q_en) : [];
}

/** The wording out of the model's reply, or null when it is absent, not JSON, not fresh, or drops a term of art. */
export function parseWording(content: string | null, item: Pick<ExamItem, 'q_en' | 'used_wordings'>): string | null {
  const o = parseJson<{ wording?: unknown }>(content);
  if (!o) return null;
  const w = String(o.wording ?? '').trim();
  return isFreshWording(w, item) && !droppedTerms(w, item.q_en).length ? w : null;
}

export const JUDGE_SYSTEM = 'You grade one exam answer given by a member of staff. For each REQUIRED FACT say whether the '
  + 'ANSWER states it: the same meaning in other words or in Arabic counts; a contradiction, a hedge or a different figure '
  + 'does not. Reply with one JSON object: {"facts": [{"fact": "<the required fact, verbatim>", "present": true|false}]}.';

export function judgeInput(question: string, answer: string, facts: string[]): string {
  return JSON.stringify({ question, required_facts: facts, answer: answer.slice(0, 6000) });
}

/** The facts the judge found missing, or null when its reply cannot be read or does not grade every fact asked. */
export function parseJudge(content: string | null, facts: string[]): string[] | null {
  const o = parseJson<{ facts?: { fact?: unknown; present?: unknown }[] }>(content);
  if (!o) return null;
  const rows = o.facts ?? [];
  if (!Array.isArray(rows)) return null;
  const seen = new Map(rows.map((r) => [norm(r.fact), r.present === true]));
  if (!facts.every((f) => seen.has(norm(f)))) return null;
  return facts.filter((f) => seen.get(norm(f)) !== true);
}

export type BatchResult = {
  // missed: judged (or not answered) and failed; unjudged: answered, missed by the exact-phrase check, given no judge verdict
  // (fn_seat_exam_record counts it apart and opens no fix: every_seat_knows_the_facts_its_exam_asks.sql)
  asked: number; passed: number; missed: number; unjudged: number; no_wording: number; rewords_retried: number; lessons: number; lesson_errors: string[];
  stop: string | null; items: { item_id: string; seat: string; status: string; pass: boolean; graded_by: string; missing: string[] }[];
};

/** One post of the duty: asks the run's next items until none is left, the run must stop, or the clock is spent. */
export async function runExamBatch(deps: ExamDeps, runId: number, o: { budgetMs?: number; itemMs?: number; max?: number } = {}): Promise<BatchResult> {
  const t0 = deps.now();
  const budget = o.budgetMs ?? 100_000;
  const itemMs = o.itemMs ?? 45_000;
  const out: BatchResult = { asked: 0, passed: 0, missed: 0, unjudged: 0, no_wording: 0, rewords_retried: 0, lessons: 0, lesson_errors: [], stop: null, items: [] };
  while (out.asked < (o.max ?? 4)) {
    // An item takes up to itemMs (the wording, think()'s whole run, the judge): none is started that could not finish
    // inside the post's budget (the edge's 150 s wall kills a worker with nothing recorded). The first always starts.
    if (out.asked > 0 && deps.now() - t0 > budget - itemMs) { out.stop = 'clock'; break; }
    const { items, stop } = await deps.next(runId, 1);
    if (stop) { out.stop = stop; break; }
    const item = items[0];
    if (!item) { out.stop = 'all_asked'; break; }

    const rw = await deps.reword(REWORD_SYSTEM, rewordInput(item));
    let wording = parseWording(rw.content, item);
    // ONE RETRY FOR A DROPPED TERM (review of #2077, 19 Nov 2026). A wording refused only because it left out a term of art
    // is asked for once more, naming what it dropped; an outage or a stale wording is not. Twice refused, the item is
    // recorded no_wording, and fn_it_engineer_seat_exam_tick raises never_worded:<item> when that happens two runs in a row.
    const dropped = wording ? [] : droppedFromReply(rw.content, item);
    if (dropped.length) {
      out.rewords_retried++;
      wording = parseWording((await deps.reword(REWORD_SYSTEM, rewordInput(item, dropped))).content, item);
    }
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
      // THE JUDGE NAMES THE ANSWER'S AUTHOR (19 Nov 2026): without it ai_gateway refused every judge call of run 1 (400
      // review_needs_counterpart) and 13 right answers in other words were marked misses. An answer whose model is not known
      // is not judged (the gateway could not prove the judge's independence): it keeps the code verdict, which
      // fn_seat_exam_record counts as unjudged and opens no fix for (every_seat_knows_the_facts_its_exam_asks.sql).
      if (a.status === 'answered' && missing.length && a.model) {
        const j = await deps.judge(JUDGE_SYSTEM, judgeInput(wording, a.answer, item.expected_facts), a.model);
        const still = parseJudge(j.content, item.expected_facts);
        if (still) { missing = still; by = 'model'; }
      }
      row = { run_id: runId, item_id: item.item_id, seat: item.seat, wording, answer: a.answer, model: a.model,
              status: a.status, pass: a.status === 'answered' && !missing.length, graded_by: by, missing };
    }
    const rec = await deps.record(row);
    if (rec.error) { out.stop = 'record_failed: ' + rec.error; break; }
    out.asked++;
    if (row.pass) out.passed++;
    else if (row.status === 'answered' && row.graded_by === 'code') out.unjudged++;
    else if (row.status !== 'no_wording') out.missed++;
    if (rec.lesson_needed && rec.fix_id) {
      const l = await deps.lesson(rec.fix_id);
      if (l.knowledge_id) out.lessons++; else out.lesson_errors.push(`${item.item_id}: ${l.error ?? 'no row'}`);
    }
    out.items.push({ item_id: item.item_id, seat: item.seat, status: row.status, pass: row.pass, graded_by: row.graded_by, missing: row.missing });
  }
  return out;
}
