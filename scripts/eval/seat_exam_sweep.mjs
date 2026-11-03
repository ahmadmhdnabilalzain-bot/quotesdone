// THE FULL SEAT-EXAM SWEEP: every item of every seat's exam, answered from the seat's own knowledge, graded by code
// first. Seat: ceo (company knowledge). 3 Nov 2026, qualification matrix gap #13 / row E14
// (docs/release/qualification_matrix.md): "Seat exams cover 18 of 633 items".
//
// WHY A SECOND RUNNER. scripts/eval/seat_exam_llm_on.mjs asks 5-6 items a seat a day through think() on the live
// project, inside a capped rehearsal window; it needs SUPABASE_ACCESS_TOKEN and the OpenRouter gateway (on hold), and it
// writes its record to production. This sweep needs neither and writes nothing outside its own folder: the seat is
// stood in for by a model on the founder's subscription, given exactly what think() gives an internal seat --
//   * the SETTLED FACTS: knowledge/brief/company.md + knowledge/brief/seats.md + the seat's card
//     (knowledge/brief/seats/<seat>.md), the byte-stable prefix of every think() call (think.ts settledFacts);
//   * six SOURCES: the seat-pack rows retrieval hands it, each cut at 2,400 characters (think.ts EXCERPT_MAX, the
//     seat-pack cut of a_seats_own_entry_reaches_the_answer_whole.sql).
// WHAT IT DOES NOT MEASURE (say it with every score): retrieval rank. The live embedder (gte-small) is not reachable
// from a cloud session, so the six sources are the item's expected entries plus the nearest other entries of the same
// pack by a lexical (BM25) ranking. Whether gte-small would put the expected entry in the top 5 is measured by
// scripts/eval/seat_qualification_exam.mjs (live/staged) and matrix row E15, not here. This sweep measures whether the
// KNOWLEDGE the seat is handed lets it answer exactly, and whether any answer contradicts the canon.
//
// GRADING (code first; a model only where code cannot decide):
//   1. canon     an answer that contradicts the canon (seat_exam_canon.mjs: company_facts.json, company.md, seats.md,
//                COMPANY_CANON.md) FAILS, and no judge can overturn it;
//   2. facts     every expected fact present (the grader's normal form: case, punctuation, hyphens ignored);
//   3. figures   every AED amount and percentage the answer states appears in what the seat was given; one that does
//                not is a possible invention and goes to the judge, named;
//   pass by code = 1 + 2 + 3. Anything else that is not a canon failure goes to the JUDGE: an independent model that
//   sees the rubric (answer_must), the reference entries and the answer, never the answering prompt, and only after it
//   is calibrated (`calibrate`, >= 48 of 50 labelled cases right and <= 1 good answer flagged, matrix §4).
//
//   node scripts/eval/seat_exam_sweep.mjs audit                                   # the knowledge vs the canon, code only
//   node scripts/eval/seat_exam_sweep.mjs prepare --dir D [--wordings w.json] [--only ids.json]
//   node scripts/eval/seat_exam_sweep.mjs grade --dir D                           # D/answers/*.json -> D/code.json, D/judge/*.md
//   node scripts/eval/seat_exam_sweep.mjs score --dir D [--prior D0]              # D/judged/*.json -> D/score.json + table
//   node scripts/eval/seat_exam_sweep.mjs calibrate-prepare --dir D               # the labelled cases as a blind judge batch
//   node scripts/eval/seat_exam_sweep.mjs calibrate --dir D                       # D/calibration_verdicts.json vs the labels
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { readExams } from './seat_qualification_exam.mjs';
import { bankItemsFor, norm } from './seat_exam_bank.mjs';
import { canonFindings, isMoneyOrTerms, unsupportedFigures } from './seat_exam_canon.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const SEATS = ['ceo', 'customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing'];
export const K = 6;              // think() retrieves 6 rows a step
export const EXCERPT = 2400;     // think.ts EXCERPT_MAX: a seat-pack row reaches the answer at up to 2,400 characters
export const PASS_BAR = 0.98;    // matrix row E14: >= 98% per seat
export const CALIBRATION = 'tests/fixtures/seat_exam_judge_calibration.json';
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const json = (p) => JSON.parse(readFileSync(p, 'utf8'));

