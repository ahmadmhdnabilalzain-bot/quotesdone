// A supplier is e-mailed no scorecard for a month before he was approved, or for a month no request reached him (sales_engineer,
// 18 Nov 2026). Measured: all 3 October 2026 cards (supplier_scorecard, outcome 'queued') went to suppliers approved in November,
// among them Shine Carpets (leads 2936, approved 17 Nov 08:40 UTC, card e-mailed 18 Nov 02:00 UTC, notification 149942).
// Reads the routine as the pending file defines it; the rule itself is replayed below on those three cases.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SQL = readFileSync(new URL('../sql/a_supplier_is_sent_no_scorecard_for_a_month_before_he_was_approved_or_without_a_request.sql', import.meta.url), 'utf8');
const body = SQL.slice(SQL.indexOf('create or replace function public.fn_sales_engineer_supplier_scorecard_tick'));

test('the tick skips a month that ended before he was approved, and a month with no request, before anything is sent', () => {
  const skip = body.indexOf('v_skip := case when r.since >= (v_month + interval \'1 month\')::date');
  const send = body.indexOf('fn_customer_support_takes_delivery');
  assert.ok(skip > 0 && send > skip, 'the skip is decided before the delivery');
  assert.match(body, /coalesce\(l\.approved_at, l\.registration_submitted_at, l\.accepted_terms_at, l\.created_at\)/);
  assert.match(body, /\(v_card->'activity'->>'requests_sent'\)::int, 0\) = 0/);
  assert.match(body, /if v_skip is not null then\s+insert into public\.supplier_scorecard[^;]+v_skip\);\s+v_skipped := v_skipped \+ 1;\s+continue;/);
  assert.match(body, /revoke execute on function public\.fn_sales_engineer_supplier_scorecard_tick\(\) from public, anon, authenticated/);
});

// the same rule in JS, replayed on the measured October cards (Dubai dates)
const month = '2026-10-01', monthEnd = '2026-11-01';
const skipped = (since, requests) => since >= monthEnd ? 'approved after' : requests === 0 ? 'no request' : null;
test('replay: the three October 2026 cards, all to suppliers approved in November, are skipped; a supplier of October with a request is not', () => {
  // leads 2936, 19398, 158318 as measured 18 Nov 2026 (approved, Dubai date; requests_sent 0 on each card)
  for (const since of ['2026-11-17', '2026-11-11', '2026-11-12']) assert.equal(skipped(since, 0), 'approved after');
  assert.equal(skipped('2026-10-20', 0), 'no request');
  assert.equal(skipped('2026-09-01', 2), null);
  assert.ok(month < monthEnd);
});
