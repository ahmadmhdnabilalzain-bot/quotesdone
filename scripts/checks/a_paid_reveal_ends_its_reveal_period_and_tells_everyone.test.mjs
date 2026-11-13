// A PAID REVEAL ENDS ITS REVEAL PERIOD ON THE QUOTATIONS' VALIDITY AND TELLS EVERYONE ON IT (sales_engineer, 13 Nov 2026;
// founder_instruction 1685/1688; revised after review "WORKFLOW W2 SALES 1", decisions A, B, C).
// Guards scripts/sql/a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql and the quotation fixes beside it. The
// behaviour is proved by that file's _probe.sql (rehearsed on production, rolled back; five mutants each caught) and by
// scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs GAP 8-10 on a rehearsal; this fails when the shape
// that makes it true is taken away.
//   node --test scripts/checks/a_paid_reveal_ends_its_reveal_period_and_tells_everyone.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const SQL = read('scripts/sql/a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql');
const fn = (name) => {
  const at = SQL.search(new RegExp(`create or replace function public\\.${name}\\(`, 'i'));
  assert.ok(at >= 0, `${name} is defined`);
  const tag = SQL.slice(at).match(/as (\$\w*\$)/i)[1];
  const body = SQL.indexOf(tag, at) + tag.length;
  return SQL.slice(at, SQL.indexOf(tag, body));
};

test('a paid request keeps status revealed: the closure is its outcome, stage and record, never status closed (decision A)', () => {
  assert.doesNotMatch(SQL, /set status = 'closed'/i);
  const r = fn('fn_sales_engineer_records_reveal');
  assert.match(r, /outcome = coalesce\(outcome, 'revealed'\)/, 'never overwrites a hire');
  assert.match(r, /pipeline_stage = case when pipeline_stage = 'won' then pipeline_stage else 'revealed' end/);
  assert.match(r, /insert into public\.request_reveal_outcome/);
});