// ---- the items ---------------------------------------------------------------------------------------------------
/** Every item of every seat's exam, and the trade-distinction bank, with the wording the sweep asks it in. */
export function allItems() {
  const exams = Object.fromEntries(readExams().map((x) => [x.seat, x.items]));
  return SEATS.flatMap((seat) => [
    ...(exams[seat] ?? []).map((it) => ({ ...it, seat, bank: false })),
    ...bankItemsFor(seat).map((it) => ({ ...it, seat, bank: true, q_reworded: it.q_reworded ?? it.wordings?.[0] })),
  ]).map((it) => ({ ...it, money_terms: isMoneyOrTerms(it) }));
}

// ---- what the seat is given ---------------------------------------------------------------------------------------
export function settledFacts(seat) {
  const card = existsSync(join(ROOT, `knowledge/brief/seats/${seat}.md`)) ? read(`knowledge/brief/seats/${seat}.md`) : '';
  return ['# SETTLED COMPANY FACTS AND FOUNDER RULINGS (they override any SOURCE that contradicts them)',
    read('knowledge/brief/company.md'), read('knowledge/brief/seats.md'), card].join('\n\n');
}

/** The pool a seat's sources come from: its own pack, and for a bank item the trade's two packs. */
function poolFor(seat, item) {
  const own = json(join(ROOT, `knowledge/seats/${seat}.json`)).entries;
  if (!item.bank) return own;
  const t = item.trade;
  const trade = [`${t}.json`, `${t}.market.json`].filter((f) => existsSync(join(ROOT, 'knowledge/packs', f)))
    .flatMap((f) => json(join(ROOT, 'knowledge/packs', f)).entries);
  return [...trade, ...own];
}
// Served entries only (verified_packs.mjs isVerified: an unverified or low-confidence entry is never retrieved).
const served = (e) => e.verified !== false && e.confidence !== 'low';

const tok = (t) => String(t).toLowerCase().match(/[a-z0-9]+/g) ?? [];
const STOP = new Set('the a an and or of to in on for is are be by with what how when who which does do our we it this that can should as at from your you if not'.split(' '));
/** BM25 over topic + body: the lexical stand-in for gte-small, used only to choose the five neighbours. */
export function bm25(entries) {
  const docs = entries.map((e) => tok(`${e.topic} ${e.topic} ${e.body_en}`).filter((w) => !STOP.has(w)));
  const df = new Map(); docs.forEach((d) => new Set(d).forEach((w) => df.set(w, (df.get(w) ?? 0) + 1)));
  const avg = docs.reduce((s, d) => s + d.length, 0) / Math.max(1, docs.length);
  const tf = docs.map((d) => { const m = new Map(); d.forEach((w) => m.set(w, (m.get(w) ?? 0) + 1)); return m; });
  return (q) => {
    const qs = [...new Set(tok(q).filter((w) => !STOP.has(w)))];
    return entries.map((e, i) => {
      let s = 0;
      for (const w of qs) {
        const f = tf[i].get(w); if (!f) continue;
        const idf = Math.log(1 + (entries.length - df.get(w) + 0.5) / (df.get(w) + 0.5));
        s += idf * (f * 2.2) / (f + 1.2 * (0.25 + 0.75 * docs[i].length / avg));
      }
      return [e, s];
    }).sort((a, b) => b[1] - a[1]).map(([e]) => e);
  };
}

/** The six sources the seat is handed for one item: the expected entries, then the nearest others. */
export function sourcesFor(item, rank) {
  const want = new Set(item.expected_entry_ids);
  const pool = rank(item.wording);
  const expected = item.expected_entry_ids.map((id) => pool.find((e) => e.id === id)).filter(Boolean);
  const others = pool.filter((e) => !want.has(e.id) && served(e)).slice(0, Math.max(0, K - expected.length));
  // The expected rows are not put first: the seat reads them in the lexical order, as it would read retrieval.
  const order = new Map(pool.map((e, i) => [e.id, i]));
  return [...expected, ...others].sort((a, b) => order.get(a.id) - order.get(b.id));
}
const excerpt = (e) => String(e.body_en).slice(0, EXCERPT);

