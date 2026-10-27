// A REQUEST WITH NO QUOTE IN 24 HOURS IS WIDENED, AND NO SUPPLIER IS NUDGED TWICE A DAY (founder ruling 1209).
// Assigned: sales_engineer. Offline: reads the SQL file the release operator applies at merge. Fails when:
//   1. the reminder loses its 24-hour per-supplier guard (a supplier on three short requests got three reminders a day);
//   2. the widening stops being once, from fn_match_capability, recorded in routing.short_sweep;
//   3. the customer stops being told once at the deadline, or the reminder stops being once per request and supplier;
//   4. the aborted-transaction probe stops asserting one reminder across two requests.
//   node --test scripts/checks/a_request_with_no_quote_in_24_hours_is_widened_and_no_supplier_is_nudged_twice_a_day.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const NAME = 'a_request_with_no_quote_in_24_hours_is_widened_and_no_supplier_is_nudged_twice_a_day';
const SRC = readFileSync(join(REPO, `scripts/sql/${NAME}.sql`), 'utf8');
const PROBE = readFileSync(join(REPO, `scripts/sql/${NAME}_probe.sql`), 'utf8');
const code = (s) => s.split(/\r?\n/).map((l) => l.replace(/--.*$/, '')).join('\n');
const B = (() => {
  const m = code(SRC).match(/function public\.fn_rfq_short_of_quotes_tick\([\s\S]*?\$function\$([\s\S]*?)\$function\$/i);
  assert.ok(m, 'fn_rfq_short_of_quotes_tick is not defined');
  return m[1];
})();

test('a supplier reminded in the last 24 hours is not reminded again', () => {
  const loop = B.slice(B.indexOf('for l in select ld.* from public.inquiry_matches'), B.indexOf("'rfq_quote_reminder', 'supplier'"));
  assert.ok(loop.length > 0, 'the reminder loop moved');
  assert.match(loop, /not exists \(select 1 from public\.notifications n\s+where n\.lead_id = ld\.id and n\.type = 'rfq_quote_reminder'\s+and n\.created_at > now\(\) - interval '24 hours'/,
    'the reminder no longer skips a supplier nudged in the last 24 hours');
});

test('the widening, the one reminder per request and the customer notice are still there', () => {
  assert.match(B, /if not coalesce\(r\.routing \? 'short_sweep', false\) then/, 'the widening is no longer once');
  assert.match(B, /from public\.fn_match_capability\(v_codes, v_need/, 'the widening no longer uses the one matcher (exact trade)');
  assert.match(B, /fn_seat_clock_lead_is_fixture\(ld\) = r\.fixture/, 'demo and real may pair');
  assert.match(B, /'rfq_quote_reminder:' \|\| r\.id \|\| ':' \|\| l\.id/, 'the reminder is no longer once per request and supplier');
  assert.match(B, /if now\(\) >= r\.deadline then[\s\S]*'rfq_short_of_quotes:' \|\| r\.id/, 'the customer is no longer told once at the deadline');
});

test('the probe aborts its transaction and proves one reminder across two requests', () => {
  assert.match(PROBE, /raise exception 'CHK<<%>>'/);
  assert.ok(PROBE.includes('if r1 <> 1 then'), 'the probe no longer asserts one reminder across two requests');
  assert.ok(PROBE.includes('r1b <> r1'), 'the probe no longer asserts the second tick adds nothing');
  assert.doesNotMatch(code(PROBE), /'[^']*@(?!example\.invalid)[a-z][^']*'/i, 'the probe names a real address');
});
