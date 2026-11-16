// A CUSTOMER'S QUESTION ABOUT ONE QUOTE REACHES ONLY THAT SUPPLIER (sales_engineer, CUSTOMER_W2, 16 Nov 2026; holes/CUSTOMER.md
// item 6). Before: the customer could not ask a supplier anything before paying (clarify_ask was supplier-only), and the list
// showed every ANSWERED question to every matched supplier. FAILS IF: the customer door disappears; a customer question is shown
// to the supplier before the sales engineer relays it, or to another supplier at all; his own question gets the customer's
// answer box; the door stops asking the sales engineer to read it.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { clarifyVisible } from './clarify_visibility.ts';

const S1 = 11, S2 = 22;
const cq = (o: Record<string, unknown> = {}) => ({ kind: 'question', supplier_id: S1, asked_by: 'customer', relayed_at: null, answered_at: null, answer: null, ...o });

Deno.test('the customer always sees his own question', () => {
  assert(clarifyVisible(cq(), true, null));
  assert(clarifyVisible(cq({ relayed_at: '2026-11-16T10:00:00Z', answered_at: '2026-11-16T12:00:00Z', answer: 'Yes' }), true, null));
});

Deno.test('the quoted supplier sees it only once the sales engineer relayed it', () => {
  assert(!clarifyVisible(cq(), false, S1), 'shown before the relay');
  assert(clarifyVisible(cq({ relayed_at: '2026-11-16T10:00:00Z' }), false, S1));
});

Deno.test('another supplier never sees it, even answered', () => {
  assert(!clarifyVisible(cq({ relayed_at: '2026-11-16T10:00:00Z' }), false, S2));
  assert(!clarifyVisible(cq({ relayed_at: '2026-11-16T10:00:00Z', answered_at: '2026-11-16T12:00:00Z', answer: 'Scaffolding included' }), false, S2));
});

Deno.test("a supplier's question keeps its old rule: its asker, then every supplier once answered", () => {
  const sq = { kind: 'question', supplier_id: S1, asked_by: 'supplier', answered_at: null as string | null, answer: null as string | null };
  assert(clarifyVisible(sq, false, S1)); assert(!clarifyVisible(sq, false, S2));
  assert(clarifyVisible({ ...sq, answered_at: '2026-11-16T12:00:00Z', answer: '3 rooms' }, false, S2));
  assertEquals(clarifyVisible({ kind: 'note', supplier_id: null, answer: 'Two bedrooms' }, false, S2), true);
});

Deno.test('the doors: the customer asks one quote, the sales engineer reads it, the supplier replies, his own question gets no answer box', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assertMatch(src, /if \(action === 'clarify_ask_supplier'\) \{/);
  assertMatch(src, /asked_by: 'customer', quote_id: qid, source: 'portal'/);
  assertMatch(src, /admin\.rpc\('fn_sales_engineer_customer_question_file', \{ p_id: ins\.id \}\)/);
  assertMatch(src, /if \(action === 'clarify_reply'\) \{/);
  assertMatch(src, /row\.asked_by !== 'customer' \|\| Number\(row\.supplier_id\) !== Number\(supLead\.id\) \|\| !row\.relayed_at/);
  assertMatch(src, /if \(row\.asked_by === 'customer'\) return R\(400, \{ error: 'not_a_question' \}\);/);
  assertMatch(src, /clarifyVisible\(r, isOwner, supLead \? Number\(supLead\.id\) : null\)/);
});
