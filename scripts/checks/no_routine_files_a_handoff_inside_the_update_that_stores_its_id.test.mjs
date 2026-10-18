// No routine files a seat handoff INSIDE the UPDATE that stores the handoff's id (12 Oct 2026, it_engineer).
// fn_marketing_reviews_tick did, and filing the handoff writes back to the very row the UPDATE is changing, so
// every run failed with SQLSTATE 27000 "tuple to be updated was already modified by an operation triggered by
// the current command" (336 failures). The id is taken into a variable first, then stored by its own statement.
// Reads the live mirror (supabase/schema/full_schema), which is kept equal to production on every PR. A routine
// whose replacement is committed but not yet applied (scripts/sql/<name>.sql with a scripts/sql/pending note) is
// judged by that file instead, so the check is green on the PR and stays honest once the apply lands.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const SHAPE = /update\s+public\.(\w+)\s+set\s+\w+\s*=\s*public\.fn_seat_handoff\(/gi;
const routineAt = (src, i) => [...src.slice(0, i).matchAll(/function\s+public\.(\w+)\s*\(/gi)].pop()?.[1] ?? '?';

test('no UPDATE assigns a column from fn_seat_handoff(...) in the same statement', () => {
  const pendingSql = readdirSync('scripts/sql/pending').filter((f) => f.endsWith('.txt'))
    .map((f) => 'scripts/sql/' + f.replace(/\.txt$/, '.sql')).filter(existsSync)
    .map((f) => readFileSync(f, 'utf8'));
  const replacedByPending = (name) => pendingSql.find((s) => s.toLowerCase().includes('function public.' + name.toLowerCase() + '('));
  const bad = [];
  const mirror = readSchemaMirror();
  for (const m of mirror.matchAll(SHAPE)) {
    const name = routineAt(mirror, m.index);
    const pending = replacedByPending(name);
    if (pending ? [...pending.matchAll(SHAPE)].length : true) bad.push(name);
  }
  assert.deepEqual(bad, [], 'a handoff is filed inside the UPDATE that stores its id');
});
