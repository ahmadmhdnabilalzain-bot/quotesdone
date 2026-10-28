// AN 'ANY' EVAL QUESTION IS ANSWERED BY ANY ONE OF ITS ENTRIES, in the daily exam as in the eval (it_engineer, 27 Oct 2026).
// Measured: 14 pack questions said expected_mode 'any'; scripts/eval/knowledge_pack_eval.mjs scored them min(1, hits), while
// the daily exam (fn_it_engineer_knowledge_recall_exam) divided hits by the number of entries named, because the loader
// never carried the mode into public.seat_knowledge_eval_question. 13 market-pack questions joined them on 27 Oct, each
// with a base-pack entry that answers the question as asked. Pinned here, offline:
//   1. the loader writes expected_any from expected_mode;
//   2. the routine file is the canonical body with ONLY the recall expression changed, and scores expected_any as min(1, hits);
//   3. every 'any' question names 2+ entries and a why, and every 27 Oct alternate is its own trade's base-pack entry.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const FILE = 'scripts/sql/an_any_mode_eval_question_is_answered_by_any_of_its_entries.sql';
const CANON = 'scripts/sql/a_seats_own_pack_fills_half_of_every_retrieval.sql';
const body = (src) => { const i = src.indexOf('FUNCTION public.fn_it_engineer_knowledge_recall_exam()'); assert.ok(i > 0); return src.slice(i, src.indexOf('end $function$', i)); };

test('the loader carries expected_mode into expected_any, on insert and on conflict', () => {
  const s = read('scripts/kb/load_knowledge_eval_questions.mjs');
  assert.match(s, /any: q\.expected_mode === 'any'/);
  assert.match(s, /\(seat, pack, lang, question, expected, expected_any, embedding\)/);
  assert.match(s, /expected_any = excluded\.expected_any/);
});

test('the exam scores an any-mode question min(1, hits) and changes nothing else in the canonical body', () => {
  const mine = body(read(FILE)), canon = body(read(CANON));
  assert.match(mine, /case when q\.expected_any then least\(count\(distinct regexp_replace\(x->>'id', '@ar\$', ''\)\), 1\)::numeric/);
  assert.match(mine, /else count\(distinct regexp_replace\(x->>'id', '@ar\$', ''\)\)::numeric \/ \(select count\(distinct e\) from unnest\(q\.expected\) e\) end/);
  // every line of the canonical body survives, except the three of the old recall expression
  const gone = canon.split('\n').filter((l) => !mine.split('\n').includes(l));
  assert.equal(gone.length, 3, 'only the old recall expression may go:\n' + gone.join('\n'));
  assert.ok(gone.every((l) => /count\(distinct regexp_replace|\)::numeric$|unnest\(q\.expected\) e\)$/.test(l.trim())), gone.join('\n'));
  assert.match(read(FILE), /add column if not exists expected_any boolean not null default false/);
  assert.match(read(FILE), /revoke execute on function public\.fn_it_engineer_knowledge_recall_exam\(\) from public, anon, authenticated;/);
  assert.ok(!/^\s*(begin|commit)\s*;/im.test(read(FILE)), 'no transaction control in a replayable file');
});

test('every any-mode question names 2+ entries and a why; each 27 Oct alternate is its trade\'s own base-pack entry', () => {
  const dir = new URL('../../knowledge/packs/', import.meta.url);
  let any = 0, ruled = 0;
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.json'))) {
    const p = JSON.parse(readFileSync(new URL(f, dir), 'utf8'));
    for (const q of p.eval ?? []) {
      if (q.expected_mode !== 'any') continue;
      any++;
      assert.ok(q.expected_entry_ids.length >= 2 && String(q.why ?? '').trim().length > 40, `${f}: ${q.q_en}`);
      if (!q.alternate_ruled) continue;
      ruled++;
      assert.ok(f.endsWith('.market.json'), f);
      const base = JSON.parse(readFileSync(new URL(f.replace('.market.json', '.json'), dir), 'utf8')).entries.map((e) => e.id);
      const own = new Set(p.entries.map((e) => e.id));
      const alt = q.expected_entry_ids.filter((x) => !own.has(x));
      assert.equal(alt.length, 1, `${f}: one alternate per question`);
      assert.ok(base.includes(alt[0]) && alt[0].startsWith(p.trade + ':'), `${f}: ${alt[0]} is not ${p.trade}'s own base-pack entry`);
    }
  }
  assert.ok(any >= 27, `any-mode questions: ${any}`);
  assert.equal(ruled, 13);
});
