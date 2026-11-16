// THE BOOKS HOLD A COST ON THE FOUNDER'S WORD AND TELL THE CEO WHAT A REQUEST COSTS (accountant, 15 Nov 2026).
// Fails if a cause of these comes back:
//   1. a Mashreq fee booked on the founder's word is booked again when the statement arrives (fn_accountant_book_bank_charges
//      stops attaching first, or the month-booked reading stops counting an attached line);
//   2. a receipt for a held cost books a second expense (fn_expense_post_to_gl stops calling the merge, in either file
//      that defines it);
//   3. test spend (an e2e_run_tag row) is counted as the cost of a request again;
//   4. runway and the 13-week forecast stop reading founder funding; founder money is booked as a loan;
//   5. a July Mashreq fee is booked although the August statement opens at 0.00;
//   review of 15 Nov 2026 (SP/show/REVIEW_books.md), each also a probe row that failed before:
//   6. a statement line can attach only within 7 days (late Mashreq fee booked twice); a line that may be a held fee
//      at another amount is posted instead of raised;
//   7. a receipt closes a fee waiting for its bank statement; a document for such a fee is posted;
//   8. the vendor match is a LIKE again; a held cost's VAT reaches 1150; a statement-held cost in USD is accepted;
//   9. runway or the forecast assume founder funding with no commitment recorded, or say covered without one;
//  10. conversation calls, or calls in a month with no real request, count as the cost of a request;
//  11. a cost already stopped counts as a saving;
//  12. a folded receipt's evidence is filed against the deleted row (receipts.ts, the accountant's sweep).
// Source checks; the routines run on a local Postgres 16 with their probes.
//   node --test scripts/checks/the_books_hold_a_cost_on_the_founders_word_and_tell_the_ceo_what_a_request_costs.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const code = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
const read = (p) => code(readFileSync(join(REPO, 'scripts/sql', p), 'utf8'));
const HELD = read('the_books_hold_a_cost_on_the_founders_word_until_its_document_arrives.sql');
const ECON = read('the_books_tell_the_ceo_what_a_request_costs_and_how_long_the_money_lasts.sql');
const body = (sql, name) => {
  const i = sql.search(new RegExp('create or replace function public\\.' + name + '\\(', 'i'));
  assert.ok(i >= 0, name + ' is defined');
  const rest = sql.slice(i);
  const end = rest.search(/\$(fn|function)\$;/);
  return rest.slice(0, end);
};

test('a statement line is attached to a held fee before any bank_charge journal is booked', () => {
  const b = body(HELD, 'fn_accountant_book_bank_charges');
  assert.ok(b.indexOf('fn_accountant_attach_statement_line(l.id)') > 0, 'the attach step is gone');
  assert.ok(b.indexOf('fn_accountant_attach_statement_line(l.id)') < b.indexOf("perform public.fn_gl_entry(l.value_date, v_memo, 'bank_charge'"), 'attach must come first');
  assert.match(b, /not exists \(select 1 from public\.expense_bank_match m where m\.bank_line_id = b\.id\)/);
  assert.match(body(HELD, 'fn_accountant_statement_booked'), /x\.src = 'bank_charge' and exists \(select 1 from public\.expense_bank_match m where m\.bank_line_id = b\.id\)/);
});

test('every definition of fn_expense_post_to_gl folds a document into its held entry first', () => {
  for (const f of ['the_books_hold_a_cost_on_the_founders_word_until_its_document_arrives.sql', 'the_company_recovers_no_input_vat_so_1150_is_moved_into_cost.sql']) {
    const b = body(read(f), 'fn_expense_post_to_gl');
    assert.ok(b.indexOf('fn_expense_held_document_merge(e.id)') > 0, f + ': the merge call is gone');
    assert.ok(b.indexOf('fn_expense_held_document_merge(e.id)') < b.indexOf("where g.source='expense' and g.source_ref = e.id::text"), f + ': the merge must run before the already-posted return');
  }
});

test('a cost on the founder\'s word names his ledger entry, is a founder statement, and is refused when a document books it', () => {
  const b = body(HELD, 'fn_accountant_expense_on_founder_word');
  assert.match(b, /from public\.founder_instruction where id = p_founder_instruction_id/);
  assert.match(b, /'founder_reported', 'founder_statement'/);
  assert.match(b, /'refused', 'already_booked'/);
  assert.match(b, /'refused', 'statement_shows_it'/);
  assert.match(b, /if p_dry_run then/);
});

