// EVERY SEAT EXAM IS LOADED FOR THE MONTHLY SELF-REVIEW.   seats: ceo, it_engineer · 10 Nov 2026 · ledger 1609 (P10)
//
// Measured 10 Nov 2026: knowledge/exams/{ceo,marketing,accountant,it_engineer,customer_support,sales_engineer}.json hold
// 119 / 78 / 109 / 109 / 96 / 122 items, public.seat_exam_item holds 0 rows, and every seat_self_review since October
// reads no_exam: the exams were written and never loaded (scripts/eval/seat_qualification_exam.mjs --load). This fails:
//   A. offline, when an exam names an entry its seat pack lacks or a fact the excerpt cannot carry (it could never pass),
//      or when the CEO pack loses its deliverability entries (warm-up, bounce and complaint, provider placement);
//   B. with a token, when production's seat_exam_item does not hold every item of every exam file (the load was skipped).
//   node --test scripts/checks/every_seat_exam_is_loaded_for_the_monthly_self_review.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { validateExam } from '../eval/seat_qualification_exam.mjs';
import { SEATS } from '../kb/verified_packs.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const json = (p) => JSON.parse(readFileSync(path.join(REPO, p), 'utf8'));
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(SUPABASE_TOKEN_FILE) ? readFileSync(SUPABASE_TOKEN_FILE, 'utf8') : '')).trim();

test('A. every exam can be passed by its own pack; the CEO pack knows deliverability', () => {
  for (const seat of SEATS) {
    const exam = json(`knowledge/exams/${seat}.json`);
    const pack = json(`knowledge/seats/${seat}.json`);
    assert.equal(exam.seat, seat);
    assert.deepEqual(validateExam(exam, new Map(pack.entries.map((e) => [e.id, e]))), [], `${seat}: an exam item could never pass`);
  }
  const ceo = new Set(json('knowledge/seats/ceo.json').entries.map((e) => e.id));
  for (const id of ['ceo:deliverability-warm-up', 'ceo:deliverability-bounce-and-complaint', 'ceo:deliverability-provider-placement'])
    assert.ok(ceo.has(id), `the CEO pack lost ${id} (it owns the invitation cap, ledger 1455)`);
});

test('B. production holds every exam item', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select seat, count(*)::int n, count(*) filter (where q_vec is null)::int no_vec from public.seat_exam_item group by seat`, { readOnly: true });
  const live = Object.fromEntries(rows.map((r) => [r.seat, r]));
  const missing = [];
  for (const seat of SEATS) {
    const want = json(`knowledge/exams/${seat}.json`).items.length;
    const got = live[seat]?.n ?? 0;
    if (got < want || (live[seat]?.no_vec ?? 0) > 0) missing.push(`${seat}: ${got} of ${want} loaded${live[seat]?.no_vec ? `, ${live[seat].no_vec} without a vector` : ''}`);
  }
  assert.deepEqual(missing, [], 'run: node scripts/eval/seat_qualification_exam.mjs --load (docs/runbooks/release-without-ci.md §2)');
});