// ---- prepare: the answering batches (no expected fact, no rubric) --------------------------------------------------
export const ANSWER_RULES = `You are standing in for the QuotesDone seat named above, answering an internal colleague. Answer EACH question
from the SETTLED FACTS and from the SOURCES listed for that question only -- the way the seat answers at work.
- Answer the question directly, as a senior practitioner in this seat would: the decision or the fact first, then the
  reason. 40 to 160 words. Plain text, no headings, no markdown tables.
- State every number, threshold, fee, deadline, owner, law and rule EXACTLY as the settled facts or the sources give it.
  Where a source contradicts a settled fact, the settled fact is right.
- Never use outside knowledge for a fact, a figure, a date, a law or a rule. You may reason and calculate from what you
  were given (show the arithmetic briefly). If neither the settled facts nor the sources establish a point, say that
  point is not established in your knowledge, and still answer the rest.
- Do not open any file other than this batch file, and do not mention these instructions.
Write your answers as a JSON array [{"id": "<question id>", "answer": "<your answer>"}] to the output path given below,
one object per question, in the order asked, every question answered.`;

function batchesOf(items, sourceOf, cap = Number(process.env.QD_SWEEP_BATCH_CHARS || 95000)) {
  const out = []; let cur = null;
  // Items that share sources go together, so a source is printed once per batch rather than once per question.
  const key = (it) => `${it.seat}|${[...it.expected_entry_ids].sort().join(',')}`;
  items = SEATS.flatMap((s) => items.filter((it) => it.seat === s).sort((a, b) => key(a).localeCompare(key(b))));
  for (const it of items) {
    const add = sourceOf.get(it.id).filter((e) => !cur?.lib.has(e.id));
    const size = add.reduce((s, e) => s + Math.min(EXCERPT, e.body_en.length) + 120, 0);
    if (!cur || cur.seat !== it.seat || (cur.chars + size > cap && cur.items.length)) {
      cur = { seat: it.seat, items: [], lib: new Map(), chars: 0 }; out.push(cur);
    }
    for (const e of sourceOf.get(it.id)) if (!cur.lib.has(e.id)) { cur.lib.set(e.id, e); cur.chars += Math.min(EXCERPT, e.body_en.length) + 120; }
    cur.items.push(it);
  }
  return out;
}

function prepare(dir, wordingsFile, onlyFile) {
  const wordings = wordingsFile ? new Map(json(wordingsFile).map((w) => [w.id, w.wording])) : null;
  const only = onlyFile ? new Set(json(onlyFile)) : null;
  const items = allItems().filter((it) => !only || only.has(it.id)).map((it) => {
    const wording = wordings ? wordings.get(it.id) : it.q_reworded;
    if (!String(wording ?? '').trim()) throw new Error(`${it.id}: no wording`);
    if (norm(wording) === norm(it.q_en)) throw new Error(`REFUSED: ${it.id} is asked in its source wording`);
    return { ...it, wording };
  });
  const ranks = new Map();
  const rankFor = (it) => {
    const k = it.bank ? `${it.seat}/${it.trade}` : it.seat;
    if (!ranks.has(k)) ranks.set(k, bm25(poolFor(it.seat, it)));
    return ranks.get(k);
  };
  const sourceOf = new Map(items.map((it) => [it.id, sourcesFor(it, rankFor(it))]));
  for (const it of items) {
    const missing = it.expected_entry_ids.filter((id) => !sourceOf.get(it.id).some((e) => e.id === id));
    if (missing.length) throw new Error(`${it.id}: expected ${missing.join(', ')} not in its pool`);
  }
  mkdirSync(join(dir, 'batches'), { recursive: true });
  mkdirSync(join(dir, 'answers'), { recursive: true });
  const batches = batchesOf(items, sourceOf);
  const manifest = [];
  batches.forEach((b, n) => {
    const name = `${b.seat}-${String(n + 1).padStart(2, '0')}`;
    const lib = [...b.lib.values()].map((e) => `### SOURCE [${e.id}] ${e.topic}\n${excerpt(e)}`).join('\n\n');
    const qs = b.items.map((it) => `### QUESTION ${it.id}\nSources handed for this question: ${sourceOf.get(it.id).map((e) => e.id).join(', ')}\n${it.wording}`).join('\n\n');
    const text = `# Seat: ${b.seat} -- answering batch ${name} (${b.items.length} questions)\n\nOutput path: ${join(dir, 'answers', name + '.json')}\n\n## How to answer\n${ANSWER_RULES}\n\n## SETTLED FACTS\n${settledFacts(b.seat)}\n\n## SOURCE LIBRARY (each question names which of these it was handed; use only those)\n${lib}\n\n## QUESTIONS\n${qs}\n`;
    writeFileSync(join(dir, 'batches', name + '.md'), text);
    manifest.push({ batch: name, seat: b.seat, items: b.items.map((it) => it.id), chars: text.length });
  });
  // What each item was asked in and handed, for the grader (the batch file itself never carries a rubric).
  writeFileSync(join(dir, 'asked.json'), JSON.stringify(items.map((it) => ({ id: it.id, seat: it.seat, wording: it.wording,
    sources: sourceOf.get(it.id).map((e) => e.id) })), null, 1));
  writeFileSync(join(dir, 'manifest.json'), JSON.stringify(manifest, null, 1));
  for (const m of manifest) console.log(`${m.batch}: ${m.items.length} items, ${m.chars} chars`);
  console.log(`${items.length} items in ${manifest.length} batches -> ${dir}`);
}

