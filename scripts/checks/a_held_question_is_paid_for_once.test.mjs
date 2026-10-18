// A held question is paid for once and our own test traffic never waits for a model (it_engineer, 5 Oct 2026).
// The LLM burn audit of 5 Oct 2026 found 627 held questions and 24 deliberations waiting for the hold to lift; about half
// were E2E harness traffic, repeats of one question, stale visitor chat or decisions a rule makes. Fails if any of the
// fixes is undone: a failed or expired row reopens on re-filing, a harness subject is filed, the claim stops being one
// row per question hash, the answer stops fanning out, the sweep stops running under the hold, a visitor chat loses its
// hour, the supply gap goes back to the model, or a fixture subject opens a second-seat review. Offline: committed tree.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const FILE = 'scripts/sql/a_held_question_is_paid_for_once_and_test_traffic_never_waits_for_a_model.sql';
const SQL = readFileSync(FILE, 'utf8');
const body = (name) => {
  const i = SQL.indexOf(`create or replace function public.${name}(`);
  assert.ok(i >= 0, `${name} is defined in ${FILE}`);
  return SQL.slice(i, SQL.indexOf('$fn$;', SQL.indexOf('$fn$', i) + 4));
};
const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split('\n').map((l) => l.trim());
const pendingNote = (() => { try { return readFileSync(FILE.replace('scripts/sql/', 'scripts/sql/pending/').replace(/\.sql$/, '.txt'), 'utf8'); } catch { return null; } })();

test('the file is either applied (MANIFEST) or pending (its note), never neither', () => {
  assert.ok(manifest.includes(FILE) || pendingNote, 'a MANIFEST line or a pending note');
});

test('a failed or expired row is never reopened, and a recent failure of the same question files nothing', () => {
  const hold = body('fn_reason_hold');
  assert.doesNotMatch(hold, /then 'held' else reasoning_held_question\.status/, 'the reopen branch is gone');
  assert.match(hold, /where reasoning_held_question\.status = 'held'/);
  assert.match(hold, /status = 'failed'[\s\S]*interval '7 days'/);
});

test('a harness subject is never filed; visitor chat lives an hour', () => {
  const hold = body('fn_reason_hold');
  assert.match(hold, /if public\.fn_reason_subject_is_fixture\(p_subject\) then\s+return null/);
  assert.match(hold, /site_assistant\.%' then now\(\) \+ interval '1 hour'/);
  assert.match(body('fn_reason_subject_is_fixture'), /fn_ai_subject_is_fixture/, 'only the harness marker counts, never typed text');
});

test('one claim per question hash, and the answer fans out to every row waiting on it', () => {
  assert.match(body('fn_reason_held_due'), /distinct on \(surface, coalesce\(qhash, id::text\)\)/);
  const res = body('fn_reason_held_resolve');
  assert.match(res, /'fanned_from', p_id/);
  assert.match(res, /p_result->>'fanned_from' is null/, 'a fanned row is never fanned again');
  assert.match(res, /'failed_with', p_id/, 'a failed leader takes its duplicates with it');
});

test('the sweep runs every tick, before the hold gate', () => {
  const think = readFileSync('supabase/functions/_shared/think.ts', 'utf8');
  const fn = think.slice(think.indexOf('export async function replayHeld'));
  const sweep = fn.indexOf("'fn_reason_held_sweep'"), gate = fn.indexOf('heldFromGate(');
  assert.ok(sweep > 0 && sweep < gate, 'fn_reason_held_sweep is called before the gate can return');
  const sw = body('fn_reason_held_sweep');
  for (const why of ['fixture, never paid for', 'its subject no longer exists', 'a visitor chat past its hour', 'one postmortem per fault'])
    assert.ok(sw.includes(why), `the sweep expires: ${why}`);
});

test('a supply gap nobody waits on is decided by code, never filed for the model', () => {
  const sg = body('fn_sales_engineer_supply_gap');
  assert.match(sg, /rule:nobody_waiting/);
  assert.doesNotMatch(sg, /fn_seat_duty_reason\(/);
});

test('a fixture subject opens no second-seat review; a withdrawal needs a fixture or a vanished subject', () => {
  const g = body('fn_high_stakes_gate');
  const fx = g.indexOf('fn_deliberation_subject_is_fixture'), open = g.indexOf('fn_high_stakes_challenge(');
  assert.ok(fx > 0 && fx < open, 'the fixture branch returns before a deliberation is opened');
  assert.match(body('fn_seat_deliberation_withdraw'), /if not \(v_fixture or v_gone\) then\s+raise exception/);
});
