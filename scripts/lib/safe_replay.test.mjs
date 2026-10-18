// safe_replay.mjs reads SQL the way Postgres does (offline; no database). The live proof that a
// begin; create function; commit; file leaves production unchanged is in
// scripts/checks/every_sql_replay_goes_through_safe_replay.test.mjs.
import test from 'node:test';
import assert from 'node:assert/strict';
import { sanitizeReplay, createdObjects } from './safe_replay.mjs';

test('the file\'s own transaction wrapper is blanked, its body is kept, offsets are kept', () => {
  const t = 'BEGIN;\ncreate function public.zz_demo_x() returns int language sql as $$ select 1 $$;\nCOMMIT;\n';
  const out = sanitizeReplay(t);
  assert.equal(out.length, t.length);
  assert.doesNotMatch(out, /\b(begin|commit)\b/i);
  assert.match(out, /create function public\.zz_demo_x\(\)/);
  for (const w of ['start transaction;', 'begin work;', 'end;', 'commit work;', 'begin isolation level serializable;']) {
    assert.equal(sanitizeReplay(w).trim(), ';', w);
  }
});

test('commit and begin inside bodies, strings and comments are code Postgres never sees as control', () => {
  const t = [
    "create procedure public.zz_demo_p() language plpgsql as $body$ begin commit; end $body$;",
    "do $$ begin perform 1; end $$;",
    "select 'commit;' as s, E'rollback;\\' x' as e, \"commit;\" from t;",
    '-- commit;',
    '/* rollback; /* nested commit; */ */ select 1;',
  ].join('\n');
  assert.equal(sanitizeReplay(t), t);
});

test('what would end, split or escape the one rolled-back transaction is refused', () => {
  for (const bad of ['rollback;', 'abort;', 'savepoint a;', 'release savepoint a;', 'release a;',
    'set transaction isolation level serializable;', 'set session characteristics as transaction read write;',
    "prepare transaction 'x';", "commit prepared 'x';", 'create index concurrently i on t(a);',
    'vacuum t;', "alter system set work_mem = '1MB';", "alter type e add value 'x';", 'create database zz;',
    'create function f() returns int language sql begin atomic select 1; end;']) {
    assert.throws(() => sanitizeReplay('select 1;\n' + bad), /SAFE REPLAY REFUSED/, bad);
  }
});

test('the objects a text creates are named for the before/after fingerprint', () => {
  const o = createdObjects('create or replace function zz_demo_a(int) returns int ...; create table if not exists public.zz_t (a int);'
    + " -- create function public.not_this()\nselect 'create table nope (a int)';");
  assert.deepEqual(o, { routines: ['public.zz_demo_a'], relations: ['public.zz_t'] });
});