// ---- grade: code first, the judge queue for what code cannot decide ------------------------------------------------
/** THE CODE GRADER for one answer. ctx: the text the seat was given (settled facts + its sources + the wording). */
export function gradeAnswer(item, answer, ctx) {
  const text = String(answer ?? '').trim();
  if (!text) return { verdict: 'fail', by: 'code', reason: 'no answer', canon: [], missing: item.expected_facts, unsupported: [] };
  const canon = canonFindings(text);
  const missing = item.expected_facts.filter((f) => !norm(text).includes(norm(f)));
  const unsupported = unsupportedFigures(text, ctx);
  if (canon.length) return { verdict: 'fail', by: 'code', reason: 'contradicts the canon', canon, missing, unsupported };
  if (!missing.length && !unsupported.length) return { verdict: 'pass', by: 'code', canon, missing, unsupported };
  return { verdict: 'judge', by: 'code', reason: [missing.length && 'expected fact not in these words', unsupported.length && 'figure not in what the seat was given'].filter(Boolean).join('; '), canon, missing, unsupported };
}

export const JUDGE_RULES = `You are an independent examiner grading answers given by a QuotesDone seat. For each case you get the
question, the RUBRIC (the points a correct answer must make), the KEY FACTS, the REFERENCE (the knowledge the answer
should rest on) and the ANSWER. Code has already checked the words; you see only the cases it could not decide.
PASS only when ALL of these hold:
  1. every RUBRIC point is made, in any words or language (a point made in substance passes; a point missing,
     contradicted or made only vaguely fails);
  2. nothing in the answer contradicts the REFERENCE, the rubric or a company fact (fees, deadlines, owners, rules);
  3. every number the answer states is in the reference or rubric, or is correct arithmetic on numbers given there.
     A CHECK line names any figure code could not find in what the seat was given: decide whether it is correctly
     derived (pass) or invented / wrong (fail).
Otherwise FAIL. Being cautious ("not established") about a point the rubric requires is a FAIL. Extra correct detail
is fine. Judge each case on its own.
Write {"<case id>": {"pass": true|false, "note": "<one line: what decided it>"}} for every case, as one JSON object,
to the output path given below. Do not open any other file.`;

export function judgeCase(c) {
  return `### CASE ${c.id}\nQUESTION: ${c.question}\nRUBRIC:\n${c.answer_must.map((m) => `- ${m}`).join('\n')}\nKEY FACTS: ${c.expected_facts.join(' | ')}\nREFERENCE:\n${c.reference}\nANSWER:\n${c.answer}\n${c.check ? `CHECK: ${c.check}\n` : ''}`;
}

