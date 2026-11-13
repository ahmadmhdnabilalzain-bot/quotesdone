// A PAID REVEAL CLOSES THE REQUEST AND EVERYONE ON IT IS TOLD (sales_engineer, 13 Nov 2026; founder_instruction 1685/1688).
// Guards scripts/sql/a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql and the quotation weak points it fixes
// with it. The behaviour is proved by that file's _probe.sql (rehearsed on production, rolled back) and by
// scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs GAP 8-10 on a rehearsal; this fails when the shape
// that makes it true is taken away: the handler registration, the tell at the payment, the follow-up rows, the model's
// question and its strict apply, the anonymity of the notices, and "no fee base on a held VAT basis".
//   node --test scripts/checks/a_paid_reveal_closes_the_request.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const SQL = read('scripts/sql/a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql');
const fn = (name) => {
  const at = SQL.indexOf(`create or replace function public.${name}(`);
  assert.ok(at >= 0, `${name} is defined`);
  return SQL.slice(at, SQL.indexOf('end $fn$;', at));
};

test('reveal.paid and refund.paid reach the sales engineer through the wrapper that still sends the old messages first', () => {
  assert.match(SQL, /update public\.seat_handoff_kind\s+set handler = 'fn_sales_engineer_acts_on_money_handoff'[\s\S]*type in \('reveal\.paid', 'refund\.paid'\)/);
  const w = fn('fn_sales_engineer_acts_on_money_handoff');
  assert.ok(w.indexOf('fn_sales_engineer_acts_on_handoff(p_id)') < w.indexOf('fn_sales_engineer_closes_on_reveal(p_id)'), 'messages first, then the request');
  assert.match(w, /exception when others then/, 'a failure on the request never un-sends the receipt');
  assert.doesNotMatch(SQL, /create or replace function public\.fn_sales_engineer_acts_on_handoff\(/, 'this file never redefines the receipt routine (agent W1 owns it)');
});

test('at the payment: the request records the sale, the unchosen suppliers are told, the follow-up is owned, the model is asked', () => {
  const c = fn('fn_sales_engineer_closes_on_reveal');
  assert.match(c, /outcome = coalesce\(outcome, 'revealed'\)/, 'never overwrites a hire');
  assert.match(c, /pipeline_stage = case when pipeline_stage = 'won' then pipeline_stage else 'revealed' end/);
  assert.match(c, /fn_sales_engineer_tells_unchosen_suppliers\(i\.id, 'reveal_open', v_until\)/);
  assert.match(c, /'connect_check', 'sales_engineer'[\s\S]*'hire_check', 'customer_support'/);
  assert.match(c, /fn_reason_hold\('sales_engineer', 'sales_engineer\.reveal_paid'/);
  assert.match(c, /'lean', true, 'easy', true/, 'one lean decide call on the seat\'s easy route');
});

test('the model\'s answer is applied only when it is one of the options', () => {
  const a = fn('fn_reason_apply_sales_engineer__reveal_paid');
  assert.match(a, /raise exception 'CHOICE_NOT_AN_OPTION/);
  assert.match(a, /v_choice not in \('close_now', 'keep_open'\)/);
});

test('a notice to an unchosen supplier carries no customer text, no name and no price', () => {
  const t = fn('fn_sales_engineer_tells_unchosen_suppliers');
  for (const leak of [/i\.summary/, /raw_input/, /full_name/, /company_name/, /quote_amount/, /price_ex_vat/, /total_charged/]) assert.doesNotMatch(t, leak);
  assert.match(t, /'lang', 'en'/, 'suppliers are written in English');
  assert.match(t, /dedupe_key', v_key/, 'one message per supplier per event');
});

test('every routine the file creates is revoked and pins its search_path', () => {
  const made = [...SQL.matchAll(/create or replace function public\.(\w+)\(([^)]*)\)/g)].map((m) => m[1]);
  assert.ok(made.length >= 8);
  for (const n of made) {
    assert.match(SQL, new RegExp(`revoke execute on function public\\.${n}\\(`), `${n} is revoked`);
    assert.match(fn(n), /set search_path to 'public', 'pg_temp'/, `${n} pins search_path`);
  }
  for (const t of ['request_reveal_outcome', 'reveal_followup']) {
    assert.match(SQL, new RegExp(`alter table public\\.${t} enable row level security`));
    assert.match(SQL, new RegExp(`create policy ${t}_service_role_only`));
  }
});

test('a quotation held for its VAT basis stores no fee base, and no page computes a fee from its gross total', () => {
  const sp = read('supabase/functions/_shared/stated_price.ts');
  assert.match(sp, /quote_amount: sp\.fee_base, price_ex_vat/);
  assert.match(sp, /vat_treatment === 'not_stated' \|\| q\.vat_treatment === 'inclusive'\)\) return null/);
  assert.match(SQL, /alter table public\.quotes alter column quote_amount drop not null/);
  const wf = read('supabase/functions/_shared/line_specs/workflow.ts');
  assert.match(wf, /answers\.vat === 'inclusive' \? Math\.round\(\(total \/ 1\.05\) \* 100\) \/ 100 : total/, '"including 5% VAT" settles the price');
  assert.match(read('supabase/functions/supplier_api/actions/quotes.ts'), /code: 'currency_not_aed' \}, 400\)/, 'a non-AED typed total is refused');
});
