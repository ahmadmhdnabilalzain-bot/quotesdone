// A REQUEST IS REVISED UNTIL IT IS REVEALED (sales_engineer, CUSTOMER_W2, 16 Nov 2026; scratchpad holes/CUSTOMER.md item 5).
// Before: fn_edit_inquiry refused every edit an hour after posting, the portal hid its Edit button after 60 minutes, and the
// date the work is needed by was editable nowhere although repeat.ts told the customer to edit it. A change sent later was only
// a note: the record kept the old budget and date and no quote said which version it priced.
// FAILS IF THE CAUSE RETURNS: a date-only edit is refused as "nothing editable"; a past or impossible date is accepted; the
// portal's `editable` goes back to a clock; fn_edit_inquiry gets its one-hour refusal back or stops making a revision.
import { assertEquals, assert, assertMatch } from 'jsr:@std/assert@1';
import { editDecision, dubaiToday } from './lib/edit_summary.ts';

const owner = { resolved: false };
const TODAY = '2026-11-16';

Deno.test('a date-only edit is accepted as the date the work is needed by', () => {
  const d = editDecision({ required_by: '2026-12-01' }, { summary: 'Paint two rooms' }, owner, TODAY);
  assert(d.ok, JSON.stringify(d));
  if (d.ok) assertEquals(d.patch, { required_by: '2026-12-01' });
});

Deno.test('a past date and an impossible date are refused in both languages', () => {
  for (const [v, code] of [['2026-11-15', 'date_in_past'], ['2026-02-30', 'date_invalid'], ['next Friday', 'date_invalid']]) {
    const d = editDecision({ required_by: v }, { summary: '' }, owner, TODAY);
    assert(!d.ok, v);
    if (!d.ok) { assertEquals(d.body.code, code, v); assert(String(d.body.message_ar || '').length > 0); }
  }
});

Deno.test('budget, emirate and date together; an empty date is no change', () => {
  const d = editDecision({ budget: 'AED 30,000', emirate: 'sharjah', required_by: '' }, { summary: '' }, owner, TODAY);
  assert(d.ok);
  if (d.ok) assertEquals(d.patch, { budget: 'AED 30,000', emirate: 'Sharjah' });
});

Deno.test("today's date in Dubai rolls over at 20:00 UTC", () => {
  assertEquals(dubaiToday(new Date('2026-11-16T19:59:00Z')), '2026-11-16');
  assertEquals(dubaiToday(new Date('2026-11-16T20:01:00Z')), '2026-11-17');
});

Deno.test('the portal button follows the database rule: no clock, editable until revealed, paid or closed', async () => {
  const src = await Deno.readTextFile(new URL('./actions/inquiry_lifecycle.ts', import.meta.url));
  assert(!/EDIT_WINDOW_MS/.test(src), 'the edit window is back in my_inquiries');
  assertMatch(src, /editable: \['open', 'sent', 'quoted'\]\.includes\(String\(i\.status\)\) && !paidInq\.has\(String\(i\.id\)\)/);
  assertMatch(src, /priced_revision: q\.priced_revision \?\? 1, priced_older: /);
});

Deno.test('fn_edit_inquiry has no one-hour refusal, edits the date and records every change as a revision', async () => {
  const sql = await Deno.readTextFile(new URL('../../../scripts/sql/a_change_to_a_sent_request_is_a_revision_every_quote_names_and_every_supplier_is_told.sql', import.meta.url));
  const body = sql.slice(sql.indexOf('create or replace function public.fn_edit_inquiry'), sql.indexOf('revoke execute on function public.fn_edit_inquiry'));
  assert(body.length > 1000);
  assert(!/interval '1 hour'/.test(body), 'the one-hour clock is back');
  assertMatch(body, /required_by = coalesce\(v_req, required_by\)/);
  assertMatch(body, /revision  = v_rev/);
  assertMatch(body, /insert into inquiry_revision/);
});
