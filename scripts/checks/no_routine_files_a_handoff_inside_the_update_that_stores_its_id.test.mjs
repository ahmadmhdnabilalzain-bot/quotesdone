// No routine files a seat handoff INSIDE the UPDATE that stores the handoff's id (12 Oct 2026, it_engineer).
// fn_marketing_reviews_tick did, and filing the handoff writes back to the very row the UPDATE is changing, so
// every run failed with SQLSTATE 27000 "tuple to be updated was already modified by an operation triggered by
// the current command" (336 failures). The id is taken into a variable first, then stored by its own statement.
// Reads the live mirror (supabase/schema/full_schema), which is kept equal to production on every PR.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

test('no UPDATE assigns a column from fn_seat_handoff(...) in the same statement', () => {
  const src = readSchemaMirror();
  const bad = [...src.matchAll(/update\s+public\.(\w+)\s+set\s+\w+\s*=\s*public\.fn_seat_handoff\(/gi)].map((m) => m[1]);
  assert.deepEqual(bad, [], 'a handoff is filed inside the UPDATE that stores its id');
});
