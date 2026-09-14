// HANDOFF KINDS ARE DATA; THE ROUTINES THAT READ THEM HAVE ONE OWNER.
//
// Four builds redefined fn_seat_handoff_types and fn_seat_handoff_act on 14 Sep 2026, and whichever
// applied last deleted the others' rows and branches. The conversations are now rows of
// public.seat_handoff_kind (type, from, to, meaning, handler, reply window, who closes), which each build
// INSERTs; scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql is the one file that defines the
// routines. This fails when:
//   1. a file listed in MANIFEST after that file defines fn_seat_handoff_types, fn_seat_handoff_act or
//      fn_seat_handoff (a second owner, the thing that kept reverting everyone);
//   2. (production) a kind names a handler routine that does not exist;
//   3. (production) fn_seat_handoff_types() is not exactly the table.
//
//   node --test scripts/checks/handoff_kinds_are_data.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OWNER = 'scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql';
const ROUTINES = /create\s+or\s+replace\s+function\s+public\.(fn_seat_handoff_types|fn_seat_handoff_act|fn_seat_handoff)\s*\(/gi;

test('no file after the owner redefines the handoff routines', () => {
  const order = readFileSync(join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).filter((l) => l.endsWith('.sql'));
  const at = order.indexOf(OWNER);
  assert.ok(at >= 0, `${OWNER} is not in MANIFEST`);
  const offenders = order.slice(at + 1).flatMap((f) => {
    const p = join(REPO, f);
    if (!existsSync(p)) return [];
    return [...readFileSync(p, 'utf8').matchAll(ROUTINES)].map((m) => `${f}: ${m[1]}`);
  });
  assert.deepEqual(offenders, [], 'add a row to public.seat_handoff_kind instead of redefining the routine');
  const own = [...readFileSync(join(REPO, OWNER), 'utf8').matchAll(ROUTINES)].map((m) => m[1].toLowerCase());
  assert.ok(own.includes('fn_seat_handoff_types') && own.includes('fn_seat_handoff_act'), 'the owner file must define both routines');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('every kind names a handler that exists, and fn_seat_handoff_types is the table', { skip: SKIP }, async () => {
  const missing = await sql(`select type, from_seat, to_seat, handler from public.seat_handoff_kind
                              where to_regprocedure('public.' || handler || '(bigint)') is null`);
  assert.deepEqual(missing, []);
  const [d] = await sql(`select (select count(*) from (select type, from_seat, to_seat, meaning from public.fn_seat_handoff_types()
                                  except select type, from_seat, to_seat, meaning from public.seat_handoff_kind) a)
                              + (select count(*) from (select type, from_seat, to_seat, meaning from public.seat_handoff_kind
                                  except select type, from_seat, to_seat, meaning from public.fn_seat_handoff_types()) b) n`);
  assert.equal(Number(d.n), 0);
});
