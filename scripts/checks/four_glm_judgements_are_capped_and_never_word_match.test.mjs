// THE FOUR GLM JUDGEMENTS ARE CAPPED, RUN ON GLM, AND NEVER WORD-MATCH (24 Sep 2026, it_engineer; founder's approval of
// the same day: quote spec match, repeat requests, supplier trade words, unknown-sender mail move to GLM 5.3 Flash,
// each capped; held = queued, never word-matched).
//
// WHAT FAILS IF THE CAUSE RETURNS (static, over the committed SQL and TypeScript):
//   * a kind loses its daily cap, or the cap is not asked before the model;
//   * a judgement's model step is billed to a class other than the GLM one;
//   * pg_trgm stops going first for repeats (a row it already flagged reaches the model);
//   * a supplier-trade code outside the taxonomy can be written;
//   * a held judgement is answered by a pattern (ilike / regex) instead of staying queued;
//   * email_triage sends an unknown sender to its old model path instead of the GLM queue.
//
//   node --test scripts/checks/four_glm_judgements_are_capped_and_never_word_match.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const strip = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '').replace(/\/\/.*$/, '')).join('\n');
const SQL = strip(read('scripts/sql/four_judgements_move_to_glm_each_capped_and_queued_when_held.sql'));
const TS = strip(read('supabase/functions/_shared/glm_judgements.ts'));
function body(name) {
  const i = SQL.indexOf(`create or replace function public.${name}(`);
  assert.ok(i >= 0, `${name} is not defined`);
  const rest = SQL.slice(i); const a = rest.indexOf('$fn$') + 4;
  return rest.slice(a, rest.indexOf('$fn$', a));
}
const KINDS = ['quote_spec_match', 'repeat_request', 'supplier_trade_words', 'unknown_sender_mail'];

test('every kind has a positive default daily cap, and an unknown kind has none', () => {
  const b = body('fn_glm_judgement_cap');
  for (const k of KINDS) assert.match(b, new RegExp(`when '${k}' then [1-9][0-9]*`), `${k} has no positive default cap`);
  assert.match(b, /else 0 end/);
  assert.match(body('fn_glm_judgement_take'), /where d\.calls < v_cap/, 'the cap is not enforced atomically');
});

test('the hold and the cap are asked before the model, and every model step is on the GLM class', () => {
  const j = TS.slice(TS.indexOf('export async function judge'));
  const gate = j.indexOf('deps.gate()'), take = j.indexOf("'fn_glm_judgement_take'"), model = j.indexOf('specMatch(');
  assert.ok(gate > 0 && take > gate && model > take, 'judge() must ask the hold, then the cap, then the model');
  assert.match(TS, /export const GLM_CLASS = 'routine_employee_reasoning';/);
  assert.match(TS, /taskClass: phase === 'verify' \? o\.taskClass : GLM_CLASS/);
  const policy = read('scripts/sql/every_seat_gets_the_model_its_own_work_needs.sql');
  assert.match(policy, /z-ai\/glm-5\.3-flash/, 'the GLM model is gone from the model policy');
});

test('pg_trgm goes first: a request trg_inquiry_enrich already flagged never reaches the model', () => {
  const b = body('trg_glm_repeat_request_enqueue');
  assert.match(b, /possible_duplicate/);
  assert.match(SQL, /create trigger z20_glm_repeat_request_enqueue after insert on public\.inquiries/);
});

test('a supplier-trade code is exact or nothing: the caller refuses and the database refuses', () => {
  assert.match(TS, /codes\.some\(\(c\) => !known\.has\(c\)\)/, 'glm_judgements.ts accepts a code outside the taxonomy');
  assert.match(body('fn_glm_judgement_resolve'), /from public\.taxonomy_trade t where t\.code = c and t\.active/);
  assert.match(body('fn_glm_judgement_resolve'), /status = 'map_offered'/, 'a single exact trade must be OFFERED, not mapped');
});

test('nothing is word-matched: no pattern match in the judgement routines or the module', () => {
  for (const f of ['fn_glm_judgement_resolve', 'trg_glm_repeat_request_enqueue', 'trg_glm_trade_words_enqueue', 'fn_glm_sender_known']) {
    assert.doesNotMatch(body(f), /\bilike\b|~\*|\bsimilar to\b|position\(|strpos\(/i, `${f} pattern-matches text`);
  }
  assert.doesNotMatch(TS, /\.includes\(input|\.test\(String\(input|match\(\/.*\/i\)/, 'glm_judgements.ts reads meaning from the input text');
});

test('email_triage queues an unknown sender for GLM before its old model call', () => {
  const s = strip(read('supabase/functions/email_triage/index.ts'));
  const known = s.indexOf("'fn_glm_sender_known'"), queue = s.indexOf("p_kind: 'unknown_sender_mail'"), old = s.indexOf('await llm(SYS');
  assert.ok(known > 0 && queue > known && old > queue, 'the unknown-sender branch must come before the old model call');
  assert.match(s, /continue;/);
});

test('the terminal state (three failed readings) hands every kind back to its owner - nothing waits forever', () => {
  const b = body('fn_glm_judgement_defer');
  // unknown mail: leaves the glm_queued mark (email_triage skips it) and goes to a person's review
  assert.match(b, /g\.kind = 'unknown_sender_mail'[\s\S]*update public\.inbound_messages set ai_category = 'other'[\s\S]*triaged_at = now\(\)/);
  assert.match(b, /insert into public\.agent_actions[\s\S]*'inbound_review'/);
  // supplier words: the proposal stays pending for the sales engineer, with the reason
  assert.match(b, /g\.kind = 'supplier_trade_words'[\s\S]*taxonomy_trade_proposal[\s\S]*status = 'pending'/);
  // spec cells: reported unread, never as meeting the request
  assert.match(body('fn_quote_spec_mismatches'), /'unread',[\s\S]*g\.status = 'failed'/);
});

test('a corrected cell stops counting: each comparison supersedes the quote\'s older cells', () => {
  assert.match(body('fn_glm_quote_spec_supersede'), /set status = 'superseded'[\s\S]*not \(subject_key = any/);
  assert.doesNotMatch(body('fn_quote_spec_mismatches'), /superseded/, 'the report must not read superseded rows');
  const qc = strip(read('supabase/functions/quote_compare/index.ts'));
  assert.ok(qc.indexOf("'fn_glm_quote_spec_supersede'") > qc.indexOf("p_kind: 'quote_spec_match'"), 'quote_compare must supersede after it enqueues the current cells');
});
