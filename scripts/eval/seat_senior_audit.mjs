// THE SENIOR SEAT AUDIT: is each seat as qualified as a senior human with 20 years in the role, and does it do what that
// senior hire would do to grow QuotesDone? Seat: ceo, 19 Oct 2026, founder ledger 1003 (two stages) and 894 (a
// professional checklist and an exam per seat).
//
// THE STANDARD is knowledge/standards/<seat>.json: the senior's qualifications, the professional checklist each
// qualification rests on (every item names the knowledge entries that hold it and the exam items that test it), and
// the contributions a senior hire would make, each mapped to the live seat_duty keys that make it.
//
// WHAT THIS MEASURES, per seat (production, read-only):
//   checklist  items whose every named entry is LOADED in the seat's own knowledge table (record_id = entry id):
//              894 says "100% of items backed by an ingested entry".
//   exam       items with at least one exam item.
//   retrieval  the seat_qualification_exam live pass rate (--retrieval <report.json>, optional).
//   answered   the LLM-on exam: knowledge/exams/judged/<seat>.json holds the reader's verdict on each answer the seat's
//              real models gave to the REWORDED question (scripts/eval/seat_exam_through_think.ts --answer --reworded).
//              No model judges a model: the CEO session read every answer against the item's answer_must.
//   duties     contributions whose every named duty exists in seat_duty and is enabled.
// VERDICT: 'senior' only when checklist = 100%, every item examined, answered >= 95%, and every contribution live.
// Otherwise the level is named with the evidence that falls short (ledger 1003: never call a seat senior without it).
//
//   node scripts/eval/seat_senior_audit.mjs [--seat ceo] [--retrieval report.json] [--json out.json]
// Exit 1 when a standard file is malformed (a reference that resolves to nothing): such a standard measures its
// author, not the seat.
import { readFileSync, readdirSync, existsSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => JSON.parse(readFileSync(join(REPO, p), 'utf8'));
export const SENIOR_BAR = 0.95;

/** Every reference in a standard that resolves to nothing, named. */
export function validateStandard(std, packIds, examIds) {
  const err = [];
  const cl = new Set();
  for (const c of std.checklist ?? []) {
    if (cl.has(c.id)) err.push(`${c.id}: duplicate`);
    cl.add(c.id);
    if (!c.entry_ids?.length) err.push(`${c.id}: no entry backs it`);
    if (!c.exam_items?.length) err.push(`${c.id}: no exam item tests it`);
    for (const e of c.entry_ids ?? []) if (!packIds.has(e)) err.push(`${c.id}: entry ${e} is not in the seat pack`);
    for (const x of c.exam_items ?? []) if (!examIds.has(x)) err.push(`${c.id}: exam item ${x} does not exist`);
  }
  for (const q of std.qualifications ?? []) for (const c of q.checklist ?? []) if (!cl.has(c)) err.push(`${q.id}: names checklist ${c}, which does not exist`);
  if (!std.qualifications?.length) err.push('no qualifications');
  if (!std.contributions?.length) err.push('no contributions');
  return err;
}

/** The verdict from the measured numbers. Pure, so the check can prove the bar. */
export function verdict(m) {
  const short = [];
  if (m.checklist_backed < 1) short.push(`checklist backed by loaded knowledge ${(100 * m.checklist_backed).toFixed(1)}% (< 100%)`);
  if (m.checklist_examined < 1) short.push(`checklist examined ${(100 * m.checklist_examined).toFixed(1)}% (< 100%)`);
  if (m.answered == null) short.push('no judged LLM-on exam');
  else if (m.answered < SENIOR_BAR) short.push(`LLM-on reworded exam ${(100 * m.answered).toFixed(1)}% (< 95%)`);
  if (m.contributions_live < 1) short.push(`contributions live ${(100 * m.contributions_live).toFixed(1)}% (< 100%)`);
  const level = !short.length ? 'senior' : (m.answered ?? 0) >= 0.8 && m.checklist_backed >= 0.9 ? 'mid-level' : 'junior';
  return { level, short };
}

async function main() {
  const at = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
  const { sql } = await import('../lib/db.mjs');
  const { SEAT_TABLE } = await import('../kb/verified_packs.mjs');
  const seats = readdirSync(join(REPO, 'knowledge', 'standards')).filter((f) => f.endsWith('.json')).map((f) => f.slice(0, -5))
    .filter((s) => !at('--seat') || s === at('--seat')).sort();
  const retrieval = at('--retrieval') ? Object.fromEntries(JSON.parse(readFileSync(at('--retrieval'), 'utf8')).seats.map((s) => [s.seat, s.rate])) : {};
  const bad = []; const out = [];
  for (const seat of seats) {
    const std = read(`knowledge/standards/${seat}.json`);
    const pack = read(`knowledge/seats/${seat}.json`);
    const exam = read(`knowledge/exams/${seat}.json`);
    const errs = validateStandard(std, new Set(pack.entries.map((e) => e.id)), new Set(exam.items.map((i) => i.id)));
    if (errs.length) { bad.push(...errs.map((e) => `knowledge/standards/${seat}.json: ${e}`)); continue; }
    const ids = [...new Set(std.checklist.flatMap((c) => c.entry_ids))];
    const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;
    const loaded = new Set((await sql(`select record_id from public.${SEAT_TABLE[seat]} where record_id = any(array[${ids.map(lit).join(',')}]::text[])`)).map((r) => r.record_id));
    const keys = [...new Set(std.contributions.flatMap((c) => c.duties ?? []))];
    const duties = keys.length ? new Map((await sql(`select to_jsonb(d) - 'last_result' j from public.seat_duty d where d.duty = any(array[${keys.map(lit).join(',')}]::text[])`)).map((r) => [r.j.duty, r.j])) : new Map();
    const enabled = (k) => { const d = duties.get(k); return !!d && d.enabled === true && !!d.last_ok_at; };
    const judgedFile = `knowledge/exams/judged/${seat}.json`;
    const judged = existsSync(join(REPO, judgedFile)) ? read(judgedFile) : null;
    const m = {
      seat,
      qualifications: std.qualifications.length,
      checklist: std.checklist.length,
      checklist_backed: std.checklist.filter((c) => c.entry_ids.every((e) => loaded.has(e))).length / std.checklist.length,
      checklist_examined: std.checklist.filter((c) => c.exam_items.length).length / std.checklist.length,
      exam_items: exam.items.length,
      retrieval: retrieval[seat] ?? null,
      answered: judged ? judged.items.filter((i) => i.verdict === 'pass').length / exam.items.length : null,
      contributions: std.contributions.length,
      contributions_live: std.contributions.filter((c) => c.duties?.length && c.duties.every(enabled)).length / std.contributions.length,
      not_loaded: ids.filter((e) => !loaded.has(e)),
      contributions_not_live: std.contributions.filter((c) => !(c.duties?.length && c.duties.every(enabled))).map((c) => `${c.id} ${c.what}`),
    };
    Object.assign(m, verdict(m));
    out.push(m);
    const pc = (x) => (x == null ? '  -  ' : `${(100 * x).toFixed(1)}%`);
    console.log(`${seat.padEnd(17)} ${m.level.padEnd(9)} checklist ${m.checklist} backed ${pc(m.checklist_backed)} examined ${pc(m.checklist_examined)} | retrieval ${pc(m.retrieval)} | LLM-on ${pc(m.answered)} | contributions live ${pc(m.contributions_live)}`);
    for (const s of m.short) console.log(`   short: ${s}`);
  }
  if (bad.length) { console.error(bad.join('\n')); process.exit(1); }
  if (at('--json')) writeFileSync(at('--json'), JSON.stringify(out, null, 1));
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) await main();
