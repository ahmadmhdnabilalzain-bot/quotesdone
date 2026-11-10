// A RECEIPT IS MATCHED TO THE BANK DEBIT THAT PAID IT (T6, accountant seat, 4 Oct 2026).
//
// prevented by: scripts/sql/the_accountant_matches_every_expense_receipt_to_its_bank_line.sql
//
// Replays that file against production with ZZ DEMO receipts and zz_demo statement lines, runs
// fn_accountant_receipt_bank_match, and asserts: a USD receipt pairs with the debit carrying its
// vendor word over a nearer debit of the same amount; a receipt outside tolerance or with no debit is
// listed unmatched; a debit with no receipt is listed unmatched and a bank charge is not; a second
// run matches nothing new. The DO block ALWAYS raises (PROBE OK or PROBE FAILED), so the whole
// statement, the DDL included, rolls back and production is never written.
//
//   node --test scripts/checks/a_receipt_is_matched_to_the_bank_debit_that_paid_it.test.mjs
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { replaySql } from '../lib/safe_replay.mjs';

const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
const FILE = 'scripts/sql/the_accountant_matches_every_expense_receipt_to_its_bank_line.sql';

const PROBE = `
do $probe$
declare r jsonb; r2 jsonb; r3 jsonb; l1 bigint; l2 bigint; l3 bigint; l4 bigint; l5 bigint; l6 bigint; l7 bigint; l8 bigint; l9 bigint; e1 bigint; e2 bigint; e3 bigint; e4 bigint; e5 bigint; e6 bigint; e7 bigint; m record; bad text := '';
begin
  insert into public.bank_statement_intake (source_ref, account, state) values ('zz_demo_t6', 'zz_demo', 'parsed');
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash) values
    ('zz_demo', 'zz_demo_t6', date '2025-12-30', 'ZZ DEMO OPENING', 1000, 'zz_demo_t6_0'),
    ('zz_demo', 'zz_demo_t6', date '2026-01-20', 'ZZ DEMO CLOSING', -10, 'zz_demo_t6_5');
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
    values ('zz_demo', 'zz_demo_t6', date '2026-01-03', 'ZZ DEMO CARD VERCEL INC', -73.45, 'zz_demo_t6_1') returning id into l1;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
    values ('zz_demo', 'zz_demo_t6', date '2026-01-02', 'ZZ DEMO CARD OTHER', -73.45, 'zz_demo_t6_2') returning id into l2;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
    values ('zz_demo', 'zz_demo_t6', date '2026-01-04', 'ZZ DEMO CARD UNKNOWN', -500, 'zz_demo_t6_3') returning id into l3;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
    values ('zz_demo', 'zz_demo_t6', date '2026-01-04', 'ZZ DEMO FEE', -199, 'zz_demo_t6_4', 'bank_charge') returning id into l4;
  insert into public.expense_entries (vendor, amount, currency, charged_on, source)
    values ('ZZ DEMO Vercel', 20, 'USD', date '2026-01-01', 'receipt') returning id into e1;
  insert into public.expense_entries (vendor, amount, currency, charged_on, source)
    values ('ZZ DEMO Missing', 100, 'AED', date '2026-01-05', 'receipt') returning id into e2;
  insert into public.expense_entries (vendor, amount, currency, charged_on, source)
    values ('ZZ DEMO Pricey', 600, 'AED', date '2026-01-03', 'receipt') returning id into e3;

  r := public.fn_accountant_receipt_bank_match();
  select * into m from public.expense_bank_match where expense_entry_id = e1;
  if m.bank_line_id is distinct from l1 or not m.vendor_in_text then bad := bad || 'the USD receipt did not pair with the debit carrying its vendor word; '; end if;
  if exists (select 1 from public.expense_bank_match where expense_entry_id in (e2, e3)) then bad := bad || 'a receipt with no debit in tolerance was matched; '; end if;
  if not (r->'receipts_unmatched' @> jsonb_build_array(jsonb_build_object('expense_entry', e2))
      and r->'receipts_unmatched' @> jsonb_build_array(jsonb_build_object('expense_entry', e3))) then bad := bad || 'an unmatched receipt is not listed; '; end if;
  if not (r->'bank_debits_unmatched' @> jsonb_build_array(jsonb_build_object('line', l2))
      and r->'bank_debits_unmatched' @> jsonb_build_array(jsonb_build_object('line', l3))) then bad := bad || 'an unmatched debit is not listed; '; end if;
  if r->'bank_debits_unmatched' @> jsonb_build_array(jsonb_build_object('line', l4)) then bad := bad || 'a bank charge is listed as needing a receipt; '; end if;
  -- Review of #1178: ambiguity is listed, never booked; order never steals a later receipt's debit.
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
    values ('zz_demo', 'zz_demo_t6', date '2026-02-02', 'ZZ DEMO CARD ACME ONE', -50, 'zz_demo_t6_6') returning id into l5;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
    values ('zz_demo', 'zz_demo_t6', date '2026-02-03', 'ZZ DEMO CARD ACME TWO', -50, 'zz_demo_t6_7') returning id into l6;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
    values ('zz_demo', 'zz_demo_t6', date '2026-03-02', 'ZZ DEMO CARD XYZ', -70, 'zz_demo_t6_8') returning id into l7;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
    values ('zz_demo', 'zz_demo_t6', date '2026-03-31', 'ZZ DEMO CARD DELTA A', -80, 'zz_demo_t6_9') returning id into l8;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
    values ('zz_demo', 'zz_demo_t6', date '2026-04-01', 'ZZ DEMO CARD DELTA B', -80, 'zz_demo_t6_10') returning id into l9;
  insert into public.expense_entries (vendor, amount, currency, charged_on, source)
    values ('ZZ DEMO Acme', 50, 'AED', date '2026-02-01', 'receipt') returning id into e4;
  insert into public.expense_entries (vendor, amount, currency, charged_on, source)
    values ('ZZ DEMO Zeta', 70, 'AED', date '2026-03-01', 'receipt') returning id into e5;
  -- e6 (1 Apr) fits l8 and l9 and is nearer l9; e7 (2 Apr) fits only l9. A greedy pass gave l9 to e6.
  insert into public.expense_entries (vendor, amount, currency, charged_on, source)
    values ('ZZ DEMO Delta', 80, 'AED', date '2026-04-01', 'receipt') returning id into e6;
  insert into public.expense_entries (vendor, amount, currency, charged_on, source)
    values ('ZZ DEMO Delta', 80, 'AED', date '2026-04-02', 'receipt') returning id into e7;
  r3 := public.fn_accountant_receipt_bank_match();
  if exists (select 1 from public.expense_bank_match where expense_entry_id in (e4, e5) or bank_line_id in (l5, l6, l7))
    then bad := bad || 'an ambiguous receipt was booked; '; end if;
  if not r3->'ambiguous' @> jsonb_build_array(jsonb_build_object('expense_entry', e4, 'reason', 'several_debits'))
    then bad := bad || 'two vendor-word debits for one receipt are not listed several_debits; '; end if;
  if not r3->'ambiguous' @> jsonb_build_array(jsonb_build_object('expense_entry', e5, 'reason', 'no_vendor_word'))
    then bad := bad || 'a debit with no vendor word is not listed no_vendor_word; '; end if;
  if not exists (select 1 from public.expense_bank_match where expense_entry_id = e6 and bank_line_id = l8)
     or not exists (select 1 from public.expense_bank_match where expense_entry_id = e7 and bank_line_id = l9)
    then bad := bad || 'the earlier receipt took the debit the later receipt needed; '; end if;

  r2 := public.fn_accountant_receipt_bank_match();
  if (r2->>'matched_now')::int <> 0 then bad := bad || 'a second run matched again; '; end if;
  -- Founder ruling 1559 (10 Nov 2026): the duty is RETIRED while company_policy_decision no_bank_statement_reconciliation
  -- stands (the_founders_rulings_of_10_november_settle_four_open_problems.sql); the routine stays and is proved above.
  if not exists (select 1 from public.seat_duty where duty = 'accountant.receipt_bank_match'
                   and routine = 'fn_accountant_receipt_bank_match'
                   and enabled = not exists (select 1 from public.company_policy_decision
                                              where decision_key = 'no_bank_statement_reconciliation')) then
    bad := bad || 'the seat_duty row is missing, or enabled against ruling 1559; '; end if;
  if has_function_privilege('anon', 'public.fn_accountant_receipt_bank_match()', 'execute') then bad := bad || 'anon can execute the routine; '; end if;
  if bad <> '' then raise exception 'PROBE FAILED: %', bad; end if;
  raise exception 'PROBE OK';
end $probe$;`;

test('receipts pair with their bank debits and the unmatched are listed (rolled back)', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  let text = 'the probe returned without raising, so it did not roll back';
  try { await replaySql(readFileSync(FILE, 'utf8') + '\n' + PROBE, { label: 'the receipt-match probe', retry: false }); }
  catch (e) { text = String(e.message); }
  assert.match(text, /PROBE OK/, text);
});

test('the file never commits its own transaction', () => {
  const sql = readFileSync(FILE, 'utf8').replace(/--.*$/gm, '');
  assert.doesNotMatch(sql, /^\s*(begin|commit)\s*;/im);
});
