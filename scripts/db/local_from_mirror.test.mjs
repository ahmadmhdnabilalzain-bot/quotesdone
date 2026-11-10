// The local-database builder's offline guarantees (no Docker needed). The Docker run itself is measured by
// `node scripts/db/local_from_mirror.mjs`, which fails on any missing object; this file pins the three text
// transformations that make the mirror replayable, so a regenerated mirror that changes shape is caught here.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';
import { replayableMirror, typeDefinitions, expectedObjects, buildSql } from './local_from_mirror.mjs';

const mirror = readSchemaMirror();

test('every routine the mirror defines is terminated, so psql cannot read the section as one statement', () => {
  const routines = (mirror.match(/^CREATE OR REPLACE (FUNCTION|PROCEDURE) /gm) || []).length;
  const { sql, terminated } = replayableMirror(mirror);
  assert.ok(routines > 1000, `the mirror defines ${routines} routines; expected the full export`);
  assert.equal(terminated, routines, 'one terminator per routine body');
  assert.equal((sql.match(/\$function\$;$/gm) || []).length, routines);
});

test('no cron job is scheduled active: every top-level cron.schedule goes through schedule_off', () => {
  const { sql, cron } = replayableMirror(mirror);
  assert.ok(cron > 0, 'the mirror schedules jobs');
  assert.equal((sql.match(/^select\s+cron\.schedule\(/gim) || []).length, 0);
  assert.match(buildSql().sql, /cron\.alter_job\(v, active := false\)/);
});

test('every enum type a table or routine names is defined before the mirror replays', () => {
  const used = new Set([...mirror.matchAll(/\b(answer_precedence|gate_state)\b/g)].map((m) => m[1]));
  const { names } = typeDefinitions();
  for (const t of used) assert.ok(names.includes(t), `${t} is used by the mirror but defined nowhere in the SQL history`);
});

test('the measurement has something to measure for every kind', () => {
  for (const [kind, set] of Object.entries(expectedObjects(mirror))) assert.ok(set.size > 0, `${kind}: 0 names parsed from the mirror`);
});
