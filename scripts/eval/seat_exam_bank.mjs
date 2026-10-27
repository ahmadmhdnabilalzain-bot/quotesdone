// THE SEAT EXAM BANK (27 Oct 2026; seats sales_engineer and it_engineer; founder ledger 893, 894, 899).
//
// Pure helpers for scripts/eval/seat_exam_llm_on.mjs, kept apart so the check can import them without a token.
// Measured 27 Oct 2026: no exam item tested a trade's product distinctions (ledger 893/899) - the sales_engineer exam
// is about drawings, specs and the platform - and no run reported a score per ledger. Two things close that:
//   * knowledge/exams/bank/<seat>_*.json add items to a seat's exam. The first is the trade-distinction bank of
//     sales_engineer (ledger 893/899), whose expected entries are TRADE pack entries (knowledge/packs), which the seat
//     exam files cannot name (their validator admits only the seat's own pack).
//   * every item can be asked without a newly authored wording: q_reworded, then the item's `wordings`, each used once.
// Ledger 894 (every seat's professional knowledge for its own work) is scored over each seat's own exam file.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const BANK_DIR = join(ROOT, 'knowledge/exams/bank');
// The grader's normal form: case, punctuation and hyphenation ignored ("title-block" = "title block").
export const norm = (t) => String(t ?? '').toLowerCase().replace(/[\W_]+/gu, '');

export const bankFiles = (dir = BANK_DIR) => (existsSync(dir) ? readdirSync(dir).filter((f) => /^[a-z_]+\.json$/.test(f)).sort() : [])
  .map((f) => ({ file: f, ...JSON.parse(readFileSync(join(dir, f), 'utf8')) }));

/** A seat's bank items, each carrying its ledgers (its own, else the bank's). */
export const bankItemsFor = (seat, dir) => bankFiles(dir).filter((b) => b.seat === seat)
  .flatMap((b) => b.items.map((it) => ({ ...it, ledger: it.ledger ?? b.ledger })));

/** The ledgers an item scores: its own `ledger`, else 894 (the seat's professional knowledge for its own work). */
export const ledgersOf = (it) => (it?.ledger?.length ? it.ledger : [894]);

/** The bank's candidate wordings for an item, in order: q_reworded, then wordings[]. */
export const bankWordings = (it) => [it.q_reworded, ...(it.wordings ?? [])].filter((w) => String(w ?? '').trim());

/** The first bank wording that is neither source question nor ever asked; null when the bank is used up. */
export function freshBankWording(it, usedWordings = []) {
  const used = new Set([it.q_en, it.q_ar, ...usedWordings].map(norm));
  return bankWordings(it).find((w) => !used.has(norm(w))) ?? null;
}

/** Pass rates per seat and per ledger from graded results [{id, seat, pass}]. */
export function scoreResults(results, itemOf) {
  const seats = {}, ledgers = {};
  const add = (o, k, pass) => { o[k] ??= { asked: 0, passed: 0 }; o[k].asked++; if (pass) o[k].passed++; };
  for (const r of results) {
    add(seats, r.seat, r.pass);
    for (const l of ledgersOf(itemOf(r.id))) add(ledgers, String(l), r.pass);
  }
  const rate = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, { ...v, rate: +(v.passed / v.asked).toFixed(3) }]));
  return { seats: rate(seats), ledgers: rate(ledgers) };
}

/** Every refusal for a bank against the trade packs: unknown entry, unserved entry, a fact the entry does not hold. */
export function validateBank(bank, entries) {
  const err = [], ids = new Set();
  for (const it of bank.items ?? []) {
    if (ids.has(it.id)) err.push(`${it.id}: duplicate id`);
    ids.add(it.id);
    for (const f of ['q_en', 'q_ar', 'trade']) if (!String(it[f] ?? '').trim()) err.push(`${it.id}: ${f} missing`);
    if (!it.expected_facts?.length) err.push(`${it.id}: no expected facts`);
    if (!it.answer_must?.length) err.push(`${it.id}: no answer_must`);
    if ((it.wordings ?? []).length < 2) err.push(`${it.id}: fewer than 2 bank wordings`);
    const ws = [it.q_en, ...(it.wordings ?? [])].map(norm);
    if (new Set(ws).size !== ws.length) err.push(`${it.id}: a bank wording repeats the question or another wording`);
    for (const id of it.expected_entry_ids ?? []) {
      const e = entries.get(id);
      if (!e) { err.push(`${it.id}: ${id} is not in any trade pack`); continue; }
      if (e.verified === false || e.confidence === 'low') err.push(`${it.id}: ${id} is not served (unverified or low confidence)`);
      if (!id.startsWith(`${it.trade}:`)) err.push(`${it.id}: ${id} is not a ${it.trade} entry`);
    }
    const text = norm((it.expected_entry_ids ?? []).map((id) => entries.get(id)?.body_en ?? '').join(' '));
    for (const f of it.expected_facts ?? []) if (!text.includes(norm(f))) err.push(`${it.id}: fact "${f}" is not in its expected entry`);
  }
  return err;
}
