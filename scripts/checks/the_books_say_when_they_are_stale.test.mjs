// THE BOOKS SAY WHEN THEY ARE STALE, AND WHY (accountant, 23 Sep 2026).
// The readiness audit found the last journal on 15 Sep and read it as posting having stopped. Nothing had
// failed: nothing had been forwarded. The ledger was silent either way, so the two could not be told apart.
// Duty 12 (fn_accountant_books_duty) runs after the costs duty posts and raises one finding naming the cause.
// This fails if the duty is unwired from the hourly run, loses its stage, or stops naming a cause.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../sql/the_accountant_runs_its_duties_every_hour.sql', import.meta.url), 'utf8');
const books = src.slice(src.indexOf('function public.fn_accountant_books_duty('), src.indexOf('function public.fn_accountant_duties(p_r jsonb)'));
// 16 Nov 2026: the chain moved out of the one hourly statement into its own hourly seat duty, accountant.books_chain
// (the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql); the order is the same.
const chainSrc = readFileSync(new URL('../sql/the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql', import.meta.url), 'utf8');
const chain = chainSrc.slice(chainSrc.indexOf('function public.fn_accountant_books_chain_duty('), chainSrc.indexOf('function public.fn_accountant_ceo_reports_duty('));

test('the hourly duties run the books duty after costs has posted, as its own stage', () => {
  const iCosts = chain.indexOf("public.fn_accountant_cost_booking_tick()");
  const iBooks = chain.indexOf("public.fn_accountant_books_duty()");
  assert.ok(iCosts > 0 && iBooks > iCosts, 'books must run after costs (which calls fn_gl_sync_business)');
  assert.match(chain, /'costs', 'owner_card', 'books'\]/, "the 'books' stage is not in the stage list, so a raise would go unreported");
  assert.match(chainSrc, /\('accountant\.books_chain',[^)]*'1 hour', true, 'fn_accountant_books_chain_duty'/, 'the chain is not an hourly seat duty');
});

test('the books duty names each cause and reads its threshold from gl_settings', () => {
  assert.match(books, /books_stale_after_days/);
  assert.match(books, /posting is failing/);
  assert.match(books, /neither booked nor held as a statement/);
  assert.match(books, /nothing has reached the expenses mailbox/);
  assert.match(books, /fn_accountant_duty_settle\('books'/);
  assert.match(src, /revoke execute on function public\.fn_accountant_books_duty\(date\) from public, anon, authenticated/);
});
