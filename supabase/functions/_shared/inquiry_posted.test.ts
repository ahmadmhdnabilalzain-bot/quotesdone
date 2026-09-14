// deno test supabase/functions/_shared/inquiry_posted.test.ts
// Every create_inquiry answer names the request the customer made, and which requests suppliers quote.
import { assertEquals } from 'jsr:@std/assert@1';
import { postedSingle, postedSplit } from './inquiry_posted.ts';

Deno.test('single and turnkey: the request is its own id and the thing quoted', () => {
  const s = postedSingle('a1', 'single', 3, { mode: 'router' });
  assertEquals([s.inquiry_id, s.parent_id, s.child_ids, s.quotable_ids, s.matches, s.split], ['a1', null, [], ['a1'], 3, false]);
  assertEquals(postedSingle('t1', 'turnkey', 0).scope_type, 'turnkey');
});

Deno.test('split: a stable parent id at the top, the children listed, matches summed', () => {
  const p = postedSplit('P', [
    { inquiry_id: 'c1', trade: 'aluminium', label: 'Aluminium', matches: 2 },
    { inquiry_id: 'c2', trade: 'glass', label: 'Glass', matches: 1 },
  ], ['aluminium', 'glass', 'steel'], ['steel']);
  assertEquals(p.inquiry_id, 'P');            // what the harness and the portal key on
  assertEquals(p.parent_id, 'P');
  assertEquals(p.child_ids, ['c1', 'c2']);
  assertEquals(p.quotable_ids, ['c1', 'c2']);  // a supplier quotes a child, never the 'split' parent
  assertEquals(p.matches, 3);
  assertEquals(p.failed_trades, ['steel']);
});