test('the Mashreq data file books 1 Nov only, never a July fee', () => {
  const d = read('the_mashreq_fee_of_1_november_2026_is_booked_on_the_founders_word.sql');
  assert.equal((d.match(/fn_accountant_expense_on_founder_word\('Mashreq', date '2026-11-01'/g) || []).length, 2);
  assert.doesNotMatch(d, /date '2026-07-/, 'a July fee is booked although the August statement opens at 0.00');
});

test('test spend never reaches the cost per request', () => {
  const b = body(ECON, 'fn_accountant_request_economics');
  assert.match(b, /case when a\.e2e_run_tag is not null then 'test' else coalesce\(d\.driver, 'fixed'\) end drv/);
  assert.match(b, /v_ai_tied := case when v_req > 0 then v_ai_req else 0 end;/, 'calls are counted per request without a real request');
  assert.match(b, /v_or_fixed_share := case when \(v_ai_total - v_ai_test\) > 0 then round\(1 - v_ai_tied \/ \(v_ai_total - v_ai_test\), 4\) else 1 end;/);
  assert.match(b, /'requests_per_month', v_be_req/);
  assert.match(b, /'cost_cuts', v_cuts/);
  assert.match(b, /'already_stopped', v_stopped/);
  assert.doesNotMatch(b, /'stop_' \|\| s\.key/, 'a stopped cost is a saving again');
  for (const fn of ['site_assistant', 'wa_inbound', 'sales_engineer']) {
    assert.match(ECON, new RegExp("\\('model_fn', '" + fn + "',\\s+'fixed',\\s+'conversation'"), fn + ' is counted per request');
  }
});

test('a late statement line attaches to the oldest held fee; an ambiguous one is raised, not posted', () => {
  const a = body(HELD, 'fn_accountant_attach_statement_line');
  assert.match(a, /and e\.charged_on <= l\.value_date \+ 7/);
  assert.doesNotMatch(a, /abs\(e\.charged_on - l\.value_date\) <= 7/, 'the 7-day upper limit is back');
  assert.match(a, /order by e\.charged_on, e\.id/);
  const b = body(HELD, 'fn_accountant_book_bank_charges');
  assert.match(b, /'held_fee_ambiguous:line:' \|\| l\.id/);
  assert.ok(b.indexOf("'held_fee_ambiguous:line:'") < b.indexOf("perform public.fn_gl_entry(l.value_date, v_memo, 'bank_charge'"), 'the ambiguity check must come before posting');
});

test('a receipt folds only into an entry waiting for a receipt; a statement-held fee\'s document is held out', () => {
  const m = body(HELD, 'fn_expense_held_document_merge');
  assert.match(m, /fn_expense_held_entry_for\(d\.id, 'receipt', true\)/);
  assert.match(m, /a\.awaits = 'receipt'/);
  assert.doesNotMatch(m, / like /i, 'a LIKE vendor match is back');
  for (const f of ['the_books_hold_a_cost_on_the_founders_word_until_its_document_arrives.sql', 'the_company_recovers_no_input_vat_so_1150_is_moved_into_cost.sql']) {
    assert.match(body(read(f), 'fn_expense_post_to_gl'), /if public\.fn_expense_document_waits_for_statement\(e\.id\) then return null; end if;/, f);
  }
});

test('the action refuses a USD statement cost, matches vendors without LIKE, and keeps VAT out of 1150', () => {
  const b = body(HELD, 'fn_accountant_expense_on_founder_word');
  assert.match(b, /p_awaits = 'bank_statement' and v_cur <> 'AED'/);
  assert.doesNotMatch(b, / like /i, 'a LIKE vendor match is back');
  assert.match(b, /abs\(x\.aed - v_aed\) <= greatest\(0\.10 \* greatest\(x\.aed, v_aed\), 0\.01\)/);
  assert.match(body(HELD, 'fn_expense_same_vendor'), /length\(a\) >= 3 and length\(b\) >= 3/);
  assert.match(body(HELD, 'fn_expense_post_to_gl'), /where x\.expense_entry_id = e\.id\) then vat_aed := 0;/);
});

test('a folded receipt files its evidence against the surviving row, read back by its message key', () => {
  for (const p of ['supabase/functions/resend_inbound/steps/receipts.ts', 'supabase/functions/accountant/actions/expenses.ts']) {
    const t = readFileSync(join(REPO, p), 'utf8');
    const post = t.indexOf("admin.rpc('fn_expense_post_to_gl'");
    const reread = t.indexOf('survivingEntryId(admin, entryId, msgKey)', post);
    const file = t.indexOf("from('doc_backups').insert(", post);
    assert.ok(post > 0 && reread > post && file > reread, p + ': doc_backups is filed before the survivor is re-read');
    assert.doesNotMatch(t.slice(file, file + 600), /entity_id: String\(entryId\)/, p + ': filed against the inserted id');
  }
  assert.match(HELD, /fn_expense_held_entry_for\(new\.id, 'receipt', true\)/, 'the insert trigger emits for a row the merge deletes');
});

test('runway and the 13-week forecast count only a recorded commitment, and founder money is capital, not a loan', () => {
  for (const name of ['fn_accountant_cash_13_weeks', 'fn_accountant_runway_figures']) {
    const b = body(ECON, name);
    assert.match(b, /v_fund := case when v_committed then \(v_ff->>'committed_aed_per_month'\)::numeric else 0 end;/, name + ': funding without a commitment');
    assert.doesNotMatch(b, /coalesce\(\(v_ff->>'committed_aed_per_month'\)::numeric, v_spend\)/, name + ': assumes he funds the spend');
    assert.match(b, /not committed/, name + ': does not say the funding is not committed');
  }
  assert.match(body(ECON, 'fn_accountant_runway_figures'), /'runway_months_with_founder_funding', v_run_f/);
  assert.match(body(ECON, 'fn_accountant_runway_figures'), /'runway_months_cash_only', v_run_cash/);
  const f = body(ECON, 'fn_accountant_founder_funding');
  assert.match(f, /l\.account_code = '3000'/);
  assert.doesNotMatch(f, /'loan'/);
  assert.match(ECON, /'accountant\.request_economics', 'accountant', interval '1 day', 'fn_accountant_request_economics_tick'/);
});
