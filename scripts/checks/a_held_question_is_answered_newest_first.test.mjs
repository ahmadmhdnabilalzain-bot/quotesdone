// A held question lives 14 days once the model is open, never expires by age under the founder's hold, and the newest
// due question is answered first. 6 Oct 2026, it_engineer (final check, founder_instruction 1119).
// Measured that day: 284 held questions, all with no expiry, 141 older than 7 days, claimed oldest-first, so the first
// day after the hold lifts would have paid to answer 23-24 Sep questions whose moment had passed.
// Reads the newest file (MANIFEST order, then the pending file) that defines each routine, code only (comments stripped).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/a_held_question_lives_fourteen_days_once_the_model_is_open_and_the_newest_is_answered_first.sql';
const manifest = readFileSync(join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8').split('\n').map((l) => l.trim()).filter((l) => l.endsWith('.sql'));
const order = manifest.includes(FILE) ? manifest : [...manifest, FILE];
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

/** The body of the LAST definition of a routine in apply order: the one production runs. */
function body(name) {
  let last = null;
  for (const f of order) {
    if (!existsSync(join(REPO, f))) continue;
    const t = code(readFileSync(join(REPO, f), 'utf8'));
    // Any dollar tag, matched to its own close (12 Oct 2026): a body copied from pg_get_functiondef is quoted
    // $function$, and a lazy `$fn$` match ran on into the NEXT routine's $fn$ body and asserted on that instead.
    const re = new RegExp(String.raw`create or replace function public\.${name}\([^$]*?\$(\w*)\$([\s\S]*?)\$\1\$`, 'gi');
    for (const m of t.matchAll(re)) last = m[2];
  }
  assert.ok(last, `${name} is defined somewhere`);
  return last;
}

test('the scheduler claims the newest due question first', () => {
  assert.match(body('fn_reason_held_due'), /order by h\.last_attempt_at nulls first, h\.created_at desc/i);
});

test('a filed question gets 14 days; a visitor chat keeps its hour', () => {
  const b = body('fn_reason_hold');
  assert.match(b, /site_assistant\.%' then now\(\) \+ interval '1 hour' else now\(\) \+ interval '14 days'/i);
});

test('under the founder hold nothing but a visitor chat expires by age, and an untried row never does', () => {
  const b = body('fn_reason_held_sweep');
  assert.match(b, /v_held boolean := [\s\S]*?'founder_hold'/i);
  assert.match(b, /if not v_held then[\s\S]*?fn_reason_held_expire\([\s\S]*?attempts > 0 and expires_at < now\(\)/i);
});

// Review of #1235 (6 Oct): a clock started at apply would expire ~172 untried questions on the first sweep after a
// lift later than ~20 Oct. The clock starts when the scheduler first claims the row.
test('the first claim starts the 14-day clock', () => {
  assert.match(body('fn_reason_held_due'), /expires_at = case when h\.attempts = 0[\s\S]*?then now\(\) \+ interval '14 days'/i);
});

// Review of #1235: a customer or supplier waiting is handed to the seat, never dropped.
test('a person-facing question opens a handoff to its seat when it expires', () => {
  const b = body('fn_reason_held_expire');
  assert.match(b, /insert into public\.agent_actions[\s\S]*?'held_question_expired'[\s\S]*?where g\.audience <> 'internal'/i);
});

test('the column default is 14 days', () => {
  assert.match(code(readFileSync(join(REPO, FILE), 'utf8')), /alter column expires_at set default now\(\) \+ interval '14 days'/i);
});
