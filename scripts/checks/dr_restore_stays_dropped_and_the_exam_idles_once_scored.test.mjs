// DR_RESTORE STAYS DROPPED, AND THE KNOWLEDGE EXAM IDLES ONCE THE DAY IS SCORED (it_engineer, 5 Oct 2026).
//
// 1. scripts/sql/the_dr_restore_staging_table_leaves_the_database.sql drops public.dr_restore (0 rows, no reader).
//    Fails if any file applied after it creates the table again, or the export registry still lists it.
// 2. fn_it_engineer_knowledge_recall_exam runs every 30 minutes all day. Measured 4-5 Oct 2026: once a day's 2,354
//    questions are aggregated it returns {"done": true} and scores nothing (8 days of answers, exactly 2,354 a day; one
//    aggregation per day; an aborted-transaction probe with a ZZ DEMO aggregate row: tick 2 scored 0). That idle rests on
//    ONE guard - the "day already aggregated" return - sitting before the slice insert. Fails if the canonical body
//    (the schema mirror, equal to production) loses that guard or moves it after the insert.
//
//   node --test scripts/checks/dr_restore_stays_dropped_and_the_exam_idles_once_scored.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { manifestWithPending } from '../lib/pending_sql.mjs';
import { readRegistry } from '../lib/table_export_registry.mjs';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const DROP_FILE = 'scripts/sql/the_dr_restore_staging_table_leaves_the_database.sql';
const strip = (s) => s.replace(/--[^\n]*/g, '');

export const recreates = (sql) => /create\s+table\s+(?:if\s+not\s+exists\s+)?public\.dr_restore\b/i.test(strip(sql));

// The exam body idles after completion iff the aggregated-day return comes before the slice insert.
export function idlesOnceScored(body) {
  const b = strip(body);
  const guard = b.search(/if\s+exists\s*\(\s*select\s+1\s+from\s+public\.seat_knowledge_recall\s+where\s+day\s*=\s*v_day\s*\)\s*then\s*return/i);
  const insert = b.search(/insert\s+into\s+public\.seat_knowledge_recall_answer/i);
  return guard >= 0 && insert > guard;
}

test('self-test', () => {
  assert.ok(recreates('create table if not exists public.dr_restore (id bigint);'));
  assert.ok(!recreates('-- create table public.dr_restore ('));
  assert.ok(!recreates('drop table if exists public.dr_restore;'));
  const ok = 'if exists (select 1 from public.seat_knowledge_recall where day = v_day) then return x; end if; insert into public.seat_knowledge_recall_answer';
  assert.ok(idlesOnceScored(ok));
  assert.ok(!idlesOnceScored('insert into public.seat_knowledge_recall_answer ...; if exists (select 1 from public.seat_knowledge_recall where day = v_day) then return x;'));
  assert.ok(!idlesOnceScored('insert into public.seat_knowledge_recall_answer ...'));
});

test('no file applied after the drop creates dr_restore again, and the registry no longer lists it', () => {
  const order = manifestWithPending(REPO);
  const at = order.indexOf(DROP_FILE);
  assert.ok(at >= 0, `${DROP_FILE} is in neither MANIFEST.txt nor a pending note`);
  const back = order.slice(at + 1).filter((f) => existsSync(join(REPO, f)) && recreates(readFileSync(join(REPO, f), 'utf8')));
  assert.deepEqual(back, []);
  assert.ok(!readRegistry(REPO).has('dr_restore'), 'table_export_registry still lists dr_restore');
});

test('the knowledge exam returns before scoring once the day is aggregated (production body, via the mirror)', () => {
  const m = readSchemaMirror();
  const start = m.indexOf('CREATE OR REPLACE FUNCTION public.fn_it_engineer_knowledge_recall_exam()');
  assert.ok(start >= 0, 'fn_it_engineer_knowledge_recall_exam is not in the schema mirror');
  const end = m.indexOf('$function$', m.indexOf('$function$', start) + 10);
  assert.ok(idlesOnceScored(m.slice(start, end > 0 ? end : start + 20000)),
    'the exam lost its "day already aggregated" return, or scores before it: it would re-score after completion');
});
