// THE CEO QUEUE WORKER NEVER TOUCHES A SUPPORT HANDOVER (it_engineer, 19 Oct 2026). #1462's
// fn_ceo_support_handover_duty sends the customer the reply and closes support_question_handover itself;
// fn_ceo_queue_work closing or flagging one could end it before the customer is answered. Repository only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const src = readFileSync(fileURLToPath(new URL('../sql/the_ceo_queue_is_worked_closed_or_flagged_overdue.sql', import.meta.url)), 'utf8');
// The function body only, comments stripped, so the file's own header cannot satisfy or trip the check.
const body = src.slice(src.indexOf('as $fn$'), src.lastIndexOf('$fn$'))
  .split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('the kind list it closes does not name support_question_handover', () => {
  const kinds = body.match(/a\.kind in \(([^)]*)\)/);
  assert.ok(kinds, 'fn_ceo_queue_work names no kind list');
  assert.ok(!kinds[1].includes('support_question_handover'), 'fn_ceo_queue_work closes support handovers');
});

test('only an applied question for the same item supersedes', () => {
  assert.match(body, /n\.status = 'applied'/, 'supersession must count only applied questions');
  assert.match(body, /fn_ceo_queue_dedupe_stem\(n\.dedupe_key\) = q\.stem/, 'supersession must match the dedupe_key stem');
  assert.doesNotMatch(body, /'closed'|'answered'/, 'reasoning_held_question has no closed/answered status');
});

test('the worker closes its own overdue tasks', () => {
  assert.match(body, /update public\.ceo_task t\s+set state = 'done'/, 'nothing closes the daily CEO queue overdue task');
  assert.match(body, /t\.title like 'CEO queue overdue %'/, 'the close step must target its own task titles');
});

test('the overdue flag excludes support_question_handover', () => {
  assert.match(body, /a\.kind <> 'support_question_handover'/, 'the overdue update can flag a support handover');
});
