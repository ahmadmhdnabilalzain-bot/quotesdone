// THE SEAT EXAM, MODEL ON (ledger 1084, 19 Oct 2026). Seat: it_engineer. Replaces the retired retrieval-only exam
// (seat_qualification_exam.mjs / seat_exam_through_think.ts stop before any answer).
//
// The founder: no reason to test knowledge without the model; the exam tests the real answer; a correct reply to one
// exact wording proves nothing, so every question is asked in a fresh wording each run; a miss leads to an actual fix,
// not a record. Hence three steps, run daily by a Claude session on the subscription (never a paid judge):
//
//   1. plan    node scripts/eval/seat_exam_llm_on.mjs plan [--per-seat 6] [--seats a,b] > plan.json
//              The items due today: every item with an open fix first, then the least recently asked. Each carries
//              the question and every wording already used for it; it never carries the expected facts, so the
//              author of the new wording cannot lead the seat to them.
//   2. ask     node scripts/eval/seat_exam_llm_on.mjs ask --wordings w.json [--cap-usd 3]
//              w.json [{id, wording}] written fresh by the Claude session. Refused when a wording repeats the source
//              question or any earlier wording of that item. Each is put to the seat through think() end to end
//              (seat_exam_llm_on.ts) inside this run's capped rehearsal window, then graded BY CODE: pass = the
//              answer holds every expected fact of the item. Writes results.json; nothing is recorded yet.
//   3. record  node scripts/eval/seat_exam_llm_on.mjs record --results results.json [--judged j.json]
//              j.json {item_id: {pass, note}}: a Claude agent's judgement, ONLY for answers code failed (a fact said
//              in other words, or in Arabic). Records every ask; a miss opens a fix; a pass closes the item's open fix
//              once its fix_ref is set. Then the session makes the fix (a knowledge entry or a prompt change), sets
//              fix_ref with:   record --fixed <item_id>=<kind>:<commit or PR>   and the next run re-asks it.
//
// Where it records: public.seat_exam_asked / public.seat_exam_fix
// (scripts/sql/a_seat_exam_question_is_never_asked_in_the_same_wording.sql). Before that file is applied the record is
// <out>/history.json and the run says so.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { withRun, internalCred, REF, q } from '../lib/demo_factory.mjs';
import { mgmtRead, mgmtFixture } from '../lib/qd_guard.mjs';

process.env.QD_FIXTURES = '1';   // the run's window, its fixtures and its exam record are the only rows it writes
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const cmd = argv[0];
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const OUT = val('--out') || join(process.env.TEMP || '.', 'qd_seat_exam_llm_on');
mkdirSync(OUT, { recursive: true });
const SEATS = (val('--seats') || 'sales_engineer,customer_support,accountant,ceo,it_engineer,marketing').split(',');
const read = (sql) => mgmtRead(REF, sql);
const write = (sql, why) => mgmtFixture(REF, sql, why);

const exam = Object.fromEntries(SEATS.map((s) => [s, JSON.parse(readFileSync(join(ROOT, 'knowledge/exams', `${s}.json`), 'utf8')).items]));
const itemOf = (id) => { for (const s of SEATS) { const it = exam[s].find((x) => x.id === id); if (it) return { ...it, seat: s }; } return null; };
export const norm = (t) => String(t ?? '').toLowerCase().replace(/[\W_]+/gu, '');
// A fact is present when its words are, ignoring case, punctuation and hyphenation ("title-block" = "title block").
export const missingFacts = (answer, facts) => facts.filter((f) => !norm(answer).includes(norm(f)));

