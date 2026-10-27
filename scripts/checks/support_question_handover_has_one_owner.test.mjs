// A SUPPORT QUESTION HANDOVER HAS ONE OWNER (customer_support, #1462 review, 19 Oct 2026).
//
// agent_actions kind support_question_handover is filed by fn_cs_held_question_route and settled ONLY by the CEO's own
// duty (fn_ceo_support_handover_duty) and the reply gate's recorder (fn_ceo_support_reply_record), both claiming the
// row FOR UPDATE SKIP LOCKED. A general CEO worker that also closed it could close an item whose reply the gate is
// still holding, so the customer would never be answered.
//
// What fails if that breaks:
//   * any other SQL file names the kind in code (not comments)             -> this test
//   * either owner stops claiming its rows FOR UPDATE SKIP LOCKED          -> this test
//
//   node --test scripts/checks/support_question_handover_has_one_owner.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';

const DIR = 'scripts/sql/';
const OWNER = 'a_customer_support_question_reaches_a_person_in_fifteen_minutes';
const code = (f) => readFileSync(DIR + f, 'utf8').split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('no other SQL file settles support_question_handover', () => {
  const others = readdirSync(DIR).filter((f) => f.endsWith('.sql') && !f.startsWith(OWNER)
    && code(f).includes('support_question_handover'));
  assert.deepEqual(others, [], 'only ' + OWNER + '.sql may work this kind; exclude it from: ' + others.join(', '));
});

test('both owners claim the item FOR UPDATE SKIP LOCKED', () => {
  const body = code(OWNER + '.sql');
  for (const fn of ['fn_ceo_support_handover_duty', 'fn_ceo_support_reply_record']) {
    const start = body.indexOf('create or replace function public.' + fn);
    assert.ok(start >= 0, fn + ' is defined');
    const end = body.indexOf('end $fn$', start);
    assert.match(body.slice(start, end), /for update skip locked/i, fn + ' claims its rows');
  }
});
