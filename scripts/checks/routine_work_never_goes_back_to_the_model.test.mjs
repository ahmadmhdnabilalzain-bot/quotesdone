// ROUTINE WORK NEVER GOES BACK TO THE MODEL (24 Sep 2026, it_engineer; founder: routine work is code, the LLM only
// for real judgement; ledger 890: no word matching).
//
// WHAT FAILS IF THE CAUSE RETURNS (static, over the committed SQL and TypeScript):
//   * the retired model knowledge exam files a think() question again, or its seat_duty is re-enabled;
//   * fn_task_review files ceo.task_responsibility to the model instead of routing ownership by structure;
//   * the hourly lesson grouping reaches think(), or the weekly run reasons groups below the threshold;
//   * a weekly CEO report files at high stakes (a second, verify call), the review asks for more than the verdict and
//     the binding constraint, or an internal verdict spends the accountant's cross-family challenge call.
//
//   node --test scripts/checks/routine_work_never_goes_back_to_the_model.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
// A file carries a pending note until it is applied, then its MANIFEST line instead.
const pendingOrApplied = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt'))) ||
  readFileSync(join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim()).includes(f);
const FILE = 'scripts/sql/routine_work_is_code_and_the_model_answers_only_real_judgement.sql';
const stripped = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '').replace(/\/\/.*$/, '')).join('\n');
const code = (p) => stripped(readFileSync(join(REPO, p), 'utf8'));
const SQL = code(FILE);
/** The body of `create or replace function public.<name>(` up to its closing `$fn$` / `$function$`. */
function body(name) {
  const i = SQL.indexOf(`create or replace function public.${name}(`);
  assert.ok(i >= 0, `${name} is not defined in ${FILE}`);
  const rest = SQL.slice(i);
  const tag = rest.match(/\bas\s+(\$\w*\$)/i)[1];
  const a = rest.indexOf(tag) + tag.length;
  return rest.slice(a, rest.indexOf(tag, a));
}

