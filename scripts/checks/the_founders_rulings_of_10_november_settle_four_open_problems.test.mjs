// THE FOUNDER'S RULINGS OF 10 NOVEMBER STAY SETTLED (ceo, 10 Nov 2026).
//
// prevented by: scripts/sql/the_founders_rulings_of_10_november_settle_four_open_problems.sql
//
// Ruling 1559: "No bank statement reconciliation." The file retires the one SCHEDULED reconciliation duty,
// seat_duty accountant.receipt_bank_match (and unschedules its pg_cron job), records the ruling as
// company_policy_decision no_bank_statement_reconciliation, holds the bank duty's asks for a statement and every
// bank_balance item as `waiting` in fn_accountant_duty_settle, and stops fn_accountant_cash_truth_check's
// books-against-statement report. Ruling 1558: a resolved TEST-mode payment stays resolved in
// fn_accountant_reveal_reconcile_record, so the hourly sweep does not reopen what the accountant settled.
//
// This fails if a later file schedules the retired duty again (enables it, isolates it onto its own job, or
// schedules its job), or if a later definition of one of the three routines drops its rule. It reads the schema
// mirror (what production runs) and then every MANIFEST-listed file in apply order (what merges apply), code only:
// a comment that quotes a rule satisfies nothing (apply-discipline, section 7). Offline: no database is read.
//
//   node --test scripts/checks/the_founders_rulings_of_10_november_settle_four_open_problems.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const ROOT = join(import.meta.dirname, '..', '..');
const FILE = 'scripts/sql/the_founders_rulings_of_10_november_settle_four_open_problems.sql';
const stripComments = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const manifest = readFileSync(join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8').split('\n').map((l) => l.trim())
  .filter((l) => l && !l.startsWith('#')).map((l) => (l.startsWith('scripts/') ? l : `scripts/sql/${l}`));
const mine = stripComments(readFileSync(join(ROOT, FILE), 'utf8'));
// The mirror first, then the MANIFEST files in order: the LAST occurrence is what production ends with.
const code = stripComments(readSchemaMirror() + '\n'
  + manifest.filter((f) => existsSync(join(ROOT, f))).map((f) => readFileSync(join(ROOT, f), 'utf8')).join('\n'));
const statements = code.split(';');

const DUTY = 'accountant.receipt_bank_match';
const JOB = 'seat_duty:accountant.receipt_bank_match';

/** The last definition of a routine in apply order: from its `create or replace` to the end of its body. */
const lastDefinition = (name) => {
  const at = code.toLowerCase().lastIndexOf(`create or replace function public.${name}(`);
  if (at < 0) return null;
  const open = code.slice(at).match(/\bas\s*(\$[A-Za-z0-9_]*\$)/i);
  if (!open) return null;
  const from = at + open.index + open[0].length;
  return code.slice(at, code.indexOf(open[1], from) + open[1].length);
};

test('this file is the last MANIFEST line it is on, and it has no pending note', () => {
  assert.ok(manifest.includes(FILE), 'the file is not in MANIFEST.txt');
  assert.ok(!existsSync(join(ROOT, 'scripts/sql/pending/the_founders_rulings_of_10_november_settle_four_open_problems.txt')),
    'a file with a MANIFEST line cannot also be pending');
});

test('the file retires accountant.receipt_bank_match and unschedules its job', () => {
  assert.match(mine, /update public\.seat_duty\s+set enabled = false, own_job = false,[^;]*where duty = 'accountant\.receipt_bank_match'/,
    'the duty is not retired (enabled false, own_job false) by name');
  assert.match(mine, /for v_job in select jobid from cron\.job where jobname = 'seat_duty:accountant\.receipt_bank_match' loop\s+perform cron\.unschedule\(v_job\);/,
    'its pg_cron job is not unscheduled');
  assert.match(mine, /insert into public\.company_policy_decision[^;]*'no_bank_statement_reconciliation', date '2026-11-10', 'founder'/,
    'the ruling is not recorded in the decision register');
});

test('nothing after the retirement schedules the bank-statement duty again', () => {
  const retiredAt = statements.findLastIndex((s) => /update public\.seat_duty\s+set enabled = false/.test(s) && s.includes(`'${DUTY}'`));
  assert.ok(retiredAt >= 0, 'no statement retires the duty');
  const back = statements.slice(retiredAt + 1).filter((s) => (s.includes(`'${DUTY}'`) || s.includes(`'${JOB}'`)) && (
    /\benabled\s*=\s*(true|excluded\.enabled)\b/i.test(s)              // switched back on
    || /fn_seat_duty_isolate\(\s*'accountant\.receipt_bank_match'/.test(s)  // moved onto its own job
    || /cron\.schedule\(\s*'seat_duty:accountant\.receipt_bank_match'/.test(s)  // its job scheduled
    || (/insert into public\.seat_duty\b/i.test(s) && /\benabled\b/i.test(s) && /\btrue\b/i.test(s))));
  assert.deepEqual(back.map((s) => s.trim().slice(0, 160)), [],
    'a later statement schedules accountant.receipt_bank_match again; founder ruling 1559 retired it');
});

test('the bank duty holds its asks for a statement, and every bank_balance item, as waiting while the ruling stands', () => {
  const settle = lastDefinition('fn_accountant_duty_settle');
  assert.ok(settle, 'fn_accountant_duty_settle is not defined');
  assert.match(settle, /v_no_statement := p_duty in \('bank', 'bank_balance'\) and exists \(select 1 from public\.company_policy_decision d\s+where d\.decision_key = 'no_bank_statement_reconciliation'\);/,
    'the gate no longer reads the decision row');
  assert.match(settle, /if v_no_statement and \(p_duty = 'bank_balance'\s+or split_part\(x->>'item', ':', 1\) in \('statement', 'unreadable'\)\) then\s+v_waiting := v_waiting \|\|/,
    'the statement asks (statement:, unreadable:) or bank_balance are filed as findings again');
  // The ruling silences what ASKS for a statement, nothing else: payout facts and the IT loop's fixture key stay findings.
  assert.doesNotMatch(settle, /in \('statement', 'unreadable'[^)]*'missing'/, 'missing: is the IT loop probes\' fixture and asks nobody');
  // The receipts gate of ruling 585 is untouched.
  assert.match(settle, /v_receipts_wait := p_duty = 'expenses' and exists/);
});

test('the cash truth check sends no books-against-statement report while the ruling stands, and still fails on disagreement', () => {
  const cash = lastDefinition('fn_accountant_cash_truth_check');
  assert.ok(cash, 'fn_accountant_cash_truth_check is not defined');
  assert.match(cash, /if abs\(coalesce\(v_gap, 0\)\) > 1 and not exists \(select 1 from public\.company_policy_decision d\s+where d\.decision_key = 'no_bank_statement_reconciliation'\) then/,
    'the GL-against-statement report is not gated by ruling 1559');
  assert.match(cash, /raise exception 'the forecast cash \(%\) and the cash position \(%\) disagree by more than AED 1'/,
    'the forecast-against-position check was lost with the report');
});

test('a TEST-mode payment the accountant resolved stays resolved when the sweep reads it again', () => {
  const rec = lastDefinition('fn_accountant_reveal_reconcile_record');
  assert.ok(rec, 'fn_accountant_reveal_reconcile_record is not defined');
  assert.match(rec, /when excluded\.outcome = 'deferred' then null\s+when excluded\.outcome = 'test_mode_not_demo' and not excluded\.livemode then it\.resolved_at end;/,
    'the upsert resets a resolved test-mode payment again, so its finding reopens every hour (founder ruling 1558)');
  // The classifier contract is unchanged: a test payment whose quote is not provably demo is still filed once.
  assert.match(rec, /v_demo := case when x->>'outcome' = 'test_mode_not_demo' then public\.fn_is_demo_email\(x->>'customer_email'\)/);
});

test('every routine the file defines keeps SECURITY DEFINER, a pinned search_path and its revoke', () => {
  for (const [fn, sig] of [['fn_accountant_reveal_reconcile_record', '(bigint, jsonb)'], ['fn_accountant_duty_settle', '(text, jsonb)'],
    ['fn_accountant_cash_truth_check', '()']]) {
    assert.match(mine, new RegExp(`create or replace function public\\.${fn}\\([^)]*\\)\\s*returns jsonb language plpgsql security definer\\s*set search_path to 'public', 'pg_temp'`),
      fn + ' lost SECURITY DEFINER or its pinned search_path');
    assert.ok(mine.includes(`revoke execute on function public.${fn}${sig} from public, anon, authenticated;`), fn + ' has no revoke');
  }
  assert.ok(mine.includes('grant execute on function public.fn_accountant_reveal_reconcile_record(bigint, jsonb) to service_role;'),
    'the accountant runtime calls the record routine as service_role');
});

test('the file ends in a verdict row and never raises it, and commits no transaction of its own', () => {
  assert.doesNotMatch(mine, /^\s*(begin|commit|rollback)\s*;/im);
  assert.doesNotMatch(mine, /raise exception 'PROBE/i, 'the verdict must be a row: a raise would roll back the settlement');
  assert.match(mine, /select case when fx\.problems is null then 'PROBE OK' else 'PROBE FAILED: ' \|\| fx\.problems end as verdict/);
});
