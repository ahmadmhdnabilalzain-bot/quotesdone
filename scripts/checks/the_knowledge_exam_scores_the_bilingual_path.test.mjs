// THE KNOWLEDGE EXAM SCORES THE BILINGUAL PATH (5 Oct 2026, it_engineer; ledger 1085 stage 1).
// Fails if the daily exam goes back to the English-only retriever, drops the gte vector from the fused call, loses the
// Arabic floor, lets the routine lower a floor, or scores without a time bound (150 x 67 ms overran the 8 s tick).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const FILE = 'scripts/sql/the_knowledge_exam_scores_the_bilingual_path_and_holds_an_arabic_floor.sql';
const x = readFileSync(FILE, 'utf8');
const i = x.indexOf('create or replace function public.fn_it_engineer_knowledge_recall_exam()');
const body = x.slice(i, x.indexOf('end $fn$;', i));

test('the exam reads the bilingual retriever with both vectors', () => {
  assert.ok(i >= 0, 'the exam routine is missing');
  assert.match(body, /public\.fn_reason_retrieve_ml\(q\.seat, q\.embedding_ml, q\.embedding, 6\)/);
  assert.ok(!/public\.fn_reason_retrieve\(/.test(body), 'the exam reads the English-only retriever again');
  assert.match(body, /where n <= 5/, 'recall is not @5');
});

test('the Arabic floor is set once by the first ml run and never lowered by the routine', () => {
  assert.match(x, /create table if not exists public\.seat_knowledge_recall_floor/);
  assert.match(body, /floor\(s\.ar \* 20\) \/ 20, v_day, s\.ar\) on conflict \(seat, lang\) do nothing/);
  assert.ok(!/update public\.seat_knowledge_recall_floor/.test(body), 'the routine rewrites a floor');
  assert.match(body, /s\.ar < greatest\(v_floor, 0\.10\)/, 'Arabic under its floor raises nothing');
  assert.match(body, /s\.en < 0\.35/, 'the English floor moved');
  assert.match(body, /path = 'ml' order by day desc/, 'a fall is compared across paths');
});

test('a beat is bound by time, and a missing ml vector is a finding', () => {
  assert.match(body, /exit when clock_timestamp\(\) - v_t > interval '4 seconds'/);
  assert.match(body, /'knowledge_recall:no_ml_vectors'/);
  for (const t of ['seat_knowledge_recall_floor']) {
    assert.ok(x.includes(`alter table public.${t} enable row level security`));
    assert.ok(x.includes(`revoke all on public.${t} from anon, authenticated`));
  }
  assert.match(x, /revoke execute on function public\.fn_it_engineer_knowledge_recall_exam\(\) from public, anon, authenticated;/);
  assert.match(readFileSync('scripts/kb/load_knowledge_eval_questions.mjs', 'utf8'), /action: 'query'/, 'the loader does not fill ml vectors');
});
