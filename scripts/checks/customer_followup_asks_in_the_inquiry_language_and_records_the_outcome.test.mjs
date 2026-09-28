// THE FOLLOW-UP AND THE WIN-BACK SPEAK THE INQUIRY'S LANGUAGE, GO THROUGH THE ONE DOOR, AND RECORD THE ANSWER.
// customer_support, 29 Sep 2026, founder_instruction 1013 item 1. Offline: reads the SQL file and the edge function.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * a message picks its language from the customer's registration instead of the inquiry (fn_customer_message_lang);
//   * a message is written straight into notifications, skipping fn_customer_support_duty_send (which records each
//     stage once and refuses a suppressed address through fn_email_sendable);
//   * the answer stops reaching fn_outcome_record, or a "not yet" starts recording one;
//   * a model is called (the founder: plain code, no LLM);
//   * the page's GET path records an answer (a mail scanner opening the link would answer for the customer);
//   * a new routine loses its pinned search_path or its revoke, the table loses RLS or its policy;
//   * the file carries both, or neither, of a pending note and a MANIFEST line.
//   node --test scripts/checks/customer_followup_asks_in_the_inquiry_language_and_records_the_outcome.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const NAME = 'customer_support_asks_whether_the_customer_hired_and_nudges_a_quiet_one_by_their_trades';
const SQL = readFileSync(join(REPO, 'scripts/sql', NAME + '.sql'), 'utf8');
const EDGE = readFileSync(join(REPO, 'supabase/functions/customer_followup/index.ts'), 'utf8');
const body = (fn) => {
  const i = SQL.indexOf(`function public.${fn}(`);
  assert.ok(i >= 0, `${fn} is not defined in the file`);
  return SQL.slice(i, SQL.indexOf('$fn$;', i));
};

test('every message is in the inquiry language and goes through the one door', () => {
  for (const fn of ['fn_customer_support_followup_tick', 'fn_customer_support_winback_tick']) {
    const b = body(fn);
    assert.match(b, /fn_customer_message_lang\(/, `${fn} does not take the inquiry's language`);
    assert.match(b, /fn_customer_support_duty_send\(/, `${fn} does not send through fn_customer_support_duty_send`);
    assert.doesNotMatch(b, /insert into public\.notifications/, `${fn} writes a notification directly`);
    assert.match(b, /not coalesce\(c\.banned, false\)/, `${fn} selects banned customers`);
    assert.match(b, /qd\.duty_fixtures/, `${fn} lost the fixture guard`);
  }
  assert.match(body('fn_customer_message_lang'), /fn_inquiry_locale\(p_inquiry\)/, 'the language does not come from the inquiry first');
});

test('the answer is an outcome; "not yet" is not', () => {
  const b = body('fn_customer_followup_answer');
  assert.match(b, /if p_hired in \('yes', 'no'\) then[\s\S]*fn_outcome_record\('inquiries'/, 'a definite answer does not reach fn_outcome_record');
  assert.match(b, /if f\.hired in \('yes', 'no'\) then return/, 'a later tap can overwrite the first definite answer');
});

test('plain code: no model anywhere', () => {
  for (const s of [SQL, EDGE]) assert.doesNotMatch(s, /fn_seat_duty_reason|fn_reason_hold|ai_gateway|_shared\/llm|think\(/);
});

test('the page records only on POST', () => {
  const get = EDGE.indexOf("req.method === 'GET'");
  const rpc = EDGE.indexOf("'fn_customer_followup_answer'");
  assert.ok(get > 0 && rpc > get, 'the answer RPC is reachable before the GET branch returns');
});

test('routines pinned and revoked, the table closed, one of pending note or MANIFEST line', () => {
  for (const [, fn] of SQL.matchAll(/create or replace function public\.(\w+)\(([^)]*)\)/g)) {
    const i = SQL.indexOf(`function public.${fn}(`);
    const head = SQL.slice(i, SQL.indexOf(' as $fn$', i) + 8);
    assert.match(head, /set search_path to 'public', 'pg_temp'/, `${fn} has no pinned search_path`);
    if (fn !== 'fn_customer_support_winback_tick') assert.match(SQL, new RegExp(`revoke execute on function public\\.${fn}\\(`), `${fn} is not revoked`);
  }
  assert.match(SQL, /alter table public\.customer_followup enable row level security/);
  assert.match(SQL, /create policy customer_followup_service_role_only on public\.customer_followup[\s\S]{0,80}using \(false\) with check \(false\)/);
  assert.match(SQL, /revoke all on public\.customer_followup from anon, authenticated/);
  const pending = existsSync(join(REPO, 'scripts/sql/pending', NAME + '.txt'));
  const listed = readFileSync(join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8').includes(`scripts/sql/${NAME}.sql`);
  assert.ok(pending !== listed, 'exactly one of a pending note and a MANIFEST line');
});
