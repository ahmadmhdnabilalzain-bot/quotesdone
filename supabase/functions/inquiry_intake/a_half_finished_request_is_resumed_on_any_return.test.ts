// A HALF-FINISHED REQUEST IS RESUMED ON ANY RETURN (sales_engineer, CUSTOMER_W2, 16 Nov 2026; holes/CUSTOMER.md item 7).
// Before: the draft id lived only in the browser, so a reload or his phone opened a blank chat and he was asked everything again.
// FAILS IF: an open draft is not found by his address; a closed, empty or month-old draft is resumed; the newest is not the one
// chosen; the conversation shown carries internal turns; the intake stops looking for it when no draft id is sent, or looks
// for it when he asked for a fresh request; the request screen stops asking for it.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { isOpenDraft, newestOpenDraft, transcriptOf } from './resume.ts';

const NOW = Date.parse('2026-11-16T12:00:00Z');
const said = [{ role: 'user', text: 'Paint my villa' }, { role: 'assistant', text: 'Which emirate?' }];
const row = (o: Record<string, unknown>) => ({ id: 'x', status: 'needs_info', updated_at: '2026-11-15T12:00:00Z', turns: said, ...o });

Deno.test('an open draft is one still collecting or complete-but-unsent, that he spoke in, inside 30 days', () => {
  assert(isOpenDraft(row({}), NOW));
  assert(isOpenDraft(row({ status: 'ready' }), NOW));
  for (const st of ['consumed', 'expired', 'held', 'rejected']) assert(!isOpenDraft(row({ status: st }), NOW), st);
  assert(!isOpenDraft(row({ turns: [{ role: 'assistant', text: 'Hi' }] }), NOW), 'nothing of his');
  assert(!isOpenDraft(row({ updated_at: '2026-10-16T11:00:00Z' }), NOW), 'older than 30 days');
});

Deno.test('the newest open draft is the one resumed', () => {
  const a = row({ id: 'a', updated_at: '2026-11-14T12:00:00Z' }), b = row({ id: 'b', updated_at: '2026-11-16T09:00:00Z' }), c = row({ id: 'c', status: 'consumed', updated_at: '2026-11-16T11:00:00Z' });
  assertEquals(newestOpenDraft([a, c, b], NOW)?.id, 'b');
  assertEquals(newestOpenDraft([c], NOW), null);
});

Deno.test('the conversation shown is his words and the replies, nothing internal', () => {
  assertEquals(transcriptOf([...said, { role: 'system', text: 'slots' }, { role: 'assistant', text: '' }]), said);
});

Deno.test('the intake resumes by his address and the request screen asks for it', async () => {
  const h = await Deno.readTextFile(new URL('./handle.ts', import.meta.url));
  assertMatch(h, /if \(b && b\.resume === true && !String\(b\.text \|\| ''\)\.trim\(\)\) \{/);
  assertMatch(h, /\(!b\.fresh && b\.carry_from !== 'portal'\) \? openDrafts\(\)\.then/);
  const ui = await Deno.readTextFile(new URL('../../../src/components/me/NewRequest.tsx', import.meta.url));
  assertMatch(ui, /call\('inquiry_intake', \{ resume: true, lang \}, token\)/);
  assertMatch(ui, /!intakeId && freshRef\.current \? \{ fresh: true \} : \{\}/);
});

Deno.test('the nudges at 24 and 72 hours are the duty in SQL, once per pause, never to a demo address from the real duty', async () => {
  const sql = await Deno.readTextFile(new URL('../../../scripts/sql/an_unfinished_request_chat_is_kept_and_he_is_nudged_at_a_day_and_three_days.sql', import.meta.url));
  assertMatch(sql, /'sales_engineer\.unfinished_requests', 'sales_engineer', interval '1 hour'/);
  assertMatch(sql, /continue when x\.demo is distinct from v_fx;/);
  assertMatch(sql, /x\.nudged_24h_at >= x\.touched/);
});