function grade(dir) {
  const items = new Map(allItems().map((it) => [it.id, it]));
  const asked = new Map(json(join(dir, 'asked.json')).map((a) => [a.id, a]));
  const answers = new Map(readdirSync(join(dir, 'answers')).filter((f) => f.endsWith('.json'))
    .flatMap((f) => json(join(dir, 'answers', f))).map((a) => [a.id, a.answer]));
  const entryText = new Map();
  for (const s of SEATS) for (const e of json(join(ROOT, `knowledge/seats/${s}.json`)).entries) entryText.set(e.id, e);
  const tradeEntry = (id) => { const t = id.split(':')[0]; for (const f of [`${t}.json`, `${t}.market.json`]) { const p = join(ROOT, 'knowledge/packs', f); if (existsSync(p)) { const e = json(p).entries.find((x) => x.id === id); if (e) return e; } } return null; };
  const entry = (id) => entryText.get(id) ?? tradeEntry(id);
  const settled = new Map(SEATS.map((s) => [s, settledFacts(s)]));
  const results = [], queue = [];
  for (const [id, a] of asked) {
    const it = items.get(id);
    const ctx = [settled.get(it.seat), a.wording, ...a.sources.map((s) => excerpt(entry(s) ?? { body_en: '' }))].join('\n');
    const g = gradeAnswer(it, answers.get(id), ctx);
    results.push({ id, seat: it.seat, money_terms: it.money_terms, wording: a.wording, answer: answers.get(id) ?? null, ...g });
    if (g.verdict === 'judge') queue.push({ id, seat: it.seat, question: a.wording, answer_must: it.answer_must, expected_facts: it.expected_facts,
      reference: it.expected_entry_ids.map((x) => `[${x}] ${excerpt(entry(x) ?? { body_en: '' })}`).join('\n'),
      answer: answers.get(id), check: g.unsupported.length ? `figures not found in what the seat was given: ${g.unsupported.join(', ')}` : '' });
  }
  writeFileSync(join(dir, 'code.json'), JSON.stringify(results, null, 1));
  mkdirSync(join(dir, 'judge'), { recursive: true }); mkdirSync(join(dir, 'judged'), { recursive: true });
  const per = 30;
  for (let i = 0; i < queue.length; i += per) {
    const name = `judge-${String(i / per + 1).padStart(2, '0')}`;
    writeFileSync(join(dir, 'judge', name + '.md'), `# Judge batch ${name}\n\nOutput path: ${join(dir, 'judged', name + '.json')}\n\n## Rules\n${JUDGE_RULES}\n\n## CASES\n${queue.slice(i, i + per).map(judgeCase).join('\n')}`);
  }
  const n = (v) => results.filter((r) => r.verdict === v).length;
  const noAnswer = results.filter((r) => r.answer == null).map((r) => r.id);
  console.log(`graded ${results.length}: pass by code ${n('pass')}, fail by code ${n('fail')} (canon), to the judge ${n('judge')} in ${Math.ceil(queue.length / per)} batches${noAnswer.length ? `; NO ANSWER: ${noAnswer.join(', ')}` : ''}`);
}

// ---- score -------------------------------------------------------------------------------------------------------
export function finalVerdicts(code, judged) {
  return code.map((r) => {
    if (r.verdict !== 'judge') return { ...r, pass: r.verdict === 'pass' };
    const j = judged[r.id];
    return { ...r, pass: !!j?.pass, by: j ? 'judge' : 'unjudged', note: j?.note ?? 'not judged' };
  });
}
export function scoreTable(final) {
  const rows = SEATS.map((s) => {
    const r = final.filter((x) => x.seat === s), m = r.filter((x) => x.money_terms);
    const p = r.filter((x) => x.pass).length, mp = m.filter((x) => x.pass).length;
    return { seat: s, asked: r.length, passed: p, rate: r.length ? p / r.length : 0, mt_asked: m.length, mt_passed: mp,
      by_code: r.filter((x) => x.pass && x.by === 'code').length, by_judge: r.filter((x) => x.pass && x.by === 'judge').length,
      meets_bar: r.length > 0 && p / r.length >= PASS_BAR && mp === m.length };
  });
  return rows;
}
const pct = (x) => `${(100 * x).toFixed(1)}%`;
export const tableMd = (rows) => ['| seat | asked | passed | rate | money/terms | by code | by judge | bar (98%, 100% money/terms) |', '|---|---|---|---|---|---|---|---|',
  ...rows.map((r) => `| ${r.seat} | ${r.asked} | ${r.passed} | ${pct(r.rate)} | ${r.mt_passed}/${r.mt_asked} | ${r.by_code} | ${r.by_judge} | ${r.meets_bar ? 'MET' : 'NOT MET'} |`)].join('\n');