test('the model knowledge exam stays retired', () => {
  assert.match(SQL, /update public\.seat_duty set enabled = false,[\s\S]*?where duty = 'it_engineer\.knowledge_exam'/, 'the exam duty is not disabled');
  const b = body('fn_it_engineer_duty_knowledge_exam');
  assert.ok(!/fn_reason_hold|fn_it_engineer_knowledge_exam\(|fn_seat_duty_reason/.test(b), 'the daily exam duty files a model question again');
});

test('task ownership is routed by structure, never filed to the model', () => {
  const b = body('fn_task_review');
  assert.ok(!/fn_reason_route_ask\(\s*'ceo',\s*'ceo\.task_responsibility'/.test(b), 'fn_task_review files ceo.task_responsibility to the model');
  assert.match(b, /fn_task_ownership_record\(p_task_id, t\.dept_key, v_author, nullif\(v_resp_choice, 'none'\)\)/, 'ownership is not recorded structurally');
  assert.match(b, /coalesce\(public\.fn_reason_route_answer\(v_resp_key\), 'none'\)/, 'an unanswered task does not fall to the structural owner');
});

test('lessons: the hourly run is SQL only; only the weekly run reasons, and only over the threshold', () => {
  const ts = code('supabase/functions/_shared/learning_loop.ts');
  const hourly = ts.slice(ts.indexOf("await d.rpc('fn_lesson_clusters'"), ts.indexOf('if (!opts.reason)'));
  assert.ok(!/think\(/.test(hourly), 'the grouping half calls think()');
  assert.ok(ts.indexOf('if (!opts.reason)') < ts.indexOf('await think('), 'think() is reached before the no-model return');
  assert.match(ts, /fn_lesson_clusters_to_reason/, 'the weekly run reasons groups below the threshold');
  const ping = stripped(functionSource('resilience_ping'));
  assert.match(ping, /async function learningGroupTick[\s\S]*?\{ reason: false \}/, 'the hourly tick is not the no-model run');
  assert.match(SQL, /\('learningGroup', interval '1 hour'/);
  assert.match(SQL, /\('learningDistil', interval '7 days'/, 'reasoning runs more often than weekly');
  assert.match(body('fn_lesson_clusters_to_reason'), /cardinality\(c\.case_ids\) >= greatest\(3, coalesce\(p_min_cases, 5\)\)/);
});

test('the weekly CEO reports: one normal-stakes call, one verdict line, challenge only on founder-bound calls', () => {
  for (const f of ['fn_ceo_target_forecast', 'fn_ceo_management_review', 'fn_ceo_pricing_monitor']) {
    const b = body(f);
    assert.equal((b.match(/fn_seat_duty_reason\(/g) ?? []).length, 1, `${f} files more than one think() question`);
    assert.match(b, /'\{"stakes":"normal"\}'::jsonb/, `${f} files at high stakes (a second, verify call)`);
  }
  const mr = body('fn_ceo_management_review');
  assert.equal((mr.match(/jsonb_build_object\('key',/g) ?? []).length, 1, 'the review asks the model for more than the binding constraint');
  assert.match(body('fn_ceo_review_applies'), /if v_choice in \('propose_change', 'tell_founder'\) then\s+v_review := public\.fn_seat_duty_cross_review/,
    'an internal verdict spends the cross-family challenge call');
});

test('replay-safe: revokes, pinned search_path, a probe, a pending note', () => {
  for (const m of SQL.matchAll(/create or replace function public\.(\w+)\(([^)]*)\)/g)) {
    const head = SQL.slice(SQL.indexOf(m[0])).split(/\bas \$/i)[0];
    assert.match(head, /security definer\s+set search_path to 'public', 'pg_temp'/i, `${m[1]}: no pinned search_path`);
    assert.match(SQL, new RegExp(`revoke execute on function public\\.${m[1]}\\(`), `${m[1]} is not revoked`);
  }
  assert.ok(!/^\s*(begin|commit)\s*;/im.test(SQL));
  assert.match(SQL, /then 'PROBE OK' else 'PROBE FAILED' end as verdict;\s*$/);
  assert.ok(pendingOrApplied(FILE), `${FILE} has neither a pending note nor a MANIFEST line`);
});

// The model exam's replacement (24 Sep 2026): the daily exam exists, is registered, and never reaches a model.
const EXAM = 'scripts/sql/every_seats_knowledge_is_examined_daily_by_retrieval_without_a_model.sql';
test('the daily knowledge exam exists, scores by retrieval, raises a finding, and calls no model', () => {
  const x = code(EXAM);
  const i = x.indexOf('create or replace function public.fn_it_engineer_knowledge_recall_exam()');
  assert.ok(i >= 0, 'the retrieval exam is missing');
  const b = x.slice(i, x.indexOf('end $fn$;', i));
  assert.ok(!/fn_reason_hold|fn_seat_duty_reason|fn_reason_route_ask|think|ai_gateway|openrouter/i.test(b), 'the exam calls the model');
  assert.match(b, /public\.fn_reason_retrieve\(q\.seat, q\.embedding, 6\)/, 'the exam does not use the seat\'s own retriever');
  assert.match(b, /where n <= 5/, 'recall is not @5');
  assert.match(b, /fn_it_engineer_finding_upsert\('knowledge_recall:' \|\| s\.seat/, 'a fall raises no finding');
  assert.match(b, /s\.en < 0\.35/, 'the floor moved from the 23 Sep baseline');
  assert.match(x, /\('it_engineer\.knowledge_recall', 'it_engineer', interval '1 day', 'fn_it_engineer_knowledge_recall_exam'/, 'the exam is not a daily duty');
  assert.ok(!/knowledge_pass_rate'[^;]*enabled = false/.test(x + SQL), 'the pass-rate duty was disabled');
  for (const t of ['seat_knowledge_eval_question', 'seat_knowledge_recall']) {
    assert.ok(x.includes(`alter table public.${t} enable row level security`), `${t} has no RLS`);
    assert.match(x, new RegExp(`create policy ${t}_service_role_only on public[.]${t}[^;]*using [(]false[)] with check [(]false[)]`), `${t} has no deny policy`);
    assert.ok(x.includes(`revoke all on public.${t} from anon, authenticated`), `${t} is not revoked`);
  }
  assert.match(x, /revoke execute on function public\.fn_it_engineer_knowledge_recall_exam\(\) from public, anon, authenticated;/);
  assert.match(x, /then 'PROBE OK' else 'PROBE FAILED' end as verdict;\s*$/);
  assert.ok(pendingOrApplied(EXAM), `${EXAM} has neither a pending note nor a MANIFEST line`);
  const loader = code('scripts/kb/load_knowledge_eval_questions.mjs');
  assert.match(loader, /makeEmbedder/, 'the loader does not embed by the free gte-small path');
  assert.ok(!/think\(|chat|completion/i.test(loader), 'the loader calls a model');
});