test('the reveal period is the quotations\' validity, per request, capped at 30 days; the duty ends it on the request\'s date (decision B)', () => {
  const u = fn('fn_sales_engineer_reveal_period_until');
  assert.match(u, /least\(p_cap, coalesce\(max\(coalesce\(q\.expires_at/);
  assert.match(u, /quote_quality_hold h where h\.quote_id = q\.id and h\.released_at is null/, 'a quotation in the quality hold counts as live');
  assert.match(fn('fn_sales_engineer_records_reveal'), /v_first \+ interval '30 days'/);
  assert.match(fn('fn_sales_engineer_reveal_period_tick'), /where i\.reveal_open_until <= now\(\)/);
  assert.match(SQL, /create trigger z33_a_quote_moves_its_requests_reveal_period after update of status, expires_at on public\.quotes/);
  const g = read('supabase/functions/_shared/reveal_guard.ts');
  assert.match(g, /if \(!already && inq\.reveal_open_until && Date\.parse\(String\(inq\.reveal_open_until\)\) <= Date\.now\(\)\) return refuse\('reveal_period_ended'\)/);
});

test('no model is asked at this step: nothing in it needs judgement (decision C)', () => {
  assert.doesNotMatch(SQL, /fn_reason_hold\(|fn_seat_duty_reason\(|fn_reason_apply_sales_engineer__reveal_paid/);
});

test('from the first paid reveal the request takes no new quotations, at the database and at submit', () => {
  assert.match(fn('trg_a_paid_request_takes_no_new_quotations'), /raise exception 'REQUEST_REVEALED/);
  assert.match(SQL, /create trigger a05_a_paid_request_takes_no_new_quotations before insert on public\.quotes/);
  const q = read('supabase/functions/supplier_api/actions/quotes.ts');
  assert.match(q, /if \(!mine\) return J\(REQUEST_REVEALED, 409\)/);
  assert.match(q, /if \(error && isRequestRevealed\(error\)\) return J\(REQUEST_REVEALED, 409\)/, 'a payment racing the insert gets the same 409');
});

test('the other suppliers: once per event, English, no customer text, no name, no price, and true words', () => {
  const t = fn('fn_sales_engineer_tells_unchosen_suppliers');
  for (const leak of [/i\.summary/, /raw_input/, /full_name/, /company_name/, /quote_amount/, /price_ex_vat/, /total_charged/]) assert.doesNotMatch(t, leak);
  assert.doesNotMatch(t, /[؀-ۿ]/, 'suppliers are written in English (ruling 1008)');
  assert.match(t, /'\. Your quotation remains available to the customer while it is valid\. Nothing is needed from you now\.'/);
  assert.doesNotMatch(t, / until '/, 'no date in a supplier notice (coordinator ruling): the date moves and the supplier is never told again');
  assert.match(t, /case when i\.hired_supplier_id is not null and i\.hired_supplier_id <> l\.id then ' The customer went ahead with another supplier\.' else '' end/,
    '"went ahead" only when a hire of another supplier is recorded');
  assert.match(t, /n\.dedupe_key = v_key/);
});

test('a refund re-opens only a recorded period with a live quotation left; reveals before this file are untouched', () => {
  const r = fn('fn_sales_engineer_reopens_after_refund');
  assert.match(r, /no reveal period was recorded for this reveal/);
  assert.match(r, /fn_sales_engineer_live_quotes_left\(i\.id\) = 0/);
  assert.match(r, /tells_unchosen_suppliers\(i\.id, 'reopened', v_until\)/);
});

test('the receipt routine is the live body with only the request steps and the window sentence added; messages first', () => {
  const h = fn('fn_sales_engineer_acts_on_handoff');
  const paid = h.slice(h.indexOf("if t = 'reveal.paid' then"), h.indexOf("elsif t = 'payment.failed'"));
  assert.ok(paid.indexOf("fn_sales_engineer_writes('reveal_receipt'") < paid.indexOf('fn_sales_engineer_records_reveal(p_id)'));
  assert.ok(paid.indexOf("fn_sales_engineer_writes('quote_accepted'") < paid.indexOf('fn_sales_engineer_records_reveal(p_id)'));
  assert.match(paid, /exception when others then[\s\S]*fn_sales_engineer_request_step_failed\(p_id, 'reveal\.paid', sqlerrm\)/, 'a failure is a finding, and never un-sends the receipt');
  assert.match(h, /fn_sales_engineer_request_step_failed\(p_id, 'refund\.paid', sqlerrm\)/);
  assert.match(fn('fn_sales_engineer_request_step_failed'), /fn_it_engineer_finding_upsert\('reveal_request_step:' \|\| p_id/);
  assert.match(h, /then 'You can still open another of the quotations you received on this request while they remain valid\.'/, 'the refund message follows the re-open');
  assert.match(paid, /refund_window_sentence_en/);
  assert.doesNotMatch(SQL, /update public\.seat_handoff_kind/, 'the registered handler is unchanged');
});

test('every routine the file creates is revoked and pins its search_path; the table has RLS and a policy', () => {
  const made = [...SQL.matchAll(/create or replace function public\.(\w+)\(/gi)].map((m) => m[1]);
  assert.ok(made.length >= 10);
  for (const n of made) {
    assert.match(SQL, new RegExp(`revoke execute on function public\\.${n}\\(`), `${n} is revoked`);
    assert.match(fn(n), /set search_path to 'public', 'pg_temp'/i, `${n} pins search_path`);
  }
  assert.match(SQL, /alter table public\.request_reveal_outcome enable row level security/);
  assert.match(SQL, /create policy request_reveal_outcome_service_role_only/);
});

test('a held VAT basis stores no fee base; zero-rated and exempt are storable; a non-AED typed total is refused', () => {
  const sp = read('supabase/functions/_shared/stated_price.ts');
  assert.match(sp, /quote_amount: sp\.fee_base, price_ex_vat/);
  assert.match(SQL, /alter table public\.quotes alter column quote_amount drop not null/);
  assert.match(SQL, /'exclusive', 'inclusive', 'not_registered', 'zero_rated', 'exempt', 'not_stated', 'confirmed_on_portal'/);
  assert.match(read('supabase/functions/_shared/line_specs/workflow.ts'), /answers\.vat === 'inclusive' \? Math\.round\(\(total \/ 1\.05\) \* 100\) \/ 100 : total/);
  assert.match(read('supabase/functions/supplier_api/actions/quotes.ts'), /code: 'currency_not_aed' \}, 400\)/);
  assert.match(read('src/components/portal/supplier/money.ts'), /as stated, waiting for your VAT answer/, 'the supplier never reads "AED 0" for his own held quote');
});
