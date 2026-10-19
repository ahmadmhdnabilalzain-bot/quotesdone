// Legal finding 14: the accountant hands the CEO each VAT threshold crossing (300,000 warn; 375,000 mandatory, or the
// next pending reveal would cross it), once, from a daily accountant duty. Fails if the thresholds leave
// decision_policy, the sender or receiver changes, the duty loses its seat, or the probe stops returning a verdict.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../sql/the_accountant_tells_the_ceo_before_the_vat_threshold.sql', import.meta.url), 'utf8')
  .split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n');

test('thresholds live in decision_policy, not in the routines', () => {
  assert.match(sql, /'vat_watch_warn_aed', '300000'::jsonb/);
  assert.match(sql, /'vat_mandatory_threshold_aed', '375000'::jsonb/);
  const body = sql.slice(sql.indexOf('create or replace function'), sql.indexOf('insert into public.seat_handoff_kind'));
  assert.doesNotMatch(body, /\b(300000|375000)\b/);
});

test('one deduplicated handoff accountant -> ceo per level', () => {
  assert.match(sql, /fn_seat_handoff\('accountant', 'ceo', 'accountant\.vat_threshold', 'transactions',\s*v_level \|\| ':' \|\| to_char\(now\(\), 'YYYY'\)/);
  assert.match(sql, /\('accountant\.vat_threshold', 'accountant', 'ceo',/);
});

test('a pending reveal that would cross 375,000 is raised', () => {
  assert.match(sql, /fee_status = 'pending'/);
  assert.match(sql, /p_trailing_aed, 0\) \+ coalesce\(p_largest_pending_aed, 0\)/);
});

test('daily duty owned by the accountant; routines closed and pinned', () => {
  assert.match(sql, /\('accountant\.vat_threshold_watch', 'accountant', interval '1 day', 'fn_accountant_vat_threshold_watch'/);
  for (const sig of ['fn_accountant_vat_threshold_levels(numeric, numeric)', 'fn_accountant_vat_threshold_watch()', 'fn_ceo_takes_vat_threshold(bigint)'])
    assert.ok(sql.includes(`revoke execute on function public.${sig} from public, anon, authenticated`), sig);
  assert.equal((sql.match(/create or replace function/g) || []).length, (sql.match(/set search_path to 'public', 'pg_temp'/g) || []).length);
});

test('the file ends with a verdict row', () => {
  assert.match(sql.trimEnd(), /else 'PROBE OK' end as verdict;$/);
});
