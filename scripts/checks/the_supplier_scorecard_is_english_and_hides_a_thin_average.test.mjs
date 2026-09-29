// THE SUPPLIER SCORECARD IS ENGLISH, HIDES A TRADE AVERAGE OVER FEWER THAN THREE SUPPLIERS, AND SAYS SO WITH NO DATA.
// sales_engineer, 29 Sep 2026, founder_instruction 1013 item 2. Offline: reads the SQL file and the portal card.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * a trade average is computed without the three-supplier floor (a "trade average" over one competitor tells a
//     supplier that competitor's numbers);
//   * the card or its e-mail picks up a language other than English, or any Arabic letter (the founder: a supplier
//     is always written in English), or the portal card follows the page's Arabic;
//   * the e-mail leaves the one delivery door, or goes out without fn_email_sendable (suppression);
//   * "not enough data yet" disappears from the card, the e-mail or the portal;
//   * the tip stops being a rule (a model is called);
//   * a routine loses its pinned search_path or its revoke, the table loses RLS or its policy;
//   * the file carries both, or neither, of a pending note and a MANIFEST line.
//   node --test scripts/checks/the_supplier_scorecard_is_english_and_hides_a_thin_average.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const NAME = 'a_supplier_sees_its_monthly_scorecard_against_its_trade';
const SQL = readFileSync(join(REPO, 'scripts/sql', NAME + '.sql'), 'utf8');
const UI = readFileSync(join(REPO, 'src/components/portal/supplier/SupplierScorecard.tsx'), 'utf8');
const body = (fn) => {
  const i = SQL.indexOf(`function public.${fn}(`);
  assert.ok(i >= 0, `${fn} is not defined in the file`);
  return SQL.slice(i, SQL.indexOf('$fn$;', i));
};
const ARABIC = /[؀-ۿ]/;

test('every trade average needs three suppliers', () => {
  const b = body('fn_supplier_scorecard');
  for (const m of ['response_hours', 'win_rate', 'rating']) {
    assert.match(b, new RegExp(`case when count\\(s\\.${m}\\) >= 3 then`), `the ${m} average has no three-supplier floor`);
  }
});

test('English only, in the card, the e-mail and the portal', () => {
  assert.doesNotMatch(SQL, ARABIC, 'the scorecard file carries Arabic text');
  assert.doesNotMatch(UI, ARABIC, 'the portal card carries Arabic text');
  assert.match(body('fn_sales_engineer_supplier_scorecard_tick'), /'lang', 'en'/, 'the e-mail is not sent as English');
  assert.match(UI, /lang="en" dir="ltr"/, 'the portal card follows the page language');
  assert.doesNotMatch(UI, /lang === 'ar'|ar \?/, 'the portal card switches on the page language');
});

test('one door, suppression respected, once a month', () => {
  const b = body('fn_sales_engineer_supplier_scorecard_tick');
  assert.match(b, /fn_email_sendable\(/, 'the scorecard is sent without the suppression check');
  assert.match(b, /fn_customer_support_takes_delivery\(/, 'the scorecard leaves the one delivery door');
  assert.doesNotMatch(b, /insert into public\.notifications/, 'the scorecard writes a notification directly');
  assert.match(b, /not exists \(select 1 from public\.supplier_scorecard s where s\.lead_id = l\.id and s\.month = v_month\)/, 'a supplier can be sent a month twice');
  assert.match(b, /qd\.duty_fixtures/, 'the tick lost the fixture guard');
});

test('"not enough data yet" everywhere; the tip is a rule', () => {
  assert.match(body('fn_supplier_scorecard'), /'not enough data yet'/);
  assert.match(body('fn_supplier_scorecard_text'), /not enough data yet/);
  assert.match(UI, /Not enough data yet/);
  assert.doesNotMatch(SQL, /fn_seat_duty_reason|fn_reason_hold|ai_gateway|think\(/, 'the scorecard calls a model');
});

test('routines pinned and revoked, the table closed, one of pending note or MANIFEST line', () => {
  for (const [, fn] of SQL.matchAll(/create or replace function public\.(\w+)\(/g)) {
    const i = SQL.indexOf(`function public.${fn}(`);
    const head = SQL.slice(i, SQL.indexOf(' as $fn$', i) + 8);
    assert.match(head, /set search_path to 'public', 'pg_temp'/, `${fn} has no pinned search_path`);
    assert.match(SQL, new RegExp(`revoke execute on function public\\.${fn}\\(`), `${fn} is not revoked`);
  }
  assert.match(SQL, /alter table public\.supplier_scorecard enable row level security/);
  assert.match(SQL, /create policy supplier_scorecard_service_role_only on public\.supplier_scorecard[\s\S]{0,80}using \(false\) with check \(false\)/);
  assert.match(SQL, /revoke all on public\.supplier_scorecard from anon, authenticated/);
  const pending = existsSync(join(REPO, 'scripts/sql/pending', NAME + '.txt'));
  const listed = readFileSync(join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8').includes(`scripts/sql/${NAME}.sql`);
  assert.ok(pending !== listed, 'exactly one of a pending note and a MANIFEST line');
});