// ---- the record: the database once the tables are live, else <out>/history.json -------------------------------------
const HIST = join(OUT, 'history.json');
let live = null;
async function dbLive() {
  if (live === null) live = (await read(`select count(*)::int n from pg_tables where schemaname='public' and tablename in ('seat_exam_asked','seat_exam_fix')`))[0].n === 2;
  return live;
}
const hist = () => (existsSync(HIST) ? JSON.parse(readFileSync(HIST, 'utf8')) : { asked: [], fixes: [] });
async function asked() {
  return (await dbLive()) ? await read(`select item_id, wording, asked_at, pass from public.seat_exam_asked order by asked_at`) : hist().asked;
}
async function openFixes() {
  return (await dbLive()) ? await read(`select id, item_id, kind, fix_ref from public.seat_exam_fix where status='open'`) : hist().fixes.filter((f) => f.status === 'open');
}

if (cmd === 'plan') {
  const per = Number(val('--per-seat') || 6);
  const a = await asked(), open = new Set((await openFixes()).map((f) => f.item_id));
  const last = (id) => a.filter((x) => x.item_id === id).map((x) => String(x.asked_at)).sort().at(-1) || '';
  const plan = SEATS.flatMap((s) => exam[s]
    .map((it) => ({ id: it.id, seat: s, question: it.q_en, open_fix: open.has(it.id), last: last(it.id),
                    used_wordings: a.filter((x) => x.item_id === it.id).map((x) => x.wording) }))
    .sort((x, y) => (y.open_fix - x.open_fix) || x.last.localeCompare(y.last))
    .slice(0, Math.max(per, exam[s].filter((it) => open.has(it.id)).length))
    .map(({ last: _l, ...r }) => r));
  console.log(JSON.stringify(plan, null, 1));
  if (!(await dbLive())) console.error(`(record: ${HIST}; the tables are not applied yet)`);
} else if (cmd === 'ask') {
  const wf = val('--wordings'); if (!wf) throw new Error('ask needs --wordings <file>');
  const cap = Number(val('--cap-usd') || 3);
  const a = await asked();
  const items = JSON.parse(readFileSync(wf, 'utf8')).map((w) => {
    const it = itemOf(w.id); if (!it) throw new Error(`REFUSED: unknown item ${w.id}`);
    const used = [it.q_en, it.q_ar, ...a.filter((x) => x.item_id === w.id).map((x) => x.wording)].map(norm);
    if (!String(w.wording || '').trim() || used.includes(norm(w.wording))) throw new Error(`REFUSED: ${w.id} is not a fresh wording`);
    return { id: w.id, seat: it.seat, wording: String(w.wording).trim() };
  });
  const res = await withRun(async (run) => {
    const inF = join(OUT, `in_${run.tag}.json`), outF = join(OUT, `answers_${run.tag}.json`);
    writeFileSync(inF, JSON.stringify(items));
    const p = spawnSync('deno', ['run', '-A', '--node-modules-dir=none', join(ROOT, 'scripts/eval/seat_exam_llm_on.ts'), inF, outF],
      { cwd: ROOT, stdio: 'inherit', env: { ...process.env, QD_E2E_RUN_TAG: run.tag, QD_E2E_SECRET: await internalCred() } });
    if (p.status !== 0) throw new Error('the answering run failed');
    const spend = (await read(`select count(*)::int calls, coalesce(sum(cost_aed),0)::numeric(12,4) aed, string_agg(distinct model_used, ',') models from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`))[0];
    return { tag: run.tag, spend, answers: JSON.parse(readFileSync(outF, 'utf8')) };
  }, { capUsd: cap, minutes: 90, quiet: true });
  const results = res.answers.map((r) => {
    const it = itemOf(r.id), missing = r.status === 'answered' ? missingFacts(r.answer, it.expected_facts) : it.expected_facts;
    return { ...r, expected_facts: it.expected_facts, missing, pass: r.status === 'answered' && !missing.length, graded_by: 'code' };
  });
  const file = join(OUT, `results_${res.tag}.json`);
  writeFileSync(file, JSON.stringify({ ledger: 1084, run_tag: res.tag, measured_at: new Date().toISOString(), spend: res.spend, results }, null, 1));
  const by = (s) => results.filter((r) => r.seat === s);
  for (const s of SEATS) if (by(s).length) console.log(`${s}: ${by(s).filter((r) => r.pass).length}/${by(s).length} by code`);
  console.log(`spend ${JSON.stringify(res.spend)}\nresults: ${file}  (code misses go to a Claude agent for judgement, then: record --results ${file} --judged <j.json>)`);
} else if (cmd === 'record') {
  const fixed = val('--fixed');
  if (fixed) {
    const [, item, kind, ref] = /^([^=]+)=(knowledge_ingest|prompt):(.+)$/.exec(fixed) || [];
    if (!item) throw new Error('--fixed <item_id>=<knowledge_ingest|prompt>:<ref>');
    if (await dbLive()) await write(`update public.seat_exam_fix set kind=${q(kind)}, fix_ref=${q(ref)} where item_id=${q(item)} and status='open'`, 'exam fix recorded');
    else { const h = hist(); h.fixes.filter((f) => f.item_id === item && f.status === 'open').forEach((f) => Object.assign(f, { kind, fix_ref: ref })); writeFileSync(HIST, JSON.stringify(h, null, 1)); }
    console.log(`fix recorded for ${item}: ${kind} ${ref}`); process.exit(0);
  }
  const R = JSON.parse(readFileSync(val('--results'), 'utf8'));
  const J = val('--judged') ? JSON.parse(readFileSync(val('--judged'), 'utf8')) : {};
  const open = await openFixes();
  const h = hist();
  let n = 0;
  for (const r0 of R.results) {
    const j = !r0.pass && J[r0.id];
    const r = j ? { ...r0, pass: !!j.pass && r0.status === 'answered', graded_by: 'claude', note: j.note } : r0;
    const fix = open.find((f) => f.item_id === r.id);
    if (await dbLive()) {
      const id = (await write(`insert into public.seat_exam_asked (run_tag, seat, item_id, wording, answer, model, status, pass, graded_by, missing, fix_id)
        values (${q(R.run_tag)}, ${q(r.seat)}, ${q(r.id)}, ${q(r.wording)}, ${q(r.answer)}, ${q(r.model)}, ${q(r.status)}, ${r.pass}, ${q(r.graded_by)},
        ${r.missing.length ? `array[${r.missing.map(q).join(',')}]` : `'{}'`}::text[], ${fix ? fix.id : 'null'}) returning id`, 'exam ask recorded'))[0].id;
      if (!r.pass && !fix) await write(`insert into public.seat_exam_fix (seat, item_id, opened_run) values (${q(r.seat)}, ${q(r.id)}, ${q(R.run_tag)})`, 'exam miss opens a fix');
      if (r.pass && fix?.fix_ref) await write(`update public.seat_exam_fix set status='closed', closed_at=now(), closed_by_asked_id=${id} where id=${fix.id}`, 'exam fix closed by a passing re-ask');
    } else {
      const id = h.asked.length + 1;
      h.asked.push({ id, run_tag: R.run_tag, asked_at: R.measured_at, seat: r.seat, item_id: r.id, wording: r.wording, pass: r.pass, graded_by: r.graded_by, missing: r.missing });
      const f = h.fixes.find((x) => x.item_id === r.id && x.status === 'open');
      if (!r.pass && !f) h.fixes.push({ id: h.fixes.length + 1, seat: r.seat, item_id: r.id, opened_run: R.run_tag, status: 'open' });
      if (r.pass && f?.fix_ref) Object.assign(f, { status: 'closed', closed_by_asked_id: id });
    }
    n++;
  }
  if (!(await dbLive())) writeFileSync(HIST, JSON.stringify(h, null, 1));
  const fixesNow = await openFixes();
  console.log(`recorded ${n} asks of run ${R.run_tag}; open fixes now ${fixesNow.length}: ${fixesNow.map((f) => f.item_id).join(', ') || 'none'}${(await dbLive()) ? '' : `  (record: ${HIST})`}`);
} else if (process.argv[1]?.endsWith('seat_exam_llm_on.mjs')) {
  console.error('usage: seat_exam_llm_on.mjs plan|ask|record (see the header)'); process.exit(2);
}
