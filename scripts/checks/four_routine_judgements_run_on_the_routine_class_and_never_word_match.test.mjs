// THE FOUR ROUTINE JUDGEMENTS RUN ON THE ROUTINE CLASS, WAIT IN A QUEUE WHILE THE MODEL IS OFF, AND NEVER
// WORD-MATCH (24 Sep 2026, it_engineer; founder's approval of the same day: quote spec match, repeat requests,
// supplier trade words, unknown-sender mail move from code to the cheap internal class; held = queued, never
// word-matched). The class runs google/gemini-3.8-flash since founder_instruction 1056; the queue took its
// neutral name on 30 Sep 2026 (founder_instruction 1068). NO per-kind daily limit: the founder, 24 Sep 2026
// (founder_instruction 987), no caps on LLM spend - the volume is bounded by correct code.
//
// WHAT FAILS IF THE CAUSE RETURNS (static, over the committed SQL and TypeScript):
//   * a per-kind daily limit comes back, or the hold is not asked before the model;
//   * the three-failed-readings bound is lost (a row could be retried forever);
//   * a judgement's model step is billed to a class other than the routine one;
//   * pg_trgm stops going first for repeats (a row it already flagged reaches the model);
//   * a supplier-trade code outside the taxonomy can be written;
//   * a held judgement is answered by a pattern (ilike / regex) instead of staying queued;
//   * email_triage sends an unknown sender to its old model path instead of the judgement queue.
//
//   node --test scripts/checks/four_routine_judgements_run_on_the_routine_class_and_never_word_match.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const strip = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '').replace(/\/\/.*$/, '')).join('\n');
const SQL = strip(read('scripts/sql/the_retired_model_leaves_every_live_routine_and_the_judgement_queue_says_what_it_does.sql'));
const TS = strip(read('supabase/functions/_shared/routine_judgements.ts'));
function body(name) {
  const i = SQL.indexOf(`create or replace function public.${name}(`);
  assert.ok(i >= 0, `${name} is not defined`);
  const rest = SQL.slice(i); const a = rest.indexOf('$fn$') + 4;
  return rest.slice(a, rest.indexOf('$fn$', a));
}
const KINDS = ['quote_spec_match', 'repeat_request', 'supplier_trade_words', 'unknown_sender_mail'];

test('no per-kind daily limit exists, and three failed readings end a row', () => {
  assert.doesNotMatch(SQL, /judgement_take|judgement_cap|judgement_day|llm_cap_/, 'a per-kind daily limit is back');
  assert.doesNotMatch(TS, /judgement_take|daily cap/, 'judge() asks for a slot');
  assert.match(body('fn_routine_judgement_defer'), /attempts \+ 1 >= 3 then 'failed'/, 'the three-try loop bound is gone');
  for (const k of KINDS) assert.match(SQL, new RegExp(`'${k}'`), `${k} is not a queue kind`);
});

test('the hold is asked before the model, and every model step is on the routine class', () => {
  const j = TS.slice(TS.indexOf('export async function judge'));
  const gate = j.indexOf('deps.gate()'), model = j.indexOf('specMatch(');
  assert.ok(gate > 0 && model > gate, 'judge() must ask the hold, then the model');
  assert.match(TS, /export const ROUTINE_CLASS = 'routine_employee_reasoning';/);
  assert.match(TS, /taskClass: phase === 'verify' \? o\.taskClass : ROUTINE_CLASS/);
  // The class has a model: the founder's matrix (1056) routes the routine class to its plan A.
  const matrix = read('scripts/sql/every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql');
  assert.match(matrix, /routine_employee_reasoning/, 'the matrix no longer routes the routine class');
  assert.match(matrix, /google\/gemini-3\.8-flash/, 'the matrix no longer names the plan-A model');
});

test('pg_trgm goes first: a request trg_inquiry_enrich already flagged never reaches the model', () => {
  const b = body('trg_routine_repeat_request_enqueue');
  assert.match(b, /possible_duplicate/);
  assert.match(SQL, /on public\.inquiries rename to z20_routine_repeat_request_enqueue;/);
});

test('a supplier-trade code is exact or nothing: the caller refuses and the database refuses', () => {
  assert.match(TS, /codes\.some\(\(c\) => !known\.has\(c\)\)/, 'routine_judgements.ts accepts a code outside the taxonomy');
  assert.match(body('fn_routine_judgement_resolve'), /from public\.taxonomy_trade t where t\.code = c and t\.active/);
  assert.match(body('fn_routine_judgement_resolve'), /status = 'map_offered'/, 'a single exact trade must be OFFERED, not mapped');
});

test('nothing is word-matched: no pattern match in the judgement routines or the module', () => {
  for (const f of ['fn_routine_judgement_resolve', 'trg_routine_repeat_request_enqueue', 'trg_routine_trade_words_enqueue', 'fn_mail_sender_known']) {
    assert.doesNotMatch(body(f), /\bilike\b|~\*|\bsimilar to\b|position\(|strpos\(/i, `${f} pattern-matches text`);
  }
  assert.doesNotMatch(TS, /\.includes\(input|\.test\(String\(input|match\(\/.*\/i\)/, 'routine_judgements.ts reads meaning from the input text');
});

test('email_triage queues an unknown sender for judgement before its old model call', () => {
  const s = strip(read('supabase/functions/email_triage/index.ts'));
  const known = s.indexOf("'fn_mail_sender_known'"), queue = s.indexOf("p_kind: 'unknown_sender_mail'"), old = s.indexOf('await llm(SYS');
  assert.ok(known > 0 && queue > known && old > queue, 'the unknown-sender branch must come before the old model call');
  assert.match(s, /continue;/);
});

test('the terminal state (three failed readings) hands every kind back to its owner - nothing waits forever', () => {
  const b = body('fn_routine_judgement_defer');
  // unknown mail: leaves the routine_queued mark (email_triage skips it) and goes to a person's review
  assert.match(b, /g\.kind = 'unknown_sender_mail'[\s\S]*update public\.inbound_messages set ai_category = 'other'[\s\S]*triaged_at = now\(\)/);
  assert.match(b, /insert into public\.agent_actions[\s\S]*'inbound_review'/);
  // supplier words: the proposal stays pending for the sales engineer, with the reason
  assert.match(b, /g\.kind = 'supplier_trade_words'[\s\S]*taxonomy_trade_proposal[\s\S]*status = 'pending'/);
  // spec cells: reported unread, never as meeting the request
  assert.match(body('fn_quote_spec_mismatches'), /'unread',[\s\S]*g\.status = 'failed'/);
});

test('a corrected cell stops counting: each comparison supersedes the quote\'s older cells', () => {
  assert.match(body('fn_routine_quote_spec_supersede'), /set status = 'superseded'[\s\S]*not \(subject_key = any/);
  assert.doesNotMatch(body('fn_quote_spec_mismatches'), /superseded/, 'the report must not read superseded rows');
  const qc = strip(read('supabase/functions/quote_compare/index.ts'));
  assert.ok(qc.indexOf("'fn_routine_quote_spec_supersede'") > qc.indexOf("p_kind: 'quote_spec_match'"), 'quote_compare must supersede after it enqueues the current cells');
});