function score(dir) {
  const code = json(join(dir, 'code.json'));
  const judged = Object.assign({}, ...readdirSync(join(dir, 'judged')).filter((f) => f.endsWith('.json')).map((f) => json(join(dir, 'judged', f))));
  const final = finalVerdicts(code, judged);
  const rows = scoreTable(final);
  writeFileSync(join(dir, 'score.json'), JSON.stringify({ rows, failing: final.filter((r) => !r.pass).map(({ id, seat, money_terms, by, reason, note, canon, missing, unsupported, wording, answer }) => ({ id, seat, money_terms, by, reason, note, canon, missing, unsupported, wording, answer })) }, null, 1));
  console.log(tableMd(rows));
  const unj = final.filter((r) => r.by === 'unjudged').length;
  if (unj) console.log(`\n${unj} items sent to the judge have no verdict yet: the score is PARTIAL.`);
}

// ---- calibrate: the judge is used only after it passes this ---------------------------------------------------------
function calibratePrepare(dir) {
  const cases = json(join(ROOT, CALIBRATION)).cases;
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'calibration_batch.md'), `# Judge calibration batch\n\nOutput path: ${join(dir, 'calibration_verdicts.json')}\n\n## Rules\n${JUDGE_RULES}\n\n## CASES\n${cases.map(({ label: _l, planted: _p, ...c }) => judgeCase(c)).join('\n')}`);
  console.log(`${cases.length} cases -> ${join(dir, 'calibration_batch.md')}`);
}
export function calibration(cases, verdicts) {
  const good = cases.filter((c) => c.label === 'good'), bad = cases.filter((c) => c.label === 'bad');
  const right = cases.filter((c) => verdicts[c.id] && verdicts[c.id].pass === (c.label === 'good')).length;
  const flaggedGood = good.filter((c) => verdicts[c.id] && !verdicts[c.id].pass).map((c) => c.id);
  const missedBad = bad.filter((c) => !verdicts[c.id] || verdicts[c.id].pass).map((c) => c.id);
  const unanswered = cases.filter((c) => !verdicts[c.id]).map((c) => c.id);
  return { cases: cases.length, right, flaggedGood, missedBad, unanswered, ok: right >= cases.length - 2 && flaggedGood.length <= 1 && !unanswered.length };
}
function calibrate(dir) {
  const r = calibration(json(join(ROOT, CALIBRATION)).cases, json(join(dir, 'calibration_verdicts.json')));
  console.log(JSON.stringify(r, null, 1));
  if (!r.ok) { console.error('JUDGE NOT CALIBRATED: do not use its verdicts'); process.exit(1); }
}

// ---- audit: the knowledge itself against the canon, before any model is asked --------------------------------------
export function auditKnowledge() {
  const out = [];
  for (const s of SEATS) {
    for (const e of json(join(ROOT, `knowledge/seats/${s}.json`)).entries.filter(served)) for (const f of canonFindings(e.body_en)) out.push({ where: e.id, ...f });
    const card = `knowledge/brief/seats/${s}.md`;
    if (existsSync(join(ROOT, card))) for (const f of canonFindings(read(card))) out.push({ where: card, ...f });
  }
  for (const p of ['knowledge/brief/company.md', 'knowledge/brief/seats.md', 'knowledge/COMPANY_CANON.md']) for (const f of canonFindings(read(p))) out.push({ where: p, ...f });
  for (const it of allItems()) for (const f of canonFindings([...(it.answer_must ?? []), ...it.expected_facts].join('. '))) out.push({ where: `exam ${it.id}`, ...f });
  return out;
}

async function main() {
  const [cmd] = process.argv.slice(2);
  const at = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
  const dir = at('--dir');
  if (cmd !== 'audit' && !dir) { console.error('--dir <folder> is required'); process.exit(2); }
  if (cmd === 'audit') {
    const f = auditKnowledge();
    for (const x of f) console.log(`${x.where}: ${x.claim} says ${x.got}, canon ${x.want}: "${x.text}"`);
    const items = allItems();
    console.log(`${items.length} items (${items.filter((i) => i.money_terms).length} money/terms); ${f.length} contradictions of the canon in the knowledge`);
    process.exit(f.length ? 1 : 0);
  } else if (cmd === 'prepare') prepare(dir, at('--wordings'), at('--only'));
  else if (cmd === 'grade') grade(dir);
  else if (cmd === 'score') score(dir);
  else if (cmd === 'calibrate-prepare') calibratePrepare(dir);
  else if (cmd === 'calibrate') calibrate(dir);
  else { console.error('usage: seat_exam_sweep.mjs audit|prepare|grade|score|calibrate-prepare|calibrate (see the header)'); process.exit(2); }
}
if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) await main();
