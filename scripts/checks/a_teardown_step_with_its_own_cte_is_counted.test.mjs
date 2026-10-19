// Teardown counts each delete as `with d as (<step> returning 1) select count(*) from d`. A step that
// carries its own data-modifying CTE (the leads step, which deletes inbound_messages in the same statement)
// cannot be nested that way: Postgres answers 0A000 and the teardown stops at 'leads' (19 Oct 2026).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { countedDelete } from '../lib/demo_factory.mjs';

test('a plain delete is wrapped as before', () => {
  assert.equal(countedDelete('delete from public.quotes where id in (1)'), 'with d as (delete from public.quotes where id in (1) returning 1) select count(*)::int n from d');
});
test("a step's own CTE is lifted to the top level, never nested", () => {
  const s = countedDelete('with im as (delete from public.inbound_messages where lead_id in (select 1)) delete from public.leads where id in (select 1)');
  assert.equal(s, 'with im as (delete from public.inbound_messages where lead_id in (select 1)), d as (delete from public.leads where id in (select 1) returning 1) select count(*)::int n from d');
  assert.doesNotMatch(s, /\(with /i);
});
